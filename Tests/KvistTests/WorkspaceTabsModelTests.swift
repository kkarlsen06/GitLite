import Combine
import Foundation
import XCTest
@testable import Kvist

@MainActor
final class WorkspaceTabsModelTests: XCTestCase {
    func testNewTabsUseIndependentRepositoryModelsAndCanBeClosed() {
        let defaults = isolatedDefaults()
        let tabsModel = WorkspaceTabsModel(
            defaults: defaults,
            restoreSavedTabs: false
        )
        let firstTab = tabsModel.activeTab

        tabsModel.addTab()

        XCTAssertEqual(tabsModel.tabs.count, 2)
        XCTAssertNotEqual(tabsModel.activeTabID, firstTab.id)
        XCTAssertFalse(tabsModel.activeModel === firstTab.model)
        XCTAssertNil(tabsModel.activeModel.repositoryURL)

        tabsModel.close(tabsModel.activeTabID)

        XCTAssertEqual(tabsModel.tabs.count, 1)
        XCTAssertEqual(tabsModel.activeTabID, firstTab.id)
    }

    func testEditingAfterDocumentIsDirtyDoesNotInvalidateWorkspaceChrome() {
        let tabsModel = WorkspaceTabsModel(
            defaults: isolatedDefaults(),
            restoreSavedTabs: false
        )
        var workspaceChanges = 0
        let subscription = tabsModel.objectWillChange.sink {
            workspaceChanges += 1
        }

        tabsModel.activeModel.repositoryFileText = "first edit"
        XCTAssertGreaterThan(workspaceChanges, 0)

        workspaceChanges = 0
        tabsModel.activeModel.repositoryFileText = "second edit"

        XCTAssertEqual(workspaceChanges, 0)
        withExtendedLifetime(subscription) {}
    }

    func testTypingCommitMessageDoesNotInvalidateWorkspaceChrome() {
        let tabsModel = WorkspaceTabsModel(
            defaults: isolatedDefaults(),
            restoreSavedTabs: false
        )
        var workspaceChanges = 0
        let subscription = tabsModel.objectWillChange.sink {
            workspaceChanges += 1
        }

        tabsModel.activeModel.commitMessage = "Update version"

        XCTAssertEqual(workspaceChanges, 0)
        XCTAssertEqual(tabsModel.activeModel.commitMessage, "Update version")
        withExtendedLifetime(subscription) {}
    }

    func testTracksUnsavedFileChangesAcrossTabs() async throws {
        let repositoryURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try GitClient.initializeRepository(
            at: repositoryURL,
            createGitIgnore: false
        )
        try "saved\n".write(
            to: repositoryURL.appendingPathComponent("Version.txt"),
            atomically: true,
            encoding: .utf8
        )
        let tabsModel = WorkspaceTabsModel(
            defaults: isolatedDefaults(),
            restoreSavedTabs: false
        )
        await tabsModel.activeModel.openRepository(repositoryURL)
        tabsModel.activeModel.setWorkspaceMode(.fileEditor)
        tabsModel.activeModel.openRepositoryFile("Version.txt")
        let deadline = Date().addingTimeInterval(3)
        while tabsModel.activeModel.isDetailLoading, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(tabsModel.hasUnsavedRepositoryFileChanges)

        tabsModel.activeModel.repositoryFileText = "unsaved"

        XCTAssertTrue(tabsModel.hasUnsavedRepositoryFileChanges)
    }

    func testRestoresWorkspaceModeExpandedFoldersCommitTextAndDraft() async throws {
        let defaults = isolatedDefaults()
        let repositoryURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try GitClient.initializeRepository(at: repositoryURL, createGitIgnore: false)
        let sourceDirectory = repositoryURL.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try "saved\n".write(
            to: sourceDirectory.appendingPathComponent("State.txt"),
            atomically: true,
            encoding: .utf8
        )

        let original = WorkspaceTabsModel(
            defaults: defaults,
            restoreSavedTabs: false
        )
        await original.activeModel.openRepository(repositoryURL)
        original.activeModel.setWorkspaceMode(.fileEditor)
        original.activeModel.toggleFileDirectory("Sources")
        original.activeModel.openRepositoryFile("Sources/State.txt")
        await waitForEditor(in: original.activeModel)
        original.activeModel.repositoryFileText = "recovered draft\n"
        original.activeModel.commitMessage = "Keep this commit message"
        original.prepareForTermination()

        let restored = WorkspaceTabsModel(defaults: defaults)
        await waitForRepository(repositoryURL, in: restored.activeModel)
        let deadline = Date().addingTimeInterval(3)
        while restored.activeModel.selectedRepositoryFilePath != "Sources/State.txt",
              Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(restored.activeModel.workspaceMode, .fileEditor)
        XCTAssertTrue(restored.activeModel.expandedFileDirectories.contains("Sources"))
        XCTAssertEqual(restored.activeModel.selectedRepositoryFilePath, "Sources/State.txt")
        XCTAssertEqual(restored.activeModel.repositoryFileText, "recovered draft\n")
        XCTAssertTrue(restored.activeModel.repositoryFileDirty)
        XCTAssertEqual(restored.activeModel.commitMessage, "Keep this commit message")
    }

    func testClosingTheOnlyTabLeavesAnEmptyReplacementTab() {
        let defaults = isolatedDefaults()
        let tabsModel = WorkspaceTabsModel(
            defaults: defaults,
            restoreSavedTabs: false
        )
        let originalTabID = tabsModel.activeTabID

        tabsModel.close(originalTabID)

        XCTAssertEqual(tabsModel.tabs.count, 1)
        XCTAssertNotEqual(tabsModel.activeTabID, originalTabID)
        XCTAssertNil(tabsModel.activeModel.repositoryURL)
    }

    func testClosingLastRepositoryClearsLegacyRestorePath() throws {
        let defaults = isolatedDefaults()
        let repositoryURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        defaults.set([repositoryURL.path], forKey: "openRepositoryPaths")
        defaults.set(repositoryURL.path, forKey: "activeRepositoryPath")
        defaults.set(repositoryURL.path, forKey: "lastRepositoryPath")
        let tabsModel = WorkspaceTabsModel(defaults: defaults)

        tabsModel.close(tabsModel.activeTabID)

        XCTAssertEqual(defaults.stringArray(forKey: "openRepositoryPaths"), [])
        XCTAssertNil(defaults.string(forKey: "activeRepositoryPath"))
        XCTAssertNil(defaults.string(forKey: "lastRepositoryPath"))

        let restoredModel = WorkspaceTabsModel(defaults: defaults)
        XCTAssertEqual(restoredModel.tabs.count, 1)
        XCTAssertNil(restoredModel.activeModel.repositoryURL)
    }

    func testRestoresAllSavedDirectoriesAndTheSelectedTab() throws {
        let defaults = isolatedDefaults()
        let firstURL = try temporaryDirectory()
        let secondURL = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        defaults.set(
            [firstURL.path, secondURL.path],
            forKey: "openRepositoryPaths"
        )
        defaults.set(secondURL.path, forKey: "activeRepositoryPath")

        let tabsModel = WorkspaceTabsModel(defaults: defaults)

        XCTAssertEqual(tabsModel.tabs.count, 2)
        XCTAssertEqual(tabsModel.activeTabID, tabsModel.tabs[1].id)
        XCTAssertEqual(
            defaults.stringArray(forKey: "openRepositoryPaths"),
            [firstURL.path, secondURL.path]
        )
    }

    func testRestoredInactiveTabLoadsOnlyWhenSelected() async throws {
        let defaults = isolatedDefaults()
        let firstURL = try temporaryDirectory()
        let secondURL = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        try GitClient.initializeRepository(at: firstURL, createGitIgnore: false)
        try GitClient.initializeRepository(at: secondURL, createGitIgnore: false)
        defaults.set(
            [firstURL.path, secondURL.path],
            forKey: "openRepositoryPaths"
        )
        defaults.set(secondURL.path, forKey: "activeRepositoryPath")

        let tabsModel = WorkspaceTabsModel(defaults: defaults)
        let firstTab = tabsModel.tabs[0]
        let secondTab = tabsModel.tabs[1]

        XCTAssertNil(firstTab.loadedModel)
        XCTAssertTrue(firstTab.isRepositoryLoadPending)
        XCTAssertTrue(secondTab.isRepositoryLoadPending)
        await waitForRepository(secondURL, in: secondTab.model)
        XCTAssertEqual(
            secondTab.model.repositoryURL?.resolvingSymlinksInPath(),
            secondURL.resolvingSymlinksInPath()
        )
        await waitForRepositoryLoad(in: secondTab)
        XCTAssertFalse(secondTab.isRepositoryLoadPending)
        XCTAssertEqual(firstTab.displayName, firstURL.lastPathComponent)

        tabsModel.select(firstTab.id)
        XCTAssertTrue(firstTab.isRepositoryLoadPending)
        await waitForRepository(firstURL, in: firstTab.model)

        XCTAssertEqual(
            firstTab.model.repositoryURL?.resolvingSymlinksInPath(),
            firstURL.resolvingSymlinksInPath()
        )
        await waitForRepositoryLoad(in: firstTab)
        XCTAssertFalse(firstTab.isRepositoryLoadPending)
        XCTAssertEqual(tabsModel.activeTabID, firstTab.id)
    }

    func testRestoredPlainFolderLeavesLoadingStateForRepositorySetup() async throws {
        let defaults = isolatedDefaults()
        let folderURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        defaults.set([folderURL.path], forKey: "openRepositoryPaths")

        let tabsModel = WorkspaceTabsModel(defaults: defaults)
        let tab = tabsModel.activeTab
        XCTAssertTrue(tab.isRepositoryLoadPending)

        let deadline = Date().addingTimeInterval(3)
        while tab.model.repositoryInitializationURL == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await waitForRepositoryLoad(in: tab)

        XCTAssertEqual(
            tab.model.repositoryInitializationURL?.standardizedFileURL,
            folderURL.standardizedFileURL
        )
        XCTAssertFalse(tab.isRepositoryLoadPending)
    }

    func testTwentyRestoredTabsStayLazyAndUseOnlyOneWatcher() async throws {
        let defaults = isolatedDefaults()
        let repositoryURLs = try (0..<20).map { _ in
            let url = try temporaryDirectory()
            try GitClient.initializeRepository(at: url, createGitIgnore: false)
            return url
        }
        defer {
            repositoryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        defaults.set(repositoryURLs.map(\.path), forKey: "openRepositoryPaths")
        defaults.set(repositoryURLs[0].path, forKey: "activeRepositoryPath")
        KvistRuntimeMetrics.reset()

        let tabsModel = WorkspaceTabsModel(
            defaults: defaults,
            automaticallyActivatesInitialTab: false
        )

        XCTAssertEqual(tabsModel.tabs.count, 20)
        XCTAssertNil(tabsModel.activeTab.loadedModel)
        XCTAssertTrue(tabsModel.activeTab.isRepositoryLoadPending)
        XCTAssertTrue(tabsModel.tabs.dropFirst().allSatisfy { $0.loadedModel == nil })
        XCTAssertEqual(tabsModel.activeRepositoryWatcherCount, 0)
        XCTAssertTrue(KvistRuntimeMetrics.snapshot().gitCommandsByRepository.isEmpty)

        tabsModel.activateInitialTab()
        XCTAssertTrue(tabsModel.activeTab.isRepositoryLoadPending)
        await waitForRepository(repositoryURLs[0], in: tabsModel.activeModel)
        await waitForWatcher(in: tabsModel)

        XCTAssertEqual(tabsModel.tabs.count { $0.loadedModel?.repositoryURL != nil }, 1)
        XCTAssertEqual(tabsModel.activeRepositoryWatcherCount, 1)
        let inactivePaths = Set(repositoryURLs.dropFirst().map { $0.standardizedFileURL.path })
        let inactiveCommands = KvistRuntimeMetrics.snapshot().gitCommandsByRepository.reduce(into: 0) {
            if inactivePaths.contains($1.key) { $0 += $1.value }
        }
        XCTAssertEqual(inactiveCommands, 0)

        for (tab, repositoryURL) in zip(tabsModel.tabs.dropFirst(), repositoryURLs.dropFirst()) {
            tabsModel.select(tab.id)
            await waitForRepository(repositoryURL, in: tab.model)
            await waitForWatcher(in: tabsModel)
            XCTAssertEqual(tabsModel.activeRepositoryWatcherCount, 1)
        }

        tabsModel.activeModel.setMonitoringEnabled(false)
        XCTAssertEqual(tabsModel.activeRepositoryWatcherCount, 0)
    }

    func testReactivatedTabCatchesFilesystemChangesFromWhileInactive() async throws {
        let defaults = isolatedDefaults()
        let firstURL = try temporaryDirectory()
        let secondURL = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        try GitClient.initializeRepository(at: firstURL, createGitIgnore: false)
        try GitClient.initializeRepository(at: secondURL, createGitIgnore: false)
        defaults.set([firstURL.path, secondURL.path], forKey: "openRepositoryPaths")
        defaults.set(firstURL.path, forKey: "activeRepositoryPath")
        let tabsModel = WorkspaceTabsModel(defaults: defaults)
        let firstTab = tabsModel.tabs[0]
        let secondTab = tabsModel.tabs[1]
        await waitForRepository(firstURL, in: firstTab.model)

        tabsModel.select(secondTab.id)
        await waitForRepository(secondURL, in: secondTab.model)
        try await Task.sleep(for: .milliseconds(50))
        try "changed while inactive\n".write(
            to: firstURL.appendingPathComponent("inactive-change.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await Task.sleep(for: .milliseconds(50))

        tabsModel.select(firstTab.id)
        let deadline = Date().addingTimeInterval(3)
        while !firstTab.model.unstaged.contains(where: { $0.path == "inactive-change.txt" }),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(
            firstTab.model.unstaged.contains { $0.path == "inactive-change.txt" }
        )
        XCTAssertEqual(tabsModel.activeRepositoryWatcherCount, 1)
        firstTab.model.setMonitoringEnabled(false)
    }

    func testSelectNextAndPreviousCycleThroughTabs() {
        let tabsModel = WorkspaceTabsModel(
            defaults: isolatedDefaults(),
            restoreSavedTabs: false
        )
        tabsModel.addTab()
        tabsModel.addTab()
        let tabIDs = tabsModel.tabs.map(\.id)
        tabsModel.select(tabIDs[0])

        tabsModel.selectNext()
        XCTAssertEqual(tabsModel.activeTabID, tabIDs[1])

        tabsModel.selectPrevious()
        tabsModel.selectPrevious()
        XCTAssertEqual(tabsModel.activeTabID, tabIDs[2])

        tabsModel.selectNext()
        XCTAssertEqual(tabsModel.activeTabID, tabIDs[0])
    }

    func testCloseOthersKeepsOnlyTheGivenTab() {
        let tabsModel = WorkspaceTabsModel(
            defaults: isolatedDefaults(),
            restoreSavedTabs: false
        )
        tabsModel.addTab()
        tabsModel.addTab()
        let keptTabID = tabsModel.tabs[1].id

        tabsModel.closeOthers(keptTabID)

        XCTAssertEqual(tabsModel.tabs.map(\.id), [keptTabID])
        XCTAssertEqual(tabsModel.activeTabID, keptTabID)
    }

    func testRecentRepositoriesRestoreExistingPathsAndCanBeRemoved() throws {
        let defaults = isolatedDefaults()
        let existingURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: existingURL) }
        let missingPath = "/nonexistent/KvistTests-\(UUID().uuidString)"
        defaults.set(
            [existingURL.path, missingPath],
            forKey: "recentRepositoryPaths"
        )

        let tabsModel = WorkspaceTabsModel(
            defaults: defaults,
            restoreSavedTabs: false
        )

        XCTAssertEqual(
            tabsModel.recentRepositoryURLs.map(\.path),
            [existingURL.path]
        )

        tabsModel.removeRecentRepository(path: existingURL.path)

        XCTAssertTrue(tabsModel.recentRepositoryURLs.isEmpty)
        XCTAssertEqual(
            defaults.stringArray(forKey: "recentRepositoryPaths"),
            []
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "KvistTests.WorkspaceTabs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func waitForRepository(_ url: URL, in model: RepositoryModel) async {
        let deadline = Date().addingTimeInterval(3)
        while model.repositoryURL?.resolvingSymlinksInPath()
                != url.resolvingSymlinksInPath(),
              Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func waitForRepositoryLoad(in tab: RepositoryTab) async {
        let deadline = Date().addingTimeInterval(3)
        while tab.isRepositoryLoadPending, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitForEditor(in model: RepositoryModel) async {
        let deadline = Date().addingTimeInterval(3)
        while model.isDetailLoading, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func waitForWatcher(in tabsModel: WorkspaceTabsModel) async {
        let deadline = Date().addingTimeInterval(3)
        while tabsModel.activeRepositoryWatcherCount != 1, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "KvistTabTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

import Foundation
import XCTest
@testable import Kvist

/// Folders opened without Git, locally or over SSH.
final class PlainFolderTests: XCTestCase {
    private var folderURL: URL!

    override func setUpWithError() throws {
        folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "KvistPlainFolderTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folderURL)
    }

    // MARK: - SSH marker compatibility

    func testSSHRepositoryMarkersWithoutKindDecodeAsGitRepositories() throws {
        let legacy = Data(#"{"host":"user@example.com","path":"/srv/app"}"#.utf8)

        let repository = try JSONDecoder().decode(SSHRepository.self, from: legacy)

        XCTAssertTrue(repository.isGitRepository)
        XCTAssertEqual(repository.host, "user@example.com")
        XCTAssertEqual(repository.path, "/srv/app")
    }

    func testSSHFolderMarkersRoundTrip() throws {
        let folder = try SSHRepository(
            host: "user@example.com",
            path: "/srv/notes",
            isGitRepository: false
        )

        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(SSHRepository.self, from: data)

        XCTAssertEqual(decoded, folder)
        XCTAssertFalse(decoded.isGitRepository)
    }

    // MARK: - Remote path probe

    func testProbeParserDistinguishesRepositoriesFromFolders() throws {
        XCTAssertEqual(
            try GitClient.parseSSHPathProbe(Data("folder".utf8), path: "/srv/notes"),
            .folder
        )
        XCTAssertEqual(
            try GitClient.parseSSHPathProbe(
                Data("repository\n/srv/app".utf8),
                path: "/srv/app"
            ),
            .repository
        )
    }

    func testProbeParserRejectsMissingFoldersAndNestedRepositoryPaths() {
        XCTAssertThrowsError(
            try GitClient.parseSSHPathProbe(Data("missing".utf8), path: "/srv/gone")
        ) { error in
            XCTAssertTrue(
                (error as? GitCommandError)?.output.contains("/srv/gone") == true
            )
        }
        XCTAssertThrowsError(
            try GitClient.parseSSHPathProbe(
                Data("repository\n/srv/app".utf8),
                path: "/srv/app/Sources"
            )
        ) { error in
            XCTAssertTrue(
                (error as? GitCommandError)?.output.contains("repository root") == true
            )
        }
        XCTAssertThrowsError(
            try GitClient.parseSSHPathProbe(Data("garbage".utf8), path: "/srv/app")
        )
    }

    // MARK: - Restoration state

    func testRestorationStateSavedBeforeFolderModeStillDecodes() throws {
        let legacy = Data("""
        {"workspaceMode":"fileEditor","expandedFileDirectories":["Sources"],
        "expandedCommitHashes":[],"graphScope":"all","commitMessage":"wip"}
        """.utf8)

        let state = try JSONDecoder().decode(RepositoryRestorationState.self, from: legacy)

        XCTAssertEqual(state.workspaceMode, .fileEditor)
        XCTAssertEqual(state.expandedFileDirectories, ["Sources"])
        XCTAssertEqual(state.commitMessage, "wip")
        XCTAssertFalse(state.opensAsPlainFolder)
    }

    func testRestorationStateKeepsPlainFolderFlag() throws {
        var state = RepositoryRestorationState()
        state.opensAsPlainFolder = true

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RepositoryRestorationState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.opensAsPlainFolder)
    }

    // MARK: - Search without Git

    func testGrepOutputParserReadsNullSeparatedRecords() {
        let output = "./Sources/App.swift\u{0}3:let needle = 1\n"
            + "./notes.md\u{0}12:  a needle: with colon  \n"
            + "broken record\n"

        let parsed = RepositorySearchParser.textMatches(fromGrepOutput: output, limit: 10)

        XCTAssertEqual(parsed.matches.map(\.path), ["Sources/App.swift", "notes.md"])
        XCTAssertEqual(parsed.matches.map(\.line), [3, 12])
        XCTAssertEqual(
            parsed.matches.map(\.preview),
            ["let needle = 1", "a needle: with colon"]
        )
        XCTAssertFalse(parsed.wasLimited)

        let limited = RepositorySearchParser.textMatches(fromGrepOutput: output, limit: 1)
        XCTAssertEqual(limited.matches.count, 1)
        XCTAssertTrue(limited.wasLimited)
    }

    func testFolderSearchFindsFileNamesAndTextWithoutGit() throws {
        let sourcesURL = folderURL.appendingPathComponent("Sources", isDirectory: true)
        let nestedGitURL = folderURL.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourcesURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: nestedGitURL,
            withIntermediateDirectories: true
        )
        try """
        let firstNeedle = true
        let second = "NEEDLE"
        """.write(
            to: sourcesURL.appendingPathComponent("Searchable.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "needle\n".write(
            to: nestedGitURL.appendingPathComponent("config"),
            atomically: true,
            encoding: .utf8
        )
        try "it's a needle 'quoted'\n".write(
            to: folderURL.appendingPathComponent("odd 'name'.txt"),
            atomically: true,
            encoding: .utf8
        )

        let client = GitClient(repositoryURL: folderURL)
        let textResults = try client.searchFolder(for: "needle")
        let fileResults = try client.searchFolder(for: "*.swift")
        let quotedResults = try client.searchFolder(for: "needle 'quoted'")

        XCTAssertEqual(
            Set(textResults.textMatches.map(\.path)),
            ["Sources/Searchable.swift", "odd 'name'.txt"]
        )
        XCTAssertEqual(
            textResults.textMatches
                .filter { $0.path == "Sources/Searchable.swift" }
                .map(\.line),
            [1, 2]
        )
        XCTAssertFalse(textResults.textMatches.contains { $0.path.hasPrefix(".git") })
        XCTAssertEqual(
            fileResults.fileMatches.map(\.path),
            ["Sources/Searchable.swift"]
        )
        XCTAssertEqual(quotedResults.textMatches.map(\.path), ["odd 'name'.txt"])
        XCTAssertTrue(try client.searchFolder(for: "   ").textMatches.isEmpty)
    }

    @MainActor
    func testOpeningALocalFolderWithoutGitEntersFileModeAndKeepsGitOff() async throws {
        try "hello\n".write(
            to: folderURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )

        await model.openFolderWithoutGit(folderURL)

        XCTAssertEqual(
            model.repositoryURL?.standardizedFileURL,
            folderURL.standardizedFileURL
        )
        XCTAssertTrue(model.isPlainFolder)
        XCTAssertNil(model.repositoryInitializationURL)
        XCTAssertEqual(model.workspaceMode, .fileEditor)
        XCTAssertTrue(model.graph.isEmpty)
        XCTAssertTrue(model.remotes.isEmpty)

        model.setWorkspaceMode(.sourceControl)
        XCTAssertEqual(model.workspaceMode, .fileEditor)

        let children = try await model.repositoryFileChildren(at: folderURL)
        XCTAssertEqual(children.map(\.name), ["README.md"])

        let state = model.makeRestorationState()
        XCTAssertTrue(state.opensAsPlainFolder)

        await model.refresh()
        XCTAssertEqual(model.activity, "Up to date")
    }

    @MainActor
    func testFolderModeCanInitializeGitAndReturnToTheFullWorkspace() async throws {
        try "hello\n".write(
            to: folderURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )
        await model.openFolderWithoutGit(folderURL)
        XCTAssertTrue(model.isPlainFolder)

        model.requestRepositoryInitialization()
        XCTAssertEqual(
            model.repositoryInitializationURL?.standardizedFileURL,
            folderURL.standardizedFileURL
        )

        model.cancelRepositoryInitialization()
        XCTAssertNil(model.repositoryInitializationURL)
        XCTAssertTrue(model.isPlainFolder)

        model.requestRepositoryInitialization()
        await model.initializeRepository(createGitIgnore: true)

        XCTAssertNil(model.repositoryInitializationURL)
        XCTAssertFalse(model.isPlainFolder)
        XCTAssertNil(model.errorPresentation)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folderURL.appendingPathComponent(".git").path
        ))
        XCTAssertTrue(model.unstaged.contains { $0.path == "README.md" })
        model.setWorkspaceMode(.sourceControl)
        XCTAssertEqual(model.workspaceMode, .sourceControl)
    }

    @MainActor
    func testOpeningAMissingLocalFolderWithoutGitReportsAnError() async {
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )

        await model.openFolderWithoutGit(
            folderURL.appendingPathComponent("missing", isDirectory: true)
        )

        XCTAssertNil(model.repositoryURL)
        XCTAssertFalse(model.isPlainFolder)
        XCTAssertNotNil(model.errorPresentation)
    }
}

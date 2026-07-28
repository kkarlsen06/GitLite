import Foundation
import XCTest
@testable import Kvist

final class RepositorySearchTests: XCTestCase {
    private var repositoryURL: URL!

    override func setUpWithError() throws {
        repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "KvistRepositorySearchTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
        try runGit(["init", "-b", "main"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repositoryURL)
    }

    func testPathMatcherRanksDirectNamesAndSupportsWildcards() throws {
        let exact = try XCTUnwrap(RepositoryPathMatcher.score(
            query: "RepositoryModel.swift",
            path: "Sources/Kvist/RepositoryModel.swift"
        ))
        let containing = try XCTUnwrap(RepositoryPathMatcher.score(
            query: "Repository",
            path: "Sources/Kvist/RepositoryModel.swift"
        ))
        let fuzzy = try XCTUnwrap(RepositoryPathMatcher.score(
            query: "rmbsw",
            path: "Sources/Kvist/RepositoryModelBrowser.swift"
        ))

        XCTAssertLessThan(exact, containing)
        XCTAssertLessThan(containing, fuzzy)
        XCTAssertNotNil(RepositoryPathMatcher.score(
            query: "*.swift",
            path: "Sources/Kvist/RepositoryModel.swift"
        ))
        XCTAssertNotNil(RepositoryPathMatcher.score(
            query: "sources/*browser.swift",
            path: "Sources/Kvist/RepositoryFileBrowser.swift"
        ))
        XCTAssertNil(RepositoryPathMatcher.score(
            query: "*.md",
            path: "Sources/Kvist/RepositoryModel.swift"
        ))
    }

    func testSearchFindsFileNamesAndTextButExcludesIgnoredFiles() throws {
        let sourcesURL = repositoryURL.appendingPathComponent(
            "Sources",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourcesURL,
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
            to: repositoryURL.appendingPathComponent("ignored.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored.txt\n".write(
            to: repositoryURL.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let client = GitClient(repositoryURL: repositoryURL)
        let textResults = try client.searchRepository(for: "needle")
        let fileResults = try client.searchRepository(for: "*.swift")

        XCTAssertEqual(
            textResults.textMatches.map(\.path),
            ["Sources/Searchable.swift", "Sources/Searchable.swift"]
        )
        XCTAssertEqual(textResults.textMatches.map(\.line), [1, 2])
        XCTAssertFalse(textResults.textMatches.contains {
            $0.path == "ignored.txt"
        })
        XCTAssertEqual(
            fileResults.fileMatches.map(\.path),
            ["Sources/Searchable.swift"]
        )
    }

    func testSearchParserHonorsResultLimit() {
        let output = """
        Sources/App.swift\u{0}12\u{0}let needle = true
        Sources/App.swift\u{0}18\u{0}print(needle)
        Sources/Other.swift\u{0}3\u{0}needle()
        """

        let parsed = RepositorySearchParser.textMatches(
            from: output,
            limit: 2
        )

        XCTAssertEqual(parsed.matches.count, 2)
        XCTAssertEqual(parsed.matches.first?.line, 12)
        XCTAssertTrue(parsed.wasLimited)
    }

    func testSearchParserUsesCurrentEditorLineNumbers() {
        let matches = RepositorySearchParser.textMatches(
            in: "inserted\nfirst\nNeedle here\nlast",
            path: "App.swift",
            query: "needle",
            limit: 20
        )

        XCTAssertEqual(matches, [
            RepositoryTextSearchMatch(
                path: "App.swift",
                line: 3,
                preview: "Needle here"
            )
        ])
    }

    @MainActor
    func testSearchPanelPreservesAndReturnsToOpenEditor() async throws {
        let fileURL = repositoryURL.appendingPathComponent("Answer.swift")
        let otherFileURL = repositoryURL.appendingPathComponent("Other.swift")
        try "let answer = 42\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        try "let other = 1\n".write(
            to: otherFileURL,
            atomically: true,
            encoding: .utf8
        )
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: true
        )
        defer { model.setMonitoringEnabled(false) }
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Answer.swift")
        for _ in 0..<100 where model.isDetailLoading {
            try? await Task.sleep(for: .milliseconds(10))
        }

        model.toggleRepositorySearch()
        model.repositorySearchQuery = "answer"

        XCTAssertTrue(model.isFileSearchPresented)
        XCTAssertTrue(model.isRepositorySidePanelPresented)
        XCTAssertTrue(model.isDiffPanelPresented)
        XCTAssertEqual(model.selectedRepositoryFilePath, "Answer.swift")

        model.repositoryFileText = "let answer = 43\n"
        model.openRepositorySearchMatch("Answer.swift", line: 1)

        XCTAssertEqual(model.repositoryFileText, "let answer = 43\n")
        XCTAssertTrue(model.isRepositoryFileDirty)
        XCTAssertTrue(model.isFileSearchPresented)
        XCTAssertFalse(model.isFileSearchResultsPresented)
        XCTAssertTrue(model.repositoryFileScrollRequest?.highlightsLine == true)

        // Ending the search field's editing session republishes its current
        // value. That must not restart the search and cover the editor again.
        model.repositorySearchQuery = "answer"
        XCTAssertFalse(model.isFileSearchResultsPresented)

        let revisionBeforeOtherFileChanged = model.repositoryFilesRevision
        try "let other = 2\n".write(
            to: otherFileURL,
            atomically: true,
            encoding: .utf8
        )
        for _ in 0..<200
        where model.repositoryFilesRevision == revisionBeforeOtherFileChanged {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertGreaterThan(
            model.repositoryFilesRevision,
            revisionBeforeOtherFileChanged
        )
        XCTAssertFalse(model.isFileSearchResultsPresented)
        XCTAssertEqual(model.selectedRepositoryFilePath, "Answer.swift")
        XCTAssertEqual(model.repositoryFileText, "let answer = 43\n")
        XCTAssertTrue(model.isRepositoryFileDirty)

        model.showRepositorySearchResults()

        XCTAssertTrue(model.isFileSearchResultsPresented)
        model.dismissRepositorySearch()

        XCTAssertFalse(model.isFileSearchPresented)
        XCTAssertFalse(model.isFileSearchResultsPresented)
        XCTAssertTrue(model.isRepositorySidePanelPresented)
        XCTAssertTrue(model.isDiffPanelPresented)
        XCTAssertEqual(model.selectedRepositoryFilePath, "Answer.swift")
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "git failed"
            throw NSError(
                domain: "RepositorySearchTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

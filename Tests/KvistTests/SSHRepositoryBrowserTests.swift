import Foundation
import XCTest
@testable import Kvist

final class SSHRepositoryBrowserTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistSSHBrowserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testListingParsesCurrentDirectoryMarkerAndEntryKinds() throws {
        let data = try XCTUnwrap(
            "r\u{0}.\u{0}d\u{0}Sources\u{0}r\u{0}app\u{0}b\u{0}mirror.git\u{0}"
                .data(using: .utf8)
        )

        let listing = SSHBrowserRemote.parseListing(data, directory: "/srv")

        XCTAssertEqual(listing.currentKind, .repository)
        XCTAssertEqual(listing.entries.map(\.name), ["app", "mirror.git", "Sources"])
        XCTAssertEqual(
            listing.entries.map(\.kind),
            [.repository, .bareRepository, .folder]
        )
        XCTAssertEqual(
            listing.entries.map(\.path),
            ["/srv/app", "/srv/mirror.git", "/srv/Sources"]
        )
    }

    func testListingJoinsNamesAgainstTheFilesystemRoot() throws {
        let data = try XCTUnwrap("d\u{0}.\u{0}d\u{0}srv\u{0}".data(using: .utf8))

        let listing = SSHBrowserRemote.parseListing(data, directory: "/")

        XCTAssertEqual(listing.currentKind, .folder)
        XCTAssertEqual(listing.entries.map(\.path), ["/srv"])
    }

    func testListCommandFindsRepositoriesFoldersAndBareRepositories() throws {
        let repository = rootURL.appendingPathComponent("repo dir", isDirectory: true)
        let bare = rootURL.appendingPathComponent("mirror.git", isDirectory: true)
        let folder = rootURL.appendingPathComponent("plain", isDirectory: true)
        let hidden = rootURL.appendingPathComponent(".hidden", isDirectory: true)
        for directory in [repository, bare, folder, hidden] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        for component in ["objects", "refs"] {
            try FileManager.default.createDirectory(
                at: bare.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try Data("ref: refs/heads/main\n".utf8).write(
            to: bare.appendingPathComponent("HEAD")
        )
        try Data().write(to: rootURL.appendingPathComponent("file.txt"))

        let command = SSHBrowserRemote.listCommand(
            directory: rootURL.path,
            includeHidden: false
        )
        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let listing = SSHBrowserRemote.parseListing(
            Data(result.output.utf8),
            directory: rootURL.path
        )
        XCTAssertEqual(listing.currentKind, .folder)
        XCTAssertEqual(
            listing.entries.map(\.name),
            ["mirror.git", "plain", "repo dir"]
        )
        XCTAssertEqual(
            listing.entries.map(\.kind),
            [.bareRepository, .folder, .repository]
        )
    }

    func testListCommandIncludesHiddenFoldersOnRequest() throws {
        let hidden = rootURL.appendingPathComponent(".config", isDirectory: true)
        try FileManager.default.createDirectory(
            at: hidden,
            withIntermediateDirectories: true
        )

        let command = SSHBrowserRemote.listCommand(
            directory: rootURL.path,
            includeHidden: true
        )
        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let listing = SSHBrowserRemote.parseListing(
            Data(result.output.utf8),
            directory: rootURL.path
        )
        XCTAssertEqual(listing.entries.map(\.name), [".config"])
    }

    func testListCommandMarksTheListedDirectoryAsRepository() throws {
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let command = SSHBrowserRemote.listCommand(
            directory: rootURL.path,
            includeHidden: false
        )
        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let listing = SSHBrowserRemote.parseListing(
            Data(result.output.utf8),
            directory: rootURL.path
        )
        XCTAssertEqual(listing.currentKind, .repository)
        XCTAssertTrue(listing.entries.isEmpty)
    }

    func testListCommandQuotesHostileDirectoryNames() throws {
        let hostile = rootURL.appendingPathComponent(
            "it's; touch $(pwn)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: hostile.appendingPathComponent("inner", isDirectory: true),
            withIntermediateDirectories: true
        )

        let command = SSHBrowserRemote.listCommand(
            directory: hostile.path,
            includeHidden: false
        )
        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let listing = SSHBrowserRemote.parseListing(
            Data(result.output.utf8),
            directory: hostile.path
        )
        XCTAssertEqual(listing.entries.map(\.name), ["inner"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent("pwn").path
            )
        )
    }

    func testSuggestionsParserMapsGitEntriesToRepositoryFolders() {
        let output = """
        /home/user/projects/app/.git
        /home/user/projects/tool/.git
        /home/user/projects/app/.git
        /home/user/notes.txt
        relative/.git
        """
        let suggestions = SSHBrowserRemote.parseSuggestions(Data(output.utf8))

        XCTAssertEqual(suggestions, [
            "/home/user/projects/app",
            "/home/user/projects/tool"
        ])
    }

    func testDisplayPathAbbreviatesTheHomeFolder() {
        XCTAssertEqual(
            SSHBrowserRemote.displayPath("/home/user/app", home: "/home/user"),
            "~/app"
        )
        XCTAssertEqual(
            SSHBrowserRemote.displayPath("/home/user", home: "/home/user"),
            "~"
        )
        XCTAssertEqual(
            SSHBrowserRemote.displayPath("/srv/app", home: "/home/user"),
            "/srv/app"
        )
        XCTAssertEqual(SSHBrowserRemote.displayPath("/srv/app", home: "/"), "/srv/app")
    }

    func testHomeCommandPrintsAnAbsolutePath() throws {
        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", SSHBrowserRemote.homeCommand],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.hasPrefix("/"), result.output)
    }
}

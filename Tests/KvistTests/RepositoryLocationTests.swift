import AppKit
import XCTest
@testable import Kvist

final class RepositoryLocationTests: XCTestCase {
    @MainActor
    func testCopyDirectoryPathWritesStandardizedRepositoryPath() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("RepositoryLocationTests.\(UUID().uuidString)")
        )
        let repositoryURL = URL(fileURLWithPath: "/tmp/project/../repository")

        RepositoryLocationActions.copyDirectoryPath(
            repositoryURL,
            to: pasteboard
        )

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "/tmp/repository"
        )
    }

    func testSSHTerminalStartsLoginShellInRemoteRepository() throws {
        let repositoryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kvist terminal's repository", isDirectory: true)
        let shellURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistTerminalShell-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: repositoryDirectory)
            try? FileManager.default.removeItem(at: shellURL)
        }
        try FileManager.default.createDirectory(
            at: repositoryDirectory,
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\npwd\n".write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: shellURL.path
        )
        let repository = try SSHRepository(
            host: "deploy@example.com",
            path: repositoryDirectory.path
        )
        let arguments = RepositoryTerminalLauncher.sshArguments(for: repository)
        let remoteCommand = try XCTUnwrap(arguments.last)

        XCTAssertEqual(Array(arguments.suffix(4).dropLast()), [
            "-t", "--", "deploy@example.com"
        ])
        XCTAssertFalse(arguments.contains("BatchMode=yes"))
        XCTAssertTrue(arguments.contains("ControlMaster=auto"))

        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "SHELL='\(shellURL.path)' \(remoteCommand)"],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(
            result.output.trimmingCharacters(in: .whitespacesAndNewlines),
            repositoryDirectory.path
        )
    }

    func testSSHTerminalCommandFileIsExecutableShellSyntax() throws {
        let repository = try SSHRepository(
            host: "deploy@example.com",
            path: "/srv/project with spaces"
        )
        let contents = RepositoryTerminalLauncher.commandFileContents(for: repository)

        XCTAssertTrue(contents.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(contents.contains("/bin/rm -f -- \"$0\""))
        XCTAssertTrue(contents.contains("exec '/usr/bin/ssh'"))
        XCTAssertTrue(contents.contains("'-t' '--' 'deploy@example.com'"))
        XCTAssertFalse(contents.contains("BatchMode=yes"))

        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-n"],
            currentDirectoryURL: nil,
            standardInput: contents,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
    }
}

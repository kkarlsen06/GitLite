import Foundation
import XCTest
@testable import Kvist

final class GitClientTests: XCTestCase {
    private var repositoryURL: URL!

    override func setUpWithError() throws {
        repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )

        try git(["init", "-b", "main"])
        try git(["config", "user.name", "Kvist Test"])
        try git(["config", "user.email", "kvist@example.invalid"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repositoryURL)
    }

    func testSSHRepositoryRequiresSafeHostAndAbsolutePath() throws {
        XCTAssertEqual(
            try SSHRepository(host: "deploy@example.com", path: "/srv/app"),
            try SSHRepository(host: "deploy@example.com", path: "/srv/app")
        )
        XCTAssertThrowsError(
            try SSHRepository(host: "example.com; touch /tmp/pwned", path: "/srv/app")
        )
        XCTAssertThrowsError(
            try SSHRepository(host: "example.com", path: "srv/app")
        )
    }

    func testSSHConnectionUsesPrivatePersistentControlSocket() {
        let directory = URL(
            fileURLWithPath: "/Users/kvist test/Library/Caches/Kvist/SSH",
            isDirectory: true
        )

        XCTAssertEqual(
            SSHConnection.options(controlDirectory: directory),
            [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=120",
                "-o", "ControlPath=/Users/kvist test/Library/Caches/Kvist/SSH/%C"
            ]
        )
        XCTAssertEqual(
            SSHConnection.options(controlDirectory: nil),
            [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                "-o", "StrictHostKeyChecking=accept-new"
            ]
        )
    }

    func testSSHAuthenticationFailureHasActionablePresentation() throws {
        let presentation = try XCTUnwrap(GitCommandError(
            command: "ssh deploy@example.com",
            output: "Permission denied (publickey)."
        ).sshAuthenticationPresentation)

        XCTAssertEqual(presentation.title, "SSH Authentication Failed")
        XCTAssertTrue(presentation.message.contains("macOS Keychain"))
    }

    func testSSHRemoteShellQuotesControlPathForRsync() {
        let directory = URL(fileURLWithPath: "/tmp/Kvist SSH", isDirectory: true)
        let command = SSHConnection.rsyncRemoteShell(controlDirectory: directory)

        XCTAssertTrue(command.hasPrefix("'/usr/bin/ssh' "))
        XCTAssertTrue(command.contains("'ControlMaster=auto'"))
        XCTAssertTrue(command.contains("'ControlPath=/tmp/Kvist SSH/%C'"))
    }

    func testRemoteCommandFramingPreservesBinaryOutputAndExitCodes() throws {
        var data = Data("0 4\n".utf8)
        data.append(contentsOf: [0x41, 0x00, 0x42, 0x0A])
        data.append(Data("7 3\nerr".utf8))

        let results = try GitClient.parseRemoteCommandResults(data, expectedCount: 2)

        XCTAssertEqual(results.map(\.exitCode), [0, 7])
        XCTAssertEqual(results[0].output, Data([0x41, 0x00, 0x42, 0x0A]))
        XCTAssertEqual(String(decoding: results[1].output, as: UTF8.self), "err")
    }

    func testRemoteCommandBatchRunsAllCommandsAfterAFailure() throws {
        let script = GitClient.framedRemoteCommands([
            "printf 'first\\0result'",
            "printf 'failed'; exit 9",
            "printf 'last'"
        ])
        let result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let commands = try GitClient.parseRemoteCommandResults(
            Data(result.output.utf8),
            expectedCount: 3
        )
        XCTAssertEqual(commands.map(\.exitCode), [0, 9, 0])
        XCTAssertEqual(commands.map { String(decoding: $0.output, as: UTF8.self) }, [
            "first\0result", "failed", "last"
        ])
    }

    func testRemoteOperationCommandChecksGitStateOnRemoteFilesystem() throws {
        let gitDirectory = repositoryURL.appendingPathComponent(".git", isDirectory: true)
        let mergeHead = gitDirectory.appendingPathComponent("MERGE_HEAD")
        try Data().write(to: mergeHead)

        var result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", GitClient.remoteOperationCommand(path: repositoryURL.path)],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "merge")

        try FileManager.default.createDirectory(
            at: gitDirectory.appendingPathComponent("rebase-merge", isDirectory: true),
            withIntermediateDirectories: false
        )
        result = try AICommandRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", GitClient.remoteOperationCommand(path: repositoryURL.path)],
            currentDirectoryURL: nil,
            standardInput: nil,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "rebase")
    }

    func testRemoteListingParserReadsFetchAndPushURLsInOneResponse() throws {
        let output = """
        upstream\tssh://git@example.com/second.git (push)
        origin\t/Repos/project with spaces (fetch)
        upstream\tssh://git@example.com/second.git (fetch)
        origin\tssh://git@example.com/project.git (push)
        """

        XCTAssertEqual(try GitClient.parseRemotes(output), [
            GitRemote(
                name: "origin",
                fetchURL: "/Repos/project with spaces",
                pushURL: "ssh://git@example.com/project.git"
            ),
            GitRemote(
                name: "upstream",
                fetchURL: "ssh://git@example.com/second.git",
                pushURL: "ssh://git@example.com/second.git"
            )
        ])
    }

    func testSSHDirectoryEntriesPreserveNamesAndHideGitMetadata() throws {
        let data = try XCTUnwrap(
            "d\u{0}Sources\u{0}f\u{0}line\nbreak.txt\u{0}l\u{0}link\u{0}d\u{0}.git\u{0}"
                .data(using: .utf8)
        )

        let entries = GitClient.parseSSHDirectoryEntries(data)

        XCTAssertEqual(entries.map(\.name), ["Sources", "line\nbreak.txt", "link"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, false, false])
        XCTAssertEqual(entries.map(\.isSymbolicLink), [false, false, true])
    }

    func testRebaseConflictErrorUsesStructuredPresentation() throws {
        let output = """
        Rebasing (1/1)
        Auto-merging DESIGN.md
        CONFLICT (add/add): Merge conflict in DESIGN.md
        Auto-merging Package.swift
        CONFLICT (add/add): Merge conflict in Package.swift
        Auto-merging Sources/Kvist/GitClient.swift
        CONFLICT (content): Merge conflict in Sources/Kvist/GitClient.swift
        error: could not apply 773ec83... feat: add native macOS Git client
        hint: Resolve all conflicts manually, then run git rebase --continue.
        """
        let error = GitCommandError(command: "git pull", output: output)

        let presentation = try XCTUnwrap(error.rebaseConflictPresentation)
        XCTAssertEqual(presentation.title, "Rebase Paused")
        XCTAssertTrue(presentation.message.contains("3 files have conflicts"))
        XCTAssertTrue(presentation.message.contains("• DESIGN.md"))
        XCTAssertTrue(presentation.message.contains("• Package.swift"))
        XCTAssertTrue(presentation.message.contains("• Sources/Kvist/GitClient.swift"))
        XCTAssertTrue(presentation.message.contains("Resolve the conflicts under Changes"))
        XCTAssertTrue(presentation.message.contains("choose Abort Rebase"))
        XCTAssertFalse(presentation.message.contains("Terminal"))
        XCTAssertFalse(presentation.message.contains("Auto-merging"))
        XCTAssertTrue(presentation.details.contains("Command: git pull"))
        XCTAssertTrue(presentation.details.contains("Auto-merging DESIGN.md"))
        XCTAssertEqual(error.localizedDescription, presentation.message)
    }

    func testOrdinaryGitErrorKeepsOriginalMessage() {
        let error = GitCommandError(
            command: "git push",
            output: "fatal: the remote end hung up unexpectedly"
        )

        XCTAssertNil(error.rebaseConflictPresentation)
        XCTAssertEqual(
            error.localizedDescription,
            "fatal: the remote end hung up unexpectedly"
        )
    }

    func testOrdinaryGitErrorUsesBoundedCommandFailurePresentation() {
        let error = GitCommandError(
            command: "git commit -m message",
            output: String(repeating: "lint warning\n", count: 1_000)
        )

        let presentation = error.commandFailurePresentation
        XCTAssertEqual(presentation.title, "Git Command Failed")
        XCTAssertTrue(presentation.message.contains("Show Details"))
        XCTAssertFalse(presentation.message.contains("lint warning"))
        XCTAssertTrue(presentation.details.contains("git commit -m message"))
        XCTAssertEqual(presentation.details.components(separatedBy: "\n").count, 1_002)
    }

    func testMissingGitLFSErrorUsesActionablePresentation() throws {
        let output = """
        git: 'lfs' is not a git command. See 'git --help'.

        The most similar command is
            refs
        husky - pre-push script failed (code 1)
        error: failed to push some refs to 'github.com:example/project.git'
        """
        let error = GitCommandError(command: "git push", output: output)

        let presentation = try XCTUnwrap(error.missingToolPresentation)
        XCTAssertEqual(presentation.title, "Git LFS Not Found")
        XCTAssertTrue(presentation.message.contains("could not find git-lfs"))
        XCTAssertTrue(presentation.message.contains("shell’s PATH"))
        XCTAssertFalse(presentation.message.contains("husky"))
        XCTAssertTrue(presentation.details.contains("Command: git push"))
        XCTAssertTrue(presentation.details.contains("husky - pre-push script failed"))
        XCTAssertEqual(error.localizedDescription, presentation.message)
    }

    func testGitCommandEnvironmentAddsShellAndCommonToolPaths() {
        let home = URL(fileURLWithPath: "/Users/kvist-test", isDirectory: true)
        let environment = GitClient.makeCommandEnvironment(
            baseEnvironment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: home,
            loginShellPATH: "/custom/shell/bin:/usr/bin"
        )
        let paths = environment["PATH"]?.split(separator: ":").map(String.init)

        XCTAssertEqual(paths?.first, "/custom/shell/bin")
        XCTAssertEqual(paths?.filter { $0 == "/usr/bin" }.count, 1)
        XCTAssertTrue(paths?.contains("/opt/homebrew/bin") == true)
        XCTAssertTrue(paths?.contains("/usr/local/bin") == true)
        XCTAssertTrue(paths?.contains("/Users/kvist-test/.local/bin") == true)
        XCTAssertTrue(paths?.contains("/Users/kvist-test/Library/pnpm") == true)
    }

    func testGitHubRemoteDetectionMatchesSupportedCommitURLs() {
        XCTAssertTrue(GitRemote(
            name: "origin",
            fetchURL: "git@github.com:example/Kvist.git",
            pushURL: "git@github.com:example/Kvist.git"
        ).isGitHub)
        XCTAssertTrue(GitRemote(
            name: "origin",
            fetchURL: "https://github.com/example/Kvist.git",
            pushURL: "https://github.com/example/Kvist.git"
        ).isGitHub)
        XCTAssertFalse(GitRemote(
            name: "origin",
            fetchURL: "https://gitlab.com/example/Kvist.git",
            pushURL: "https://gitlab.com/example/Kvist.git"
        ).isGitHub)
    }

    func testNewRepositoryAndStageCommitWorkflow() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("README.md")
        try "# Kvist\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let newRepository = try client.snapshot()
        XCTAssertEqual(newRepository.branch, "main")
        XCTAssertTrue(newRepository.staged.isEmpty)
        XCTAssertEqual(newRepository.unstaged.first?.status, "U")
        XCTAssertTrue(newRepository.graph.isEmpty)

        try client.stageAll()
        let staged = try client.snapshot()
        XCTAssertEqual(staged.staged.first?.path, "README.md")
        XCTAssertTrue(staged.unstaged.isEmpty)

        _ = try client.commit(message: "Initial commit")
        let committed = try client.snapshot()
        XCTAssertTrue(committed.staged.isEmpty)
        XCTAssertTrue(committed.unstaged.isEmpty)
        XCTAssertEqual(committed.graph.compactMap(\.commit).first?.subject, "Initial commit")
    }

    func testSyncRebasesLocalCommitsBeforePushing() throws {
        let originURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistSyncOrigin-\(UUID().uuidString).git")
        let peerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistSyncPeer-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: originURL)
            try? FileManager.default.removeItem(at: peerURL)
        }

        let client = GitClient(repositoryURL: repositoryURL)
        try "initial\n".write(
            to: repositoryURL.appendingPathComponent("initial.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Initial commit")

        try git(["init", "--bare", "-b", "main", originURL.path])
        try git(["remote", "add", "origin", originURL.path])
        try git(["push", "--set-upstream", "origin", "main"])
        try git(["clone", originURL.path, peerURL.path])
        try git(["-C", peerURL.path, "config", "user.name", "Kvist Peer"])
        try git(["-C", peerURL.path, "config", "user.email", "peer@example.invalid"])
        try "remote\n".write(
            to: peerURL.appendingPathComponent("remote.txt"),
            atomically: true,
            encoding: .utf8
        )
        try git(["-C", peerURL.path, "add", "remote.txt"])
        try git(["-C", peerURL.path, "commit", "-m", "Remote commit"])
        try git(["-C", peerURL.path, "push"])

        try "local\n".write(
            to: repositoryURL.appendingPathComponent("local.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Local commit")
        try git(["config", "pull.rebase", "false"])

        _ = try client.sync()

        XCTAssertEqual(
            try git(["log", "--format=%s", "-3"])
                .split(separator: "\n").map(String.init),
            ["Local commit", "Remote commit", "Initial commit"]
        )
        XCTAssertEqual(
            try git(["rev-list", "--merges", "--count", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "0"
        )
        XCTAssertEqual(
            try git(["--git-dir", originURL.path, "rev-parse", "refs/heads/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            try git(["rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testDiffAndUnstageWorkflow() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("notes.txt")
        try "first\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Add notes")

        try "first\nsecond\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let changed = try XCTUnwrap(client.snapshot().unstaged.first)
        XCTAssertTrue(try client.diff(for: changed).contains("+second"))

        try client.stage(changed.path)
        let staged = try XCTUnwrap(client.snapshot().staged.first)
        XCTAssertTrue(try client.diff(for: staged).contains("+second"))

        try client.unstage(staged.path)
        let unstaged = try client.snapshot()
        XCTAssertTrue(unstaged.staged.isEmpty)
        XCTAssertEqual(unstaged.unstaged.first?.path, "notes.txt")
    }

    func testStagedAndUnstagedPreviewsUseHeadIndexAndWorkingTreeVersions() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("artwork.dat")
        let original = Data([0x00, 0x01, 0x02])
        let stagedContents = Data([0x00, 0x03, 0x04])
        let workingContents = Data([0x00, 0x05, 0x06])
        try original.write(to: fileURL)
        try client.stageAll()
        _ = try client.commit(message: "Add artwork")

        try stagedContents.write(to: fileURL)
        try client.stageAll()
        try workingContents.write(to: fileURL)

        let snapshot = try client.snapshot()
        let stagedChange = try XCTUnwrap(snapshot.staged.first)
        let unstagedChange = try XCTUnwrap(snapshot.unstaged.first)
        let stagedPreview = try XCTUnwrap(client.preview(for: stagedChange))
        let unstagedPreview = try XCTUnwrap(client.preview(for: unstagedChange))
        defer {
            stagedPreview.removeTemporaryFiles()
            unstagedPreview.removeTemporaryFiles()
        }

        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(stagedPreview.old?.url)), original)
        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(stagedPreview.new?.url)),
            stagedContents
        )
        XCTAssertEqual(stagedPreview.old?.context, "HEAD")
        XCTAssertEqual(stagedPreview.new?.context, "Staged")
        XCTAssertTrue(stagedPreview.prefersPreview)

        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(unstagedPreview.old?.url)),
            stagedContents
        )
        XCTAssertEqual(unstagedPreview.new?.url, fileURL.resolvingSymlinksInPath())
        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(unstagedPreview.new?.url)),
            workingContents
        )
        XCTAssertEqual(unstagedPreview.old?.context, "Staged")
        XCTAssertEqual(unstagedPreview.new?.context, "Working Tree")
    }

    func testAddedAndDeletedPreviewsShowOnlyTheAvailableVersion() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let deletedURL = repositoryURL.appendingPathComponent("deleted.dat")
        let deletedContents = Data([0x00, 0x01])
        try deletedContents.write(to: deletedURL)
        try client.stageAll()
        _ = try client.commit(message: "Add binary")

        try FileManager.default.removeItem(at: deletedURL)
        try client.stageAll()
        let addedURL = repositoryURL.appendingPathComponent("added.dat")
        let addedContents = Data([0x00, 0x02])
        try addedContents.write(to: addedURL)

        let snapshot = try client.snapshot()
        let deletion = try XCTUnwrap(snapshot.staged.first { $0.status == "D" })
        let addition = try XCTUnwrap(snapshot.unstaged.first { $0.status == "U" })
        let deletedPreview = try XCTUnwrap(client.preview(for: deletion))
        let addedPreview = try XCTUnwrap(client.preview(for: addition))
        defer {
            deletedPreview.removeTemporaryFiles()
            addedPreview.removeTemporaryFiles()
        }

        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(deletedPreview.old?.url)),
            deletedContents
        )
        XCTAssertNil(deletedPreview.new)
        XCTAssertNil(addedPreview.old)
        XCTAssertEqual(addedPreview.new?.url, addedURL.resolvingSymlinksInPath())
        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(addedPreview.new?.url)),
            addedContents
        )
    }

    func testCommitRenamePreviewUsesParentAndCommitBlobs() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let oldURL = repositoryURL.appendingPathComponent("old-name.dat")
        let newURL = repositoryURL.appendingPathComponent("new-name.dat")
        let contents = Data([0x00, 0x10, 0x20])
        try contents.write(to: oldURL)
        try client.stageAll()
        _ = try client.commit(message: "Add old name")
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        try client.stageAll()
        _ = try client.commit(message: "Rename binary")
        let commitHash = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rename = try XCTUnwrap(client.commitFiles(hash: commitHash).first)

        let preview = try XCTUnwrap(
            client.commitFilePreview(hash: commitHash, file: rename)
        )
        defer { preview.removeTemporaryFiles() }

        XCTAssertEqual(rename.status, "R")
        XCTAssertEqual(preview.old?.url.lastPathComponent, "old-name.dat")
        XCTAssertEqual(preview.new?.url.lastPathComponent, "new-name.dat")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preview.old?.url)), contents)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preview.new?.url)), contents)
    }

    @MainActor
    func testBinaryChangeDefaultsToPreviewAndRestoresChosenMode() async throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("preview.dat")
        try Data([0x00, 0x01]).write(to: fileURL)
        try client.stageAll()
        _ = try client.commit(message: "Add preview")
        try Data([0x00, 0x02]).write(to: fileURL)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.select(try XCTUnwrap(model.unstaged.first))
        let deadline = Date().addingTimeInterval(3)
        while model.isDetailLoading, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertNotNil(model.gitFilePreview)
        XCTAssertEqual(model.gitFileDetailMode, .preview)
        model.setGitFileDetailMode(.diff)
        model.setWorkspaceMode(.fileEditor)
        model.setWorkspaceMode(.sourceControl)
        XCTAssertEqual(model.gitFileDetailMode, .diff)
        XCTAssertNotNil(model.gitFilePreview)
    }

    func testUnstageRenameRestoresBothSidesToTheWorkingTree() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let originalURL = repositoryURL.appendingPathComponent("original.txt")
        let renamedURL = repositoryURL.appendingPathComponent("renamed.txt")
        try "renamed contents\n".write(
            to: originalURL,
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Add original file")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        try client.stageAll()

        let rename = try XCTUnwrap(client.snapshot().staged.first)
        XCTAssertEqual(rename.status, "R")
        XCTAssertEqual(rename.path, "renamed.txt")
        XCTAssertEqual(rename.previousPath, "original.txt")

        try client.unstage(rename.path, previousPath: rename.previousPath)

        let snapshot = try client.snapshot()
        XCTAssertTrue(snapshot.staged.isEmpty)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: snapshot.unstaged.map { ($0.path, $0.status) }),
            ["original.txt": "D", "renamed.txt": "U"]
        )
    }

    func testDiscardRestoresTrackedFileAndDeletesUntrackedFile() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let trackedURL = repositoryURL.appendingPathComponent("tracked.txt")
        try "original\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Add tracked file")

        try "changed\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try client.discard("tracked.txt", isUntracked: false)
        XCTAssertEqual(try String(contentsOf: trackedURL, encoding: .utf8), "original\n")

        let untrackedURL = repositoryURL.appendingPathComponent("untracked.txt")
        try "temporary\n".write(to: untrackedURL, atomically: true, encoding: .utf8)
        try client.discard("untracked.txt", isUntracked: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: untrackedURL.path))
        XCTAssertTrue(try client.snapshot().unstaged.isEmpty)
    }

    func testDiscardAllChangesResetsIndexAndDeletesUntrackedFiles() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let trackedURL = repositoryURL.appendingPathComponent("tracked.txt")
        try "original\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Add tracked file")

        try "staged\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        try "unstaged\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        let untrackedURL = repositoryURL.appendingPathComponent("untracked.txt")
        try "temporary\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

        try client.discardAllChanges()

        let snapshot = try client.snapshot()
        XCTAssertTrue(snapshot.staged.isEmpty)
        XCTAssertTrue(snapshot.unstaged.isEmpty)
        XCTAssertEqual(try String(contentsOf: trackedURL, encoding: .utf8), "original\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: untrackedURL.path))
    }

    func testDiscardAllUnstagedChangesKeepsStagedChanges() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let trackedURL = repositoryURL.appendingPathComponent("tracked.txt")
        try "original\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Add tracked file")

        try "staged\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        try "unstaged\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        let untrackedURL = repositoryURL.appendingPathComponent("untracked.txt")
        try "temporary\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

        try client.discardAllUnstagedChanges()

        let snapshot = try client.snapshot()
        XCTAssertEqual(snapshot.staged.map(\.path), ["tracked.txt"])
        XCTAssertTrue(snapshot.unstaged.isEmpty)
        XCTAssertEqual(try String(contentsOf: trackedURL, encoding: .utf8), "staged\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: untrackedURL.path))
    }

    func testResetModesMoveBranchAndHandleWorkingTree() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("file.txt")
        try "one\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "First commit")
        let baseHash = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try "two\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Second commit")

        try client.reset(to: baseHash, mode: .soft)
        var head = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(head, baseHash)
        var snapshot = try client.snapshot()
        XCTAssertEqual(snapshot.staged.map(\.path), ["file.txt"])
        XCTAssertTrue(snapshot.unstaged.isEmpty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "two\n")

        _ = try client.commit(message: "Second commit again")
        try client.reset(to: baseHash, mode: .mixed)
        head = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(head, baseHash)
        snapshot = try client.snapshot()
        XCTAssertTrue(snapshot.staged.isEmpty)
        XCTAssertEqual(snapshot.unstaged.map(\.path), ["file.txt"])
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "two\n")

        try client.stageAll()
        _ = try client.commit(message: "Second commit once more")
        try client.reset(to: baseHash, mode: .hard)
        head = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(head, baseHash)
        snapshot = try client.snapshot()
        XCTAssertTrue(snapshot.staged.isEmpty)
        XCTAssertTrue(snapshot.unstaged.isEmpty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "one\n")
    }

    func testStashCanIncludeUntrackedFilesAndMessage() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let trackedURL = repositoryURL.appendingPathComponent("tracked.txt")
        try "original\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Add tracked file")

        try "changed\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        let untrackedURL = repositoryURL.appendingPathComponent("untracked.txt")
        try "temporary\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

        _ = try client.stash(message: "Kvist test stash", includeUntracked: true)

        XCTAssertTrue(try client.snapshot().staged.isEmpty)
        XCTAssertTrue(try client.snapshot().unstaged.isEmpty)
        XCTAssertTrue(try git(["stash", "list", "--format=%s"]).contains("Kvist test stash"))

        try git(["stash", "pop"])
        XCTAssertEqual(try String(contentsOf: trackedURL, encoding: .utf8), "changed\n")
        XCTAssertEqual(try String(contentsOf: untrackedURL, encoding: .utf8), "temporary\n")
    }

    @MainActor
    func testDiscardClosesSelectedDiffPanel() async throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("selected.txt")
        try "original\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Add selected file")
        try "changed\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        let change = try XCTUnwrap(model.unstaged.first)
        model.select(change)
        XCTAssertTrue(model.isDiffPanelPresented)

        await model.discard(change)

        XCTAssertNil(model.selectedChange)
        XCTAssertFalse(model.isDiffPanelPresented)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.unstaged.isEmpty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original\n")
    }

    @MainActor
    func testConcurrentStageRequestsAreQueuedWithoutBlockingTheRepository() async throws {
        let firstURL = repositoryURL.appendingPathComponent("first.txt")
        let secondURL = repositoryURL.appendingPathComponent("second.txt")
        try "first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        let first = try XCTUnwrap(model.unstaged.first(where: { $0.path == "first.txt" }))
        let second = try XCTUnwrap(model.unstaged.first(where: { $0.path == "second.txt" }))

        async let stageFirst: Void = model.stage(first)
        async let stageSecond: Void = model.stage(second)
        await Task.yield()
        XCTAssertFalse(model.isBusy)
        _ = await (stageFirst, stageSecond)

        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.hasPendingChangeOperations)
        XCTAssertTrue(model.unstaged.isEmpty)
        XCTAssertEqual(Set(model.staged.map(\.path)), ["first.txt", "second.txt"])

        let reconciled = try GitClient(repositoryURL: repositoryURL).workingTreeSnapshot()
        XCTAssertTrue(reconciled.unstaged.isEmpty)
        XCTAssertEqual(Set(reconciled.staged.map(\.path)), ["first.txt", "second.txt"])
    }

    func testPathsWithSpacesAreNotQuotedByStatusParser() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("notes with spaces.txt")
        try "first\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let untracked = try XCTUnwrap(client.snapshot().unstaged.first)
        XCTAssertEqual(untracked.path, "notes with spaces.txt")

        try client.stage(untracked.path)
        let staged = try XCTUnwrap(client.snapshot().staged.first)
        XCTAssertEqual(staged.path, "notes with spaces.txt")
        XCTAssertTrue(try client.diff(for: staged).contains("+first"))
    }

    func testUnmergedStatusPairsAreSingleConflictChanges() {
        let client = GitClient(repositoryURL: repositoryURL)
        let pairs = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        let output = pairs.enumerated()
            .map { index, pair in "\(pair) conflict-\(index).txt" }
            .joined(separator: "\0") + "\0"

        let parsed = client.parseStatus(output)

        XCTAssertTrue(parsed.staged.isEmpty)
        XCTAssertEqual(parsed.unstaged.count, pairs.count)
        XCTAssertTrue(parsed.unstaged.allSatisfy {
            $0.area == .unstaged && $0.status == "!"
        })
    }

    func testPorcelainV2ParsesBranchTrackingRenameAndMixedChanges() {
        let client = GitClient(repositoryURL: repositoryURL)
        let firstHash = String(repeating: "1", count: 40)
        let secondHash = String(repeating: "2", count: 40)
        let output = statusFixture([
            "# branch.oid \(firstHash)",
            "# branch.head feature/performance",
            "# branch.upstream origin/feature/performance",
            "# branch.ab +12 -3",
            "1 MM N... 100644 100644 100644 \(firstHash) \(secondHash) Sources/App.swift",
            "2 R. N... 100644 100644 100644 \(secondHash) \(secondHash) R100 Sources/New Name.swift",
            "Sources/Old Name.swift",
            "? notes with spaces.txt"
        ])

        let parsed = client.parseRepositoryStatus(output)

        XCTAssertEqual(parsed.branch, "feature/performance")
        XCTAssertEqual(parsed.headHash, firstHash)
        XCTAssertEqual(parsed.upstreamName, "origin/feature/performance")
        XCTAssertTrue(parsed.hasUpstream)
        XCTAssertEqual(parsed.ahead, 12)
        XCTAssertEqual(parsed.behind, 3)
        XCTAssertEqual(Set(parsed.workingTree.staged), Set([
            FileChange(path: "Sources/App.swift", status: "M", area: .staged),
            FileChange(
                path: "Sources/New Name.swift",
                previousPath: "Sources/Old Name.swift",
                status: "R",
                area: .staged
            )
        ]))
        XCTAssertEqual(Set(parsed.workingTree.unstaged), Set([
            FileChange(path: "Sources/App.swift", status: "M", area: .unstaged),
            FileChange(path: "notes with spaces.txt", status: "U", area: .unstaged)
        ]))
    }

    func testPorcelainV2ParsesUnbornAndDetachedHeads() {
        let client = GitClient(repositoryURL: repositoryURL)
        let unborn = client.parseRepositoryStatus(statusFixture([
            "# branch.oid (initial)",
            "# branch.head main",
            "? README.md"
        ]))

        XCTAssertEqual(unborn.branch, "main")
        XCTAssertNil(unborn.headHash)
        XCTAssertFalse(unborn.hasUpstream)
        XCTAssertEqual(unborn.workingTree.unstaged, [
            FileChange(path: "README.md", status: "U", area: .unstaged)
        ])

        let hash = String(repeating: "a", count: 40)
        let detached = client.parseRepositoryStatus(statusFixture([
            "# branch.oid \(hash)",
            "# future.extension ignored",
            "# branch.head (detached)"
        ]))

        XCTAssertEqual(detached.branch, "detached HEAD")
        XCTAssertEqual(detached.headHash, hash)
        XCTAssertTrue(detached.workingTree.staged.isEmpty)
        XCTAssertTrue(detached.workingTree.unstaged.isEmpty)

        let parenthesizedBranch = client.parseRepositoryStatus(statusFixture([
            "# branch.oid \(hash)",
            "# branch.head (weird)"
        ]))
        XCTAssertEqual(parenthesizedBranch.branch, "(weird)")
    }

    func testPorcelainV2DoesNotTreatMissingTrackingRefAsAvailable() {
        let client = GitClient(repositoryURL: repositoryURL)
        let parsed = client.parseRepositoryStatus(statusFixture([
            "# branch.oid \(String(repeating: "a", count: 40))",
            "# branch.head main",
            "# branch.upstream missing"
        ]))

        XCTAssertEqual(parsed.upstreamName, "missing")
        XCTAssertFalse(parsed.hasUpstream)
    }

    func testSnapshotResolvesFullUpstreamWhenDisplayNamesCollide() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "initial\n".write(
            to: repositoryURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Initial commit")
        try git(["remote", "add", "origin", repositoryURL.path])
        try git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        try git(["branch", "origin/main", "HEAD"])
        try git(["config", "branch.main.remote", "origin"])
        try git(["config", "branch.main.merge", "refs/heads/main"])

        let snapshot = try client.snapshot()

        XCTAssertTrue(snapshot.hasUpstream)
        XCTAssertEqual(snapshot.upstreamReference?.id, "refs/remotes/origin/main")
        XCTAssertEqual(snapshot.upstreamReference?.kind, .remoteBranch)
    }

    func testSnapshotRejectsConfiguredButMissingUpstream() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "initial\n".write(
            to: repositoryURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Initial commit")
        try git(["config", "branch.main.remote", "."])
        try git(["config", "branch.main.merge", "refs/heads/missing"])

        let snapshot = try client.snapshot()

        XCTAssertFalse(snapshot.hasUpstream)
        XCTAssertNil(snapshot.upstreamReference)
        XCTAssertEqual(snapshot.ahead, 0)
        XCTAssertEqual(snapshot.behind, 0)
    }

    func testSnapshotPreservesBranchNamedDetachedSentinel() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "initial\n".write(
            to: repositoryURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Initial commit")
        try git(["branch", "-m", "(detached)"])

        XCTAssertEqual(try client.snapshot().branch, "(detached)")
    }

    func testSnapshotSupportsCustomUpstreamNamespace() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "initial\n".write(
            to: repositoryURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Initial commit")
        try git(["update-ref", "refs/custom/up", "HEAD"])
        try git(["config", "branch.main.remote", "."])
        try git(["config", "branch.main.merge", "refs/custom/up"])

        let snapshot = try client.snapshot()

        XCTAssertTrue(snapshot.hasUpstream)
        XCTAssertEqual(snapshot.upstreamReference?.id, "refs/custom/up")
        XCTAssertEqual(snapshot.upstreamReference?.kind, .other)
    }

    func testPorcelainV2MapsUnmergedRecordsToConflicts() {
        let client = GitClient(repositoryURL: repositoryURL)
        let pairs = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        let hashes = (1...3).map { String(repeating: String($0), count: 40) }
        let records = pairs.enumerated().map { index, pair in
            "u \(pair) N... 100644 100644 100644 100644 \(hashes[0]) \(hashes[1]) \(hashes[2]) conflict-\(index).txt"
        }

        let parsed = client.parseRepositoryStatus(statusFixture(records))

        XCTAssertTrue(parsed.workingTree.staged.isEmpty)
        XCTAssertEqual(parsed.workingTree.unstaged.count, pairs.count)
        XCTAssertTrue(parsed.workingTree.unstaged.allSatisfy {
            $0.status == "!" && $0.area == .unstaged
        })
    }

    func testGitCommandsUseStableNoninteractiveEnvironment() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let hookURL = repositoryURL.appendingPathComponent(".git/hooks/pre-commit")
        try "staged\n".write(
            to: repositoryURL.appendingPathComponent("environment.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        try """
        #!/bin/sh
        check_environment() {
          if [ "$1" != "$2" ]; then
            echo "$3 was '$1', expected '$2'"
            exit "$4"
          fi
        }
        check_environment "$LC_ALL" "C" "LC_ALL" 51
        check_environment "$LANG" "C" "LANG" 52
        check_environment "$GIT_TERMINAL_PROMPT" "0" "GIT_TERMINAL_PROMPT" 53
        check_environment "$GCM_INTERACTIVE" "Never" "GCM_INTERACTIVE" 54
        check_environment "$GIT_SEQUENCE_EDITOR" "true" "GIT_SEQUENCE_EDITOR" 55
        check_environment "$GIT_MERGE_AUTOEDIT" "no" "GIT_MERGE_AUTOEDIT" 56
        if IFS= read -r input; then
          echo "Git hook received unexpected standard input"
          exit 57
        fi
        """.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookURL.path
        )

        XCTAssertNoThrow(try client.commit(message: "Verify Git environment"))
    }

    func testSnapshotCollapsesUntrackedDirectoryContents() throws {
        let generatedDirectory = repositoryURL.appendingPathComponent(
            "generated",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: generatedDirectory,
            withIntermediateDirectories: true
        )
        for index in 0..<100 {
            try "generated\n".write(
                to: generatedDirectory.appendingPathComponent("file-\(index).txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        let snapshot = try GitClient(repositoryURL: repositoryURL).snapshot()

        XCTAssertEqual(snapshot.unstaged.count, 1)
        XCTAssertEqual(snapshot.unstaged.first?.path, "generated/")
        XCTAssertEqual(snapshot.unstaged.first?.status, "U")
        let directory = try XCTUnwrap(snapshot.unstaged.first)
        XCTAssertEqual(
            try GitClient(repositoryURL: repositoryURL).diff(for: directory),
            "This untracked directory is shown as one item. Stage it to inspect per-file diffs."
        )
    }

    func testRemoteCheckoutRejectsDivergentSameNamedLocalBranch() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "base\n".write(
            to: repositoryURL.appendingPathComponent("base.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Base")

        try git(["checkout", "-b", "feature"])
        try "local\n".write(
            to: repositoryURL.appendingPathComponent("local.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Local feature")

        try git(["checkout", "main"])
        try "remote\n".write(
            to: repositoryURL.appendingPathComponent("remote.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Remote feature")
        let remoteHash = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try git(["update-ref", "refs/remotes/upstream/feature", remoteHash])
        let remote = try XCTUnwrap(client.references().first {
            $0.kind == .remoteBranch && $0.name == "upstream/feature"
        })

        XCTAssertThrowsError(try client.checkout(reference: remote)) { error in
            XCTAssertTrue(error.localizedDescription.contains("different commit"))
        }
        XCTAssertEqual(
            try git(["branch", "--show-current"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "main"
        )

        try git(["branch", "-f", "feature", remoteHash])
        XCTAssertNoThrow(try client.checkout(reference: remote))
        XCTAssertEqual(
            try git(["branch", "--show-current"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "feature"
        )
    }

    func testGraphUsesParentsAndMarksTheRealHead() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "base\n".write(
            to: repositoryURL.appendingPathComponent("base.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Base")

        try git(["checkout", "-b", "feature/graph"])
        try "feature\n".write(
            to: repositoryURL.appendingPathComponent("feature.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Feature")

        try git(["checkout", "main"])
        try "main\n".write(
            to: repositoryURL.appendingPathComponent("main.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Main")
        try git(["merge", "--no-ff", "feature/graph", "-m", "Merge feature"])
        try git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        try git([
            "symbolic-ref",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/main"
        ])

        let snapshot = try client.snapshot()
        let headHash = try XCTUnwrap(snapshot.headHash)
        let main = try XCTUnwrap(snapshot.references.first {
            $0.kind == .localBranch && $0.name == "main"
        })
        let feature = try XCTUnwrap(snapshot.references.first {
            $0.kind == .localBranch && $0.name == "feature/graph"
        })
        let remoteHead = try XCTUnwrap(snapshot.references.first {
            $0.name == "origin/HEAD"
        })
        let headRow = try XCTUnwrap(snapshot.graph.first(where: { $0.commit.hash == headHash }))
        let featureRow = try XCTUnwrap(snapshot.graph.first(where: {
            $0.commit.subject == "Feature"
        }))

        XCTAssertEqual(headRow.kind, .head)
        XCTAssertEqual(remoteHead.symbolicTarget, "refs/remotes/origin/main")
        XCTAssertTrue(main.isRemoteDefaultBranch(in: snapshot.references))
        XCTAssertFalse(feature.isRemoteDefaultBranch(in: snapshot.references))
        XCTAssertEqual(headRow.commit.parentHashes.count, 2)
        XCTAssertTrue(headRow.commit.references.contains(where: {
            $0.kind == .localBranch && $0.name == "main" && $0.isHead
        }))
        XCTAssertTrue(headRow.commit.references.contains(where: {
            $0.kind == .remoteBranch && $0.name == "origin/main"
        }))
        XCTAssertTrue(featureRow.commit.references.contains(where: {
            $0.kind == .localBranch && $0.name == "feature/graph"
        }))
        XCTAssertGreaterThanOrEqual(headRow.outputLanes.count, 2)
        XCTAssertEqual(Set(snapshot.graph.map(\.id)).count, snapshot.graph.count)
    }

    func testGraphLayoutCollapsesStashInternalCommits() {
        let stashReference = GitReference(
            id: "refs/stash",
            name: "refs/stash",
            kind: .other,
            isHead: false
        )
        let stash = CommitInfo(
            hash: "stash",
            shortHash: "stash",
            parentHashes: ["head", "index"],
            author: "Test",
            relativeDate: "now",
            references: [stashReference],
            subject: "On main: WIP"
        )
        let index = commit(
            hash: "index",
            parents: ["head"],
            subject: "index on main: head Head"
        )
        let head = commit(hash: "head", parents: [], subject: "Head")

        let rows = GraphLayout.rows(
            commits: [stash, index, head],
            headHash: "head"
        )

        XCTAssertEqual(rows.map(\.id), ["stash", "head"])
        XCTAssertEqual(rows[0].commit.parentHashes, ["head"])
        XCTAssertEqual(rows[0].outputLanes.map(\.id), ["head"])
        XCTAssertTrue(rows[0].commit.isStash)
    }

    func testGraphLayoutDoesNotAssumeFirstCommitIsHead() {
        let other = commit(hash: "other", parents: ["base"], subject: "Other")
        let head = commit(hash: "head", parents: ["base"], subject: "Head")
        let base = commit(hash: "base", parents: [], subject: "Base")

        let rows = GraphLayout.rows(commits: [other, head, base], headHash: "head")

        XCTAssertEqual(rows[0].kind, .node)
        XCTAssertEqual(rows[1].kind, .head)
    }

    func testGraphTopologyAllocatesTrailingSpaceForDisconnectedRootNode() {
        let head = commit(hash: "head", parents: ["base"], subject: "Head")
        let checkpoint = commit(
            hash: "checkpoint",
            parents: [],
            subject: "Internal checkpoint"
        )
        let base = commit(hash: "base", parents: [], subject: "Base")
        let rows = GraphLayout.rows(
            commits: [head, checkpoint, base],
            headHash: "head"
        )
        let checkpointRow = rows[1]
        let laneWidth: CGFloat = 11
        let nodeIndex = GraphTopologyMetrics.nodeIndex(for: checkpointRow)
        let nodeCenterX = laneWidth * CGFloat(nodeIndex + 1)
        let width = GraphTopologyMetrics.width(
            for: checkpointRow,
            laneWidth: laneWidth
        )

        XCTAssertEqual(checkpointRow.inputLanes.count, 1)
        XCTAssertEqual(checkpointRow.outputLanes.count, 1)
        XCTAssertGreaterThanOrEqual(width, nodeCenterX + 5)
    }

    func testGraphLayoutPagesPreserveWholeHistoryTopologyAndColors() {
        let head = commit(hash: "head", parents: ["main", "side"], subject: "Merge")
        let side = commit(hash: "side", parents: ["base"], subject: "Side")
        let main = commit(hash: "main", parents: ["base"], subject: "Main")
        let base = commit(hash: "base", parents: [], subject: "Base")
        let commits = [head, side, main, base]

        let whole = GraphLayout.rows(commits: commits, headHash: "head")
        let first = GraphLayout.page(
            commits: Array(commits.prefix(2)),
            headHash: "head",
            initialState: GraphLayoutState()
        )
        let second = GraphLayout.page(
            commits: Array(commits.dropFirst(2)),
            headHash: "head",
            initialState: first.state
        )

        XCTAssertEqual(first.rows + second.rows, whole)
    }

    func testHistoryPageFrontierMatchesSingleDateOrderedTraversal() throws {
        let fileURL = repositoryURL.appendingPathComponent("history.txt")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["add", "history.txt"])
        try git(["commit", "-m", "Base"])
        try git(["checkout", "-b", "side"])
        try "side one\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["commit", "-am", "Side one"])
        try "side two\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["commit", "-am", "Side two"])
        try git(["checkout", "main"])
        let mainURL = repositoryURL.appendingPathComponent("main.txt")
        try "main one\n".write(to: mainURL, atomically: true, encoding: .utf8)
        try git(["add", "main.txt"])
        try git(["commit", "-m", "Main one"])
        try "main two\n".write(to: mainURL, atomically: true, encoding: .utf8)
        try git(["commit", "-am", "Main two"])
        try git(["merge", "--no-ff", "side", "-m", "Merge side"])

        let headHash = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let client = GitClient(repositoryURL: repositoryURL)
        let whole = try client.historyPage(
            offset: 0,
            count: 50,
            scope: .current,
            remoteReferenceID: nil,
            knownHeadHash: headHash,
            layoutState: GraphLayoutState(),
            referencesByCommitHash: [:]
        )

        var state = GraphLayoutState()
        var offset = 0
        var pagedRows: [GraphRow] = []
        repeat {
            let page = try client.historyPage(
                offset: offset,
                count: 2,
                scope: .current,
                remoteReferenceID: nil,
                knownHeadHash: headHash,
                layoutState: state,
                referencesByCommitHash: [:]
            )
            pagedRows.append(contentsOf: page.rows)
            state = page.layoutState
            offset = page.nextOffset
            if !page.hasMore { break }
        } while true

        XCTAssertEqual(pagedRows.map(\.commit.hash), whole.rows.map(\.commit.hash))
        XCTAssertEqual(pagedRows.map(\.commit.parentHashes), whole.rows.map(\.commit.parentHashes))
        XCTAssertEqual(pagedRows.map(\.kind), whole.rows.map(\.kind))
        XCTAssertEqual(pagedRows.map(\.inputLanes), whole.rows.map(\.inputLanes))
        XCTAssertEqual(pagedRows.map(\.outputLanes), whole.rows.map(\.outputLanes))
    }

    func testReflogHistoryListsEntriesInReflogOrder() throws {
        let fileURL = repositoryURL.appendingPathComponent("reflog.txt")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["add", "reflog.txt"])
        try git(["commit", "-m", "Base"])
        try "two\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["commit", "-am", "Two"])
        try git(["checkout", "-b", "side"])
        try "side\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["commit", "-am", "Side"])
        try git(["checkout", "main"])
        try git(["reset", "--hard", "HEAD"])

        let headHash = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedHashes = try git([
            "log", "--walk-reflogs", "--pretty=format:%H", "HEAD"
        ]).split(whereSeparator: \.isNewline).map(String.init)
        let expectedParents = try git(["rev-parse", "\(headHash)^"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let page = try GitClient(repositoryURL: repositoryURL).historyPage(
            offset: 0,
            count: 50,
            scope: .reflog,
            remoteReferenceID: nil,
            knownHeadHash: headHash,
            layoutState: GraphLayoutState(),
            referencesByCommitHash: [:]
        )

        XCTAssertEqual(page.rows.map(\.commit.hash), expectedHashes)
        XCTAssertGreaterThan(
            expectedHashes.count,
            Set(expectedHashes).count,
            "Scenario should revisit commits so identity needs selectors"
        )
        XCTAssertEqual(
            Set(page.rows.map(\.id)).count,
            page.rows.count,
            "Reflog rows need unique identifiers"
        )
        XCTAssertEqual(
            page.rows.map(\.commit.reflogSelector),
            (0..<expectedHashes.count).map { "HEAD@{\($0)}" }
        )
        XCTAssertEqual(page.rows.first?.kind, .head)
        XCTAssertTrue(page.rows.dropFirst().allSatisfy { $0.kind == .node })
        XCTAssertEqual(page.rows.first?.commit.displaySubject, "reset: moving to HEAD")
        XCTAssertEqual(page.rows.last?.commit.displaySubject, "commit (initial): Base")
        XCTAssertEqual(
            page.rows.first?.commit.parentHashes,
            [expectedParents],
            "Rows must keep the commit's real parents"
        )

        XCTAssertEqual(page.rows.first?.inputLanes, [])
        for (index, row) in page.rows.enumerated() {
            if index > 0 {
                XCTAssertEqual(row.inputLanes.map(\.id), [row.commit.hash])
            }
            if index + 1 < page.rows.count {
                XCTAssertEqual(
                    row.outputLanes.map(\.id),
                    [page.rows[index + 1].commit.hash],
                    "Each entry should chain to the next reflog entry"
                )
            }
        }
        XCTAssertEqual(page.rows.last?.outputLanes, [])
        XCTAssertFalse(page.hasMore)
    }

    func testReflogHistoryPaginationMatchesWholeLog() throws {
        let fileURL = repositoryURL.appendingPathComponent("pages.txt")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["add", "pages.txt"])
        try git(["commit", "-m", "Base"])
        for index in 1...4 {
            try "content \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try git(["commit", "-am", "Commit \(index)"])
        }
        let headHash = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let client = GitClient(repositoryURL: repositoryURL)

        let whole = try client.historyPage(
            offset: 0,
            count: 50,
            scope: .reflog,
            remoteReferenceID: nil,
            knownHeadHash: headHash,
            layoutState: GraphLayoutState(),
            referencesByCommitHash: [:]
        )

        var state = GraphLayoutState()
        var offset = 0
        var pagedRows: [GraphRow] = []
        repeat {
            let page = try client.historyPage(
                offset: offset,
                count: 2,
                scope: .reflog,
                remoteReferenceID: nil,
                knownHeadHash: headHash,
                layoutState: state,
                referencesByCommitHash: [:]
            )
            pagedRows.append(contentsOf: page.rows)
            state = page.layoutState
            offset = page.nextOffset
            if !page.hasMore { break }
        } while true

        XCTAssertEqual(pagedRows.map(\.id), whole.rows.map(\.id))
        XCTAssertEqual(pagedRows.map(\.kind), whole.rows.map(\.kind))
        XCTAssertEqual(pagedRows.map(\.inputLanes), whole.rows.map(\.inputLanes))
        XCTAssertEqual(pagedRows.map(\.outputLanes), whole.rows.map(\.outputLanes))
        XCTAssertEqual(
            pagedRows.map(\.commit.displaySubject),
            whole.rows.map(\.commit.displaySubject)
        )
    }

    func testAllHistoryIncludesUnreferencedDetachedHead() throws {
        let fileURL = repositoryURL.appendingPathComponent("detached.txt")
        try "detached\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["add", "detached.txt"])
        try git(["commit", "-m", "Detached commit"])
        let headHash = try git(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try git(["checkout", "--detach"])
        try git(["branch", "-D", "main"])

        let snapshot = try GitClient(repositoryURL: repositoryURL).snapshot()

        XCTAssertEqual(snapshot.headHash, headHash)
        XCTAssertEqual(snapshot.graph.first?.commit.hash, headHash)
    }

    func testGraphLayoutUsesPurpleForOriginHistory() {
        let local = GitReference(
            id: "refs/heads/main",
            name: "main",
            kind: .localBranch,
            isHead: true
        )
        let origin = GitReference(
            id: "refs/remotes/origin/main",
            name: "origin/main",
            kind: .remoteBranch,
            isHead: false
        )
        let head = CommitInfo(
            hash: "head",
            shortHash: "head",
            parentHashes: ["origin"],
            author: "Test",
            relativeDate: "now",
            references: [local],
            subject: "Head"
        )
        let originCommit = CommitInfo(
            hash: "origin",
            shortHash: "origin",
            parentHashes: ["base"],
            author: "Test",
            relativeDate: "now",
            references: [origin],
            subject: "Origin"
        )
        let base = commit(hash: "base", parents: [], subject: "Base")

        let rows = GraphLayout.rows(
            commits: [head, originCommit, base],
            headHash: "head",
            remoteReferenceID: origin.id
        )

        XCTAssertEqual(rows[0].outputLanes.first?.color, .current)
        XCTAssertEqual(rows[1].inputLanes.first?.color, .current)
        XCTAssertEqual(rows[1].outputLanes.first?.color, .remote)
        XCTAssertEqual(rows[2].inputLanes.first?.color, .remote)
    }

    func testGraphLayoutKeepsCurrentColorWhenHeadAlsoMatchesOrigin() {
        let local = GitReference(
            id: "refs/heads/main",
            name: "main",
            kind: .localBranch,
            isHead: true
        )
        let origin = GitReference(
            id: "refs/remotes/origin/main",
            name: "origin/main",
            kind: .remoteBranch,
            isHead: false
        )
        let head = CommitInfo(
            hash: "head",
            shortHash: "head",
            parentHashes: ["base"],
            author: "Test",
            relativeDate: "now",
            references: [local, origin],
            subject: "Head"
        )
        let base = commit(hash: "base", parents: [], subject: "Base")

        let rows = GraphLayout.rows(
            commits: [head, base],
            headHash: "head",
            remoteReferenceID: origin.id
        )

        XCTAssertEqual(rows[0].outputLanes.first?.color, .current)
        XCTAssertEqual(rows[1].inputLanes.first?.color, .current)
    }

    func testDisconnectedRootPreservesUnrelatedActiveLane() {
        let branchTip = commit(hash: "tip", parents: ["root-a"], subject: "Tip")
        let unrelatedRoot = commit(hash: "root-b", parents: [], subject: "Other root")
        let branchRoot = commit(hash: "root-a", parents: [], subject: "Branch root")

        let rows = GraphLayout.rows(
            commits: [branchTip, unrelatedRoot, branchRoot],
            headHash: "tip"
        )

        XCTAssertEqual(rows[1].outputLanes.map(\.id), ["root-a"])
        XCTAssertTrue(rows[2].outputLanes.isEmpty)
    }

    func testRepositoryWatchPathsPointAtTheRealWorktreeAndGitDirectory() throws {
        let paths = try GitClient(repositoryURL: repositoryURL).repositoryWatchPaths()

        XCTAssertTrue(paths.contains(repositoryURL.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(repositoryURL.appendingPathComponent(".git").path))
        XCTAssertTrue(paths.allSatisfy(FileManager.default.fileExists(atPath:)))
    }

    func testRepositoryWatcherReceivesRealWorktreeChanges() throws {
        let changed = expectation(description: "Repository watcher observed a file change")
        let watcher = RepositoryWatcher(paths: [repositoryURL.path]) { paths, fileTreePaths in
            XCTAssertTrue(paths.contains(where: { $0.hasSuffix("live-change.txt") }))
            XCTAssertTrue(fileTreePaths?.contains(where: {
                $0.hasSuffix("live-change.txt")
            }) == true)
            changed.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.25)
        try "live\n".write(
            to: repositoryURL.appendingPathComponent("live-change.txt"),
            atomically: true,
            encoding: .utf8
        )

        wait(for: [changed], timeout: 3)
    }

    func testReadOnlySnapshotDoesNotTriggerItsOwnGitWatcher() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "tracked\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Add tracked file")
        try "tracked\nchanged\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        Thread.sleep(forTimeInterval: 1)

        let selfTriggered = expectation(
            description: "Read-only Git snapshot should not write Git metadata"
        )
        selfTriggered.isInverted = true
        let watcher = RepositoryWatcher(
            paths: [repositoryURL.appendingPathComponent(".git").path]
        ) { _, _ in
            selfTriggered.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.25)
        _ = try client.snapshot()
        wait(for: [selfTriggered], timeout: 1)
    }

    @MainActor
    func testRepositoryModelPublishesExternalGitChangesAutomatically() async throws {
        let preferenceKey = "lastRepositoryPath"
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        defer { UserDefaults.standard.removeObject(forKey: preferenceKey) }

        let model = RepositoryModel()
        await model.openRepository(repositoryURL)
        XCTAssertTrue(model.unstaged.isEmpty)
        RepositoryRefreshMetrics.reset()

        try "external\n".write(
            to: repositoryURL.appendingPathComponent("external-change.txt"),
            atomically: true,
            encoding: .utf8
        )

        let deadline = Date().addingTimeInterval(3)
        while !model.unstaged.contains(where: { $0.path == "external-change.txt" }),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(model.unstaged.contains(where: {
            $0.path == "external-change.txt" && $0.status == "U"
        }))
        XCTAssertEqual(
            RepositoryRefreshMetrics.counts(),
            RepositoryRefreshMetricCounts(
                workingTreeSnapshots: 1,
                fullSnapshots: 0
            )
        )
    }

    @MainActor
    func testRepositoryModelCoalescesWorktreeEventStormIntoOneRefresh() async throws {
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        RepositoryRefreshMetrics.reset()

        let directoryPath = "storm"
        let directoryURL = repositoryURL.appendingPathComponent(
            directoryPath,
            isDirectory: true
        )
        let startedAt = DispatchTime.now().uptimeNanoseconds
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        for index in 0..<100 {
            try Data("storm\n".utf8).write(
                to: directoryURL.appendingPathComponent("file-\(index)")
            )
        }
        let writeMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - startedAt
        ) / 1_000_000
        XCTAssertLessThanOrEqual(writeMilliseconds, 100)

        let deadline = Date().addingTimeInterval(3)
        while !model.unstaged.contains(where: { $0.path == "storm/" }),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        let settleMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - startedAt
        ) / 1_000_000
        XCTAssertTrue(model.unstaged.contains(where: { $0.path == "storm/" }))
        XCTAssertLessThanOrEqual(settleMilliseconds, 450)
        XCTAssertEqual(
            RepositoryRefreshMetrics.counts(),
            RepositoryRefreshMetricCounts(
                workingTreeSnapshots: 1,
                fullSnapshots: 0
            )
        )
    }

    @MainActor
    func testRepositoryModelRefreshesGraphAfterExternalCommit() async throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "one\n".write(
            to: repositoryURL.appendingPathComponent("history.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "One")

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        XCTAssertEqual(model.graph.first?.commit.subject, "One")
        RepositoryRefreshMetrics.reset()

        try "two\n".write(
            to: repositoryURL.appendingPathComponent("history.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Two")

        let deadline = Date().addingTimeInterval(3)
        while model.graph.first?.commit.subject != "Two", Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(model.graph.first?.commit.subject, "Two")
        XCTAssertFalse(model.isBusy)
        XCTAssertGreaterThanOrEqual(
            RepositoryRefreshMetrics.counts().fullSnapshots,
            1
        )

        RepositoryRefreshMetrics.reset()
        try git(["branch", "external-reference"])
        let referenceDeadline = Date().addingTimeInterval(3)
        while !model.references.contains(where: {
            $0.kind == .localBranch && $0.name == "external-reference"
        }), Date() < referenceDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(model.references.contains(where: {
            $0.kind == .localBranch && $0.name == "external-reference"
        }))
        XCTAssertGreaterThanOrEqual(
            RepositoryRefreshMetrics.counts().fullSnapshots,
            1
        )
    }

    @MainActor
    func testRepositoryModelOffersToInitializeAndOpensPlainFolder() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistPlainFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )

        await model.openRepository(folderURL)

        XCTAssertNil(model.repositoryURL)
        XCTAssertEqual(model.repositoryInitializationURL, folderURL.standardizedFileURL)
        XCTAssertNil(model.errorMessage)

        await model.initializeRepository()

        XCTAssertEqual(
            model.repositoryURL?.resolvingSymlinksInPath(),
            folderURL.resolvingSymlinksInPath()
        )
        XCTAssertNil(model.repositoryInitializationURL)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: folderURL.appendingPathComponent(".git").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: folderURL.appendingPathComponent(".gitignore").path
            )
        )
    }

    func testRepositoryInitializationCreatesProjectAwareGitIgnore() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistNodeInit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }
        try "{}\n".write(
            to: folderURL.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        try GitClient.initializeRepository(at: folderURL, createGitIgnore: true)

        let contents = try String(
            contentsOf: folderURL.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        XCTAssertTrue(contents.contains("node_modules/"))
        XCTAssertTrue(contents.contains(".env"))
        XCTAssertTrue(contents.contains(".DS_Store"))
    }

    @MainActor
    func testCleanUnbornRepositoryDoesNotOfferPublish() async {
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )

        await model.openRepository(repositoryURL)

        XCTAssertNil(model.headHash)
        XCTAssertEqual(model.primaryActionTitle, "Commit")
        XCTAssertFalse(model.primaryActionEnabled)
    }

    @MainActor
    func testOpeningRepositoryClearsDraftOnlyForDifferentRoot() async throws {
        let secondRepositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "KvistSecondRepository-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: secondRepositoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: secondRepositoryURL) }
        try GitClient.initializeRepository(
            at: secondRepositoryURL,
            createGitIgnore: false
        )
        let subdirectoryURL = repositoryURL.appendingPathComponent(
            "nested",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: subdirectoryURL,
            withIntermediateDirectories: true
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.commitMessage = "Keep this draft"

        await model.openRepository(subdirectoryURL)
        XCTAssertEqual(model.commitMessage, "Keep this draft")

        await model.openRepository(secondRepositoryURL)
        XCTAssertEqual(model.commitMessage, "")
        XCTAssertEqual(
            model.repositoryURL?.standardizedFileURL,
            secondRepositoryURL.standardizedFileURL
        )
    }

    @MainActor
    func testDetailAndDisclosureFailuresLeaveRetryableState() async throws {
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        let invalidCommit = commit(
            hash: "not-a-commit",
            parents: [],
            subject: "Invalid"
        )
        let deadline = Date().addingTimeInterval(3)

        model.openCommitChanges(invalidCommit)
        while model.detailText == "Loading changes…", Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(
            model.detailText,
            "Could not load these changes. Select the commit again to retry."
        )

        model.errorMessage = nil
        model.toggleCommitExpansion(invalidCommit)
        while model.loadingCommitFileHashes.contains(invalidCommit.hash),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(model.expandedCommitHashes.contains(invalidCommit.hash))
    }

    @MainActor
    func testCommitPushAndSyncPublishBranchesWithoutUpstreams() async throws {
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistCommitActionsOrigin-\(UUID().uuidString).git")
        defer { try? FileManager.default.removeItem(at: bareURL) }
        try git(["init", "--bare", bareURL.path])
        try git(["remote", "add", "origin", bareURL.path])

        let client = GitClient(repositoryURL: repositoryURL)
        try "main\n".write(
            to: repositoryURL.appendingPathComponent("main.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.commitMessage = "Publish main"

        await model.commitAndPush()

        XCTAssertTrue(model.hasUpstream)
        XCTAssertEqual(
            try git(["rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            try git([
                "--git-dir", bareURL.path,
                "rev-parse", "refs/heads/main"
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try git(["checkout", "-b", "sync-branch"])
        try "sync\n".write(
            to: repositoryURL.appendingPathComponent("sync.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        await model.refresh()
        XCTAssertFalse(model.hasUpstream)
        model.commitMessage = "Publish sync branch"

        await model.commitAndSync()

        XCTAssertTrue(model.hasUpstream)
        XCTAssertEqual(model.branch, "sync-branch")
        XCTAssertEqual(
            try git(["rev-parse", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            try git([
                "--git-dir", bareURL.path,
                "rev-parse", "refs/heads/sync-branch"
            ]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testAICommitGeneratorSkipsBrokenCodexCandidateAndReadsStructuredLastMessage() throws {
        let brokenURL = repositoryURL.appendingPathComponent("broken-codex")
        let workingURL = repositoryURL.appendingPathComponent("working-codex")
        try "staged\n".write(
            to: repositoryURL.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try GitClient(repositoryURL: repositoryURL).stageAll()

        try "#!/bin/sh\nexit 1\n".write(
            to: brokenURL,
            atomically: true,
            encoding: .utf8
        )
        try """
        #!/bin/sh
        if [ "$1" = "exec" ] && [ "$2" = "--help" ]; then
          echo "--output-schema --output-last-message"
          exit 0
        fi
        output=""
        model=""
        effort=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --model)
              shift
              model="$1"
              ;;
            --config)
              shift
              effort="$1"
              ;;
            --output-last-message)
              shift
              output="$1"
              ;;
          esac
          shift
        done
        [ "$model" = "gpt-5.6-sol" ] || exit 64
        [ "$effort" = 'model_reasoning_effort=xhigh' ] || exit 65
        input="$(cat)"
        printf '%s' "$input" | grep -q 'Run `git diff --cached --no-ext-diff --no-color`' || exit 66
        printf '%s' "$input" | grep -q 'Ignore every unstaged modification' || exit 67
        printf '%s' "$input" | grep -q 'Emphasize the graph fix' || exit 68
        printf '%s' "$input" | grep -q '+staged' && exit 69
        printf '{"message":"fix: repair graph lanes"}' > "$output"
        printf '{"message":"fix: repair graph lanes"}'
        """ .write(
            to: workingURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: brokenURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: workingURL.path
        )

        let message = try AICommitMessageGenerator(
            configuration: AICommitMessageConfiguration(
                provider: .codex,
                model: AICommitMessageProvider.codex.defaultModel,
                reasoningEffort: .xhigh,
                commandTemplate: AICommitMessageProvider.codex.defaultCommandTemplate
            ),
            candidateURLs: [brokenURL, workingURL]
        ).generate(
            in: repositoryURL,
            userInstructions: "Emphasize the graph fix"
        )

        XCTAssertEqual(message, "fix: repair graph lanes")
    }

    func testAICommitGeneratorReadsClaudeStructuredOutput() throws {
        let claudeURL = repositoryURL.appendingPathComponent("working-claude")
        try "staged\n".write(
            to: repositoryURL.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try GitClient(repositoryURL: repositoryURL).stageAll()

        try """
        #!/bin/sh
        if [ "$1" = "--help" ]; then
          echo "--print --json-schema"
          exit 0
        fi
        model=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --model)
              shift
              model="$1"
              ;;
          esac
          shift
        done
        [ "$model" = "opus" ] || exit 64
        input="$(cat)"
        printf '%s' "$input" | grep -q 'only the staged Git diff' || exit 65
        printf '%s' "$input" | grep -q '+staged' || exit 66
        printf '{"structured_output":{"message":"feat: support Claude messages"}}'
        """ .write(
            to: claudeURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: claudeURL.path
        )

        let message = try AICommitMessageGenerator(
            configuration: AICommitMessageConfiguration(
                provider: .claude,
                model: "opus",
                commandTemplate: AICommitMessageProvider.claude.defaultCommandTemplate
            ),
            candidateURLs: [claudeURL]
        ).generate(in: repositoryURL)

        XCTAssertEqual(message, "feat: support Claude messages")
    }

    func testAICommitGeneratorAcceptsWordySingleLineSubject() throws {
        let codexURL = repositoryURL.appendingPathComponent("wordy-response-codex")
        let expectedMessage = "Add configurable Codex and Claude commit-message generation from staged diffs with model catalogs, reasoning controls, command templates, provider-specific consent and privacy docs, GitHub pull-request links, expanded tests, and Git feature backlog"
        try "staged\n".write(
            to: repositoryURL.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try GitClient(repositoryURL: repositoryURL).stageAll()

        try """
        #!/bin/sh
        if [ "$1" = "exec" ] && [ "$2" = "--help" ]; then
          echo "--output-schema --output-last-message"
          exit 0
        fi
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then
            shift
            output="$1"
          fi
          shift
        done
        printf '%s' '{"message":"\(expectedMessage)"}' > "$output"
        """ .write(
            to: codexURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: codexURL.path
        )

        let message = try AICommitMessageGenerator(
            configuration: AICommitMessageConfiguration(
                provider: .codex,
                model: AICommitMessageProvider.codex.defaultModel,
                reasoningEffort: .xhigh,
                commandTemplate: AICommitMessageProvider.codex.defaultCommandTemplate
            ),
            candidateURLs: [codexURL]
        ).generate(in: repositoryURL)

        XCTAssertGreaterThan(expectedMessage.count, 100)
        XCTAssertEqual(message, expectedMessage)
    }

    func testAICommitGeneratorPreservesInvalidRawResponseForDetails() throws {
        let codexURL = repositoryURL.appendingPathComponent("invalid-response-codex")
        try "staged\n".write(
            to: repositoryURL.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try GitClient(repositoryURL: repositoryURL).stageAll()

        try """
        #!/bin/sh
        if [ "$1" = "exec" ] && [ "$2" = "--help" ]; then
          echo "--output-schema --output-last-message"
          exit 0
        fi
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then
            shift
            output="$1"
          fi
          shift
        done
        printf 'the raw response that failed validation' > "$output"
        """ .write(
            to: codexURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: codexURL.path
        )

        XCTAssertThrowsError(
            try AICommitMessageGenerator(
                configuration: AICommitMessageConfiguration(
                    provider: .codex,
                    model: AICommitMessageProvider.codex.defaultModel,
                    reasoningEffort: .xhigh,
                    commandTemplate: AICommitMessageProvider.codex.defaultCommandTemplate
                ),
                candidateURLs: [codexURL]
            ).generate(in: repositoryURL)
        ) { error in
            guard let aiError = error as? AICommitMessageError,
                  case let .invalidResponse(provider, details) = aiError else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
            XCTAssertEqual(provider, .codex)
            XCTAssertTrue(details?.contains("Raw agent response:") == true)
            XCTAssertTrue(
                details?.contains("the raw response that failed validation") == true
            )
        }
    }

    func testAICommitGeneratorRejectsRepositoriesWithoutStagedChanges() throws {
        XCTAssertThrowsError(
            try AICommitMessageGenerator(candidateURLs: []).generate(in: repositoryURL)
        ) { error in
            guard case AICommitMessageError.noStagedChanges = error else {
                return XCTFail("Expected noStagedChanges, got \(error)")
            }
        }
    }

    private func statusFixture(_ records: [String]) -> String {
        records.joined(separator: "\0") + "\0"
    }

    private func commit(
        hash: String,
        parents: [String],
        subject: String
    ) -> CommitInfo {
        CommitInfo(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            parentHashes: parents,
            author: "Test",
            relativeDate: "now",
            references: [],
            subject: subject
        )
    }

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryURL
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitCommandError(
                command: "git \(arguments.joined(separator: " "))",
                output: output
            )
        }
        return output
    }
}

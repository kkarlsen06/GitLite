import Foundation
import XCTest
@testable import Kvist

final class CommitBackendTests: XCTestCase {
    private var repositoryURL: URL!

    override func setUpWithError() throws {
        repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistCommitTests-\(UUID().uuidString)", isDirectory: true)
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

    func testCommitFilesAndFileDiffHandleRootRenameAndModification() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "first\n".write(
            to: repositoryURL.appendingPathComponent("old name.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Root")
        let rootHash = try headHash()

        let rootFile = try XCTUnwrap(client.commitFiles(hash: rootHash).first)
        XCTAssertEqual(rootFile.path, "old name.txt")
        XCTAssertEqual(rootFile.status, "A")
        XCTAssertTrue(try client.commitFileDiff(hash: rootHash, file: rootFile).contains("+first"))

        try git(["mv", "old name.txt", "new name.txt"])
        _ = try client.commit(message: "Rename")
        let renameHash = try headHash()
        let renamedFile = try XCTUnwrap(client.commitFiles(hash: renameHash).first)

        XCTAssertEqual(renamedFile.status, "R")
        XCTAssertEqual(renamedFile.previousPath, "old name.txt")
        XCTAssertEqual(renamedFile.path, "new name.txt")
        let renameDiff = try client.commitFileDiff(hash: renameHash, file: renamedFile)
        XCTAssertTrue(renameDiff.contains("rename from old name.txt"))
        XCTAssertTrue(renameDiff.contains("rename to new name.txt"))

        try "first\nsecond\n".write(
            to: repositoryURL.appendingPathComponent("new name.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.commit(message: "Modify")
        let modifiedHash = try headHash()
        let modifiedFile = try XCTUnwrap(client.commitFiles(hash: modifiedHash).first)
        XCTAssertEqual(modifiedFile.status, "M")
        XCTAssertTrue(
            try client.commitFileDiff(hash: modifiedHash, file: modifiedFile)
                .contains("+second")
        )
        XCTAssertTrue(try client.commitDiff(hash: modifiedHash).contains("+second"))
    }

    func testCommitMessageReturnsSubjectAndBody() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try "message\n".write(
            to: repositoryURL.appendingPathComponent("message.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        try git([
            "commit",
            "-m", "Subject line",
            "-m", "Body line one.\nBody line two."
        ])

        XCTAssertEqual(
            try client.commitMessage(hash: headHash()),
            "Subject line\n\nBody line one.\nBody line two."
        )
    }

    func testAmendNoEditKeepsPreviousMessageAndAddsStagedChanges() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let fileURL = repositoryURL.appendingPathComponent("amend.txt")
        try "first\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.commit(message: "Keep this message")

        try "first\nsecond\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try client.stageAll()
        _ = try client.amendNoEdit()

        let amendedHash = try headHash()
        XCTAssertEqual(try client.commitMessage(hash: amendedHash), "Keep this message")
        XCTAssertTrue(try client.commitDiff(hash: amendedHash).contains("+second"))
    }

    @MainActor
    func testAmendLoadsPreviousMessageBeforeEditing() async throws {
        try commitFile(
            path: "amend-message.txt",
            contents: "content\n",
            message: "Previous message"
        )
        let originalHash = try headHash()
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )
        await model.openRepository(repositoryURL)

        await model.amend()

        XCTAssertEqual(model.commitMessage, "Previous message")
        XCTAssertTrue(model.isAmendingCommit)
        XCTAssertEqual(model.primaryActionTitle, "Amend Last Commit")
        XCTAssertTrue(model.primaryActionEnabled)
        XCTAssertEqual(try headHash(), originalHash)

        model.commitMessage = "Edited message"
        await model.performPrimaryAction()

        XCTAssertEqual(
            try GitClient(repositoryURL: repositoryURL).commitMessage(hash: headHash()),
            "Edited message"
        )
        XCTAssertFalse(model.isAmendingCommit)
    }

    func testBranchTagReferenceAndCheckoutOperations() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()
        try commitFile(path: "tip.txt", contents: "tip\n", message: "Tip")

        try client.createBranch(name: "topic/test", at: baseHash)
        XCTAssertEqual(try currentBranch(), "topic/test")
        XCTAssertEqual(try headHash(), baseHash)

        try client.createTag(name: "v1.0", at: baseHash, message: "Release 1.0")
        var references = try client.references()
        XCTAssertTrue(references.contains {
            $0.kind == .localBranch && $0.name == "topic/test" && $0.isHead
        })
        XCTAssertTrue(references.contains {
            $0.kind == .tag && $0.name == "v1.0"
        })

        let main = try XCTUnwrap(references.first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        XCTAssertEqual(try currentBranch(), "main")

        try client.checkoutDetached(hash: baseHash)
        XCTAssertEqual(try currentBranch(), "")
        XCTAssertEqual(try headHash(), baseHash)
        try client.checkout(reference: main)

        try client.deleteLocalBranch(name: "topic/test")
        try client.deleteTag(name: "v1.0")
        references = try client.references()
        XCTAssertFalse(references.contains { $0.name == "topic/test" })
        XCTAssertFalse(references.contains { $0.name == "v1.0" })
        XCTAssertThrowsError(try client.createBranch(name: "../bad", at: baseHash))
    }

    func testSafeBranchIntegrationFastForwardsAndRejectsConflicts() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "shared.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try commitFile(path: "shared.txt", contents: "feature\n", message: "Feature")
        let featureTip = try headHash()
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })

        XCTAssertTrue(try client.snapshot().fastForwardReferenceIDs.contains(feature.id))
        try client.integrate(feature, strategy: .fastForward)
        XCTAssertEqual(try headHash(), featureTip)

        _ = try git(["reset", "--hard", baseHash])
        try commitFile(path: "shared.txt", contents: "main\n", message: "Main")
        let mainTip = try headHash()

        XCTAssertThrowsError(try client.integrate(feature, strategy: .merge)) { error in
            XCTAssertTrue(error.localizedDescription.contains("predicts merge conflicts"))
        }
        XCTAssertEqual(try headHash(), mainTip)
        XCTAssertTrue(try client.snapshot().staged.isEmpty)
        XCTAssertTrue(try client.snapshot().unstaged.isEmpty)
    }

    func testConflictedMergeCanKeepCurrentAndIncomingVersions() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "current.txt", contents: "base\n", message: "Base current")
        try commitFile(path: "incoming.txt", contents: "base\n", message: "Base incoming")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try commitFile(path: "current.txt", contents: "feature\n", message: "Feature current")
        try commitFile(path: "incoming.txt", contents: "feature\n", message: "Feature incoming")
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        try commitFile(path: "current.txt", contents: "main\n", message: "Main current")
        try commitFile(path: "incoming.txt", contents: "main\n", message: "Main incoming")
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })

        try client.integrate(feature, strategy: .merge, allowConflicts: true)

        XCTAssertEqual(client.operationInProgress(), .merge)
        let mergeDocument = try client.conflictDocument(for: "current.txt")
        let sideLabels = client.conflictSideLabels(for: .merge, document: mergeDocument)
        XCTAssertEqual(sideLabels, ConflictSideLabels(current: "main", incoming: "feature"))
        let preview = try XCTUnwrap(client.conflictFilePreview(
            for: "current.txt",
            sideLabels: sideLabels
        ))
        defer { preview.removeTemporaryFiles() }
        XCTAssertEqual(
            try preview.old.map { try String(contentsOf: $0.url, encoding: .utf8) },
            "main\n"
        )
        XCTAssertEqual(
            try preview.new.map { try String(contentsOf: $0.url, encoding: .utf8) },
            "feature\n"
        )
        XCTAssertEqual(
            Set(try client.snapshot().unstaged.filter { $0.status == "!" }.map(\.path)),
            Set(["current.txt", "incoming.txt"])
        )

        try client.resolveConflict("current.txt", keeping: .current, during: .merge)
        try client.resolveConflict("incoming.txt", keeping: .incoming, during: .merge)
        XCTAssertTrue(try client.snapshot().unstaged.allSatisfy { $0.status != "!" })

        _ = try client.continueOperation(.merge)

        XCTAssertNil(client.operationInProgress())
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appendingPathComponent("current.txt"),
                encoding: .utf8
            ),
            "main\n"
        )
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appendingPathComponent("incoming.txt"),
                encoding: .utf8
            ),
            "feature\n"
        )
        XCTAssertEqual(
            try git(["rev-list", "--parents", "-n", "1", "HEAD"])
                .split(whereSeparator: \.isWhitespace)
                .count,
            3
        )
    }

    func testUnstagedConflictResolutionCanBeReopened() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "conflict.json", contents: "{\"value\":\"base\"}\n", message: "Base")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try commitFile(
            path: "conflict.json",
            contents: "{\"value\":\"feature\"}\n",
            message: "Feature"
        )
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        try commitFile(
            path: "conflict.json",
            contents: "{\"value\":\"main\"}\n",
            message: "Main"
        )
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })

        try client.integrate(feature, strategy: .merge, allowConflicts: true)
        try client.resolveConflict("conflict.json", keeping: .incoming, during: .merge)
        XCTAssertTrue(try client.workingTreeSnapshot().resolveUndoPaths.contains("conflict.json"))

        try client.unstage("conflict.json")
        let unstaged = try client.workingTreeSnapshot()
        XCTAssertEqual(unstaged.unstaged.first?.status, "M")
        XCTAssertTrue(unstaged.resolveUndoPaths.contains("conflict.json"))

        try client.reopenConflict("conflict.json", during: .merge)
        let reopened = try client.workingTreeSnapshot()
        XCTAssertEqual(reopened.unstaged.first?.status, "!")
        XCTAssertNotNil(try client.conflictDocument(for: "conflict.json"))
    }

    func testModifyDeleteConflictPreviewShowsTheDeletedSide() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "logo.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try git(["rm", "logo.txt"])
        try git(["commit", "-m", "Delete logo"])
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        try commitFile(path: "logo.txt", contents: "updated\n", message: "Update logo")
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })

        try client.integrate(feature, strategy: .merge, allowConflicts: true)

        XCTAssertEqual(client.operationInProgress(), .merge)
        XCTAssertNil(try client.conflictDocument(for: "logo.txt"))
        let labels = client.conflictSideLabels(for: .merge, document: nil)
        let preview = try XCTUnwrap(client.conflictFilePreview(
            for: "logo.txt",
            sideLabels: labels
        ))
        defer { preview.removeTemporaryFiles() }
        XCTAssertEqual(
            try preview.old.map { try String(contentsOf: $0.url, encoding: .utf8) },
            "updated\n"
        )
        XCTAssertNil(preview.new)

        try client.resolveConflict("logo.txt", keeping: .incoming, during: .merge)
        _ = try client.continueOperation(.merge)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("logo.txt").path
        ))
    }

    func testSafeBranchIntegrationRebasesDisjointChanges() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try commitFile(path: "feature.txt", contents: "feature\n", message: "Feature")
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        try commitFile(path: "main.txt", contents: "main\n", message: "Main")

        try client.integrate(feature, strategy: .rebase)

        XCTAssertEqual(try currentBranch(), "main")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("feature.txt").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("main.txt").path
        ))
        XCTAssertEqual(
            try git(["merge-base", "main", "feature"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            try git(["rev-parse", "feature"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testRebasesSelectedLocalBranchOntoAnotherBranch() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try commitFile(path: "feature.txt", contents: "feature\n", message: "Feature")
        let originalFeatureHash = try headHash()
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        try commitFile(path: "main.txt", contents: "main\n", message: "Main")
        let mainHash = try headHash()
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })

        try client.rebase(feature, onto: main)

        XCTAssertEqual(try currentBranch(), "feature")
        XCTAssertNotEqual(try headHash(), originalFeatureHash)
        _ = try git(["merge-base", "--is-ancestor", mainHash, "feature"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("feature.txt").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("main.txt").path
        ))
    }

    func testRebasingSelectedBranchLeavesConflictsReadyToResolve() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "shared.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try commitFile(path: "shared.txt", contents: "feature\n", message: "Feature")
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        try commitFile(path: "shared.txt", contents: "main\n", message: "Main")
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })

        XCTAssertThrowsError(try client.rebase(feature, onto: main))
        XCTAssertEqual(client.operationInProgress(), .rebase)
        XCTAssertEqual(try currentBranch(), "")

        _ = try client.abortOperation(.rebase)
        XCTAssertNil(client.operationInProgress())
        XCTAssertEqual(try currentBranch(), "feature")
    }

    func testSafeBranchIntegrationMergesDisjointChanges() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()

        try client.createBranch(name: "feature", at: baseHash)
        try commitFile(path: "feature.txt", contents: "feature\n", message: "Feature")
        let feature = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "feature"
        })
        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        try client.checkout(reference: main)
        try commitFile(path: "main.txt", contents: "main\n", message: "Main")

        try client.integrate(feature, strategy: .merge)

        XCTAssertEqual(try currentBranch(), "main")
        XCTAssertEqual(
            try git(["rev-list", "--parents", "-n", "1", "HEAD"])
                .split(whereSeparator: \.isWhitespace)
                .count,
            3
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("feature.txt").path
        ))
    }

    func testDeletesRemoteBranchFromBareOrigin() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistBareOrigin-\(UUID().uuidString).git")
        defer { try? FileManager.default.removeItem(at: bareURL) }

        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        try git(["init", "--bare", bareURL.path])
        try git(["remote", "add", "origin", bareURL.path])
        try git(["checkout", "-b", "remote/delete-me"])
        try commitFile(path: "remote.txt", contents: "remote\n", message: "Remote")
        try git(["push", "--set-upstream", "origin", "remote/delete-me"])
        _ = try git([
            "--git-dir=\(bareURL.path)",
            "rev-parse",
            "refs/heads/remote/delete-me"
        ])
        let remoteReference = try XCTUnwrap(client.references().first {
            $0.kind == .remoteBranch && $0.name == "origin/remote/delete-me"
        })
        try client.checkout(reference: remoteReference)
        XCTAssertEqual(try currentBranch(), "remote/delete-me")

        try client.deleteRemoteBranch(name: "origin/remote/delete-me")

        XCTAssertThrowsError(try git([
            "--git-dir=\(bareURL.path)",
            "rev-parse",
            "--verify",
            "refs/heads/remote/delete-me"
        ]))
        XCTAssertFalse(try client.references().contains {
            $0.kind == .remoteBranch && $0.name == "origin/remote/delete-me"
        })
    }

    func testForcePushOptionsRewriteTrackedRemoteBranch() throws {
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistForcePushOrigin-\(UUID().uuidString).git")
        defer { try? FileManager.default.removeItem(at: bareURL) }

        try commitFile(path: "force.txt", contents: "base\n", message: "Base")
        try git(["init", "--bare", bareURL.path])
        try git(["remote", "add", "origin", bareURL.path])
        try git(["push", "--set-upstream", "origin", "main"])

        let client = GitClient(repositoryURL: repositoryURL)
        _ = try client.amend(message: "Rewritten with lease")
        let leasedHash = try headHash()
        _ = try client.forcePushWithLease()
        XCTAssertEqual(
            try git(["--git-dir", bareURL.path, "rev-parse", "refs/heads/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            leasedHash
        )

        _ = try client.amend(message: "Rewritten forcefully")
        let forcedHash = try headHash()
        _ = try client.forcePush()
        XCTAssertEqual(
            try git(["--git-dir", bareURL.path, "rev-parse", "refs/heads/main"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            forcedHash
        )
    }

    func testDetectsAndAbortsConflictedRebase() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "conflict.txt", contents: "base\n", message: "Base")

        try git(["checkout", "-b", "feature"])
        try commitFile(path: "conflict.txt", contents: "feature\n", message: "Feature")

        try git(["checkout", "main"])
        try commitFile(path: "conflict.txt", contents: "main\n", message: "Main")

        XCTAssertThrowsError(try git(["rebase", "feature"]))
        XCTAssertTrue(client.rebaseIsInProgress())
        XCTAssertEqual(client.operationInProgress(), .rebase)
        XCTAssertTrue(try client.snapshot().isRebaseInProgress)

        _ = try client.abortRebase()

        XCTAssertFalse(client.rebaseIsInProgress())
        XCTAssertFalse(try client.snapshot().isRebaseInProgress)
        XCTAssertEqual(try currentBranch(), "main")
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appendingPathComponent("conflict.txt"),
                encoding: .utf8
            ),
            "main\n"
        )
    }

    func testConflictedRebaseCanKeepReplayedCommitAndContinue() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "conflict.txt", contents: "base\n", message: "Base")

        try git(["checkout", "-b", "feature"])
        try commitFile(path: "conflict.txt", contents: "feature\n", message: "Feature")
        let featureHash = try headHash()

        try git(["checkout", "main"])
        try commitFile(path: "conflict.txt", contents: "main\n", message: "Main")

        XCTAssertThrowsError(try git(["rebase", "feature"]))
        XCTAssertEqual(client.operationInProgress(), .rebase)
        let rebaseDocument = try client.conflictDocument(for: "conflict.txt")
        XCTAssertEqual(
            client.conflictSideLabels(for: .rebase, document: rebaseDocument),
            ConflictSideLabels(current: "feature", incoming: "main")
        )

        try client.resolveConflict("conflict.txt", keeping: .incoming, during: .rebase)
        XCTAssertTrue(try client.snapshot().unstaged.allSatisfy { $0.status != "!" })
        _ = try client.continueOperation(.rebase)

        XCTAssertNil(client.operationInProgress())
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appendingPathComponent("conflict.txt"),
                encoding: .utf8
            ),
            "main\n"
        )
        XCTAssertEqual(
            try git(["merge-base", "main", featureHash])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            featureHash
        )
    }

    func testConflictedCherryPickCanResolveHunksAndContinue() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "conflict.ts", contents: "const value = 'base';\n", message: "Base")

        try git(["checkout", "-b", "feature"])
        try commitFile(
            path: "conflict.ts",
            contents: "const value = 'feature';\n",
            message: "Feature"
        )
        let featureHash = try headHash()

        try git(["checkout", "main"])
        try commitFile(
            path: "conflict.ts",
            contents: "const value = 'main';\n",
            message: "Main"
        )

        XCTAssertThrowsError(try client.cherryPick(hash: featureHash))
        XCTAssertEqual(client.operationInProgress(), .cherryPick)
        // Some tools or manual edits can replace the marker-filled working
        // copy while the index still records an unresolved 3-way conflict.
        // Kvist must reconstruct the hunk model from stages 1, 2, and 3
        // instead of degrading a text file to whole-file selection.
        try "const value = 'feature';\n".write(
            to: repositoryURL.appendingPathComponent("conflict.ts"),
            atomically: true,
            encoding: .utf8
        )
        let document = try XCTUnwrap(client.conflictDocument(for: "conflict.ts"))
        XCTAssertEqual(document.hunks.first?.currentText, "const value = 'main';\n")
        XCTAssertEqual(document.hunks.first?.incomingText, "const value = 'feature';\n")
        XCTAssertEqual(
            client.conflictSideLabels(for: .cherryPick, document: document),
            ConflictSideLabels(current: "main", incoming: "feature")
        )
        let choices = Dictionary(uniqueKeysWithValues: document.hunks.map {
            ($0.id, ConflictChoice.incoming)
        })
        let resolvedText = try XCTUnwrap(document.resolvedText(choices: choices))

        try client.resolveConflict(
            "conflict.ts",
            with: resolvedText,
            during: .cherryPick
        )
        _ = try client.continueOperation(.cherryPick)

        XCTAssertNil(client.operationInProgress())
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appendingPathComponent("conflict.ts"),
                encoding: .utf8
            ),
            "const value = 'feature';\n"
        )
    }

    func testLinksOriginBeforePublishingNewRepository() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistPublishOrigin-\(UUID().uuidString).git")
        defer { try? FileManager.default.removeItem(at: bareURL) }

        try commitFile(path: "README.md", contents: "# New repository\n", message: "Initial")
        try git(["init", "--bare", bareURL.path])
        XCTAssertNil(client.originRemoteURL())

        try client.linkOrigin(to: bareURL.path)
        XCTAssertEqual(client.originRemoteURL(), bareURL.path)
        _ = try client.publish(branch: "main")

        XCTAssertEqual(
            try git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "origin/main"
        )
        XCTAssertThrowsError(try client.linkOrigin(to: bareURL.path))
    }

    func testComparisonCherryPickRevertAndGitHubURLs() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        try git(["checkout", "-b", "feature"])
        try commitFile(path: "feature.txt", contents: "feature\n", message: "Feature")
        let featureHash = try headHash()
        try git(["checkout", "main"])
        try commitFile(path: "main.txt", contents: "main\n", message: "Main")

        let main = try XCTUnwrap(client.references().first {
            $0.kind == .localBranch && $0.name == "main"
        })
        let directComparison = try client.comparisonDiff(
            hash: featureHash,
            against: main
        )
        let mergeBaseComparison = try client.comparisonDiff(
            hash: featureHash,
            against: main,
            fromMergeBase: true
        )
        XCTAssertTrue(directComparison.contains("main.txt"))
        XCTAssertTrue(directComparison.contains("feature.txt"))
        XCTAssertFalse(mergeBaseComparison.contains("main.txt"))
        XCTAssertTrue(mergeBaseComparison.contains("feature.txt"))

        try client.cherryPick(hash: featureHash)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("feature.txt").path
        ))
        try client.revert(hash: featureHash)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent("feature.txt").path
        ))

        try git(["remote", "add", "origin", "git@github.com:example/Kvist.git"])
        XCTAssertEqual(
            try client.githubCommitURL(hash: featureHash)?.absoluteString,
            "https://github.com/example/Kvist/commit/\(featureHash)"
        )

        try git(["update-ref", "refs/remotes/origin/feature/pr-ready", featureHash])
        let remoteFeature = try XCTUnwrap(client.references().first {
            $0.kind == .remoteBranch && $0.name == "origin/feature/pr-ready"
        })
        XCTAssertEqual(
            try client.githubPullRequestURL(for: remoteFeature)?.absoluteString,
            "https://github.com/example/Kvist/compare/feature/pr-ready?expand=1"
        )
        XCTAssertNil(try client.githubPullRequestURL(for: main))
    }

    func testSoftMixedAndHardResetModes() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "value.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()
        try commitFile(path: "value.txt", contents: "second\n", message: "Second")
        let secondHash = try headHash()

        try client.reset(to: baseHash, mode: .soft)
        XCTAssertEqual(try headHash(), baseHash)
        XCTAssertEqual(try client.snapshot().staged.first?.path, "value.txt")

        try client.reset(to: secondHash, mode: .hard)
        XCTAssertEqual(try headHash(), secondHash)
        XCTAssertTrue(try client.snapshot().staged.isEmpty)

        try client.reset(to: baseHash, mode: .mixed)
        XCTAssertEqual(try headHash(), baseHash)
        XCTAssertEqual(try client.snapshot().unstaged.first?.path, "value.txt")

        try client.reset(to: baseHash, mode: .hard)
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appendingPathComponent("value.txt"),
                encoding: .utf8
            ),
            "base\n"
        )
        XCTAssertFalse(try client.snapshot().hasChanges)
    }

    func testReflogHistoryIncludesCommitNoLongerReachableFromReferences() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        let baseHash = try headHash()
        try commitFile(path: "lost.txt", contents: "lost\n", message: "Recover me")
        let lostHash = try headHash()
        _ = try git(["reset", "--hard", baseHash])

        XCTAssertFalse(try client.history(scope: .all).rows.contains {
            $0.commit.hash == lostHash
        })
        let reflogRows = try client.history(scope: .reflog).rows
        XCTAssertTrue(reflogRows.contains { $0.commit.hash == lostHash })
        // Reflog entries may legitimately repeat a commit (here the base
        // commit is both the initial commit and the reset target), so row
        // identity comes from the reflog selector.
        XCTAssertEqual(Set(reflogRows.map(\.id)).count, reflogRows.count)
    }

    func testAllBranchesHidesInternalRefsWhileEverythingShowsThem() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        let treeHash = try git(["rev-parse", "HEAD^{tree}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let checkpointReference = "refs/t3/checkpoints/test-thread/turn/1"
        let checkpointHash = try git([
            "commit-tree",
            treeHash,
            "-m",
            "t3 checkpoint ref=\(checkpointReference)"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git(["update-ref", checkpointReference, checkpointHash])

        XCTAssertFalse(try client.history(scope: .all).rows.contains {
            $0.commit.hash == checkpointHash
        })

        let everythingRows = try client.history(scope: .everything).rows
        let checkpointRow = try XCTUnwrap(everythingRows.first {
            $0.commit.hash == checkpointHash
        })
        XCTAssertTrue(checkpointRow.commit.references.contains {
            $0.id == checkpointReference
        })
    }

    func testBranchRemoteUpstreamAndRemoteTagManagement() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let firstBareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistRemoteOne-\(UUID().uuidString).git")
        let secondBareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistRemoteTwo-\(UUID().uuidString).git")
        defer {
            try? FileManager.default.removeItem(at: firstBareURL)
            try? FileManager.default.removeItem(at: secondBareURL)
        }

        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        try git(["init", "--bare", firstBareURL.path])
        try git(["init", "--bare", secondBareURL.path])

        try client.renameBranch(oldName: "main", to: "trunk")
        XCTAssertEqual(try currentBranch(), "trunk")
        XCTAssertThrowsError(try client.renameBranch(oldName: "trunk", to: "trunk"))

        try client.addRemote(name: "origin", url: firstBareURL.path)
        XCTAssertEqual(try client.remotes(), [
            GitRemote(
                name: "origin",
                fetchURL: firstBareURL.path,
                pushURL: firstBareURL.path
            )
        ])
        try client.setRemoteURL(name: "origin", url: secondBareURL.path)
        XCTAssertEqual(try client.remotes().first?.fetchURL, secondBareURL.path)

        _ = try git(["push", "origin", "trunk"])
        try client.setUpstream(branch: "trunk", remoteBranch: "origin/trunk")
        XCTAssertEqual(
            try git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"])
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "origin/trunk"
        )
        try client.unsetUpstream(branch: "trunk")
        XCTAssertThrowsError(try git(["rev-parse", "--verify", "@{upstream}"]))

        try client.createTag(name: "v-test", at: headHash())
        try client.pushTag(name: "v-test", remote: "origin")
        _ = try git([
            "--git-dir", secondBareURL.path,
            "rev-parse", "--verify", "refs/tags/v-test"
        ])
        try client.deleteRemoteTag(name: "v-test", remote: "origin")
        XCTAssertThrowsError(try git([
            "--git-dir", secondBareURL.path,
            "rev-parse", "--verify", "refs/tags/v-test"
        ]))

        try client.removeRemote(name: "origin")
        XCTAssertTrue(try client.remotes().isEmpty)
    }

    func testFetchRecoversWhenSingleBranchRemoteWasDeleted() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistDeletedRemoteBranch-\(UUID().uuidString).git")
        defer { try? FileManager.default.removeItem(at: bareURL) }

        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        try git(["init", "--bare", bareURL.path])
        try git(["remote", "add", "origin", bareURL.path])
        try git(["push", "origin", "main"])
        try git([
            "config", "remote.origin.fetch",
            "+refs/heads/deleted:refs/remotes/origin/deleted"
        ])
        try git([
            "config", "--add", "remote.origin.fetch",
            "+refs/pull/*/head:refs/remotes/origin/pull/*"
        ])

        _ = try client.fetch()

        XCTAssertEqual(Set(
            try git(["config", "--get-all", "remote.origin.fetch"])
                .split(whereSeparator: { $0.isNewline }).map(String.init)
        ), [
            "+refs/heads/*:refs/remotes/origin/*",
            "+refs/pull/*/head:refs/remotes/origin/pull/*"
        ])
        XCTAssertNoThrow(try git(["rev-parse", "--verify", "refs/remotes/origin/main"]))
    }

    func testFetchTimesOutInsteadOfRemainingBusy() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistTimeoutRemote-\(UUID().uuidString).git")
        defer { try? FileManager.default.removeItem(at: bareURL) }
        try git(["init", "--bare", bareURL.path])
        try git(["remote", "add", "origin", bareURL.path])

        XCTAssertThrowsError(try client.fetch(timeout: 0)) { error in
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
    }

    func testCloneRepositoryUsesSafeDestinationAndReturnsRoot() throws {
        try commitFile(path: "README.md", contents: "# Clone me\n", message: "Initial")
        let cloneURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistClone-\(UUID().uuidString)")
        let occupiedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistOccupiedClone-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: cloneURL)
            try? FileManager.default.removeItem(at: occupiedURL)
        }

        let root = try GitClient.cloneRepository(
            from: repositoryURL.path,
            to: cloneURL
        )
        XCTAssertEqual(root.standardizedFileURL, cloneURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: cloneURL.appendingPathComponent("README.md").path
        ))

        try FileManager.default.createDirectory(
            at: occupiedURL,
            withIntermediateDirectories: true
        )
        try "keep\n".write(
            to: occupiedURL.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertThrowsError(try GitClient.cloneRepository(
            from: repositoryURL.path,
            to: occupiedURL
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: occupiedURL.appendingPathComponent("keep.txt").path
        ))
    }

    func testDetectsContinuesSkipsAndAbortsGitOperations() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "conflict.txt", contents: "base\n", message: "Base")

        try git(["checkout", "-b", "feature"])
        try commitFile(path: "conflict.txt", contents: "feature\n", message: "Feature")
        let featureHash = try headHash()
        try git(["checkout", "main"])
        try commitFile(path: "conflict.txt", contents: "main\n", message: "Main")

        XCTAssertThrowsError(try git(["cherry-pick", featureHash]))
        XCTAssertEqual(client.operationInProgress(), .cherryPick)
        XCTAssertThrowsError(try client.abortOperation(.merge))
        _ = try client.skipOperation(.cherryPick)
        XCTAssertNil(client.operationInProgress())

        XCTAssertThrowsError(try git(["cherry-pick", featureHash]))
        try "resolved\n".write(
            to: repositoryURL.appendingPathComponent("conflict.txt"),
            atomically: true,
            encoding: .utf8
        )
        try client.stageAll()
        _ = try client.continueOperation(.cherryPick)
        XCTAssertNil(client.operationInProgress())

        _ = try git(["reset", "--hard", "HEAD~1"])
        XCTAssertThrowsError(try git(["merge", "feature"]))
        XCTAssertEqual(client.operationInProgress(), .merge)
        XCTAssertThrowsError(try client.skipOperation(.merge))
        _ = try client.abortOperation(.merge)
        XCTAssertNil(client.operationInProgress())
    }

    func testDetectsAndAbortsConflictedRevert() throws {
        let client = GitClient(repositoryURL: repositoryURL)
        try commitFile(path: "value.txt", contents: "base\n", message: "Base")
        try commitFile(path: "value.txt", contents: "target\n", message: "Target")
        let targetHash = try headHash()
        try commitFile(path: "value.txt", contents: "later\n", message: "Later")
        let headBeforeRevert = try headHash()

        XCTAssertThrowsError(try git(["revert", "--no-edit", targetHash]))
        XCTAssertEqual(client.operationInProgress(), .revert)
        _ = try client.abortOperation(.revert)

        XCTAssertNil(client.operationInProgress())
        XCTAssertEqual(try headHash(), headBeforeRevert)
        XCTAssertEqual(
            try String(
                contentsOf: repositoryURL.appendingPathComponent("value.txt"),
                encoding: .utf8
            ),
            "later\n"
        )
    }

    @MainActor
    func testRepositoryModelExpandsCommitAndPresentsFileDiff() async throws {
        try commitFile(path: "tracked.txt", contents: "tracked\n", message: "Tracked")
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        let commit = try XCTUnwrap(model.graph.first?.commit)

        model.toggleCommitExpansion(commit)
        XCTAssertTrue(model.expandedCommitHashes.contains(commit.hash))
        XCTAssertFalse(model.isDiffPanelPresented)

        let deadline = Date().addingTimeInterval(3)
        while model.commitFilesByHash[commit.hash] == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        let file = try XCTUnwrap(model.commitFilesByHash[commit.hash]?.first)

        model.select(file, in: commit)
        XCTAssertTrue(model.isDiffPanelPresented)
        while model.detailText == "Loading diff…", Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(model.detailText.contains("+tracked"))

        model.closeDiffPanel()
        XCTAssertFalse(model.isDiffPanelPresented)
        XCTAssertNil(model.selectedCommitFile)

        model.openCommitChanges(commit)
        XCTAssertTrue(model.isDiffPanelPresented)
    }

    @MainActor
    func testAutoFetchUpdatesRemoteState() async throws {
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistAutoFetchOrigin-\(UUID().uuidString).git")
        let peerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistAutoFetchPeer-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: bareURL)
            try? FileManager.default.removeItem(at: peerURL)
        }

        try commitFile(path: "base.txt", contents: "base\n", message: "Base")
        try git(["init", "--bare", bareURL.path])
        try git(["remote", "add", "origin", bareURL.path])
        try git(["push", "--set-upstream", "origin", "main"])
        try git(["clone", "--branch", "main", bareURL.path, peerURL.path])
        try git(["config", "user.name", "Kvist Test"], in: peerURL)
        try git(["config", "user.email", "kvist@example.invalid"], in: peerURL)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )
        await model.openRepository(repositoryURL)

        try "remote\n".write(
            to: peerURL.appendingPathComponent("remote.txt"),
            atomically: true,
            encoding: .utf8
        )
        try git(["add", "remote.txt"], in: peerURL)
        try git(["commit", "-m", "Remote"], in: peerURL)
        try git(["push"], in: peerURL)

        XCTAssertEqual(model.behind, 0)
        await model.autoFetch(applicationIsActive: true)
        XCTAssertEqual(model.behind, 1)
    }

    @MainActor
    func testRepositoryModelLoadsOlderCommitsByPage() async throws {
        try commitFile(path: "one.txt", contents: "one\n", message: "One")
        try commitFile(path: "two.txt", contents: "two\n", message: "Two")
        try commitFile(path: "three.txt", contents: "three\n", message: "Three")

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            graphPageSize: 2
        )
        await model.openRepository(repositoryURL)

        XCTAssertEqual(model.graph.count, 2)
        XCTAssertTrue(model.canLoadMoreGraph)

        await model.loadMoreGraph()

        XCTAssertEqual(model.graph.count, 3)
        XCTAssertFalse(model.canLoadMoreGraph)
        XCTAssertFalse(model.isLoadingMoreGraph)
        XCTAssertEqual(
            model.graph.map(\.commit.subject),
            ["Three", "Two", "One"]
        )
    }

    private func commitFile(path: String, contents: String, message: String) throws {
        let url = repositoryURL.appendingPathComponent(path)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try GitClient(repositoryURL: repositoryURL).stageAll()
        _ = try GitClient(repositoryURL: repositoryURL).commit(message: message)
    }

    private func headHash() throws -> String {
        try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentBranch() throws -> String {
        try git(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        try git(arguments, in: repositoryURL)
    }

    @discardableResult
    private func git(_ arguments: [String], in directoryURL: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directoryURL
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

private extension RepositorySnapshot {
    var hasChanges: Bool {
        !staged.isEmpty || !unstaged.isEmpty
    }
}

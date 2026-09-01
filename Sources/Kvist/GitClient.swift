import Foundation

enum ChangeArea: String, Sendable {
    case staged
    case unstaged
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct FileChange: Identifiable, Hashable, Sendable {
    let path: String
    let previousPath: String?
    let status: String
    let area: ChangeArea

    init(
        path: String,
        previousPath: String? = nil,
        status: String,
        area: ChangeArea
    ) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.area = area
    }

    var id: String { "\(area.rawValue):\(path)" }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }

    var parentPath: String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }
}

struct CommitInfo: Hashable, Sendable {
    let hash: String
    let parentHashes: [String]
    let author: String
    let relativeDate: String
    let references: [GitReference]
    let subject: String
    /// Reflog selector such as `HEAD@{3}`, set only for reflog-scope rows.
    /// The same commit can appear in several reflog entries, so the selector
    /// is what makes an entry unique.
    let reflogSelector: String?
    let reflogSubject: String?

    var shortHash: String { String(hash.prefix(7)) }

    var displaySubject: String {
        reflogSubject?.nilIfEmpty ?? subject
    }

    init(
        hash: String,
        shortHash _: String,
        parentHashes: [String],
        author: String,
        relativeDate: String,
        references: [GitReference],
        subject: String,
        reflogSelector: String? = nil,
        reflogSubject: String? = nil
    ) {
        self.hash = hash
        self.parentHashes = parentHashes
        self.author = author
        self.relativeDate = relativeDate
        self.references = references
        self.subject = subject
        self.reflogSelector = reflogSelector
        self.reflogSubject = reflogSubject
    }

    var isStash: Bool {
        references.contains { $0.id == "refs/stash" }
    }
}

struct CommitFileChange: Identifiable, Hashable, Sendable {
    let path: String
    let previousPath: String?
    let status: String

    var id: String {
        if let previousPath {
            return "\(previousPath)\u{0}\(path)"
        }
        return path
    }

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var parentPath: String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }
}

enum GitResetMode: String, CaseIterable, Sendable {
    case soft = "--soft"
    case mixed = "--mixed"
    case hard = "--hard"
}

enum BranchIntegrationStrategy: Sendable {
    case fastForward
    case merge
    case rebase
}

enum ConflictVersion: Equatable, Sendable {
    case current
    case incoming
}

enum GitReferenceKind: Hashable, Sendable {
    case localBranch
    case remoteBranch
    case tag
    case other
}

struct GitReference: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: GitReferenceKind
    let isHead: Bool
    let symbolicTarget: String?

    init(
        id: String,
        name: String,
        kind: GitReferenceKind,
        isHead: Bool,
        symbolicTarget: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isHead = isHead
        self.symbolicTarget = symbolicTarget
    }

    var remoteBranchComponents: (remote: String, branch: String)? {
        guard kind == .remoteBranch else { return nil }
        let components = name.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else { return nil }
        return (remote: components[0], branch: components[1])
    }

    func isRemoteDefaultBranch(in references: [GitReference]) -> Bool {
        guard kind == .localBranch else { return false }
        return references.contains { reference in
            guard let remoteBranch = reference.remoteBranchComponents,
                  remoteBranch.branch == "HEAD" else { return false }
            return reference.symbolicTarget
                == "refs/remotes/\(remoteBranch.remote)/\(name)"
        }
    }
}

enum GraphLaneColor: Int, CaseIterable, Hashable, Sendable {
    case current
    case remote
    case base
    case lane1
    case lane2
    case lane3
    case lane4
    case lane5
}

struct GraphLane: Hashable, Sendable {
    let id: String
    let color: GraphLaneColor
}

enum GraphRowKind: Hashable, Sendable {
    case head
    case node
}

struct GraphRow: Identifiable, Hashable, Sendable {
    // Reflog rows can repeat a commit, so their selector provides identity.
    var id: String { commit.reflogSelector ?? commit.hash }

    let commit: CommitInfo
    let kind: GraphRowKind
    let inputLanes: [GraphLane]
    let outputLanes: [GraphLane]
}

struct GraphLayoutState: Equatable, Sendable {
    var lanes: [GraphLane] = []
    var rotatingColorIndex = -1
    var hiddenStashCommitHashes: Set<String> = []
    var historyHashBufferOffset = 0
    var historyHashBuffer = Data()
    var historyHashLength = 0
}

struct GitHistoryPage: Sendable {
    let rows: [GraphRow]
    let headHash: String?
    let nextOffset: Int
    let hasMore: Bool
    let layoutState: GraphLayoutState
}

enum GitHistoryScope: Hashable, Sendable {
    case all
    case current
    case everything
    case reflog
}

struct GitRemote: Identifiable, Hashable, Sendable {
    let name: String
    let fetchURL: String
    let pushURL: String

    var id: String { name }

    var isGitHub: Bool {
        let remoteURL = fetchURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if remoteURL.lowercased().hasPrefix("git@github.com:") {
            return true
        }
        return URL(string: remoteURL)?.host?.lowercased() == "github.com"
    }
}

enum GitOperation: String, CaseIterable, Hashable, Sendable {
    case rebase
    case merge
    case cherryPick = "cherry-pick"
    case revert
}

struct RepositorySnapshot: Sendable {
    let branch: String
    let staged: [FileChange]
    let unstaged: [FileChange]
    let resolveUndoPaths: Set<String>
    let graph: [GraphRow]
    let references: [GitReference]
    let upstreamReference: GitReference?
    let headHash: String?
    let ahead: Int
    let behind: Int
    let hasUpstream: Bool
    let isRebaseInProgress: Bool
    let activeOperation: GitOperation?
    let fastForwardReferenceIDs: Set<String>
    let historyOffset: Int
    let graphHasMore: Bool
    let graphLayoutState: GraphLayoutState
    let referencesByCommitHash: [String: [GitReference]]

    /// The snapshot of a folder opened without Git: nothing to show in the
    /// source-control views.
    static let empty = RepositorySnapshot(
        branch: "",
        staged: [],
        unstaged: [],
        resolveUndoPaths: [],
        graph: [],
        references: [],
        upstreamReference: nil,
        headHash: nil,
        ahead: 0,
        behind: 0,
        hasUpstream: false,
        isRebaseInProgress: false,
        activeOperation: nil,
        fastForwardReferenceIDs: [],
        historyOffset: 0,
        graphHasMore: false,
        graphLayoutState: GraphLayoutState(),
        referencesByCommitHash: [:]
    )
}

struct WorkingTreeSnapshot: Sendable {
    let staged: [FileChange]
    let unstaged: [FileChange]
    let resolveUndoPaths: Set<String>
}

struct RepositoryStatusSnapshot: Sendable {
    let branch: String
    let headHash: String?
    let upstreamName: String?
    let ahead: Int
    let behind: Int
    let workingTree: WorkingTreeSnapshot
    let hasUpstream: Bool
}

private struct ReferenceSnapshot: Sendable {
    let references: [GitReference]
    let referencesByCommitHash: [String: [GitReference]]
    let upstreamReference: GitReference?
    let headBranchName: String?
}

private struct RemoteRepositoryOverview: Sendable {
    let status: RepositoryStatusSnapshot
    let references: ReferenceSnapshot
    let activeOperation: GitOperation?
}

struct RemoteCommandResult: Sendable {
    let exitCode: Int32
    let output: Data
}

private final class GitCommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

struct GitCommandError: LocalizedError, Sendable {
    let command: String
    let output: String

    struct RebaseConflictPresentation: Equatable, Sendable {
        let title: String
        let message: String
        let details: String
    }

    struct MissingToolPresentation: Equatable, Sendable {
        let title: String
        let message: String
        let details: String
    }

    var rebaseConflictPresentation: RebaseConflictPresentation? {
        let paths = rebaseConflictPaths
        guard !paths.isEmpty,
              output.localizedCaseInsensitiveContains("rebas") ||
                output.localizedCaseInsensitiveContains("could not apply") else {
            return nil
        }

        let visiblePaths = paths.prefix(6)
        var lines = visiblePaths.map { "• \($0)" }
        if paths.count > visiblePaths.count {
            lines.append("• \(paths.count - visiblePaths.count) more")
        }

        let fileWord = paths.count == 1 ? "file has" : "files have"
        let message = """
        Git paused the rebase because \(paths.count) \(fileWord) conflicts.

        \(lines.joined(separator: "\n"))

        Resolve the conflicts under Changes, then choose Continue Rebase. To return to the state before syncing, choose Abort Rebase.
        """
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = detail.isEmpty
            ? "Command: \(command)"
            : "Command: \(command)\n\n\(detail)"
        return RebaseConflictPresentation(
            title: "Rebase Paused",
            message: message,
            details: details
        )
    }

    var errorDescription: String? {
        if let presentation = rebaseConflictPresentation {
            return presentation.message
        }
        if let presentation = missingToolPresentation {
            return presentation.message
        }
        if let presentation = sshAuthenticationPresentation {
            return presentation.message
        }
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "Git command failed: \(command)" : detail
    }

    var missingToolPresentation: MissingToolPresentation? {
        guard let subcommand = missingGitSubcommand else { return nil }
        let executable = "git-\(subcommand)"
        let isLFS = subcommand.caseInsensitiveCompare("lfs") == .orderedSame
        let title = isLFS ? "Git LFS Not Found" : "Git Tool Not Found"
        let toolName = isLFS ? "Git LFS" : executable
        let message = """
        \(toolName) is required by this repository, but Kvist could not find \(executable). Install the missing tool or add it to your shell’s PATH, then try again.
        """
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = detail.isEmpty
            ? "Command: \(command)"
            : "Command: \(command)\n\n\(detail)"
        return MissingToolPresentation(
            title: title,
            message: message,
            details: details
        )
    }

    var sshAuthenticationPresentation: MissingToolPresentation? {
        let lowercased = output.lowercased()
        guard lowercased.contains("permission denied")
                && (lowercased.contains("publickey") || command.hasPrefix("ssh")) else {
            return nil
        }
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return MissingToolPresentation(
            title: "SSH Authentication Failed",
            message: "Kvist could not authenticate with the keys available through your SSH configuration, agent, or macOS Keychain. Add the key there and try again; Kvist does not store SSH passwords.",
            details: detail.isEmpty
                ? "Command: \(command)"
                : "Command: \(command)\n\n\(detail)"
        )
    }

    private var rebaseConflictPaths: [String] {
        let marker = "Merge conflict in "
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            guard line.hasPrefix("CONFLICT "),
                  let markerRange = line.range(of: marker) else { return nil }
            let path = String(line[markerRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return path
        }
    }

    private var missingGitSubcommand: String? {
        let prefix = "git: '"
        let suffix = "' is not a git command"
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let prefixRange = line.range(of: prefix),
                  let suffixRange = line.range(
                    of: suffix,
                    range: prefixRange.upperBound..<line.endIndex
                  ) else { continue }
            let subcommand = String(line[prefixRange.upperBound..<suffixRange.lowerBound])
            guard !subcommand.isEmpty,
                  subcommand.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                continue
            }
            return subcommand
        }
        return nil
    }
}

struct PredictedMergeConflictError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Kvist did not change the current branch. Git predicts merge conflicts between these branches."
    }
}

struct SSHRepository: Codable, Equatable, Sendable {
    let host: String
    let path: String
    /// `false` when the remote folder is browsed and edited without Git.
    let isGitRepository: Bool

    init(host: String, path: String, isGitRepository: Bool = true) throws {
        let host = try Self.validatedHost(host)
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else {
            throw GitCommandError(
                command: "ssh",
                output: "Enter an SSH host such as user@example.com and an absolute remote path."
            )
        }
        self.host = host
        self.path = path
        self.isGitRepository = isGitRepository
    }

    private enum CodingKeys: String, CodingKey {
        case host, path, isGitRepository
    }

    /// Markers written before folder mode existed carry no kind and are
    /// Git repositories.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        path = try container.decode(String.self, forKey: .path)
        isGitRepository = try container.decodeIfPresent(
            Bool.self,
            forKey: .isGitRepository
        ) ?? true
    }

    static func validatedHost(_ host: String) throws -> String {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedHostCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "@._-")
        )
        guard !host.isEmpty,
              host.unicodeScalars.allSatisfy(allowedHostCharacters.contains) else {
            throw GitCommandError(
                command: "ssh",
                output: "Enter an SSH host such as user@example.com and an absolute repository path."
            )
        }
        return host
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

struct SSHFileEntry: Sendable {
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
}

/// What Kvist found at a remote path before opening it.
enum SSHPathKind: Equatable, Sendable {
    /// The path is the root of a Git working tree.
    case repository
    /// The path is a folder with no Git repository (or no `git` binary), so
    /// Kvist opens it as a plain file browser and editor.
    case folder
}

struct GitClient: Sendable {
    private static let networkOperationTimeout: TimeInterval = 120

    let repositoryURL: URL
    let sshRepository: SSHRepository?

    init(repositoryURL: URL, sshRepository: SSHRepository? = nil) {
        self.repositoryURL = repositoryURL
        self.sshRepository = sshRepository
    }

    private static let commandEnvironment: [String: String] = makeCommandEnvironment(
        baseEnvironment: ProcessInfo.processInfo.environment,
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        loginShellPATH: loadLoginShellPATH(
            baseEnvironment: ProcessInfo.processInfo.environment
        )
    )

    static func makeCommandEnvironment(
        baseEnvironment: [String: String],
        homeDirectory: URL,
        loginShellPATH: String?
    ) -> [String: String] {
        var environment = baseEnvironment
        let home = homeDirectory.standardizedFileURL.path
        let commonExecutableDirectories = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.volta/bin",
            "\(home)/.asdf/shims",
            "\(home)/.local/share/mise/shims",
            "\(home)/Library/pnpm",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let pathValues = [loginShellPATH, baseEnvironment["PATH"]]
            .compactMap { $0 }
            .flatMap { $0.split(separator: ":", omittingEmptySubsequences: true) }
            .map(String.init) + commonExecutableDirectories
        var seenPaths = Set<String>()
        environment["PATH"] = pathValues
            .filter { seenPaths.insert($0).inserted }
            .joined(separator: ":")
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GCM_INTERACTIVE"] = "Never"
        environment["GIT_EDITOR"] = "true"
        environment["GIT_SEQUENCE_EDITOR"] = "true"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        environment["GIT_PAGER"] = "cat"
        return environment
    }

    private static func loadLoginShellPATH(
        baseEnvironment: [String: String]
    ) -> String? {
        let shellPath = baseEnvironment["SHELL"] ?? "/bin/zsh"
        guard shellPath.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: shellPath) else { return nil }

        let process = Process()
        let outputPipe = Pipe()
        let outputBuffer = GitCommandOutputBuffer()
        let completion = DispatchSemaphore(value: 0)
        let outputCompletion = DispatchSemaphore(value: 0)
        let marker = "__KVIST_LOGIN_PATH__="

        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = [
            "-l", "-c",
            "/usr/bin/printf '\(marker)%s\\n' \"$PATH\""
        ]
        process.environment = baseEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }
        let outputHandle = outputPipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            outputBuffer.append(outputHandle.readDataToEndOfFile())
            outputCompletion.signal()
        }

        if completion.wait(timeout: .now() + .seconds(2)) == .timedOut {
            process.terminate()
        }
        process.waitUntilExit()
        outputCompletion.wait()

        let output = String(data: outputBuffer.value(), encoding: .utf8) ?? ""
        return output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            guard line.hasPrefix(marker) else { return nil }
            return String(line.dropFirst(marker.count))
        }.last
    }

    static func initializeRepository(at url: URL, createGitIgnore: Bool = true) throws {
        _ = try GitClient(repositoryURL: url).run(["init"])
        if createGitIgnore {
            try createRecommendedGitIgnore(at: url)
        }
    }

    /// Turns a remote folder opened without Git into a repository. The
    /// recommended `.gitignore` is written to the local cache and uploaded,
    /// mirroring how edited files reach the remote machine.
    func initializeSSHRepository(createGitIgnore: Bool) throws {
        guard let sshRepository else { return }
        _ = try run(["init"])
        let remoteGitIgnore = Self.shellQuote(
            URL(fileURLWithPath: sshRepository.path)
                .appendingPathComponent(".gitignore").path
        )
        let remoteHasGitIgnore = (try? runSSH("test -e \(remoteGitIgnore)")) != nil
        if createGitIgnore, !remoteHasGitIgnore {
            try Self.createRecommendedGitIgnore(at: repositoryURL)
            try uploadSSHFile(
                repositoryURL.appendingPathComponent(".gitignore"),
                relativePath: ".gitignore"
            )
        }
    }

    static func cloneRepository(from remoteURL: String, to destinationURL: URL) throws -> URL {
        let source = try validatedRemoteURL(remoteURL, command: "git clone")
        let destination = destinationURL.standardizedFileURL
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let destinationExisted = fileManager.fileExists(
            atPath: destination.path,
            isDirectory: &isDirectory
        )

        if destinationExisted {
            guard isDirectory.boolValue else {
                throw GitCommandError(
                    command: "git clone",
                    output: "The clone destination already exists and is not a folder."
                )
            }
            let contents = try fileManager.contentsOfDirectory(atPath: destination.path)
            guard contents.isEmpty else {
                throw GitCommandError(
                    command: "git clone",
                    output: "The clone destination must be a new or empty folder."
                )
            }
        }

        let parent = destination.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue else {
            throw GitCommandError(
                command: "git clone",
                output: "The clone destination's parent folder does not exist."
            )
        }

        do {
            _ = try GitClient(repositoryURL: parent).run([
                "clone", "--", source, destination.path
            ], timeout: 300)
        } catch {
            // Git creates the destination before transferring objects. Remove
            // only a directory that did not exist before this clone attempt;
            // never clean an existing user-selected folder on failure.
            if !destinationExisted {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
        return try discoverRoot(from: destination)
    }

    private static func createRecommendedGitIgnore(at url: URL) throws {
        let fileURL = url.appendingPathComponent(".gitignore")
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }

        var entries = [".DS_Store"]
        let exists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path)
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []

        if exists("Package.swift") || contents.contains(where: { $0.hasSuffix(".xcodeproj") }) {
            entries += [".build/", "DerivedData/", "xcuserdata/", "*.xcuserstate"]
        }
        if exists("package.json") {
            entries += ["node_modules/", ".next/", "dist/", ".env", ".env.*", "!.env.example"]
        }
        if exists("pyproject.toml") || exists("requirements.txt") || exists("setup.py") {
            entries += ["__pycache__/", "*.py[cod]", ".venv/", "venv/", ".pytest_cache/"]
        }

        try (entries.joined(separator: "\n") + "\n").write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
    }

    static func discoverRoot(from url: URL) throws -> URL {
        let client = GitClient(repositoryURL: url)
        let root = try client.run(["rev-parse", "--show-toplevel"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else {
            throw GitCommandError(command: "git rev-parse --show-toplevel", output: "That folder is not inside a Git repository.")
        }
        return URL(fileURLWithPath: root, isDirectory: true)
    }

    func validateSSHRepository() throws {
        guard sshRepository != nil else { return }
        let root = try run(["rev-parse", "--show-toplevel"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard root == sshRepository?.path else {
            throw GitCommandError(
                command: "git rev-parse --show-toplevel",
                output: "The SSH path must be the repository root. Git reported \(root)."
            )
        }
    }

    /// Decides whether a remote path opens as a Git repository or as a plain
    /// folder. Missing folders and paths inside (but not at the root of) a
    /// repository are errors, matching `validateSSHRepository`.
    static func probeSSHPath(host: String, path: String) throws -> SSHPathKind {
        let script = """
        p=\(shellQuote(path))
        if [ ! -d "$p" ]; then printf 'missing'; exit 0; fi
        cd "$p" 2>/dev/null || { printf 'unreadable'; exit 0; }
        top=$(git rev-parse --show-toplevel 2>/dev/null) || { printf 'folder'; exit 0; }
        printf 'repository\\n%s' "$top"
        """
        let data = try runSSH(host: host, command: posixShellCommand(script))
        return try parseSSHPathProbe(data, path: path)
    }

    static func parseSSHPathProbe(_ data: Data, path: String) throws -> SSHPathKind {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        switch lines.first.map(String.init) ?? "" {
        case "folder":
            return .folder
        case "repository":
            let root = lines.count > 1
                ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            guard root == path else {
                throw GitCommandError(
                    command: "git rev-parse --show-toplevel",
                    output: "The SSH path must be the repository root. Git reported \(root)."
                )
            }
            return .repository
        case "missing":
            throw GitCommandError(
                command: "ssh",
                output: "There is no folder at \(path) on the remote machine."
            )
        case "unreadable":
            throw GitCommandError(
                command: "ssh",
                output: "Kvist cannot read \(path) on the remote machine."
            )
        default:
            throw GitCommandError(command: "ssh", output: "Unexpected SSH response data.")
        }
    }

    /// File-name and content search for a folder opened without Git: `find`
    /// and `grep` stand in for `git ls-files` and `git grep`, locally or over
    /// SSH. Hidden `.git` folders are skipped so a nested checkout's
    /// metadata never shows up as matches.
    func searchFolder(
        for rawQuery: String,
        fileLimit: Int = 200,
        textLimit: Int = 300
    ) throws -> RepositorySearchResults {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }
        let root = sshRepository?.path ?? repositoryURL.standardizedFileURL.path

        let listScript = """
        cd \(Self.shellQuote(root)) || exit 1
        find . -name .git -prune -o -type f -print0
        """
        let pathsOutput = String(
            decoding: try runShellScript(listScript),
            as: UTF8.self
        )
        let allFileMatches = RepositorySearchParser.filePaths(from: pathsOutput)
            .map(Self.strippingCurrentDirectoryPrefix)
            .compactMap { path -> RepositoryFileSearchMatch? in
                guard let score = RepositoryPathMatcher.score(
                    query: query,
                    path: path
                ) else {
                    return nil
                }
                return RepositoryFileSearchMatch(path: path, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
        let resolvedFileLimit = max(0, fileLimit)
        let fileMatches = Array(allFileMatches.prefix(resolvedFileLimit))

        try Task.checkCancellation()
        let grepScript = """
        cd \(Self.shellQuote(root)) || exit 1
        grep -r -n -I -i -F --null --max-count=20 --exclude-dir=.git \
        -e \(Self.shellQuote(query)) . 2>/dev/null
        exit 0
        """
        let grepOutput = String(
            decoding: try runShellScript(grepScript),
            as: UTF8.self
        )
        let parsedTextMatches = RepositorySearchParser.textMatches(
            fromGrepOutput: grepOutput,
            limit: max(0, textLimit)
        )

        return RepositorySearchResults(
            fileMatches: fileMatches,
            textMatches: parsedTextMatches.matches,
            fileMatchesWereLimited: allFileMatches.count > fileMatches.count,
            textMatchesWereLimited: parsedTextMatches.wasLimited
        )
    }

    static func strippingCurrentDirectoryPrefix(_ path: String) -> String {
        path.hasPrefix("./") ? String(path.dropFirst(2)) : path
    }

    /// Runs a POSIX shell script on the machine that holds the files: over
    /// SSH for remote folders, through `/bin/sh` locally otherwise.
    private func runShellScript(_ script: String) throws -> Data {
        if let sshRepository {
            return try Self.runSSH(
                host: sshRepository.host,
                command: Self.posixShellCommand(script)
            )
        }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = Self.commandEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw GitCommandError(
                command: "sh",
                output: String(data: error, encoding: .utf8) ?? ""
            )
        }
        return output
    }

    func sshDirectoryEntries(relativePath: String) throws -> [SSHFileEntry] {
        guard let sshRepository else { return [] }
        let directory = URL(fileURLWithPath: sshRepository.path)
            .appendingPathComponent(relativePath)
            .path
        let command = """
        find \(Self.shellQuote(directory)) -mindepth 1 -maxdepth 1 -exec sh -c '\
        for item do \
        if [ -L "$item" ]; then type=l; \
        elif [ -d "$item" ]; then type=d; \
        else type=f; fi; \
        printf "%s\\0%s\\0" "$type" "${item##*/}"; \
        done' sh {} +
        """
        return Self.parseSSHDirectoryEntries(try runSSH(command))
    }

    static func parseSSHDirectoryEntries(_ data: Data) -> [SSHFileEntry] {
        let fields = data
            .split(separator: 0, omittingEmptySubsequences: false)
            .dropLast()
        return stride(from: 0, to: fields.count, by: 2).compactMap { index in
            guard index + 1 < fields.count,
                  let type = String(data: fields[index], encoding: .utf8),
                  let name = String(data: fields[index + 1], encoding: .utf8),
                  name != ".git" else { return nil }
            return SSHFileEntry(
                name: name,
                isDirectory: type == "d",
                isSymbolicLink: type == "l"
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func downloadSSHFile(relativePath: String, to fileURL: URL) throws {
        guard let sshRepository else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let remotePath = URL(fileURLWithPath: sshRepository.path)
            .appendingPathComponent(relativePath)
            .path
        try runRsync([
            "-a",
            "-e", SSHConnection.rsyncRemoteShell,
            "\(sshRepository.host):\(Self.shellQuote(remotePath))",
            fileURL.path
        ])
    }

    func uploadSSHFile(_ fileURL: URL, relativePath: String) throws {
        guard let sshRepository else { return }
        let remotePath = URL(fileURLWithPath: sshRepository.path)
            .appendingPathComponent(relativePath)
            .path
        try runRsync([
            "-a",
            "-e", SSHConnection.rsyncRemoteShell,
            fileURL.path,
            "\(sshRepository.host):\(Self.shellQuote(remotePath))"
        ])
    }

    func snapshot(
        maxGraphCount: Int = 50,
        historyScope: GitHistoryScope = .all
    ) throws -> RepositorySnapshot {
        try Task.checkCancellation()
        let status: RepositoryStatusSnapshot
        let referenceSnapshot: ReferenceSnapshot
        let activeOperation: GitOperation?
        if sshRepository != nil {
            let overview = try remoteRepositoryOverview()
            status = overview.status
            referenceSnapshot = overview.references
            activeOperation = overview.activeOperation
        } else {
            status = try repositoryStatusSnapshot()
            try Task.checkCancellation()
            referenceSnapshot = try self.referenceSnapshot()
            activeOperation = operationInProgress()
        }
        let allReferences = referenceSnapshot.references
        let upstream = status.hasUpstream
            ? referenceSnapshot.upstreamReference
            : nil
        let historyResult: GitHistoryPage
        if let headHash = status.headHash {
            try Task.checkCancellation()
            historyResult = try history(
                maxCount: maxGraphCount,
                scope: historyScope,
                remoteReferenceID: upstream?.id,
                knownHeadHash: headHash,
                referencesByCommitHash: referenceSnapshot.referencesByCommitHash
            )
        } else {
            historyResult = GitHistoryPage(
                rows: [],
                headHash: nil,
                nextOffset: 0,
                hasMore: false,
                layoutState: GraphLayoutState()
            )
        }
        let fastForwardReferenceIDs: Set<String> = status.headHash == nil
            ? []
            : {
                guard !Task.isCancelled else { return Set<String>() }
                return self.fastForwardReferenceIDs()
            }()

        try Task.checkCancellation()

        return RepositorySnapshot(
            branch: referenceSnapshot.headBranchName ?? status.branch,
            staged: status.workingTree.staged,
            unstaged: status.workingTree.unstaged,
            resolveUndoPaths: status.workingTree.resolveUndoPaths,
            graph: historyResult.rows,
            references: allReferences,
            upstreamReference: upstream,
            headHash: historyResult.headHash,
            ahead: status.ahead,
            behind: status.behind,
            hasUpstream: status.hasUpstream && upstream != nil,
            isRebaseInProgress: activeOperation == .rebase,
            activeOperation: activeOperation,
            fastForwardReferenceIDs: fastForwardReferenceIDs,
            historyOffset: historyResult.nextOffset,
            graphHasMore: historyResult.hasMore,
            graphLayoutState: historyResult.layoutState,
            referencesByCommitHash: referenceSnapshot.referencesByCommitHash
        )
    }

    func snapshotAsync(
        maxGraphCount: Int = 50,
        historyScope: GitHistoryScope = .all
    ) async throws -> RepositorySnapshot {
        let status: RepositoryStatusSnapshot
        let referenceSnapshot: ReferenceSnapshot
        let activeOperation: GitOperation?
        if sshRepository != nil {
            let overview = try await Task.detached(priority: .userInitiated) {
                try remoteRepositoryOverview()
            }.value
            status = overview.status
            referenceSnapshot = overview.references
            activeOperation = overview.activeOperation
        } else {
            async let statusValue = Task.detached(priority: .userInitiated) {
                try repositoryStatusSnapshot()
            }.value
            async let referencesValue = Task.detached(priority: .userInitiated) {
                try self.referenceSnapshot()
            }.value
            async let operationValue = Task.detached(priority: .userInitiated) {
                operationInProgress()
            }.value
            (status, referenceSnapshot, activeOperation) = try await (
                statusValue,
                referencesValue,
                operationValue
            )
        }
        let upstream = status.hasUpstream
            ? referenceSnapshot.upstreamReference
            : nil

        let historyTask = Task.detached(priority: .userInitiated) {
            guard let headHash = status.headHash else {
                return GitHistoryPage(
                    rows: [],
                    headHash: nil,
                    nextOffset: 0,
                    hasMore: false,
                    layoutState: GraphLayoutState()
                )
            }
            return try history(
                maxCount: maxGraphCount,
                scope: historyScope,
                remoteReferenceID: upstream?.id,
                knownHeadHash: headHash,
                referencesByCommitHash: referenceSnapshot.referencesByCommitHash
            )
        }
        let fastForwardTask = Task.detached(priority: .userInitiated) {
            status.headHash == nil ? Set<String>() : self.fastForwardReferenceIDs()
        }
        let historyResult = try await historyTask.value
        let fastForwardReferenceIDs = await fastForwardTask.value
        try Task.checkCancellation()

        return RepositorySnapshot(
            branch: referenceSnapshot.headBranchName ?? status.branch,
            staged: status.workingTree.staged,
            unstaged: status.workingTree.unstaged,
            resolveUndoPaths: status.workingTree.resolveUndoPaths,
            graph: historyResult.rows,
            references: referenceSnapshot.references,
            upstreamReference: upstream,
            headHash: historyResult.headHash,
            ahead: status.ahead,
            behind: status.behind,
            hasUpstream: status.hasUpstream && upstream != nil,
            isRebaseInProgress: activeOperation == .rebase,
            activeOperation: activeOperation,
            fastForwardReferenceIDs: fastForwardReferenceIDs,
            historyOffset: historyResult.nextOffset,
            graphHasMore: historyResult.hasMore,
            graphLayoutState: historyResult.layoutState,
            referencesByCommitHash: referenceSnapshot.referencesByCommitHash
        )
    }

    func repositoryStatusSnapshot() throws -> RepositoryStatusSnapshot {
        let output = try run(Self.repositoryStatusArguments)
        return repositoryStatusSnapshot(
            statusOutput: output,
            resolveUndoOutput: try run(Self.resolveUndoArguments)
        )
    }

    private static let repositoryStatusArguments = [
        "status",
        "--porcelain=v2",
        "--branch",
        "-z",
        // Keep large generated directories represented by a single item.
        "--untracked-files=normal"
    ]

    private static let resolveUndoArguments = [
        "ls-files", "--resolve-undo", "-z"
    ]

    private func repositoryStatusSnapshot(
        statusOutput: String,
        resolveUndoOutput: String
    ) -> RepositoryStatusSnapshot {
        let parsed = parseRepositoryStatus(statusOutput)
        return RepositoryStatusSnapshot(
            branch: parsed.branch,
            headHash: parsed.headHash,
            upstreamName: parsed.upstreamName,
            ahead: parsed.ahead,
            behind: parsed.behind,
            workingTree: WorkingTreeSnapshot(
                staged: parsed.workingTree.staged,
                unstaged: parsed.workingTree.unstaged,
                resolveUndoPaths: Self.parseResolveUndoPaths(resolveUndoOutput)
            ),
            hasUpstream: parsed.hasUpstream
        )
    }

    func workingTreeSnapshot() throws -> WorkingTreeSnapshot {
        let status = try run([
            "status",
            "--porcelain=v1",
            "-z",
            // Let Git collapse untracked directories before producing output.
            // Enumerating every descendant can keep repository opening blocked
            // for a very long time in dependency and build directories.
            "--untracked-files=normal"
        ])
        let parsed = parseStatus(status)
        return WorkingTreeSnapshot(
            staged: parsed.staged,
            unstaged: parsed.unstaged,
            resolveUndoPaths: try resolveUndoPaths()
        )
    }

    func history(
        maxCount: Int = 50,
        scope: GitHistoryScope = .all,
        remoteReferenceID: String? = nil
    ) throws -> GitHistoryPage {
        let referenceSnapshot = try referenceSnapshot()
        let headHash: String
        do {
            headHash = try run(["rev-parse", "--verify", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as GitCommandError where error.isUnbornHead {
            return GitHistoryPage(
                rows: [],
                headHash: nil,
                nextOffset: 0,
                hasMore: false,
                layoutState: GraphLayoutState()
            )
        }
        return try history(
            maxCount: maxCount,
            scope: scope,
            remoteReferenceID: remoteReferenceID,
            knownHeadHash: headHash,
            referencesByCommitHash: referenceSnapshot.referencesByCommitHash
        )
    }

    private func history(
        maxCount: Int,
        scope: GitHistoryScope,
        remoteReferenceID: String?,
        knownHeadHash: String,
        referencesByCommitHash: [String: [GitReference]]
    ) throws -> GitHistoryPage {
        try historyPage(
            offset: 0,
            count: maxCount,
            scope: scope,
            remoteReferenceID: remoteReferenceID,
            knownHeadHash: knownHeadHash,
            layoutState: GraphLayoutState(),
            referencesByCommitHash: referencesByCommitHash
        )
    }

    func historyPage(
        offset: Int,
        count: Int,
        scope: GitHistoryScope,
        remoteReferenceID: String?,
        knownHeadHash: String,
        layoutState: GraphLayoutState,
        referencesByCommitHash: [String: [GitReference]]
    ) throws -> GitHistoryPage {
        let requestedCount = max(1, count)
        let allReferencesAreAtHead = !referencesByCommitHash.isEmpty
            && referencesByCommitHash.keys.allSatisfy { $0 == knownHeadHash }
        let historyReferencesByCommitHash = scope == .everything
            ? try referenceSnapshot(includingInternalRefs: true).referencesByCommitHash
            : referencesByCommitHash
        let revisions: [String]
        switch scope {
        case .current:
            revisions = ["HEAD"]
        case .all where allReferencesAreAtHead:
            revisions = ["HEAD"]
        case .all:
            let hasStash = referencesByCommitHash.values
                .joined()
                .contains { $0.id == "refs/stash" }
            revisions = [
                "--branches",
                "--remotes",
                "--tags"
            ] + (hasStash ? ["refs/stash"] : []) + ["HEAD"]
        case .everything:
            revisions = ["--all", "HEAD"]
        case .reflog:
            return try reflogHistoryPage(
                offset: offset,
                count: requestedCount,
                knownHeadHash: knownHeadHash,
                layoutState: layoutState,
                referencesByCommitHash: referencesByCommitHash
            )
        }
        let format = "--pretty=format:%H%x1f%P%x1f%an%x1f%ar%x1f%s%x00"
        let output: String
        var paginationState = layoutState
        if offset > 0 {
            let bufferedIndex = offset - paginationState.historyHashBufferOffset
            let requiredHashCount = requestedCount + 1
            let hashStride = paginationState.historyHashLength + 1
            let bufferedHashCount = hashStride > 1
                ? paginationState.historyHashBuffer.count / hashStride
                : 0
            if bufferedIndex < 0
                || bufferedIndex + requiredHashCount > bufferedHashCount {
                paginationState.historyHashBufferOffset = offset
                let hashOutput = try run([
                    "rev-list",
                    "--date-order",
                    "--skip=\(offset)",
                    "--max-count=2050"
                ] + revisions)
                paginationState.historyHashLength = hashOutput.firstIndex(of: "\n")
                    .map { hashOutput.distance(from: hashOutput.startIndex, to: $0) }
                    ?? hashOutput.utf8.count
                paginationState.historyHashBuffer = Data(hashOutput.utf8)
            }
            let startIndex = offset - paginationState.historyHashBufferOffset
            let currentStride = paginationState.historyHashLength + 1
            let currentHashCount = currentStride > 1
                ? paginationState.historyHashBuffer.count / currentStride
                : 0
            let endIndex = min(
                startIndex + requiredHashCount,
                currentHashCount
            )
            let hashes: [String] = startIndex >= 0 && startIndex < endIndex
                ? (startIndex..<endIndex).compactMap { index in
                    let start = index * currentStride
                    let end = start + paginationState.historyHashLength
                    return String(
                        data: paginationState.historyHashBuffer[start..<end],
                        encoding: .utf8
                    )
                }
                : []
            guard !hashes.isEmpty else {
                return GitHistoryPage(
                    rows: [],
                    headHash: knownHeadHash.isEmpty ? nil : knownHeadHash,
                    nextOffset: offset,
                    hasMore: false,
                    layoutState: layoutState
                )
            }
            output = try run([
                "log",
                "--no-walk=unsorted",
                "--date=relative",
                format
            ] + hashes)
        } else {
            output = try run([
                "log",
                "--date-order",
                "--date=relative",
                "--max-count=\(requestedCount + 1)",
                format
            ] + revisions)
        }

        let parsedCommits = parseHistory(
            output,
            referencesByCommitHash: historyReferencesByCommitHash
        )
        let hasMore = parsedCommits.count > requestedCount
        let commits = Array(parsedCommits.prefix(requestedCount))
        let layout = GraphLayout.page(
            commits: commits,
            headHash: knownHeadHash,
            remoteReferenceID: remoteReferenceID,
            initialState: paginationState
        )
        return GitHistoryPage(
            rows: layout.rows,
            headHash: knownHeadHash.isEmpty ? nil : knownHeadHash,
            nextOffset: max(0, offset) + commits.count,
            hasMore: hasMore,
            layoutState: layout.state
        )
    }

    // The reflog scope lists HEAD's reflog entries in reflog order, one row
    // per entry, instead of walking commit topology: entries repeat commits
    // and are ordered by when HEAD moved, so a topological graph would bury
    // the actual log. Rows keep the commit's real parents (file diffs and
    // menus depend on them) and chain visually through a single lane.
    private func reflogHistoryPage(
        offset: Int,
        count: Int,
        knownHeadHash: String,
        layoutState: GraphLayoutState,
        referencesByCommitHash: [String: [GitReference]]
    ) throws -> GitHistoryPage {
        // No `--date` option, so `%gd` yields index selectors (`HEAD@{N}`)
        // that uniquely identify entries repeating the same commit.
        let format =
            "--pretty=format:%H%x1f%P%x1f%an%x1f%ar%x1f%gd%x1f%gs%x1f%s%x00"
        let output = try run([
            "log",
            "--walk-reflogs",
            "--skip=\(max(0, offset))",
            "--max-count=\(count + 1)",
            format,
            "HEAD"
        ])
        let entries = parseReflogHistory(
            output,
            referencesByCommitHash: referencesByCommitHash
        )
        let hasMore = entries.count > count
        let visible = Array(entries.prefix(count))
        var rows: [GraphRow] = []
        rows.reserveCapacity(visible.count)
        for (index, commit) in visible.enumerated() {
            let isNewestEntry = offset <= 0 && index == 0
            let nextHash = index + 1 < entries.count
                ? entries[index + 1].hash
                : nil
            rows.append(GraphRow(
                commit: commit,
                kind: isNewestEntry ? .head : .node,
                inputLanes: isNewestEntry
                    ? []
                    : [GraphLane(id: commit.hash, color: .current)],
                outputLanes: nextHash.map {
                    [GraphLane(id: $0, color: .current)]
                } ?? []
            ))
        }
        return GitHistoryPage(
            rows: rows,
            headHash: knownHeadHash.isEmpty ? nil : knownHeadHash,
            nextOffset: max(0, offset) + visible.count,
            hasMore: hasMore,
            layoutState: layoutState
        )
    }

    private func parseReflogHistory(
        _ output: String,
        referencesByCommitHash: [String: [GitReference]]
    ) -> [CommitInfo] {
        output.split(separator: "\0", omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let record = rawRecord.drop(while: \.isNewline)
                let fields = record.split(
                    separator: "\u{1F}",
                    maxSplits: 6,
                    omittingEmptySubsequences: false
                )
                guard fields.count == 7 else { return nil }

                let hash = String(fields[0])
                return CommitInfo(
                    hash: hash,
                    shortHash: String(hash.prefix(7)),
                    parentHashes: fields[1]
                        .split(whereSeparator: \.isWhitespace)
                        .map(String.init),
                    author: String(fields[2]),
                    relativeDate: String(fields[3]),
                    references: referencesByCommitHash[hash] ?? [],
                    subject: String(fields[6]),
                    reflogSelector: String(fields[4]),
                    reflogSubject: String(fields[5])
                )
            }
    }

    func repositoryWatchPaths() throws -> [String] {
        if sshRepository != nil { return [] }
        try Task.checkCancellation()
        let root = repositoryURL.standardizedFileURL
        let paths = try run([
            "rev-parse",
            "--absolute-git-dir",
            "--git-common-dir"
        ]).split(whereSeparator: \.isNewline).map(String.init)
        guard paths.count == 2 else {
            throw GitCommandError(
                command: "git rev-parse --absolute-git-dir --git-common-dir",
                output: "Git did not return both repository metadata paths."
            )
        }
        let gitDirectory = URL(
            fileURLWithPath: paths[0],
            isDirectory: true
        ).standardizedFileURL

        try Task.checkCancellation()
        let commonDirectoryValue = paths[1]
        let commonDirectory: URL
        if commonDirectoryValue.hasPrefix("/") {
            commonDirectory = URL(
                fileURLWithPath: commonDirectoryValue,
                isDirectory: true
            ).standardizedFileURL
        } else {
            commonDirectory = URL(
                fileURLWithPath: commonDirectoryValue,
                relativeTo: root
            ).standardizedFileURL
        }

        var seen = Set<String>()
        return [root.path, gitDirectory.path, commonDirectory.path].filter {
            seen.insert($0).inserted && FileManager.default.fileExists(atPath: $0)
        }
    }

    func stage(_ path: String) throws {
        _ = try run(["add", "--", path])
    }

    func stageAll() throws {
        _ = try run(["add", "-A"])
    }

    func reopenConflict(_ path: String, during operation: GitOperation) throws {
        try requireInProgress(operation)
        guard try resolveUndoPaths().contains(path) else {
            throw GitCommandError(
                command: "git checkout -m -- \(path)",
                output: "Git no longer has the conflict versions needed to reopen this file."
            )
        }
        _ = try run(["checkout", "-m", "--", path])
    }

    func resolveConflict(
        _ path: String,
        keeping version: ConflictVersion,
        during operation: GitOperation
    ) throws {
        try requireInProgress(operation)
        let stage = version == .current ? 2 : 3
        let stages = try unmergedStages(for: path)
        guard !stages.isEmpty else {
            throw GitCommandError(
                command: "git resolve -- \(path)",
                output: "The selected file no longer has an unresolved merge conflict."
            )
        }

        if stages.contains(stage) {
            let flag = version == .current ? "--ours" : "--theirs"
            _ = try run(["checkout", flag, "--", path])
            _ = try run(["add", "--", path])
        } else {
            // A missing stage means that side deleted the path. Recording the
            // deletion is the correct equivalent of choosing that version.
            _ = try run(["rm", "--ignore-unmatch", "--", path])
        }
    }

    func conflictDocument(for path: String) throws -> ConflictDocument? {
        let stages = try unmergedStages(for: path)
        guard !stages.isEmpty else { return nil }
        let fileURL = try validatedWorkingTreeFileURL(for: path)
        if let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
           !data.contains(0),
           let text = String(data: data, encoding: .utf8),
           let document = ConflictDocument.parse(path: path, text: text) {
            return document
        }
        return try reconstructedConflictDocument(for: path, stages: stages)
    }

    func conflictSideLabels(
        for operation: GitOperation,
        document: ConflictDocument?
    ) -> ConflictSideLabels {
        let markerLabel = document?.hunks.first?.incomingLabel.nilIfEmpty
        switch operation {
        case .merge:
            let incomingRevision = gitStateValue(at: ["MERGE_HEAD"])
            return ConflictSideLabels(
                current: symbolicHeadBranch(),
                incoming: incomingRevision.flatMap {
                    referenceName(pointingAt: $0, preferred: markerLabel)
                } ?? markerLabel
            )
        case .rebase:
            let ontoRevision = gitStateValue(at: [
                "rebase-merge/onto",
                "rebase-apply/onto"
            ])
            let rebasedHead = gitStateValue(at: [
                "rebase-merge/head-name",
                "rebase-apply/head-name"
            ]).flatMap(branchName(fromFullReference:))
            return ConflictSideLabels(
                current: ontoRevision.flatMap { referenceName(pointingAt: $0) },
                incoming: rebasedHead ?? markerLabel
            )
        case .cherryPick:
            let revision = gitStateValue(at: ["CHERRY_PICK_HEAD"])
            return ConflictSideLabels(
                current: symbolicHeadBranch(),
                incoming: revision.flatMap {
                    referenceName(pointingAt: $0, preferred: markerLabel)
                        ?? compactCommitLabel(for: $0)
                } ?? markerLabel
            )
        case .revert:
            let revision = gitStateValue(at: ["REVERT_HEAD"])
            return ConflictSideLabels(
                current: symbolicHeadBranch(),
                incoming: revision.flatMap {
                    referenceName(pointingAt: $0, preferred: markerLabel)
                        ?? compactCommitLabel(for: $0, prefix: "Revert")
                }
            )
        }
    }

    func conflictFilePreview(
        for path: String,
        sideLabels: ConflictSideLabels
    ) throws -> GitFilePreview? {
        let stages = try unmergedStages(for: path)
        guard !stages.isEmpty else { return nil }
        return try GitFilePreviewMaterializer.make(
            old: stages.contains(2) ? .blob(object: ":2:\(path)", path: path) : nil,
            new: stages.contains(3) ? .blob(object: ":3:\(path)", path: path) : nil,
            oldContext: sideLabels.current ?? "Current version",
            newContext: sideLabels.incoming ?? "Incoming version",
            client: self
        )
    }

    func resolveConflict(
        _ path: String,
        with resolvedText: String,
        during operation: GitOperation
    ) throws {
        try requireInProgress(operation)
        guard !(try unmergedStages(for: path)).isEmpty else {
            throw GitCommandError(
                command: "git resolve -- \(path)",
                output: "The selected file no longer has an unresolved conflict."
            )
        }
        let fileURL = try validatedWorkingTreeFileURL(for: path)
        guard let data = resolvedText.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
        _ = try run(["add", "--", path])
    }

    func unstage(_ path: String, previousPath: String? = nil) throws {
        let paths = [path, previousPath]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, path in
                if !result.contains(path) {
                    result.append(path)
                }
            }
        do {
            _ = try run(["restore", "--staged", "--"] + paths)
        } catch {
            _ = try run(["reset", "HEAD", "--"] + paths)
        }
    }

    func unstageAll() throws {
        do {
            _ = try run(["restore", "--staged", "."])
        } catch {
            _ = try run(["reset", "HEAD", "--", "."])
        }
    }

    func discard(_ path: String, isUntracked: Bool) throws {
        if isUntracked {
            if sshRepository != nil {
                _ = try run(["clean", "-f", "--", path])
                return
            }
            let root = repositoryURL.standardizedFileURL
            let target = root.appendingPathComponent(path).standardizedFileURL
            guard target.path.hasPrefix(root.path + "/") else {
                throw GitCommandError(
                    command: "discard -- \(path)",
                    output: "The selected path is outside the repository."
                )
            }
            try FileManager.default.removeItem(at: target)
            return
        }

        do {
            _ = try run(["restore", "--worktree", "--", path])
        } catch {
            _ = try run(["checkout", "--", path])
        }
    }

    func discardAllUnstagedChanges() throws {
        let changes = try workingTreeSnapshot().unstaged
        if changes.contains(where: { $0.status != "U" }) {
            do {
                _ = try run(["restore", "--worktree", "."])
            } catch {
                _ = try run(["checkout", "--", "."])
            }
        }
        if changes.contains(where: { $0.status == "U" }) {
            _ = try run(["clean", "-fd"])
        }
    }

    func discardAllChanges() throws {
        _ = try run(["reset", "--hard", "HEAD"])
        _ = try run(["clean", "-fd"])
    }

    @discardableResult
    func stash(message: String?, includeUntracked: Bool) throws -> String {
        var arguments = ["stash", "push"]
        if includeUntracked {
            arguments.append("--include-untracked")
        }
        if let message, !message.isEmpty {
            arguments.append(contentsOf: ["--message", message])
        }
        return try run(arguments)
    }

    func commit(message: String) throws -> String {
        try run(["commit", "-m", message])
    }

    func amend(message: String) throws -> String {
        try run(["commit", "--amend", "-m", message])
    }

    func amendNoEdit() throws -> String {
        try run(["commit", "--amend", "--no-edit"])
    }

    func fetch(timeout: TimeInterval = Self.networkOperationTimeout) throws -> String {
        do {
            return try run(
                ["fetch", "--all", "--prune"],
                timeout: timeout
            )
        } catch let error as GitCommandError {
            let marker = "couldn't find remote ref "
            guard let markerRange = error.output.range(of: marker),
                  let missingRef = error.output[markerRange.upperBound...]
                    .split(whereSeparator: { $0.isNewline }).first else {
                throw error
            }

            var repaired = false
            for remote in try run(["remote"]).split(whereSeparator: { $0.isNewline }) {
                let configKey = "remote.\(remote).fetch"
                let fetchSpecs = try run(
                    ["config", "--get-all", configKey],
                    allowedExitCodes: [0, 1]
                ).split(whereSeparator: { $0.isNewline })
                guard let staleSpec = fetchSpecs.first(where: {
                    $0.split(separator: ":", maxSplits: 1).first?
                        .trimmingPrefix("+") == missingRef
                }) else { continue }
                let wildcard = "+refs/heads/*:refs/remotes/\(remote)/*"
                if fetchSpecs.contains(Substring(wildcard)) {
                    _ = try run([
                        "config", "--fixed-value", "--unset-all",
                        configKey, String(staleSpec)
                    ])
                } else {
                    _ = try run([
                        "config", "--fixed-value", "--replace-all",
                        configKey, wildcard, String(staleSpec)
                    ])
                }
                repaired = true
            }
            guard repaired else { throw error }
            return try run(
                ["fetch", "--all", "--prune"],
                timeout: timeout
            )
        }
    }

    func pull() throws -> String {
        try run(["pull"], timeout: Self.networkOperationTimeout)
    }

    func pullRebasing() throws -> String {
        try run(["pull", "--rebase"], timeout: Self.networkOperationTimeout)
    }

    func push() throws -> String {
        try run(["push"], timeout: Self.networkOperationTimeout)
    }

    func forcePushWithLease() throws -> String {
        try run(["push", "--force-with-lease"], timeout: Self.networkOperationTimeout)
    }

    func forcePush() throws -> String {
        try run(["push", "--force"], timeout: Self.networkOperationTimeout)
    }

    func rebaseIsInProgress() -> Bool {
        operationInProgress() == .rebase
    }

    func abortRebase() throws -> String {
        try abortOperation(.rebase)
    }

    func operationInProgress() -> GitOperation? {
        if let sshRepository {
            guard let output = try? runSSH(
                Self.remoteOperationCommand(path: sshRepository.path)
            ) else { return nil }
            return Self.parseOperation(String(decoding: output, as: UTF8.self))
        }
        guard let gitDirectory = absoluteGitDirectory() else { return nil }
        let exists: (String) -> Bool = {
            FileManager.default.fileExists(
                atPath: gitDirectory.appendingPathComponent($0).path
            )
        }
        if exists("rebase-merge") || exists("rebase-apply") { return .rebase }
        if exists("MERGE_HEAD") { return .merge }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        return nil
    }

    static func remoteOperationCommand(path: String) -> String {
        let gitDirectoryCommand = remoteCommand(
            path: path,
            gitArguments: configuredGitArguments(["rev-parse", "--absolute-git-dir"])
        )
        let script = """
        kvist_git_dir=$(\(gitDirectoryCommand)) || exit $?
        if [ -d "$kvist_git_dir/rebase-merge" ] || [ -d "$kvist_git_dir/rebase-apply" ]; then
          printf 'rebase\\n'
        elif [ -f "$kvist_git_dir/MERGE_HEAD" ]; then
          printf 'merge\\n'
        elif [ -f "$kvist_git_dir/CHERRY_PICK_HEAD" ]; then
          printf 'cherry-pick\\n'
        elif [ -f "$kvist_git_dir/REVERT_HEAD" ]; then
          printf 'revert\\n'
        fi
        """
        return posixShellCommand(script)
    }

    private static func parseOperation(_ output: String) -> GitOperation? {
        GitOperation(rawValue: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func continueOperation(_ operation: GitOperation) throws -> String {
        try requireInProgress(operation)
        return try run([operation.rawValue, "--continue"])
    }

    func skipOperation(_ operation: GitOperation) throws -> String {
        try requireInProgress(operation)
        guard operation != .merge else {
            throw GitCommandError(
                command: "git merge --skip",
                output: "Git does not support skipping a merge. Continue or abort it instead."
            )
        }
        return try run([operation.rawValue, "--skip"])
    }

    func abortOperation(_ operation: GitOperation) throws -> String {
        try requireInProgress(operation)
        return try run([operation.rawValue, "--abort"])
    }

    func originRemoteURL() -> String? {
        guard let value = try? run(["remote", "get-url", "origin"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    func linkOrigin(to remoteURL: String) throws {
        let value = try Self.validatedRemoteURL(
            remoteURL,
            command: "git remote add origin"
        )
        guard originRemoteURL() == nil else {
            throw GitCommandError(
                command: "git remote add origin",
                output: "A remote named origin is already linked to this repository."
            )
        }
        _ = try run(["remote", "add", "origin", value])
    }

    func remotes() throws -> [GitRemote] {
        try Self.parseRemotes(run(["remote", "-v"]))
    }

    static func parseRemotes(_ output: String) throws -> [GitRemote] {
        var values: [String: (fetch: String?, push: String?)] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(where: \.isWhitespace) else { continue }
            let name = String(line[..<separator])
            guard !name.isEmpty,
                  !name.hasPrefix("-"),
                  !name.contains("\r") else {
                throw GitCommandError(command: "git remote -v", output: "Invalid remote name.")
            }
            let description = line[separator...]
                .trimmingCharacters(in: .whitespaces)
            let kind: String
            if description.hasSuffix(" (fetch)") {
                kind = "fetch"
            } else if description.hasSuffix(" (push)") {
                kind = "push"
            } else {
                continue
            }
            let url = String(description.dropLast(kind.count + 3))
            var remote = values[name] ?? (nil, nil)
            if kind == "fetch", remote.fetch == nil {
                remote.fetch = url
            } else if kind == "push", remote.push == nil {
                remote.push = url
            }
            values[name] = remote
        }
        return values.compactMap { name, value in
            guard let fetchURL = value.fetch, let pushURL = value.push else { return nil }
            return GitRemote(name: name, fetchURL: fetchURL, pushURL: pushURL)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func addRemote(name: String, url: String) throws {
        let remote = try validatedNewRemoteName(name)
        let remoteURL = try Self.validatedRemoteURL(url, command: "git remote add")
        _ = try run(["remote", "add", remote, remoteURL])
    }

    func setRemoteURL(name: String, url: String) throws {
        let remote = try validatedExistingRemoteName(name)
        let remoteURL = try Self.validatedRemoteURL(url, command: "git remote set-url")
        _ = try run(["remote", "set-url", remote, remoteURL])
    }

    func removeRemote(name: String) throws {
        let remote = try validatedExistingRemoteName(name)
        _ = try run(["remote", "remove", remote])
    }

    func setUpstream(branch: String, remoteBranch: String) throws {
        let local = try validatedBranchName(branch)
        let tracking = try validatedRemoteBranchName(remoteBranch)
        _ = try run(["show-ref", "--verify", "refs/remotes/\(tracking)"])
        _ = try run(["branch", "--set-upstream-to=\(tracking)", "--", local])
    }

    func unsetUpstream(branch: String) throws {
        let local = try validatedBranchName(branch)
        _ = try run(["branch", "--unset-upstream", "--", local])
    }

    func publish(branch: String) throws -> String {
        try run(
            ["push", "--set-upstream", "origin", branch],
            timeout: Self.networkOperationTimeout
        )
    }

    func sync() throws -> String {
        let pullOutput = try pullRebasing()
        let pushOutput = try push()
        return [pullOutput, pushOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    func diff(for change: FileChange) throws -> String {
        if change.area == .staged {
            return try run(["diff", "--cached", "--", change.path], allowedExitCodes: [0, 1])
        }

        if change.status == "U" {
            if change.path.hasSuffix("/") {
                return "This untracked directory is shown as one item. Stage it to inspect per-file diffs."
            }
            return try run(
                ["diff", "--no-index", "--", "/dev/null", change.path],
                allowedExitCodes: [0, 1]
            )
        }

        return try run(["diff", "--", change.path], allowedExitCodes: [0, 1])
    }

    func preview(for change: FileChange) throws -> GitFilePreview? {
        let oldSource: GitFilePreviewSource?
        let newSource: GitFilePreviewSource?
        let oldContext: String
        let newContext: String

        if change.status == "!" {
            oldSource = .blob(object: ":2:\(change.path)", path: change.path)
            newSource = workingTreePreviewSource(for: change.path)
            oldContext = "Ours"
            newContext = "Working Tree"
        } else if change.area == .staged {
            let oldPath = change.previousPath ?? change.path
            oldSource = change.status == "A"
                ? nil
                : .blob(object: "HEAD:\(oldPath)", path: oldPath)
            newSource = change.status == "D"
                ? nil
                : .blob(object: ":\(change.path)", path: change.path)
            oldContext = "HEAD"
            newContext = "Staged"
        } else {
            let oldPath = change.previousPath ?? change.path
            oldSource = change.status == "U"
                ? nil
                : .blob(object: ":\(oldPath)", path: oldPath)
            newSource = change.status == "D"
                ? nil
                : workingTreePreviewSource(for: change.path)
            oldContext = "Staged"
            newContext = "Working Tree"
        }

        return try GitFilePreviewMaterializer.make(
            old: oldSource,
            new: newSource,
            oldContext: oldContext,
            newContext: newContext,
            client: self
        )
    }

    private func workingTreePreviewSource(for path: String) -> GitFilePreviewSource? {
        let resolvedRootURL = repositoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedFileURL = repositoryURL
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = resolvedRootURL.path.hasSuffix("/")
            ? resolvedRootURL.path
            : resolvedRootURL.path + "/"
        guard resolvedFileURL.path.hasPrefix(rootPrefix) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolvedFileURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else { return nil }
        return .workingTree(resolvedFileURL)
    }

    func commitDetails(hash: String) throws -> String {
        let resolvedHash = try resolvedCommitHash(hash)
        return try run([
            "show",
            "--stat",
            "--decorate=short",
            "--format=fuller",
            "--no-ext-diff",
            resolvedHash
        ])
    }

    func commitMessage(hash: String) throws -> String {
        let resolvedHash = try resolvedCommitHash(hash)
        return try run(["log", "-1", "--format=%B", resolvedHash])
            .trimmingCharacters(in: .newlines)
    }

    func commitFiles(hash: String) throws -> [CommitFileChange] {
        let commit = try commitIdentity(hash)
        return try commitFiles(hash: commit.hash, firstParent: commit.firstParent)
    }

    func commitFiles(_ commit: CommitInfo) throws -> [CommitFileChange] {
        try commitFiles(hash: commit.hash, firstParent: commit.parentHashes.first)
    }

    private func commitFiles(
        hash: String,
        firstParent: String?
    ) throws -> [CommitFileChange] {
        let arguments: [String]

        if let firstParent {
            arguments = [
                "diff-tree",
                "--no-commit-id",
                "--name-status",
                "-z",
                "-r",
                "--no-ext-diff",
                "--no-renames",
                firstParent,
                hash
            ]
        } else {
            arguments = [
                "diff-tree",
                "--root",
                "--no-commit-id",
                "--name-status",
                "-z",
                "-r",
                "--no-renames",
                hash
            ]
        }

        let changes = parseCommitFiles(try run(arguments, allowedExitCodes: [0, 1]))
        let statuses = Set(changes.map(\.status))
        guard statuses.contains("A"), statuses.contains("D") else { return changes }
        var renameArguments = arguments
        if let noRenamesIndex = renameArguments.firstIndex(of: "--no-renames") {
            renameArguments[noRenamesIndex] = "-M"
        }
        return parseCommitFiles(try run(renameArguments, allowedExitCodes: [0, 1]))
    }

    func commitDiff(hash: String) throws -> String {
        let commit = try commitIdentity(hash)
        if let firstParent = commit.firstParent {
            return try run([
                "diff",
                "--no-ext-diff",
                "--find-renames",
                firstParent,
                commit.hash
            ], allowedExitCodes: [0, 1])
        }
        return try run([
            "show",
            "--format=",
            "--no-ext-diff",
            "--find-renames",
            commit.hash
        ], allowedExitCodes: [0, 1])
    }

    func commitFileDiff(hash: String, file: CommitFileChange) throws -> String {
        let commit = try commitIdentity(hash)
        let paths = [file.previousPath, file.path]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, path in
                if !result.contains(path) {
                    result.append(path)
                }
            }
        let arguments: [String]

        if let firstParent = commit.firstParent {
            arguments = [
                "diff",
                "--no-ext-diff",
                "--find-renames",
                firstParent,
                commit.hash,
                "--"
            ] + paths
        } else {
            arguments = [
                "show",
                "--format=",
                "--no-ext-diff",
                "--find-renames",
                commit.hash,
                "--"
            ] + paths
        }

        return try run(arguments, allowedExitCodes: [0, 1])
    }

    func commitFilePreview(
        hash: String,
        file: CommitFileChange
    ) throws -> GitFilePreview? {
        let commit = try commitIdentity(hash)
        let oldPath = file.previousPath ?? file.path
        let oldSource: GitFilePreviewSource? = if file.status == "A" {
            nil
        } else if let firstParent = commit.firstParent {
            .blob(object: "\(firstParent):\(oldPath)", path: oldPath)
        } else {
            nil
        }
        let newSource: GitFilePreviewSource? = file.status == "D"
            ? nil
            : .blob(object: "\(commit.hash):\(file.path)", path: file.path)

        return try GitFilePreviewMaterializer.make(
            old: oldSource,
            new: newSource,
            oldContext: commit.firstParent.map { String($0.prefix(7)) } ?? "Parent",
            newContext: String(commit.hash.prefix(7)),
            client: self
        )
    }

    func checkoutDetached(hash: String) throws {
        let resolvedHash = try resolvedCommitHash(hash)
        try switchOrCheckout(
            switchArguments: ["--detach", resolvedHash],
            checkoutArguments: ["--detach", resolvedHash]
        )
    }

    func checkout(reference: GitReference) throws {
        switch reference.kind {
        case .localBranch:
            _ = try run(["check-ref-format", "--branch", reference.name])
            try switchOrCheckout(
                switchArguments: ["--", reference.name],
                checkoutArguments: [reference.name]
            )
        case .remoteBranch:
            let revision = try resolvedReference(reference)
            let remoteHash = try resolvedReferenceHash(reference)
            let parts = reference.name.split(separator: "/", maxSplits: 1)
            let localName = parts.count == 2 ? String(parts[1]) : reference.name
            _ = try run(["check-ref-format", "--branch", localName])
            if (try? run([
                "show-ref",
                "--verify",
                "--quiet",
                "refs/heads/\(localName)"
            ])) != nil {
                let localHash = try run([
                    "rev-parse",
                    "--verify",
                    "refs/heads/\(localName)^{commit}"
                ]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard localHash == remoteHash else {
                    throw GitCommandError(
                        command: "git switch \(reference.name)",
                        output: """
                        A local branch named \(localName) already exists at a different commit \
                        than \(reference.name). Check out the local branch directly, or rename \
                        or delete it before checking out this remote branch.
                        """
                    )
                }
                try switchOrCheckout(
                    switchArguments: ["--", localName],
                    checkoutArguments: [localName]
                )
            } else {
                try switchOrCheckout(
                    switchArguments: ["--track", revision],
                    checkoutArguments: ["--track", revision]
                )
            }
        case .tag:
            let revision = try resolvedReference(reference)
            try switchOrCheckout(
                switchArguments: ["--detach", revision],
                checkoutArguments: ["--detach", revision]
            )
        case .other:
            throw GitCommandError(
                command: "git switch",
                output: "This reference cannot be checked out."
            )
        }
    }

    func integrate(
        _ reference: GitReference,
        strategy: BranchIntegrationStrategy,
        allowConflicts: Bool = false
    ) throws {
        let target = try resolvedReference(reference)
        let targetHash = try resolvedReferenceHash(reference)
        let headHash = try run(["rev-parse", "--verify", "HEAD^{commit}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentBranch = try run(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !currentBranch.isEmpty else {
            throw manualIntegrationError(
                "The repository is in detached HEAD state. Check out a local branch first."
            )
        }
        guard try run(["status", "--porcelain=v1", "-z"]).isEmpty else {
            throw manualIntegrationError(
                "The working tree has uncommitted changes. Commit or stash them first."
            )
        }
        guard !integrationIsInProgress() else {
            throw manualIntegrationError(
                "Another merge, rebase, or cherry-pick is already in progress. Finish or abort it first."
            )
        }
        guard headHash != targetHash else {
            throw manualIntegrationError(
                "The current branch already points to \(reference.name)."
            )
        }

        switch strategy {
        case .fastForward:
            guard try isAncestor(headHash, of: targetHash) else {
                throw manualIntegrationError(
                    "A fast-forward is not available because the branches have diverged."
                )
            }
            _ = try run(["merge", "--ff-only", target])

        case .merge:
            guard !(try isAncestor(targetHash, of: headHash)) else {
                throw manualIntegrationError(
                    "The current branch already contains every commit from \(reference.name)."
                )
            }
            guard !(try isAncestor(headHash, of: targetHash)) else {
                throw manualIntegrationError(
                    "This can be fast-forwarded. Use Fast-Forward Current Branch instead."
                )
            }
            if !allowConflicts {
                try requireConflictFreeMerge(headHash: headHash, targetHash: targetHash)
            }
            do {
                _ = try run(["merge", "--no-edit", target])
            } catch {
                if allowConflicts, operationInProgress() == .merge {
                    return
                }
                _ = try? run(["merge", "--abort"])
                throw manualIntegrationError(
                    "Git could not complete the merge cleanly. The attempted merge was aborted. Perform it manually to resolve the details."
                )
            }

        case .rebase:
            guard !(try isAncestor(targetHash, of: headHash)) else {
                throw manualIntegrationError(
                    "The current branch is already based on \(reference.name)."
                )
            }
            guard !(try isAncestor(headHash, of: targetHash)) else {
                throw manualIntegrationError(
                    "This can be fast-forwarded without rewriting commits. Use Fast-Forward Current Branch instead."
                )
            }
            try requireStraightforwardRebase(headHash: headHash, targetHash: targetHash)
            do {
                _ = try run(["rebase", target])
            } catch {
                _ = try? run(["rebase", "--abort"])
                throw manualIntegrationError(
                    "Git could not complete the rebase cleanly. The attempted rebase was aborted. Perform it manually to resolve the details."
                )
            }
        }
    }

    func rebase(_ branch: GitReference, onto base: GitReference) throws {
        guard branch.kind == .localBranch else {
            throw manualIntegrationError(
                "Check out \(branch.name) as a local branch before rebasing it."
            )
        }

        let branchName = try validatedBranchName(branch.name)
        let branchHash = try resolvedReferenceHash(branch)
        let baseRevision = try resolvedReference(base)
        let baseHash = try resolvedReferenceHash(base)
        let currentBranch = try run(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !currentBranch.isEmpty else {
            throw manualIntegrationError(
                "The repository is in detached HEAD state. Check out a local branch first."
            )
        }
        guard try run(["status", "--porcelain=v1", "-z"]).isEmpty else {
            throw manualIntegrationError(
                "The working tree has uncommitted changes. Commit or stash them first."
            )
        }
        guard !integrationIsInProgress() else {
            throw manualIntegrationError(
                "Another merge, rebase, or cherry-pick is already in progress. Finish or abort it first."
            )
        }
        guard branchHash != baseHash else {
            throw manualIntegrationError(
                "\(branch.name) already points to \(base.name)."
            )
        }
        guard !(try isAncestor(baseHash, of: branchHash)) else {
            throw manualIntegrationError(
                "\(branch.name) is already based on \(base.name)."
            )
        }

        do {
            _ = try run(["rebase", baseRevision, branchName])
        } catch {
            if operationInProgress() == .rebase {
                throw error
            }

            if currentBranch != branchName {
                try? switchOrCheckout(
                    switchArguments: ["--", currentBranch],
                    checkoutArguments: [currentBranch]
                )
            }
            throw error
        }
    }

    func createBranch(
        name: String,
        at hash: String,
        checkout: Bool = true
    ) throws {
        let branchName = try validatedBranchName(name)
        let resolvedHash = try resolvedCommitHash(hash)
        if checkout {
            try switchOrCheckout(
                switchArguments: ["--no-track", "-c", branchName, resolvedHash],
                checkoutArguments: ["--no-track", "-b", branchName, resolvedHash]
            )
        } else {
            _ = try run(["branch", "--", branchName, resolvedHash])
        }
    }

    func deleteLocalBranch(name: String, force: Bool = false) throws {
        let branchName = try validatedBranchName(name)
        _ = try run(["branch", force ? "-D" : "-d", "--", branchName])
    }

    func renameBranch(oldName: String, to newName: String) throws {
        let oldBranchName = try validatedBranchName(oldName)
        let newBranchName = try validatedBranchName(newName)
        guard oldBranchName != newBranchName else {
            throw GitCommandError(
                command: "git branch --move",
                output: "Enter a different name for the branch."
            )
        }
        _ = try run(["branch", "--move", "--", oldBranchName, newBranchName])
    }

    func deleteRemoteBranch(name: String) throws {
        let components = name.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            throw GitCommandError(
                command: "git push --delete",
                output: "Invalid remote branch name."
            )
        }

        let remote = components[0]
        let branch = components[1]
        _ = try run(["remote", "get-url", remote])
        _ = try run(["check-ref-format", "refs/heads/\(branch)"])
        _ = try run(["push", remote, "--delete", branch])
    }

    func createTag(
        name: String,
        at hash: String,
        message: String? = nil
    ) throws {
        let tagName = try validatedTagName(name)
        let resolvedHash = try resolvedCommitHash(hash)
        if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            _ = try run(["tag", "-a", "-m", message, "--", tagName, resolvedHash])
        } else {
            _ = try run(["tag", "--", tagName, resolvedHash])
        }
    }

    func deleteTag(name: String) throws {
        let tagName = try validatedTagName(name)
        _ = try run(["tag", "-d", "--", tagName])
    }

    func pushTag(name: String, remote: String) throws {
        let tagName = try validatedTagName(name)
        let remoteName = try validatedExistingRemoteName(remote)
        _ = try run(["show-ref", "--verify", "refs/tags/\(tagName)"])
        _ = try run(["push", remoteName, "refs/tags/\(tagName):refs/tags/\(tagName)"])
    }

    func deleteRemoteTag(name: String, remote: String) throws {
        let tagName = try validatedTagName(name)
        let remoteName = try validatedExistingRemoteName(remote)
        _ = try run(["push", remoteName, ":refs/tags/\(tagName)"])
    }

    func cherryPick(hash: String) throws {
        let resolvedHash = try resolvedCommitHash(hash)
        _ = try run(["cherry-pick", resolvedHash])
    }

    func applyStash(hash: String) throws {
        _ = try run(["stash", "apply", try stashReference(for: hash)])
    }

    func popStash(hash: String) throws {
        _ = try run(["stash", "pop", try stashReference(for: hash)])
    }

    func dropStash(hash: String) throws {
        _ = try run(["stash", "drop", try stashReference(for: hash)])
    }

    /// `git stash pop`/`drop` only accept reflog-style references, so map
    /// a stash commit hash from the graph back to its `stash@{n}` entry.
    private func stashReference(for hash: String) throws -> String {
        let resolvedHash = try resolvedCommitHash(hash)
        let entries = try run(["stash", "list", "--format=%H %gd"])
        for line in entries.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 1)
            if fields.count == 2, fields[0] == Substring(resolvedHash) {
                return String(fields[1])
            }
        }
        throw GitCommandError(
            command: "git stash list",
            output: "The stash \(resolvedHash) no longer exists. It may have been popped or dropped elsewhere."
        )
    }

    func revert(hash: String) throws {
        let resolvedHash = try resolvedCommitHash(hash)
        _ = try run(["revert", "--no-edit", resolvedHash])
    }

    func reset(to hash: String, mode: GitResetMode) throws {
        let resolvedHash = try resolvedCommitHash(hash)
        _ = try run(["reset", mode.rawValue, resolvedHash])
    }

    func references() throws -> [GitReference] {
        try referenceSnapshot().references
    }

    private func referenceSnapshot(
        includingInternalRefs: Bool = false
    ) throws -> ReferenceSnapshot {
        let namespaces = includingInternalRefs
            ? ["refs"]
            : ["refs/heads", "refs/remotes", "refs/tags", "refs/stash"]
        let arguments = [
            "for-each-ref",
            "--format=%(refname)%09%(HEAD)%09%(upstream)%09%(objectname)%09%(*objectname)%09%(symref)"
        ] + namespaces
        return parseReferenceSnapshot(try run(arguments))
    }

    private static let standardReferenceArguments = [
        "for-each-ref",
        "--format=%(refname)%09%(HEAD)%09%(upstream)%09%(objectname)%09%(*objectname)%09%(symref)",
        "refs/heads",
        "refs/remotes",
        "refs/tags",
        "refs/stash"
    ]

    private func parseReferenceSnapshot(_ output: String) -> ReferenceSnapshot {
        var upstreamID: String?
        var headBranchName: String?
        var referencesByCommitHash: [String: [GitReference]] = [:]
        let references = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> GitReference? in
                let fields = line.split(
                    separator: "\t",
                    maxSplits: 5,
                    omittingEmptySubsequences: false
                )
                guard let fullName = fields.first.map(String.init) else { return nil }
                let isHead = fields.count > 1
                    && fields[1].trimmingCharacters(in: .whitespaces) == "*"
                if isHead, fields.count > 2 {
                    let candidate = fields[2].trimmingCharacters(in: .whitespaces)
                    if !candidate.isEmpty {
                        upstreamID = candidate
                    }
                }
                let symbolicTarget = fields.count > 5
                    ? String(fields[5]).nilIfEmpty
                    : nil
                let parsedReference = reference(
                    fullName: fullName,
                    isHead: isHead,
                    symbolicTarget: symbolicTarget
                )
                if isHead, parsedReference?.kind == .localBranch {
                    headBranchName = parsedReference?.name
                }
                if let parsedReference, fields.count > 3 {
                    let directHash = String(fields[3])
                    let peeledHash = fields.count > 4 ? String(fields[4]) : ""
                    let commitHash = peeledHash.isEmpty ? directHash : peeledHash
                    referencesByCommitHash[commitHash, default: []].append(parsedReference)
                }
                return parsedReference
            }
        return ReferenceSnapshot(
            references: references,
            referencesByCommitHash: referencesByCommitHash,
            upstreamReference: upstreamID.flatMap { id in
                references.first { $0.id == id }
                    ?? reference(fullName: id, isHead: false)
            },
            headBranchName: headBranchName
        )
    }

    func upstreamReference() -> GitReference? {
        guard let fullName = try? run([
            "rev-parse",
            "--symbolic-full-name",
            "@{upstream}"
        ]).trimmingCharacters(in: .whitespacesAndNewlines),
        !fullName.isEmpty else {
            return nil
        }
        return reference(fullName: fullName, isHead: false)
    }

    func comparisonDiff(
        hash: String,
        against reference: GitReference,
        fromMergeBase: Bool = false
    ) throws -> String {
        let commitHash = try resolvedCommitHash(hash)
        let referenceHash = try resolvedReferenceHash(reference)
        let baseHash: String

        if fromMergeBase {
            baseHash = try run(["merge-base", commitHash, referenceHash])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            baseHash = referenceHash
        }

        return try run([
            "diff",
            "--no-ext-diff",
            "--find-renames",
            baseHash,
            commitHash
        ], allowedExitCodes: [0, 1])
    }

    func githubCommitURL(hash: String) throws -> URL? {
        let resolvedHash = try resolvedCommitHash(hash)
        guard let remoteURL = try? run(["remote", "get-url", "origin"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
        let repositoryPath = githubRepositoryPath(from: remoteURL) else {
            return nil
        }
        return URL(string: "https://github.com/\(repositoryPath)/commit/\(resolvedHash)")
    }

    func githubPullRequestURL(for reference: GitReference) throws -> URL? {
        guard let remoteBranch = reference.remoteBranchComponents,
              remoteBranch.branch != "HEAD" else { return nil }
        let remoteName = try validatedExistingRemoteName(remoteBranch.remote)
        let remoteURL = try run(["remote", "get-url", remoteName])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let repositoryPath = githubRepositoryPath(from: remoteURL) else {
            return nil
        }

        // Resolve the remote-tracking ref before offering GitHub the branch.
        // This prevents a fabricated or stale local-only reference from being
        // turned into a pull-request URL.
        _ = try resolvedReferenceHash(reference)

        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repositoryPath)/compare/\(remoteBranch.branch)"
        components.queryItems = [URLQueryItem(name: "expand", value: "1")]
        return components.url
    }

    func parseRepositoryStatus(_ output: String) -> RepositoryStatusSnapshot {
        let records = output.split(separator: "\0", omittingEmptySubsequences: true)
        var branch = "detached HEAD"
        var headHash: String?
        var upstreamName: String?
        var hasTrackingCounts = false
        var ahead = 0
        var behind = 0
        var staged: [FileChange] = []
        var unstaged: [FileChange] = []
        var recordIndex = 0

        func appendChange(
            indexStatus: Character,
            workingStatus: Character,
            path: String,
            previousPath: String? = nil
        ) {
            if indexStatus != "." {
                staged.append(FileChange(
                    path: path,
                    previousPath: previousPath,
                    status: displayStatus(for: indexStatus),
                    area: .staged
                ))
            }
            if workingStatus != "." {
                unstaged.append(FileChange(
                    path: path,
                    previousPath: previousPath,
                    status: displayStatus(for: workingStatus),
                    area: .unstaged
                ))
            }
        }

        while recordIndex < records.count {
            let record = records[recordIndex]
            if record.hasPrefix("# branch.oid ") {
                let value = String(record.dropFirst("# branch.oid ".count))
                headHash = value == "(initial)" ? nil : value
            } else if record.hasPrefix("# branch.head ") {
                let value = String(record.dropFirst("# branch.head ".count))
                branch = value == "(detached)" ? "detached HEAD" : value
            } else if record.hasPrefix("# branch.upstream ") {
                upstreamName = String(record.dropFirst("# branch.upstream ".count))
            } else if record.hasPrefix("# branch.ab ") {
                hasTrackingCounts = true
                let values = record
                    .dropFirst("# branch.ab ".count)
                    .split(separator: " ")
                for value in values {
                    if value.hasPrefix("+") {
                        ahead = Int(value.dropFirst()) ?? 0
                    } else if value.hasPrefix("-") {
                        behind = Int(value.dropFirst()) ?? 0
                    }
                }
            } else if record.hasPrefix("1 ") {
                let fields = record.split(
                    separator: " ",
                    maxSplits: 8,
                    omittingEmptySubsequences: false
                )
                if fields.count == 9,
                   fields[1].count == 2 {
                    let statuses = Array(fields[1])
                    appendChange(
                        indexStatus: statuses[0],
                        workingStatus: statuses[1],
                        path: String(fields[8])
                    )
                }
            } else if record.hasPrefix("2 ") {
                let fields = record.split(
                    separator: " ",
                    maxSplits: 9,
                    omittingEmptySubsequences: false
                )
                if fields.count == 10,
                   fields[1].count == 2,
                   recordIndex + 1 < records.count {
                    let statuses = Array(fields[1])
                    appendChange(
                        indexStatus: statuses[0],
                        workingStatus: statuses[1],
                        path: String(fields[9]),
                        previousPath: String(records[recordIndex + 1])
                    )
                    recordIndex += 1
                }
            } else if record.hasPrefix("u ") {
                let fields = record.split(
                    separator: " ",
                    maxSplits: 10,
                    omittingEmptySubsequences: false
                )
                if fields.count == 11 {
                    unstaged.append(FileChange(
                        path: String(fields[10]),
                        status: "!",
                        area: .unstaged
                    ))
                }
            } else if record.hasPrefix("? ") {
                unstaged.append(FileChange(
                    path: String(record.dropFirst(2)),
                    status: "U",
                    area: .unstaged
                ))
            }
            recordIndex += 1
        }

        let ordering: (FileChange, FileChange) -> Bool = {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        return RepositoryStatusSnapshot(
            branch: branch,
            headHash: headHash,
            upstreamName: upstreamName,
            ahead: ahead,
            behind: behind,
            workingTree: WorkingTreeSnapshot(
                staged: staged.sorted(by: ordering),
                unstaged: unstaged.sorted(by: ordering),
                resolveUndoPaths: []
            ),
            hasUpstream: upstreamName != nil && hasTrackingCounts
        )
    }

    func parseStatus(_ output: String) -> (staged: [FileChange], unstaged: [FileChange]) {
        var staged: [FileChange] = []
        var unstaged: [FileChange] = []

        let records = output.split(separator: "\0", omittingEmptySubsequences: true)
        var recordIndex = 0

        while recordIndex < records.count {
            let characters = Array(records[recordIndex])
            guard characters.count >= 4 else {
                recordIndex += 1
                continue
            }

            let indexStatus = characters[0]
            let workingStatus = characters[1]
            let path = String(characters.dropFirst(3))
            let statusPair = String([indexStatus, workingStatus])
            if Self.unmergedStatusPairs.contains(statusPair) {
                unstaged.append(FileChange(
                    path: path,
                    status: "!",
                    area: .unstaged
                ))
                recordIndex += 1
                continue
            }
            let hasPreviousPath = indexStatus == "R"
                || indexStatus == "C"
                || workingStatus == "R"
                || workingStatus == "C"
            let previousPath = hasPreviousPath && recordIndex + 1 < records.count
                ? String(records[recordIndex + 1])
                : nil

            if indexStatus != " " && indexStatus != "?" {
                staged.append(FileChange(
                    path: path,
                    previousPath: previousPath,
                    status: displayStatus(for: indexStatus),
                    area: .staged
                ))
            }

            if workingStatus != " " || indexStatus == "?" {
                let rawStatus = indexStatus == "?" ? Character("?") : workingStatus
                unstaged.append(FileChange(
                    path: path,
                    previousPath: previousPath,
                    status: displayStatus(for: rawStatus),
                    area: .unstaged
                ))
            }

            if hasPreviousPath {
                recordIndex += 1
            }
            recordIndex += 1
        }

        let ordering: (FileChange, FileChange) -> Bool = {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        return (staged.sorted(by: ordering), unstaged.sorted(by: ordering))
    }

    private static let unmergedStatusPairs: Set<String> = [
        "DD", "AU", "UD", "UA", "DU", "AA", "UU"
    ]

    private func parseCommitFiles(_ output: String) -> [CommitFileChange] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true)
        var changes: [CommitFileChange] = []
        var index = 0

        while index < fields.count {
            let rawStatus = String(fields[index])
            index += 1
            guard let status = rawStatus.first, index < fields.count else { break }

            if status == "R" || status == "C" {
                guard index + 1 < fields.count else { break }
                changes.append(CommitFileChange(
                    path: String(fields[index + 1]),
                    previousPath: String(fields[index]),
                    status: String(status)
                ))
                index += 2
            } else {
                changes.append(CommitFileChange(
                    path: String(fields[index]),
                    previousPath: nil,
                    status: String(status)
                ))
                index += 1
            }
        }

        guard changes.count < 500 else { return changes }
        return changes.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func commitIdentity(_ hash: String) throws -> (
        hash: String,
        firstParent: String?
    ) {
        let resolvedHash = try resolvedCommitHash(hash)
        let fields = try run(["rev-list", "--parents", "-n", "1", resolvedHash])
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard fields.first == resolvedHash else {
            throw GitCommandError(
                command: "git rev-list --parents -n 1 \(resolvedHash)",
                output: "Could not read commit \(resolvedHash)."
            )
        }
        return (resolvedHash, fields.dropFirst().first)
    }

    private func resolvedCommitHash(_ hash: String) throws -> String {
        let value = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy(\.isHexDigit) else {
            throw GitCommandError(
                command: "git rev-parse --verify",
                output: "Invalid commit hash."
            )
        }
        return try run(["rev-parse", "--verify", "\(value)^{commit}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validatedBranchName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw GitCommandError(command: "git branch", output: "Enter a branch name.")
        }
        _ = try run(["check-ref-format", "--branch", value])
        return value
    }

    private func validatedTagName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw GitCommandError(command: "git tag", output: "Enter a tag name.")
        }
        _ = try run(["check-ref-format", "refs/tags/\(value)"])
        return value
    }

    private static func validatedRemoteURL(
        _ remoteURL: String,
        command: String
    ) throws -> String {
        let value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.hasPrefix("-"),
              !value.contains("\n"),
              !value.contains("\r"),
              !value.contains("\0") else {
            throw GitCommandError(
                command: command,
                output: "Enter a valid remote repository URL or local path."
            )
        }
        return value
    }

    private func validatedRemoteName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.hasPrefix("-"),
              !value.contains("\n"),
              !value.contains("\r") else {
            throw GitCommandError(
                command: "git remote",
                output: "Enter a valid remote name."
            )
        }
        _ = try run(["check-ref-format", "refs/remotes/\(value)"])
        return value
    }

    private func validatedExistingRemoteName(_ name: String) throws -> String {
        let value = try validatedRemoteName(name)
        _ = try run(["remote", "get-url", value])
        return value
    }

    private func validatedNewRemoteName(_ name: String) throws -> String {
        let value = try validatedRemoteName(name)
        if (try? run(["remote", "get-url", value])) != nil {
            throw GitCommandError(
                command: "git remote add",
                output: "A remote named \(value) already exists."
            )
        }
        return value
    }

    private func validatedRemoteBranchName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2, !components[1].isEmpty else {
            throw GitCommandError(
                command: "git branch --set-upstream-to",
                output: "Choose a remote branch such as origin/main."
            )
        }
        _ = try validatedExistingRemoteName(components[0])
        _ = try run(["check-ref-format", "refs/remotes/\(value)"])
        return value
    }

    private func reference(
        fullName: String,
        isHead: Bool,
        symbolicTarget: String? = nil
    ) -> GitReference? {
        let kind: GitReferenceKind
        let name: String

        if fullName.hasPrefix("refs/heads/") {
            kind = .localBranch
            name = String(fullName.dropFirst("refs/heads/".count))
        } else if fullName.hasPrefix("refs/remotes/") {
            kind = .remoteBranch
            name = String(fullName.dropFirst("refs/remotes/".count))
        } else if fullName.hasPrefix("refs/tags/") {
            kind = .tag
            name = String(fullName.dropFirst("refs/tags/".count))
        } else if fullName.hasPrefix("refs/") {
            kind = .other
            name = String(fullName.dropFirst("refs/".count))
        } else {
            return nil
        }

        return GitReference(
            id: fullName,
            name: name,
            kind: kind,
            isHead: isHead,
            symbolicTarget: symbolicTarget
        )
    }

    private func resolvedReference(_ reference: GitReference) throws -> String {
        let fullName: String
        switch reference.kind {
        case .localBranch:
            _ = try run(["check-ref-format", "--branch", reference.name])
            fullName = "refs/heads/\(reference.name)"
        case .remoteBranch:
            fullName = "refs/remotes/\(reference.name)"
            _ = try run(["check-ref-format", fullName])
        case .tag:
            fullName = "refs/tags/\(reference.name)"
            _ = try run(["check-ref-format", fullName])
        case .other:
            guard reference.id.hasPrefix("refs/") else {
                throw GitCommandError(
                    command: "git rev-parse --verify",
                    output: "Unsupported Git reference."
                )
            }
            fullName = reference.id
            _ = try run(["check-ref-format", fullName])
        }
        return fullName
    }

    private func resolvedReferenceHash(_ reference: GitReference) throws -> String {
        let fullName = try resolvedReference(reference)
        return try run(["rev-parse", "--verify", "\(fullName)^{commit}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAncestor(_ ancestor: String, of descendant: String) throws -> Bool {
        let mergeBase = try run(
            ["merge-base", ancestor, descendant],
            allowedExitCodes: [0, 1]
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return mergeBase == ancestor
    }

    private func fastForwardReferenceIDs() -> Set<String> {
        guard let output = try? run([
            "for-each-ref",
            "--contains=HEAD",
            "--format=%(refname)",
            "refs/heads",
            "refs/remotes"
        ]) else { return [] }
        return Set(
            output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
        )
    }

    private func integrationIsInProgress() -> Bool {
        operationInProgress() != nil
    }

    private func absoluteGitDirectory() -> URL? {
        guard let path = try? run(["rev-parse", "--absolute-git-dir"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func symbolicHeadBranch() -> String? {
        guard let output = try? run(
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            allowedExitCodes: [0, 1]
        ) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func gitStateValue(at relativePaths: [String]) -> String? {
        guard let gitDirectory = absoluteGitDirectory() else { return nil }
        for relativePath in relativePaths {
            let url = gitDirectory.appendingPathComponent(relativePath)
            guard let value = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init),
                  let value = value.nilIfEmpty else { continue }
            return value
        }
        return nil
    }

    private func branchName(fromFullReference reference: String) -> String? {
        let prefixes = ["refs/heads/", "refs/remotes/"]
        for prefix in prefixes where reference.hasPrefix(prefix) {
            return String(reference.dropFirst(prefix.count)).nilIfEmpty
        }
        return nil
    }

    private func referenceName(
        pointingAt revision: String,
        preferred: String? = nil
    ) -> String? {
        guard let output = try? run([
            "for-each-ref",
            "--format=%(refname)",
            "--points-at", revision,
            "refs/heads",
            "refs/remotes"
        ]) else { return nil }
        let references = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasSuffix("/HEAD") }
        let names = references.compactMap(branchName(fromFullReference:))
        if let preferred,
           let match = names.first(where: {
               $0 == preferred || $0.hasSuffix("/\(preferred)")
           }) {
            return match
        }
        if let localIndex = references.firstIndex(where: { $0.hasPrefix("refs/heads/") }) {
            return names[localIndex]
        }
        return names.first
    }

    private func compactCommitLabel(for revision: String, prefix: String? = nil) -> String? {
        guard let output = try? run(["show", "-s", "--format=%h · %s", revision])
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let label = output.nilIfEmpty else { return nil }
        return prefix.map { "\($0) \(label)" } ?? label
    }

    private func requireInProgress(_ operation: GitOperation) throws {
        guard let activeOperation = operationInProgress() else {
            throw GitCommandError(
                command: "git \(operation.rawValue)",
                output: "No Git operation is currently in progress."
            )
        }
        guard activeOperation == operation else {
            throw GitCommandError(
                command: "git \(operation.rawValue)",
                output: "A \(activeOperation.rawValue) is in progress, not a \(operation.rawValue)."
            )
        }
    }

    private func requireConflictFreeMerge(headHash: String, targetHash: String) throws {
        do {
            _ = try run(["merge-tree", "--write-tree", headHash, targetHash])
        } catch {
            throw PredictedMergeConflictError()
        }
    }

    private func unmergedStages(for path: String) throws -> Set<Int> {
        let output = try run(["ls-files", "-u", "-z", "--", path])
        return Set(output.split(separator: "\0").compactMap { record in
            guard let tab = record.firstIndex(of: "\t") else { return nil }
            let fields = record[..<tab].split(separator: " ")
            guard fields.count == 3 else { return nil }
            return Int(fields[2])
        })
    }

    private func resolveUndoPaths() throws -> Set<String> {
        Self.parseResolveUndoPaths(try run(Self.resolveUndoArguments))
    }

    private static func parseResolveUndoPaths(_ output: String) -> Set<String> {
        return Set(output.split(separator: "\0").compactMap { record in
            guard let separator = record.firstIndex(of: "\t") else { return nil }
            return String(record[record.index(after: separator)...])
        })
    }

    private func reconstructedConflictDocument(
        for path: String,
        stages: Set<Int>
    ) throws -> ConflictDocument? {
        guard stages.isSuperset(of: [1, 2, 3]) else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Kvist-Conflict-Reconstruction-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileExtension = URL(fileURLWithPath: path).pathExtension
        func temporaryFile(_ name: String) -> URL {
            let fileName = fileExtension.isEmpty ? name : "\(name).\(fileExtension)"
            return directory.appendingPathComponent(fileName)
        }

        let currentURL = temporaryFile("Current")
        let baseURL = temporaryFile("Base")
        let incomingURL = temporaryFile("Incoming")
        try writePreviewBlob(object: ":2:\(path)", to: currentURL)
        try writePreviewBlob(object: ":1:\(path)", to: baseURL)
        try writePreviewBlob(object: ":3:\(path)", to: incomingURL)

        for url in [currentURL, baseURL, incomingURL] {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  !data.contains(0),
                  String(data: data, encoding: .utf8) != nil else { return nil }
        }

        let merged = try run(
            [
                "merge-file", "-p", "--diff3",
                "-L", "Current", "-L", "Base", "-L", "Incoming",
                currentURL.path, baseURL.path, incomingURL.path
            ],
            allowedExitCodes: [0, 1]
        )
        return ConflictDocument.parse(path: path, text: merged)
    }

    private func validatedWorkingTreeFileURL(for path: String) throws -> URL {
        let root = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let target = repositoryURL
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard target.path.hasPrefix(rootPrefix) else {
            throw GitCommandError(
                command: "git resolve -- \(path)",
                output: "The selected path is outside the repository."
            )
        }
        return target
    }

    private func requireStraightforwardRebase(headHash: String, targetHash: String) throws {
        try requireConflictFreeMerge(headHash: headHash, targetHash: targetHash)
        let mergeBase = try run(["merge-base", headHash, targetHash])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentChanges = try changedPaths(from: mergeBase, to: headHash)
        let targetChanges = try changedPaths(from: mergeBase, to: targetHash)

        guard currentChanges.isDisjoint(with: targetChanges) else {
            throw manualIntegrationError(
                "Both branches modify at least one of the same files, so Kvist cannot prove the rebase will be straightforward. Rebase manually."
            )
        }
    }

    private func changedPaths(from base: String, to tip: String) throws -> Set<String> {
        let changes = parseCommitFiles(try run([
            "diff", "--name-status", "-z", "--find-renames", base, tip
        ], allowedExitCodes: [0, 1]))
        guard !changes.contains(where: { $0.status == "R" || $0.status == "C" }) else {
            throw manualIntegrationError(
                "The branches include renamed or copied files, so Kvist cannot prove the rebase is straightforward. Rebase manually."
            )
        }
        return Set(changes.flatMap { [$0.path, $0.previousPath].compactMap { $0 } })
    }

    private func manualIntegrationError(_ reason: String) -> GitCommandError {
        GitCommandError(
            command: "branch integration safety check",
            output: "Kvist did not change the current branch. \(reason)"
        )
    }

    private func switchOrCheckout(
        switchArguments: [String],
        checkoutArguments: [String]
    ) throws {
        do {
            _ = try run(["switch"] + switchArguments)
        } catch let error as GitCommandError {
            let output = error.output.lowercased()
            guard output.contains("not a git command")
                    || output.contains("unknown subcommand") else {
                throw error
            }
            _ = try run(["checkout"] + checkoutArguments)
        }
    }

    private func githubRepositoryPath(from remoteURL: String) -> String? {
        let rawPath: String
        if remoteURL.hasPrefix("git@github.com:") {
            rawPath = String(remoteURL.dropFirst("git@github.com:".count))
        } else if let url = URL(string: remoteURL),
                  url.host?.lowercased() == "github.com" {
            rawPath = url.path
        } else {
            return nil
        }

        var path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") {
            path.removeLast(4)
        }
        guard path.split(separator: "/").count == 2 else { return nil }
        return path
    }

    private func displayStatus(for character: Character) -> String {
        switch character {
        case "?": return "U"
        case "A": return "A"
        case "D": return "D"
        case "R": return "R"
        case "C": return "C"
        case "U": return "!"
        default: return "M"
        }
    }

    private func parseHistory(
        _ output: String,
        referencesByCommitHash: [String: [GitReference]]
    ) -> [CommitInfo] {
        var internedHashes: [String: String] = [:]
        func internHash(_ value: Substring) -> String {
            let hash = String(value)
            if let existing = internedHashes[hash] { return existing }
            internedHashes[hash] = hash
            return hash
        }

        return output.split(separator: "\0", omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let record = rawRecord.drop(while: \.isNewline)
                let fields = record.split(
                    separator: "\u{1F}",
                    maxSplits: 4,
                    omittingEmptySubsequences: false
                )
                guard fields.count == 5 else { return nil }

                let hash = internHash(fields[0])

                return CommitInfo(
                    hash: hash,
                    shortHash: String(hash.prefix(7)),
                    parentHashes: fields[1]
                        .split(whereSeparator: \.isWhitespace)
                        .map(internHash),
                    author: String(fields[2]),
                    relativeDate: String(fields[3]),
                    references: referencesByCommitHash[hash] ?? [],
                    subject: String(fields[4])
                )
            }
    }

    func searchRepository(
        for rawQuery: String,
        fileLimit: Int = 200,
        textLimit: Int = 300
    ) throws -> RepositorySearchResults {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }

        let pathsOutput = try run([
            "ls-files", "--cached", "--others", "--exclude-standard", "-z"
        ])
        let allFileMatches = RepositorySearchParser.filePaths(from: pathsOutput)
            .compactMap { path -> RepositoryFileSearchMatch? in
                guard let score = RepositoryPathMatcher.score(
                    query: query,
                    path: path
                ) else {
                    return nil
                }
                return RepositoryFileSearchMatch(path: path, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
        let resolvedFileLimit = max(0, fileLimit)
        let fileMatches = Array(allFileMatches.prefix(resolvedFileLimit))

        let grepOutput = try run([
            "grep",
            "-n",
            "-z",
            "-I",
            "--full-name",
            "--no-color",
            "--ignore-case",
            "--fixed-strings",
            "--max-count=20",
            "--untracked",
            "-e",
            query,
            "--"
        ], allowedExitCodes: [0, 1])
        let parsedTextMatches = RepositorySearchParser.textMatches(
            from: grepOutput,
            limit: max(0, textLimit)
        )

        return RepositorySearchResults(
            fileMatches: fileMatches,
            textMatches: parsedTextMatches.matches,
            fileMatchesWereLimited: allFileMatches.count > fileMatches.count,
            textMatchesWereLimited: parsedTextMatches.wasLimited
        )
    }

    @discardableResult
    private func run(
        _ arguments: [String],
        allowedExitCodes: Set<Int32> = [0],
        timeout: TimeInterval? = nil
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()

        let gitArguments = Self.configuredGitArguments(arguments)
        if let sshRepository {
            process.executableURL = SSHConnection.executableURL
            process.arguments = SSHConnection.arguments(
                host: sshRepository.host,
                command: Self.remoteCommand(
                    path: sshRepository.path,
                    gitArguments: gitArguments
                )
            )
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = gitArguments
            process.currentDirectoryURL = repositoryURL
        }
        process.environment = Self.commandEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputBuffer = GitCommandOutputBuffer()
        let outputHandle = outputPipe.fileHandleForReading
        let completion = DispatchSemaphore(value: 0)
        let outputCompletion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            throw GitCommandError(
                command: "git \(arguments.joined(separator: " "))",
                output: error.localizedDescription
            )
        }
        KvistRuntimeMetrics.gitProcessStarted(
            repositoryURL: repositoryURL,
            processID: process.processIdentifier
        )
        defer {
            KvistRuntimeMetrics.gitProcessFinished(processID: process.processIdentifier)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            outputBuffer.append(outputHandle.readDataToEndOfFile())
            outputCompletion.signal()
        }

        let deadline = timeout.map { Date().addingTimeInterval($0) }
        var wasCancelled = false
        var timedOut = false
        var terminationDeadline: Date?
        while completion.wait(timeout: .now() + .milliseconds(20)) == .timedOut {
            if Task.isCancelled || deadline.map({ Date() >= $0 }) == true {
                timedOut = !Task.isCancelled
                wasCancelled = true
                if terminationDeadline == nil {
                    process.terminate()
                    terminationDeadline = Date().addingTimeInterval(2)
                } else if Date() >= terminationDeadline! {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        process.waitUntilExit()
        if timedOut { try? outputHandle.close() }
        outputCompletion.wait()
        if !Task.isCancelled, deadline.map({ Date() >= $0 }) == true {
            timedOut = true
        }
        if timedOut {
            let seconds = Int(timeout ?? 0)
            throw GitCommandError(
                command: "git \(arguments.joined(separator: " "))",
                output: "The Git operation timed out after \(seconds) seconds. Check the network or remote host and try again."
            )
        }
        if wasCancelled || Task.isCancelled {
            throw CancellationError()
        }
        let output = String(data: outputBuffer.value(), encoding: .utf8) ?? ""

        guard allowedExitCodes.contains(process.terminationStatus) else {
            throw GitCommandError(
                command: "git \(arguments.joined(separator: " "))",
                output: output
            )
        }
        return output
    }

    private static func configuredGitArguments(_ arguments: [String]) -> [String] {
        [
            "-c", "core.quotepath=false",
            // Kvist owns refresh scheduling, so a command-triggered detached
            // maintenance process only adds contention and self-watcher events.
            "-c", "maintenance.auto=false",
            "-c", "gc.auto=0"
        ] + arguments
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func remoteCommand(path: String, gitArguments: [String]) -> String {
        ([
            "env",
            "LC_ALL=C",
            "LANG=C",
            "GIT_OPTIONAL_LOCKS=0",
            "GIT_TERMINAL_PROMPT=0",
            "GCM_INTERACTIVE=Never",
            "GIT_EDITOR=true",
            "GIT_SEQUENCE_EDITOR=true",
            "GIT_MERGE_AUTOEDIT=no",
            "GIT_PAGER=cat",
            "git",
            "-C",
            path
        ] + gitArguments)
            .map(shellQuote)
            .joined(separator: " ")
    }

    private func remoteRepositoryOverview() throws -> RemoteRepositoryOverview {
        guard let sshRepository else {
            throw GitCommandError(command: "ssh", output: "Missing SSH repository.")
        }
        let commands = [
            Self.remoteCommand(
                path: sshRepository.path,
                gitArguments: Self.configuredGitArguments(Self.repositoryStatusArguments)
            ),
            Self.remoteCommand(
                path: sshRepository.path,
                gitArguments: Self.configuredGitArguments(Self.resolveUndoArguments)
            ),
            Self.remoteCommand(
                path: sshRepository.path,
                gitArguments: Self.configuredGitArguments(Self.standardReferenceArguments)
            ),
            Self.remoteOperationCommand(path: sshRepository.path)
        ]
        let labels = ["git status", "git ls-files", "git for-each-ref", "git rev-parse"]
        let results = try runRemoteCommands(commands)
        for (label, result) in zip(labels, results) where result.exitCode != 0 {
            throw GitCommandError(
                command: label,
                output: String(decoding: result.output, as: UTF8.self)
            )
        }
        guard results.count == commands.count else {
            throw GitCommandError(command: "ssh", output: "Incomplete SSH response.")
        }

        let statusOutput = String(decoding: results[0].output, as: UTF8.self)
        let resolveUndoOutput = String(decoding: results[1].output, as: UTF8.self)
        let referenceOutput = String(decoding: results[2].output, as: UTF8.self)
        let operationOutput = String(decoding: results[3].output, as: UTF8.self)
        return RemoteRepositoryOverview(
            status: repositoryStatusSnapshot(
                statusOutput: statusOutput,
                resolveUndoOutput: resolveUndoOutput
            ),
            references: parseReferenceSnapshot(referenceOutput),
            activeOperation: Self.parseOperation(operationOutput)
        )
    }

    private func runRemoteCommands(_ commands: [String]) throws -> [RemoteCommandResult] {
        let data = try runSSH(Self.framedRemoteCommands(commands))
        return try Self.parseRemoteCommandResults(data, expectedCount: commands.count)
    }

    static func framedRemoteCommands(_ commands: [String]) -> String {
        var lines = [
            "kvist_tmp=$(mktemp -d \"${TMPDIR:-/tmp}/kvist-git.XXXXXX\") || exit 1",
            "trap 'rm -rf \"$kvist_tmp\"' 0 1 2 15"
        ]
        for command in commands {
            lines += [
                "(\n\(command)\n) >\"$kvist_tmp/output\" 2>&1",
                "kvist_status=$?",
                "kvist_size=$(wc -c <\"$kvist_tmp/output\" | tr -d '[:space:]')",
                "printf '%s %s\\n' \"$kvist_status\" \"$kvist_size\"",
                "cat \"$kvist_tmp/output\""
            ]
        }
        return posixShellCommand(lines.joined(separator: "\n"))
    }

    private static func posixShellCommand(_ script: String) -> String {
        "/bin/sh -c \(shellQuote(script))"
    }

    static func parseRemoteCommandResults(
        _ data: Data,
        expectedCount: Int
    ) throws -> [RemoteCommandResult] {
        var cursor = data.startIndex
        var results: [RemoteCommandResult] = []
        for _ in 0..<expectedCount {
            guard cursor < data.endIndex,
                  let newline = data[cursor...].firstIndex(of: 0x0A),
                  let header = String(data: data[cursor..<newline], encoding: .utf8) else {
                throw GitCommandError(command: "ssh", output: "Malformed SSH response.")
            }
            let fields = header.split(separator: " ")
            guard fields.count == 2,
                  let exitCode = Int32(fields[0]),
                  let size = Int(fields[1]),
                  size >= 0 else {
                throw GitCommandError(command: "ssh", output: "Malformed SSH response header.")
            }
            cursor = data.index(after: newline)
            guard let end = data.index(cursor, offsetBy: size, limitedBy: data.endIndex) else {
                throw GitCommandError(command: "ssh", output: "Truncated SSH response.")
            }
            results.append(RemoteCommandResult(
                exitCode: exitCode,
                output: Data(data[cursor..<end])
            ))
            cursor = end
        }
        guard cursor == data.endIndex else {
            throw GitCommandError(command: "ssh", output: "Unexpected SSH response data.")
        }
        return results
    }

    private func runSSH(_ command: String) throws -> Data {
        guard let sshRepository else { return Data() }
        return try Self.runSSH(host: sshRepository.host, command: command)
    }

    static func runSSH(host: String, command: String) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = SSHConnection.executableURL
        process.arguments = SSHConnection.arguments(
            host: host,
            command: command
        )
        process.environment = Self.commandEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw GitCommandError(
                command: "ssh",
                output: String(data: error, encoding: .utf8) ?? ""
            )
        }
        return output
    }

    private func runRsync(_ arguments: [String]) throws {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = arguments
        process.environment = Self.commandEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw GitCommandError(
                command: "rsync",
                output: String(data: output, encoding: .utf8) ?? ""
            )
        }
    }

    func writePreviewBlob(object: String, to outputURL: URL) throws {
        let process = Process()
        let errorPipe = Pipe()

        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw GitCommandError(
                command: "git cat-file blob",
                output: "Could not create a temporary preview file."
            )
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        let gitArguments = Self.configuredGitArguments(["cat-file", "blob", object])
        if let sshRepository {
            process.executableURL = SSHConnection.executableURL
            process.arguments = SSHConnection.arguments(
                host: sshRepository.host,
                command: Self.remoteCommand(
                    path: sshRepository.path,
                    gitArguments: gitArguments
                )
            )
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = gitArguments
            process.currentDirectoryURL = repositoryURL
        }
        process.environment = Self.commandEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = errorPipe

        let errorBuffer = GitCommandOutputBuffer()
        let errorHandle = errorPipe.fileHandleForReading
        let completion = DispatchSemaphore(value: 0)
        let errorCompletion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw GitCommandError(
                command: "git cat-file blob",
                output: error.localizedDescription
            )
        }
        KvistRuntimeMetrics.gitProcessStarted(
            repositoryURL: repositoryURL,
            processID: process.processIdentifier
        )
        defer {
            KvistRuntimeMetrics.gitProcessFinished(processID: process.processIdentifier)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            errorBuffer.append(errorHandle.readDataToEndOfFile())
            errorCompletion.signal()
        }

        var wasCancelled = false
        while completion.wait(timeout: .now() + .milliseconds(20)) == .timedOut {
            if Task.isCancelled {
                wasCancelled = true
                process.terminate()
            }
        }
        process.waitUntilExit()
        errorCompletion.wait()
        if wasCancelled || Task.isCancelled {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            let errorOutput = String(data: errorBuffer.value(), encoding: .utf8) ?? ""
            try? FileManager.default.removeItem(at: outputURL)
            throw GitCommandError(
                command: "git cat-file blob",
                output: errorOutput
            )
        }
    }

}

private extension GitCommandError {
    var isUnbornHead: Bool {
        let message = output.lowercased()
        return message.contains("needed a single revision")
            || message.contains("unknown revision")
            || message.contains("ambiguous argument 'head'")
            || message.contains("bad revision 'head'")
    }
}

enum GraphLayout {
    struct Page: Sendable {
        let rows: [GraphRow]
        let state: GraphLayoutState
    }

    static func rows(
        commits: [CommitInfo],
        headHash: String?,
        remoteReferenceID: String? = nil
    ) -> [GraphRow] {
        page(
            commits: commits,
            headHash: headHash,
            remoteReferenceID: remoteReferenceID,
            initialState: GraphLayoutState()
        ).rows
    }

    static func page(
        commits: [CommitInfo],
        headHash: String?,
        remoteReferenceID: String? = nil,
        initialState: GraphLayoutState
    ) -> Page {
        var state = initialState
        let commits = collapsingStashInternals(commits, state: &state)
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            let inputLanes = state.lanes
            var outputLanes: [GraphLane] = []
            outputLanes.reserveCapacity(inputLanes.count + commit.parentHashes.count)
            var firstParentAdded = false

            if let firstParent = commit.parentHashes.first {
                for lane in inputLanes {
                    if lane.id == commit.hash {
                        if !firstParentAdded {
                            outputLanes.append(GraphLane(
                                id: firstParent,
                                color: preferredColor(
                                    for: commit,
                                    headHash: headHash,
                                    remoteReferenceID: remoteReferenceID
                                ) ?? lane.color
                            ))
                            firstParentAdded = true
                        }
                        continue
                    }

                    outputLanes.append(lane)
                }
            } else {
                outputLanes = inputLanes.filter { $0.id != commit.hash }
            }

            let unprocessedParents = firstParentAdded
                ? commit.parentHashes.dropFirst()
                : commit.parentHashes[...]

            for (offset, parentHash) in unprocessedParents.enumerated() {
                let parentIndex = firstParentAdded ? offset + 1 : offset
                var color: GraphLaneColor?

                if parentIndex == 0 {
                    color = preferredColor(
                        for: commit,
                        headHash: headHash,
                        remoteReferenceID: remoteReferenceID
                    )
                }

                if color == nil {
                    state.rotatingColorIndex = (
                        state.rotatingColorIndex + 1
                    ) % rotatingColors.count
                    color = rotatingColors[state.rotatingColorIndex]
                }

                outputLanes.append(GraphLane(id: parentHash, color: color ?? .lane1))
            }

            rows.append(GraphRow(
                commit: commit,
                kind: commit.hash == headHash ? .head : .node,
                inputLanes: inputLanes,
                outputLanes: outputLanes
            ))
            state.lanes = outputLanes
        }

        return Page(rows: rows, state: state)
    }

    // A stash is stored as a merge commit whose extra parents are git's
    // synthetic "index on …" / "untracked files on …" commits. Collapse
    // each stash to a single-parent node so the graph shows one stash
    // entry instead of its internal bookkeeping commits.
    private static func collapsingStashInternals(
        _ commits: [CommitInfo],
        state: inout GraphLayoutState
    ) -> [CommitInfo] {
        state.hiddenStashCommitHashes.formUnion(
            commits
                .filter(\.isStash)
                .flatMap { $0.parentHashes.dropFirst() }
        )
        guard !state.hiddenStashCommitHashes.isEmpty else { return commits }

        return commits.compactMap { commit in
            if state.hiddenStashCommitHashes.contains(commit.hash) { return nil }
            guard commit.isStash, commit.parentHashes.count > 1 else {
                return commit
            }
            return CommitInfo(
                hash: commit.hash,
                shortHash: commit.shortHash,
                parentHashes: Array(commit.parentHashes.prefix(1)),
                author: commit.author,
                relativeDate: commit.relativeDate,
                references: commit.references,
                subject: commit.subject
            )
        }
    }

    // Unlabelled history lanes rotate through
    // five foreground colors, while the current and upstream remote refs
    // keep their dedicated reference colors.
    private static let rotatingColors: [GraphLaneColor] = [
        .lane1, .lane2, .lane3, .lane4, .lane5
    ]

    private static func preferredColor(
        for commit: CommitInfo,
        headHash: String?,
        remoteReferenceID: String?
    ) -> GraphLaneColor? {
        if commit.hash == headHash || commit.references.contains(where: \.isHead) {
            return .current
        }
        if let remoteReferenceID,
           commit.references.contains(where: { $0.id == remoteReferenceID }) {
            return .remote
        }
        return nil
    }
}

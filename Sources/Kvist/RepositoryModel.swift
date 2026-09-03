import AppKit
import Combine
import CryptoKit
import Foundation

enum PrimaryRepositoryAction {
    case commit
    case publish
    case sync
}

enum GraphScope: String, CaseIterable, Identifiable, Codable {
    case all
    case current
    case everything
    case reflog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .current: return "Current"
        case .everything: return "All Refs"
        case .reflog: return "Reflog"
        }
    }

    var gitScope: GitHistoryScope {
        switch self {
        case .all: return .all
        case .current: return .current
        case .everything: return .everything
        case .reflog: return .reflog
        }
    }
}

extension GitOperation {
    var displayName: String {
        switch self {
        case .rebase: return "Rebase"
        case .merge: return "Merge"
        case .cherryPick: return "Cherry-pick"
        case .revert: return "Revert"
        }
    }
}

@MainActor
final class CommitMessageState: ObservableObject {
    @Published var text = ""
}

private final class RepositoryMutationQueue: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.hjalmarkarlsen.Kvist.repository-mutations",
        qos: .userInitiated
    )

    func run(
        client: GitClient,
        operation: @escaping @Sendable (GitClient) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try operation(client)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct RepositoryOpenResult: Sendable {
    let rootURL: URL
    let snapshot: RepositorySnapshot
    let remotes: [GitRemote]
    let activeOperation: GitOperation?
    let watchPaths: [String]
    let isPlainFolder: Bool
}

private struct RepositoryRefreshResult: Sendable {
    let snapshot: RepositorySnapshot
    let remotes: [GitRemote]
    let activeOperation: GitOperation?
}

struct HistoryPerformanceQueryContext: Sendable {
    let repositoryURL: URL
    let headHash: String
    let scope: GitHistoryScope
    let remoteReferenceID: String?
    let referencesByCommitHash: [String: [GitReference]]
}

struct RepositoryErrorPresentation: Equatable {
    let title: String
    let message: String
    let details: String?
}

@MainActor
final class RepositoryModel: ObservableObject {
    @Published private(set) var repositoryURL: URL?
    @Published private(set) var sshRepository: SSHRepository?
    /// The open folder is browsed and edited without Git: no snapshot,
    /// history, remotes, or source-control mode.
    @Published private(set) var isPlainFolder = false
    @Published private(set) var repositoryInitializationURL: URL?
    private(set) var deferredRepositoryOpenURL: URL?
    @Published private(set) var branch = ""
    @Published private(set) var staged: [FileChange] = []
    @Published private(set) var unstaged: [FileChange] = []
    @Published private(set) var resolveUndoPaths: Set<String> = []
    @Published private(set) var graph: [GraphRow] = []
    @Published private(set) var graphPublicationVersion = 0
    @Published private(set) var references: [GitReference] = []
    @Published private(set) var upstreamReference: GitReference?
    @Published private(set) var expandedCommitHashes: Set<String> = []
    @Published private(set) var commitFilesByHash: [String: [CommitFileChange]] = [:]
    @Published private(set) var loadingCommitFileHashes: Set<String> = []
    @Published private(set) var headHash: String?
    @Published private(set) var ahead = 0
    @Published private(set) var behind = 0
    @Published private(set) var hasUpstream = false
    @Published private(set) var isRebaseInProgress = false
    @Published private(set) var activeOperation: GitOperation?
    @Published private(set) var remotes: [GitRemote] = []
    @Published private(set) var fastForwardReferenceIDs: Set<String> = []
    @Published private(set) var graphScope: GraphScope = .all
    @Published private(set) var isLoadingMoreGraph = false
    @Published private(set) var workspaceMode: RepositoryWorkspaceMode = .sourceControl
    @Published private(set) var expandedFileDirectories: Set<String> = []
    @Published private(set) var selectedRepositoryFilePath: String?
    @Published private(set) var repositoryFilesRevision = 0
    @Published private(set) var isFileSearchPresented = false
    @Published private(set) var isFileSearchResultsPresented = false
    @Published var repositorySearchQuery = "" {
        didSet {
            guard repositorySearchQuery != oldValue else { return }
            scheduleRepositorySearch()
        }
    }
    @Published private(set) var repositorySearchResults = RepositorySearchResults.empty
    @Published private(set) var isRepositorySearchLoading = false
    @Published private(set) var repositorySearchError: String?
    let commitMessageState = CommitMessageState()
    var commitMessage: String {
        get { commitMessageState.text }
        set { commitMessageState.text = newValue }
    }
    @Published var selectedChange: FileChange?
    @Published var selectedCommit: CommitInfo?
    @Published var selectedCommitFile: CommitFileChange?
    @Published private(set) var detailText = ""
    @Published private(set) var detailTitle = "Select a changed file or commit"
    @Published private(set) var detailKind: RepositoryDetailKind = .diff
    @Published private(set) var gitFilePreview: GitFilePreview?
    @Published private(set) var gitFileDetailMode: GitFileDetailMode = .diff
    @Published private(set) var conflictResolution: ConflictResolutionSession?
    @Published private(set) var isDetailLoading = false
    var repositoryFileText = "" {
        didSet {
            repositoryFileTextRevision &+= 1
            if !repositoryFileDirty {
                if isUpdatingRepositoryFileTextFromEditor {
                    scheduleRepositoryFileDirtyPublication()
                } else {
                    repositoryFileDirty = true
                }
            }
            scheduleRepositoryFileDirtyReconciliation()
            refreshEditedFileSearchMatches()
            restorationStateDidChange?()
        }
    }
    private(set) var savedRepositoryFileText = ""
    @Published private(set) var repositoryFileDirty = false
    @Published private(set) var repositoryFileScrollRequest: SourceScrollRequest?
    @Published private(set) var isSavingRepositoryFile = false
    @Published private(set) var isDiffPanelPresented = false
    @Published private(set) var isBusy = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isAmendingCommit = false
    @Published private(set) var pendingChangePaths: Set<String> = []
    @Published private(set) var isGeneratingCommitMessage = false
    @Published private(set) var activity = "Ready"
    @Published var errorPresentation: RepositoryErrorPresentation?
    var errorMessage: String? {
        get { errorPresentation?.message }
        set {
            errorPresentation = newValue.map {
                RepositoryErrorPresentation(
                    title: "Kvist",
                    message: $0,
                    details: nil
                )
            }
        }
    }

    var unresolvedConflicts: [FileChange] {
        unstaged.filter { $0.status == "!" }
    }

    var hasUnresolvedConflicts: Bool {
        !unresolvedConflicts.isEmpty
    }

    func isReopenableConflict(_ change: FileChange) -> Bool {
        activeOperation != nil
            && change.status != "!"
            && resolveUndoPaths.contains(change.path)
    }

    private let lastRepositoryKey = "lastRepositoryPath"
    private let persistsLastRepository: Bool
    private let graphPageSize: Int
    private var detailRequestID = UUID()
    private var graphLimit: Int
    private var graphHistoryOffset = 0
    private var graphHasMore = false
    private var graphLayoutState = GraphLayoutState()
    private var referencesByCommitHash: [String: [GitReference]] = [:]
    private var graphHistoryLoadTask: Task<GitHistoryPage, Error>?
    private(set) var graphPublicationScope: GraphScope = .all
    private(set) var staleGraphPublicationCount = 0
    private var openRequestID = UUID()
    private var activeOpenRequestID: UUID?
    private var snapshotRequestID = UUID()
    private var repositoryWatcher: RepositoryWatcher?
    private var repositoryOpenLoadTask: Task<RepositoryOpenResult, Error>?
    private var repositoryCloneTask: Task<URL, Error>?
    private var sshProbeTask: Task<SSHPathKind, Error>?
    private var repositorySnapshotLoadTask: Task<RepositoryRefreshResult, Error>?
    private var workingTreeSnapshotLoadTask: Task<WorkingTreeSnapshot, Error>?
    private var repositoryFileSession: RepositoryFileSession?
    private var repositoryFileDiskVersion: RepositoryFileDiskVersion?
    private var gitDetailSession: GitDetailSession?
    private var repositoryFileDirtyReconciliationTask: Task<Void, Never>?
    private var repositoryFileDirtyPublicationTask: Task<Void, Never>?
    private var repositorySearchTask: Task<Void, Never>?
    private var isUpdatingRepositoryFileTextFromEditor = false
    private var repositoryFileTextRevision = 0
    private var liveRefreshTask: Task<Void, Never>?
    private var workingTreeRefreshTask: Task<Void, Never>?
    private var autoFetchTask: Task<Void, Never>?
    private var repositoryWatchPaths: [String] = []
    private var repositoryWatchSinceEventID = RepositoryWatcher.currentEventID()
    private var monitoringEnabled: Bool
    private var isRefreshInProgress = false
    private var syncActivityDepth = 0
    private var pendingLiveRefresh = false
    private var pendingWorkingTreeRefresh = false
    private var repositoryMetadataPaths: [String] = []
    private var workingTreeVersion = 0
    private let mutationQueue = RepositoryMutationQueue()
    private let gitPreviewDirectoryStore = GitFilePreviewDirectoryStore()
    var restorationStateDidChange: (() -> Void)?

    init(
        initialRepositoryURL: URL? = nil,
        restoresLastRepository: Bool = true,
        persistsLastRepository: Bool = true,
        graphPageSize: Int = 50,
        monitoringEnabled: Bool = true
    ) {
        self.persistsLastRepository = persistsLastRepository
        self.graphPageSize = max(1, graphPageSize)
        self.monitoringEnabled = monitoringEnabled
        graphLimit = max(1, graphPageSize)

        if let initialRepositoryURL {
            Task { [weak self] in
                await self?.openRepository(initialRepositoryURL)
            }
        } else if restoresLastRepository,
                  let path = UserDefaults.standard.string(forKey: lastRepositoryKey),
           FileManager.default.fileExists(atPath: path) {
            Task { [weak self] in
                await self?.openRepository(URL(fileURLWithPath: path, isDirectory: true))
            }
        } else if restoresLastRepository {
            UserDefaults.standard.removeObject(forKey: lastRepositoryKey)
        }
    }

    deinit {
        repositoryFileDirtyPublicationTask?.cancel()
        repositoryFileDirtyReconciliationTask?.cancel()
        repositorySearchTask?.cancel()
        repositoryOpenLoadTask?.cancel()
        repositoryCloneTask?.cancel()
        repositorySnapshotLoadTask?.cancel()
        graphHistoryLoadTask?.cancel()
        workingTreeSnapshotLoadTask?.cancel()
        liveRefreshTask?.cancel()
        workingTreeRefreshTask?.cancel()
        autoFetchTask?.cancel()
        repositoryWatcher?.stop()
        gitPreviewDirectoryStore.removeAll()
    }

    func makeRestorationState() -> RepositoryRestorationState {
        let activeEditor = selectedRepositoryFilePath.map {
            let retainsText = detailKind != .largeSource
            return RepositoryEditorRestorationState(
                path: $0,
                title: detailTitle,
                detailText: detailText,
                fileText: retainsText ? repositoryFileText : "",
                savedFileText: retainsText ? savedRepositoryFileText : "",
                kind: detailKind,
                isPanelPresented: isDiffPanelPresented,
                diskModificationDate: repositoryFileDiskVersion?.contentModificationDate,
                diskFileSize: repositoryFileDiskVersion?.fileSize,
                diskContentHash: repositoryFileDiskVersion?.contentHash
            )
        }
        let rememberedEditor = repositoryFileSession.map {
            let retainsText = $0.kind != .largeSource
            return RepositoryEditorRestorationState(
                path: $0.path,
                title: $0.title,
                detailText: $0.detailText,
                fileText: retainsText ? $0.fileText : "",
                savedFileText: retainsText ? $0.savedFileText : "",
                kind: $0.kind,
                isPanelPresented: $0.isPanelPresented,
                diskModificationDate: $0.diskVersion?.contentModificationDate,
                diskFileSize: $0.diskVersion?.fileSize,
                diskContentHash: $0.diskVersion?.contentHash
            )
        }
        return RepositoryRestorationState(
            workspaceMode: workspaceMode,
            expandedFileDirectories: expandedFileDirectories,
            expandedCommitHashes: expandedCommitHashes,
            graphScope: graphScope,
            commitMessage: commitMessage,
            editor: workspaceMode == .fileEditor ? activeEditor : rememberedEditor,
            opensAsPlainFolder: isPlainFolder
        )
    }

    func restore(from state: RepositoryRestorationState) async {
        var state = state
        if isPlainFolder {
            state.workspaceMode = .fileEditor
        }
        commitMessage = state.commitMessage
        expandedFileDirectories = state.expandedFileDirectories

        if graphScope != state.graphScope {
            await setGraphScope(state.graphScope)
        }

        for hash in state.expandedCommitHashes {
            guard let commit = graph.lazy.map(\.commit).first(where: {
                $0.hash == hash
            }) else { continue }
            toggleCommitExpansion(commit)
        }

        guard let editor = state.editor else {
            workspaceMode = state.workspaceMode
            restorationStateDidChange?()
            return
        }

        let diskVersion = RepositoryFileDiskVersion(
            contentModificationDate: editor.diskModificationDate,
            fileSize: editor.diskFileSize,
            contentHash: editor.diskContentHash
        )
        let session = RepositoryFileSession(
            path: editor.path,
            title: editor.title,
            detailText: editor.detailText,
            fileText: editor.fileText,
            savedFileText: editor.savedFileText,
            kind: editor.kind,
            isPanelPresented: editor.isPanelPresented,
            diskVersion: diskVersion
        )

        if state.workspaceMode == .sourceControl {
            repositoryFileSession = session
            workspaceMode = .sourceControl
        } else {
            workspaceMode = .fileEditor
            if editor.isPanelPresented, editor.isDirty {
                selectedRepositoryFilePath = editor.path
                detailTitle = editor.title
                detailText = editor.detailText
                repositoryFileText = editor.fileText
                savedRepositoryFileText = editor.savedFileText
                repositoryFileDirty = true
                detailKind = editor.kind
                isDiffPanelPresented = true
                repositoryFileDiskVersion = diskVersion
                errorMessage = "Recovered unsaved edits to \(editor.path)."
            } else if editor.isPanelPresented {
                openRepositoryFile(editor.path)
            } else {
                repositoryFileSession = session
            }
        }
        restorationStateDidChange?()
    }

    var repositoryName: String {
        repositoryURL?.lastPathComponent ?? "Kvist"
    }

    var hasStagedChanges: Bool {
        !staged.isEmpty
    }

    var hasChanges: Bool {
        !staged.isEmpty || !unstaged.isEmpty
    }

    var hasPendingChangeOperations: Bool {
        !pendingChangePaths.isEmpty
    }

    func isChangeOperationPending(_ change: FileChange) -> Bool {
        pendingChangePaths.contains(change.path)
    }

    var canLoadMoreGraph: Bool {
        graphHasMore
    }

    var primaryAction: PrimaryRepositoryAction {
        if isAmendingCommit {
            return .commit
        }
        if hasChanges {
            return .commit
        }
        if !hasUpstream,
           branch != "detached HEAD",
           headHash != nil {
            return .publish
        }
        if ahead > 0 || behind > 0 {
            return .sync
        }
        return .commit
    }

    var primaryActionTitle: String {
        switch primaryAction {
        case .commit:
            if isAmendingCommit { return "Amend Last Commit" }
            guard hasChanges else { return "Commit" }
            if hasStagedChanges { return "Commit Staged Changes" }
            switch UserDefaults.standard.integer(forKey: "smartCommitPreference") {
            case 1: return "Commit All Changes"
            case 2: return "Commit Staged Changes"
            default: return "Commit Changes"
            }
        case .publish:
            return "Publish Branch"
        case .sync:
            return syncLabel
        }
    }

    var primaryActionEnabled: Bool {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return false }
        switch primaryAction {
        case .commit:
            if isAmendingCommit {
                return headHash != nil
                    && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasStagedChanges { return true }
            return hasChanges
                && UserDefaults.standard.integer(forKey: "smartCommitPreference") != 2
        case .publish:
            return branch != "detached HEAD" && headHash != nil
        case .sync:
            return ahead > 0 || behind > 0
        }
    }

    var syncLabel: String {
        if ahead == 0 && behind == 0 { return "Sync Changes" }
        var parts: [String] = []
        if behind > 0 { parts.append("\(behind)↓") }
        if ahead > 0 { parts.append("\(ahead)↑") }
        return "Sync Changes \(parts.joined(separator: " "))"
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        guard monitoringEnabled != enabled else { return }
        monitoringEnabled = enabled

        if enabled {
            if !repositoryWatchPaths.isEmpty {
                repositoryFilesRevision &+= 1
                startWatching(paths: repositoryWatchPaths)
            }
            startAutoFetching()
        } else {
            autoFetchTask?.cancel()
            autoFetchTask = nil
            liveRefreshTask?.cancel()
            workingTreeRefreshTask?.cancel()
            liveRefreshTask = nil
            workingTreeRefreshTask = nil
            pendingLiveRefresh = false
            pendingWorkingTreeRefresh = false
            repositorySnapshotLoadTask?.cancel()
            workingTreeSnapshotLoadTask?.cancel()
            repositoryWatchSinceEventID = RepositoryWatcher.currentEventID()
            repositoryWatcher?.stop()
            repositoryWatcher = nil
        }
    }

    var hasActiveRepositoryWatcher: Bool {
        repositoryWatcher != nil
    }

    var hasOutstandingRepositoryTasks: Bool {
        repositoryOpenLoadTask != nil
            || repositorySnapshotLoadTask != nil
            || workingTreeSnapshotLoadTask != nil
            || liveRefreshTask != nil
            || workingTreeRefreshTask != nil
            || graphHistoryLoadTask != nil
            || isRefreshInProgress
    }

    func historyPerformanceQueryContext() -> HistoryPerformanceQueryContext? {
        guard KvistPerformanceInstrumentation.configuration?.mode == .history,
              let repositoryURL,
              let headHash else { return nil }
        return HistoryPerformanceQueryContext(
            repositoryURL: repositoryURL,
            headHash: headHash,
            scope: graphScope.gitScope,
            remoteReferenceID: upstreamReference?.id,
            referencesByCommitHash: referencesByCommitHash
        )
    }

    func chooseRepository() {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return }
        let panel = NSOpenPanel()
        panel.title = "Open Git Repository"
        panel.message = "Choose a repository or any folder inside one."
        panel.prompt = "Open Repository"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = repositoryURL ?? FileManager.default.homeDirectoryForCurrentUser

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.openRepository(url)
            }
        }
    }

    @discardableResult
    func cloneRepository(
        from remoteURL: String,
        to destinationURL: URL
    ) async -> Bool {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return false }
        let trimmedRemoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRemoteURL.isEmpty else {
            errorMessage = "Enter a remote repository URL or local Git path."
            return false
        }

        let checkoutName = cloneCheckoutName(from: trimmedRemoteURL)
        let checkoutURL = destinationURL.appendingPathComponent(
            checkoutName,
            isDirectory: true
        )
        guard !FileManager.default.fileExists(atPath: checkoutURL.path) else {
            errorMessage = "A file or folder named \(checkoutName) already exists in the selected destination."
            return false
        }

        isBusy = true
        activity = "Cloning \(checkoutName)…"
        do {
            let cloneTask = Task.detached(priority: .userInitiated) {
                try GitClient.cloneRepository(
                    from: trimmedRemoteURL,
                    to: checkoutURL
                )
            }
            repositoryCloneTask = cloneTask
            let rootURL = try await withTaskCancellationHandler {
                try await cloneTask.value
            } onCancel: {
                cloneTask.cancel()
            }
            repositoryCloneTask = nil
            isBusy = false
            await openRepository(rootURL)
            return repositoryURL?.standardizedFileURL == rootURL.standardizedFileURL
        } catch {
            repositoryCloneTask = nil
            isBusy = false
            if error is CancellationError {
                activity = repositoryURL == nil ? "Ready" : "Up to date"
                return false
            }
            present(error)
            return false
        }
    }

    private func cloneCheckoutName(from remoteURL: String) -> String {
        let candidate = remoteURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
            .split(separator: "/")
            .last
            .map(String.init) ?? "Repository"
        let scpPathComponent = candidate.split(separator: ":").last.map(String.init)
            ?? candidate
        let name = scpPathComponent.hasSuffix(".git")
            ? String(scpPathComponent.dropLast(4))
            : scpPathComponent
        guard !name.isEmpty, name != ".", name != ".." else {
            return "Repository"
        }
        return name
    }

    func openRepository(_ url: URL, asPlainFolder: Bool = false) async {
        let marker = url.appendingPathComponent(".kvist-ssh")
        if let data = try? Data(contentsOf: marker),
           let sshRepository = try? JSONDecoder().decode(SSHRepository.self, from: data) {
            await openRepository(url, overSSH: sshRepository)
            return
        }
        await openRepository(url, overSSH: nil, asPlainFolder: asPlainFolder)
    }

    /// Opens a local folder as a file browser and editor without Git.
    func openFolderWithoutGit(_ url: URL) async {
        await openRepository(url, overSSH: nil, asPlainFolder: true)
    }

    /// Leaves the initialize-repository screen and browses the folder's
    /// files without creating a Git repository.
    func browseFolderWithoutGit() async {
        guard let url = repositoryInitializationURL, !isBusy else { return }
        repositoryInitializationURL = nil
        await openFolderWithoutGit(url)
    }

    /// Opens a remote path over SSH. Git repositories get the full
    /// source-control workspace; any other folder opens as a file browser
    /// and editor.
    func openSSHRepository(host: String, path: String) async {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return }
        do {
            let location = try SSHRepository(host: host, path: path)
            isBusy = true
            activity = "Connecting to \(location.host)…"
            let probeTask = Task.detached(priority: .userInitiated) {
                try GitClient.probeSSHPath(host: location.host, path: location.path)
            }
            sshProbeTask = probeTask
            let kind: SSHPathKind
            do {
                kind = try await withTaskCancellationHandler {
                    try await probeTask.value
                } onCancel: {
                    probeTask.cancel()
                }
            } catch {
                sshProbeTask = nil
                isBusy = false
                activity = repositoryURL == nil ? "Ready" : "Up to date"
                if !(error is CancellationError) { present(error) }
                return
            }
            sshProbeTask = nil
            isBusy = false
            let sshRepository = try SSHRepository(
                host: location.host,
                path: location.path,
                isGitRepository: kind == .repository
            )
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
                .appendingPathComponent("Kvist/SSH", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(sshRepository.displayName, isDirectory: true)
            try FileManager.default.createDirectory(
                at: base,
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(sshRepository).write(
                to: base.appendingPathComponent(".kvist-ssh"),
                options: .atomic
            )
            await openRepository(base, overSSH: sshRepository)
        } catch {
            present(error)
        }
    }

    private func openRepository(
        _ url: URL,
        overSSH sshRepository: SSHRepository?,
        asPlainFolder: Bool = false
    ) async {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations,
              approveDiscardingRepositoryFileChanges() else { return }
        deferredRepositoryOpenURL = url
        let previousRepositoryRoot = repositoryURL?.standardizedFileURL.path
        repositoryInitializationURL = nil
        let requestID = UUID()
        openRequestID = requestID
        activeOpenRequestID = requestID
        snapshotRequestID = UUID()
        liveRefreshTask?.cancel()
        workingTreeRefreshTask?.cancel()
        autoFetchTask?.cancel()
        autoFetchTask = nil
        repositorySnapshotLoadTask?.cancel()
        graphHistoryLoadTask?.cancel()
        graphHistoryLoadTask = nil
        workingTreeSnapshotLoadTask?.cancel()
        pendingLiveRefresh = false
        pendingWorkingTreeRefresh = false
        isLoadingMoreGraph = false
        isBusy = true
        activity = "Opening repository…"
        var openedRepository = false
        let watcherStartEventID = RepositoryWatcher.currentEventID()

        do {
            let maxGraphCount = graphPageSize
            let historyScope = graphScope.gitScope
            let opensPlainFolder = asPlainFolder
                || sshRepository?.isGitRepository == false
            let loadTask = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                if opensPlainFolder {
                    if sshRepository == nil {
                        var isDirectory: ObjCBool = false
                        guard FileManager.default.fileExists(
                            atPath: url.path,
                            isDirectory: &isDirectory
                        ), isDirectory.boolValue else {
                            throw GitCommandError(
                                command: "open folder",
                                output: "There is no folder at \(url.path)."
                            )
                        }
                    }
                    return RepositoryOpenResult(
                        rootURL: url,
                        snapshot: .empty,
                        remotes: [],
                        activeOperation: nil,
                        watchPaths: sshRepository == nil
                            ? [url.standardizedFileURL.path]
                            : [],
                        isPlainFolder: true
                    )
                }
                let root: URL
                if let sshRepository {
                    root = url
                    try GitClient(
                        repositoryURL: root,
                        sshRepository: sshRepository
                    ).validateSSHRepository()
                } else {
                    root = try GitClient.discoverRoot(from: url)
                }
                try Task.checkCancellation()
                let client = GitClient(
                    repositoryURL: root,
                    sshRepository: sshRepository
                )
                RepositoryRefreshMetrics.recordFullSnapshot()
                async let snapshot = client.snapshotAsync(
                    maxGraphCount: maxGraphCount,
                    historyScope: historyScope
                )
                async let remotes = Task.detached(priority: .userInitiated) {
                    try client.remotes()
                }.value
                async let watchPaths = Task.detached(priority: .userInitiated) {
                    try client.repositoryWatchPaths()
                }.value
                let loadedSnapshot = try await snapshot
                return RepositoryOpenResult(
                    rootURL: root,
                    snapshot: loadedSnapshot,
                    remotes: try await remotes,
                    activeOperation: loadedSnapshot.activeOperation,
                    watchPaths: try await watchPaths,
                    isPlainFolder: false
                )
            }
            repositoryOpenLoadTask = loadTask
            let result = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }

            guard openRequestID == requestID else { return }
            repositoryOpenLoadTask = nil
            guard approveDiscardingRepositoryFileChanges() else {
                deferredRepositoryOpenURL = nil
                activeOpenRequestID = nil
                isBusy = false
                activity = repositoryURL == nil ? "Ready" : "Up to date"
                await drainPendingWorkingTreeRefresh()
                await drainPendingLiveRefresh()
                return
            }
            repositoryWatcher?.stop()

            let openedRepositoryRoot = result.rootURL.standardizedFileURL.path
            repositoryURL = result.rootURL
            self.sshRepository = sshRepository
            isPlainFolder = result.isPlainFolder
            deferredRepositoryOpenURL = nil
            repositoryInitializationURL = nil
            if previousRepositoryRoot != openedRepositoryRoot {
                commitMessage = ""
                isAmendingCommit = false
                workspaceMode = .sourceControl
                expandedFileDirectories = []
            }
            if result.isPlainFolder {
                workspaceMode = .fileEditor
            }
            dismissRepositorySearch(clearingQuery: true)
            graphLimit = graphPageSize
            graphHistoryOffset = 0
            graphHasMore = false
            graphLayoutState = GraphLayoutState()
            referencesByCommitHash = [:]
            detailRequestID = UUID()
            removeAllGitPreviewFiles()
            selectedChange = nil
            selectedCommit = nil
            selectedCommitFile = nil
            selectedRepositoryFilePath = nil
            repositoryFileScrollRequest = nil
            repositoryFileSession = nil
            gitDetailSession = nil
            expandedCommitHashes = []
            commitFilesByHash = [:]
            loadingCommitFileHashes = []
            detailText = ""
            isDetailLoading = false
            repositoryFileText = ""
            savedRepositoryFileText = ""
            markRepositoryFileClean()
            detailTitle = "Select a changed file or commit"
            detailKind = .diff
            isDiffPanelPresented = false
            apply(result.snapshot)
            applyRepositoryMetadata(
                remotes: result.remotes,
                activeOperation: result.activeOperation
            )
            if persistsLastRepository {
                UserDefaults.standard.set(result.rootURL.path, forKey: lastRepositoryKey)
            }
            startWatching(paths: result.watchPaths, sinceWhen: watcherStartEventID)
            pendingLiveRefresh = false
            pendingWorkingTreeRefresh = false
            openedRepository = true
            activity = "Up to date"
            KvistPerformanceInstrumentation.recordRepositoryLoaded(
                rootURL: result.rootURL,
                model: self
            )
        } catch {
            guard openRequestID == requestID else { return }
            repositoryOpenLoadTask = nil
            if error is CancellationError {
                activity = repositoryURL == nil ? "Ready" : "Up to date"
            } else if isNotRepositoryError(error) {
                deferredRepositoryOpenURL = nil
                repositoryInitializationURL = url.standardizedFileURL
                activity = "Repository setup required"
            } else if persistsLastRepository,
               repositoryURL == nil,
               UserDefaults.standard.string(forKey: lastRepositoryKey) == url.path {
                deferredRepositoryOpenURL = nil
                UserDefaults.standard.removeObject(forKey: lastRepositoryKey)
                present(error)
            } else {
                deferredRepositoryOpenURL = nil
                present(error)
            }
        }
        activeOpenRequestID = nil
        isBusy = false
        if openedRepository {
            // The initial snapshot is already current. Only reconcile again if
            // the newly installed watcher observed a change while it was applied.
            await drainPendingWorkingTreeRefresh()
            await drainPendingLiveRefresh()
        } else {
            await drainPendingWorkingTreeRefresh()
            await drainPendingLiveRefresh()
        }
    }

    func cancelRepositoryOpen() {
        if let sshProbeTask {
            sshProbeTask.cancel()
            self.sshProbeTask = nil
            isBusy = false
            activity = repositoryURL == nil ? "Ready" : "Up to date"
        }
        if repositoryCloneTask != nil {
            repositoryCloneTask?.cancel()
            repositoryCloneTask = nil
            isBusy = false
            activity = repositoryURL == nil ? "Ready" : "Up to date"
        }
        guard activeOpenRequestID != nil else { return }
        repositoryOpenLoadTask?.cancel()
        repositoryOpenLoadTask = nil
        activeOpenRequestID = nil
        openRequestID = UUID()
        isBusy = false
        activity = repositoryURL == nil ? "Ready" : "Up to date"
    }

    private func approveDiscardingRepositoryFileChanges() -> Bool {
        reconcileRepositoryFileDirtyImmediately()
        let hasFileChanges = isRepositoryFileDirty
            || repositoryFileSession?.isDirty == true
        guard confirmDiscardRepositoryFileChanges() else { return false }
        if hasFileChanges {
            repositoryFileSession = nil
            closeDiffPanel()
        }
        return true
    }

    func initializeRepository(createGitIgnore: Bool = true) async {
        guard let url = repositoryInitializationURL,
              !isBusy,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return }

        // A folder opened without Git over SSH initializes on the remote
        // machine; the marker is rewritten so the reopened tab gets Git.
        let sshFolder = isPlainFolder
            && repositoryURL?.standardizedFileURL == url.standardizedFileURL
            ? sshRepository
            : nil
        isBusy = true
        activity = "Initializing repository…"
        do {
            if let sshFolder {
                let client = GitClient(repositoryURL: url, sshRepository: sshFolder)
                try await Task.detached(priority: .userInitiated) {
                    try client.initializeSSHRepository(createGitIgnore: createGitIgnore)
                }.value
                let repository = try SSHRepository(
                    host: sshFolder.host,
                    path: sshFolder.path,
                    isGitRepository: true
                )
                try JSONEncoder().encode(repository).write(
                    to: url.appendingPathComponent(".kvist-ssh"),
                    options: .atomic
                )
            } else {
                try await Task.detached(priority: .userInitiated) {
                    try GitClient.initializeRepository(
                        at: url,
                        createGitIgnore: createGitIgnore
                    )
                }.value
            }
            isBusy = false
            repositoryInitializationURL = nil
            await openRepository(url)
        } catch {
            isBusy = false
            present(error)
        }
    }

    /// Shows the initialize-repository screen for a folder that is open
    /// without Git, so Git can be added later without reopening the folder.
    func requestRepositoryInitialization() {
        guard isPlainFolder, let repositoryURL, !isBusy else { return }
        repositoryInitializationURL = repositoryURL
        activity = "Repository setup required"
    }

    func cancelRepositoryInitialization() {
        repositoryInitializationURL = nil
        activity = repositoryURL == nil ? "Ready" : "Up to date"
    }

    private func isNotRepositoryError(_ error: Error) -> Bool {
        guard let gitError = error as? GitCommandError,
              gitError.command == "git rev-parse --show-toplevel" else {
            return false
        }
        return gitError.output.lowercased().contains("not a git repository")
    }

    func refresh() async {
        await refresh(activityMessage: "Refreshing…", blocksActions: true)
    }

    private func refresh(
        activityMessage: String,
        blocksActions: Bool,
        presentsErrors: Bool = true
    ) async {
        guard let repositoryURL,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage else { return }
        guard !isRefreshInProgress else {
            pendingLiveRefresh = true
            return
        }
        if isPlainFolder {
            // Nothing from Git to reload. Remote folders re-list their files;
            // local folders are already kept current by the watcher.
            pendingLiveRefresh = false
            pendingWorkingTreeRefresh = false
            if sshRepository != nil {
                repositoryFilesRevision &+= 1
                scheduleRepositorySearch(presentsResults: false)
            }
            activity = "Up to date"
            return
        }
        isRefreshInProgress = true
        let requestID = UUID()
        snapshotRequestID = requestID
        let initialWorkingTreeVersion = workingTreeVersion
        isLoadingMoreGraph = false
        graphHistoryLoadTask?.cancel()
        graphHistoryLoadTask = nil
        pendingLiveRefresh = false
        pendingWorkingTreeRefresh = false
        workingTreeRefreshTask?.cancel()
        if blocksActions {
            isBusy = true
        }
        activity = activityMessage

        do {
            let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
            let maxGraphCount = graphLimit
            let historyScope = graphScope.gitScope
            let loadTask = Task.detached(priority: .userInitiated) {
                RepositoryRefreshMetrics.recordFullSnapshot()
                async let snapshot = client.snapshotAsync(
                    maxGraphCount: maxGraphCount,
                    historyScope: historyScope
                )
                async let remotes = Task.detached(priority: .userInitiated) {
                    try client.remotes()
                }.value
                let loadedSnapshot = try await snapshot
                return RepositoryRefreshResult(
                    snapshot: loadedSnapshot,
                    remotes: try await remotes,
                    activeOperation: loadedSnapshot.activeOperation
                )
            }
            repositorySnapshotLoadTask = loadTask
            let result = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            repositorySnapshotLoadTask = nil
            if snapshotRequestID == requestID,
               self.repositoryURL == repositoryURL {
                apply(
                    result.snapshot,
                    includeWorkingTree: workingTreeVersion == initialWorkingTreeVersion
                )
                applyRepositoryMetadata(
                    remotes: result.remotes,
                    activeOperation: result.activeOperation
                )
                if sshRepository != nil {
                    repositoryFilesRevision &+= 1
                }
                activity = "Up to date"
            }
        } catch {
            repositorySnapshotLoadTask = nil
            if !(error is CancellationError),
               snapshotRequestID == requestID,
               self.repositoryURL == repositoryURL,
               presentsErrors {
                present(error)
            }
        }

        if snapshotRequestID == requestID,
           self.repositoryURL == repositoryURL {
            if blocksActions {
                isBusy = false
            }
        }
        isRefreshInProgress = false
        if !Task.isCancelled {
            await drainPendingWorkingTreeRefresh()
            await drainPendingLiveRefresh()
        }
    }

    private func refreshWorkingTree() async {
        guard let repositoryURL,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage else { return }
        guard !isRefreshInProgress else {
            pendingWorkingTreeRefresh = true
            return
        }
        if isPlainFolder {
            pendingWorkingTreeRefresh = false
            return
        }
        isRefreshInProgress = true
        pendingWorkingTreeRefresh = false
        let initialWorkingTreeVersion = workingTreeVersion
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)

        do {
            let loadTask = Task.detached(priority: .userInitiated) {
                RepositoryRefreshMetrics.recordWorkingTreeSnapshot()
                let snapshot = try client.workingTreeSnapshot()
                try Task.checkCancellation()
                return snapshot
            }
            workingTreeSnapshotLoadTask = loadTask
            let snapshot = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            workingTreeSnapshotLoadTask = nil
            if self.repositoryURL == repositoryURL,
               workingTreeVersion == initialWorkingTreeVersion {
                applyWorkingTree(snapshot)
                activity = "Up to date"
            }
        } catch {
            workingTreeSnapshotLoadTask = nil
            if !(error is CancellationError),
               self.repositoryURL == repositoryURL {
                present(error)
            }
        }
        isRefreshInProgress = false
        if !Task.isCancelled {
            await drainPendingWorkingTreeRefresh()
            await drainPendingLiveRefresh()
        }
    }

    func select(_ change: FileChange) {
        clearGitFilePreview()
        selectedChange = change
        selectedCommit = nil
        selectedCommitFile = nil
        selectedRepositoryFilePath = nil
        detailTitle = change.path
        detailText = "Loading diff…"
        detailKind = .diff
        isDetailLoading = true
        isDiffPanelPresented = true
        let requestID = UUID()
        detailRequestID = requestID

        guard let repositoryURL else { return }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)

        if change.status == "!", let activeOperation {
            detailText = "Loading conflict…"
            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    let document = try? client.conflictDocument(for: change.path)
                    let sideLabels = client.conflictSideLabels(
                        for: activeOperation,
                        document: document
                    )
                    let preview = document == nil
                        ? try? client.conflictFilePreview(
                            for: change.path,
                            sideLabels: sideLabels
                        )
                        : nil
                    return (document, sideLabels, preview)
                }.value
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL,
                      self.selectedChange == change else {
                    result.2?.removeTemporaryFiles()
                    return
                }
                gitFilePreview = result.2
                gitPreviewDirectoryStore.insert(result.2)
                conflictResolution = ConflictResolutionSession(
                    path: change.path,
                    operation: activeOperation,
                    document: result.0,
                    sideLabels: result.1
                )
                detailText = result.0 == nil
                    ? "This conflict cannot be split into text hunks. Choose a complete version or open the file for manual editing."
                    : ""
                isDetailLoading = false
            }
            return
        }

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let output = try client.diff(for: change)
                    let preview = try? client.preview(for: change)
                    return (output, preview)
                }.value
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else {
                    result.1?.removeTemporaryFiles()
                    return
                }
                detailText = result.0.isEmpty ? "No textual diff available." : result.0
                installGitFilePreview(result.1)
                isDetailLoading = false
            } catch {
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = "Could not load this diff. Select the file again to retry."
                isDetailLoading = false
                present(error)
            }
        }
    }

    func select(_ commit: CommitInfo) {
        clearGitFilePreview()
        selectedCommit = commit
        selectedChange = nil
        selectedCommitFile = nil
        selectedRepositoryFilePath = nil
        detailTitle = "\(commit.shortHash) · \(commit.subject)"
        detailText = "Loading commit…"
        detailKind = .diff
        isDetailLoading = true
        isDiffPanelPresented = false
        let requestID = UUID()
        detailRequestID = requestID

        guard let repositoryURL else { return }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try client.commitDetails(hash: commit.hash)
                }.value
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = output
                isDetailLoading = false
            } catch {
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = "Could not load these commit details. Select the commit again to retry."
                isDetailLoading = false
                present(error)
            }
        }
    }

    func toggleCommitExpansion(_ commit: CommitInfo) {
        if expandedCommitHashes.remove(commit.hash) != nil {
            return
        }

        expandedCommitHashes.insert(commit.hash)
        guard commitFilesByHash[commit.hash] == nil,
              !loadingCommitFileHashes.contains(commit.hash),
              let repositoryURL else { return }

        loadingCommitFileHashes.insert(commit.hash)
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        Task {
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    try client.commitFiles(commit)
                }.value
                guard self.repositoryURL == repositoryURL else { return }
                commitFilesByHash[commit.hash] = files
                loadingCommitFileHashes.remove(commit.hash)
            } catch {
                guard self.repositoryURL == repositoryURL else { return }
                loadingCommitFileHashes.remove(commit.hash)
                expandedCommitHashes.remove(commit.hash)
                present(error)
            }
        }
    }

    func files(for commit: CommitInfo) -> [CommitFileChange] {
        commitFilesByHash[commit.hash] ?? []
    }

    func resetCommitExpansionForPerformanceMeasurement(_ commit: CommitInfo) {
        guard KvistPerformanceInstrumentation.configuration?.mode == .history else { return }
        expandedCommitHashes.remove(commit.hash)
        loadingCommitFileHashes.remove(commit.hash)
        commitFilesByHash.removeValue(forKey: commit.hash)
    }

    func select(_ file: CommitFileChange, in commit: CommitInfo) {
        clearGitFilePreview()
        selectedChange = nil
        selectedCommit = commit
        selectedCommitFile = file
        selectedRepositoryFilePath = nil
        detailTitle = file.path
        detailText = "Loading diff…"
        detailKind = .diff
        isDetailLoading = true
        isDiffPanelPresented = true
        let requestID = UUID()
        detailRequestID = requestID

        guard let repositoryURL else { return }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let output = try client.commitFileDiff(hash: commit.hash, file: file)
                    let preview = try? client.commitFilePreview(hash: commit.hash, file: file)
                    return (output, preview)
                }.value
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else {
                    result.1?.removeTemporaryFiles()
                    return
                }
                detailText = result.0.isEmpty ? "No textual diff available." : result.0
                installGitFilePreview(result.1)
                isDetailLoading = false
            } catch {
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = "Could not load this diff. Select the file again to retry."
                isDetailLoading = false
                present(error)
            }
        }
    }

    func openCommitChanges(_ commit: CommitInfo) {
        clearGitFilePreview()
        selectedChange = nil
        selectedCommit = commit
        selectedCommitFile = nil
        selectedRepositoryFilePath = nil
        detailTitle = "\(commit.shortHash) · \(commit.subject)"
        detailText = "Loading changes…"
        detailKind = .diff
        isDetailLoading = true
        isDiffPanelPresented = true
        let requestID = UUID()
        detailRequestID = requestID

        guard let repositoryURL else { return }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try client.commitDiff(hash: commit.hash)
                }.value
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = output.isEmpty ? "No textual diff available." : output
                isDetailLoading = false
            } catch {
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = "Could not load these changes. Select the commit again to retry."
                isDetailLoading = false
                present(error)
            }
        }
    }

    func githubURL(for commit: CommitInfo) async -> URL? {
        guard let repositoryURL else { return nil }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try client.githubCommitURL(hash: commit.hash)
            }.value
        } catch {
            guard self.repositoryURL == repositoryURL else { return nil }
            present(error)
            return nil
        }
    }

    func githubPullRequestURL(for reference: GitReference) async -> URL? {
        guard let repositoryURL else { return nil }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try client.githubPullRequestURL(for: reference)
            }.value
        } catch {
            guard self.repositoryURL == repositoryURL else { return nil }
            present(error)
            return nil
        }
    }

    func copyCommitMessage(_ commit: CommitInfo) async -> String? {
        guard let repositoryURL else { return nil }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        do {
            let message = try await Task.detached(priority: .userInitiated) {
                try client.commitMessage(hash: commit.hash)
            }.value
            guard self.repositoryURL == repositoryURL else { return nil }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(message, forType: .string)
            return message
        } catch {
            guard self.repositoryURL == repositoryURL else { return nil }
            present(error)
            return nil
        }
    }

    func setWorkspaceMode(_ mode: RepositoryWorkspaceMode) {
        guard mode != workspaceMode else { return }
        guard !isSavingRepositoryFile else { return }
        guard mode == .sourceControl || repositoryURL != nil else { return }
        guard mode == .fileEditor || !isPlainFolder else { return }
        switch (workspaceMode, mode) {
        case (.fileEditor, .sourceControl):
            dismissRepositorySearch()
            rememberRepositoryFileSession()
            closeDiffPanel()
            workspaceMode = mode
            restoreGitDetailSession()
            if let selectedChange, conflictResolution != nil {
                select(selectedChange)
            }
        case (.sourceControl, .fileEditor):
            rememberGitDetailSession()
            closeDiffPanel(preservingGitPreviewFiles: true)
            workspaceMode = mode
            restoreRepositoryFileSession()
        default:
            workspaceMode = mode
        }
    }

    func toggleWorkspaceMode() {
        setWorkspaceMode(
            workspaceMode == .sourceControl ? .fileEditor : .sourceControl
        )
    }

    private var changeForSelectedRepositoryFile: FileChange? {
        guard workspaceMode == .fileEditor,
              let path = selectedRepositoryFilePath else { return nil }
        return unstaged.first { $0.path == path }
            ?? staged.first { $0.path == path }
    }

    var canShowChangesForCurrentFile: Bool {
        changeForSelectedRepositoryFile != nil
    }

    func showChangesForCurrentFile() {
        guard let change = changeForSelectedRepositoryFile else { return }
        setWorkspaceMode(.sourceControl)
        guard workspaceMode == .sourceControl else { return }
        select(change)
    }

    var currentDiffFilePath: String? {
        guard workspaceMode == .sourceControl,
              detailKind == .diff,
              isDiffPanelPresented else { return nil }
        return selectedChange?.path ?? selectedCommitFile?.path
    }

    func setGitFileDetailMode(_ mode: GitFileDetailMode) {
        guard mode != gitFileDetailMode else { return }
        guard mode == .diff || gitFilePreview?.isAvailable == true else { return }
        gitFileDetailMode = mode
    }

    private func installGitFilePreview(_ preview: GitFilePreview?) {
        clearGitFilePreview()
        gitFilePreview = preview
        gitPreviewDirectoryStore.insert(preview)
        gitFileDetailMode = preview?.prefersPreview == true ? .preview : .diff
    }

    private func clearGitFilePreview(removingFiles: Bool = true) {
        conflictResolution = nil
        let preview = gitFilePreview
        gitFilePreview = nil
        gitFileDetailMode = .diff
        guard removingFiles, let preview else { return }
        gitPreviewDirectoryStore.remove(preview, after: 0.5)
    }

    private func removeAllGitPreviewFiles() {
        let activePreview = gitFilePreview
        let rememberedPreview = gitDetailSession?.preview
        gitFilePreview = nil
        gitFileDetailMode = .diff
        gitDetailSession = nil
        gitPreviewDirectoryStore.remove(activePreview)
        gitPreviewDirectoryStore.remove(rememberedPreview)
    }

    var canViewCurrentDiffInFiles: Bool {
        guard let repositoryURL,
              let path = currentDiffFilePath,
              let url = repositoryFileURL(for: path, repositoryURL: repositoryURL) else {
            return false
        }
        guard conflictResolution != nil
                || DiffNavigation.firstChangedLine(in: detailText) != nil else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    func viewCurrentDiffInFiles() {
        guard let path = currentDiffFilePath,
              canViewCurrentDiffInFiles else { return }
        let line = conflictResolution?.document?.firstConflictLine
            ?? DiffNavigation.firstChangedLine(in: detailText)
            ?? 1

        setWorkspaceMode(.fileEditor)
        expandFileDirectories(containing: path)

        if selectedRepositoryFilePath != path
            || detailKind != .source && detailKind != .largeSource {
            openRepositoryFile(path, scrollToLine: line)
        } else {
            repositoryFileScrollRequest = SourceScrollRequest(line: line)
        }
    }

    func canOpenInFiles(_ change: FileChange) -> Bool {
        guard let repositoryURL,
              let url = repositoryFileURL(
                for: change.path,
                repositoryURL: repositoryURL
              ) else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    func openInFiles(_ change: FileChange) {
        guard canOpenInFiles(change) else { return }

        setWorkspaceMode(.fileEditor)
        guard workspaceMode == .fileEditor else { return }
        expandFileDirectories(containing: change.path)

        if selectedRepositoryFilePath != change.path || !isDiffPanelPresented {
            openRepositoryFile(change.path)
        }
    }

    private func expandFileDirectories(containing relativePath: String) {
        var directory = ""
        for component in relativePath.split(separator: "/").dropLast() {
            directory = directory.isEmpty
                ? String(component)
                : "\(directory)/\(component)"
            expandedFileDirectories.insert(directory)
        }
    }

    func toggleFileDirectory(_ relativePath: String) {
        if expandedFileDirectories.remove(relativePath) == nil {
            expandedFileDirectories.insert(relativePath)
        }
    }

    func repositoryFileChildren(
        at directoryURL: URL,
        parentRelativePath: String = ""
    ) async throws -> [RepositoryFileTreeItem] {
        guard let repositoryURL else { return [] }
        guard let sshRepository else {
            return try await RepositoryFileLoader.loadChildren(
                of: directoryURL,
                parentRelativePath: parentRelativePath
            )
        }
        let client = GitClient(
            repositoryURL: repositoryURL,
            sshRepository: sshRepository
        )
        let entries = try await Task.detached(priority: .userInitiated) {
            try client.sshDirectoryEntries(relativePath: parentRelativePath)
        }.value
        return entries.map { entry in
            let relativePath = parentRelativePath.isEmpty
                ? entry.name
                : "\(parentRelativePath)/\(entry.name)"
            return RepositoryFileTreeItem(
                url: repositoryURL.appendingPathComponent(relativePath),
                relativePath: relativePath,
                name: entry.name,
                isDirectory: entry.isDirectory,
                isSymbolicLink: entry.isSymbolicLink
            )
        }
    }

    var isRepositorySidePanelPresented: Bool {
        isDiffPanelPresented || isFileSearchResultsPresented
    }

    func toggleRepositorySearch() {
        if isFileSearchPresented {
            dismissRepositorySearch()
        } else {
            guard workspaceMode == .fileEditor, repositoryURL != nil else { return }
            isFileSearchPresented = true
            isFileSearchResultsPresented = true
            scheduleRepositorySearch()
        }
    }

    func dismissRepositorySearch(clearingQuery: Bool = false) {
        isFileSearchPresented = false
        isFileSearchResultsPresented = false
        repositorySearchTask?.cancel()
        repositorySearchTask = nil
        isRepositorySearchLoading = false
        repositorySearchError = nil
        if clearingQuery {
            repositorySearchQuery = ""
            repositorySearchResults = .empty
        }
    }

    func openRepositorySearchMatch(
        _ relativePath: String,
        line: Int? = nil
    ) {
        if isDiffPanelPresented,
           selectedRepositoryFilePath == relativePath {
            if let line {
                openRepositoryFile(
                    relativePath,
                    scrollToLine: line,
                    highlightsLine: true
                )
            }
            isFileSearchResultsPresented = false
            return
        }
        openRepositoryFile(
            relativePath,
            scrollToLine: line,
            highlightsLine: line != nil
        )
        guard selectedRepositoryFilePath == relativePath else { return }
        isFileSearchResultsPresented = false
    }

    func showRepositorySearchResults() {
        guard isFileSearchPresented else { return }
        isFileSearchResultsPresented = true
    }

    func activateRepositoryFile(_ relativePath: String) {
        if isDiffPanelPresented,
           selectedRepositoryFilePath == relativePath {
            closeEditorPanel()
        } else {
            openRepositoryFile(relativePath)
        }
    }

    func openRepositoryFile(
        _ relativePath: String,
        scrollToLine: Int? = nil,
        highlightsLine: Bool = false
    ) {
        guard !isSavingRepositoryFile, let repositoryURL else { return }
        if let scrollToLine,
           relativePath == selectedRepositoryFilePath,
           detailKind == .source || detailKind == .largeSource,
           !isDetailLoading {
            repositoryFileScrollRequest = SourceScrollRequest(
                line: scrollToLine,
                highlightsLine: highlightsLine
            )
            return
        }
        guard relativePath == selectedRepositoryFilePath
                || confirmDiscardRepositoryFileChanges() else { return }

        selectedChange = nil
        selectedCommit = nil
        selectedCommitFile = nil
        selectedRepositoryFilePath = relativePath
        repositoryFileScrollRequest = nil
        markRepositoryFileClean()
        detailTitle = relativePath
        isDiffPanelPresented = true
        let requestID = UUID()
        detailRequestID = requestID

        guard let fileURL = repositoryFileURL(
            for: relativePath,
            repositoryURL: repositoryURL
        ) else {
            detailText = "Kvist can only preview files inside this repository."
            detailKind = .message
            isDetailLoading = false
            return
        }

        detailText = "Loading file…"
        detailKind = .source
        isDetailLoading = true

        Task {
            do {
                let client = GitClient(
                    repositoryURL: repositoryURL,
                    sshRepository: sshRepository
                )
                let result = try await Task.detached(priority: .userInitiated) {
                    try client.downloadSSHFile(
                        relativePath: relativePath,
                        to: fileURL
                    )
                    let document = try RepositoryFileLoader.document(at: fileURL)
                    return (
                        document,
                        RepositoryFileDiskVersion(fileURL: fileURL)
                    )
                }.value
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL,
                      selectedRepositoryFilePath == relativePath else { return }
                repositoryFileDiskVersion = result.1

                switch result.0 {
                case .source(let text):
                    detailText = text
                    repositoryFileText = text
                    savedRepositoryFileText = text
                    markRepositoryFileClean()
                    detailKind = .source
                    isDetailLoading = false
                    if let scrollToLine {
                        repositoryFileScrollRequest = SourceScrollRequest(
                            line: scrollToLine,
                            highlightsLine: highlightsLine
                        )
                    }
                case .largeSource(let text):
                    detailText = ""
                    repositoryFileText = text
                    savedRepositoryFileText = ""
                    markRepositoryFileClean()
                    detailKind = .largeSource
                    isDetailLoading = false
                    if let scrollToLine {
                        repositoryFileScrollRequest = SourceScrollRequest(
                            line: scrollToLine,
                            highlightsLine: highlightsLine
                        )
                    }
                case .preview:
                    detailText = ""
                    repositoryFileText = ""
                    savedRepositoryFileText = ""
                    markRepositoryFileClean()
                    detailKind = .preview
                    isDetailLoading = false
                case .message(let message):
                    detailText = message
                    repositoryFileText = ""
                    savedRepositoryFileText = ""
                    markRepositoryFileClean()
                    detailKind = .message
                    isDetailLoading = false
                }
            } catch {
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL,
                      selectedRepositoryFilePath == relativePath else { return }
                detailText = "Kvist could not preview this file."
                detailKind = .message
                isDetailLoading = false
            }
        }
    }

    /// Re-derives the open editor's text matches from the in-memory buffer so
    /// typing never re-runs (and never blanks) the repository-wide search.
    private func refreshEditedFileSearchMatches() {
        let query = repositorySearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFileSearchPresented,
              !query.isEmpty,
              let editedPath = selectedRepositoryFilePath else { return }

        let existing = repositorySearchResults
        let editedMatches = RepositorySearchParser.textMatches(
            in: repositoryFileText,
            path: editedPath,
            query: query,
            limit: 20
        )
        let textMatches = existing.textMatches.filter {
            $0.path != editedPath
        } + editedMatches
        guard textMatches != existing.textMatches else { return }
        repositorySearchResults = RepositorySearchResults(
            fileMatches: existing.fileMatches,
            textMatches: textMatches,
            fileMatchesWereLimited: existing.fileMatchesWereLimited,
            textMatchesWereLimited: existing.textMatchesWereLimited
        )
    }

    private func scheduleRepositorySearch(presentsResults: Bool = true) {
        repositorySearchTask?.cancel()
        repositorySearchTask = nil

        let query = repositorySearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFileSearchPresented,
              let repositoryURL,
              !query.isEmpty else {
            if presentsResults {
                isRepositorySearchLoading = false
                repositorySearchError = nil
                repositorySearchResults = .empty
            }
            return
        }

        isRepositorySearchLoading = presentsResults
        repositorySearchError = nil
        if presentsResults {
            repositorySearchResults = .empty
            isFileSearchResultsPresented = true
        }
        let revision = repositoryFilesRevision
        let editedPath = selectedRepositoryFilePath
        let editedText = repositoryFileText
        let searchesPlainFolder = isPlainFolder
        repositorySearchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(160))
                let client = GitClient(
                    repositoryURL: repositoryURL,
                    sshRepository: self?.sshRepository
                )
                let searchTask = Task.detached(priority: .userInitiated) {
                    searchesPlainFolder
                        ? try client.searchFolder(for: query)
                        : try client.searchRepository(for: query)
                }
                var results = try await withTaskCancellationHandler {
                    try await searchTask.value
                } onCancel: {
                    searchTask.cancel()
                }
                if let editedPath {
                    let editedMatches = RepositorySearchParser.textMatches(
                        in: editedText,
                        path: editedPath,
                        query: query,
                        limit: 20
                    )
                    results = RepositorySearchResults(
                        fileMatches: results.fileMatches,
                        textMatches: results.textMatches.filter {
                            $0.path != editedPath
                        } + editedMatches,
                        fileMatchesWereLimited: results.fileMatchesWereLimited,
                        textMatchesWereLimited: results.textMatchesWereLimited
                    )
                }
                guard !Task.isCancelled,
                      let self,
                      self.repositoryURL == repositoryURL,
                      self.repositorySearchQuery
                        .trimmingCharacters(in: .whitespacesAndNewlines) == query,
                      self.repositoryFilesRevision == revision else {
                    return
                }
                self.repositorySearchResults = results
                self.isRepositorySearchLoading = false
                self.repositorySearchTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.repositoryURL == repositoryURL,
                      self.repositorySearchQuery
                        .trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                    return
                }
                if presentsResults {
                    self.repositorySearchResults = .empty
                    self.repositorySearchError = "Could not search this repository."
                }
                self.isRepositorySearchLoading = false
                self.repositorySearchTask = nil
            }
        }
    }

    func activate(_ change: FileChange) {
        if isDiffPanelPresented, selectedChange == change {
            closeEditorPanel()
        } else {
            select(change)
        }
    }

    func activate(_ file: CommitFileChange, in commit: CommitInfo) {
        if isDiffPanelPresented,
           selectedCommit?.hash == commit.hash,
           selectedCommitFile?.id == file.id {
            closeEditorPanel()
        } else {
            select(file, in: commit)
        }
    }

    var selectedRepositoryFileURL: URL? {
        guard let repositoryURL, let selectedRepositoryFilePath else { return nil }
        return repositoryFileURL(
            for: selectedRepositoryFilePath,
            repositoryURL: repositoryURL
        )
    }

    private func repositoryFileURL(
        for relativePath: String,
        repositoryURL: URL
    ) -> URL? {
        let resolvedRootURL = repositoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedFileURL = repositoryURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = resolvedRootURL.path.hasSuffix("/")
            ? resolvedRootURL.path
            : resolvedRootURL.path + "/"
        guard resolvedFileURL.path.hasPrefix(rootPrefix) else { return nil }
        return resolvedFileURL
    }

    func closeEditorPanel() {
        guard !isSavingRepositoryFile else { return }
        if workspaceMode == .fileEditor {
            guard confirmDiscardRepositoryFileChanges() else { return }
            repositoryFileSession = nil
        } else {
            gitDetailSession = nil
        }
        closeDiffPanel()
    }

    var isRepositoryFileDirty: Bool {
        detailKind == .source && repositoryFileDirty
    }

    var hasUnsavedRepositoryFileChanges: Bool {
        isRepositoryFileDirty || repositoryFileSession?.isDirty == true
    }

    var canSaveRepositoryFile: Bool {
        isRepositoryFileDirty && !isSavingRepositoryFile && !isBusy
    }

    func updateRepositoryFileTextFromEditor(_ text: String) {
        isUpdatingRepositoryFileTextFromEditor = true
        repositoryFileText = text
        isUpdatingRepositoryFileTextFromEditor = false
    }

    func restoreSavedRepositoryFileText() {
        repositoryFileText = savedRepositoryFileText
        markRepositoryFileClean()
    }

    private func scheduleRepositoryFileDirtyReconciliation() {
        repositoryFileDirtyReconciliationTask?.cancel()
        let revision = repositoryFileTextRevision
        repositoryFileDirtyReconciliationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled,
                  let self,
                  self.repositoryFileTextRevision == revision,
                  self.repositoryFileDirty else { return }
            let text = self.repositoryFileText
            let savedText = self.savedRepositoryFileText
            let matchesSavedText = await Task.detached(priority: .utility) {
                text == savedText
            }.value
            guard !Task.isCancelled,
                  self.repositoryFileTextRevision == revision,
                  matchesSavedText else { return }
            self.markRepositoryFileClean()
        }
    }

    private func scheduleRepositoryFileDirtyPublication() {
        repositoryFileDirtyPublicationTask?.cancel()
        let revision = repositoryFileTextRevision
        repositoryFileDirtyPublicationTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  self.repositoryFileTextRevision == revision,
                  self.repositoryFileText != self.savedRepositoryFileText else { return }
            self.repositoryFileDirty = true
            self.repositoryFileDirtyPublicationTask = nil
        }
    }

    private func reconcileRepositoryFileDirtyImmediately() {
        guard repositoryFileDirty,
              repositoryFileText == savedRepositoryFileText else { return }
        markRepositoryFileClean()
    }

    private func markRepositoryFileClean() {
        repositoryFileDirtyPublicationTask?.cancel()
        repositoryFileDirtyPublicationTask = nil
        repositoryFileDirtyReconciliationTask?.cancel()
        repositoryFileDirtyReconciliationTask = nil
        repositoryFileDirty = false
    }

    func saveRepositoryFile() async {
        guard canSaveRepositoryFile else { return }
        guard let fileURL = selectedRepositoryFileURL else {
            present(GitCommandError(
                command: "save file",
                output: "Kvist can only save files inside this repository."
            ))
            return
        }
        let currentDiskVersion = RepositoryFileDiskVersion(fileURL: fileURL)
        if let repositoryFileDiskVersion,
           currentDiskVersion != repositoryFileDiskVersion {
            let result = AppDialog.run(
                title: "File Changed on Disk",
                message: "\(detailTitle) changed after it was opened. Overwriting it may discard newer edits.",
                actions: [
                    AppDialogAction(title: "Cancel", role: .cancel),
                    AppDialogAction(title: "Overwrite", role: .destructive)
                ]
            )
            guard result.actionIndex == 1 else { return }
        }
        isSavingRepositoryFile = true
        defer {
            isSavingRepositoryFile = false
            scheduleWorkingTreeRefresh(delay: .zero)
        }
        let text = repositoryFileText
        let fileRequestID = detailRequestID
        guard let repositoryURL else { return }
        let sshRepository = sshRepository
        let relativePath = selectedRepositoryFilePath ?? fileURL.lastPathComponent
        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.persistRepositoryFile(
                    text,
                    to: fileURL,
                    repositoryURL: repositoryURL,
                    sshRepository: sshRepository,
                    relativePath: relativePath
                )
            }.value
            guard detailRequestID == fileRequestID,
                  selectedRepositoryFileURL == fileURL else { return }
            repositoryFileDiskVersion = RepositoryFileDiskVersion(fileURL: fileURL)
            repositoryFileDirtyReconciliationTask?.cancel()
            savedRepositoryFileText = text
            detailText = text
            if repositoryFileText == text {
                markRepositoryFileClean()
            } else {
                repositoryFileDirty = true
                scheduleRepositoryFileDirtyReconciliation()
            }
        } catch {
            present(error)
        }
    }

    func confirmDiscardRepositoryFileChanges() -> Bool {
        guard !isSavingRepositoryFile else { return false }
        reconcileRepositoryFileDirtyImmediately()
        let activeDirty = isRepositoryFileDirty
        let rememberedDirty = repositoryFileSession?.isDirty == true
        guard activeDirty || rememberedDirty else { return true }
        let draft = activeDirty
            ? RepositoryFileDraft(
                path: selectedRepositoryFilePath ?? detailTitle,
                title: detailTitle,
                text: repositoryFileText,
                savedText: savedRepositoryFileText,
                diskVersion: repositoryFileDiskVersion,
                isActive: true
            )
            : repositoryFileSession.map {
                RepositoryFileDraft(
                    path: $0.path,
                    title: $0.title,
                    text: $0.fileText,
                    savedText: $0.savedFileText,
                    diskVersion: $0.diskVersion,
                    isActive: false
                )
            }
        guard let draft else { return true }
        let diff = DraftDiff.make(
            savedText: draft.savedText,
            draftText: draft.text,
            path: draft.path
        )
        let result = AppDialog.run(
            title: "Save Changes?",
            message: "\(draft.title) has unsaved changes.",
            disclosure: AppDialogDisclosure(
                title: "Changes",
                summary: diff.summary,
                text: diff.text
            ),
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Discard Changes", role: .destructive),
                AppDialogAction(title: "Save", role: .primary)
            ]
        )
        switch result.actionIndex {
        case 1:
            return true
        case 2:
            return saveRepositoryFileBeforeContinuing(draft)
        default:
            return false
        }
    }

    private func saveRepositoryFileBeforeContinuing(
        _ draft: RepositoryFileDraft
    ) -> Bool {
        guard let repositoryURL,
              let fileURL = repositoryFileURL(
                for: draft.path,
                repositoryURL: repositoryURL
              ) else {
            present(GitCommandError(
                command: "save file",
                output: "Kvist can only save files inside this repository."
            ))
            return false
        }
        let currentDiskVersion = RepositoryFileDiskVersion(fileURL: fileURL)
        if let diskVersion = draft.diskVersion,
           currentDiskVersion != diskVersion {
            let result = AppDialog.run(
                title: "File Changed on Disk",
                message: "\(draft.title) changed after it was opened. Overwriting it may discard newer edits.",
                actions: [
                    AppDialogAction(title: "Cancel", role: .cancel),
                    AppDialogAction(title: "Overwrite", role: .destructive)
                ]
            )
            guard result.actionIndex == 1 else { return false }
        }

        isSavingRepositoryFile = true
        defer {
            isSavingRepositoryFile = false
            scheduleWorkingTreeRefresh(delay: .zero)
        }
        do {
            try Self.persistRepositoryFile(
                draft.text,
                to: fileURL,
                repositoryURL: repositoryURL,
                sshRepository: sshRepository,
                relativePath: draft.path
            )

            if draft.isActive,
               selectedRepositoryFilePath == draft.path {
                repositoryFileDiskVersion = RepositoryFileDiskVersion(fileURL: fileURL)
                savedRepositoryFileText = draft.text
                detailText = draft.text
                if repositoryFileText == draft.text {
                    markRepositoryFileClean()
                }
            } else if repositoryFileSession?.path == draft.path {
                repositoryFileSession = nil
            }
            return true
        } catch {
            present(error)
            return false
        }
    }

    nonisolated private static func persistRepositoryFile(
        _ text: String,
        to fileURL: URL,
        repositoryURL: URL,
        sshRepository: SSHRepository?,
        relativePath: String
    ) throws {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: fileURL, options: .atomic)
        try GitClient(
            repositoryURL: repositoryURL,
            sshRepository: sshRepository
        ).uploadSSHFile(fileURL, relativePath: relativePath)
    }

    private func rememberRepositoryFileSession() {
        guard let path = selectedRepositoryFilePath else {
            repositoryFileSession = nil
            return
        }
        let retainsText = detailKind != .largeSource
        repositoryFileSession = RepositoryFileSession(
            path: path,
            title: detailTitle,
            detailText: detailText,
            fileText: retainsText ? repositoryFileText : "",
            savedFileText: retainsText ? savedRepositoryFileText : "",
            kind: detailKind,
            isPanelPresented: isDiffPanelPresented,
            diskVersion: repositoryFileDiskVersion
        )
    }

    private func restoreRepositoryFileSession() {
        guard let session = repositoryFileSession else { return }
        selectedRepositoryFilePath = session.path
        detailTitle = session.title
        detailText = session.detailText
        repositoryFileText = session.fileText
        savedRepositoryFileText = session.savedFileText
        if session.isDirty {
            repositoryFileDirty = true
        } else {
            markRepositoryFileClean()
        }
        detailKind = session.kind
        isDiffPanelPresented = session.isPanelPresented
        repositoryFileDiskVersion = session.diskVersion

        if session.isPanelPresented, !session.isDirty {
            openRepositoryFile(session.path)
        }
    }

    private func rememberGitDetailSession() {
        guard isDiffPanelPresented,
              detailKind == .diff,
              !isDetailLoading else {
            gitDetailSession = nil
            return
        }
        gitDetailSession = GitDetailSession(
            selectedChange: selectedChange,
            selectedCommit: selectedCommit,
            selectedCommitFile: selectedCommitFile,
            title: detailTitle,
            text: detailText,
            preview: gitFilePreview,
            detailMode: gitFileDetailMode,
            conflictResolution: conflictResolution,
            isPanelPresented: isDiffPanelPresented
        )
    }

    private func restoreGitDetailSession() {
        guard let session = gitDetailSession else { return }
        selectedChange = session.selectedChange
        selectedCommit = session.selectedCommit
        selectedCommitFile = session.selectedCommitFile
        selectedRepositoryFilePath = nil
        detailTitle = session.title
        detailText = session.text
        detailKind = .diff
        gitFilePreview = session.preview
        gitFileDetailMode = session.detailMode
        conflictResolution = session.conflictResolution
        isDiffPanelPresented = session.isPanelPresented
        gitDetailSession = nil
    }

    func closeDiffPanel(preservingGitPreviewFiles: Bool = false) {
        detailRequestID = UUID()
        clearGitFilePreview(removingFiles: !preservingGitPreviewFiles)
        selectedChange = nil
        selectedCommit = nil
        selectedCommitFile = nil
        selectedRepositoryFilePath = nil
        repositoryFileScrollRequest = nil
        detailText = ""
        isDetailLoading = false
        repositoryFileText = ""
        savedRepositoryFileText = ""
        repositoryFileDiskVersion = nil
        markRepositoryFileClean()
        detailTitle = "Select a changed file or commit"
        detailKind = .diff
        isDiffPanelPresented = false
    }

    func stage(_ change: FileChange) async {
        guard change.area == .unstaged else { return }
        if change.status == "!", activeOperation != nil {
            select(change)
            return
        }
        await performChangeOperation(
            "Staging \(change.name)…",
            paths: Set([change.path]),
            operation: { try $0.stage(change.path) },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyStage([change])
            }
        )
    }

    func resolveConflict(
        _ change: FileChange,
        keeping version: ConflictVersion
    ) async {
        guard let activeOperation,
              change.area == .unstaged,
              change.status == "!" else { return }
        let versionName: String
        switch (activeOperation, version) {
        case (.rebase, .current): versionName = "onto-branch"
        case (.rebase, .incoming): versionName = "replayed-commit"
        case (.cherryPick, .current), (.revert, .current):
            versionName = "current-branch"
        case (.cherryPick, .incoming): versionName = "cherry-picked-commit"
        case (.revert, .incoming): versionName = "reverted"
        case (_, .current): versionName = "current-branch"
        case (_, .incoming): versionName = "incoming-branch"
        }
        let resolved = await performChangeOperation(
            "Keeping \(versionName) version of \(change.name)…",
            paths: Set([change.path]),
            operation: {
                try $0.resolveConflict(
                    change.path,
                    keeping: version,
                    during: activeOperation
                )
            },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyStage([change])
            }
        )
        if resolved { closeDiffPanel() }
    }

    func chooseConflictHunk(_ hunkID: Int, choice: ConflictChoice?) {
        guard var session = conflictResolution,
              session.document?.hunks.contains(where: { $0.id == hunkID }) == true else {
            return
        }
        session.choices[hunkID] = choice
        conflictResolution = session
    }

    func chooseAllConflictHunks(_ choice: ConflictChoice) {
        guard var session = conflictResolution, let document = session.document else { return }
        session.choices = Dictionary(uniqueKeysWithValues: document.hunks.map {
            ($0.id, choice)
        })
        conflictResolution = session
    }

    func clearConflictChoices() {
        guard var session = conflictResolution, !session.choices.isEmpty else { return }
        session.choices = [:]
        conflictResolution = session
    }

    func applyConflictResolution() async {
        guard let session = conflictResolution,
              let resolvedText = session.resolvedText,
              let change = unresolvedConflicts.first(where: { $0.path == session.path }) else {
            return
        }
        let resolved = await performChangeOperation(
            "Resolving \(change.name)…",
            paths: Set([change.path]),
            operation: {
                try $0.resolveConflict(
                    change.path,
                    with: resolvedText,
                    during: session.operation
                )
            },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyStage([change])
            }
        )
        if resolved { closeDiffPanel() }
    }

    func openNextConflict() {
        let conflicts = unresolvedConflicts
        guard !conflicts.isEmpty else { return }
        guard let selectedChange,
              let currentIndex = conflicts.firstIndex(where: {
                $0.path == selectedChange.path
              }) else {
            select(conflicts[0])
            return
        }
        select(conflicts[(currentIndex + 1) % conflicts.count])
    }

    func unstage(_ change: FileChange) async {
        guard change.area == .staged else { return }
        if isReopenableConflict(change) {
            await reopenConflict(change)
            return
        }
        let paths = Set([change.path, change.previousPath].compactMap { $0 })
        await performChangeOperation(
            "Unstaging \(change.name)…",
            paths: paths,
            operation: {
                try $0.unstage(change.path, previousPath: change.previousPath)
            },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyUnstage([change])
            }
        )
    }

    func reopenConflict(_ change: FileChange) async {
        guard let activeOperation,
              isReopenableConflict(change) else { return }
        let reopened = await performChangeOperation(
            "Reopening conflict in \(change.name)…",
            paths: Set([change.path]),
            operation: {
                try $0.reopenConflict(change.path, during: activeOperation)
            },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyReopenConflict(change)
            }
        )
        if reopened,
           let conflict = unstaged.first(where: {
               $0.path == change.path && $0.status == "!"
           }) {
            select(conflict)
        }
    }

    func discard(_ change: FileChange) async {
        guard change.area == .unstaged else { return }
        await performChangeOperation(
            "Discarding changes in \(change.name)…",
            paths: Set([change.path]),
            operation: {
                try $0.discard(change.path, isUntracked: change.status == "U")
            },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyDiscard(change)
            }
        )
    }

    func discardAllUnstagedChanges() async {
        guard !unstaged.isEmpty else { return }
        await perform("Discarding all unstaged changes…") {
            try $0.discardAllUnstagedChanges()
        }
    }

    func discardAllChanges() async {
        guard hasChanges, headHash != nil else { return }
        await perform("Discarding all changes…") {
            try $0.discardAllChanges()
        }
    }

    func stashChanges(message: String?, includeUntracked: Bool) async {
        guard hasChanges else { return }
        await perform("Stashing changes…") {
            _ = try $0.stash(
                message: message,
                includeUntracked: includeUntracked
            )
        }
    }

    func stageAll() async {
        let changes = unstaged
        guard !changes.isEmpty else { return }
        if hasUnresolvedConflicts {
            openNextConflict()
            return
        }
        await performChangeOperation(
            "Staging all changes…",
            paths: Set(changes.map(\.path)),
            operation: { try $0.stageAll() },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyStage(changes)
            }
        )
    }

    func unstageAll() async {
        let changes = staged
        guard !changes.isEmpty else { return }
        let conflictsToReopen = activeOperation.map { _ in
            changes.filter(isReopenableConflict)
        } ?? []
        let operation = activeOperation
        await performChangeOperation(
            "Unstaging all changes…",
            paths: Set(changes.flatMap {
                [$0.path, $0.previousPath].compactMap { $0 }
            }),
            operation: {
                try $0.unstageAll()
                if let operation {
                    for conflict in conflictsToReopen {
                        try $0.reopenConflict(conflict.path, during: operation)
                    }
                }
            },
            optimisticUpdate: { [weak self] in
                self?.optimisticallyUnstage(changes)
                for conflict in conflictsToReopen {
                    self?.optimisticallyReopenConflict(conflict)
                }
            }
        )
        if let first = conflictsToReopen.first,
           let conflict = unstaged.first(where: {
               $0.path == first.path && $0.status == "!"
           }) {
            select(conflict)
        }
    }

    func commit() async {
        await commit(stageAll: false, pushAfterCommit: false)
    }

    func commitAll() async {
        await commit(stageAll: true, pushAfterCommit: false)
    }

    func commitAndPush() async {
        await commit(stageAll: false, pushAfterCommit: true)
    }

    func commitAllAndPush() async {
        await commit(stageAll: true, pushAfterCommit: true)
    }

    func amend() async {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            guard let repositoryURL, let headHash else { return }
            let client = GitClient(
                repositoryURL: repositoryURL,
                sshRepository: sshRepository
            )
            do {
                commitMessage = try await Task.detached(priority: .userInitiated) {
                    try client.commitMessage(hash: headHash)
                }.value
                isAmendingCommit = true
                activity = "Edit the previous message, then choose Amend Last Commit again"
            } catch {
                present(error)
            }
            return
        }

        let succeeded = await perform("Amending commit…") {
            _ = try $0.amend(message: message)
        }
        if succeeded {
            commitMessage = ""
            isAmendingCommit = false
        }
    }

    func amendNoEdit() async {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return }
        guard hasStagedChanges else {
            errorMessage = "Stage changes before amending the previous commit."
            return
        }

        let succeeded = await perform("Amending commit with previous message…") {
            _ = try $0.amendNoEdit()
        }
        if succeeded {
            commitMessage = ""
            isAmendingCommit = false
        }
    }

    func commitAndSync() async {
        let succeeded = await commit(
            stageAll: false,
            pushAfterCommit: false,
            clearMessage: false
        )
        guard succeeded else { return }
        commitMessage = ""
        if hasUpstream {
            await sync()
        } else {
            await publish()
        }
    }

    @discardableResult
    func publish() async -> Bool {
        guard let repositoryURL,
              !isBusy,
              !isGeneratingCommitMessage else { return false }
        let branch = branch
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        let hasOrigin = await Task.detached(priority: .userInitiated) {
            client.originRemoteURL() != nil
        }.value

        if hasOrigin {
            var published = false
            await withSyncActivity {
                published = await self.perform("Publishing branch…") {
                    _ = try $0.publish(branch: branch)
                }
            }
            return published
        }

        let result = AppDialog.run(
            title: "Link Remote Repository",
            message: "This repository does not have a remote named origin. Paste an HTTPS URL, SSH URL, or local Git repository path to link it and publish \(branch).",
            fields: [
                AppDialogField(
                    label: "Remote repository",
                    placeholder: "https://github.com/owner/repository.git"
                )
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Link & Publish", role: .primary)
            ]
        )
        guard result.actionIndex == 1 else { return false }
        guard let remoteURL = result.values.first, !remoteURL.isEmpty else {
            errorMessage = "Enter a remote repository URL or local Git path."
            return false
        }

        var published = false
        await withSyncActivity {
            published = await self.perform("Linking and publishing branch…") {
                try $0.linkOrigin(to: remoteURL)
                _ = try $0.publish(branch: branch)
            }
        }
        return published
    }

    func performPrimaryAction() async {
        if isAmendingCommit {
            await amend()
            return
        }
        switch primaryAction {
        case .commit:
            await commit()
        case .publish:
            await publish()
        case .sync:
            await sync()
        }
    }

    func loadMoreGraph() async {
        guard let repositoryURL,
              !isBusy,
              !isGeneratingCommitMessage,
              !isLoadingMoreGraph else { return }
        guard graphHasMore, let knownHeadHash = headHash else { return }
        let historyScope = graphScope.gitScope
        let publicationScope = graphScope
        let requestID = UUID()
        snapshotRequestID = requestID
        isLoadingMoreGraph = true
        activity = "Loading more history…"

        do {
            let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
            let remoteReferenceID = upstreamReference?.id
            let offset = graphHistoryOffset
            let layoutState = graphLayoutState
            let referencesByCommitHash = referencesByCommitHash
            let pageSize = graphPageSize
            let loadTask = Task.detached(priority: .userInitiated) {
                try client.historyPage(
                    offset: offset,
                    count: pageSize,
                    scope: historyScope,
                    remoteReferenceID: remoteReferenceID,
                    knownHeadHash: knownHeadHash,
                    layoutState: layoutState,
                    referencesByCommitHash: referencesByCommitHash
                )
            }
            graphHistoryLoadTask = loadTask
            let history = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }

            guard snapshotRequestID == requestID,
                  self.repositoryURL == repositoryURL,
                  graphScope == publicationScope else {
                graphHistoryLoadTask = nil
                return
            }
            graphHistoryLoadTask = nil
            graphLimit += graphPageSize
            graphHistoryOffset = history.nextOffset
            graphHasMore = history.hasMore
            graphLayoutState = history.layoutState
            appendGraph(history.rows, scope: publicationScope)
            isLoadingMoreGraph = false
            activity = "Up to date"
            await drainPendingWorkingTreeRefresh()
            await drainPendingLiveRefresh()
        } catch {
            graphHistoryLoadTask = nil
            guard snapshotRequestID == requestID,
                  self.repositoryURL == repositoryURL else { return }
            isLoadingMoreGraph = false
            if !(error is CancellationError) {
                present(error)
            }
            await drainPendingWorkingTreeRefresh()
            await drainPendingLiveRefresh()
        }
    }

    @discardableResult
    private func commit(
        stageAll: Bool,
        pushAfterCommit: Bool,
        clearMessage: Bool = true
    ) async -> Bool {
        guard !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations else { return false }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "Please enter a commit message."
            return false
        }

        var shouldStageAll = stageAll
        if !stageAll && staged.isEmpty && !unstaged.isEmpty {
            switch UserDefaults.standard.integer(forKey: "smartCommitPreference") {
            case 1:
                shouldStageAll = true
            case 2:
                errorMessage = "There are no staged changes to commit. Stage files first or change the commit behavior in Settings."
                return false
            default:
                let result = AppDialog.run(
                    title: "Nothing Is Staged",
                    message: "Kvist can stage every change and continue with this commit.",
                    actions: [
                        AppDialogAction(title: "Cancel", role: .cancel),
                        AppDialogAction(title: "Require Manual Staging", role: .secondary),
                        AppDialogAction(title: "Always Stage & Commit", role: .secondary),
                        AppDialogAction(title: "Stage All & Commit", role: .primary)
                    ]
                )

                switch result.actionIndex {
                case 3:
                    shouldStageAll = true
                case 2:
                    UserDefaults.standard.set(1, forKey: "smartCommitPreference")
                    shouldStageAll = true
                case 1:
                    UserDefaults.standard.set(2, forKey: "smartCommitPreference")
                    return false
                default:
                    return false
                }
            }
        }

        guard !staged.isEmpty || shouldStageAll else {
            errorMessage = "There are no changes to commit."
            return false
        }

        let stageAllBeforeCommit = shouldStageAll
        let committed = await perform("Committing…") {
            if stageAllBeforeCommit {
                try $0.stageAll()
            }
            _ = try $0.commit(message: message)
        }
        guard committed else { return false }

        if clearMessage {
            commitMessage = ""
        }
        isAmendingCommit = false

        if pushAfterCommit {
            if hasUpstream {
                var pushed = false
                await withSyncActivity {
                    pushed = await self.perform("Pushing…") { _ = try $0.push() }
                }
                return pushed
            }
            return await publish()
        }
        return true
    }

    func fetch() async {
        await withSyncActivity {
            await self.perform("Fetching…") { _ = try $0.fetch() }
        }
    }

    @discardableResult
    func autoFetch(applicationIsActive: Bool) async -> Bool? {
        guard applicationIsActive,
              !remotes.isEmpty,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              !hasPendingChangeOperations,
              !isRefreshInProgress,
              !isLoadingMoreGraph else { return nil }
        return await perform("Fetching…", presentsErrors: false) {
            _ = try $0.fetch()
        }
    }

    func pull() async {
        await withSyncActivity {
            await self.perform("Pulling…") { _ = try $0.pull() }
        }
    }

    func pullRebasing() async {
        await withSyncActivity {
            await self.perform("Pulling with rebase…") {
                _ = try $0.pullRebasing()
            }
        }
    }

    func push() async {
        await withSyncActivity {
            await self.perform("Pushing…") { _ = try $0.push() }
        }
    }

    private func withSyncActivity(_ body: () async -> Void) async {
        syncActivityDepth += 1
        isSyncing = true
        await body()
        syncActivityDepth -= 1
        if syncActivityDepth == 0 {
            isSyncing = false
        }
    }

    func forcePushWithLease() async {
        guard canForcePush else { return }
        let result = AppDialog.run(
            title: "Force Push with Lease?",
            message: "This rewrites \(branch) on its remote, but refuses if the remote contains work Kvist has not fetched.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Force Push with Lease", role: .destructive)
            ]
        )
        guard result.actionIndex == 1 else { return }
        await withSyncActivity {
            await self.perform("Force pushing with lease…") {
                _ = try $0.forcePushWithLease()
            }
        }
    }

    func forcePush() async {
        guard canForcePush else { return }
        let result = AppDialog.run(
            title: "Force Push?",
            message: "This rewrites \(branch) on its remote and can permanently discard commits pushed by someone else. Use Force Push with Lease unless you intentionally need to overwrite unseen remote work.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Force Push", role: .destructive)
            ]
        )
        guard result.actionIndex == 1 else { return }
        await withSyncActivity {
            await self.perform("Force pushing…") { _ = try $0.forcePush() }
        }
    }

    @discardableResult
    func continueActiveOperation() async -> Bool {
        guard let activeOperation else { return false }
        guard !hasUnresolvedConflicts else {
            errorMessage = "Resolve and stage every conflicted file before continuing the \(activeOperation.displayName.lowercased())."
            return false
        }
        return await perform("Continuing \(activeOperation.displayName.lowercased())…") {
            _ = try $0.continueOperation(activeOperation)
        }
    }

    var canSkipActiveOperation: Bool {
        activeOperation != nil && activeOperation != .merge
    }

    @discardableResult
    func skipActiveOperation() async -> Bool {
        guard let activeOperation, activeOperation != .merge else { return false }
        return await perform("Skipping \(activeOperation.displayName.lowercased()) step…") {
            _ = try $0.skipOperation(activeOperation)
        }
    }

    @discardableResult
    func abortActiveOperation() async -> Bool {
        guard let activeOperation else { return false }
        let result = AppDialog.run(
            title: "Abort \(activeOperation.displayName)?",
            message: "This stops the \(activeOperation.displayName.lowercased()) and discards conflict resolutions and other changes made during it. Git will restore the state from before the operation began.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(
                    title: "Abort \(activeOperation.displayName)",
                    role: .destructive
                )
            ]
        )
        guard result.actionIndex == 1 else { return false }
        return await perform("Aborting \(activeOperation.displayName.lowercased())…") {
            _ = try $0.abortOperation(activeOperation)
        }
    }

    func abortRebase() async {
        guard activeOperation == .rebase || isRebaseInProgress else { return }
        if activeOperation == nil {
            await refresh()
        }
        _ = await abortActiveOperation()
    }

    private var canForcePush: Bool {
        guard !isBusy, !isGeneratingCommitMessage else { return false }
        guard hasUpstream, branch != "detached HEAD" else {
            errorMessage = "Publish this branch before force pushing it."
            return false
        }
        return true
    }

    func sync() async {
        await withSyncActivity {
            let pulled = await self.perform("Pulling with rebase…") {
                _ = try $0.pullRebasing()
            }
            guard pulled else { return }
            await self.perform("Pushing…") { _ = try $0.push() }
        }
    }

    func pushOrPublish() async {
        if hasUpstream {
            await push()
        } else {
            await publish()
        }
    }

    @discardableResult
    func checkoutDetached(_ commit: CommitInfo) async -> Bool {
        await perform("Checking out \(commit.shortHash)…") {
            try $0.checkoutDetached(hash: commit.hash)
        }
    }

    @discardableResult
    func checkout(_ reference: GitReference) async -> Bool {
        await perform("Checking out \(reference.name)…") {
            try $0.checkout(reference: reference)
        }
    }

    func canFastForward(to reference: GitReference) -> Bool {
        fastForwardReferenceIDs.contains(reference.id)
    }

    @discardableResult
    func rebase(_ branch: GitReference, onto base: GitReference) async -> Bool {
        await perform("Rebasing \(branch.name) onto \(base.name)…") {
            try $0.rebase(branch, onto: base)
        }
    }

    @discardableResult
    func integrate(
        _ reference: GitReference,
        strategy: BranchIntegrationStrategy
    ) async -> Bool {
        let action: String
        switch strategy {
        case .fastForward: action = "Fast-forwarding"
        case .merge: action = "Merging"
        case .rebase: action = "Rebasing onto"
        }
        let firstAttempt = await runBranchIntegration(
            reference,
            strategy: strategy,
            message: "\(action) \(reference.name)…"
        )
        switch firstAttempt {
        case .success:
            return true
        case .failure(let error) where error is PredictedMergeConflictError:
            let result = AppDialog.run(
                title: "Resolve Merge Conflicts?",
                message: "Git found conflicts between “\(branch)” and “\(reference.name)”. Start the merge and resolve them in Kvist?\n\nConflicted files will appear under Changes. Keep the current or incoming version of a whole file, or open it in Files to combine both. Stage edited files, then choose Continue Merge.",
                actions: [
                    AppDialogAction(title: "Cancel", role: .cancel),
                    AppDialogAction(title: "Start Merge", role: .primary)
                ]
            )
            guard result.actionIndex == 1 else {
                activity = "Up to date"
                return false
            }
            let conflictAttempt = await runBranchIntegration(
                reference,
                strategy: strategy,
                message: "Starting merge with \(reference.name)…",
                allowConflicts: true
            )
            if case .failure(let error) = conflictAttempt {
                present(error)
                return false
            }
            return true
        case .failure(let error):
            present(error)
            return false
        }
    }

    private func runBranchIntegration(
        _ reference: GitReference,
        strategy: BranchIntegrationStrategy,
        message: String,
        allowConflicts: Bool = false
    ) async -> Result<Void, Error> {
        guard let repositoryURL,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage else {
            return .failure(CancellationError())
        }
        isBusy = true
        snapshotRequestID = UUID()
        workingTreeVersion += 1
        activity = message
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)

        do {
            try await mutationQueue.run(client: client) {
                try $0.integrate(
                    reference,
                    strategy: strategy,
                    allowConflicts: allowConflicts
                )
            }
            isBusy = false
            await refresh()
            return .success(())
        } catch {
            isBusy = false
            await refresh()
            return .failure(error)
        }
    }

    @discardableResult
    func createBranch(named name: String, at commit: CommitInfo) async -> Bool {
        await perform("Creating branch…") {
            try $0.createBranch(name: name, at: commit.hash)
        }
    }

    @discardableResult
    func createBranchAtHead(named name: String) async -> Bool {
        guard let headHash else { return false }
        return await perform("Creating branch…") {
            try $0.createBranch(name: name, at: headHash)
        }
    }

    @discardableResult
    func renameBranch(
        _ reference: GitReference,
        to newName: String
    ) async -> Bool {
        guard reference.kind == .localBranch else {
            errorMessage = "Only local branches can be renamed."
            return false
        }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a branch name."
            return false
        }
        return await perform("Renaming \(reference.name)…") {
            try $0.renameBranch(oldName: reference.name, to: trimmedName)
        }
    }

    @discardableResult
    func deleteBranch(_ reference: GitReference, force: Bool = false) async -> Bool {
        switch reference.kind {
        case .localBranch:
            return await perform("Deleting \(reference.name)…") {
                try $0.deleteLocalBranch(name: reference.name, force: force)
            }
        case .remoteBranch:
            return await perform("Deleting \(reference.name) from its remote…") {
                try $0.deleteRemoteBranch(name: reference.name)
            }
        case .tag, .other:
            errorMessage = "Only branches can be deleted with this action."
            return false
        }
    }

    @discardableResult
    func deleteBranchWithConfirmation(_ reference: GitReference) async -> Bool {
        guard reference.kind == .localBranch || reference.kind == .remoteBranch else {
            errorMessage = "Only branches can be deleted with this action."
            return false
        }
        let kind = reference.kind == .remoteBranch ? "Remote Branch" : "Branch"
        let result = AppDialog.run(
            title: "Delete \(kind)?",
            message: "Delete \(reference.name)?",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Delete", role: .destructive)
            ]
        )
        guard result.actionIndex == 1 else { return false }
        guard reference.kind == .localBranch else {
            return await deleteBranch(reference)
        }

        guard let repositoryURL,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage else { return false }
        isBusy = true
        activity = "Deleting \(reference.name)…"
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        do {
            try await mutationQueue.run(client: client) {
                try $0.deleteLocalBranch(name: reference.name, force: false)
            }
            isBusy = false
            await refresh()
            return true
        } catch {
            isBusy = false
            await refresh()
            guard isUnmergedBranchDeletionError(error) else {
                present(error)
                return false
            }
        }

        let forceResult = AppDialog.run(
            title: "Branch Is Not Fully Merged",
            message: "\(reference.name) contains commits that are not merged elsewhere. Force deletion can make those commits difficult to recover, although they may remain available in the reflog for a while.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Force Delete", role: .destructive)
            ]
        )
        guard forceResult.actionIndex == 1 else { return false }
        return await deleteBranch(reference, force: true)
    }

    private func isUnmergedBranchDeletionError(_ error: Error) -> Bool {
        let output: String
        if let gitError = error as? GitCommandError {
            output = gitError.output.lowercased()
        } else {
            output = error.localizedDescription.lowercased()
        }
        return output.contains("not fully merged")
            || output.contains("not yet merged")
            || output.contains("unmerged commits")
    }

    @discardableResult
    func createTag(
        named name: String,
        message: String? = nil,
        at commit: CommitInfo
    ) async -> Bool {
        await perform("Creating tag…") {
            try $0.createTag(name: name, at: commit.hash, message: message)
        }
    }

    @discardableResult
    func deleteTag(_ reference: GitReference) async -> Bool {
        guard reference.kind == .tag else {
            errorMessage = "Only tags can be deleted with this action."
            return false
        }
        return await perform("Deleting \(reference.name)…") {
            try $0.deleteTag(name: reference.name)
        }
    }

    @discardableResult
    func pushTag(
        _ reference: GitReference,
        to remote: GitRemote
    ) async -> Bool {
        guard reference.kind == .tag else {
            errorMessage = "Only tags can be pushed with this action."
            return false
        }
        return await perform("Pushing \(reference.name) to \(remote.name)…") {
            try $0.pushTag(name: reference.name, remote: remote.name)
        }
    }

    @discardableResult
    func deleteRemoteTag(
        _ reference: GitReference,
        from remote: GitRemote
    ) async -> Bool {
        guard reference.kind == .tag else {
            errorMessage = "Only tags can be deleted with this action."
            return false
        }
        let result = AppDialog.run(
            title: "Delete Remote Tag?",
            message: "Delete \(reference.name) from \(remote.name)? The local tag will remain.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Delete from \(remote.name)", role: .destructive)
            ]
        )
        guard result.actionIndex == 1 else { return false }
        return await perform("Deleting \(reference.name) from \(remote.name)…") {
            try $0.deleteRemoteTag(name: reference.name, remote: remote.name)
        }
    }

    func refreshRemotes() async {
        guard let repositoryURL,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage else { return }
        do {
            let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
            let loadedRemotes = try await Task.detached(priority: .userInitiated) {
                try client.remotes()
            }.value
            guard self.repositoryURL == repositoryURL else { return }
            if remotes != loadedRemotes { remotes = loadedRemotes }
        } catch {
            guard self.repositoryURL == repositoryURL else { return }
            present(error)
        }
    }

    @discardableResult
    func addRemote(name: String, url: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else {
            errorMessage = "Enter both a remote name and URL."
            return false
        }
        return await perform("Adding \(trimmedName)…") {
            try $0.addRemote(name: trimmedName, url: trimmedURL)
        }
    }

    @discardableResult
    func editRemote(_ remote: GitRemote, url: String) async -> Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            errorMessage = "Enter a remote URL."
            return false
        }
        return await perform("Updating \(remote.name)…") {
            try $0.setRemoteURL(name: remote.name, url: trimmedURL)
        }
    }

    @discardableResult
    func removeRemote(_ remote: GitRemote) async -> Bool {
        let upstreamWarning = upstreamReference?.name.hasPrefix(remote.name + "/") == true
            ? " The current branch tracks this remote, so removing it will also remove that usable upstream connection."
            : ""
        let result = AppDialog.run(
            title: "Remove Remote?",
            message: "Remove \(remote.name) from this repository? This does not delete the remote repository.\(upstreamWarning)",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Remove Remote", role: .destructive)
            ]
        )
        guard result.actionIndex == 1 else { return false }
        return await perform("Removing \(remote.name)…") {
            try $0.removeRemote(name: remote.name)
        }
    }

    @discardableResult
    func setUpstream(_ remoteBranch: GitReference) async -> Bool {
        guard remoteBranch.kind == .remoteBranch else {
            errorMessage = "Choose a remote branch as the upstream."
            return false
        }
        guard branch != "detached HEAD" else {
            errorMessage = "Check out a local branch before setting an upstream."
            return false
        }
        let currentBranch = branch
        return await perform("Setting upstream to \(remoteBranch.name)…") {
            try $0.setUpstream(branch: currentBranch, remoteBranch: remoteBranch.name)
        }
    }

    @discardableResult
    func unsetUpstream() async -> Bool {
        guard hasUpstream else { return false }
        guard branch != "detached HEAD" else { return false }
        let currentBranch = branch
        return await perform("Removing upstream from \(currentBranch)…") {
            try $0.unsetUpstream(branch: currentBranch)
        }
    }

    @discardableResult
    func cherryPick(_ commit: CommitInfo) async -> Bool {
        await perform("Cherry-picking \(commit.shortHash)…") {
            try $0.cherryPick(hash: commit.hash)
        }
    }

    @discardableResult
    func applyStash(_ commit: CommitInfo) async -> Bool {
        await perform("Applying stash…") {
            try $0.applyStash(hash: commit.hash)
        }
    }

    @discardableResult
    func popStash(_ commit: CommitInfo) async -> Bool {
        await perform("Popping stash…") {
            try $0.popStash(hash: commit.hash)
        }
    }

    @discardableResult
    func dropStash(_ commit: CommitInfo) async -> Bool {
        await perform("Dropping stash…") {
            try $0.dropStash(hash: commit.hash)
        }
    }

    @discardableResult
    func revert(_ commit: CommitInfo) async -> Bool {
        let result = AppDialog.run(
            title: "Revert Commit?",
            message: "Create a new commit that reverses \(commit.shortHash)? If the changes conflict with newer work, Git will pause the revert so you can resolve or abort it.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Revert Commit", role: .primary)
            ]
        )
        guard result.actionIndex == 1 else { return false }
        return await perform("Reverting \(commit.shortHash)…") {
            try $0.revert(hash: commit.hash)
        }
    }

    @discardableResult
    func reset(to commit: CommitInfo, mode: GitResetMode) async -> Bool {
        let branchLabel = branch.isEmpty || branch == "detached HEAD"
            ? "HEAD"
            : "“\(branch)”"
        let title: String
        let message: String
        let actionTitle: String
        let actionRole: AppDialogActionRole
        switch mode {
        case .soft:
            title = "Soft Reset?"
            message = "Move \(branchLabel) to \(commit.shortHash). Later commits leave the branch, but their changes stay staged and no files on disk change."
            actionTitle = "Soft Reset"
            actionRole = .primary
        case .mixed:
            title = "Mixed Reset?"
            message = "Move \(branchLabel) to \(commit.shortHash). Later commits leave the branch, and their changes become unstaged edits in the working tree. No files on disk change."
            actionTitle = "Mixed Reset"
            actionRole = .destructive
        case .hard:
            title = "Hard Reset?"
            message = "Move \(branchLabel) to \(commit.shortHash) and permanently discard all staged and unstaged changes to tracked files, including uncommitted work. Untracked files are kept. Removed commits remain recoverable from the reflog for a while."
            actionTitle = "Hard Reset"
            actionRole = .destructive
        }
        let result = AppDialog.run(
            title: title,
            message: message,
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: actionTitle, role: actionRole)
            ]
        )
        guard result.actionIndex == 1 else { return false }
        return await perform("Resetting to \(commit.shortHash)…") {
            try $0.reset(to: commit.hash, mode: mode)
        }
    }

    func compare(
        _ commit: CommitInfo,
        against reference: GitReference,
        fromMergeBase: Bool = false
    ) {
        clearGitFilePreview()
        selectedChange = nil
        selectedCommit = commit
        selectedCommitFile = nil
        selectedRepositoryFilePath = nil
        detailTitle = fromMergeBase
            ? "\(commit.shortHash) ↔ merge base with \(reference.name)"
            : "\(commit.shortHash) ↔ \(reference.name)"
        detailText = "Loading comparison…"
        detailKind = .diff
        isDetailLoading = true
        isDiffPanelPresented = true
        let requestID = UUID()
        detailRequestID = requestID

        guard let repositoryURL else { return }
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try client.comparisonDiff(
                        hash: commit.hash,
                        against: reference,
                        fromMergeBase: fromMergeBase
                    )
                }.value
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = output.isEmpty ? "No differences." : output
                isDetailLoading = false
            } catch {
                guard detailRequestID == requestID,
                      self.repositoryURL == repositoryURL else { return }
                detailText = "Could not load this comparison. Choose it again to retry."
                isDetailLoading = false
                present(error)
            }
        }
    }

    func compareWithUpstream(
        _ commit: CommitInfo,
        fromMergeBase: Bool = false
    ) {
        guard let upstreamReference else {
            errorMessage = "This branch does not have an upstream remote."
            return
        }
        compare(commit, against: upstreamReference, fromMergeBase: fromMergeBase)
    }

    func setGraphScope(_ scope: GraphScope) async {
        guard graphScope != scope, !isGeneratingCommitMessage,
              let repositoryURL else { return }
        graphHistoryLoadTask?.cancel()
        graphHistoryLoadTask = nil
        isLoadingMoreGraph = false
        graphScope = scope
        graphLimit = graphPageSize
        let requestID = UUID()
        snapshotRequestID = requestID
        activity = "Switching graph scope…"
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)
        let remoteReferenceID = upstreamReference?.id
        let pageSize = graphPageSize
        guard let knownHeadHash = headHash else { return }
        let referencesByCommitHash = referencesByCommitHash
        let loadTask = Task.detached(priority: .userInitiated) {
            try client.historyPage(
                offset: 0,
                count: pageSize,
                scope: scope.gitScope,
                remoteReferenceID: remoteReferenceID,
                knownHeadHash: knownHeadHash,
                layoutState: GraphLayoutState(),
                referencesByCommitHash: referencesByCommitHash
            )
        }
        graphHistoryLoadTask = loadTask
        do {
            let history = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            guard snapshotRequestID == requestID,
                  self.repositoryURL == repositoryURL,
                  graphScope == scope else {
                graphHistoryLoadTask = nil
                return
            }
            graphHistoryLoadTask = nil
            applyGraph(history, scope: scope)
            activity = "Up to date"
        } catch {
            graphHistoryLoadTask = nil
            guard snapshotRequestID == requestID,
                  self.repositoryURL == repositoryURL else { return }
            if !(error is CancellationError) { present(error) }
        }
    }

    func generateCommitMessage() async {
        guard let repositoryURL,
              hasStagedChanges,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage else { return }
        let configuration = AICommitMessageConfiguration.load()
        guard confirmAIProcessingConsentIfNeeded(for: configuration.provider) else { return }
        let messageBeforeGeneration = commitMessage
        let sshRepository = self.sshRepository
        isGeneratingCommitMessage = true
        let hasInstructions = !messageBeforeGeneration
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        activity = hasInstructions
            ? "Generating commit message from your instructions…"
            : "Generating commit message with \(configuration.provider.displayName)…"

        do {
            let message = try await Task.detached(priority: .userInitiated) {
                try AICommitMessageGenerator(configuration: configuration).generate(
                    in: repositoryURL,
                    overSSH: sshRepository,
                    userInstructions: messageBeforeGeneration
                )
            }.value
            if self.repositoryURL == repositoryURL,
               commitMessage == messageBeforeGeneration {
                commitMessage = message
                activity = "Commit message generated"
            } else if self.repositoryURL == repositoryURL {
                activity = "Generated message kept aside because you edited the field"
            }
        } catch {
            present(error)
        }

        isGeneratingCommitMessage = false
        await drainPendingWorkingTreeRefresh()
        await drainPendingLiveRefresh()
    }

    private func confirmAIProcessingConsentIfNeeded(
        for provider: AICommitMessageProvider
    ) -> Bool {
        let defaults = UserDefaults.standard
        let consentKey = PrivacyPreferences.processingConsentKey(for: provider)
        if defaults.bool(forKey: consentKey) {
            return true
        }

        let result = AppDialog.run(
            title: "Send staged changes to \(provider.displayName)?",
            message: "Kvist will launch the \(provider.displayName) CLI signed in to your account. \(provider.displayName) may send the staged diff, this repository's path, and any instructions in the commit field to \(provider.serviceName).\n\nUnstaged and untracked changes are excluded by Kvist's prompt. Continue only if you are authorized to send the staged source code.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Allow & Continue", role: .primary)
            ]
        )
        guard result.actionIndex == 1 else { return false }
        defaults.set(true, forKey: consentKey)
        return true
    }

    @discardableResult
    private func performChangeOperation(
        _ message: String,
        paths: Set<String>,
        operation: @escaping @Sendable (GitClient) throws -> Void,
        optimisticUpdate: @escaping @MainActor () -> Void
    ) async -> Bool {
        guard let repositoryURL,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage,
              pendingChangePaths.isDisjoint(with: paths) else { return false }

        pendingChangePaths.formUnion(paths)
        activity = message
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)

        do {
            try await mutationQueue.run(client: client, operation: operation)
            guard self.repositoryURL == repositoryURL else {
                pendingChangePaths.subtract(paths)
                return false
            }
            optimisticUpdate()
            pendingChangePaths.subtract(paths)
            if pendingChangePaths.isEmpty, !isBusy {
                activity = "Up to date"
            }
            scheduleWorkingTreeRefresh(delay: .zero)
            return true
        } catch {
            let commandError = error
            pendingChangePaths.subtract(paths)
            scheduleWorkingTreeRefresh(delay: .zero)
            present(commandError)
            return false
        }
    }

    @discardableResult
    private func perform(
        _ message: String,
        presentsErrors: Bool = true,
        operation: @escaping @Sendable (GitClient) throws -> Void
    ) async -> Bool {
        guard let repositoryURL,
              !isBusy,
              !isSavingRepositoryFile,
              !isGeneratingCommitMessage else { return false }
        isBusy = true
        snapshotRequestID = UUID()
        workingTreeVersion += 1
        activity = message
        let client = GitClient(repositoryURL: repositoryURL, sshRepository: sshRepository)

        do {
            try await mutationQueue.run(client: client, operation: operation)
            isBusy = false
            await refresh(
                activityMessage: "Refreshing…",
                blocksActions: true,
                presentsErrors: presentsErrors
            )
            return true
        } catch {
            let commandError = error
            isBusy = false
            await refresh(
                activityMessage: "Refreshing…",
                blocksActions: true,
                presentsErrors: presentsErrors
            )
            if activeOperation == .rebase,
               hasUnresolvedConflicts,
               (commandError as? GitCommandError)?.rebaseConflictPresentation != nil {
                activity = "Rebase paused"
            } else if presentsErrors {
                present(commandError)
            }
            return false
        }
    }

    private func apply(
        _ snapshot: RepositorySnapshot,
        includeWorkingTree: Bool = true
    ) {
        if branch != snapshot.branch { branch = snapshot.branch }
        if includeWorkingTree {
            applyWorkingTree(
                WorkingTreeSnapshot(
                    staged: snapshot.staged,
                    unstaged: snapshot.unstaged,
                    resolveUndoPaths: snapshot.resolveUndoPaths
                )
            )
        }
        if references != snapshot.references { references = snapshot.references }
        if upstreamReference != snapshot.upstreamReference {
            upstreamReference = snapshot.upstreamReference
        }
        if ahead != snapshot.ahead { ahead = snapshot.ahead }
        if behind != snapshot.behind { behind = snapshot.behind }
        if hasUpstream != snapshot.hasUpstream { hasUpstream = snapshot.hasUpstream }
        if isRebaseInProgress != snapshot.isRebaseInProgress {
            isRebaseInProgress = snapshot.isRebaseInProgress
        }
        if fastForwardReferenceIDs != snapshot.fastForwardReferenceIDs {
            fastForwardReferenceIDs = snapshot.fastForwardReferenceIDs
        }
        graphHistoryOffset = snapshot.historyOffset
        graphHasMore = snapshot.graphHasMore
        graphLayoutState = snapshot.graphLayoutState
        referencesByCommitHash = snapshot.referencesByCommitHash
        applyGraphRows(
            snapshot.graph,
            headHash: snapshot.headHash,
            scope: graphScope
        )

        closeDiffPanelIfSelectionWasRemoved()
    }

    private func applyRepositoryMetadata(
        remotes: [GitRemote],
        activeOperation: GitOperation?
    ) {
        if self.remotes != remotes { self.remotes = remotes }
        if remotes.isEmpty {
            autoFetchTask?.cancel()
            autoFetchTask = nil
        } else if autoFetchTask == nil {
            startAutoFetching()
        }
        if self.activeOperation != activeOperation {
            self.activeOperation = activeOperation
        }
        let rebaseInProgress = activeOperation == .rebase
        if isRebaseInProgress != rebaseInProgress {
            isRebaseInProgress = rebaseInProgress
        }
    }

    private func applyWorkingTree(_ snapshot: WorkingTreeSnapshot) {
        if staged != snapshot.staged { staged = snapshot.staged }
        if unstaged != snapshot.unstaged { unstaged = snapshot.unstaged }
        if resolveUndoPaths != snapshot.resolveUndoPaths {
            resolveUndoPaths = snapshot.resolveUndoPaths
        }
        workingTreeVersion += 1
        closeDiffPanelIfSelectionWasRemoved()

        if workspaceMode == .fileEditor,
           let selectedRepositoryFilePath {
            guard !isRepositoryFileDirty else { return }
            let fileURL = selectedRepositoryFileURL
            if let fileURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                let diskVersion = RepositoryFileDiskVersion(fileURL: fileURL)
                if diskVersion != repositoryFileDiskVersion {
                    openRepositoryFile(selectedRepositoryFilePath)
                }
            } else if fileURL == nil {
                detailRequestID = UUID()
                detailText = "Kvist can only preview files inside this repository."
                detailKind = .message
                isDetailLoading = false
                isDiffPanelPresented = true
            } else {
                closeDiffPanel()
            }
        }
    }

    private func optimisticallyStage(_ changes: [FileChange]) {
        for change in changes {
            unstaged.removeAll { $0.path == change.path }
            guard !staged.contains(where: { $0.path == change.path }) else { continue }
            staged.append(FileChange(
                path: change.path,
                previousPath: change.previousPath,
                status: stagedStatus(for: change.status),
                area: .staged
            ))
        }
        staged.sort(by: changeOrdering)
        workingTreeVersion += 1
        closeDiffPanelIfSelectionWasRemoved()
    }

    /// Staging settles what the working tree showed: untracked files become
    /// additions and conflicts become plain modifications, so the staged list
    /// never publishes a conflict marker while the status refresh is pending.
    private func stagedStatus(for status: String) -> String {
        switch status {
        case "U": return "A"
        case "!": return "M"
        default: return status
        }
    }

    private func optimisticallyUnstage(_ changes: [FileChange]) {
        for change in changes {
            staged.removeAll { $0.path == change.path }

            if change.status == "R", let previousPath = change.previousPath {
                unstaged.removeAll {
                    $0.path == change.path || $0.path == previousPath
                }
                unstaged.append(FileChange(
                    path: previousPath,
                    status: "D",
                    area: .unstaged
                ))
                unstaged.append(FileChange(
                    path: change.path,
                    status: "U",
                    area: .unstaged
                ))
                continue
            }

            if change.status == "A" || change.status == "C" {
                unstaged.removeAll { $0.path == change.path }
                unstaged.append(FileChange(
                    path: change.path,
                    status: "U",
                    area: .unstaged
                ))
                continue
            }

            guard !unstaged.contains(where: { $0.path == change.path }) else { continue }
            unstaged.append(FileChange(
                path: change.path,
                previousPath: change.previousPath,
                status: change.status,
                area: .unstaged
            ))
        }
        unstaged.sort(by: changeOrdering)
        workingTreeVersion += 1
        closeDiffPanelIfSelectionWasRemoved()
    }

    private func optimisticallyReopenConflict(_ change: FileChange) {
        staged.removeAll { $0.path == change.path }
        unstaged.removeAll { $0.path == change.path }
        unstaged.append(FileChange(
            path: change.path,
            previousPath: change.previousPath,
            status: "!",
            area: .unstaged
        ))
        unstaged.sort(by: changeOrdering)
        workingTreeVersion += 1
        closeDiffPanelIfSelectionWasRemoved()
    }

    private func optimisticallyDiscard(_ change: FileChange) {
        unstaged.removeAll { $0.path == change.path }
        workingTreeVersion += 1
        closeDiffPanelIfSelectionWasRemoved()
    }

    private func closeDiffPanelIfSelectionWasRemoved() {
        guard let selectedChange,
              !staged.contains(selectedChange),
              !unstaged.contains(selectedChange) else { return }
        closeDiffPanel()
    }

    private func changeOrdering(_ lhs: FileChange, _ rhs: FileChange) -> Bool {
        lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }

    private func applyGraph(_ page: GitHistoryPage, scope: GraphScope) {
        graphHistoryOffset = page.nextOffset
        graphHasMore = page.hasMore
        graphLayoutState = page.layoutState
        applyGraphRows(page.rows, headHash: page.headHash, scope: scope)
    }

    private func appendGraph(_ rows: [GraphRow], scope: GraphScope) {
        guard scope == graphScope else {
            staleGraphPublicationCount += 1
            return
        }
        graphPublicationScope = scope
        guard !rows.isEmpty else { return }
        if graph.count == graphPageSize {
            graph.reserveCapacity(5_000)
        }
        graph.append(contentsOf: rows)
        graphPublicationVersion &+= 1
    }

    private func applyGraphRows(
        _ rows: [GraphRow],
        headHash: String?,
        scope: GraphScope
    ) {
        guard scope == graphScope else {
            staleGraphPublicationCount += 1
            return
        }
        graphPublicationScope = scope
        if graph != rows {
            graph = rows
            graphPublicationVersion &+= 1
        }
        if self.headHash != headHash { self.headHash = headHash }
        let visibleCommitHashes = Set(rows.map(\.commit.hash))
        let retainedExpandedHashes = expandedCommitHashes.intersection(
            visibleCommitHashes
        )
        if expandedCommitHashes != retainedExpandedHashes {
            expandedCommitHashes = retainedExpandedHashes
        }
        let retainedCommitFiles = commitFilesByHash.filter {
            visibleCommitHashes.contains($0.key)
        }
        if commitFilesByHash != retainedCommitFiles {
            commitFilesByHash = retainedCommitFiles
        }
        let retainedLoadingHashes = loadingCommitFileHashes.intersection(
            visibleCommitHashes
        )
        if loadingCommitFileHashes != retainedLoadingHashes {
            loadingCommitFileHashes = retainedLoadingHashes
        }

        if let selectedCommit,
           !rows.contains(where: { $0.commit.hash == selectedCommit.hash }) {
            detailRequestID = UUID()
            clearGitFilePreview()
            self.selectedCommit = nil
            selectedCommitFile = nil
            detailText = ""
            isDetailLoading = false
            detailTitle = "Select a changed file or commit"
            detailKind = .diff
            isDiffPanelPresented = false
        }
    }

    private func startWatching(paths: [String], sinceWhen: UInt64? = nil) {
        repositoryWatchPaths = paths
        if let sinceWhen {
            repositoryWatchSinceEventID = sinceWhen
        }
        repositoryMetadataPaths = Array(paths.dropFirst()).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        repositoryWatcher?.stop()
        repositoryWatcher = nil
        guard monitoringEnabled else { return }

        let watcher = RepositoryWatcher(
            paths: minimizedWatchPaths(paths),
            sinceWhen: repositoryWatchSinceEventID
        ) { [weak self] changedPaths, fileTreePaths in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if fileTreePaths?.contains(where: {
                    !self.isRepositoryMetadataPath($0)
                }) ?? true {
                    self.repositoryFilesRevision &+= 1
                    self.scheduleRepositorySearch(presentsResults: false)
                }
                self.scheduleLiveRefresh(for: changedPaths)
            }
        }
        repositoryWatcher = watcher
        watcher.start()
    }

    private func startAutoFetching() {
        guard monitoringEnabled,
              repositoryURL != nil,
              !remotes.isEmpty,
              autoFetchTask == nil else { return }
        autoFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let shouldContinue = self.map({
                    $0.monitoringEnabled
                        && $0.repositoryURL != nil
                        && !$0.remotes.isEmpty
                }), shouldContinue else { return }
                let delay: Duration
                if !NSApplication.shared.isActive {
                    delay = .seconds(15)
                } else if await self?.autoFetch(applicationIsActive: true) == nil {
                    delay = .seconds(1)
                } else {
                    delay = .seconds(180)
                }
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func minimizedWatchPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        let standardized = paths.compactMap { rawPath -> String? in
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            return seen.insert(path).inserted ? path : nil
        }
        return standardized.filter { candidate in
            !standardized.contains { parent in
                parent != candidate && candidate.hasPrefix(parent + "/")
            }
        }
    }

    private func scheduleLiveRefresh(
        for changedPaths: [String] = [],
        delay: Duration = .zero
    ) {
        guard monitoringEnabled, repositoryURL != nil else { return }

        if !requiresFullRefresh(for: changedPaths) {
            scheduleWorkingTreeRefresh(delay: delay)
            return
        }

        pendingLiveRefresh = true
        pendingWorkingTreeRefresh = false
        workingTreeRefreshTask?.cancel()
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            self.liveRefreshTask = nil
            await self.drainPendingLiveRefresh()
        }
    }

    private func scheduleWorkingTreeRefresh(
        delay: Duration = .zero
    ) {
        guard monitoringEnabled,
              repositoryURL != nil,
              !pendingLiveRefresh else { return }
        pendingWorkingTreeRefresh = true
        workingTreeRefreshTask?.cancel()
        workingTreeRefreshTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            self.workingTreeRefreshTask = nil
            await self.drainPendingWorkingTreeRefresh()
        }
    }

    private func requiresFullRefresh(for changedPaths: [String]) -> Bool {
        guard !changedPaths.isEmpty else { return true }

        for rawPath in changedPaths {
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            guard let metadataRoot = repositoryMetadataPaths.first(where: {
                path == $0 || path.hasPrefix($0 + "/")
            }) else {
                continue
            }

            let relativePath: String
            if path == metadataRoot {
                relativePath = ""
            } else {
                relativePath = String(path.dropFirst(metadataRoot.count + 1))
            }
            let isIndexChange = relativePath == "index" || relativePath == "index.lock"
            let isObjectChange = relativePath == "objects"
                || relativePath.hasPrefix("objects/")
            if !isIndexChange && !isObjectChange {
                return true
            }
        }
        return false
    }

    private func isRepositoryMetadataPath(_ rawPath: String) -> Bool {
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        return repositoryMetadataPaths.contains {
            path == $0 || path.hasPrefix($0 + "/")
        }
    }

    private func drainPendingWorkingTreeRefresh() async {
        guard pendingWorkingTreeRefresh,
              !pendingLiveRefresh,
              !isRefreshInProgress,
              monitoringEnabled,
              repositoryURL != nil,
              !isBusy,
              !isGeneratingCommitMessage,
              !isLoadingMoreGraph else { return }
        await refreshWorkingTree()
    }

    private func drainPendingLiveRefresh() async {
        guard pendingLiveRefresh,
              !isRefreshInProgress,
              monitoringEnabled,
              repositoryURL != nil,
              !isBusy,
              !isGeneratingCommitMessage,
              !isLoadingMoreGraph else { return }
        await refresh(activityMessage: "Refreshing…", blocksActions: false)
    }

    private func present(_ error: Error) {
        if let aiError = error as? AICommitMessageError {
            errorPresentation = RepositoryErrorPresentation(
                title: aiError.provider.map {
                    "\($0.displayName) Commit Message"
                } ?? "AI Commit Message",
                message: aiError.localizedDescription,
                details: aiError.diagnosticDetails
            )
        } else if let gitError = error as? GitCommandError {
            if let presentation = gitError.rebaseConflictPresentation {
                errorPresentation = RepositoryErrorPresentation(
                    title: presentation.title,
                    message: presentation.message,
                    details: presentation.details
                )
            } else if let presentation = gitError.missingToolPresentation
                ?? gitError.sshAuthenticationPresentation {
                errorPresentation = RepositoryErrorPresentation(
                    title: presentation.title,
                    message: presentation.message,
                    details: presentation.details
                )
            } else {
                let presentation = gitError.commandFailurePresentation
                errorPresentation = RepositoryErrorPresentation(
                    title: presentation.title,
                    message: presentation.message,
                    details: presentation.details
                )
            }
        } else {
            errorMessage = error.localizedDescription
        }
        activity = "Command failed"
    }
}

private struct RepositoryFileSession {
    let path: String
    let title: String
    let detailText: String
    let fileText: String
    let savedFileText: String
    let kind: RepositoryDetailKind
    let isPanelPresented: Bool
    let diskVersion: RepositoryFileDiskVersion?

    var isDirty: Bool {
        kind == .source && fileText != savedFileText
    }
}

private struct RepositoryFileDraft {
    let path: String
    let title: String
    let text: String
    let savedText: String
    let diskVersion: RepositoryFileDiskVersion?
    let isActive: Bool
}

struct RepositoryFileDiskVersion: Equatable {
    let contentModificationDate: Date?
    let fileSize: Int?
    let contentHash: String?

    init(contentModificationDate: Date?, fileSize: Int?, contentHash: String?) {
        self.contentModificationDate = contentModificationDate
        self.fileSize = fileSize
        self.contentHash = contentHash
    }

    init(fileURL: URL) {
        let values = try? fileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        contentModificationDate = values?.contentModificationDate
        fileSize = values?.fileSize
        contentHash = fileSize.map { $0 <= RepositoryFileLoader.maximumSourceFileSize } == true
            ? (try? Data(contentsOf: fileURL, options: .mappedIfSafe)).map {
                SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
            }
            : nil
    }
}

private struct GitDetailSession {
    let selectedChange: FileChange?
    let selectedCommit: CommitInfo?
    let selectedCommitFile: CommitFileChange?
    let title: String
    let text: String
    let preview: GitFilePreview?
    let detailMode: GitFileDetailMode
    let conflictResolution: ConflictResolutionSession?
    let isPanelPresented: Bool
}

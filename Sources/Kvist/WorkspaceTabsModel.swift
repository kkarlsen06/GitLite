import Combine
import Foundation

@MainActor
final class RepositoryTab: ObservableObject, Identifiable {
    let id: UUID
    private var storedModel: RepositoryModel?
    fileprivate var repositoryPath: String?
    private var activationTask: Task<Void, Never>?
    private var activationGeneration = UUID()
    private var pendingRestorationState: RepositoryRestorationState?
    private var restorationSubscriptions: Set<AnyCancellable> = []
    fileprivate var restorationDidChange: (() -> Void)?
    fileprivate var modelDidInitialize: ((RepositoryModel) -> Void)?
    @Published private(set) var hasChanges = false
    @Published private(set) var isRepositoryLoadPending: Bool

    init(
        id: UUID = UUID(),
        repositoryURL: URL? = nil,
        restorationState: RepositoryRestorationState? = nil
    ) {
        self.id = id
        repositoryPath = repositoryURL?.standardizedFileURL.path
        pendingRestorationState = restorationState
        isRepositoryLoadPending = repositoryURL != nil
    }

    var model: RepositoryModel {
        if let storedModel { return storedModel }
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )
        storedModel = model
        observeRestorableState(model: model)
        modelDidInitialize?(model)
        return model
    }

    var loadedModel: RepositoryModel? {
        storedModel
    }

    var repositoryURL: URL? {
        storedModel?.repositoryURL ?? repositoryPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    var displayName: String {
        if let repositoryURL = storedModel?.repositoryURL {
            return repositoryURL.lastPathComponent
        }
        if let repositoryPath {
            return URL(fileURLWithPath: repositoryPath).lastPathComponent
        }
        return "New"
    }

    fileprivate func activate() {
        let model = model
        guard model.repositoryInitializationURL == nil else {
            isRepositoryLoadPending = false
            return
        }
        guard !model.isBusy else { return }
        let repositoryURL: URL?
        if let deferredRepositoryOpenURL = model.deferredRepositoryOpenURL {
            repositoryURL = deferredRepositoryOpenURL
        } else if model.repositoryURL == nil {
            repositoryURL = repositoryPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        } else {
            repositoryURL = nil
        }
        guard let repositoryURL else {
            isRepositoryLoadPending = false
            return
        }
        isRepositoryLoadPending = true
        let generation = UUID()
        activationGeneration = generation
        activationTask = Task { [weak self, weak model] in
            await model?.openRepository(repositoryURL)
            guard let self,
                  self.activationGeneration == generation else { return }
            if let state = self.pendingRestorationState {
                self.pendingRestorationState = nil
                await model?.restore(from: state)
            }
            self.activationTask = nil
            self.isRepositoryLoadPending = false
            self.restorationDidChange?()
        }
    }

    fileprivate func deactivate() {
        guard let model = storedModel else { return }
        activationGeneration = UUID()
        activationTask?.cancel()
        activationTask = nil
        model.cancelRepositoryOpen()
        model.setMonitoringEnabled(false)
        isRepositoryLoadPending = model.repositoryURL == nil
            && model.repositoryInitializationURL == nil
            && repositoryPath != nil
    }

    fileprivate var restorationState: RepositoryRestorationState {
        pendingRestorationState ?? storedModel?.makeRestorationState()
            ?? RepositoryRestorationState()
    }

    private func observeRestorableState(model: RepositoryModel) {
        model.restorationStateDidChange = { [weak self] in
            guard self?.pendingRestorationState == nil else { return }
            self?.restorationDidChange?()
        }
        let publishers: [AnyPublisher<Void, Never>] = [
            model.$workspaceMode.map { _ in () }.eraseToAnyPublisher(),
            model.$expandedFileDirectories.map { _ in () }.eraseToAnyPublisher(),
            model.$expandedCommitHashes.map { _ in () }.eraseToAnyPublisher(),
            model.$graphScope.map { _ in () }.eraseToAnyPublisher(),
            model.$isOutgoingExpanded.map { _ in () }.eraseToAnyPublisher(),
            model.$selectedRepositoryFilePath.map { _ in () }.eraseToAnyPublisher(),
            model.$isDiffPanelPresented.map { _ in () }.eraseToAnyPublisher(),
            model.$detailKind.map { _ in () }.eraseToAnyPublisher(),
            model.$repositoryFileDirty.map { _ in () }.eraseToAnyPublisher(),
            model.commitMessageState.$text.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(publishers)
            .dropFirst()
            .sink { [weak self] _ in
                guard self?.pendingRestorationState == nil else { return }
                self?.restorationDidChange?()
            }
            .store(in: &restorationSubscriptions)
        model.$staged.combineLatest(model.$unstaged)
            .map { !$0.isEmpty || !$1.isEmpty }
            .removeDuplicates()
            .sink { [weak self] in self?.hasChanges = $0 }
            .store(in: &restorationSubscriptions)
    }
}
private struct RestoredRepositoryTab: Codable {
    let id: UUID
    let repositoryPath: String?
    let state: RepositoryRestorationState
}

private struct RestoredWorkspace: Codable {
    let activeTabID: UUID
    let tabs: [RestoredRepositoryTab]
}

@MainActor
final class WorkspaceTabsModel: ObservableObject {
    @Published private(set) var tabs: [RepositoryTab] = []
    @Published private(set) var activeTabID: UUID {
        didSet { activeTabDidChange(from: oldValue) }
    }
    @Published private(set) var recentRepositoryPaths: [String] = []

    private let defaults: UserDefaults
    private let persistenceEnabled: Bool
    private let monitoringActivationDelayMilliseconds: Int
    private var hasActivatedInitialTab = false
    private let openRepositoriesKey = "openRepositoryPaths"
    private let activeRepositoryKey = "activeRepositoryPath"
    private let legacyRepositoryKey = "lastRepositoryPath"
    private let recentRepositoriesKey = "recentRepositoryPaths"
    private let restoredWorkspaceKey = "restoredWorkspaceV2"
    private let recentRepositoriesLimit = 7
    private var repositorySubscriptions: [UUID: AnyCancellable] = [:]
    private var activeModelSubscription: AnyCancellable?
    private var persistenceTask: Task<Void, Never>?
    private var monitoringActivationWorkItem: DispatchWorkItem?

    init(
        defaults: UserDefaults = .standard,
        restoreSavedTabs: Bool = true,
        initialRepositoryURL: URL? = nil,
        restoredRepositoryURLs: [URL]? = nil,
        persistenceEnabled: Bool = true,
        automaticallyActivatesInitialTab: Bool = true,
        monitoringActivationDelayMilliseconds: Int = 100
    ) {
        self.defaults = defaults
        self.persistenceEnabled = persistenceEnabled
        self.monitoringActivationDelayMilliseconds = max(
            0,
            monitoringActivationDelayMilliseconds
        )
        recentRepositoryPaths = (defaults.stringArray(forKey: recentRepositoriesKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }

        let restoredWorkspace = restoreSavedTabs
            ? defaults.data(forKey: restoredWorkspaceKey).flatMap {
                try? JSONDecoder().decode(RestoredWorkspace.self, from: $0)
            }
            : nil

        let savedPaths: [String]
        if restoreSavedTabs, restoredWorkspace == nil {
            let currentPaths = defaults.stringArray(forKey: openRepositoriesKey) ?? []
            if currentPaths.isEmpty,
               let legacyPath = defaults.string(forKey: legacyRepositoryKey) {
                savedPaths = [legacyPath]
            } else {
                savedPaths = currentPaths
            }
        } else {
            savedPaths = []
        }

        var seen = Set<String>()
        let repositoryURLs = savedPaths.compactMap { path -> URL? in
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard seen.insert(standardizedPath).inserted,
                  FileManager.default.fileExists(atPath: standardizedPath) else {
                return nil
            }
            return URL(fileURLWithPath: standardizedPath, isDirectory: true)
        }

        let detailedTabs = restoredWorkspace?.tabs.compactMap { saved -> RepositoryTab? in
            guard let path = saved.repositoryPath else {
                return RepositoryTab(id: saved.id, restorationState: saved.state)
            }
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard seen.insert(standardizedPath).inserted,
                  FileManager.default.fileExists(atPath: standardizedPath) else {
                return nil
            }
            return RepositoryTab(
                id: saved.id,
                repositoryURL: URL(fileURLWithPath: standardizedPath, isDirectory: true),
                restorationState: saved.state
            )
        } ?? []
        let restoredTabs: [RepositoryTab]
        if let restoredRepositoryURLs {
            restoredTabs = restoredRepositoryURLs.map { RepositoryTab(repositoryURL: $0) }
        } else if let initialRepositoryURL {
            restoredTabs = [RepositoryTab(repositoryURL: initialRepositoryURL)]
        } else {
            restoredTabs = detailedTabs.isEmpty
                ? repositoryURLs.map { RepositoryTab(repositoryURL: $0) }
                : detailedTabs
        }
        let initialTabs = restoredTabs.isEmpty ? [RepositoryTab()] : restoredTabs
        tabs = initialTabs

        let preferredPath = defaults.string(forKey: activeRepositoryKey)
        let preferredIndex = restoredWorkspace.flatMap { workspace in
            initialTabs.firstIndex { $0.id == workspace.activeTabID }
        } ?? preferredPath.flatMap { path in
            initialTabs.firstIndex {
                $0.repositoryPath
                    == URL(fileURLWithPath: path).standardizedFileURL.path
            }
        } ?? 0
        activeTabID = initialTabs[preferredIndex].id

        initialTabs.forEach(observeRepository)
        // Avoid materializing the active RepositoryModel until a caller has
        // explicitly activated the lazily restored workspace.
        if automaticallyActivatesInitialTab {
            activateInitialTab()
        }
    }

    deinit {
        persistenceTask?.cancel()
        monitoringActivationWorkItem?.cancel()
    }

    private func activeTabDidChange(from oldTabID: UUID) {
        monitoringActivationWorkItem?.cancel()
        tabs.first(where: { $0.id == oldTabID })?.deactivate()
        activate(activeTab)
        forwardActiveModelChanges()
    }

    func activateInitialTab() {
        guard !hasActivatedInitialTab else { return }
        hasActivatedInitialTab = true
        forwardActiveModelChanges()
        activate(activeTab)
    }

    private func activate(_ tab: RepositoryTab) {
        tab.activate()
        let tabID = tab.id
        let workItem = DispatchWorkItem { [weak self, weak tab] in
            guard let self,
                  self.activeTabID == tabID else { return }
            tab?.model.setMonitoringEnabled(true)
            self.monitoringActivationWorkItem = nil
        }
        monitoringActivationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(monitoringActivationDelayMilliseconds),
            execute: workItem
        )
    }

    /// Menu-bar commands read state from the active tab's repository model, so
    /// command-relevant changes republish through this object for validation.
    /// Keeping editor text out of this stream prevents every keystroke from
    /// invalidating the complete window hierarchy.
    private func forwardActiveModelChanges() {
        let model = activeModel
        let commandState: [AnyPublisher<Void, Never>] = [
            model.$repositoryURL.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$workspaceMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$selectedRepositoryFilePath.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$detailKind.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$repositoryFileDirty.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$isSavingRepositoryFile.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$isDiffPanelPresented.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$isBusy.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$isGeneratingCommitMessage.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$pendingChangePaths.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$staged.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$unstaged.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$hasUpstream.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$branch.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$headHash.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        activeModelSubscription = Publishers.MergeMany(commandState)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    var activeTab: RepositoryTab {
        tabs.first(where: { $0.id == activeTabID }) ?? tabs[0]
    }

    var activeModel: RepositoryModel {
        activeTab.model
    }

    var activeRepositoryWatcherCount: Int {
        tabs.count { $0.loadedModel?.hasActiveRepositoryWatcher == true }
    }

    var outstandingRepositoryTaskCount: Int {
        tabs.count { $0.loadedModel?.hasOutstandingRepositoryTasks == true }
    }

    func addTab() {
        let tab = RepositoryTab()
        tabs.append(tab)
        observeRepository(tab)
        activeTabID = tab.id
        persistTabs()
    }

    func select(_ tabID: UUID) {
        guard tabID != activeTabID,
              tabs.contains(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        persistTabs()
    }

    func selectNext() {
        selectAdjacentTab(offset: 1)
    }

    func selectPrevious() {
        selectAdjacentTab(offset: -1)
    }

    private func selectAdjacentTab(offset: Int) {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return
        }
        let next = (index + offset + tabs.count) % tabs.count
        select(tabs[next].id)
    }

    func close(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard tabs[index].model.confirmDiscardRepositoryFileChanges() else { return }
        tabs[index].deactivate()
        repositorySubscriptions[tabID] = nil
        tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = RepositoryTab()
            tabs = [replacement]
            observeRepository(replacement)
            activeTabID = replacement.id
        } else if activeTabID == tabID {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }

        persistTabs()
    }

    func closeOthers(_ tabID: UUID) {
        guard let keptTab = tabs.first(where: { $0.id == tabID }) else { return }
        guard tabs.filter({ $0.id != tabID }).allSatisfy({
            $0.model.confirmDiscardRepositoryFileChanges()
        }) else { return }
        for tab in tabs where tab.id != tabID {
            tab.deactivate()
            repositorySubscriptions[tab.id] = nil
        }
        tabs = [keptTab]
        if activeTabID != keptTab.id {
            activeTabID = keptTab.id
        }
        persistTabs()
    }

    var hasUnsavedRepositoryFileChanges: Bool {
        tabs.contains { $0.model.hasUnsavedRepositoryFileChanges }
    }

    func confirmDiscardAllRepositoryFileChanges() -> Bool {
        tabs.allSatisfy { $0.model.confirmDiscardRepositoryFileChanges() }
    }

    var recentRepositoryURLs: [URL] {
        recentRepositoryPaths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func removeRecentRepository(path: String) {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        recentRepositoryPaths.removeAll { $0 == standardizedPath }
        if persistenceEnabled {
            defaults.set(recentRepositoryPaths, forKey: recentRepositoriesKey)
        }
    }

    private func recordRecentRepository(path: String) {
        var paths = recentRepositoryPaths.filter { $0 != path }
        paths.insert(path, at: 0)
        recentRepositoryPaths = Array(paths.prefix(recentRepositoriesLimit))
        if persistenceEnabled {
            defaults.set(recentRepositoryPaths, forKey: recentRepositoriesKey)
        }
    }

    private func observeRepository(_ tab: RepositoryTab) {
        tab.restorationDidChange = { [weak self] in
            self?.scheduleWorkspacePersistence()
        }
        tab.modelDidInitialize = { [weak self, weak tab] model in
            guard let self, let tab else { return }
            self.observeRepositoryModel(model, for: tab)
        }
        if let model = tab.loadedModel {
            observeRepositoryModel(model, for: tab)
        }
    }

    private func observeRepositoryModel(_ model: RepositoryModel, for tab: RepositoryTab) {
        repositorySubscriptions[tab.id] = model.$repositoryURL
            .dropFirst()
            .sink { [weak self, weak tab] repositoryURL in
                let path = repositoryURL?.standardizedFileURL.path
                tab?.repositoryPath = path
                tab?.objectWillChange.send()
                if let path {
                    self?.recordRecentRepository(path: path)
                }
                self?.persistTabs()
            }
    }

    private func persistTabs() {
        guard persistenceEnabled else { return }
        let paths = tabs.compactMap(\.repositoryPath)
        defaults.set(paths, forKey: openRepositoriesKey)

        if let activePath = activeTab.repositoryPath {
            defaults.set(activePath, forKey: activeRepositoryKey)
            defaults.set(activePath, forKey: legacyRepositoryKey)
        } else {
            defaults.removeObject(forKey: activeRepositoryKey)
            if paths.isEmpty {
                defaults.removeObject(forKey: legacyRepositoryKey)
            }
        }
        scheduleWorkspacePersistence()
    }

    func prepareForTermination() {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        persistWorkspaceImmediately()
    }

    private func scheduleWorkspacePersistence() {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistWorkspaceImmediately()
        }
    }

    private func persistWorkspaceImmediately() {
        guard persistenceEnabled else { return }
        let savedTabs = tabs.map {
            RestoredRepositoryTab(
                id: $0.id,
                repositoryPath: $0.repositoryPath,
                state: $0.restorationState
            )
        }
        let workspace = RestoredWorkspace(
            activeTabID: activeTabID,
            tabs: savedTabs
        )
        if let data = try? JSONEncoder().encode(workspace) {
            defaults.set(data, forKey: restoredWorkspaceKey)
        }
    }
}

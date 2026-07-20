import AppKit
import Foundation
import QuartzCore

struct KvistRuntimeMetricSnapshot: Equatable {
    let gitCommandsByRepository: [String: Int]
    let activeGitProcessCount: Int
    let activeWatcherCount: Int
}

enum KvistRuntimeMetrics {
    private static let lock = NSLock()
    private static let enabled = {
        let environment = ProcessInfo.processInfo.environment
        return environment["KVIST_PERFORMANCE_MODE"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
    }()
    private static var gitCommandsByRepository: [String: Int] = [:]
    private static var activeGitProcesses: Set<Int32> = []
    private static var activeWatchers = 0

    static func reset() {
        guard enabled else { return }
        lock.lock()
        gitCommandsByRepository = [:]
        activeGitProcesses = []
        activeWatchers = 0
        lock.unlock()
    }

    static func gitProcessStarted(repositoryURL: URL, processID: Int32) {
        guard enabled else { return }
        let path = repositoryURL.standardizedFileURL.path
        lock.lock()
        gitCommandsByRepository[path, default: 0] += 1
        activeGitProcesses.insert(processID)
        lock.unlock()
    }

    static func gitProcessFinished(processID: Int32) {
        guard enabled else { return }
        lock.lock()
        activeGitProcesses.remove(processID)
        lock.unlock()
    }

    static func watcherStarted(path: String) {
        guard enabled else { return }
        lock.lock()
        activeWatchers += 1
        lock.unlock()
    }

    static func watcherStopped() {
        guard enabled else { return }
        lock.lock()
        activeWatchers = max(0, activeWatchers - 1)
        lock.unlock()
    }

    static func snapshot() -> KvistRuntimeMetricSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return KvistRuntimeMetricSnapshot(
            gitCommandsByRepository: gitCommandsByRepository,
            activeGitProcessCount: activeGitProcesses.count,
            activeWatcherCount: activeWatchers
        )
    }
}

struct RepositoryRefreshMetricCounts: Equatable {
    let workingTreeSnapshots: Int
    let fullSnapshots: Int
}

enum RepositoryRefreshMetrics {
    private static let lock = NSLock()
    private static var workingTreeSnapshots = 0
    private static var fullSnapshots = 0

    static func reset() {
        lock.lock()
        workingTreeSnapshots = 0
        fullSnapshots = 0
        lock.unlock()
    }

    static func recordWorkingTreeSnapshot() {
        lock.lock()
        workingTreeSnapshots += 1
        lock.unlock()
    }

    static func recordFullSnapshot() {
        lock.lock()
        fullSnapshots += 1
        lock.unlock()
    }

    static func counts() -> RepositoryRefreshMetricCounts {
        lock.lock()
        defer { lock.unlock() }
        return RepositoryRefreshMetricCounts(
            workingTreeSnapshots: workingTreeSnapshots,
            fullSnapshots: fullSnapshots
        )
    }
}

enum KvistPerformanceMode: String {
    case launch
    case idle
    case git
    case refresh
    case tabs
    case interaction
    case history
}

struct KvistPerformanceConfiguration {
    let mode: KvistPerformanceMode
    let repositoryURL: URL
    let outputDirectory: URL
    let gitSampleCount: Int
    let externalRefreshSampleCount: Int
    let eventStormTrialCount: Int
    let tabRepositoryURLs: [URL]

    var opensRepository: Bool {
        mode == .launch || mode == .idle || mode == .refresh || mode == .tabs
            || mode == .interaction || mode == .history
    }
}

struct KvistPerformanceTimestamp: Codable {
    let uptimeNanoseconds: UInt64
    let repositoryPath: String?
}

struct KvistGitPerformanceResult: Codable {
    let repositoryPath: String
    let sampleCount: Int
    let workingTreeRefreshMilliseconds: [Double]
    let initialRepositoryLoadingMilliseconds: [Double]
}

struct KvistExternalRefreshPerformanceResult: Codable {
    let repositoryPath: String
    let sampleCount: Int
    let eventStormTrialCount: Int
    let eventStormFileCount: Int
    let externalEditToPublicationMilliseconds: [Double]
    let eventStormSettleMilliseconds: [Double]
    let eventStormWriteMilliseconds: [Double]
    let sampleWorkingTreeSnapshotCounts: [Int]
    let sampleFullSnapshotCounts: [Int]
    let eventStormWorkingTreeSnapshotCounts: [Int]
    let eventStormFullSnapshotCounts: [Int]
}

struct KvistTabRestorationPerformanceResult: Codable {
    let restoredTabCount: Int
    let loadedRepositoryCount: Int
    let inactiveGitCommandCount: Int
    let inactiveWatcherCount: Int
}

struct KvistTabPhasePerformanceResult: Codable {
    let loadedRepositoryCount: Int
    let activeWatcherCount: Int
    let activeGitProcessCount: Int
    let outstandingRepositoryTaskCount: Int
}

struct KvistTabLifecyclePerformanceResult: Codable {
    let restoredTabCount: Int
    let initiallyLoadedRepositoryCount: Int
    let inactiveGitCommandCountBeforeSelection: Int
    let inactiveWatcherCountBeforeSelection: Int
    let initialQuiescentWatcherCount: Int
    let unopenedSwitchMilliseconds: [Double]
    let loadedSwitchMilliseconds: [Double]
    let rapidCycleCount: Int
    let rapidCycleWatcherCount: Int
    let orphanGitProcessCount: Int
    let orphanRepositoryTaskCount: Int
    let maximumMainThreadStallMilliseconds: Double
    let returnedToOriginalTab: Bool
}

enum KvistPerformanceInstrumentation {
    private static let lock = NSLock()
    private static var recordedInitialFrame = false
    private static var recordedRepositoryLoad = false
    private static var startedExternalRefreshMeasurements = false
    private static var startedTabMeasurements = false
    private static var tabRestorationResult: KvistTabRestorationPerformanceResult?

    static let configuration: KvistPerformanceConfiguration? = {
        let environment = ProcessInfo.processInfo.environment
        guard let rawMode = environment["KVIST_PERFORMANCE_MODE"],
              let mode = KvistPerformanceMode(rawValue: rawMode),
              let repositoryPath = environment["KVIST_PERFORMANCE_REPOSITORY"],
              let outputPath = environment["KVIST_PERFORMANCE_OUTPUT"] else {
            return nil
        }
        let samples = Int(environment["KVIST_PERFORMANCE_GIT_SAMPLES"] ?? "") ?? 30
        let refreshSamples = Int(
            environment["KVIST_PERFORMANCE_REFRESH_SAMPLES"] ?? ""
        ) ?? 30
        let stormTrials = Int(
            environment["KVIST_PERFORMANCE_STORM_TRIALS"] ?? ""
        ) ?? 10
        let tabRepositoryURLs = environment["KVIST_PERFORMANCE_TAB_REPOSITORIES"]
            .map { value in
                value.split(separator: "\n").map {
                    URL(fileURLWithPath: String($0), isDirectory: true)
                }
            }
            ?? [URL(fileURLWithPath: repositoryPath, isDirectory: true)]
        return KvistPerformanceConfiguration(
            mode: mode,
            repositoryURL: URL(fileURLWithPath: repositoryPath, isDirectory: true),
            outputDirectory: URL(fileURLWithPath: outputPath, isDirectory: true),
            gitSampleCount: max(1, samples),
            externalRefreshSampleCount: max(1, refreshSamples),
            eventStormTrialCount: max(1, stormTrials),
            tabRepositoryURLs: tabRepositoryURLs
        )
    }()

    @MainActor
    static func recordTabsBeforeInitialSelection(_ tabsModel: WorkspaceTabsModel) {
        guard let configuration, configuration.mode == .tabs else { return }
        let metrics = KvistRuntimeMetrics.snapshot()
        let inactivePaths = Set(configuration.tabRepositoryURLs.dropFirst().map {
            $0.standardizedFileURL.path
        })
        let result = KvistTabRestorationPerformanceResult(
            restoredTabCount: tabsModel.tabs.count,
            loadedRepositoryCount: tabsModel.tabs.count {
                $0.loadedModel?.repositoryURL != nil
                    || $0.loadedModel?.repositoryInitializationURL != nil
            },
            inactiveGitCommandCount: metrics.gitCommandsByRepository.reduce(into: 0) {
                if inactivePaths.contains($1.key) { $0 += $1.value }
            },
            inactiveWatcherCount: tabsModel.activeRepositoryWatcherCount
        )
        tabRestorationResult = result
        write(result, named: "tabs-restored.json", configuration: configuration)
    }

    @MainActor
    static func runTabMeasurementsIfRequested(tabsModel: WorkspaceTabsModel) {
        guard let configuration, configuration.mode == .tabs else { return }
        lock.lock()
        guard !startedTabMeasurements else {
            lock.unlock()
            return
        }
        startedTabMeasurements = true
        lock.unlock()

        Task {
            do {
                let result = try await measureTabs(
                    tabsModel: tabsModel,
                    configuration: configuration
                )
                try writeThrowing(result, named: "tabs-result.json", configuration: configuration)
            } catch {
                let message = (error as NSError).localizedDescription
                try? message.write(
                    to: configuration.outputDirectory.appendingPathComponent("error.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                NSApp.terminate(nil)
            }
        }
    }

    static func recordInitialFrame() {
        guard let configuration, configuration.opensRepository else { return }
        lock.lock()
        guard !recordedInitialFrame else {
            lock.unlock()
            return
        }
        recordedInitialFrame = true
        lock.unlock()

        write(
            KvistPerformanceTimestamp(
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                repositoryPath: nil
            ),
            named: "initial-frame.json",
            configuration: configuration
        )
    }

    @MainActor
    static func recordRepositoryLoaded(
        rootURL: URL,
        model: RepositoryModel? = nil
    ) {
        guard let configuration, configuration.opensRepository else { return }
        guard rootURL.standardizedFileURL == configuration.repositoryURL.standardizedFileURL else {
            return
        }
        lock.lock()
        guard !recordedRepositoryLoad else {
            lock.unlock()
            return
        }
        recordedRepositoryLoad = true
        lock.unlock()

        write(
            KvistPerformanceTimestamp(
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                repositoryPath: rootURL.path
            ),
            named: "repository-loaded.json",
            configuration: configuration
        )

        if configuration.mode == .refresh, let model {
            runExternalRefreshMeasurements(
                model: model,
                configuration: configuration
            )
        }
    }

    @MainActor
    static func runGitMeasurementsIfRequested() {
        guard let configuration, configuration.mode == .git else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let result = try measureGitOperations(configuration: configuration)
                try writeThrowing(
                    result,
                    named: "git-operations.json",
                    configuration: configuration
                )
                await MainActor.run { NSApp.terminate(nil) }
            } catch {
                let message = (error as NSError).localizedDescription
                try? message.write(
                    to: configuration.outputDirectory.appendingPathComponent("error.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                await MainActor.run { NSApp.terminate(nil) }
            }
        }
    }

    @MainActor
    private static func runExternalRefreshMeasurements(
        model: RepositoryModel,
        configuration: KvistPerformanceConfiguration
    ) {
        lock.lock()
        guard !startedExternalRefreshMeasurements else {
            lock.unlock()
            return
        }
        startedExternalRefreshMeasurements = true
        lock.unlock()

        Task {
            do {
                let result = try await measureExternalRefreshes(
                    model: model,
                    configuration: configuration
                )
                try writeThrowing(
                    result,
                    named: "external-refresh.json",
                    configuration: configuration
                )
                NSApp.terminate(nil)
            } catch {
                let message = (error as NSError).localizedDescription
                try? message.write(
                    to: configuration.outputDirectory.appendingPathComponent("error.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                NSApp.terminate(nil)
            }
        }
    }

    @MainActor
    private static func measureTabs(
        tabsModel: WorkspaceTabsModel,
        configuration: KvistPerformanceConfiguration
    ) async throws -> KvistTabLifecyclePerformanceResult {
        guard configuration.tabRepositoryURLs.count == 20,
              tabsModel.tabs.count == configuration.tabRepositoryURLs.count,
              let restoration = tabRestorationResult else {
            throw performanceError("Tab benchmark requires exactly 20 restored repositories")
        }
        let originalTabID = tabsModel.activeTabID
        let originalURL = configuration.tabRepositoryURLs[0].standardizedFileURL
        try await waitForModel(timeoutSeconds: 5) {
            tabsModel.activeModel.repositoryURL?.standardizedFileURL == originalURL
                && !tabsModel.activeModel.isBusy
        }
        try await waitForTabQuiescence(tabsModel, timeoutSeconds: 5)
        let initialPhase = tabPhase(tabsModel)
        write(initialPhase, named: "tabs-initially-ready.json", configuration: configuration)
        try await waitForContinue(named: "continue-after-initial", configuration: configuration)

        var unopenedSwitches: [Double] = []
        for (tab, expectedURL) in zip(
            tabsModel.tabs.dropFirst(),
            configuration.tabRepositoryURLs.dropFirst()
        ) {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            tabsModel.select(tab.id)
            let standardizedExpectedURL = expectedURL.standardizedFileURL
            try await waitForModel(timeoutSeconds: 5) {
                tab.model.repositoryURL?.standardizedFileURL == standardizedExpectedURL
                    && !tab.model.isBusy
            }
            renderApplication()
            unopenedSwitches.append(milliseconds(since: startedAt))
        }
        try await waitForTabQuiescence(tabsModel, timeoutSeconds: 5)
        write(tabPhase(tabsModel), named: "tabs-all-visited.json", configuration: configuration)
        try await waitForContinue(named: "continue-after-all-visited", configuration: configuration)

        var loadedSwitches: [Double] = []
        loadedSwitches.reserveCapacity(100)
        for sample in 0..<100 {
            let tab = tabsModel.tabs[(sample + 1) % tabsModel.tabs.count]
            let startedAt = DispatchTime.now().uptimeNanoseconds
            tabsModel.select(tab.id)
            renderApplication()
            loadedSwitches.append(milliseconds(since: startedAt))
            await Task.yield()
        }
        tabsModel.select(originalTabID)
        renderApplication()
        try await waitForTabQuiescence(tabsModel, timeoutSeconds: 5)
        write(tabPhase(tabsModel), named: "tabs-before-rapid-cycle.json", configuration: configuration)
        try await waitForContinue(named: "continue-before-rapid-cycle", configuration: configuration)

        let rapidCycleCount = 100
        var maximumStall = loadedSwitches.max() ?? 0
        for _ in 0..<rapidCycleCount {
            for tab in tabsModel.tabs where tab.id != tabsModel.activeTabID {
                let startedAt = DispatchTime.now().uptimeNanoseconds
                tabsModel.select(tab.id)
                maximumStall = max(maximumStall, milliseconds(since: startedAt))
                await nextMainRunLoopTurn()
            }
        }
        tabsModel.select(originalTabID)
        renderApplication()
        await nextMainRunLoopTurn()
        try await waitForTabQuiescence(tabsModel, timeoutSeconds: 5)
        let finalMetrics = KvistRuntimeMetrics.snapshot()

        return KvistTabLifecyclePerformanceResult(
            restoredTabCount: restoration.restoredTabCount,
            initiallyLoadedRepositoryCount: initialPhase.loadedRepositoryCount,
            inactiveGitCommandCountBeforeSelection: restoration.inactiveGitCommandCount,
            inactiveWatcherCountBeforeSelection: restoration.inactiveWatcherCount,
            initialQuiescentWatcherCount: initialPhase.activeWatcherCount,
            unopenedSwitchMilliseconds: unopenedSwitches,
            loadedSwitchMilliseconds: loadedSwitches,
            rapidCycleCount: rapidCycleCount,
            rapidCycleWatcherCount: tabsModel.activeRepositoryWatcherCount,
            orphanGitProcessCount: finalMetrics.activeGitProcessCount,
            orphanRepositoryTaskCount: tabsModel.outstandingRepositoryTaskCount,
            maximumMainThreadStallMilliseconds: maximumStall,
            returnedToOriginalTab: tabsModel.activeTabID == originalTabID
        )
    }

    @MainActor
    private static func waitForTabQuiescence(
        _ tabsModel: WorkspaceTabsModel,
        timeoutSeconds: Double
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var quietSince: UInt64?
        while Date() < deadline {
            let metrics = KvistRuntimeMetrics.snapshot()
            let isQuiet = tabsModel.activeRepositoryWatcherCount == 1
                && tabsModel.outstandingRepositoryTaskCount == 0
                && metrics.activeGitProcessCount == 0
                && metrics.activeWatcherCount == 1
            if isQuiet {
                let now = DispatchTime.now().uptimeNanoseconds
                if let quietSince, now - quietSince >= 100_000_000 { return }
                if quietSince == nil { quietSince = now }
            } else {
                quietSince = nil
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw performanceError("Timed out waiting for tab workload to quiesce")
    }

    @MainActor
    private static func tabPhase(_ tabsModel: WorkspaceTabsModel) -> KvistTabPhasePerformanceResult {
        let metrics = KvistRuntimeMetrics.snapshot()
        return KvistTabPhasePerformanceResult(
            loadedRepositoryCount: tabsModel.tabs.count {
                $0.loadedModel?.repositoryURL != nil
            },
            activeWatcherCount: tabsModel.activeRepositoryWatcherCount,
            activeGitProcessCount: metrics.activeGitProcessCount,
            outstandingRepositoryTaskCount: tabsModel.outstandingRepositoryTaskCount
        )
    }

    @MainActor
    private static func waitForContinue(
        named name: String,
        configuration: KvistPerformanceConfiguration
    ) async throws {
        let url = configuration.outputDirectory.appendingPathComponent(name)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw performanceError("Timed out waiting for benchmark handoff \(name)")
        }
    }

    @MainActor
    private static func renderApplication() {
        for window in NSApp.windows where window.isVisible {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        CATransaction.flush()
    }

    @MainActor
    private static func nextMainRunLoopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) {
                continuation.resume()
            }
        }
    }

    @MainActor
    private static func measureExternalRefreshes(
        model: RepositoryModel,
        configuration: KvistPerformanceConfiguration
    ) async throws -> KvistExternalRefreshPerformanceResult {
        let repositoryURL = try GitClient.discoverRoot(from: configuration.repositoryURL)
        guard model.repositoryURL?.standardizedFileURL == repositoryURL.standardizedFileURL else {
            throw performanceError("Kvist loaded the wrong repository for refresh measurement")
        }

        let marker = UUID().uuidString.lowercased()
        let samplePath = "kvist-external-refresh-\(marker)"
        let sampleURL = repositoryURL.appendingPathComponent(samplePath)
        var cleanupURLs = [sampleURL]
        defer {
            for url in cleanupURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        var latencies: [Double] = []
        var sampleWorkingTreeCounts: [Int] = []
        var sampleFullCounts: [Int] = []
        latencies.reserveCapacity(configuration.externalRefreshSampleCount)

        for sample in 0..<configuration.externalRefreshSampleCount {
            RepositoryRefreshMetrics.reset()
            let startedAt = try await Task.detached(priority: .userInitiated) {
                let startedAt = DispatchTime.now().uptimeNanoseconds
                try Data("sample \(sample)\n".utf8).write(to: sampleURL, options: .atomic)
                return startedAt
            }.value
            try await waitForModel(timeoutSeconds: 3) {
                model.unstaged.contains { $0.path == samplePath }
            }
            latencies.append(milliseconds(since: startedAt))
            let counts = RepositoryRefreshMetrics.counts()
            sampleWorkingTreeCounts.append(counts.workingTreeSnapshots)
            sampleFullCounts.append(counts.fullSnapshots)
            guard counts.workingTreeSnapshots == 1, counts.fullSnapshots == 0 else {
                throw performanceError(
                    "External edit triggered \(counts.workingTreeSnapshots) working-tree " +
                    "and \(counts.fullSnapshots) full snapshots"
                )
            }

            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.removeItem(at: sampleURL)
            }.value
            try await waitForModel(timeoutSeconds: 3) {
                !model.unstaged.contains { $0.path == samplePath }
            }
        }

        let stormFileCount = 100
        var stormLatencies: [Double] = []
        var stormWriteDurations: [Double] = []
        var stormWorkingTreeCounts: [Int] = []
        var stormFullCounts: [Int] = []
        for trial in 0..<configuration.eventStormTrialCount {
            let directoryPath = "kvist-event-storm-\(marker)-\(trial)"
            let directoryURL = repositoryURL.appendingPathComponent(
                directoryPath,
                isDirectory: true
            )
            let publishedPath = directoryPath + "/"
            cleanupURLs.append(directoryURL)
            RepositoryRefreshMetrics.reset()
            let timing = try await Task.detached(priority: .userInitiated) {
                let startedAt = DispatchTime.now().uptimeNanoseconds
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: false
                )
                for index in 0..<stormFileCount {
                    let url = directoryURL.appendingPathComponent("file-\(index)")
                    try Data("storm \(trial) \(index)\n".utf8).write(to: url)
                }
                let finishedAt = DispatchTime.now().uptimeNanoseconds
                return (startedAt, finishedAt)
            }.value
            let writeMilliseconds = Double(timing.1 - timing.0) / 1_000_000
            guard writeMilliseconds <= 100 else {
                throw performanceError(
                    "Event storm writes took \(String(format: "%.3f", writeMilliseconds)) ms"
                )
            }
            try await waitForModel(timeoutSeconds: 3) {
                model.unstaged.contains { $0.path == publishedPath }
            }
            stormLatencies.append(milliseconds(since: timing.0))
            stormWriteDurations.append(writeMilliseconds)
            let counts = RepositoryRefreshMetrics.counts()
            stormWorkingTreeCounts.append(counts.workingTreeSnapshots)
            stormFullCounts.append(counts.fullSnapshots)
            guard counts.workingTreeSnapshots == 1, counts.fullSnapshots == 0 else {
                throw performanceError(
                    "Event storm triggered \(counts.workingTreeSnapshots) working-tree " +
                    "and \(counts.fullSnapshots) full snapshots"
                )
            }

            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.removeItem(at: directoryURL)
            }.value
            try await waitForModel(timeoutSeconds: 3) {
                !model.unstaged.contains { $0.path == publishedPath }
            }
        }

        return KvistExternalRefreshPerformanceResult(
            repositoryPath: repositoryURL.path,
            sampleCount: configuration.externalRefreshSampleCount,
            eventStormTrialCount: configuration.eventStormTrialCount,
            eventStormFileCount: stormFileCount,
            externalEditToPublicationMilliseconds: latencies,
            eventStormSettleMilliseconds: stormLatencies,
            eventStormWriteMilliseconds: stormWriteDurations,
            sampleWorkingTreeSnapshotCounts: sampleWorkingTreeCounts,
            sampleFullSnapshotCounts: sampleFullCounts,
            eventStormWorkingTreeSnapshotCounts: stormWorkingTreeCounts,
            eventStormFullSnapshotCounts: stormFullCounts
        )
    }

    @MainActor
    private static func waitForModel(
        timeoutSeconds: Double,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        guard condition() else {
            throw performanceError("Timed out waiting for RepositoryModel publication")
        }
    }

    private static func performanceError(_ message: String) -> NSError {
        NSError(
            domain: "KvistPerformanceInstrumentation",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func measureGitOperations(
        configuration: KvistPerformanceConfiguration
    ) throws -> KvistGitPerformanceResult {
        let repositoryURL = try GitClient.discoverRoot(from: configuration.repositoryURL)
        let client = GitClient(repositoryURL: repositoryURL)

        // Warm both paths before recording. This removes one-time dynamic-linker
        // and Git executable startup costs while retaining normal filesystem caches.
        _ = try client.workingTreeSnapshot()
        _ = try client.snapshot()
        _ = try client.repositoryWatchPaths()

        var workingTree: [Double] = []
        var initialLoading: [Double] = []
        workingTree.reserveCapacity(configuration.gitSampleCount)
        initialLoading.reserveCapacity(configuration.gitSampleCount)

        for _ in 0..<configuration.gitSampleCount {
            let refreshStart = DispatchTime.now().uptimeNanoseconds
            _ = try client.workingTreeSnapshot()
            workingTree.append(milliseconds(since: refreshStart))

            let loadingStart = DispatchTime.now().uptimeNanoseconds
            let root = try GitClient.discoverRoot(from: configuration.repositoryURL)
            let initialClient = GitClient(repositoryURL: root)
            _ = try initialClient.snapshot()
            _ = try initialClient.repositoryWatchPaths()
            initialLoading.append(milliseconds(since: loadingStart))
        }

        return KvistGitPerformanceResult(
            repositoryPath: repositoryURL.path,
            sampleCount: configuration.gitSampleCount,
            workingTreeRefreshMilliseconds: workingTree,
            initialRepositoryLoadingMilliseconds: initialLoading
        )
    }

    private static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func write<Value: Encodable>(
        _ value: Value,
        named name: String,
        configuration: KvistPerformanceConfiguration
    ) {
        try? writeThrowing(value, named: name, configuration: configuration)
    }

    private static func writeThrowing<Value: Encodable>(
        _ value: Value,
        named name: String,
        configuration: KvistPerformanceConfiguration
    ) throws {
        try FileManager.default.createDirectory(
            at: configuration.outputDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(
            to: configuration.outputDirectory.appendingPathComponent(name),
            options: .atomic
        )
    }
}

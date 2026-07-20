import Foundation

public struct AppArtifactResult: Codable, Equatable {
    public let bundleBytes: UInt64
    public let compressedBytes: UInt64

    public init(bundleBytes: UInt64, compressedBytes: UInt64) {
        self.bundleBytes = bundleBytes
        self.compressedBytes = compressedBytes
    }
}

public struct RepositoryResult: Codable, Equatable {
    public let name: String
    public let path: String
    public let launchToInitialFrameMilliseconds: [Double]
    public let startupPeakPhysicalFootprintMiB: [Double]
    public let settledPhysicalFootprintMiB: [Double]
    public let idleCPUPercent: [Double]
    public let idleWakeupsPerSecond: [Double]
    public let workingTreeRefreshMilliseconds: [Double]
    public let initialRepositoryLoadingMilliseconds: [Double]
    public let externalEditToPublicationMilliseconds: [Double]
    public let eventStormSettleMilliseconds: [Double]
    public let eventStormWriteMilliseconds: [Double]
    public let externalEditWorkingTreeSnapshotCounts: [Int]
    public let externalEditFullSnapshotCounts: [Int]
    public let eventStormWorkingTreeSnapshotCounts: [Int]
    public let eventStormFullSnapshotCounts: [Int]

    public init(
        name: String,
        path: String,
        launchToInitialFrameMilliseconds: [Double],
        startupPeakPhysicalFootprintMiB: [Double],
        settledPhysicalFootprintMiB: [Double],
        idleCPUPercent: [Double],
        idleWakeupsPerSecond: [Double],
        workingTreeRefreshMilliseconds: [Double],
        initialRepositoryLoadingMilliseconds: [Double],
        externalEditToPublicationMilliseconds: [Double],
        eventStormSettleMilliseconds: [Double],
        eventStormWriteMilliseconds: [Double],
        externalEditWorkingTreeSnapshotCounts: [Int],
        externalEditFullSnapshotCounts: [Int],
        eventStormWorkingTreeSnapshotCounts: [Int],
        eventStormFullSnapshotCounts: [Int]
    ) {
        self.name = name
        self.path = path
        self.launchToInitialFrameMilliseconds = launchToInitialFrameMilliseconds
        self.startupPeakPhysicalFootprintMiB = startupPeakPhysicalFootprintMiB
        self.settledPhysicalFootprintMiB = settledPhysicalFootprintMiB
        self.idleCPUPercent = idleCPUPercent
        self.idleWakeupsPerSecond = idleWakeupsPerSecond
        self.workingTreeRefreshMilliseconds = workingTreeRefreshMilliseconds
        self.initialRepositoryLoadingMilliseconds = initialRepositoryLoadingMilliseconds
        self.externalEditToPublicationMilliseconds = externalEditToPublicationMilliseconds
        self.eventStormSettleMilliseconds = eventStormSettleMilliseconds
        self.eventStormWriteMilliseconds = eventStormWriteMilliseconds
        self.externalEditWorkingTreeSnapshotCounts = externalEditWorkingTreeSnapshotCounts
        self.externalEditFullSnapshotCounts = externalEditFullSnapshotCounts
        self.eventStormWorkingTreeSnapshotCounts = eventStormWorkingTreeSnapshotCounts
        self.eventStormFullSnapshotCounts = eventStormFullSnapshotCounts
    }
}

public struct TabPerformanceResult: Codable, Equatable {
    public let fixtureCount: Int
    public let initiallyLoadedRepositoryCount: Int
    public let inactiveGitCommandCountBeforeSelection: Int
    public let inactiveWatcherCountBeforeSelection: Int
    public let initialQuiescentWatcherCount: Int
    public let unopenedTabsFootprintDeltaMiB: Double
    public let unopenedSwitchMilliseconds: [Double]
    public let retainedTabsFootprintDeltaMiB: Double
    public let loadedSwitchMilliseconds: [Double]
    public let rapidCycleCount: Int
    public let rapidCycleWatcherCount: Int
    public let orphanGitProcessCount: Int
    public let orphanRepositoryTaskCount: Int
    public let rapidCycleFootprintDeltaMiB: Double
    public let maximumMainThreadStallMilliseconds: Double
    public let returnedToOriginalTab: Bool
    public let idleCPUPercent: Double
    public let idleWakeupsPerSecond: Double

    public init(
        fixtureCount: Int,
        initiallyLoadedRepositoryCount: Int,
        inactiveGitCommandCountBeforeSelection: Int,
        inactiveWatcherCountBeforeSelection: Int,
        initialQuiescentWatcherCount: Int,
        unopenedTabsFootprintDeltaMiB: Double,
        unopenedSwitchMilliseconds: [Double],
        retainedTabsFootprintDeltaMiB: Double,
        loadedSwitchMilliseconds: [Double],
        rapidCycleCount: Int,
        rapidCycleWatcherCount: Int,
        orphanGitProcessCount: Int,
        orphanRepositoryTaskCount: Int,
        rapidCycleFootprintDeltaMiB: Double,
        maximumMainThreadStallMilliseconds: Double,
        returnedToOriginalTab: Bool,
        idleCPUPercent: Double,
        idleWakeupsPerSecond: Double
    ) {
        self.fixtureCount = fixtureCount
        self.initiallyLoadedRepositoryCount = initiallyLoadedRepositoryCount
        self.inactiveGitCommandCountBeforeSelection = inactiveGitCommandCountBeforeSelection
        self.inactiveWatcherCountBeforeSelection = inactiveWatcherCountBeforeSelection
        self.initialQuiescentWatcherCount = initialQuiescentWatcherCount
        self.unopenedTabsFootprintDeltaMiB = unopenedTabsFootprintDeltaMiB
        self.unopenedSwitchMilliseconds = unopenedSwitchMilliseconds
        self.retainedTabsFootprintDeltaMiB = retainedTabsFootprintDeltaMiB
        self.loadedSwitchMilliseconds = loadedSwitchMilliseconds
        self.rapidCycleCount = rapidCycleCount
        self.rapidCycleWatcherCount = rapidCycleWatcherCount
        self.orphanGitProcessCount = orphanGitProcessCount
        self.orphanRepositoryTaskCount = orphanRepositoryTaskCount
        self.rapidCycleFootprintDeltaMiB = rapidCycleFootprintDeltaMiB
        self.maximumMainThreadStallMilliseconds = maximumMainThreadStallMilliseconds
        self.returnedToOriginalTab = returnedToOriginalTab
        self.idleCPUPercent = idleCPUPercent
        self.idleWakeupsPerSecond = idleWakeupsPerSecond
    }
}

public struct ScrollPerformanceResult: Codable, Equatable {
    public let durationSeconds: Double
    public let renderedFrameCount: Int
    public let droppedFrameCount: Int
    public let droppedFrameRatePercent: Double
    public let maximumMainThreadStallMilliseconds: Double

    public init(
        durationSeconds: Double,
        renderedFrameCount: Int,
        droppedFrameCount: Int,
        droppedFrameRatePercent: Double,
        maximumMainThreadStallMilliseconds: Double
    ) {
        self.durationSeconds = durationSeconds
        self.renderedFrameCount = renderedFrameCount
        self.droppedFrameCount = droppedFrameCount
        self.droppedFrameRatePercent = droppedFrameRatePercent
        self.maximumMainThreadStallMilliseconds = maximumMainThreadStallMilliseconds
    }
}

public struct InteractionPerformanceResult: Codable, Equatable {
    public let maximumSourceFileBytes: Int
    public let largeSourceLineCount: Int
    public let longestSourceLineCharacters: Int
    public let largeDiffChangedLineCount: Int
    public let maximumSourceOpenMilliseconds: [Double]
    public let largeLineOpenMilliseconds: [Double]
    public let largeDiffOpenMilliseconds: [Double]
    public let typingInputToDisplayMilliseconds: [Double]
    public let editorScroll: ScrollPerformanceResult
    public let diffScroll: ScrollPerformanceResult
    public let lineJumpMilliseconds: [Double]
    public let lifecycleCycleCount: Int
    public let lifecycleFootprintDeltaMiB: Double
    public let orphanPreviewDirectoryCount: Int
    public let orphanTaskCount: Int

    public init(
        maximumSourceFileBytes: Int,
        largeSourceLineCount: Int,
        longestSourceLineCharacters: Int,
        largeDiffChangedLineCount: Int,
        maximumSourceOpenMilliseconds: [Double],
        largeLineOpenMilliseconds: [Double],
        largeDiffOpenMilliseconds: [Double],
        typingInputToDisplayMilliseconds: [Double],
        editorScroll: ScrollPerformanceResult,
        diffScroll: ScrollPerformanceResult,
        lineJumpMilliseconds: [Double],
        lifecycleCycleCount: Int,
        lifecycleFootprintDeltaMiB: Double,
        orphanPreviewDirectoryCount: Int,
        orphanTaskCount: Int
    ) {
        self.maximumSourceFileBytes = maximumSourceFileBytes
        self.largeSourceLineCount = largeSourceLineCount
        self.longestSourceLineCharacters = longestSourceLineCharacters
        self.largeDiffChangedLineCount = largeDiffChangedLineCount
        self.maximumSourceOpenMilliseconds = maximumSourceOpenMilliseconds
        self.largeLineOpenMilliseconds = largeLineOpenMilliseconds
        self.largeDiffOpenMilliseconds = largeDiffOpenMilliseconds
        self.typingInputToDisplayMilliseconds = typingInputToDisplayMilliseconds
        self.editorScroll = editorScroll
        self.diffScroll = diffScroll
        self.lineJumpMilliseconds = lineJumpMilliseconds
        self.lifecycleCycleCount = lifecycleCycleCount
        self.lifecycleFootprintDeltaMiB = lifecycleFootprintDeltaMiB
        self.orphanPreviewDirectoryCount = orphanPreviewDirectoryCount
        self.orphanTaskCount = orphanTaskCount
    }
}

public struct InteractionBenchmarkReport: Codable, Equatable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let gitCommit: String
    public let gitTreeState: String
    public let operatingSystem: String
    public let app: AppArtifactResult
    public let interactions: InteractionPerformanceResult
    public let guardrails: [GuardrailResult]

    public init(
        schemaVersion: Int,
        generatedAt: String,
        gitCommit: String,
        gitTreeState: String,
        operatingSystem: String,
        app: AppArtifactResult,
        interactions: InteractionPerformanceResult,
        guardrails: [GuardrailResult]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.gitCommit = gitCommit
        self.gitTreeState = gitTreeState
        self.operatingSystem = operatingSystem
        self.app = app
        self.interactions = interactions
        self.guardrails = guardrails
    }
}

public enum GuardrailComparison: String, Codable, Equatable {
    case atMost
    case atLeast
    case exactly

    public var symbol: String {
        switch self {
        case .atMost: return "≤"
        case .atLeast: return "≥"
        case .exactly: return "="
        }
    }

    fileprivate func passes(measured: Double, limit: Double) -> Bool {
        switch self {
        case .atMost: return measured <= limit
        case .atLeast: return measured >= limit
        case .exactly: return measured == limit
        }
    }
}

public struct GuardrailResult: Codable, Equatable {
    public let name: String
    public let repository: String?
    public let statistic: String
    public let measured: Double
    public let limit: Double
    public let unit: String
    public let comparison: GuardrailComparison
    public let passed: Bool

    public init(
        name: String,
        repository: String?,
        statistic: String,
        measured: Double,
        limit: Double,
        unit: String,
        comparison: GuardrailComparison
    ) {
        self.name = name
        self.repository = repository
        self.statistic = statistic
        self.measured = measured
        self.limit = limit
        self.unit = unit
        self.comparison = comparison
        self.passed = comparison.passes(measured: measured, limit: limit)
    }

    public var failureDescription: String {
        let scope = repository.map { "[\($0)] " } ?? ""
        return "\(scope)\(name) \(statistic): \(format(measured)) \(unit) " +
            "(required \(comparison.symbol) \(format(limit)) \(unit))"
    }
}

public enum BenchmarkLimits {
    public static let bundleMiB = 2.75
    public static let compressedMiB = 1.15
    public static let launchMedianMilliseconds = 250.0
    public static let launchP95Milliseconds = 275.0
    public static let startupPeakMiB = 35.0
    public static let settledMiB = 50.0
    public static let idleCPUPercent = 0.01
    public static let idleWakeupsPerSecond = 1.2
    public static let directRefreshMedianMilliseconds = 35.0
    public static let directRefreshP95Milliseconds = 50.0
    public static let initialLoadingMedianMilliseconds = 90.0
    public static let initialLoadingP95Milliseconds = 130.0
    public static let externalRefreshMedianMilliseconds = 180.0
    public static let externalRefreshP95Milliseconds = 200.0
    public static let eventStormP95Milliseconds = 220.0
    public static let eventStormWriteMilliseconds = 100.0
    public static let unopenedTabsFootprintDeltaMiB = 10.0
    public static let unopenedSwitchMedianMilliseconds = 200.0
    public static let unopenedSwitchP95Milliseconds = 300.0
    public static let loadedSwitchMedianMilliseconds = 30.0
    public static let loadedSwitchP95Milliseconds = 50.0
    public static let rapidCycleFootprintDeltaMiB = 3.0
    public static let mainThreadStallMilliseconds = 50.0
    public static let retainedTabsFootprintDeltaMiB = 30.0
}

public enum BenchmarkMinimums {
    public static let launchSamples = 20
    public static let gitSamples = 30
    public static let externalRefreshSamples = 30
    public static let eventStormTrials = 10
    public static let eventStormFiles = 100
    public static let idleSamples = 5
    public static let idleDurationSeconds = 10.0

    public static func violation(
        launchSamples: Int,
        gitSamples: Int,
        externalRefreshSamples: Int,
        eventStormTrials: Int,
        idleSamples: Int,
        idleDurationSeconds: Double
    ) -> String? {
        if launchSamples < self.launchSamples {
            return "--launch-samples must be at least \(self.launchSamples)"
        }
        if gitSamples < self.gitSamples {
            return "--git-samples must be at least \(self.gitSamples)"
        }
        if externalRefreshSamples < self.externalRefreshSamples {
            return "--external-refresh-samples must be at least \(self.externalRefreshSamples)"
        }
        if eventStormTrials < self.eventStormTrials {
            return "--event-storm-trials must be at least \(self.eventStormTrials)"
        }
        if idleSamples < self.idleSamples {
            return "--idle-samples must be at least \(self.idleSamples)"
        }
        if idleDurationSeconds < self.idleDurationSeconds {
            return "--idle-duration must be at least \(format(self.idleDurationSeconds)) seconds"
        }
        return nil
    }
}

public enum BenchmarkGuardrails {
    // Keeping every release guardrail together makes omissions visible in review and tests.
    // swiftlint:disable:next function_body_length
    public static func evaluate(
        app: AppArtifactResult,
        repositories: [RepositoryResult]
    ) -> [GuardrailResult] {
        var results: [GuardrailResult] = []

        func atMost(
            _ name: String,
            repository: String? = nil,
            statistic: String,
            measured: Double,
            limit: Double,
            unit: String
        ) {
            results.append(
                GuardrailResult(
                    name: name,
                    repository: repository,
                    statistic: statistic,
                    measured: measured,
                    limit: limit,
                    unit: unit,
                    comparison: .atMost
                )
            )
        }

        func exactly(
            _ name: String,
            repository: String,
            measured: Double,
            limit: Double
        ) {
            results.append(
                GuardrailResult(
                    name: name,
                    repository: repository,
                    statistic: "every burst",
                    measured: measured,
                    limit: limit,
                    unit: "count",
                    comparison: .exactly
                )
            )
        }

        atMost(
            "App bundle",
            statistic: "value",
            measured: mebibytes(app.bundleBytes),
            limit: BenchmarkLimits.bundleMiB,
            unit: "MiB"
        )
        atMost(
            "Compressed app",
            statistic: "value",
            measured: mebibytes(app.compressedBytes),
            limit: BenchmarkLimits.compressedMiB,
            unit: "MiB"
        )

        for repository in repositories {
            let name = repository.name
            atMost(
                "Launch",
                repository: name,
                statistic: "median",
                measured: median(repository.launchToInitialFrameMilliseconds),
                limit: BenchmarkLimits.launchMedianMilliseconds,
                unit: "ms"
            )
            atMost(
                "Launch",
                repository: name,
                statistic: "p95",
                measured: percentile95(repository.launchToInitialFrameMilliseconds),
                limit: BenchmarkLimits.launchP95Milliseconds,
                unit: "ms"
            )
            atMost(
                "Startup peak footprint",
                repository: name,
                statistic: "maximum",
                measured: repository.startupPeakPhysicalFootprintMiB.max()
                    ?? .greatestFiniteMagnitude,
                limit: BenchmarkLimits.startupPeakMiB,
                unit: "MiB"
            )
            atMost(
                "Settled footprint",
                repository: name,
                statistic: "maximum",
                measured: repository.settledPhysicalFootprintMiB.max()
                    ?? .greatestFiniteMagnitude,
                limit: BenchmarkLimits.settledMiB,
                unit: "MiB"
            )
            atMost(
                "Idle CPU",
                repository: name,
                statistic: "maximum",
                measured: repository.idleCPUPercent.max() ?? .greatestFiniteMagnitude,
                limit: BenchmarkLimits.idleCPUPercent,
                unit: "%"
            )
            atMost(
                "Idle wakeups",
                repository: name,
                statistic: "maximum",
                measured: repository.idleWakeupsPerSecond.max() ?? .greatestFiniteMagnitude,
                limit: BenchmarkLimits.idleWakeupsPerSecond,
                unit: "/s"
            )
            atMost(
                "Working-tree refresh",
                repository: name,
                statistic: "median",
                measured: median(repository.workingTreeRefreshMilliseconds),
                limit: BenchmarkLimits.directRefreshMedianMilliseconds,
                unit: "ms"
            )
            atMost(
                "Working-tree refresh",
                repository: name,
                statistic: "p95",
                measured: percentile95(repository.workingTreeRefreshMilliseconds),
                limit: BenchmarkLimits.directRefreshP95Milliseconds,
                unit: "ms"
            )
            atMost(
                "Initial repository loading",
                repository: name,
                statistic: "median",
                measured: median(repository.initialRepositoryLoadingMilliseconds),
                limit: BenchmarkLimits.initialLoadingMedianMilliseconds,
                unit: "ms"
            )
            atMost(
                "Initial repository loading",
                repository: name,
                statistic: "p95",
                measured: percentile95(repository.initialRepositoryLoadingMilliseconds),
                limit: BenchmarkLimits.initialLoadingP95Milliseconds,
                unit: "ms"
            )
            atMost(
                "External-edit latency",
                repository: name,
                statistic: "median",
                measured: median(repository.externalEditToPublicationMilliseconds),
                limit: BenchmarkLimits.externalRefreshMedianMilliseconds,
                unit: "ms"
            )
            atMost(
                "External-edit latency",
                repository: name,
                statistic: "p95",
                measured: percentile95(repository.externalEditToPublicationMilliseconds),
                limit: BenchmarkLimits.externalRefreshP95Milliseconds,
                unit: "ms"
            )
            atMost(
                "Event-storm latency",
                repository: name,
                statistic: "p95",
                measured: percentile95(repository.eventStormSettleMilliseconds),
                limit: BenchmarkLimits.eventStormP95Milliseconds,
                unit: "ms"
            )
            atMost(
                "Event storm writes",
                repository: name,
                statistic: "maximum",
                measured: repository.eventStormWriteMilliseconds.max()
                    ?? .greatestFiniteMagnitude,
                limit: BenchmarkLimits.eventStormWriteMilliseconds,
                unit: "ms"
            )

            exactly(
                "External edit working-tree snapshots",
                repository: name,
                measured: exactValue(
                    repository.externalEditWorkingTreeSnapshotCounts,
                    expected: 1
                ),
                limit: 1
            )
            exactly(
                "External edit full snapshots",
                repository: name,
                measured: exactValue(repository.externalEditFullSnapshotCounts, expected: 0),
                limit: 0
            )
            exactly(
                "Event storm working-tree snapshots",
                repository: name,
                measured: exactValue(
                    repository.eventStormWorkingTreeSnapshotCounts,
                    expected: 1
                ),
                limit: 1
            )
            exactly(
                "Event storm full snapshots",
                repository: name,
                measured: exactValue(repository.eventStormFullSnapshotCounts, expected: 0),
                limit: 0
            )
        }
        return results
    }

    public static func failureReport(for results: [GuardrailResult]) -> String? {
        let failures = results.filter { !$0.passed }
        guard !failures.isEmpty else { return nil }
        return failures.map(\.failureDescription).joined(separator: "\n")
    }

    private static func exactValue(_ values: [Int], expected: Int) -> Double {
        guard !values.isEmpty else { return -1 }
        return Double(values.first { $0 != expected } ?? expected)
    }
}

public enum TabBenchmarkGuardrails {
    public static func evaluate(_ tabs: TabPerformanceResult) -> [GuardrailResult] {
        func result(
            _ name: String,
            statistic: String,
            measured: Double,
            limit: Double,
            unit: String,
            comparison: GuardrailComparison = .atMost
        ) -> GuardrailResult {
            GuardrailResult(
                name: name,
                repository: "20 tabs",
                statistic: statistic,
                measured: measured,
                limit: limit,
                unit: unit,
                comparison: comparison
            )
        }

        return [
            result("Temporary repository fixtures", statistic: "count", measured: Double(tabs.fixtureCount), limit: 20, unit: "count", comparison: .exactly),
            result("Initially loaded repositories", statistic: "count", measured: Double(tabs.initiallyLoadedRepositoryCount), limit: 1, unit: "count", comparison: .exactly),
            result("Inactive-tab Git commands", statistic: "before first selection", measured: Double(tabs.inactiveGitCommandCountBeforeSelection), limit: 0, unit: "count", comparison: .exactly),
            result("Inactive-tab watchers", statistic: "before first selection", measured: Double(tabs.inactiveWatcherCountBeforeSelection), limit: 0, unit: "count", comparison: .exactly),
            result("Quiescent repository watchers", statistic: "initial", measured: Double(tabs.initialQuiescentWatcherCount), limit: 1, unit: "count", comparison: .exactly),
            result("Unopened-tab footprint delta", statistic: "settled", measured: tabs.unopenedTabsFootprintDeltaMiB, limit: BenchmarkLimits.unopenedTabsFootprintDeltaMiB, unit: "MiB"),
            result("Unopened-tab switch", statistic: "median", measured: median(tabs.unopenedSwitchMilliseconds), limit: BenchmarkLimits.unopenedSwitchMedianMilliseconds, unit: "ms"),
            result("Unopened-tab switch", statistic: "p95", measured: percentile95(tabs.unopenedSwitchMilliseconds), limit: BenchmarkLimits.unopenedSwitchP95Milliseconds, unit: "ms"),
            result("Loaded-tab switch", statistic: "median", measured: median(tabs.loadedSwitchMilliseconds), limit: BenchmarkLimits.loadedSwitchMedianMilliseconds, unit: "ms"),
            result("Loaded-tab switch", statistic: "p95", measured: percentile95(tabs.loadedSwitchMilliseconds), limit: BenchmarkLimits.loadedSwitchP95Milliseconds, unit: "ms"),
            result("Rapid tab cycles", statistic: "count", measured: Double(tabs.rapidCycleCount), limit: 100, unit: "count", comparison: .exactly),
            result("Rapid-cycle repository watchers", statistic: "quiescent", measured: Double(tabs.rapidCycleWatcherCount), limit: 1, unit: "count", comparison: .exactly),
            result("Orphan Git processes", statistic: "after rapid cycle", measured: Double(tabs.orphanGitProcessCount), limit: 0, unit: "count", comparison: .exactly),
            result("Orphan repository tasks", statistic: "after rapid cycle", measured: Double(tabs.orphanRepositoryTaskCount), limit: 0, unit: "count", comparison: .exactly),
            result("Rapid-cycle footprint delta", statistic: "settled", measured: tabs.rapidCycleFootprintDeltaMiB, limit: BenchmarkLimits.rapidCycleFootprintDeltaMiB, unit: "MiB"),
            result("Main-thread stall", statistic: "maximum", measured: tabs.maximumMainThreadStallMilliseconds, limit: BenchmarkLimits.mainThreadStallMilliseconds, unit: "ms"),
            result("Returned to original tab", statistic: "value", measured: tabs.returnedToOriginalTab ? 1 : 0, limit: 1, unit: "boolean", comparison: .exactly),
            result("Retained tab-state footprint delta", statistic: "settled", measured: tabs.retainedTabsFootprintDeltaMiB, limit: BenchmarkLimits.retainedTabsFootprintDeltaMiB, unit: "MiB"),
            result("Tab workload idle CPU", statistic: "value", measured: tabs.idleCPUPercent, limit: BenchmarkLimits.idleCPUPercent, unit: "%"),
            result("Tab workload idle wakeups", statistic: "value", measured: tabs.idleWakeupsPerSecond, limit: BenchmarkLimits.idleWakeupsPerSecond, unit: "/s")
        ]
    }
}

public enum InteractionBenchmarkLimits {
    public static let bundleMiB = 2.75
    public static let compressedMiB = 1.15
    public static let maximumSourceFileBytes = 1_048_576
    public static let largeSourceLineCount = 20_000
    public static let longestSourceLineCharacters = 20_000
    public static let largeDiffChangedLineCount = 10_000
    public static let openSamples = 30
    public static let sourceOpenMedianMilliseconds = 100.0
    public static let sourceOpenP95Milliseconds = 150.0
    public static let diffOpenMedianMilliseconds = 125.0
    public static let diffOpenP95Milliseconds = 200.0
    public static let typingEdits = 1_000
    public static let typingMedianMilliseconds = 8.0
    public static let typingP95Milliseconds = 16.0
    public static let mainThreadStallMilliseconds = 33.0
    public static let scrollDurationSeconds = 10.0
    public static let droppedFrameRatePercent = 1.0
    public static let lineJumpSamples = 30
    public static let lineJumpP95Milliseconds = 50.0
    public static let lifecycleCycles = 100
    public static let lifecycleFootprintDeltaMiB = 5.0
}

public enum InteractionBenchmarkGuardrails {
    public static func evaluate(
        app: AppArtifactResult,
        interactions: InteractionPerformanceResult
    ) -> [GuardrailResult] {
        func result(
            _ name: String,
            statistic: String,
            measured: Double,
            limit: Double,
            unit: String,
            comparison: GuardrailComparison = .atMost
        ) -> GuardrailResult {
            GuardrailResult(
                name: name,
                repository: "interaction limits",
                statistic: statistic,
                measured: measured,
                limit: limit,
                unit: unit,
                comparison: comparison
            )
        }

        let source = interactions.maximumSourceOpenMilliseconds
        let diff = interactions.largeDiffOpenMilliseconds
        let typing = interactions.typingInputToDisplayMilliseconds
        let jump = interactions.lineJumpMilliseconds
        return [
            result("App bundle", statistic: "value", measured: mebibytes(app.bundleBytes), limit: InteractionBenchmarkLimits.bundleMiB, unit: "MiB"),
            result("Compressed app", statistic: "value", measured: mebibytes(app.compressedBytes), limit: InteractionBenchmarkLimits.compressedMiB, unit: "MiB"),
            result("Maximum source fixture", statistic: "bytes", measured: Double(interactions.maximumSourceFileBytes), limit: Double(InteractionBenchmarkLimits.maximumSourceFileBytes), unit: "bytes", comparison: .exactly),
            result("Large source fixture", statistic: "lines", measured: Double(interactions.largeSourceLineCount), limit: Double(InteractionBenchmarkLimits.largeSourceLineCount), unit: "lines", comparison: .exactly),
            result("Long-line fixture", statistic: "characters", measured: Double(interactions.longestSourceLineCharacters), limit: Double(InteractionBenchmarkLimits.longestSourceLineCharacters), unit: "characters", comparison: .exactly),
            result("Large diff fixture", statistic: "changed lines", measured: Double(interactions.largeDiffChangedLineCount), limit: Double(InteractionBenchmarkLimits.largeDiffChangedLineCount), unit: "lines", comparison: .atLeast),
            result("Maximum source opens", statistic: "samples", measured: Double(source.count), limit: Double(InteractionBenchmarkLimits.openSamples), unit: "count", comparison: .exactly),
            result("Maximum source open", statistic: "median", measured: median(source), limit: InteractionBenchmarkLimits.sourceOpenMedianMilliseconds, unit: "ms"),
            result("Maximum source open", statistic: "p95", measured: percentile95(source), limit: InteractionBenchmarkLimits.sourceOpenP95Milliseconds, unit: "ms"),
            result("Large diff opens", statistic: "samples", measured: Double(diff.count), limit: Double(InteractionBenchmarkLimits.openSamples), unit: "count", comparison: .exactly),
            result("Large diff open", statistic: "median", measured: median(diff), limit: InteractionBenchmarkLimits.diffOpenMedianMilliseconds, unit: "ms"),
            result("Large diff open", statistic: "p95", measured: percentile95(diff), limit: InteractionBenchmarkLimits.diffOpenP95Milliseconds, unit: "ms"),
            result("Sequential edits", statistic: "count", measured: Double(typing.count), limit: Double(InteractionBenchmarkLimits.typingEdits), unit: "count", comparison: .exactly),
            result("Typing input-to-display", statistic: "median", measured: median(typing), limit: InteractionBenchmarkLimits.typingMedianMilliseconds, unit: "ms"),
            result("Typing input-to-display", statistic: "p95", measured: percentile95(typing), limit: InteractionBenchmarkLimits.typingP95Milliseconds, unit: "ms"),
            result("Typing stall", statistic: "maximum", measured: typing.max() ?? .greatestFiniteMagnitude, limit: InteractionBenchmarkLimits.mainThreadStallMilliseconds, unit: "ms"),
            result("Editor scroll duration", statistic: "value", measured: interactions.editorScroll.durationSeconds, limit: InteractionBenchmarkLimits.scrollDurationSeconds, unit: "s", comparison: .atLeast),
            result("Editor dropped frames", statistic: "rate", measured: interactions.editorScroll.droppedFrameRatePercent, limit: InteractionBenchmarkLimits.droppedFrameRatePercent, unit: "%"),
            result("Editor scroll stall", statistic: "maximum", measured: interactions.editorScroll.maximumMainThreadStallMilliseconds, limit: InteractionBenchmarkLimits.mainThreadStallMilliseconds, unit: "ms"),
            result("Diff scroll duration", statistic: "value", measured: interactions.diffScroll.durationSeconds, limit: InteractionBenchmarkLimits.scrollDurationSeconds, unit: "s", comparison: .atLeast),
            result("Diff dropped frames", statistic: "rate", measured: interactions.diffScroll.droppedFrameRatePercent, limit: InteractionBenchmarkLimits.droppedFrameRatePercent, unit: "%"),
            result("Diff scroll stall", statistic: "maximum", measured: interactions.diffScroll.maximumMainThreadStallMilliseconds, limit: InteractionBenchmarkLimits.mainThreadStallMilliseconds, unit: "ms"),
            result("Line jumps", statistic: "samples", measured: Double(jump.count), limit: Double(InteractionBenchmarkLimits.lineJumpSamples), unit: "count", comparison: .exactly),
            result("Line jump", statistic: "p95", measured: percentile95(jump), limit: InteractionBenchmarkLimits.lineJumpP95Milliseconds, unit: "ms"),
            result("File/diff lifecycle", statistic: "cycles", measured: Double(interactions.lifecycleCycleCount), limit: Double(InteractionBenchmarkLimits.lifecycleCycles), unit: "count", comparison: .exactly),
            result("File/diff lifecycle footprint", statistic: "settled delta", measured: interactions.lifecycleFootprintDeltaMiB, limit: InteractionBenchmarkLimits.lifecycleFootprintDeltaMiB, unit: "MiB"),
            result("Orphan preview directories", statistic: "settled", measured: Double(interactions.orphanPreviewDirectoryCount), limit: 0, unit: "count", comparison: .exactly),
            result("Orphan repository tasks", statistic: "settled", measured: Double(interactions.orphanTaskCount), limit: 0, unit: "count", comparison: .exactly)
        ]
    }
}

public func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return .greatestFiniteMagnitude }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

public func percentile95(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return .greatestFiniteMagnitude }
    let sorted = values.sorted()
    let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
    return sorted[index]
}

public func mebibytes(_ bytes: UInt64) -> Double {
    Double(bytes) / 1_048_576
}

public func format(_ value: Double) -> String {
    String(format: "%.3f", value)
}

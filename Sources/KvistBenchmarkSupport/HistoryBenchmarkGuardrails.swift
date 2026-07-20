import Foundation

public struct HistoryFixtureResult: Codable, Equatable {
    public let commitCount: Int
    public let mergeCommitCount: Int
    public let branchCount: Int
    public let tagCount: Int
    public let expandedCommitFileCount: Int

    public init(
        commitCount: Int,
        mergeCommitCount: Int,
        branchCount: Int,
        tagCount: Int,
        expandedCommitFileCount: Int
    ) {
        self.commitCount = commitCount
        self.mergeCommitCount = mergeCommitCount
        self.branchCount = branchCount
        self.tagCount = tagCount
        self.expandedCommitFileCount = expandedCommitFileCount
    }
}

public struct HistoryPerformanceResult: Codable, Equatable {
    public let fixture: HistoryFixtureResult
    public let initialHistoryQueryMilliseconds: [Double]
    public let repositoryOpenToRenderedGraphMilliseconds: [Double]
    public let paginationMilliseconds: [Double]
    public let scopeSwitchMilliseconds: [Double]
    public let referenceParseAndDisplayMilliseconds: [Double]
    public let graphScroll: ScrollPerformanceResult
    public let fiveThousandRowFootprintDeltaMiB: [Double]
    public let lifecycleCycleCount: Int
    public let orphanTaskCount: Int
    public let staleGraphPublicationCount: Int
    public let lifecycleFootprintDeltaMiB: Double
    public let commitExpansionMilliseconds: [Double]
    public let commitExpansionStallMilliseconds: [Double]

    public init(
        fixture: HistoryFixtureResult,
        initialHistoryQueryMilliseconds: [Double],
        repositoryOpenToRenderedGraphMilliseconds: [Double],
        paginationMilliseconds: [Double],
        scopeSwitchMilliseconds: [Double],
        referenceParseAndDisplayMilliseconds: [Double],
        graphScroll: ScrollPerformanceResult,
        fiveThousandRowFootprintDeltaMiB: [Double],
        lifecycleCycleCount: Int,
        orphanTaskCount: Int,
        staleGraphPublicationCount: Int,
        lifecycleFootprintDeltaMiB: Double,
        commitExpansionMilliseconds: [Double],
        commitExpansionStallMilliseconds: [Double]
    ) {
        self.fixture = fixture
        self.initialHistoryQueryMilliseconds = initialHistoryQueryMilliseconds
        self.repositoryOpenToRenderedGraphMilliseconds = repositoryOpenToRenderedGraphMilliseconds
        self.paginationMilliseconds = paginationMilliseconds
        self.scopeSwitchMilliseconds = scopeSwitchMilliseconds
        self.referenceParseAndDisplayMilliseconds = referenceParseAndDisplayMilliseconds
        self.graphScroll = graphScroll
        self.fiveThousandRowFootprintDeltaMiB = fiveThousandRowFootprintDeltaMiB
        self.lifecycleCycleCount = lifecycleCycleCount
        self.orphanTaskCount = orphanTaskCount
        self.staleGraphPublicationCount = staleGraphPublicationCount
        self.lifecycleFootprintDeltaMiB = lifecycleFootprintDeltaMiB
        self.commitExpansionMilliseconds = commitExpansionMilliseconds
        self.commitExpansionStallMilliseconds = commitExpansionStallMilliseconds
    }
}

public struct HistoryBenchmarkReport: Codable, Equatable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let gitCommit: String
    public let gitTreeState: String
    public let operatingSystem: String
    public let app: AppArtifactResult
    public let history: HistoryPerformanceResult
    public let guardrails: [GuardrailResult]

    public init(
        schemaVersion: Int,
        generatedAt: String,
        gitCommit: String,
        gitTreeState: String,
        operatingSystem: String,
        app: AppArtifactResult,
        history: HistoryPerformanceResult,
        guardrails: [GuardrailResult]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.gitCommit = gitCommit
        self.gitTreeState = gitTreeState
        self.operatingSystem = operatingSystem
        self.app = app
        self.history = history
        self.guardrails = guardrails
    }
}

public enum HistoryBenchmarkLimits {
    public static let commits = 20_000
    public static let mergeCommits = 1_000
    public static let branches = 500
    public static let tags = 500
    public static let changedFiles = 1_000
    public static let backendSamples = 30
    public static let renderingSamples = 20
    public static let memorySamples = 5
    public static let initialMedianMilliseconds = 75.0
    public static let initialP95Milliseconds = 120.0
    public static let openMedianMilliseconds = 150.0
    public static let openP95Milliseconds = 220.0
    public static let paginationMedianMilliseconds = 80.0
    public static let paginationP95Milliseconds = 130.0
    public static let scopeSwitchP95Milliseconds = 150.0
    public static let referencesP95Milliseconds = 120.0
    public static let scrollDurationSeconds = 10.0
    public static let droppedFrameRatePercent = 1.0
    public static let scrollStallMilliseconds = 25.0
    public static let rowFootprintDeltaMiB = 20.0
    public static let lifecycleCycles = 100
    public static let lifecycleFootprintDeltaMiB = 3.0
    public static let expansionP95Milliseconds = 175.0
    public static let expansionStallMilliseconds = 33.0
}

public enum HistoryBenchmarkGuardrails {
    public static func evaluate(
        app: AppArtifactResult,
        history: HistoryPerformanceResult
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
                repository: "Large history fixture",
                statistic: statistic,
                measured: measured,
                limit: limit,
                unit: unit,
                comparison: comparison
            )
        }

        let initial = history.initialHistoryQueryMilliseconds
        let opens = history.repositoryOpenToRenderedGraphMilliseconds
        let pages = history.paginationMilliseconds
        let scopes = history.scopeSwitchMilliseconds
        let references = history.referenceParseAndDisplayMilliseconds
        let memory = history.fiveThousandRowFootprintDeltaMiB
        let expansions = history.commitExpansionMilliseconds
        let expansionStalls = history.commitExpansionStallMilliseconds

        return [
            result("App bundle", statistic: "size", measured: mebibytes(app.bundleBytes), limit: BenchmarkLimits.bundleMiB, unit: "MiB"),
            result("Compressed app", statistic: "size", measured: mebibytes(app.compressedBytes), limit: BenchmarkLimits.compressedMiB, unit: "MiB"),
            result("Fixture commits", statistic: "count", measured: Double(history.fixture.commitCount), limit: Double(HistoryBenchmarkLimits.commits), unit: "count", comparison: .atLeast),
            result("Fixture merge commits", statistic: "count", measured: Double(history.fixture.mergeCommitCount), limit: Double(HistoryBenchmarkLimits.mergeCommits), unit: "count", comparison: .atLeast),
            result("Fixture branches", statistic: "count", measured: Double(history.fixture.branchCount), limit: Double(HistoryBenchmarkLimits.branches), unit: "count", comparison: .atLeast),
            result("Fixture tags", statistic: "count", measured: Double(history.fixture.tagCount), limit: Double(HistoryBenchmarkLimits.tags), unit: "count", comparison: .atLeast),
            result("Expanded commit files", statistic: "count", measured: Double(history.fixture.expandedCommitFileCount), limit: Double(HistoryBenchmarkLimits.changedFiles), unit: "count", comparison: .atLeast),
            result("Initial history", statistic: "samples", measured: Double(initial.count), limit: Double(HistoryBenchmarkLimits.backendSamples), unit: "count", comparison: .atLeast),
            result("Initial history", statistic: "median", measured: median(initial), limit: HistoryBenchmarkLimits.initialMedianMilliseconds, unit: "ms"),
            result("Initial history", statistic: "p95", measured: percentile95(initial), limit: HistoryBenchmarkLimits.initialP95Milliseconds, unit: "ms"),
            result("Open to rendered graph", statistic: "samples", measured: Double(opens.count), limit: Double(HistoryBenchmarkLimits.renderingSamples), unit: "count", comparison: .atLeast),
            result("Open to rendered graph", statistic: "median", measured: median(opens), limit: HistoryBenchmarkLimits.openMedianMilliseconds, unit: "ms"),
            result("Open to rendered graph", statistic: "p95", measured: percentile95(opens), limit: HistoryBenchmarkLimits.openP95Milliseconds, unit: "ms"),
            result("Pagination", statistic: "samples", measured: Double(pages.count), limit: Double(HistoryBenchmarkLimits.backendSamples), unit: "count", comparison: .atLeast),
            result("Pagination", statistic: "median", measured: median(pages), limit: HistoryBenchmarkLimits.paginationMedianMilliseconds, unit: "ms"),
            result("Pagination", statistic: "p95", measured: percentile95(pages), limit: HistoryBenchmarkLimits.paginationP95Milliseconds, unit: "ms"),
            result("Scope switch", statistic: "samples", measured: Double(scopes.count), limit: Double(HistoryBenchmarkLimits.renderingSamples), unit: "count", comparison: .atLeast),
            result("Scope switch", statistic: "p95", measured: percentile95(scopes), limit: HistoryBenchmarkLimits.scopeSwitchP95Milliseconds, unit: "ms"),
            result("Reference parse and display", statistic: "samples", measured: Double(references.count), limit: Double(HistoryBenchmarkLimits.renderingSamples), unit: "count", comparison: .atLeast),
            result("Reference parse and display", statistic: "p95", measured: percentile95(references), limit: HistoryBenchmarkLimits.referencesP95Milliseconds, unit: "ms"),
            result("Graph scroll", statistic: "duration", measured: history.graphScroll.durationSeconds, limit: HistoryBenchmarkLimits.scrollDurationSeconds, unit: "s", comparison: .atLeast),
            result("Graph scroll", statistic: "dropped frames", measured: history.graphScroll.droppedFrameRatePercent, limit: HistoryBenchmarkLimits.droppedFrameRatePercent, unit: "%"),
            result("Graph scroll", statistic: "maximum stall", measured: history.graphScroll.maximumMainThreadStallMilliseconds, limit: HistoryBenchmarkLimits.scrollStallMilliseconds, unit: "ms"),
            result("5,000-row footprint", statistic: "samples", measured: Double(memory.count), limit: Double(HistoryBenchmarkLimits.memorySamples), unit: "count", comparison: .atLeast),
            result("5,000-row footprint", statistic: "maximum delta", measured: memory.max() ?? .greatestFiniteMagnitude, limit: HistoryBenchmarkLimits.rowFootprintDeltaMiB, unit: "MiB"),
            result("Lifecycle", statistic: "cycles", measured: Double(history.lifecycleCycleCount), limit: Double(HistoryBenchmarkLimits.lifecycleCycles), unit: "count", comparison: .exactly),
            result("Orphan graph tasks", statistic: "settled", measured: Double(history.orphanTaskCount), limit: 0, unit: "count", comparison: .exactly),
            result("Stale graph publications", statistic: "count", measured: Double(history.staleGraphPublicationCount), limit: 0, unit: "count", comparison: .exactly),
            result("Lifecycle footprint", statistic: "settled delta", measured: history.lifecycleFootprintDeltaMiB, limit: HistoryBenchmarkLimits.lifecycleFootprintDeltaMiB, unit: "MiB"),
            result("Commit expansion", statistic: "samples", measured: Double(expansions.count), limit: Double(HistoryBenchmarkLimits.renderingSamples), unit: "count", comparison: .atLeast),
            result("Commit expansion", statistic: "p95", measured: percentile95(expansions), limit: HistoryBenchmarkLimits.expansionP95Milliseconds, unit: "ms"),
            result("Commit expansion", statistic: "maximum stall", measured: expansionStalls.max() ?? .greatestFiniteMagnitude, limit: HistoryBenchmarkLimits.expansionStallMilliseconds, unit: "ms")
        ]
    }
}

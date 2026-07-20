import XCTest
@testable import KvistBenchmarkSupport

final class BenchmarkGuardrailsTests: XCTestCase {
    private struct FailureScenario {
        let name: String
        let statistic: String
        let app: AppArtifactResult
        let repository: RepositoryResult
    }

    func testEveryGuardrailPassesAtItsExactLimitForEveryRepository() {
        let repositories = ["GitLite", "Paeonia", "Tidex"].map {
            repository(name: $0, valuesAtLimits: true)
        }
        let results = BenchmarkGuardrails.evaluate(app: appAtLimits(), repositories: repositories)

        XCTAssertEqual(results.count, 56)
        XCTAssertTrue(results.allSatisfy(\.passed))
        XCTAssertEqual(Set(results.compactMap(\.repository)), Set(["GitLite", "Paeonia", "Tidex"]))
    }

    func testEveryGuardrailHasAReportedFailurePath() throws {
        let tooLargeBundle = UInt64(BenchmarkLimits.bundleMiB * 1_048_576) + 1
        let tooLargeCompressed = UInt64(BenchmarkLimits.compressedMiB * 1_048_576) + 1
        let passingApp = appAtLimits()
        let passingRepository = repository()
        let scenarios = [
            FailureScenario(name: "App bundle", statistic: "value", app: AppArtifactResult(bundleBytes: tooLargeBundle, compressedBytes: passingApp.compressedBytes), repository: passingRepository),
            FailureScenario(
                name: "Compressed app",
                statistic: "value",
                app: AppArtifactResult(
                    bundleBytes: passingApp.bundleBytes,
                    compressedBytes: tooLargeCompressed
                ),
                repository: passingRepository
            ),
            FailureScenario(name: "Launch", statistic: "median", app: passingApp, repository: repository(launch: repeated(251, count: 20))),
            FailureScenario(name: "Launch", statistic: "p95", app: passingApp, repository: repository(launch: p95Spike(count: 20, failure: 276))),
            FailureScenario(name: "Startup peak footprint", statistic: "maximum", app: passingApp, repository: repository(startupPeak: [35.001])),
            FailureScenario(name: "Settled footprint", statistic: "maximum", app: passingApp, repository: repository(settled: [50.001])),
            FailureScenario(name: "Idle CPU", statistic: "maximum", app: passingApp, repository: repository(idleCPU: [0.01001])),
            FailureScenario(name: "Idle wakeups", statistic: "maximum", app: passingApp, repository: repository(idleWakeups: [1.201])),
            FailureScenario(name: "Working-tree refresh", statistic: "median", app: passingApp, repository: repository(directRefresh: repeated(35.001, count: 30))),
            FailureScenario(name: "Working-tree refresh", statistic: "p95", app: passingApp, repository: repository(directRefresh: p95Spike(count: 30, failure: 50.001))),
            FailureScenario(name: "Initial repository loading", statistic: "median", app: passingApp, repository: repository(initialLoading: repeated(90.001, count: 30))),
            FailureScenario(name: "Initial repository loading", statistic: "p95", app: passingApp, repository: repository(initialLoading: p95Spike(count: 30, failure: 130.001))),
            FailureScenario(name: "External-edit latency", statistic: "median", app: passingApp, repository: repository(externalEdit: repeated(180.001, count: 30))),
            FailureScenario(name: "External-edit latency", statistic: "p95", app: passingApp, repository: repository(externalEdit: p95Spike(count: 30, failure: 200.001))),
            FailureScenario(name: "Event-storm latency", statistic: "p95", app: passingApp, repository: repository(eventStorm: p95Spike(count: 10, highSampleCount: 1, failure: 220.001))),
            FailureScenario(name: "Event storm writes", statistic: "maximum", app: passingApp, repository: repository(eventStormWrites: [100.001])),
            FailureScenario(name: "External edit working-tree snapshots", statistic: "every burst", app: passingApp, repository: repository(externalWorkingTreeSnapshots: [1, 0])),
            FailureScenario(name: "External edit full snapshots", statistic: "every burst", app: passingApp, repository: repository(externalFullSnapshots: [0, 1])),
            FailureScenario(name: "Event storm working-tree snapshots", statistic: "every burst", app: passingApp, repository: repository(stormWorkingTreeSnapshots: [0, 1])),
            FailureScenario(name: "Event storm full snapshots", statistic: "every burst", app: passingApp, repository: repository(stormFullSnapshots: [0, 1]))
        ]

        for scenario in scenarios {
            let results = BenchmarkGuardrails.evaluate(
                app: scenario.app,
                repositories: [scenario.repository]
            )
            let failure = try XCTUnwrap(
                results.first {
                    $0.name == scenario.name && $0.statistic == scenario.statistic && !$0.passed
                },
                "Expected \(scenario.name) \(scenario.statistic) to fail"
            )
            let report = try XCTUnwrap(BenchmarkGuardrails.failureReport(for: results))
            XCTAssertTrue(report.contains(failure.failureDescription))
            XCTAssertTrue(failure.failureDescription.contains("required \(failure.comparison.symbol)"))
            XCTAssertNoThrow(try JSONEncoder().encode(results))
        }
    }

    func testWorktreeSnapshotGuardrailsRequireExactlyOneRatherThanAtMostOne() {
        let results = BenchmarkGuardrails.evaluate(
            app: appAtLimits(),
            repositories: [
                repository(
                    externalWorkingTreeSnapshots: [0, 0],
                    stormWorkingTreeSnapshots: [0, 0]
                )
            ]
        )
        let worktreeResults = results.filter { $0.name.contains("working-tree snapshots") }

        XCTAssertEqual(worktreeResults.count, 2)
        XCTAssertTrue(worktreeResults.allSatisfy { !$0.passed && $0.comparison == .exactly })
    }

    func testGuardrailsAreEvaluatedIndependentlyPerRepository() {
        let results = BenchmarkGuardrails.evaluate(
            app: appAtLimits(),
            repositories: [
                repository(name: "GitLite", launch: repeated(251, count: 20)),
                repository(name: "Paeonia"),
                repository(name: "Tidex")
            ]
        )
        let launchMedians = results.filter { $0.name == "Launch" && $0.statistic == "median" }

        XCTAssertEqual(launchMedians.count, 3)
        XCTAssertEqual(launchMedians.filter { !$0.passed }.map(\.repository), ["GitLite"])
    }

    func testPassingResultsProduceNoFailureReport() {
        let results = BenchmarkGuardrails.evaluate(
            app: appAtLimits(),
            repositories: [repository()]
        )

        XCTAssertNil(BenchmarkGuardrails.failureReport(for: results))
    }

    func testEmptySampleSetsFailInsteadOfBeingIgnored() {
        let results = BenchmarkGuardrails.evaluate(
            app: appAtLimits(),
            repositories: [repository(launch: [])]
        )
        let launchResults = results.filter { $0.name == "Launch" }

        XCTAssertEqual(launchResults.count, 2)
        XCTAssertTrue(
            launchResults.allSatisfy {
                !$0.passed && $0.measured == .greatestFiniteMagnitude
            }
        )
    }

    func testMinimumBenchmarkMethodologyIsAcceptedAndEachReductionIsRejected() {
        XCTAssertNil(minimumViolation())
        XCTAssertEqual(minimumViolation(launchSamples: 19), "--launch-samples must be at least 20")
        XCTAssertEqual(minimumViolation(gitSamples: 29), "--git-samples must be at least 30")
        XCTAssertEqual(minimumViolation(externalRefreshSamples: 29), "--external-refresh-samples must be at least 30")
        XCTAssertEqual(minimumViolation(eventStormTrials: 9), "--event-storm-trials must be at least 10")
        XCTAssertEqual(minimumViolation(idleSamples: 4), "--idle-samples must be at least 5")
        XCTAssertNotNil(minimumViolation(idleDurationSeconds: 9.999))
    }

    func testNearestRankP95AndMedianMethodologyArePreserved() {
        XCTAssertEqual(median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(median([3, 1, 2]), 2)
        XCTAssertEqual(percentile95(Array(1...20).map(Double.init)), 19)
        XCTAssertEqual(percentile95(Array(1...30).map(Double.init)), 29)
    }

    func testTabGuardrailsPassAtEveryExactLimit() {
        let results = TabBenchmarkGuardrails.evaluate(tabResult(valuesAtLimits: true))

        XCTAssertEqual(results.count, 20)
        XCTAssertTrue(results.allSatisfy(\.passed))
    }

    func testTabGuardrailsReportLifecycleAndLatencyRegressions() {
        let failing = TabPerformanceResult(
            fixtureCount: 19,
            initiallyLoadedRepositoryCount: 2,
            inactiveGitCommandCountBeforeSelection: 1,
            inactiveWatcherCountBeforeSelection: 1,
            initialQuiescentWatcherCount: 2,
            unopenedTabsFootprintDeltaMiB: 10.001,
            unopenedSwitchMilliseconds: repeated(301, count: 19),
            retainedTabsFootprintDeltaMiB: 30.001,
            loadedSwitchMilliseconds: repeated(51, count: 100),
            rapidCycleCount: 99,
            rapidCycleWatcherCount: 2,
            orphanGitProcessCount: 1,
            orphanRepositoryTaskCount: 1,
            rapidCycleFootprintDeltaMiB: 3.001,
            maximumMainThreadStallMilliseconds: 50.001,
            returnedToOriginalTab: false,
            idleCPUPercent: 0.01001,
            idleWakeupsPerSecond: 1.201
        )
        let results = TabBenchmarkGuardrails.evaluate(failing)

        XCTAssertEqual(results.count, 20)
        XCTAssertTrue(results.allSatisfy { !$0.passed })
        XCTAssertNotNil(BenchmarkGuardrails.failureReport(for: results))
    }

    func testInteractionGuardrailsPassAtEveryExactLimit() {
        let app = AppArtifactResult(
            bundleBytes: UInt64(InteractionBenchmarkLimits.bundleMiB * 1_048_576),
            compressedBytes: UInt64(InteractionBenchmarkLimits.compressedMiB * 1_048_576)
        )
        let results = InteractionBenchmarkGuardrails.evaluate(
            app: app,
            interactions: interactionResult()
        )

        XCTAssertEqual(results.count, 28)
        XCTAssertTrue(results.allSatisfy(\.passed))
        XCTAssertEqual(
            results.first { $0.name == "Large diff fixture" }?.comparison,
            .atLeast
        )
    }

    func testInteractionGuardrailsRejectIncompleteAndRegressedMeasurements() {
        let result = interactionResult(
            sourceOpens: repeated(151, count: 29),
            changedLines: 9_999,
            typing: repeated(34, count: 999),
            lifecycleCycles: 99
        )
        let app = AppArtifactResult(
            bundleBytes: UInt64(2.751 * 1_048_576),
            compressedBytes: UInt64(1.151 * 1_048_576)
        )
        let guardrails = InteractionBenchmarkGuardrails.evaluate(
            app: app,
            interactions: result
        )

        XCTAssertFalse(guardrails.first { $0.name == "App bundle" }!.passed)
        XCTAssertFalse(guardrails.first { $0.name == "Compressed app" }!.passed)
        XCTAssertFalse(guardrails.first { $0.name == "Large diff fixture" }!.passed)
        XCTAssertFalse(guardrails.first { $0.name == "Maximum source opens" }!.passed)
        XCTAssertFalse(guardrails.first { $0.name == "Sequential edits" }!.passed)
        XCTAssertFalse(guardrails.first { $0.name == "File/diff lifecycle" }!.passed)
        XCTAssertNotNil(BenchmarkGuardrails.failureReport(for: guardrails))
    }

    private func appAtLimits() -> AppArtifactResult {
        AppArtifactResult(
            bundleBytes: UInt64(BenchmarkLimits.bundleMiB * 1_048_576),
            compressedBytes: UInt64(BenchmarkLimits.compressedMiB * 1_048_576)
        )
    }

    private func interactionResult(
        sourceOpens: [Double]? = nil,
        changedLines: Int = InteractionBenchmarkLimits.largeDiffChangedLineCount,
        typing: [Double]? = nil,
        lifecycleCycles: Int = InteractionBenchmarkLimits.lifecycleCycles
    ) -> InteractionPerformanceResult {
        let passingScroll = ScrollPerformanceResult(
            durationSeconds: InteractionBenchmarkLimits.scrollDurationSeconds,
            renderedFrameCount: 600,
            droppedFrameCount: 6,
            droppedFrameRatePercent: InteractionBenchmarkLimits.droppedFrameRatePercent,
            maximumMainThreadStallMilliseconds: InteractionBenchmarkLimits.mainThreadStallMilliseconds
        )
        return InteractionPerformanceResult(
            maximumSourceFileBytes: InteractionBenchmarkLimits.maximumSourceFileBytes,
            largeSourceLineCount: InteractionBenchmarkLimits.largeSourceLineCount,
            longestSourceLineCharacters: InteractionBenchmarkLimits.longestSourceLineCharacters,
            largeDiffChangedLineCount: changedLines,
            maximumSourceOpenMilliseconds: sourceOpens
                ?? repeated(InteractionBenchmarkLimits.sourceOpenMedianMilliseconds, count: 30),
            largeLineOpenMilliseconds: [1],
            largeDiffOpenMilliseconds: repeated(
                InteractionBenchmarkLimits.diffOpenMedianMilliseconds,
                count: 30
            ),
            typingInputToDisplayMilliseconds: typing
                ?? repeated(InteractionBenchmarkLimits.typingMedianMilliseconds, count: 1_000),
            editorScroll: passingScroll,
            diffScroll: passingScroll,
            lineJumpMilliseconds: repeated(
                InteractionBenchmarkLimits.lineJumpP95Milliseconds,
                count: 30
            ),
            lifecycleCycleCount: lifecycleCycles,
            lifecycleFootprintDeltaMiB: InteractionBenchmarkLimits.lifecycleFootprintDeltaMiB,
            orphanPreviewDirectoryCount: 0,
            orphanTaskCount: 0
        )
    }

    func testHistoryGuardrailsPassAtExactLimits() {
        let app = AppArtifactResult(
            bundleBytes: UInt64(BenchmarkLimits.bundleMiB * 1_048_576),
            compressedBytes: UInt64(BenchmarkLimits.compressedMiB * 1_048_576)
        )
        let results = HistoryBenchmarkGuardrails.evaluate(
            app: app,
            history: historyResult(valuesAtLimits: true)
        )

        XCTAssertEqual(results.count, 32)
        XCTAssertTrue(results.allSatisfy(\.passed))
    }

    func testHistoryGuardrailsRejectIncompleteAndRegressedRuns() {
        var result = historyResult(valuesAtLimits: false)
        result = HistoryPerformanceResult(
            fixture: result.fixture,
            initialHistoryQueryMilliseconds: [121],
            repositoryOpenToRenderedGraphMilliseconds: [221],
            paginationMilliseconds: [131],
            scopeSwitchMilliseconds: [151],
            referenceParseAndDisplayMilliseconds: [121],
            graphScroll: ScrollPerformanceResult(
                durationSeconds: 9,
                renderedFrameCount: 1,
                droppedFrameCount: 1,
                droppedFrameRatePercent: 2,
                maximumMainThreadStallMilliseconds: 26
            ),
            fiveThousandRowFootprintDeltaMiB: [21],
            lifecycleCycleCount: 99,
            orphanTaskCount: 1,
            staleGraphPublicationCount: 1,
            lifecycleFootprintDeltaMiB: 4,
            commitExpansionMilliseconds: [176],
            commitExpansionStallMilliseconds: [34]
        )
        let failures = HistoryBenchmarkGuardrails.evaluate(
            app: AppArtifactResult(bundleBytes: 0, compressedBytes: 0),
            history: result
        ).filter { !$0.passed }

        XCTAssertGreaterThanOrEqual(failures.count, 20)
    }

    private func historyResult(valuesAtLimits: Bool) -> HistoryPerformanceResult {
        let exact = valuesAtLimits
        return HistoryPerformanceResult(
            fixture: HistoryFixtureResult(
                commitCount: 20_000,
                mergeCommitCount: 1_000,
                branchCount: 500,
                tagCount: 500,
                expandedCommitFileCount: 1_000
            ),
            initialHistoryQueryMilliseconds: repeated(exact ? 75 : 1, count: 30),
            repositoryOpenToRenderedGraphMilliseconds: repeated(exact ? 150 : 1, count: 20),
            paginationMilliseconds: repeated(exact ? 80 : 1, count: 30),
            scopeSwitchMilliseconds: repeated(exact ? 150 : 1, count: 20),
            referenceParseAndDisplayMilliseconds: repeated(exact ? 120 : 1, count: 20),
            graphScroll: ScrollPerformanceResult(
                durationSeconds: 10,
                renderedFrameCount: 1_000,
                droppedFrameCount: exact ? 10 : 0,
                droppedFrameRatePercent: exact ? 1 : 0,
                maximumMainThreadStallMilliseconds: exact ? 25 : 1
            ),
            fiveThousandRowFootprintDeltaMiB: repeated(exact ? 20 : 1, count: 5),
            lifecycleCycleCount: 100,
            orphanTaskCount: 0,
            staleGraphPublicationCount: 0,
            lifecycleFootprintDeltaMiB: exact ? 3 : 0,
            commitExpansionMilliseconds: repeated(exact ? 175 : 1, count: 20),
            commitExpansionStallMilliseconds: repeated(exact ? 33 : 1, count: 20)
        )
    }

    private func repository(
        name: String = "GitLite",
        valuesAtLimits: Bool = false,
        launch: [Double]? = nil,
        startupPeak: [Double]? = nil,
        settled: [Double]? = nil,
        idleCPU: [Double]? = nil,
        idleWakeups: [Double]? = nil,
        directRefresh: [Double]? = nil,
        initialLoading: [Double]? = nil,
        externalEdit: [Double]? = nil,
        eventStorm: [Double]? = nil,
        eventStormWrites: [Double]? = nil,
        externalWorkingTreeSnapshots: [Int]? = nil,
        externalFullSnapshots: [Int]? = nil,
        stormWorkingTreeSnapshots: [Int]? = nil,
        stormFullSnapshots: [Int]? = nil
    ) -> RepositoryResult {
        let value = valuesAtLimits
        return RepositoryResult(
            name: name,
            path: "/tmp/\(name)",
            launchToInitialFrameMilliseconds: launch ?? repeated(value ? 250 : 100, count: 20),
            startupPeakPhysicalFootprintMiB: startupPeak ?? [value ? 35 : 10],
            settledPhysicalFootprintMiB: settled ?? [value ? 50 : 10],
            idleCPUPercent: idleCPU ?? [value ? 0.01 : 0],
            idleWakeupsPerSecond: idleWakeups ?? [value ? 1.2 : 0],
            workingTreeRefreshMilliseconds: directRefresh ?? repeated(value ? 35 : 10, count: 30),
            initialRepositoryLoadingMilliseconds: initialLoading ?? repeated(value ? 90 : 10, count: 30),
            externalEditToPublicationMilliseconds: externalEdit ?? repeated(value ? 180 : 10, count: 30),
            eventStormSettleMilliseconds: eventStorm ?? repeated(value ? 220 : 10, count: 10),
            eventStormWriteMilliseconds: eventStormWrites ?? [value ? 100 : 10],
            externalEditWorkingTreeSnapshotCounts: externalWorkingTreeSnapshots ?? [1],
            externalEditFullSnapshotCounts: externalFullSnapshots ?? [0],
            eventStormWorkingTreeSnapshotCounts: stormWorkingTreeSnapshots ?? [1],
            eventStormFullSnapshotCounts: stormFullSnapshots ?? [0]
        )
    }

    private func repeated(_ value: Double, count: Int) -> [Double] {
        Array(repeating: value, count: count)
    }

    private func tabResult(valuesAtLimits: Bool) -> TabPerformanceResult {
        let exact = valuesAtLimits
        return TabPerformanceResult(
            fixtureCount: 20,
            initiallyLoadedRepositoryCount: 1,
            inactiveGitCommandCountBeforeSelection: 0,
            inactiveWatcherCountBeforeSelection: 0,
            initialQuiescentWatcherCount: 1,
            unopenedTabsFootprintDeltaMiB: exact ? 10 : 1,
            unopenedSwitchMilliseconds: repeated(exact ? 200 : 10, count: 19),
            retainedTabsFootprintDeltaMiB: exact ? 30 : 1,
            loadedSwitchMilliseconds: repeated(exact ? 30 : 1, count: 100),
            rapidCycleCount: 100,
            rapidCycleWatcherCount: 1,
            orphanGitProcessCount: 0,
            orphanRepositoryTaskCount: 0,
            rapidCycleFootprintDeltaMiB: exact ? 3 : 1,
            maximumMainThreadStallMilliseconds: exact ? 50 : 1,
            returnedToOriginalTab: true,
            idleCPUPercent: exact ? 0.01 : 0,
            idleWakeupsPerSecond: exact ? 1.2 : 0
        )
    }

    private func p95Spike(
        count: Int,
        highSampleCount: Int = 2,
        failure: Double
    ) -> [Double] {
        repeated(1, count: count - highSampleCount) + repeated(failure, count: highSampleCount)
    }

    private func minimumViolation(
        launchSamples: Int = 20,
        gitSamples: Int = 30,
        externalRefreshSamples: Int = 30,
        eventStormTrials: Int = 10,
        idleSamples: Int = 5,
        idleDurationSeconds: Double = 10
    ) -> String? {
        BenchmarkMinimums.violation(
            launchSamples: launchSamples,
            gitSamples: gitSamples,
            externalRefreshSamples: externalRefreshSamples,
            eventStormTrials: eventStormTrials,
            idleSamples: idleSamples,
            idleDurationSeconds: idleDurationSeconds
        )
    }
}

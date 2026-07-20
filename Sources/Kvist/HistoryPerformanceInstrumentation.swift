import AppKit
import Darwin
import Foundation
import QuartzCore

private struct KvistHistoryScrollResult: Codable {
    let durationSeconds: Double
    let renderedFrameCount: Int
    let droppedFrameCount: Int
    let droppedFrameRatePercent: Double
    let maximumMainThreadStallMilliseconds: Double
}

private struct KvistHistoryFixtureResult: Codable {
    let commitCount: Int
    let mergeCommitCount: Int
    let branchCount: Int
    let tagCount: Int
    let expandedCommitFileCount: Int
}

private struct KvistHistoryResult: Codable {
    let fixture: KvistHistoryFixtureResult
    let initialHistoryQueryMilliseconds: [Double]
    let repositoryOpenToRenderedGraphMilliseconds: [Double]
    let paginationMilliseconds: [Double]
    let scopeSwitchMilliseconds: [Double]
    let referenceParseAndDisplayMilliseconds: [Double]
    let graphScroll: KvistHistoryScrollResult
    let fiveThousandRowFootprintDeltaMiB: [Double]
    let lifecycleCycleCount: Int
    let orphanTaskCount: Int
    let staleGraphPublicationCount: Int
    let lifecycleFootprintDeltaMiB: Double
    let commitExpansionMilliseconds: [Double]
    let commitExpansionStallMilliseconds: [Double]
}

@MainActor
enum KvistHistoryPerformanceInstrumentation {
    private static var started = false
    private static let backendSampleCount = 30
    private static let renderingSampleCount = 20
    private static let memorySampleCount = 5
    private static let loadedRowCount = 5_000
    private static let lifecycleCycleCount = 100
    private static let scrollDurationSeconds = 10.0

    static func runIfRequested(model: RepositoryModel) {
        guard let configuration = KvistPerformanceInstrumentation.configuration,
              configuration.mode == .history,
              !started else { return }
        started = true
        Task {
            do {
                let result = try await measure(model: model, configuration: configuration)
                try FileManager.default.createDirectory(
                    at: configuration.outputDirectory,
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(
                    to: configuration.outputDirectory.appendingPathComponent("history.json"),
                    options: .atomic
                )
                NSApp.terminate(nil)
            } catch {
                try? error.localizedDescription.write(
                    to: configuration.outputDirectory.appendingPathComponent("error.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                NSApp.terminate(nil)
            }
        }
    }

    private static func measure(
        model: RepositoryModel,
        configuration: KvistPerformanceConfiguration
    ) async throws -> KvistHistoryResult {
        let repositoryURL = configuration.repositoryURL.standardizedFileURL
        try await wait(timeoutSeconds: 30) {
            model.repositoryURL?.standardizedFileURL == repositoryURL && !model.isBusy
        }
        renderApplication()
        let client = GitClient(repositoryURL: repositoryURL)
        guard let queryContext = model.historyPerformanceQueryContext() else {
            throw benchmarkError("Initial history query context is unavailable")
        }

        _ = try await Task.detached(priority: .userInitiated) {
            try client.historyPage(
                offset: 0,
                count: 50,
                scope: queryContext.scope,
                remoteReferenceID: queryContext.remoteReferenceID,
                knownHeadHash: queryContext.headHash,
                layoutState: GraphLayoutState(),
                referencesByCommitHash: queryContext.referencesByCommitHash
            )
        }.value
        var initialQueries: [Double] = []
        initialQueries.reserveCapacity(backendSampleCount)
        for _ in 0..<backendSampleCount {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            _ = try await Task.detached(priority: .userInitiated) {
                try client.historyPage(
                    offset: 0,
                    count: 50,
                    scope: queryContext.scope,
                    remoteReferenceID: queryContext.remoteReferenceID,
                    knownHeadHash: queryContext.headHash,
                    layoutState: GraphLayoutState(),
                    referencesByCommitHash: queryContext.referencesByCommitHash
                )
            }.value
            initialQueries.append(milliseconds(since: startedAt))
        }

        var opens: [Double] = []
        opens.reserveCapacity(renderingSampleCount)
        for _ in 0..<renderingSampleCount {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            await model.openRepository(repositoryURL)
            await nextMainRunLoopTurn()
            renderApplication()
            guard model.graph.count == 50 else {
                throw benchmarkError("Repository open did not render the initial 50 rows")
            }
            opens.append(milliseconds(since: startedAt))
        }

        var references: [Double] = []
        references.reserveCapacity(renderingSampleCount)
        for _ in 0..<renderingSampleCount {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let parsed = try await Task.detached(priority: .userInitiated) {
                try client.references()
            }.value
            renderApplication()
            guard parsed.count >= 1_000, model.references.count >= 1_000 else {
                throw benchmarkError("Reference benchmark requires at least 1,000 references")
            }
            references.append(milliseconds(since: startedAt))
        }

        var scopeSwitches: [Double] = []
        scopeSwitches.reserveCapacity(renderingSampleCount)
        for sample in 0..<renderingSampleCount {
            let scope: GraphScope = sample.isMultiple(of: 2) ? .current : .all
            let startedAt = DispatchTime.now().uptimeNanoseconds
            await model.setGraphScope(scope)
            await nextMainRunLoopTurn()
            renderApplication()
            guard model.graphScope == scope,
                  model.graphPublicationScope == scope else {
                throw benchmarkError("Graph scope published mismatched rows")
            }
            scopeSwitches.append(milliseconds(since: startedAt))
        }

        var pagination: [Double] = []
        var memoryDeltas: [Double] = []
        memoryDeltas.reserveCapacity(memorySampleCount)
        var scrollView: NSScrollView?
        for _ in 0..<memorySampleCount {
            await model.openRepository(repositoryURL)
            try await settle(model: model)
            let initialFootprint = try physicalFootprintBytes()
            while model.graph.count < loadedRowCount, model.canLoadMoreGraph {
                let previousCount = model.graph.count
                let startedAt = DispatchTime.now().uptimeNanoseconds
                await model.loadMoreGraph()
                await nextMainRunLoopTurn()
                renderApplication()
                guard model.graph.count > previousCount else {
                    throw benchmarkError("Pagination did not append history rows")
                }
                pagination.append(milliseconds(since: startedAt))
            }
            guard model.graph.count >= loadedRowCount else {
                throw benchmarkError("Fixture did not provide 5,000 visible history rows")
            }
            try await settle(model: model)
            let loadedFootprint = try physicalFootprintBytes()
            memoryDeltas.append(
                Double(Int64(loadedFootprint) - Int64(initialFootprint)) / 1_048_576
            )
            scrollView = largestScrollableView()
        }

        guard pagination.count >= backendSampleCount else {
            throw benchmarkError("Pagination benchmark produced too few samples")
        }
        guard let scrollView else {
            throw benchmarkError("Could not locate the rendered history scroll view")
        }
        let graphScroll = await measureScroll(
            scrollView,
            durationSeconds: scrollDurationSeconds
        )

        await model.openRepository(repositoryURL)
        try await settle(model: model)
        let lifecycleFootprintBefore = try physicalFootprintBytes()
        let staleBefore = model.staleGraphPublicationCount
        for _ in 0..<lifecycleCycleCount {
            let paginationTask = Task { await model.loadMoreGraph() }
            await Task.yield()
            let nextScope: GraphScope = model.graphScope == .all ? .current : .all
            await model.setGraphScope(nextScope)
            await paginationTask.value
        }
        if model.graphScope != .all {
            await model.setGraphScope(.all)
        }
        try await settle(model: model)
        renderApplication()
        guard model.graph.count == 50 else {
            throw benchmarkError("Lifecycle benchmark did not return to the initial page")
        }
        let lifecycleFootprintAfter = try physicalFootprintBytes()
        let orphanTasks = model.hasOutstandingRepositoryTasks ? 1 : 0
        let stalePublications = model.staleGraphPublicationCount - staleBefore

        var expansions: [Double] = []
        var expansionStalls: [Double] = []
        expansions.reserveCapacity(renderingSampleCount)
        expansionStalls.reserveCapacity(renderingSampleCount)
        for _ in 0..<renderingSampleCount {
            await model.openRepository(repositoryURL)
            guard let commit = model.graph.first?.commit else {
                throw benchmarkError("Expansion fixture commit is not visible")
            }
            model.resetCommitExpansionForPerformanceMeasurement(commit)
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let toggleStartedAt = DispatchTime.now().uptimeNanoseconds
            model.toggleCommitExpansion(commit)
            var maximumStall = milliseconds(since: toggleStartedAt)
            try await wait(timeoutSeconds: 10) {
                model.files(for: commit).count >= 1_000
                    && !model.loadingCommitFileHashes.contains(commit.hash)
            }
            await nextMainRunLoopTurn()
            let renderStartedAt = DispatchTime.now().uptimeNanoseconds
            renderApplication()
            maximumStall = max(maximumStall, milliseconds(since: renderStartedAt))
            guard model.files(for: commit).count == 1_000 else {
                throw benchmarkError("Expansion fixture did not contain exactly 1,000 files")
            }
            expansions.append(milliseconds(since: startedAt))
            expansionStalls.append(maximumStall)
        }

        let environment = ProcessInfo.processInfo.environment
        func fixtureValue(_ name: String) throws -> Int {
            guard let value = environment[name].flatMap(Int.init) else {
                throw benchmarkError("Missing fixture metadata: \(name)")
            }
            return value
        }

        return KvistHistoryResult(
            fixture: KvistHistoryFixtureResult(
                commitCount: try fixtureValue("KVIST_HISTORY_FIXTURE_COMMITS"),
                mergeCommitCount: try fixtureValue("KVIST_HISTORY_FIXTURE_MERGES"),
                branchCount: try fixtureValue("KVIST_HISTORY_FIXTURE_BRANCHES"),
                tagCount: try fixtureValue("KVIST_HISTORY_FIXTURE_TAGS"),
                expandedCommitFileCount: 1_000
            ),
            initialHistoryQueryMilliseconds: initialQueries,
            repositoryOpenToRenderedGraphMilliseconds: opens,
            paginationMilliseconds: pagination,
            scopeSwitchMilliseconds: scopeSwitches,
            referenceParseAndDisplayMilliseconds: references,
            graphScroll: graphScroll,
            fiveThousandRowFootprintDeltaMiB: memoryDeltas,
            lifecycleCycleCount: lifecycleCycleCount,
            orphanTaskCount: orphanTasks,
            staleGraphPublicationCount: stalePublications,
            lifecycleFootprintDeltaMiB: Double(
                Int64(lifecycleFootprintAfter) - Int64(lifecycleFootprintBefore)
            ) / 1_048_576,
            commitExpansionMilliseconds: expansions,
            commitExpansionStallMilliseconds: expansionStalls
        )
    }

    private static func largestScrollableView() -> NSScrollView? {
        applicationViews().compactMap { $0 as? NSScrollView }
            .filter { scrollView in
                guard let documentView = scrollView.documentView else { return false }
                return documentView.bounds.height - scrollView.contentView.bounds.height > 1
            }
            .max { lhs, rhs in
                let left = (lhs.documentView?.bounds.height ?? 0) - lhs.contentView.bounds.height
                let right = (rhs.documentView?.bounds.height ?? 0) - rhs.contentView.bounds.height
                return left < right
            }
    }

    private static func applicationViews() -> [NSView] {
        NSApp.windows.filter(\.isVisible).flatMap { window in
            window.contentView.map(descendants(in:)) ?? []
        }
    }

    private static func descendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants(in:))
    }

    private static func measureScroll(
        _ scrollView: NSScrollView,
        durationSeconds: Double
    ) async -> KvistHistoryScrollResult {
        await withCheckedContinuation { continuation in
            let driver = DisplayLinkScrollDriver(
                scrollView: scrollView,
                durationSeconds: durationSeconds
            ) { result in
                continuation.resume(returning: result)
            }
            driver.start()
        }
    }

    private static func settle(model: RepositoryModel) async throws {
        try await wait(timeoutSeconds: 15) {
            !model.hasOutstandingRepositoryTasks && !model.isLoadingMoreGraph
        }
        try await Task.sleep(for: .milliseconds(250))
        renderApplication()
    }

    private static func physicalFootprintBytes() throws -> UInt64 {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            proc_pid_rusage(
                getpid(),
                RUSAGE_INFO_V4,
                UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self)
            )
        }
        guard status == 0 else {
            throw benchmarkError("Could not read Kvist physical footprint")
        }
        return usage.ri_phys_footprint
    }

    private static func wait(
        timeoutSeconds: Double,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        guard condition() else {
            throw benchmarkError("Timed out waiting for history benchmark state")
        }
    }

    private static func renderApplication() {
        for window in NSApp.windows where window.isVisible {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        CATransaction.flush()
    }

    private static func nextMainRunLoopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private static func milliseconds(since startedAt: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
    }

    private static func benchmarkError(_ message: String) -> NSError {
        NSError(
            domain: "KvistHistoryPerformanceInstrumentation",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    @MainActor
    private final class DisplayLinkScrollDriver: NSObject {
        private weak var scrollView: NSScrollView?
        private let requestedDuration: Double
        private let completion: (KvistHistoryScrollResult) -> Void
        private var displayLink: CADisplayLink?
        private var firstTimestamp: CFTimeInterval?
        private var lastTimestamp: CFTimeInterval?
        private var renderedFrames = 0
        private var droppedFrames = 0
        private var maximumStallMilliseconds = 0.0

        init(
            scrollView: NSScrollView,
            durationSeconds: Double,
            completion: @escaping (KvistHistoryScrollResult) -> Void
        ) {
            self.scrollView = scrollView
            requestedDuration = durationSeconds
            self.completion = completion
        }

        func start() {
            guard let scrollView else {
                finish(duration: 0)
                return
            }
            let link = scrollView.displayLink(target: self, selector: #selector(frame(_:)))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func frame(_ link: CADisplayLink) {
            guard let scrollView, let documentView = scrollView.documentView else {
                finish(duration: 0)
                return
            }
            if firstTimestamp == nil { firstTimestamp = link.timestamp }
            if let lastTimestamp {
                let frameDuration = max(link.duration, 1.0 / 240.0)
                let frameInterval = link.timestamp - lastTimestamp
                let elapsedFrames = max(1, Int((frameInterval / frameDuration).rounded()))
                droppedFrames += max(0, elapsedFrames - 1)
                maximumStallMilliseconds = max(
                    maximumStallMilliseconds,
                    frameInterval * 1_000
                )
            }
            lastTimestamp = link.timestamp

            let operationStartedAt = DispatchTime.now().uptimeNanoseconds
            let elapsed = link.timestamp - (firstTimestamp ?? link.timestamp)
            let clipView = scrollView.contentView
            let maximumY = max(0, documentView.bounds.height - clipView.bounds.height)
            if maximumY > 0 {
                let phase = (elapsed * 480).truncatingRemainder(dividingBy: maximumY * 2)
                    / maximumY
                let progress = phase <= 1 ? phase : 2 - phase
                clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: maximumY * progress))
                scrollView.reflectScrolledClipView(clipView)
            }
            renderApplication()
            maximumStallMilliseconds = max(
                maximumStallMilliseconds,
                milliseconds(since: operationStartedAt)
            )
            renderedFrames += 1
            if elapsed >= requestedDuration { finish(duration: elapsed) }
        }

        private func finish(duration: Double) {
            displayLink?.invalidate()
            displayLink = nil
            let totalFrames = renderedFrames + droppedFrames
            completion(KvistHistoryScrollResult(
                durationSeconds: duration,
                renderedFrameCount: renderedFrames,
                droppedFrameCount: droppedFrames,
                droppedFrameRatePercent: totalFrames > 0
                    ? Double(droppedFrames) / Double(totalFrames) * 100
                    : 100,
                maximumMainThreadStallMilliseconds: maximumStallMilliseconds
            ))
        }
    }
}

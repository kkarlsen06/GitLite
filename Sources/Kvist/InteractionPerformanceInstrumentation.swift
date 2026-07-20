import AppKit
import Darwin
import Foundation
import QuartzCore

private struct KvistInteractionScrollResult: Codable {
    let durationSeconds: Double
    let renderedFrameCount: Int
    let droppedFrameCount: Int
    let droppedFrameRatePercent: Double
    let maximumMainThreadStallMilliseconds: Double
}

private struct KvistInteractionResult: Codable {
    let maximumSourceFileBytes: Int
    let largeSourceLineCount: Int
    let longestSourceLineCharacters: Int
    let largeDiffChangedLineCount: Int
    let maximumSourceOpenMilliseconds: [Double]
    let largeLineOpenMilliseconds: [Double]
    let largeDiffOpenMilliseconds: [Double]
    let typingInputToDisplayMilliseconds: [Double]
    let editorScroll: KvistInteractionScrollResult
    let diffScroll: KvistInteractionScrollResult
    let lineJumpMilliseconds: [Double]
    let lifecycleCycleCount: Int
    let lifecycleFootprintDeltaMiB: Double
    let orphanPreviewDirectoryCount: Int
    let orphanTaskCount: Int
}

@MainActor
enum KvistInteractionPerformanceInstrumentation {
    private static var started = false
    private static let maximumSourcePath = "maximum-source.swift"
    private static let largeSourcePath = "twenty-thousand-lines.swift"
    private static let longLinePath = "twenty-thousand-character-line.swift"
    private static let largeDiffPath = "large-diff.swift"
    private static let openSampleCount = 30
    private static let typingEditCount = 1_000
    private static let lineJumpSampleCount = 30
    private static let lifecycleCycleCount = 100
    private static let scrollDurationSeconds = 10.0

    static func runIfRequested(model: RepositoryModel) {
        guard let configuration = KvistPerformanceInstrumentation.configuration,
              configuration.mode == .interaction,
              !started else { return }
        started = true
        Task {
            do {
                let result = try await measure(model: model, configuration: configuration)
                let url = configuration.outputDirectory.appendingPathComponent(
                    "interactions.json"
                )
                try FileManager.default.createDirectory(
                    at: configuration.outputDirectory,
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(to: url, options: .atomic)
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
    ) async throws -> KvistInteractionResult {
        let repositoryURL = configuration.repositoryURL.standardizedFileURL
        try await wait(timeoutSeconds: 10) {
            model.repositoryURL?.standardizedFileURL == repositoryURL && !model.isBusy
        }
        guard let change = model.unstaged.first(where: { $0.path == largeDiffPath }) else {
            throw benchmarkError("Large diff fixture is missing from the working tree")
        }

        model.setWorkspaceMode(.fileEditor)
        _ = try await openSource(maximumSourcePath, model: model)
        _ = try await openSource(longLinePath, model: model)

        var maximumSourceOpens: [Double] = []
        var largeLineOpens: [Double] = []
        maximumSourceOpens.reserveCapacity(openSampleCount)
        largeLineOpens.reserveCapacity(openSampleCount)
        for _ in 0..<openSampleCount {
            maximumSourceOpens.append(
                try await openSource(maximumSourcePath, model: model)
            )
            largeLineOpens.append(
                try await openSource(longLinePath, model: model)
            )
        }

        var largeDiffOpens: [Double] = []
        largeDiffOpens.reserveCapacity(openSampleCount)
        var changedLineCount = 0
        for _ in 0..<openSampleCount {
            _ = try await openSource(longLinePath, model: model)
            largeDiffOpens.append(try await openDiff(change, model: model))
            changedLineCount = max(changedLineCount, changedLines(in: model.detailText))
        }

        _ = try await openSource(maximumSourcePath, model: model)
        guard let typingTextView = sourceTextView(
            expectedUTF16Length: (model.repositoryFileText as NSString).length
        ) else {
            throw benchmarkError("Could not locate the rendered source editor")
        }
        typingTextView.window?.makeFirstResponder(typingTextView)
        typingTextView.setSelectedRange(NSRange(location: 0, length: 0))
        renderApplication()
        await nextMainRunLoopTurn()
        renderApplication()
        var typing: [Double] = []
        typing.reserveCapacity(typingEditCount)
        for _ in 0..<typingEditCount {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            typingTextView.insertText("x", replacementRange: typingTextView.selectedRange())
            renderApplication()
            typing.append(milliseconds(since: startedAt))
        }
        typingTextView.string = model.savedRepositoryFileText
        model.restoreSavedRepositoryFileText()
        renderApplication()
        guard !model.isRepositoryFileDirty else {
            throw benchmarkError("Typing benchmark could not restore the source document")
        }

        _ = try await openSource(largeSourcePath, model: model)
        guard let editorScrollView = sourceTextView(
            expectedUTF16Length: (model.repositoryFileText as NSString).length
        )?.enclosingScrollView else {
            throw benchmarkError("Could not locate the large source scroll view")
        }
        let editorScroll = await measureScroll(
            editorScrollView,
            durationSeconds: scrollDurationSeconds
        )

        var lineJumps: [Double] = []
        lineJumps.reserveCapacity(lineJumpSampleCount)
        for _ in 0..<lineJumpSampleCount {
            model.openRepositoryFile(largeSourcePath, scrollToLine: 1)
            await nextMainRunLoopTurn()
            renderApplication()
            let startedAt = DispatchTime.now().uptimeNanoseconds
            model.openRepositoryFile(largeSourcePath, scrollToLine: 19_950)
            await nextMainRunLoopTurn()
            renderApplication()
            lineJumps.append(milliseconds(since: startedAt))
        }

        _ = try await openDiff(change, model: model)
        guard let diffScrollView = diffTextView()?.enclosingScrollView else {
            throw benchmarkError("Could not locate the large diff scroll view")
        }
        let diffScroll = await measureScroll(
            diffScrollView,
            durationSeconds: scrollDurationSeconds
        )

        model.closeDiffPanel()
        renderApplication()
        try await settle(model: model)
        let previewDirectoriesBefore = previewDirectories()
        let footprintBefore = try physicalFootprintBytes()

        for _ in 0..<lifecycleCycleCount {
            _ = try await openSource(maximumSourcePath, model: model)
            model.closeDiffPanel()
            renderApplication()
            _ = try await openDiff(change, model: model)
            model.closeDiffPanel()
            renderApplication()
        }

        try await settle(model: model)
        let footprintAfter = try physicalFootprintBytes()
        let previewDirectoriesAfter = previewDirectories()
        let orphanPreviews = previewDirectoriesAfter.subtracting(previewDirectoriesBefore).count
        let orphanTasks = model.hasOutstandingRepositoryTasks || model.isDetailLoading ? 1 : 0

        let maximumSourceURL = repositoryURL.appendingPathComponent(maximumSourcePath)
        let largeSourceURL = repositoryURL.appendingPathComponent(largeSourcePath)
        let longLineURL = repositoryURL.appendingPathComponent(longLinePath)
        let maximumSourceBytes = try maximumSourceURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize ?? -1
        let largeSource = try String(contentsOf: largeSourceURL, encoding: .utf8)
        let longLine = try String(contentsOf: longLineURL, encoding: .utf8)

        return KvistInteractionResult(
            maximumSourceFileBytes: maximumSourceBytes,
            largeSourceLineCount: largeSource.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count,
            longestSourceLineCharacters: longLine.count,
            largeDiffChangedLineCount: changedLineCount,
            maximumSourceOpenMilliseconds: maximumSourceOpens,
            largeLineOpenMilliseconds: largeLineOpens,
            largeDiffOpenMilliseconds: largeDiffOpens,
            typingInputToDisplayMilliseconds: typing,
            editorScroll: editorScroll,
            diffScroll: diffScroll,
            lineJumpMilliseconds: lineJumps,
            lifecycleCycleCount: lifecycleCycleCount,
            lifecycleFootprintDeltaMiB: Double(Int64(footprintAfter) - Int64(footprintBefore))
                / 1_048_576,
            orphanPreviewDirectoryCount: orphanPreviews,
            orphanTaskCount: orphanTasks
        )
    }

    private static func openSource(
        _ path: String,
        model: RepositoryModel
    ) async throws -> Double {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        model.openRepositoryFile(path)
        try await wait(timeoutSeconds: 5) {
            model.selectedRepositoryFilePath == path
                && model.detailKind == .source
                && !model.isDetailLoading
        }
        await nextMainRunLoopTurn()
        renderApplication()
        guard sourceTextView(
            expectedUTF16Length: (model.repositoryFileText as NSString).length
        ) != nil else {
            throw benchmarkError("Source view did not render for \(path)")
        }
        return milliseconds(since: startedAt)
    }

    private static func openDiff(
        _ change: FileChange,
        model: RepositoryModel
    ) async throws -> Double {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        model.select(change)
        try await wait(timeoutSeconds: 5) {
            model.selectedChange == change
                && model.detailKind == .diff
                && !model.isDetailLoading
                && diffTextView()?.isPreparingDiff == false
        }
        await nextMainRunLoopTurn()
        renderApplication()
        guard diffTextView()?.enclosingScrollView != nil else {
            throw benchmarkError("Large diff did not render")
        }
        return milliseconds(since: startedAt)
    }

    private static func changedLines(in diff: String) -> Int {
        diff.split(separator: "\n", omittingEmptySubsequences: false).count { line in
            (line.hasPrefix("+") && !line.hasPrefix("+++"))
                || (line.hasPrefix("-") && !line.hasPrefix("---"))
        }
    }

    private static func sourceTextView(expectedUTF16Length: Int) -> NSTextView? {
        applicationViews().compactMap { $0 as? NSTextView }.first {
            $0.enclosingScrollView != nil
                && !$0.isRichText
                && ($0.string as NSString).length == expectedUTF16Length
        }
    }

    private static func diffTextView() -> DiffTextView? {
        applicationViews().compactMap { $0 as? DiffTextView }.first
    }

    private static func largestScrollableView(
        excluding excluded: NSScrollView?
    ) -> NSScrollView? {
        applicationViews().compactMap { $0 as? NSScrollView }
            .filter { scrollView in
                guard scrollView !== excluded,
                      let documentView = scrollView.documentView else { return false }
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
    ) async -> KvistInteractionScrollResult {
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
        try await wait(timeoutSeconds: 10) {
            !model.hasOutstandingRepositoryTasks && !model.isDetailLoading
        }
        try await Task.sleep(for: .seconds(2))
        renderApplication()
    }

    private static func previewDirectories() -> Set<String> {
        let temporaryURL = FileManager.default.temporaryDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: temporaryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(urls.filter {
            $0.lastPathComponent.hasPrefix("Kvist-Git-Preview-")
        }.map(\.path))
    }

    private static func physicalFootprintBytes() throws -> UInt64 {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            proc_pid_rusage(
                getpid(),
                RUSAGE_INFO_V4,
                UnsafeMutableRawPointer(pointer).assumingMemoryBound(
                    to: rusage_info_t?.self
                )
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
            throw benchmarkError("Timed out waiting for interaction benchmark state")
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
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private static func milliseconds(since startedAt: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
    }

    private static func benchmarkError(_ message: String) -> NSError {
        NSError(
            domain: "KvistInteractionPerformanceInstrumentation",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    @MainActor
    private final class DisplayLinkScrollDriver: NSObject {
        private weak var scrollView: NSScrollView?
        private let requestedDuration: Double
        private let completion: (KvistInteractionScrollResult) -> Void
        private var displayLink: CADisplayLink?
        private var firstTimestamp: CFTimeInterval?
        private var lastTimestamp: CFTimeInterval?
        private var renderedFrames = 0
        private var droppedFrames = 0
        private var maximumStallMilliseconds = 0.0

        init(
            scrollView: NSScrollView,
            durationSeconds: Double,
            completion: @escaping (KvistInteractionScrollResult) -> Void
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
            guard let scrollView,
                  let documentView = scrollView.documentView else {
                finish(duration: 0)
                return
            }
            if firstTimestamp == nil {
                firstTimestamp = link.timestamp
            }
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
                let phase = (elapsed * 600).truncatingRemainder(dividingBy: maximumY * 2)
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

            if elapsed >= requestedDuration {
                finish(duration: elapsed)
            }
        }

        private func finish(duration: Double) {
            displayLink?.invalidate()
            displayLink = nil
            let totalFrames = renderedFrames + droppedFrames
            let droppedRate = totalFrames > 0
                ? Double(droppedFrames) / Double(totalFrames) * 100
                : 100
            completion(KvistInteractionScrollResult(
                durationSeconds: duration,
                renderedFrameCount: renderedFrames,
                droppedFrameCount: droppedFrames,
                droppedFrameRatePercent: droppedRate,
                maximumMainThreadStallMilliseconds: maximumStallMilliseconds
            ))
        }
    }
}

import AppKit
import SwiftUI

struct LargeSourceDocument: NSViewRepresentable, Equatable {
    let text: String
    let scrollRequest: SourceScrollRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = AppTheme.diffCanvasNSColor
        scrollView.drawsBackground = true

        let textView = LargeSourceTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textColor = AppTheme.primaryNSColor
        textView.backgroundColor = AppTheme.diffCanvasNSColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        SourceDocument.configureWrapping(in: textView, scrollView: scrollView)
        textView.setAccessibilityLabel("Large file, read only")
        textView.string = text
        scrollView.documentView = textView
        context.coordinator.scrollIfNeeded(
            scrollRequest,
            in: text,
            textView: textView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LargeSourceTextView else { return }
        textView.backgroundColor = AppTheme.diffCanvasNSColor
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.scrollIfNeeded(
            scrollRequest,
            in: text,
            textView: textView
        )
    }

    @MainActor
    final class Coordinator {
        private var lastScrollRequestID: UUID?
        private var scrollTask: Task<Void, Never>?
        private var highlightedRange: NSRange?

        func scrollIfNeeded(
            _ request: SourceScrollRequest?,
            in text: String,
            textView: LargeSourceTextView
        ) {
            guard let request, request.id != lastScrollRequestID else { return }
            lastScrollRequestID = request.id
            scrollTask?.cancel()

            let navigationTask = Task.detached(priority: .userInitiated) {
                let offset = LargeSourceNavigation.utf16Offset(
                    forLine: request.line,
                    in: text
                )
                let range = request.highlightsLine
                    ? offset.flatMap {
                        SourceDocument.highlightedRange(
                            atUTF16Offset: $0,
                            in: text
                        )
                    }
                    : nil
                return (offset, range)
            }
            scrollTask = Task { @MainActor [weak textView] in
                let result = await withTaskCancellationHandler {
                    await navigationTask.value
                } onCancel: {
                    navigationTask.cancel()
                }
                guard !Task.isCancelled,
                      let offset = result.0,
                      let textView else { return }
                updateHighlight(result.1, in: textView)
                LargeSourceDocument.reveal(utf16Offset: offset, in: textView)
            }
        }

        private func updateHighlight(
            _ range: NSRange?,
            in textView: NSTextView
        ) {
            let textStorage = textView.textStorage
            if let previousRange = highlightedRange {
                let validRange = NSIntersectionRange(
                    previousRange,
                    NSRange(location: 0, length: textStorage?.length ?? 0)
                )
                if validRange.length > 0 {
                    textStorage?.removeAttribute(
                        .backgroundColor,
                        range: validRange
                    )
                }
            }
            highlightedRange = nil
            guard let range, range.length > 0 else { return }
            textStorage?.addAttribute(
                .backgroundColor,
                value: AppTheme.selectionNSColor,
                range: range
            )
            highlightedRange = range
        }

        deinit {
            scrollTask?.cancel()
        }
    }

    /// Brings the line at `offset` to the top of the viewport, or as close to it
    /// as the document allows when the line sits in the last screenful.
    static func reveal(utf16Offset offset: Int, in textView: NSTextView) {
        // Lays out the text around the offset, which both guarantees the line is
        // on screen and makes its fragment frame exact rather than estimated.
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
        guard let scrollView = textView.enclosingScrollView,
              let lineMinY = lineMinY(atUTF16Offset: offset, in: textView) else { return }
        let clipView = scrollView.contentView
        let targetY = lineMinY + textView.textContainerInset.height
        let maximumY = max(0, textView.bounds.height - clipView.bounds.height)
        clipView.scroll(to: NSPoint(
            x: clipView.bounds.minX,
            y: min(max(0, targetY), maximumY)
        ))
        scrollView.reflectScrolledClipView(clipView)
    }

    private static func lineMinY(
        atUTF16Offset offset: Int,
        in textView: NSTextView
    ) -> CGFloat? {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let location = contentManager.location(
                contentManager.documentRange.location,
                offsetBy: offset
              ) else {
            return nil
        }
        var minY: CGFloat?
        layoutManager.enumerateTextLayoutFragments(
            from: location,
            options: [.ensuresLayout]
        ) { fragment in
            minY = fragment.layoutFragmentFrame.minY
            return false
        }
        return minY
    }
}

final class LargeSourceTextView: NSTextView {}

enum LargeSourceNavigation {
    static func utf16Offset(forLine requestedLine: Int, in text: String) -> Int? {
        guard requestedLine > 1 else { return 0 }
        let utf16 = text.utf16
        var index = utf16.startIndex
        var offset = 0
        var line = 1
        var lastLineStart = 0

        while index != utf16.endIndex {
            if offset.isMultiple(of: 16_384), Task.isCancelled {
                return nil
            }
            let character = utf16[index]
            index = utf16.index(after: index)
            offset += 1

            let isNewline: Bool
            if character == 0x0D {
                if index != utf16.endIndex, utf16[index] == 0x0A {
                    index = utf16.index(after: index)
                    offset += 1
                }
                isNewline = true
            } else {
                isNewline = character == 0x0A
                    || character == 0x0085
                    || character == 0x2028
                    || character == 0x2029
            }

            if isNewline {
                line += 1
                lastLineStart = offset
                if line == requestedLine { return offset }
            }
        }
        return lastLineStart
    }
}

import AppKit
import SwiftUI

struct DiffDocument: NSViewRepresentable, Equatable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(palette: AppTheme.palette)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = AppTheme.diffCanvasNSColor
        scrollView.drawsBackground = true

        // TextKit 2 lays out only the viewport. TextKit 1's non-contiguous layout
        // still performs enough bookkeeping for enormous diffs to stall scrolling.
        let textView = DiffTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = AppTheme.diffCanvasNSColor
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        SourceDocument.configureWrapping(in: textView, scrollView: scrollView)
        textView.setAccessibilityLabel("Diff")
        context.coordinator.attach(to: textView)
        scrollView.documentView = textView
        context.coordinator.install(text, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? DiffTextView else { return }
        textView.backgroundColor = AppTheme.diffCanvasNSColor
        guard context.coordinator.text != text else { return }
        context.coordinator.install(text, in: textView)
    }

    @MainActor
    final class Coordinator {
        var text: String?
        private var preparationTask: Task<Void, Never>?
        private let contentDelegate: DiffTextContentDelegate

        init(palette: AppThemePalette) {
            contentDelegate = DiffTextContentDelegate(palette: palette)
        }

        func attach(to textView: DiffTextView) {
            guard let contentStorage = textView.textLayoutManager?
                .textContentManager as? NSTextContentStorage else { return }
            contentStorage.delegate = contentDelegate
        }

        func install(_ text: String, in textView: DiffTextView) {
            self.text = text
            preparationTask?.cancel()
            textView.isPreparingDiff = true
            textView.string = "Preparing diff…"

            let formattingTask = Task.detached(priority: .userInitiated) {
                DiffDocumentFormatter.formattedText(for: text)
            }
            preparationTask = Task { @MainActor [weak self, weak textView] in
                let formatted = await withTaskCancellationHandler {
                    await formattingTask.value
                } onCancel: {
                    formattingTask.cancel()
                }
                guard !Task.isCancelled,
                      let formatted,
                      let self,
                      let textView,
                      self.text == text else { return }
                textView.string = formatted
                textView.isPreparingDiff = false
                textView.scrollToBeginningOfDocument(nil)
            }
        }

        deinit {
            preparationTask?.cancel()
        }
    }
}

final class DiffTextView: NSTextView {
    var isPreparingDiff = false
}

enum DiffDocumentFormatter {
    static func formattedText(for text: String) -> String? {
        var output = String()
        output.reserveCapacity(text.utf8.count + min(text.utf8.count, 16_777_216))
        var oldLine: Int?
        var newLine: Int?
        var sourceLineStart = text.startIndex
        var displayLine = 0

        while true {
            if displayLine.isMultiple(of: 1_024), Task.isCancelled {
                return nil
            }
            let remainder = text[sourceLineStart...]
            let newline = remainder.firstIndex(of: "\n")
            let sourceLineEnd = newline ?? text.endIndex
            let line = text[sourceLineStart..<sourceLineEnd]

            if line.hasPrefix("@@") {
                let components = line.split(separator: " ")
                if components.count >= 3 {
                    oldLine = lineStart(from: components[1])
                    newLine = lineStart(from: components[2])
                }
                append(line, oldLine: nil, newLine: nil, to: &output)
            } else if line.hasPrefix("diff --git")
                        || line.hasPrefix("index ")
                        || line.hasPrefix("--- ")
                        || line.hasPrefix("+++ ") {
                append(line, oldLine: nil, newLine: nil, to: &output)
            } else if line.hasPrefix("+") {
                append(line, oldLine: nil, newLine: newLine, to: &output)
                if newLine != nil { newLine! += 1 }
            } else if line.hasPrefix("-") {
                append(line, oldLine: oldLine, newLine: nil, to: &output)
                if oldLine != nil { oldLine! += 1 }
            } else if line.hasPrefix(" ") {
                append(line, oldLine: oldLine, newLine: newLine, to: &output)
                if oldLine != nil { oldLine! += 1 }
                if newLine != nil { newLine! += 1 }
            } else {
                append(line, oldLine: nil, newLine: nil, to: &output)
            }

            displayLine += 1
            guard let newline else { break }
            sourceLineStart = text.index(after: newline)
        }
        return output
    }

    private static func append(
        _ line: Substring,
        oldLine: Int?,
        newLine: Int?,
        to output: inout String
    ) {
        output.append("\t")
        if let oldLine { output.append(String(oldLine)) }
        output.append("\t")
        if let newLine { output.append(String(newLine)) }
        output.append("\t▏\t")
        if line.isEmpty {
            output.append(" ")
        } else {
            output.append(contentsOf: line)
        }
        output.append("\n")
    }

    private static func lineStart(from component: Substring) -> Int? {
        Int(
            component
                .dropFirst()
                .split(separator: ",", maxSplits: 1)
                .first
                ?? ""
        )
    }
}

private final class DiffTextContentDelegate: NSObject, NSTextContentStorageDelegate {
    private enum Kind {
        case header
        case hunk
        case added
        case removed
        case context
        case metadata
    }

    private let palette: AppThemePalette
    private let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    private let paragraph: NSParagraphStyle

    init(palette: AppThemePalette) {
        self.palette = palette
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18
        paragraph.maximumLineHeight = 18
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: 32),
            NSTextTab(textAlignment: .right, location: 68),
            NSTextTab(textAlignment: .left, location: 78),
            NSTextTab(textAlignment: .left, location: 90)
        ]
        paragraph.defaultTabInterval = 28
        paragraph.headIndent = 90
        paragraph.firstLineHeadIndent = 0
        self.paragraph = paragraph
    }

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let backing = textContentStorage.attributedString,
              range.location >= 0,
              NSMaxRange(range) <= backing.length else { return nil }
        let line = NSMutableAttributedString(
            attributedString: backing.attributedSubstring(from: range)
        )
        let fullRange = NSRange(location: 0, length: line.length)
        line.addAttributes([
            .font: font,
            .foregroundColor: NSColor(hex: palette.muted),
            .paragraphStyle: paragraph
        ], range: fullRange)

        let plainLine = line.string as NSString
        let markerRange = plainLine.range(of: "▏")
        guard markerRange.location != NSNotFound else {
            return NSTextParagraph(attributedString: line)
        }
        let contentLocation = min(NSMaxRange(markerRange) + 1, plainLine.length)
        let contentRange = NSRange(
            location: contentLocation,
            length: plainLine.length - contentLocation
        )
        let content = plainLine.substring(with: contentRange)
        let kind = kind(for: content)

        if let background = backgroundColor(for: kind) {
            line.addAttribute(.backgroundColor, value: background, range: fullRange)
        }
        line.addAttribute(
            .foregroundColor,
            value: foregroundColor(for: kind),
            range: contentRange
        )
        if let marker = markerColor(for: kind) {
            line.addAttribute(.foregroundColor, value: marker, range: markerRange)
        }
        return NSTextParagraph(attributedString: line)
    }

    private func kind(for content: String) -> Kind {
        if content.hasPrefix("@@") { return .hunk }
        if content.hasPrefix("diff --git")
            || content.hasPrefix("index ")
            || content.hasPrefix("--- ")
            || content.hasPrefix("+++ ") {
            return .header
        }
        if content.hasPrefix("+") { return .added }
        if content.hasPrefix("-") { return .removed }
        if content.hasPrefix(" ") { return .context }
        return .metadata
    }

    private func foregroundColor(for kind: Kind) -> NSColor {
        switch kind {
        case .header: return NSColor(hex: palette.diffHeaderText)
        case .hunk: return NSColor(hex: palette.diffHunkText)
        case .added: return NSColor(hex: palette.diffAddedText)
        case .removed: return NSColor(hex: palette.diffRemovedText)
        case .context, .metadata: return NSColor(hex: palette.primary)
        }
    }

    private func backgroundColor(for kind: Kind) -> NSColor? {
        switch kind {
        case .hunk: return NSColor(hex: palette.diffHunkBackground)
        case .added: return NSColor(hex: palette.diffAddedBackground)
        case .removed: return NSColor(hex: palette.diffRemovedBackground)
        case .header, .context, .metadata: return nil
        }
    }

    private func markerColor(for kind: Kind) -> NSColor? {
        switch kind {
        case .added: return NSColor(hex: palette.added)
        case .removed: return NSColor(hex: palette.deleted)
        case .hunk: return NSColor(hex: palette.graphBlue)
        case .header, .context, .metadata: return nil
        }
    }
}

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
                DiffDocumentFormatter.formattedDocument(for: text)
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
                let attributed = NSMutableAttributedString(string: formatted.text)
                for range in formatted.emphasisRanges {
                    attributed.addAttribute(.diffEmphasis, value: true, range: range)
                }
                textView.textStorage?.setAttributedString(attributed)
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

extension NSAttributedString.Key {
    /// Marks the characters within a changed line that differ from the line
    /// it was paired with, so the renderer can emphasize them.
    static let diffEmphasis = NSAttributedString.Key("KvistDiffEmphasis")
}

/// The rendered diff text plus the UTF-16 ranges (in that text) to emphasize
/// as character-level changes.
struct DiffFormattedDocument: Equatable {
    let text: String
    let emphasisRanges: [NSRange]
}

enum DiffDocumentFormatter {
    /// A removed or added line awaiting pairing with its counterpart in the
    /// same change block. `contentStart` is the UTF-16 offset in the output
    /// of the line's first character after the `+`/`-` marker.
    private struct PendingLine {
        let content: Substring
        let contentStart: Int
    }

    static func formattedText(for text: String) -> String? {
        formattedDocument(for: text)?.text
    }

    static func formattedDocument(for text: String) -> DiffFormattedDocument? {
        var output = String()
        output.reserveCapacity(text.utf8.count + min(text.utf8.count, 16_777_216))
        var outputLength = 0
        var emphasisRanges: [NSRange] = []
        var oldLine: Int?
        var newLine: Int?
        var sourceLineStart = text.startIndex
        var displayLine = 0
        var pendingRemoved: [PendingLine] = []
        var pendingAdded: [PendingLine] = []

        func flushPendingPairs() {
            guard !pendingRemoved.isEmpty, !pendingAdded.isEmpty else {
                pendingRemoved.removeAll()
                pendingAdded.removeAll()
                return
            }
            for (removed, added) in zip(pendingRemoved, pendingAdded) {
                let changes = DiffLineComparer.changedRanges(
                    removed: removed.content,
                    added: added.content
                )
                emphasisRanges += changes.removed.map {
                    NSRange(location: removed.contentStart + $0.location, length: $0.length)
                }
                emphasisRanges += changes.added.map {
                    NSRange(location: added.contentStart + $0.location, length: $0.length)
                }
            }
            pendingRemoved.removeAll()
            pendingAdded.removeAll()
        }

        while true {
            if displayLine.isMultiple(of: 1_024), Task.isCancelled {
                return nil
            }
            let remainder = text[sourceLineStart...]
            let newline = remainder.firstIndex(of: "\n")
            let sourceLineEnd = newline ?? text.endIndex
            let line = text[sourceLineStart..<sourceLineEnd]

            if line.hasPrefix("@@") {
                flushPendingPairs()
                let components = line.split(separator: " ")
                if components.count >= 3 {
                    oldLine = lineStart(from: components[1])
                    newLine = lineStart(from: components[2])
                }
                append(line, oldLine: nil, newLine: nil, to: &output, length: &outputLength)
            } else if line.hasPrefix("diff --git")
                        || line.hasPrefix("index ")
                        || line.hasPrefix("--- ")
                        || line.hasPrefix("+++ ") {
                flushPendingPairs()
                append(line, oldLine: nil, newLine: nil, to: &output, length: &outputLength)
            } else if line.hasPrefix("+") {
                let contentStart = append(
                    line, oldLine: nil, newLine: newLine, to: &output, length: &outputLength
                )
                if !pendingRemoved.isEmpty {
                    pendingAdded.append(PendingLine(
                        content: line.dropFirst(),
                        contentStart: contentStart + 1
                    ))
                }
                if newLine != nil { newLine! += 1 }
            } else if line.hasPrefix("-") {
                // A removed line after added lines starts a new change block.
                if !pendingAdded.isEmpty { flushPendingPairs() }
                let contentStart = append(
                    line, oldLine: oldLine, newLine: nil, to: &output, length: &outputLength
                )
                pendingRemoved.append(PendingLine(
                    content: line.dropFirst(),
                    contentStart: contentStart + 1
                ))
                if oldLine != nil { oldLine! += 1 }
            } else if line.hasPrefix(" ") {
                flushPendingPairs()
                append(line, oldLine: oldLine, newLine: newLine, to: &output, length: &outputLength)
                if oldLine != nil { oldLine! += 1 }
                if newLine != nil { newLine! += 1 }
            } else {
                // "\ No newline at end of file" sits inside a change block
                // without ending it.
                if !line.hasPrefix("\\") { flushPendingPairs() }
                append(line, oldLine: nil, newLine: nil, to: &output, length: &outputLength)
            }

            displayLine += 1
            guard let newline else { break }
            sourceLineStart = text.index(after: newline)
        }
        flushPendingPairs()
        return DiffFormattedDocument(text: output, emphasisRanges: emphasisRanges)
    }

    /// Appends one display line and returns the UTF-16 offset of the line's
    /// content (the diff marker character) in the output.
    @discardableResult
    private static func append(
        _ line: Substring,
        oldLine: Int?,
        newLine: Int?,
        to output: inout String,
        length: inout Int
    ) -> Int {
        output.append("\t")
        length += 1
        if let oldLine {
            let text = String(oldLine)
            output.append(text)
            length += text.utf16.count
        }
        output.append("\t")
        length += 1
        if let newLine {
            let text = String(newLine)
            output.append(text)
            length += text.utf16.count
        }
        output.append("\t▏\t")
        length += 3
        let contentStart = length
        if line.isEmpty {
            output.append(" ")
            length += 1
        } else {
            output.append(contentsOf: line)
            length += line.utf16.count
        }
        output.append("\n")
        length += 1
        return contentStart
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

/// Character-level comparison of a removed line with the added line that
/// replaced it. Lines are split into words, whitespace runs, and single
/// punctuation marks; a longest-common-subsequence over those tokens finds
/// the parts that actually changed, which is what makes a one-space edit
/// visible. Ranges are UTF-16 offsets within each line's content.
enum DiffLineComparer {
    struct Changes: Equatable {
        let removed: [NSRange]
        let added: [NSRange]
    }

    /// Token pairs beyond this product fall back to a prefix/suffix scan so
    /// pathological lines never stall diff preparation.
    private static let maximumTokenProduct = 250_000

    /// Pairs whose tokens are almost entirely different get no emphasis:
    /// a fully highlighted line reads worse than the plain colored line.
    private static let maximumChangedFraction = 0.75

    static func changedRanges(removed: Substring, added: Substring) -> Changes {
        let removedTokens = tokenize(removed)
        let addedTokens = tokenize(added)
        guard !removedTokens.isEmpty, !addedTokens.isEmpty else {
            return Changes(removed: [], added: [])
        }

        let removedChanged: [Bool]
        let addedChanged: [Bool]
        if removedTokens.count * addedTokens.count <= maximumTokenProduct {
            (removedChanged, addedChanged) = subsequenceChanges(removedTokens, addedTokens)
        } else {
            (removedChanged, addedChanged) = affixChanges(removedTokens, addedTokens)
        }

        let removedRanges = ranges(of: removedChanged, tokens: removedTokens)
        let addedRanges = ranges(of: addedChanged, tokens: addedTokens)
        let removedLength = removed.utf16.count
        let addedLength = added.utf16.count
        let changedLength = removedRanges.reduce(0) { $0 + $1.length }
            + addedRanges.reduce(0) { $0 + $1.length }
        let totalLength = removedLength + addedLength
        guard totalLength > 0,
              Double(changedLength) / Double(totalLength) <= maximumChangedFraction else {
            return Changes(removed: [], added: [])
        }
        return Changes(removed: removedRanges, added: addedRanges)
    }

    private struct Token: Equatable {
        let text: Substring.UTF16View.SubSequence
        let location: Int
        let length: Int

        static func == (lhs: Token, rhs: Token) -> Bool {
            lhs.length == rhs.length && lhs.text.elementsEqual(rhs.text)
        }
    }

    private enum TokenClass {
        case word, whitespace, punctuation
    }

    private static func tokenClass(_ unit: UInt16) -> TokenClass {
        if unit == 0x20 || unit == 0x09 { return .whitespace }
        if unit < 0x80 {
            let scalar = Unicode.Scalar(UInt8(unit))
            if CharacterSet.alphanumerics.contains(scalar) || unit == 0x5F {
                return .word
            }
            return .punctuation
        }
        return .word
    }

    private static func tokenize(_ line: Substring) -> [Token] {
        let units = line.utf16
        var tokens: [Token] = []
        var index = units.startIndex
        var offset = 0
        while index < units.endIndex {
            let unitClass = tokenClass(units[index])
            var end = units.index(after: index)
            var length = 1
            if unitClass != .punctuation {
                while end < units.endIndex, tokenClass(units[end]) == unitClass {
                    end = units.index(after: end)
                    length += 1
                }
            }
            tokens.append(Token(text: units[index..<end], location: offset, length: length))
            offset += length
            index = end
        }
        return tokens
    }

    private static func subsequenceChanges(
        _ lhs: [Token],
        _ rhs: [Token]
    ) -> ([Bool], [Bool]) {
        let rows = lhs.count, columns = rhs.count
        var table = [Int](repeating: 0, count: (rows + 1) * (columns + 1))
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1) {
                let index = row * (columns + 1) + column
                if lhs[row] == rhs[column] {
                    table[index] = table[index + columns + 2] + 1
                } else {
                    table[index] = max(table[index + columns + 1], table[index + 1])
                }
            }
        }
        var lhsChanged = [Bool](repeating: true, count: rows)
        var rhsChanged = [Bool](repeating: true, count: columns)
        var row = 0, column = 0
        while row < rows, column < columns {
            if lhs[row] == rhs[column] {
                lhsChanged[row] = false
                rhsChanged[column] = false
                row += 1
                column += 1
            } else if table[(row + 1) * (columns + 1) + column]
                        >= table[row * (columns + 1) + column + 1] {
                row += 1
            } else {
                column += 1
            }
        }
        return (lhsChanged, rhsChanged)
    }

    private static func affixChanges(
        _ lhs: [Token],
        _ rhs: [Token]
    ) -> ([Bool], [Bool]) {
        var prefix = 0
        while prefix < lhs.count, prefix < rhs.count, lhs[prefix] == rhs[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < lhs.count - prefix,
              suffix < rhs.count - prefix,
              lhs[lhs.count - 1 - suffix] == rhs[rhs.count - 1 - suffix] {
            suffix += 1
        }
        var lhsChanged = [Bool](repeating: false, count: lhs.count)
        var rhsChanged = [Bool](repeating: false, count: rhs.count)
        for index in prefix..<(lhs.count - suffix) { lhsChanged[index] = true }
        for index in prefix..<(rhs.count - suffix) { rhsChanged[index] = true }
        return (lhsChanged, rhsChanged)
    }

    /// Merges consecutive changed tokens into single ranges.
    private static func ranges(of changed: [Bool], tokens: [Token]) -> [NSRange] {
        var ranges: [NSRange] = []
        var current: NSRange?
        for (index, token) in tokens.enumerated() where changed[index] {
            if let range = current, NSMaxRange(range) == token.location {
                current = NSRange(location: range.location, length: range.length + token.length)
            } else {
                if let range = current { ranges.append(range) }
                current = NSRange(location: token.location, length: token.length)
            }
        }
        if let range = current { ranges.append(range) }
        return ranges
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
        if let emphasis = emphasisColor(for: kind) {
            line.enumerateAttribute(.diffEmphasis, in: contentRange) { value, range, _ in
                guard value != nil else { return }
                line.addAttribute(.backgroundColor, value: emphasis, range: range)
            }
        }
        return NSTextParagraph(attributedString: line)
    }

    /// A stronger tint over the line background for the characters that
    /// actually changed.
    private func emphasisColor(for kind: Kind) -> NSColor? {
        switch kind {
        case .added: return NSColor(hex: palette.added).withAlphaComponent(0.32)
        case .removed: return NSColor(hex: palette.deleted).withAlphaComponent(0.32)
        case .header, .hunk, .context, .metadata: return nil
        }
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

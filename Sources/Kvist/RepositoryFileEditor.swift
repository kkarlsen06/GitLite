import AppKit
import Foundation
import QuickLookUI
import SwiftUI

struct SourceDocument: NSViewRepresentable {
    @Binding var text: String
    let scrollRequest: SourceScrollRequest?
    let isEditable: Bool
    let onSave: () -> Void
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    static func configureWrapping(
        in textView: NSTextView,
        scrollView: NSScrollView
    ) {
        scrollView.hasHorizontalScroller = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = AppTheme.diffCanvasNSColor
        scrollView.drawsBackground = true

        let textView = SourceTextView()
        // Force TextKit 1 before any layout: the line-number ruler queries
        // `layoutManager`, and a lazy downgrade after rendering starts leaves
        // the text view blank.
        _ = textView.layoutManager
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.onExit = onExit
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textColor = AppTheme.primaryNSColor
        textView.insertionPointColor = AppTheme.primaryNSColor
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
        Self.configureWrapping(in: textView, scrollView: scrollView)
        // Install content only after the plain-text attributes and automatic
        // substitutions are configured. Applying each of those properties to
        // an existing maximum-size document forces repeated full-storage edits.
        textView.string = text
        textView.updateConflictPresentation()
        scrollView.documentView = textView

        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.scrollIfNeeded(
            scrollRequest,
            in: textView,
            scrollView: scrollView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SourceTextView else { return }
        textView.onSave = onSave
        textView.onExit = onExit
        textView.isEditable = isEditable
        var replacedText = false
        if textView.string != text {
            let selection = textView.selectedRanges
            context.coordinator.isApplyingExternalText = true
            textView.string = text
            replacedText = true
            textView.selectedRanges = Self.clampedSelectionRanges(
                selection,
                textLength: (text as NSString).length
            )
            context.coordinator.isApplyingExternalText = false
            (scrollView.verticalRulerView as? LineNumberRulerView)?
                .invalidateLineNumbers()
        }
        textView.updateConflictPresentation(reparse: replacedText)
        context.coordinator.scrollIfNeeded(
            scrollRequest,
            in: textView,
            scrollView: scrollView
        )
    }

    static func clampedSelectionRanges(
        _ ranges: [NSValue],
        textLength: Int
    ) -> [NSValue] {
        ranges.map { value in
            let range = value.rangeValue
            let location = min(max(0, range.location), textLength)
            let length = min(max(0, range.length), textLength - location)
            return NSValue(range: NSRange(location: location, length: length))
        }
    }

    nonisolated static func highlightedRange(
        forLine line: Int,
        in text: String
    ) -> NSRange? {
        guard let offset = LargeSourceNavigation.utf16Offset(
            forLine: line,
            in: text
        ) else {
            return nil
        }
        return highlightedRange(atUTF16Offset: offset, in: text)
    }

    nonisolated static func highlightedRange(
        atUTF16Offset offset: Int,
        in text: String
    ) -> NSRange? {
        let content = text as NSString
        guard content.length > 0 else { return nil }
        let location = min(max(0, offset), content.length - 1)
        return content.lineRange(for: NSRange(location: location, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        var isApplyingExternalText = false
        private var lastScrollRequestID: UUID?
        private var highlightedRange: NSRange?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText,
                  let textView = notification.object as? NSTextView else { return }
            (textView as? SourceTextView)?.updateConflictPresentation()
            text = textView.string
        }

        func scrollIfNeeded(
            _ request: SourceScrollRequest?,
            in textView: NSTextView,
            scrollView: NSScrollView
        ) {
            guard let request, request.id != lastScrollRequestID else { return }
            lastScrollRequestID = request.id

            DispatchQueue.main.async { [weak self, weak textView, weak scrollView] in
                guard let self, let textView, let scrollView else { return }
                self.updateHighlight(
                    for: request,
                    in: textView
                )
                SourceDocument.scroll(
                    toLine: request.line,
                    in: textView,
                    scrollView: scrollView
                )
            }
        }

        private func updateHighlight(
            for request: SourceScrollRequest,
            in textView: NSTextView
        ) {
            guard let layoutManager = textView.layoutManager else { return }
            if let previousRange = highlightedRange {
                let validRange = NSIntersectionRange(
                    previousRange,
                    NSRange(location: 0, length: (textView.string as NSString).length)
                )
                if validRange.length > 0 {
                    layoutManager.removeTemporaryAttribute(
                        .backgroundColor,
                        forCharacterRange: validRange
                    )
                }
            }
            highlightedRange = nil

            guard request.highlightsLine,
                  let range = SourceDocument.highlightedRange(
                    forLine: request.line,
                    in: textView.string
                  ),
                  range.length > 0 else {
                return
            }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: AppTheme.selectionNSColor,
                forCharacterRange: range
            )
            highlightedRange = range
        }
    }

    static func scroll(
        toLine requestedLine: Int,
        in textView: NSTextView,
        scrollView: NSScrollView
    ) {
        let content = textView.string as NSString
        guard content.length > 0,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let characterIndex = (scrollView.verticalRulerView as? LineNumberRulerView)?
            .characterIndex(forLine: requestedLine, in: content)
            ?? LargeSourceNavigation.utf16Offset(forLine: requestedLine, in: textView.string)
            ?? 0

        let targetCharacter = min(characterIndex, content.length - 1)
        // Non-contiguous layout only estimates the height of text it has not
        // reached yet, so the position of a line deep in the file can be off by
        // dozens of lines. Lay out everything above the target — the layout is
        // cached, so later jumps into the same document stay cheap.
        layoutManager.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: targetCharacter + 1)
        )
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: targetCharacter)
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        let inset = textView.textContainerInset.height
        let targetY = max(0, lineRect.minY + inset)
        let clipView = scrollView.contentView
        var documentHeight = documentHeight(
            of: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
        if targetY > documentHeight - clipView.bounds.height {
            // The line sits in the last screenful, so the scroll gets clamped to
            // the bottom of the document. That only reveals the line when the
            // height below it is real rather than estimated.
            layoutManager.ensureLayout(
                forCharacterRange: NSRange(
                    location: targetCharacter,
                    length: content.length - targetCharacter
                )
            )
            documentHeight = self.documentHeight(
                of: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }
        let maximumY = max(0, documentHeight - clipView.bounds.height)
        clipView.scroll(to: NSPoint(
            x: clipView.bounds.minX,
            y: min(targetY, maximumY)
        ))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// The scrollable height of `textView`, growing its frame when layout has
    /// produced more text than the frame currently accounts for.
    private static func documentHeight(
        of textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> CGFloat {
        let laidOutHeight = layoutManager.usedRect(for: textContainer).maxY
            + textView.textContainerInset.height * 2
        guard laidOutHeight > textView.bounds.height else {
            return textView.bounds.height
        }
        textView.setFrameSize(NSSize(
            width: textView.frame.width,
            height: laidOutHeight
        ))
        return laidOutHeight
    }
}

final class LineNumberRulerView: NSRulerView, NSTextStorageDelegate {
    private weak var textView: NSTextView?
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(
            scrollView: textView.enclosingScrollView,
            orientation: .verticalRuler
        )
        clientView = textView
        ruleThickness = 40
        textView.textStorage?.delegate = self
        // The ruler's drawable region extends past its frame (scroll offsets
        // shift its bounds, and AppKit no longer clips subview drawing), which
        // lets gutter paint spill over the editor and its header.
        clipsToBounds = true

    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        updateLineStarts(
            afterEditing: textStorage.string as NSString,
            editedRange: editedRange,
            changeInLength: delta
        )
        needsDisplay = true
    }

    func invalidateLineNumbers() {
        cachedLineStarts = nil
        needsDisplay = true
    }

    func characterIndex(forLine requestedLine: Int, in text: NSString) -> Int {
        let lineStarts: [Int]
        if let cachedLineStarts {
            lineStarts = cachedLineStarts
        } else {
            lineStarts = makeLineStarts(in: text)
            cachedLineStarts = lineStarts
        }
        let lineIndex = min(max(0, requestedLine - 1), lineStarts.count - 1)
        return lineStarts[lineIndex]
    }

    private var cachedLineStarts: [Int]?

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // The dirty rect can extend past this view's bounds (views no longer
        // clip subview drawing by default); painting it all would cover the
        // text view. Restrict every draw to the gutter itself.
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        AppTheme.diffCanvasNSColor.setFill()
        bounds.fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let content = textView.string as NSString
        let lineStarts: [Int]
        if let cachedLineStarts {
            lineStarts = cachedLineStarts
        } else {
            lineStarts = makeLineStarts(in: content)
            cachedLineStarts = lineStarts
        }
        updateThickness(forLineCount: lineStarts.count)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: AppTheme.mutedNSColor
        ]
        let relativePoint = convert(NSPoint.zero, from: textView)
        let visibleGlyphs = layoutManager.glyphRange(
            forBoundingRect: textView.visibleRect,
            in: textContainer
        )
        let visibleCharacters = layoutManager.characterRange(
            forGlyphRange: visibleGlyphs,
            actualGlyphRange: nil
        )

        var lineIndex = lineIndex(
            containing: visibleCharacters.location,
            lineStarts: lineStarts
        )
        let visibleEnd = NSMaxRange(visibleCharacters)

        while lineIndex < lineStarts.count {
            let characterIndex = lineStarts[lineIndex]
            guard characterIndex < content.length,
                  characterIndex <= visibleEnd else { break }
            let nextLineStart = lineIndex + 1 < lineStarts.count
                ? lineStarts[lineIndex + 1]
                : content.length
            let lineRange = NSRange(
                location: characterIndex,
                length: max(0, nextLineStart - characterIndex)
            )
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange,
                actualCharacterRange: nil
            )
            var effectiveRange = NSRange(location: 0, length: 0)
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: &effectiveRange
            )
            draw(
                lineNumber: lineIndex + 1,
                atYPosition: fragmentRect.minY + relativePoint.y
                    + textView.textContainerInset.height,
                attributes: attributes
            )
            lineIndex += 1
        }

        if hasTrailingEmptyLine(in: content) || content.length == 0 {
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                draw(
                    lineNumber: lineStarts.count,
                    atYPosition: extraRect.minY + relativePoint.y
                        + textView.textContainerInset.height,
                    attributes: attributes
                )
            }
        }
    }

    private func draw(
        lineNumber: Int,
        atYPosition yPosition: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let label = "\(lineNumber)" as NSString
        let size = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: ruleThickness - size.width - 6, y: yPosition),
            withAttributes: attributes
        )
    }

    private func updateThickness(forLineCount lineCount: Int) {
        let digits = max("\(lineCount)".count, 2)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: numberFont]).width
        let thickness = max(ceil(width) + 14, 30)
        if abs(thickness - ruleThickness) > 0.5 {
            ruleThickness = thickness
        }
    }

    private func makeLineStarts(in text: NSString) -> [Int] {
        var starts = [0]
        guard text.length > 0 else { return starts }
        starts.reserveCapacity(min(20_001, max(1, text.length / 40)))
        let characters = UnsafeMutableBufferPointer<unichar>.allocate(
            capacity: text.length
        )
        defer { characters.deallocate() }
        text.getCharacters(
            characters.baseAddress!,
            range: NSRange(location: 0, length: text.length)
        )

        var index = 0
        while index < text.length {
            let character = characters[index]
            if character == 0x0D {
                index += 1
                if index < text.length, characters[index] == 0x0A {
                    index += 1
                }
                starts.append(index)
            } else if character == 0x0A
                || character == 0x0085
                || character == 0x2028
                || character == 0x2029 {
                index += 1
                starts.append(index)
            } else {
                index += 1
            }
        }
        return starts
    }

    private func updateLineStarts(
        afterEditing text: NSString,
        editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard let oldStarts = cachedLineStarts, !oldStarts.isEmpty else { return }

        let oldEditedLength = max(0, editedRange.length - delta)
        let oldEditedEnd = editedRange.location + oldEditedLength
        // Include the preceding line because an edit at a line boundary can
        // create or split a CRLF pair and move that boundary.
        let anchorIndex = max(0, lineIndex(
            containing: editedRange.location,
            lineStarts: oldStarts
        ) - 1)
        let anchorStart = oldStarts[anchorIndex]
        let suffixIndex = firstLineIndex(
            after: oldEditedEnd,
            lineStarts: oldStarts
        )
        let scanEnd = suffixIndex < oldStarts.count
            ? oldStarts[suffixIndex] + delta
            : text.length
        guard anchorStart <= scanEnd,
              scanEnd <= text.length else {
            cachedLineStarts = nil
            return
        }

        var updated = Array(oldStarts[..<anchorIndex])
        updated.append(anchorStart)
        var index = anchorStart
        while index < scanEnd {
            let lineRange = text.lineRange(
                for: NSRange(location: index, length: 0)
            )
            let nextIndex = NSMaxRange(lineRange)
            guard nextIndex > index, nextIndex <= scanEnd else {
                cachedLineStarts = nil
                return
            }
            if nextIndex < scanEnd
                || (suffixIndex == oldStarts.count
                    && nextIndex == text.length
                    && hasTrailingEmptyLine(in: text)) {
                updated.append(nextIndex)
            }
            index = nextIndex
        }

        if suffixIndex < oldStarts.count {
            for oldStart in oldStarts[suffixIndex...] {
                let shiftedStart = oldStart + delta
                if updated.last != shiftedStart {
                    updated.append(shiftedStart)
                }
            }
        }
        cachedLineStarts = updated
    }

    private func firstLineIndex(after location: Int, lineStarts: [Int]) -> Int {
        var lowerBound = 0
        var upperBound = lineStarts.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if lineStarts[middle] <= location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func lineIndex(containing location: Int, lineStarts: [Int]) -> Int {
        var lowerBound = 0
        var upperBound = lineStarts.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if lineStarts[middle] <= location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return max(0, lowerBound - 1)
    }

    private func hasTrailingEmptyLine(in text: NSString) -> Bool {
        guard text.length > 0 else { return false }
        let lastCharacter = text.character(at: text.length - 1)
        return lastCharacter == 0x0A || lastCharacter == 0x0D
    }
}

private final class SourceTextView: NSTextView {
    var onSave: (() -> Void)?
    var onExit: (() -> Void)?
    private var conflictDecorations: [ConflictEditorDecoration] = []
    private var hasAcceptedMouseInteraction = false

    func updateConflictPresentation(reparse: Bool = true) {
        guard let layoutManager else { return }
        let textLength = (string as NSString).length

        for decoration in conflictDecorations where decoration.kind.setsTextAttributes {
            let range = decoration.range.clamped(toLength: textLength)
            guard range.length > 0 else { continue }
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            layoutManager.removeTemporaryAttribute(.font, forCharacterRange: range)
        }

        if reparse {
            conflictDecorations = ConflictEditorPresentation.decorations(for: string)
        }

        let markerFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        for decoration in conflictDecorations where decoration.kind.setsTextAttributes {
            let range = decoration.range.clamped(toLength: textLength)
            guard range.length > 0 else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: decoration.kind.foregroundColor
            ]
            if decoration.kind.isMarker {
                attributes[.font] = markerFont
            }
            layoutManager.addTemporaryAttributes(attributes, forCharacterRange: range)
        }
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard !conflictDecorations.isEmpty,
              let layoutManager else { return }

        let textLength = (string as NSString).length
        let origin = textContainerOrigin
        let visible = visibleRect
        for decoration in conflictDecorations {
            let characterRange = decoration.range.clamped(toLength: textLength)
            guard characterRange.length > 0 else { continue }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )

            var regionTop = CGFloat.greatestFiniteMagnitude
            var regionBottom = -CGFloat.greatestFiniteMagnitude
            var markerLineRect: NSRect?
            decoration.kind.backgroundColor.setFill()
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] lineRect, _, _, _, _ in
                guard let self else { return }
                let rowRect = NSRect(
                    x: self.bounds.minX,
                    y: lineRect.minY + origin.y,
                    width: self.bounds.width,
                    height: lineRect.height
                )
                regionTop = min(regionTop, rowRect.minY)
                regionBottom = max(regionBottom, rowRect.maxY)
                if markerLineRect == nil { markerLineRect = rowRect }
                let fillRect = rowRect.intersection(rect)
                if !fillRect.isEmpty {
                    fillRect.fill()
                }
            }
            guard regionBottom > regionTop else { continue }

            // A side-colored spine at the viewport edge keeps each region
            // identifiable even where the row tint is subtle.
            let bar = NSRect(
                x: visible.minX,
                y: regionTop,
                width: 3,
                height: regionBottom - regionTop
            ).intersection(rect)
            if !bar.isEmpty {
                decoration.kind.accentColor.setFill()
                bar.fill()
            }

            // Plain-language labels so marker lines don't require knowing
            // Git's <<<<<<< / ======= / >>>>>>> syntax.
            if let annotation = decoration.kind.annotation,
               let markerLineRect,
               markerLineRect.intersects(rect) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                    .foregroundColor: decoration.kind.foregroundColor
                        .withAlphaComponent(0.9)
                ]
                let size = (annotation as NSString).size(withAttributes: attributes)
                (annotation as NSString).draw(
                    at: NSPoint(
                        x: visible.maxX - size.width - 12,
                        y: markerLineRect.minY
                            + (markerLineRect.height - size.height) / 2
                    ),
                    withAttributes: attributes
                )
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        hasAcceptedMouseInteraction = false
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let shortcutModifiers = event.modifierFlags.intersection([
            .command,
            .control,
            .option,
            .shift
        ])
        if event.keyCode == 53, shortcutModifiers.isEmpty {
            onExit?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // Ending the search field's editing session can send a cancel command
        // through the editor that just became first responder. Only treat
        // Escape as navigation after the responder handoff has settled.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(100)
        ) { [weak self] in
            self?.hasAcceptedMouseInteraction = true
        }
    }

    override func cancelOperation(_ sender: Any?) {
        guard hasAcceptedMouseInteraction else { return }
        onExit?()
    }
}

private extension ConflictEditorRegionKind {
    var isMarker: Bool {
        switch self {
        case .currentMarker, .ancestorMarker, .separator, .incomingMarker:
            return true
        case .currentContent, .ancestorContent, .incomingContent:
            return false
        }
    }

    /// Marker lines restyle text and font; ancestor content only dims, so it
    /// reads as reference material rather than a version you can pick.
    var setsTextAttributes: Bool {
        isMarker || self == .ancestorContent
    }

    /// One hue per side, everywhere: blue is the current branch's side, green
    /// is the incoming side, gray is the common ancestor. The resolver panes
    /// use the same assignments.
    var accentColor: NSColor {
        switch self {
        case .currentMarker, .currentContent:
            return AppTheme.graphBlueNSColor
        case .ancestorMarker, .ancestorContent:
            return AppTheme.mutedNSColor
        case .separator:
            return AppTheme.conflictNSColor
        case .incomingContent, .incomingMarker:
            return AppTheme.addedNSColor
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .currentMarker, .incomingMarker:
            return accentColor.withAlphaComponent(0.30)
        case .currentContent, .incomingContent:
            return accentColor.withAlphaComponent(0.13)
        case .ancestorMarker:
            return accentColor.withAlphaComponent(0.20)
        case .ancestorContent:
            return accentColor.withAlphaComponent(0.08)
        case .separator:
            return accentColor.withAlphaComponent(0.26)
        }
    }

    var foregroundColor: NSColor {
        switch self {
        case .currentMarker, .separator, .incomingMarker:
            return accentColor
        case .ancestorMarker, .ancestorContent:
            return AppTheme.secondaryNSColor
        case .currentContent, .incomingContent:
            return AppTheme.primaryNSColor
        }
    }

    /// Deliberately avoids "yours"/"theirs": during a rebase the roles swap,
    /// and the editor does not know which operation produced the markers.
    var annotation: String? {
        switch self {
        case .currentMarker:
            return "Current change"
        case .ancestorMarker:
            return "Common ancestor"
        case .incomingMarker:
            return "Incoming change"
        case .currentContent, .ancestorContent, .separator, .incomingContent:
            return nil
        }
    }
}

private extension NSRange {
    func clamped(toLength length: Int) -> NSRange {
        let location = min(max(0, self.location), length)
        let rangeLength = min(max(0, self.length), length - location)
        return NSRange(location: location, length: rangeLength)
    }
}

@MainActor
final class QuickLookPreviewScrollSynchronizer {
    private struct WeakScrollView {
        weak var value: NSScrollView?
    }

    private var scrollViews: [ObjectIdentifier: WeakScrollView] = [:]
    private var isSynchronizing = false

    func register(_ scrollView: NSScrollView, owner: ObjectIdentifier) {
        scrollViews[owner] = WeakScrollView(value: scrollView)
        removeReleasedScrollViews()
    }

    func unregister(owner: ObjectIdentifier) {
        scrollViews.removeValue(forKey: owner)
    }

    func synchronize(_ source: NSScrollView, owner: ObjectIdentifier) {
        guard !isSynchronizing else { return }

        let sourcePosition = Self.scrollPosition(in: source)
        guard sourcePosition.x != nil || sourcePosition.y != nil else { return }

        isSynchronizing = true
        defer { isSynchronizing = false }

        removeReleasedScrollViews()
        for (candidateOwner, candidate) in scrollViews where candidateOwner != owner {
            guard let target = candidate.value else { continue }
            Self.apply(sourcePosition, to: target)
        }
    }

    private func removeReleasedScrollViews() {
        scrollViews = scrollViews.filter { $0.value.value != nil }
    }

    private static func scrollPosition(in scrollView: NSScrollView) -> (x: CGFloat?, y: CGFloat?) {
        guard let documentView = scrollView.documentView else { return (nil, nil) }

        let documentBounds = documentView.bounds
        let visibleBounds = scrollView.contentView.bounds
        let horizontalRange = documentBounds.width - visibleBounds.width
        let verticalRange = documentBounds.height - visibleBounds.height

        return (
            x: normalizedPosition(
                visibleBounds.minX,
                minimum: documentBounds.minX,
                range: horizontalRange
            ),
            y: normalizedPosition(
                visibleBounds.minY,
                minimum: documentBounds.minY,
                range: verticalRange
            )
        )
    }

    private static func normalizedPosition(
        _ value: CGFloat,
        minimum: CGFloat,
        range: CGFloat
    ) -> CGFloat? {
        guard range > 0.5 else { return nil }
        return min(max((value - minimum) / range, 0), 1)
    }

    private static func apply(
        _ position: (x: CGFloat?, y: CGFloat?),
        to scrollView: NSScrollView
    ) {
        guard let documentView = scrollView.documentView else { return }

        let documentBounds = documentView.bounds
        let clipView = scrollView.contentView
        let visibleBounds = clipView.bounds
        var targetOrigin = visibleBounds.origin

        if let x = position.x {
            let range = documentBounds.width - visibleBounds.width
            if range > 0.5 {
                targetOrigin.x = documentBounds.minX + (range * x)
            }
        }

        if let y = position.y {
            let range = documentBounds.height - visibleBounds.height
            if range > 0.5 {
                targetOrigin.y = documentBounds.minY + (range * y)
            }
        }

        guard abs(targetOrigin.x - visibleBounds.minX) > 0.01
                || abs(targetOrigin.y - visibleBounds.minY) > 0.01 else { return }

        clipView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
    }
}

private final class ScrollTrackingQuickLookPreviewView: QLPreviewView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

struct RepositoryQuickLookPreview: NSViewRepresentable {
    let url: URL
    var scrollSynchronizer: QuickLookPreviewScrollSynchronizer?

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollSynchronizer: scrollSynchronizer)
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = ScrollTrackingQuickLookPreviewView(frame: .zero, style: .normal)!
        previewView.autostarts = true
        previewView.previewItem = url as NSURL
        previewView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleScrollViewDiscovery()
        }
        context.coordinator.url = url
        context.coordinator.attach(to: previewView)
        return previewView
    }

    func updateNSView(_ previewView: QLPreviewView, context: Context) {
        context.coordinator.setScrollSynchronizer(scrollSynchronizer)
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        previewView.previewItem = url as NSURL
        previewView.refreshPreviewItem()
        context.coordinator.scheduleScrollViewDiscovery()
    }

    static func dismantleNSView(_ previewView: QLPreviewView, coordinator: Coordinator) {
        (previewView as? ScrollTrackingQuickLookPreviewView)?.onLayout = nil
        coordinator.detach()
        previewView.close()
    }

    @MainActor
    final class Coordinator {
        var url: URL?

        private weak var previewView: QLPreviewView?
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var scrollSynchronizer: QuickLookPreviewScrollSynchronizer?
        private var isDiscoveryScheduled = false

        private var owner: ObjectIdentifier {
            ObjectIdentifier(self)
        }

        init(scrollSynchronizer: QuickLookPreviewScrollSynchronizer?) {
            self.scrollSynchronizer = scrollSynchronizer
        }

        func attach(to previewView: QLPreviewView) {
            self.previewView = previewView
            scheduleScrollViewDiscovery()
        }

        func setScrollSynchronizer(_ scrollSynchronizer: QuickLookPreviewScrollSynchronizer?) {
            guard self.scrollSynchronizer !== scrollSynchronizer else { return }
            self.scrollSynchronizer?.unregister(owner: owner)
            self.scrollSynchronizer = scrollSynchronizer
            if let observedScrollView {
                scrollSynchronizer?.register(observedScrollView, owner: owner)
            }
        }

        func scheduleScrollViewDiscovery() {
            guard !isDiscoveryScheduled else { return }
            isDiscoveryScheduled = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDiscoveryScheduled = false
                self.discoverScrollView()
            }
        }

        func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
            observedScrollView = nil
            scrollSynchronizer?.unregister(owner: owner)
            previewView = nil
        }

        private func discoverScrollView() {
            guard let previewView,
                  let scrollView = primaryScrollView(in: previewView) else { return }

            guard observedScrollView !== scrollView else {
                scrollSynchronizer?.register(scrollView, owner: owner)
                return
            }

            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }

            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView else { return }
                    self.scrollSynchronizer?.synchronize(scrollView, owner: self.owner)
                }
            }
            scrollSynchronizer?.register(scrollView, owner: owner)
        }

        private func primaryScrollView(in view: NSView) -> NSScrollView? {
            let candidates = descendantScrollViews(in: view).filter {
                !$0.isHidden && $0.documentView != nil
            }
            return candidates.max {
                ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
            }
        }

        private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { subview in
                var scrollViews = descendantScrollViews(in: subview)
                if let scrollView = subview as? NSScrollView {
                    scrollViews.append(scrollView)
                }
                return scrollViews
            }
        }
    }
}

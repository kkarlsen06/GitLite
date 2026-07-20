import Foundation

enum ConflictChoice: Equatable, Sendable {
    case current
    case incoming
    case both
    case custom(String)

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

struct ConflictHunk: Identifiable, Equatable, Sendable {
    let id: Int
    let currentLabel: String
    let incomingLabel: String
    let currentText: String
    let incomingText: String
    /// 1-based line numbers of the conflict markers in the working-tree file,
    /// so the resolver can show the same numbers an editor would.
    let markerLine: Int
    let ancestorMarkerLine: Int?
    let separatorLine: Int
    let endLine: Int

    var currentStartLine: Int { markerLine + 1 }
    var incomingStartLine: Int { separatorLine + 1 }
}

struct ConflictContext: Equatable, Sendable {
    let text: String
    let startLine: Int
}

struct ConflictDocument: Equatable, Sendable {
    enum Segment: Equatable, Sendable {
        case plain(String)
        case conflict(ConflictHunk)
    }

    let path: String
    let segments: [Segment]

    var hunks: [ConflictHunk] {
        segments.compactMap { segment in
            guard case .conflict(let hunk) = segment else { return nil }
            return hunk
        }
    }

    var firstConflictLine: Int {
        hunks.first?.markerLine ?? 1
    }

    func contextBefore(hunkID: Int, lineLimit: Int = 3) -> ConflictContext? {
        guard let index = segmentIndex(for: hunkID), index > 0,
              case .plain(let text) = segments[index - 1],
              case .conflict(let hunk) = segments[index] else { return nil }
        let lines = Self.textLines(text).suffix(lineLimit)
        guard !lines.isEmpty else { return nil }
        return ConflictContext(
            text: lines.joined(),
            startLine: hunk.markerLine - lines.count
        )
    }

    func contextAfter(hunkID: Int, lineLimit: Int = 3) -> ConflictContext? {
        guard let index = segmentIndex(for: hunkID),
              case .conflict(let hunk) = segments[index],
              index + 1 < segments.count,
              case .plain(let text) = segments[index + 1] else { return nil }
        let lines = Self.textLines(text).prefix(lineLimit)
        guard !lines.isEmpty else { return nil }
        return ConflictContext(text: lines.joined(), startLine: hunk.endLine + 1)
    }

    func resolvedText(choices: [Int: ConflictChoice]) -> String? {
        var result = ""
        for segment in segments {
            switch segment {
            case .plain(let text):
                result += text
            case .conflict(let hunk):
                guard let choice = choices[hunk.id] else { return nil }
                switch choice {
                case .current:
                    result += hunk.currentText
                case .incoming:
                    result += hunk.incomingText
                case .both:
                    result += hunk.currentText
                    result += hunk.incomingText
                case .custom(let text):
                    // An empty custom resolution deletes the block; otherwise
                    // keep the file line-structured even when the editor draft
                    // lost its trailing newline.
                    if !text.isEmpty {
                        result += text.hasSuffix("\n") ? text : text + "\n"
                    }
                }
            }
        }
        return result
    }

    static func parse(path: String, text: String) -> ConflictDocument? {
        let lines = textLines(text)
        var segments: [Segment] = []
        var plain = ""
        var index = 0
        var hunkID = 0

        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("<<<<<<<") else {
                plain += line
                index += 1
                continue
            }

            guard let parsed = parseHunk(lines: lines, startIndex: index, id: hunkID) else {
                return nil
            }
            if !plain.isEmpty {
                segments.append(.plain(plain))
                plain = ""
            }
            segments.append(.conflict(parsed.hunk))
            hunkID += 1
            index = parsed.nextIndex
        }

        if !plain.isEmpty {
            segments.append(.plain(plain))
        }
        guard hunkID > 0 else { return nil }
        return ConflictDocument(path: path, segments: segments)
    }

    private func segmentIndex(for hunkID: Int) -> Int? {
        segments.firstIndex { segment in
            guard case .conflict(let hunk) = segment else { return false }
            return hunk.id == hunkID
        }
    }

    private static func parseHunk(
        lines: [String],
        startIndex: Int,
        id: Int
    ) -> (hunk: ConflictHunk, nextIndex: Int)? {
        let currentLabel = markerLabel(lines[startIndex], marker: "<<<<<<<")
        var current = ""
        var incoming = ""
        var index = startIndex + 1
        var ancestorMarkerLine: Int?

        while index < lines.count,
              !lines[index].hasPrefix("|||||||"),
              !lines[index].hasPrefix("=======") {
            current += lines[index]
            index += 1
        }

        if index < lines.count, lines[index].hasPrefix("|||||||") {
            ancestorMarkerLine = index + 1
            index += 1
            while index < lines.count, !lines[index].hasPrefix("=======") {
                index += 1
            }
        }

        guard index < lines.count, lines[index].hasPrefix("=======") else { return nil }
        let separatorIndex = index
        index += 1
        while index < lines.count, !lines[index].hasPrefix(">>>>>>>") {
            incoming += lines[index]
            index += 1
        }
        guard index < lines.count else { return nil }

        let incomingLabel = markerLabel(lines[index], marker: ">>>>>>>")
        return (
            ConflictHunk(
                id: id,
                currentLabel: currentLabel,
                incomingLabel: incomingLabel,
                currentText: current,
                incomingText: incoming,
                markerLine: startIndex + 1,
                ancestorMarkerLine: ancestorMarkerLine,
                separatorLine: separatorIndex + 1,
                endLine: index + 1
            ),
            index + 1
        )
    }

    private static func markerLabel(_ line: String, marker: String) -> String {
        line.dropFirst(marker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func textLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines: [String] = []
        var start = text.startIndex
        while let newline = text[start...].firstIndex(of: "\n") {
            let afterNewline = text.index(after: newline)
            lines.append(String(text[start..<afterNewline]))
            start = afterNewline
        }
        if start < text.endIndex {
            lines.append(String(text[start..<text.endIndex]))
        }
        return lines
    }
}

struct ConflictResolutionSession: Equatable, Sendable {
    let path: String
    let operation: GitOperation
    let document: ConflictDocument?
    let sideLabels: ConflictSideLabels
    var choices: [Int: ConflictChoice] = [:]

    var resolvedCount: Int { choices.count }
    var totalCount: Int { document?.hunks.count ?? 1 }
    var resolvedText: String? { document?.resolvedText(choices: choices) }
    var currentTitle: String {
        sideLabels.current ?? operation.conflictCurrentTitle
    }
    var incomingTitle: String {
        sideLabels.incoming ?? operation.conflictIncomingTitle
    }
}

struct ConflictSideLabels: Equatable, Sendable {
    let current: String?
    let incoming: String?
}

enum ConflictEditorRegionKind: Equatable, Sendable {
    case currentMarker
    case currentContent
    case ancestorMarker
    case ancestorContent
    case separator
    case incomingContent
    case incomingMarker
}

struct ConflictEditorDecoration: Equatable, Sendable {
    let range: NSRange
    let kind: ConflictEditorRegionKind
}

/// Maps the shared conflict parser's line metadata to editor ranges. Keeping
/// this separate from rendering lets every editor presentation use exactly the
/// same interpretation of merge, rebase, cherry-pick, and revert markers.
enum ConflictEditorPresentation {
    static func decorations(for text: String) -> [ConflictEditorDecoration] {
        guard text.contains("<<<<<<<"),
              let document = ConflictDocument.parse(path: "", text: text) else { return [] }

        let lines = lineRanges(in: text as NSString)
        var decorations: [ConflictEditorDecoration] = []
        decorations.reserveCapacity(document.hunks.count * 7)

        for hunk in document.hunks {
            append(
                .currentMarker,
                from: hunk.markerLine,
                through: hunk.markerLine,
                lineRanges: lines,
                to: &decorations
            )
            append(
                .currentContent,
                from: hunk.currentStartLine,
                through: (hunk.ancestorMarkerLine ?? hunk.separatorLine) - 1,
                lineRanges: lines,
                to: &decorations
            )

            if let ancestorMarkerLine = hunk.ancestorMarkerLine {
                append(
                    .ancestorMarker,
                    from: ancestorMarkerLine,
                    through: ancestorMarkerLine,
                    lineRanges: lines,
                    to: &decorations
                )
                append(
                    .ancestorContent,
                    from: ancestorMarkerLine + 1,
                    through: hunk.separatorLine - 1,
                    lineRanges: lines,
                    to: &decorations
                )
            }

            append(
                .separator,
                from: hunk.separatorLine,
                through: hunk.separatorLine,
                lineRanges: lines,
                to: &decorations
            )
            append(
                .incomingContent,
                from: hunk.incomingStartLine,
                through: hunk.endLine - 1,
                lineRanges: lines,
                to: &decorations
            )
            append(
                .incomingMarker,
                from: hunk.endLine,
                through: hunk.endLine,
                lineRanges: lines,
                to: &decorations
            )
        }
        return decorations
    }

    private static func append(
        _ kind: ConflictEditorRegionKind,
        from startLine: Int,
        through endLine: Int,
        lineRanges: [NSRange],
        to decorations: inout [ConflictEditorDecoration]
    ) {
        guard startLine > 0,
              endLine >= startLine,
              endLine <= lineRanges.count else { return }
        let start = lineRanges[startLine - 1].location
        let end = NSMaxRange(lineRanges[endLine - 1])
        decorations.append(ConflictEditorDecoration(
            range: NSRange(location: start, length: end - start),
            kind: kind
        ))
    }

    private static func lineRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            let range = text.lineRange(for: NSRange(location: location, length: 0))
            guard range.length > 0 else { break }
            ranges.append(range)
            location = NSMaxRange(range)
        }
        return ranges
    }
}

extension GitOperation {
    var conflictCurrentTitle: String {
        switch self {
        case .rebase: return "Onto Branch"
        case .merge, .cherryPick, .revert: return "Current Branch"
        }
    }

    var conflictIncomingTitle: String {
        switch self {
        case .merge: return "Incoming Branch"
        case .rebase: return "Replayed Commit"
        case .cherryPick: return "Cherry-picked Commit"
        case .revert: return "Reverted Result"
        }
    }
}

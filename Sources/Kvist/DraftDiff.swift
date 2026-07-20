import Foundation

struct DraftDiff {
    let text: String
    let addedLineCount: Int
    let removedLineCount: Int

    var summary: String {
        "+\(addedLineCount) −\(removedLineCount)"
    }

    static func make(
        savedText: String,
        draftText: String,
        path: String
    ) -> DraftDiff {
        let savedLines = lines(in: savedText)
        let draftLines = lines(in: draftText)
        let difference = draftLines.difference(from: savedLines)
        let removedOffsets: Set<Int> = Set(difference.removals.compactMap {
            change -> Int? in
            guard case .remove(let offset, _, _) = change else { return nil }
            return offset
        })
        let insertedOffsets: Set<Int> = Set(difference.insertions.compactMap {
            change -> Int? in
            guard case .insert(let offset, _, _) = change else { return nil }
            return offset
        })
        let entries = entries(
            savedLines: savedLines,
            draftLines: draftLines,
            removedOffsets: removedOffsets,
            insertedOffsets: insertedOffsets
        )
        let changedIndices = entries.indices.filter {
            entries[$0].kind != .context
        }
        let ranges = hunkRanges(for: changedIndices, entryCount: entries.count)

        var output = "--- a/\(path)\n+++ b/\(path)\n"
        for range in ranges {
            let lines = entries[range]
            let oldCount = lines.count { $0.kind != .addition }
            let newCount = lines.count { $0.kind != .removal }
            let first = entries[range.lowerBound]
            let oldStart = oldCount == 0
                ? first.oldOffsetBefore
                : first.oldOffsetBefore + 1
            let newStart = newCount == 0
                ? first.newOffsetBefore
                : first.newOffsetBefore + 1
            output += "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
            for line in lines {
                output += "\(line.kind.marker)\(line.text)\n"
                if line.kind != .context, !line.hasTrailingNewline {
                    output += "\\ No newline at end of file\n"
                }
            }
        }

        return DraftDiff(
            text: output,
            addedLineCount: insertedOffsets.count,
            removedLineCount: removedOffsets.count
        )
    }

    private static func lines(in text: String) -> [SourceLine] {
        guard !text.isEmpty else { return [] }
        var contents = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let endsWithNewline = text.hasSuffix("\n")
        if endsWithNewline {
            contents.removeLast()
        }
        return contents.indices.map { index in
            SourceLine(
                text: contents[index],
                hasTrailingNewline: endsWithNewline || index < contents.count - 1
            )
        }
    }

    private static func entries(
        savedLines: [SourceLine],
        draftLines: [SourceLine],
        removedOffsets: Set<Int>,
        insertedOffsets: Set<Int>
    ) -> [Entry] {
        var entries: [Entry] = []
        entries.reserveCapacity(savedLines.count + insertedOffsets.count)
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < savedLines.count || newIndex < draftLines.count {
            if oldIndex < savedLines.count, removedOffsets.contains(oldIndex) {
                entries.append(Entry(
                    kind: .removal,
                    text: savedLines[oldIndex].text,
                    hasTrailingNewline: savedLines[oldIndex].hasTrailingNewline,
                    oldOffsetBefore: oldIndex,
                    newOffsetBefore: newIndex
                ))
                oldIndex += 1
                continue
            }
            if newIndex < draftLines.count, insertedOffsets.contains(newIndex) {
                entries.append(Entry(
                    kind: .addition,
                    text: draftLines[newIndex].text,
                    hasTrailingNewline: draftLines[newIndex].hasTrailingNewline,
                    oldOffsetBefore: oldIndex,
                    newOffsetBefore: newIndex
                ))
                newIndex += 1
                continue
            }
            guard oldIndex < savedLines.count, newIndex < draftLines.count else {
                break
            }
            entries.append(Entry(
                kind: .context,
                text: savedLines[oldIndex].text,
                hasTrailingNewline: savedLines[oldIndex].hasTrailingNewline,
                oldOffsetBefore: oldIndex,
                newOffsetBefore: newIndex
            ))
            oldIndex += 1
            newIndex += 1
        }
        return entries
    }

    private static func hunkRanges(
        for changedIndices: [Int],
        entryCount: Int
    ) -> [ClosedRange<Int>] {
        guard let firstChange = changedIndices.first else { return [] }
        var ranges: [ClosedRange<Int>] = []
        var currentStart = max(0, firstChange - 3)
        var currentEnd = min(entryCount - 1, firstChange + 3)

        for changedIndex in changedIndices.dropFirst() {
            let nextStart = max(0, changedIndex - 3)
            let nextEnd = min(entryCount - 1, changedIndex + 3)
            if nextStart <= currentEnd + 1 {
                currentEnd = max(currentEnd, nextEnd)
            } else {
                ranges.append(currentStart...currentEnd)
                currentStart = nextStart
                currentEnd = nextEnd
            }
        }
        ranges.append(currentStart...currentEnd)
        return ranges
    }

    private struct Entry {
        let kind: Kind
        let text: String
        let hasTrailingNewline: Bool
        let oldOffsetBefore: Int
        let newOffsetBefore: Int
    }

    private struct SourceLine: Equatable {
        let text: String
        let hasTrailingNewline: Bool
    }

    private enum Kind {
        case context
        case addition
        case removal

        var marker: Character {
            switch self {
            case .context: return " "
            case .addition: return "+"
            case .removal: return "-"
            }
        }
    }
}

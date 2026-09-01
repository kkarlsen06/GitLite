import XCTest
@testable import Kvist

final class DiffDocumentTests: XCTestCase {
    func testFormatterPreservesDiffContentAndLineNumbers() throws {
        let diff = """
        diff --git a/sample.swift b/sample.swift
        @@ -10,2 +20,3 @@
        -old
        +new
         context
        \\ No newline at end of file
        """

        let formatted = try XCTUnwrap(DiffDocumentFormatter.formattedText(for: diff))

        XCTAssertEqual(
            formatted,
            """
            \t\t\t▏\tdiff --git a/sample.swift b/sample.swift
            \t\t\t▏\t@@ -10,2 +20,3 @@
            \t10\t\t▏\t-old
            \t\t20\t▏\t+new
            \t11\t21\t▏\t context
            \t\t\t▏\t\\ No newline at end of file

            """
        )
    }

    func testLineComparerHighlightsOnlyTheChangedWhitespaceAndWords() {
        let spacing = DiffLineComparer.changedRanges(
            removed: "let value  = compute(a, b)",
            added: "let value = compute(a, b)"
        )
        XCTAssertEqual(spacing.removed, [NSRange(location: 9, length: 2)])
        XCTAssertEqual(spacing.added, [NSRange(location: 9, length: 1)])

        let words = DiffLineComparer.changedRanges(
            removed: "return first + second",
            added: "return first - third"
        )
        XCTAssertEqual(
            words.removed,
            [NSRange(location: 13, length: 1), NSRange(location: 15, length: 6)]
        )
        XCTAssertEqual(
            words.added,
            [NSRange(location: 13, length: 1), NSRange(location: 15, length: 5)]
        )

        let rewritten = DiffLineComparer.changedRanges(
            removed: "alpha beta gamma",
            added: "one two three four"
        )
        XCTAssertEqual(rewritten, DiffLineComparer.Changes(removed: [], added: []))
    }

    func testFormatterEmphasizesPairedChangesWithinAHunk() throws {
        let diff = """
        @@ -1,3 +1,3 @@
         context
        -let a  = 1
        -unchanged line
        +let a = 1
        +unchanged line
        """

        let document = try XCTUnwrap(DiffDocumentFormatter.formattedDocument(for: diff))
        let text = document.text as NSString

        XCTAssertEqual(document.emphasisRanges.count, 2)
        XCTAssertEqual(
            document.emphasisRanges.map { text.substring(with: $0) },
            ["  ", " "]
        )
        let removedLine = text.range(of: "-let a  = 1")
        XCTAssertTrue(NSLocationInRange(document.emphasisRanges[0].location, removedLine))
        let addedLine = text.range(of: "+let a = 1")
        XCTAssertTrue(NSLocationInRange(document.emphasisRanges[1].location, addedLine))
    }

    func testFormatterHandlesLargeDiffWithoutMaterializingLineModels() throws {
        let changedLineCount = 1_000_000
        var diff = "@@ -0,0 +1,\(changedLineCount) @@"
        for line in 1...changedLineCount {
            diff.append("\n+value \(line)")
        }

        let formatted = try XCTUnwrap(DiffDocumentFormatter.formattedText(for: diff))

        XCTAssertTrue(formatted.hasSuffix("\t\t\(changedLineCount)\t▏\t+value \(changedLineCount)\n"))
        XCTAssertEqual(formatted.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }, changedLineCount + 1)
    }
}

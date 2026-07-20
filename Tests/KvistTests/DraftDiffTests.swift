import XCTest
@testable import Kvist

final class DraftDiffTests: XCTestCase {
    func testReplacementIncludesChangedLinesAndContext() {
        let diff = DraftDiff.make(
            savedText: "one\ntwo\nthree\n",
            draftText: "one\nupdated\nthree\n",
            path: "Example.txt"
        )

        XCTAssertEqual(diff.addedLineCount, 1)
        XCTAssertEqual(diff.removedLineCount, 1)
        XCTAssertEqual(diff.summary, "+1 −1")
        XCTAssertTrue(diff.text.contains("--- a/Example.txt"))
        XCTAssertTrue(diff.text.contains("+++ b/Example.txt"))
        XCTAssertTrue(diff.text.contains("-two"))
        XCTAssertTrue(diff.text.contains("+updated"))
        XCTAssertTrue(diff.text.contains(" three"))
    }

    func testInsertionAtStartUsesZeroOldLineCount() {
        let diff = DraftDiff.make(
            savedText: "existing\n",
            draftText: "new\nexisting\n",
            path: "Example.txt"
        )

        XCTAssertEqual(diff.addedLineCount, 1)
        XCTAssertEqual(diff.removedLineCount, 0)
        XCTAssertTrue(diff.text.contains("+new"))
        XCTAssertTrue(diff.text.contains(" existing"))
    }

    func testDistantChangesProduceSeparateHunks() {
        let saved = (1...12).map { "line \($0)" }.joined(separator: "\n") + "\n"
        var draftLines = (1...12).map { "line \($0)" }
        draftLines[0] = "first"
        draftLines[11] = "last"
        let diff = DraftDiff.make(
            savedText: saved,
            draftText: draftLines.joined(separator: "\n") + "\n",
            path: "Example.txt"
        )

        XCTAssertEqual(
            diff.text.components(separatedBy: "@@").count - 1,
            4
        )
    }

    func testRemovingFinalNewlineIsShownAsAChange() {
        let diff = DraftDiff.make(
            savedText: "value\n",
            draftText: "value",
            path: "Example.txt"
        )

        XCTAssertEqual(diff.addedLineCount, 1)
        XCTAssertEqual(diff.removedLineCount, 1)
        XCTAssertTrue(diff.text.contains("-value"))
        XCTAssertTrue(diff.text.contains("+value"))
        XCTAssertTrue(diff.text.contains("\\ No newline at end of file"))
    }
}

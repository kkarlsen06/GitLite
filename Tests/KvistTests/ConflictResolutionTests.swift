import XCTest
@testable import Kvist

final class ConflictResolutionTests: XCTestCase {
    private let source = """
    before
    <<<<<<< HEAD
    current one
    ||||||| parent
    base one
    =======
    incoming one
    >>>>>>> abc123
    middle
    <<<<<<< HEAD
    current two
    =======
    incoming two
    >>>>>>> def456
    after
    """

    func testParserBuildsHunksAndResolvesEachSideOrBoth() throws {
        let document = try XCTUnwrap(ConflictDocument.parse(path: "file.ts", text: source))

        XCTAssertEqual(document.hunks.count, 2)
        XCTAssertEqual(document.hunks[0].currentLabel, "HEAD")
        XCTAssertEqual(document.hunks[0].incomingLabel, "abc123")
        XCTAssertEqual(document.contextBefore(hunkID: 0)?.text, "before\n")
        XCTAssertEqual(document.contextAfter(hunkID: 1)?.text, "after")
        XCTAssertNil(document.resolvedText(choices: [0: .current]))
        XCTAssertEqual(
            document.resolvedText(choices: [0: .incoming, 1: .both]),
            "before\nincoming one\nmiddle\ncurrent two\nincoming two\nafter"
        )
    }

    func testParserRecordsWorkingFileLineNumbers() throws {
        let document = try XCTUnwrap(ConflictDocument.parse(path: "file.ts", text: source))

        // The diff3 base section between ||||||| and ======= must not shift
        // either side's numbering.
        let first = document.hunks[0]
        XCTAssertEqual(first.markerLine, 2)
        XCTAssertEqual(first.currentStartLine, 3)
        XCTAssertEqual(first.ancestorMarkerLine, 4)
        XCTAssertEqual(first.separatorLine, 6)
        XCTAssertEqual(first.incomingStartLine, 7)
        XCTAssertEqual(first.endLine, 8)

        let second = document.hunks[1]
        XCTAssertEqual(second.markerLine, 10)
        XCTAssertEqual(second.currentStartLine, 11)
        XCTAssertNil(second.ancestorMarkerLine)
        XCTAssertEqual(second.separatorLine, 12)
        XCTAssertEqual(second.incomingStartLine, 13)
        XCTAssertEqual(second.endLine, 14)

        XCTAssertEqual(document.firstConflictLine, 2)
        XCTAssertEqual(document.contextBefore(hunkID: 0)?.startLine, 1)
        XCTAssertEqual(document.contextAfter(hunkID: 0)?.startLine, 9)
        XCTAssertEqual(document.contextBefore(hunkID: 1)?.startLine, 9)
        XCTAssertEqual(document.contextAfter(hunkID: 1)?.startLine, 15)
        XCTAssertNil(
            ConflictDocument.parse(
                path: "file.ts",
                text: "<<<<<<< HEAD\ncurrent\n=======\nincoming\n>>>>>>> theirs\n"
            )?.contextBefore(hunkID: 0)
        )
    }

    func testEditorPresentationDecoratesConflictRegionsFromSharedParser() throws {
        let decorations = ConflictEditorPresentation.decorations(for: source)
        let text = source as NSString

        func firstText(for kind: ConflictEditorRegionKind) throws -> String {
            let decoration = try XCTUnwrap(decorations.first { $0.kind == kind })
            return text.substring(with: decoration.range)
        }

        XCTAssertEqual(try firstText(for: .currentMarker), "<<<<<<< HEAD\n")
        XCTAssertEqual(try firstText(for: .currentContent), "current one\n")
        XCTAssertEqual(try firstText(for: .ancestorMarker), "||||||| parent\n")
        XCTAssertEqual(try firstText(for: .ancestorContent), "base one\n")
        XCTAssertEqual(try firstText(for: .separator), "=======\n")
        XCTAssertEqual(try firstText(for: .incomingContent), "incoming one\n")
        XCTAssertEqual(try firstText(for: .incomingMarker), ">>>>>>> abc123\n")
        XCTAssertTrue(ConflictEditorPresentation.decorations(for: "ordinary\n").isEmpty)
    }

    func testCustomChoiceReplacesHunkAndNormalizesTrailingNewline() throws {
        let document = try XCTUnwrap(ConflictDocument.parse(path: "file.ts", text: source))

        XCTAssertEqual(
            document.resolvedText(choices: [
                0: .custom("merged one"),
                1: .custom("merged two\nmerged three\n")
            ]),
            "before\nmerged one\nmiddle\nmerged two\nmerged three\nafter"
        )
        // An empty custom resolution deletes the conflicted block entirely.
        XCTAssertEqual(
            document.resolvedText(choices: [0: .custom(""), 1: .current]),
            "before\nmiddle\ncurrent two\nafter"
        )
    }

    func testParserRejectsOrdinaryAndMalformedText() {
        XCTAssertNil(ConflictDocument.parse(path: "file.ts", text: "ordinary\ntext\n"))
        XCTAssertNil(ConflictDocument.parse(
            path: "file.ts",
            text: "<<<<<<< HEAD\ncurrent\nmissing separator\n"
        ))
    }
}

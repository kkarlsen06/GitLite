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

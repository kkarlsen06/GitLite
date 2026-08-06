import AppKit
import Combine
import Foundation
import XCTest
@testable import Kvist

final class RepositoryFileEditorTests: XCTestCase {
    func testDiskVersionDetectsSameSizeEditWithPreservedTimestamp() throws {
        let fileURL = repositoryURL.appendingPathComponent("Version.txt")
        try "first\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let modificationDate = try XCTUnwrap(
            fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        )
        let original = RepositoryFileDiskVersion(fileURL: fileURL)

        try "other\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: fileURL.path
        )

        XCTAssertNotEqual(original, RepositoryFileDiskVersion(fileURL: fileURL))
    }

    private var repositoryURL: URL!

    override func setUpWithError() throws {
        repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "KvistFileEditorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repositoryURL)
    }

    @MainActor
    func testWrappedSourceTextViewRemainsEditable() throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: 80))

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.isEditable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        SourceDocument.configureWrapping(in: textView, scrollView: scrollView)
        scrollView.documentView = textView

        let original = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        textView.string = original
        let insertion = " edited"
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.insertText(
            insertion,
            replacementRange: textView.selectedRange()
        )

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        var fragmentCount = 0
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { _, _, _, _, _ in
            fragmentCount += 1
        }

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertTrue(textContainer.widthTracksTextView)
        XCTAssertEqual(textContainer.lineBreakMode, .byWordWrapping)
        XCTAssertGreaterThan(fragmentCount, 1)
        XCTAssertEqual(textView.string, "alpha\(insertion) beta gamma delta epsilon zeta eta theta iota kappa lambda")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5 + insertion.utf16.count, length: 0))
    }

    func testSourceSelectionsClampWhenReplacementDocumentIsShorter() {
        let ranges = [
            NSValue(range: NSRange(location: 900, length: 50)),
            NSValue(range: NSRange(location: 3, length: 20))
        ]

        let clamped = SourceDocument.clampedSelectionRanges(ranges, textLength: 10)

        XCTAssertEqual(clamped.map(\.rangeValue), [
            NSRange(location: 10, length: 0),
            NSRange(location: 3, length: 7)
        ])
    }

    @MainActor
    func testEditorTextDefersOnlyFirstDirtyPublicationUntilNextTurn() async {
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )

        model.updateRepositoryFileTextFromEditor("edited")
        XCTAssertFalse(model.repositoryFileDirty)
        for _ in 0..<10 where !model.repositoryFileDirty {
            await Task.yield()
        }

        XCTAssertTrue(model.repositoryFileDirty)
        model.restoreSavedRepositoryFileText()
        XCTAssertFalse(model.repositoryFileDirty)
        XCTAssertEqual(model.repositoryFileText, "")
    }

    @MainActor
    func testQuickLookPreviewScrollSynchronizationUsesRelativePosition() {
        let source = makeScrollView(documentSize: NSSize(width: 500, height: 1_000))
        let target = makeScrollView(documentSize: NSSize(width: 900, height: 2_000))
        let sourceOwner = NSObject()
        let targetOwner = NSObject()
        let synchronizer = QuickLookPreviewScrollSynchronizer()

        synchronizer.register(source, owner: ObjectIdentifier(sourceOwner))
        synchronizer.register(target, owner: ObjectIdentifier(targetOwner))

        let sourceHorizontalRange = source.documentView!.bounds.width - source.contentView.bounds.width
        let sourceVerticalRange = source.documentView!.bounds.height - source.contentView.bounds.height
        source.contentView.scroll(to: NSPoint(
            x: sourceHorizontalRange * 0.25,
            y: sourceVerticalRange * 0.6
        ))
        synchronizer.synchronize(source, owner: ObjectIdentifier(sourceOwner))

        let targetHorizontalRange = target.documentView!.bounds.width - target.contentView.bounds.width
        let targetVerticalRange = target.documentView!.bounds.height - target.contentView.bounds.height
        XCTAssertEqual(target.contentView.bounds.minX / targetHorizontalRange, 0.25, accuracy: 0.001)
        XCTAssertEqual(target.contentView.bounds.minY / targetVerticalRange, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testScrollingAnchorsLineAtTopOfViewport() throws {
        let (scrollView, textView) = makeSourceEditor(
            text: (1...5_000).map { "line \($0)" }.joined(separator: "\n")
        )

        SourceDocument.scroll(toLine: 2_500, in: textView, scrollView: scrollView)

        let lineRect = try lineFragmentRect(forLine: 2_500, in: textView)
        XCTAssertEqual(
            lineRect.minY,
            textView.visibleRect.minY,
            accuracy: textView.textContainerInset.height + 1,
            "The line should be revealed at the top of the viewport"
        )
    }

    @MainActor
    func testScrollingToLineNearEndOfFileRevealsIt() throws {
        let (scrollView, textView) = makeSourceEditor(
            text: (1...5_000).map { "line \($0)" }.joined(separator: "\n")
        )

        SourceDocument.scroll(toLine: 4_999, in: textView, scrollView: scrollView)

        let lineRect = try lineFragmentRect(forLine: 4_999, in: textView)
        XCTAssertTrue(
            textView.visibleRect.intersects(lineRect),
            "Line 4999 at \(lineRect) is outside \(textView.visibleRect)"
        )
    }

    @MainActor
    func testScrollingToLastLineOfFileRevealsIt() throws {
        let (scrollView, textView) = makeSourceEditor(
            text: (1...5_000).map { "line \($0)" }.joined(separator: "\n")
        )
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)

        SourceDocument.scroll(toLine: 5_000, in: textView, scrollView: scrollView)

        layoutManager.ensureLayout(for: textContainer)
        let documentHeight = layoutManager.usedRect(for: textContainer).maxY
            + textView.textContainerInset.height * 2
        XCTAssertEqual(
            textView.visibleRect.maxY,
            documentHeight,
            accuracy: 1,
            "The last line should be reachable at the bottom of the document"
        )
    }

    @MainActor
    func testLargeSourceScrollingAnchorsLineAtTopOfViewport() throws {
        let text = (1...20_000).map { "line \($0) content" }.joined(separator: "\n")
        let (_, textView) = makeLargeSourceViewer(text: text)
        let offset = try XCTUnwrap(
            LargeSourceNavigation.utf16Offset(forLine: 10_000, in: text)
        )

        LargeSourceDocument.reveal(utf16Offset: offset, in: textView)

        let lineRect = try lineFragmentRect(atUTF16Offset: offset, in: textView)
        XCTAssertEqual(
            lineRect.minY,
            textView.visibleRect.minY,
            accuracy: textView.textContainerInset.height + 1,
            "The line should be revealed at the top of the viewport"
        )
    }

    @MainActor
    func testLargeSourceScrollingRevealsLineNearEndOfFile() throws {
        let text = (1...20_000).map { "line \($0) content" }.joined(separator: "\n")
        let (_, textView) = makeLargeSourceViewer(text: text)
        let offset = try XCTUnwrap(
            LargeSourceNavigation.utf16Offset(forLine: 19_999, in: text)
        )

        LargeSourceDocument.reveal(utf16Offset: offset, in: textView)

        let lineRect = try lineFragmentRect(atUTF16Offset: offset, in: textView)
        XCTAssertTrue(
            textView.visibleRect.intersects(lineRect),
            "Line 19999 at \(lineRect) is outside \(textView.visibleRect)"
        )
        XCTAssertEqual(
            textView.visibleRect.maxY,
            textView.bounds.height,
            accuracy: 1,
            "A line in the last screenful should scroll the document to its end"
        )
    }

    /// The on-screen rect of `line`, measured once the whole document is laid
    /// out so that estimated positions cannot mask a short scroll.
    @MainActor
    private func lineFragmentRect(
        forLine line: Int,
        in textView: NSTextView
    ) throws -> CGRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let range = try XCTUnwrap(
            SourceDocument.highlightedRange(forLine: line, in: textView.string)
        )
        return layoutManager.boundingRect(
            forGlyphRange: layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            ),
            in: textContainer
        ).offsetBy(dx: 0, dy: textView.textContainerInset.height)
    }

    @MainActor
    private func lineFragmentRect(
        atUTF16Offset offset: Int,
        in textView: NSTextView
    ) throws -> CGRect {
        let layoutManager = try XCTUnwrap(textView.textLayoutManager)
        let contentManager = try XCTUnwrap(layoutManager.textContentManager)
        let location = try XCTUnwrap(contentManager.location(
            contentManager.documentRange.location,
            offsetBy: offset
        ))
        var rect: CGRect?
        layoutManager.enumerateTextLayoutFragments(
            from: location,
            options: [.ensuresLayout]
        ) { fragment in
            rect = fragment.layoutFragmentFrame
            return false
        }
        return try XCTUnwrap(rect)
            .offsetBy(dx: 0, dy: textView.textContainerInset.height)
    }

    @MainActor
    private func makeLargeSourceViewer(text: String) -> (NSScrollView, NSTextView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.hasVerticalScroller = true
        let textView = LargeSourceTextView(usingTextLayoutManager: true)
        textView.frame = scrollView.contentView.bounds
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        SourceDocument.configureWrapping(in: textView, scrollView: scrollView)
        textView.string = text
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    @MainActor
    private func makeSourceEditor(text: String) -> (NSScrollView, NSTextView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.hasVerticalScroller = true
        let textView = NSTextView(frame: scrollView.contentView.bounds)
        _ = textView.layoutManager
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.isEditable = true
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        SourceDocument.configureWrapping(in: textView, scrollView: scrollView)
        textView.string = text
        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return (scrollView, textView)
    }

    @MainActor
    private func makeScrollView(documentSize: NSSize) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        scrollView.documentView = NSView(frame: NSRect(origin: .zero, size: documentSize))
        return scrollView
    }

    func testDirectoryChildrenAreShallowFilteredAndFoldersFirst() throws {
        let alphaFolder = repositoryURL.appendingPathComponent("alpha", isDirectory: true)
        let zetaFolder = repositoryURL.appendingPathComponent("Zeta", isDirectory: true)
        let gitFolder = repositoryURL.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: alphaFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zetaFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitFolder, withIntermediateDirectories: true)
        try "nested\n".write(
            to: alphaFolder.appendingPathComponent("nested.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "swift\n".write(
            to: repositoryURL.appendingPathComponent("App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored\n".write(
            to: repositoryURL.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try "finder\n".write(
            to: repositoryURL.appendingPathComponent(".DS_Store"),
            atomically: true,
            encoding: .utf8
        )

        let children = try RepositoryFileLoader.children(of: repositoryURL)

        XCTAssertEqual(Array(children.prefix(2).map(\.name)), ["alpha", "Zeta"])
        XCTAssertTrue(children.prefix(2).allSatisfy(\.isDirectory))
        XCTAssertEqual(Set(children.dropFirst(2).map(\.name)), [".gitignore", "App.swift"])
        XCTAssertFalse(children.contains { $0.name == ".git" || $0.name == ".DS_Store" })
        XCTAssertFalse(children.contains { $0.name == "nested.txt" })

        let nested = try RepositoryFileLoader.children(
            of: alphaFolder,
            parentRelativePath: "alpha"
        )
        XCTAssertEqual(nested.first?.relativePath, "alpha/nested.txt")
    }

    func testDocumentLoaderUsesSourceForTextAndPreviewForBinaryData() throws {
        let textURL = repositoryURL.appendingPathComponent(".gitignore")
        try ".build\n*.xcuserstate\n".write(
            to: textURL,
            atomically: true,
            encoding: .utf8
        )
        let binaryURL = repositoryURL.appendingPathComponent("fixture.dat")
        try Data([0x00, 0x01, 0x02, 0x03, 0xFF]).write(to: binaryURL)
        let imageURL = repositoryURL.appendingPathComponent("mark.svg")
        try "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".write(
            to: imageURL,
            atomically: true,
            encoding: .utf8
        )
        let typeScriptURL = repositoryURL.appendingPathComponent("example.ts")
        let typeScript = "const answer: number = 42\n"
        try typeScript.write(
            to: typeScriptURL,
            atomically: true,
            encoding: .utf8
        )
        let generatedURL = repositoryURL.appendingPathComponent("generated.txt")
        let generated = Array(repeating: "x", count: 20_002)
            .joined(separator: "\n")
        try generated.write(to: generatedURL, atomically: true, encoding: .utf8)
        let minifiedURL = repositoryURL.appendingPathComponent("minified.json")
        let minified = String(
            repeating: "x",
            count: RepositoryFileLoader.maximumSourceLineLength + 1
        )
        try minified.write(to: minifiedURL, atomically: true, encoding: .utf8)
        let oversizedURL = repositoryURL.appendingPathComponent("oversized.log")
        let oversized = String(
            repeating: "a\n",
            count: RepositoryFileLoader.maximumSourceFileSize / 2 + 1
        )
        try oversized.write(to: oversizedURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try RepositoryFileLoader.document(at: textURL),
            .source(".build\n*.xcuserstate\n")
        )
        XCTAssertEqual(
            try RepositoryFileLoader.document(at: binaryURL),
            .preview
        )
        XCTAssertEqual(
            try RepositoryFileLoader.document(at: imageURL),
            .preview
        )
        XCTAssertEqual(
            try RepositoryFileLoader.document(at: typeScriptURL),
            .source(typeScript)
        )
        XCTAssertEqual(
            try RepositoryFileLoader.document(at: generatedURL),
            .largeSource(generated)
        )
        XCTAssertEqual(
            try RepositoryFileLoader.document(at: minifiedURL),
            .largeSource(minified)
        )
        XCTAssertEqual(
            try RepositoryFileLoader.document(at: oversizedURL),
            .largeSource(oversized)
        )
    }

    func testSourceSearchHighlightCoversTheRequestedLine() {
        let text = "first\nsecond match\nthird\n"

        XCTAssertEqual(
            SourceDocument.highlightedRange(forLine: 2, in: text),
            NSRange(location: 6, length: 13)
        )
    }

    func testGitPreviewPrefersDiffForTypeScriptFiles() throws {
        let oldURL = repositoryURL.appendingPathComponent("Old/openai.ts")
        let newURL = repositoryURL.appendingPathComponent("New/openai.ts")
        try FileManager.default.createDirectory(
            at: oldURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: newURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "export const model = 'old';\n".write(
            to: oldURL,
            atomically: true,
            encoding: .utf8
        )
        try "export const model = 'new';\n".write(
            to: newURL,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertFalse(RepositoryFileLoader.prefersGitPreview(for: [oldURL, newURL]))
    }

    func testDocumentLoaderKeepsUnsafeTextSizesOutOfTheViewportRenderer() throws {
        let oversizedURL = repositoryURL.appendingPathComponent("enormous.log")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversizedURL.path, contents: nil))
        let oversizedHandle = try FileHandle(forWritingTo: oversizedURL)
        try oversizedHandle.truncate(
            atOffset: UInt64(RepositoryFileLoader.maximumReadOnlySourceFileSize + 1)
        )
        try oversizedHandle.close()

        let longLineURL = repositoryURL.appendingPathComponent("single-line.json")
        try Data(
            repeating: 0x61,
            count: RepositoryFileLoader.maximumReadOnlySourceLineLength + 1
        ).write(to: longLineURL)

        XCTAssertEqual(
            try RepositoryFileLoader.document(at: oversizedURL),
            .message("This file is too large to view efficiently.")
        )
        XCTAssertEqual(
            try RepositoryFileLoader.document(at: longLineURL),
            .message("This file contains a line too large to view efficiently.")
        )
    }

    func testDocumentLoaderAcceptsEveryExactSupportedSourceLimit() throws {
        let maximumURL = repositoryURL.appendingPathComponent("maximum.swift")
        let fixedLine = Data((String(repeating: "x", count: 255) + "\n").utf8)
        var maximumData = Data(capacity: RepositoryFileLoader.maximumSourceFileSize)
        for _ in 0..<4_096 {
            maximumData.append(fixedLine)
        }
        try maximumData.write(to: maximumURL)

        let linesURL = repositoryURL.appendingPathComponent("lines.swift")
        let lines = (1...RepositoryFileLoader.maximumSourceLineCount)
            .map { "line\($0)" }
            .joined(separator: "\n")
        try Data(lines.utf8).write(to: linesURL)

        let longLineURL = repositoryURL.appendingPathComponent("long-line.swift")
        let longLine = String(
            repeating: "l",
            count: RepositoryFileLoader.maximumSourceLineLength
        )
        try Data(longLine.utf8).write(to: longLineURL)

        XCTAssertEqual(maximumData.count, RepositoryFileLoader.maximumSourceFileSize)
        guard case .source = try RepositoryFileLoader.document(at: maximumURL) else {
            return XCTFail("The exact maximum file size should remain editable")
        }
        XCTAssertEqual(try RepositoryFileLoader.document(at: linesURL), .source(lines))
        XCTAssertEqual(try RepositoryFileLoader.document(at: longLineURL), .source(longLine))
    }

    func testLargeSourceNavigationFindsUTF16OffsetsOffTheMainActor() throws {
        let text = "😀 first\r\nsecond\u{2028}third\nfourth"
        let source = text as NSString

        XCTAssertEqual(LargeSourceNavigation.utf16Offset(forLine: 1, in: text), 0)
        XCTAssertEqual(
            LargeSourceNavigation.utf16Offset(forLine: 2, in: text),
            source.range(of: "second").location
        )
        XCTAssertEqual(
            LargeSourceNavigation.utf16Offset(forLine: 4, in: text),
            source.range(of: "fourth").location
        )
        XCTAssertEqual(
            LargeSourceNavigation.utf16Offset(forLine: 99, in: text),
            source.range(of: "fourth").location
        )
    }

    @MainActor
    func testLargeSourceOpensReadOnlyWithoutPersistingItsContents() async throws {
        try runGit(["init", "-b", "main"])
        let relativePath = "large.txt"
        let source = Array(repeating: "value", count: 20_001)
            .joined(separator: "\n")
        try source.write(
            to: repositoryURL.appendingPathComponent(relativePath),
            atomically: true,
            encoding: .utf8
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile(relativePath, scrollToLine: 19_950)
        await waitForFileLoad(in: model)

        XCTAssertEqual(model.detailKind, .largeSource)
        XCTAssertEqual(model.repositoryFileText, source)
        XCTAssertFalse(model.isRepositoryFileDirty)
        XCTAssertFalse(model.canSaveRepositoryFile)
        XCTAssertEqual(model.repositoryFileScrollRequest?.line, 19_950)
        XCTAssertEqual(model.makeRestorationState().editor?.fileText, "")
    }

    @MainActor
    func testJumpingWithinOpenSourceReusesDocumentAndPublishesScrollRequest() async throws {
        try runGit(["init", "-b", "main"])
        let source = (1...20_000).map { "line\($0)" }.joined(separator: "\n")
        try source.write(
            to: repositoryURL.appendingPathComponent("large.swift"),
            atomically: true,
            encoding: .utf8
        )
        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("large.swift")
        await waitForFileLoad(in: model)

        model.openRepositoryFile("large.swift", scrollToLine: 19_950)

        XCTAssertEqual(model.repositoryFileText, source)
        XCTAssertEqual(model.repositoryFileScrollRequest?.line, 19_950)
        XCTAssertFalse(model.isDetailLoading)
    }

    func testImageDetectionUsesSystemContentType() throws {
        let imageURL = repositoryURL.appendingPathComponent("preview.png")
        let textURL = repositoryURL.appendingPathComponent("notes.txt")
        try Data().write(to: imageURL)
        try Data().write(to: textURL)

        XCTAssertTrue(RepositoryFileLoader.isImage(at: imageURL))
        XCTAssertFalse(RepositoryFileLoader.isImage(at: textURL))
    }

    func testDiffNavigationFindsFirstNewFileLine() {
        let diff = """
        diff --git a/Example.swift b/Example.swift
        --- a/Example.swift
        +++ b/Example.swift
        @@ -7,2 +9,3 @@
         context
        @@ -20 +24 @@
        """

        XCTAssertEqual(DiffNavigation.firstChangedLine(in: diff), 9)
        XCTAssertNil(DiffNavigation.firstChangedLine(in: "No textual diff available."))
    }

    @MainActor
    func testViewDiffInFilesOpensFileAtFirstHunkAndExpandsParents() async throws {
        try runGit(["init", "-b", "main"])
        try runGit(["config", "user.email", "tests@example.com"])
        try runGit(["config", "user.name", "Kvist Tests"])
        let sourceFolder = repositoryURL
            .appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceFolder,
            withIntermediateDirectories: true
        )
        let sourceURL = sourceFolder.appendingPathComponent("Example.swift")
        try "one\ntwo\nthree\nfour\nfive\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."])
        try runGit(["commit", "-m", "Initial"])
        try "one\ntwo\nthree\nchanged\nfive\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        let change = try XCTUnwrap(model.unstaged.first)
        model.select(change)
        await waitForDetailLoad(in: model)

        model.viewCurrentDiffInFiles()
        await waitForFileLoad(in: model)

        XCTAssertEqual(model.workspaceMode, .fileEditor)
        XCTAssertEqual(model.selectedRepositoryFilePath, "Sources/App/Example.swift")
        XCTAssertEqual(model.repositoryFileScrollRequest?.line, 1)
        XCTAssertTrue(model.expandedFileDirectories.contains("Sources"))
        XCTAssertTrue(model.expandedFileDirectories.contains("Sources/App"))
    }

    @MainActor
    func testFileEditorStateIsPerRepositoryAndRestoresAfterModeChanges() async throws {
        try runGit(["init", "-b", "main"])
        try "let answer = 42\n".write(
            to: repositoryURL.appendingPathComponent("Answer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let firstModel = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await firstModel.openRepository(repositoryURL)
        firstModel.setWorkspaceMode(.fileEditor)
        firstModel.toggleFileDirectory("Sources")
        firstModel.openRepositoryFile("Answer.swift")
        await waitForFileLoad(in: firstModel)

        XCTAssertEqual(firstModel.workspaceMode, .fileEditor)
        XCTAssertEqual(firstModel.expandedFileDirectories, ["Sources"])
        XCTAssertEqual(firstModel.selectedRepositoryFilePath, "Answer.swift")
        XCTAssertEqual(firstModel.detailKind, .source)
        XCTAssertEqual(firstModel.detailText, "let answer = 42\n")
        XCTAssertTrue(firstModel.isDiffPanelPresented)

        try "let answer = 43\n".write(
            to: repositoryURL.appendingPathComponent("Answer.swift"),
            atomically: true,
            encoding: .utf8
        )
        await firstModel.refresh()
        await waitForFileLoad(in: firstModel)
        XCTAssertEqual(firstModel.detailText, "let answer = 43\n")

        let secondModel = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await secondModel.openRepository(repositoryURL)
        XCTAssertEqual(secondModel.workspaceMode, .sourceControl)
        XCTAssertTrue(secondModel.expandedFileDirectories.isEmpty)

        firstModel.setWorkspaceMode(.sourceControl)

        XCTAssertEqual(firstModel.workspaceMode, .sourceControl)
        XCTAssertNil(firstModel.selectedRepositoryFilePath)
        XCTAssertFalse(firstModel.isDiffPanelPresented)
        XCTAssertEqual(firstModel.expandedFileDirectories, ["Sources"])

        firstModel.setWorkspaceMode(.fileEditor)
        await waitForFileLoad(in: firstModel)

        XCTAssertEqual(firstModel.selectedRepositoryFilePath, "Answer.swift")
        XCTAssertEqual(firstModel.detailText, "let answer = 43\n")
        XCTAssertTrue(firstModel.isDiffPanelPresented)
        XCTAssertEqual(firstModel.expandedFileDirectories, ["Sources"])

        firstModel.activateRepositoryFile("Answer.swift")
        XCTAssertNil(firstModel.selectedRepositoryFilePath)
        XCTAssertFalse(firstModel.isDiffPanelPresented)
    }

    @MainActor
    func testRefreshingUnchangedRepositoryDoesNotReplaceVisibleEditor() async throws {
        try runGit(["init", "-b", "main"])
        let sourceURL = repositoryURL.appendingPathComponent("Stable.swift")
        try "let value = 1\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false,
            monitoringEnabled: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Stable.swift")
        await waitForFileLoad(in: model)

        var loadingStates: [Bool] = []
        let loadingObserver = model.$isDetailLoading
            .dropFirst()
            .sink { loadingStates.append($0) }

        await model.refresh()

        XCTAssertFalse(loadingStates.contains(true))
        XCTAssertEqual(model.repositoryFileText, "let value = 1\n")
        XCTAssertEqual(model.detailKind, .source)
        withExtendedLifetime(loadingObserver) {}
    }

    @MainActor
    func testFileEditorDoesNotFollowSymlinksOutsideTheRepository() async throws {
        try runGit(["init", "-b", "main"])
        let externalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistExternal-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: externalURL) }
        try "outside\n".write(to: externalURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: repositoryURL.appendingPathComponent("outside.txt"),
            withDestinationURL: externalURL
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("outside.txt")

        XCTAssertEqual(model.detailKind, .message)
        XCTAssertEqual(
            model.detailText,
            "Kvist can only preview files inside this repository."
        )
        XCTAssertNil(model.selectedRepositoryFileURL)
        XCTAssertTrue(model.isDiffPanelPresented)
    }

    @MainActor
    func testGitDiffRestoresAfterSwitchingToFilesAndBack() async throws {
        try runGit(["init", "-b", "main"])
        try "changed\n".write(
            to: repositoryURL.appendingPathComponent("Changed.txt"),
            atomically: true,
            encoding: .utf8
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        let change = try XCTUnwrap(model.unstaged.first)
        model.select(change)
        await waitForDetailLoad(in: model)
        let expectedDetail = model.detailText

        model.setWorkspaceMode(.fileEditor)
        XCTAssertFalse(model.isDiffPanelPresented)

        model.setWorkspaceMode(.sourceControl)
        XCTAssertEqual(model.selectedChange, change)
        XCTAssertEqual(model.detailText, expectedDetail)
        XCTAssertTrue(model.isDiffPanelPresented)

        model.activate(change)
        XCTAssertNil(model.selectedChange)
        XCTAssertFalse(model.isDiffPanelPresented)
    }

    @MainActor
    func testTextFileCanBeEditedAndSavedWithoutRefreshOverwritingDraft() async throws {
        try runGit(["init", "-b", "main"])
        let sourceURL = repositoryURL.appendingPathComponent("Editable.swift")
        try "let value = 1\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Editable.swift")
        await waitForFileLoad(in: model)

        model.repositoryFileText = "let value = 2\n"
        XCTAssertTrue(model.isRepositoryFileDirty)

        model.setWorkspaceMode(.sourceControl)
        XCTAssertEqual(model.workspaceMode, .sourceControl)
        XCTAssertFalse(model.isDiffPanelPresented)

        model.setWorkspaceMode(.fileEditor)
        XCTAssertEqual(model.repositoryFileText, "let value = 2\n")
        XCTAssertTrue(model.isRepositoryFileDirty)
        XCTAssertEqual(model.selectedRepositoryFilePath, "Editable.swift")
        XCTAssertTrue(model.isDiffPanelPresented)

        await model.refresh()
        XCTAssertEqual(model.repositoryFileText, "let value = 2\n")

        await model.saveRepositoryFile()
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "let value = 2\n")
        XCTAssertFalse(model.isRepositoryFileDirty)
    }

    @MainActor
    func testReturningEditorTextToSavedValueClearsDirtyState() async throws {
        try runGit(["init", "-b", "main"])
        let sourceURL = repositoryURL.appendingPathComponent("Editable.swift")
        let savedText = "let value = 1\n"
        try savedText.write(to: sourceURL, atomically: true, encoding: .utf8)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Editable.swift")
        await waitForFileLoad(in: model)

        model.repositoryFileText = "let value = 2\n"
        XCTAssertTrue(model.isRepositoryFileDirty)
        model.repositoryFileText = savedText
        for _ in 0..<50 where model.isRepositoryFileDirty {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(model.isRepositoryFileDirty)
        XCTAssertFalse(model.canSaveRepositoryFile)
    }

    @MainActor
    func testSourceBeginningWithLoadingTextStillOpensInEditor() async throws {
        try runGit(["init", "-b", "main"])
        let sourceText = "Loading configuration…\nversion = 1\n"
        try sourceText.write(
            to: repositoryURL.appendingPathComponent("Config.txt"),
            atomically: true,
            encoding: .utf8
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Config.txt")
        await waitForFileLoad(in: model)

        XCTAssertEqual(model.detailKind, .source)
        XCTAssertEqual(model.repositoryFileText, sourceText)
    }

    @MainActor
    func testRefreshStopsShowingFileReplacedByExternalSymlink() async throws {
        try runGit(["init", "-b", "main"])
        let sourceURL = repositoryURL.appendingPathComponent("Source.swift")
        try "let value = 1\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )
        let externalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistExternal-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: externalURL) }
        try "outside\n".write(to: externalURL, atomically: true, encoding: .utf8)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Source.swift")
        await waitForFileLoad(in: model)
        XCTAssertEqual(model.detailText, "let value = 1\n")

        try FileManager.default.removeItem(at: sourceURL)
        try FileManager.default.createSymbolicLink(
            at: sourceURL,
            withDestinationURL: externalURL
        )
        await model.refresh()

        XCTAssertEqual(model.detailKind, .message)
        XCTAssertEqual(
            model.detailText,
            "Kvist can only preview files inside this repository."
        )
        XCTAssertNil(model.selectedRepositoryFileURL)
    }

    @MainActor
    func testRefreshPreservesDirtyDraftWhenFileBecomesExternalSymlink() async throws {
        try runGit(["init", "-b", "main"])
        let sourceURL = repositoryURL.appendingPathComponent("Source.swift")
        try "let value = 1\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )
        let externalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KvistExternal-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: externalURL) }
        try "outside\n".write(to: externalURL, atomically: true, encoding: .utf8)

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Source.swift")
        await waitForFileLoad(in: model)
        let draft = "let value = 2\n"
        model.repositoryFileText = draft

        try FileManager.default.removeItem(at: sourceURL)
        try FileManager.default.createSymbolicLink(
            at: sourceURL,
            withDestinationURL: externalURL
        )
        await model.refresh()

        XCTAssertEqual(model.detailKind, .source)
        XCTAssertEqual(model.repositoryFileText, draft)
        XCTAssertTrue(model.isRepositoryFileDirty)
        XCTAssertNil(model.selectedRepositoryFileURL)
        await model.saveRepositoryFile()
        XCTAssertEqual(
            model.errorMessage,
            "Kvist can only save files inside this repository."
        )
    }

    @MainActor
    func testRefreshPreservesDirtyDraftWhenFileIsDeleted() async throws {
        try runGit(["init", "-b", "main"])
        let sourceURL = repositoryURL.appendingPathComponent("Source.swift")
        try "let value = 1\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        let model = RepositoryModel(
            restoresLastRepository: false,
            persistsLastRepository: false
        )
        await model.openRepository(repositoryURL)
        model.setWorkspaceMode(.fileEditor)
        model.openRepositoryFile("Source.swift")
        await waitForFileLoad(in: model)
        let draft = "let value = 2\n"
        model.repositoryFileText = draft

        try FileManager.default.removeItem(at: sourceURL)
        await model.refresh()

        XCTAssertEqual(model.detailKind, .source)
        XCTAssertEqual(model.repositoryFileText, draft)
        XCTAssertTrue(model.isRepositoryFileDirty)
        XCTAssertTrue(model.isDiffPanelPresented)
    }

    @MainActor
    private func waitForFileLoad(in model: RepositoryModel) async {
        for _ in 0..<100 where model.isDetailLoading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func waitForDetailLoad(in model: RepositoryModel) async {
        for _ in 0..<100 where model.detailText.hasPrefix("Loading ") {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "git failed"
            throw NSError(
                domain: "RepositoryFileEditorTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: message
                ]
            )
        }
    }
}

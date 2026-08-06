import Foundation
import UniformTypeIdentifiers

enum RepositoryWorkspaceMode: String, CaseIterable, Identifiable, Codable {
    case sourceControl
    case fileEditor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sourceControl: return "Git"
        case .fileEditor: return "Files"
        }
    }

    var symbol: String {
        switch self {
        case .sourceControl: return "clock.arrow.trianglehead.clockwise.rotate.90.path.dotted"
        case .fileEditor: return "folder"
        }
    }

    var shortcutHint: String {
        switch self {
        case .sourceControl: return "⌘1"
        case .fileEditor: return "⌘2"
        }
    }
}

enum RepositoryDetailKind: String, Equatable, Codable {
    case diff
    case source
    case largeSource
    case preview
    case message
}

struct RepositoryEditorRestorationState: Codable, Equatable {
    let path: String
    let title: String
    let detailText: String
    let fileText: String
    let savedFileText: String
    let kind: RepositoryDetailKind
    let isPanelPresented: Bool
    let diskModificationDate: Date?
    let diskFileSize: Int?
    let diskContentHash: String?

    var isDirty: Bool {
        kind == .source && fileText != savedFileText
    }
}

struct RepositoryRestorationState: Codable, Equatable {
    var workspaceMode: RepositoryWorkspaceMode = .sourceControl
    var expandedFileDirectories: Set<String> = []
    var expandedCommitHashes: Set<String> = []
    var graphScope: GraphScope = .all
    var commitMessage = ""
    var editor: RepositoryEditorRestorationState?
}

struct SourceScrollRequest: Equatable {
    let id = UUID()
    let line: Int
    let highlightsLine: Bool

    init(line: Int, highlightsLine: Bool = false) {
        self.line = line
        self.highlightsLine = highlightsLine
    }
}

enum DiffNavigation {
    static func firstChangedLine(in diff: String) -> Int? {
        var changedLine: Int?
        diff.enumerateLines { line, stop in
            guard line.hasPrefix("@@") else { return }
            guard let newRange = line.split(separator: " ").first(where: {
                $0.hasPrefix("+")
            }) else { return }
            if let start = newRange
                .dropFirst()
                .split(separator: ",", maxSplits: 1)
                .first
                .flatMap({ Int($0) }) {
                changedLine = max(1, start)
                stop = true
            }
        }
        return changedLine
    }
}

enum RepositoryFileDocument: Equatable {
    case source(String)
    case largeSource(String)
    case preview
    case message(String)
}

struct RepositoryFileTreeItem: Identifiable, Equatable, Sendable {
    let url: URL
    let relativePath: String
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool

    var id: String { relativePath }
}

enum RepositoryFileLoader {
    static let maximumSourceFileSize = 1_024 * 1_024
    static let maximumReadOnlySourceFileSize = 128 * 1_024 * 1_024
    static let maximumNativePreviewFileSize = 32 * 1_024 * 1_024
    static let maximumSourceLineCount = 20_000
    static let maximumSourceLineLength = 20_000
    static let maximumReadOnlySourceLineLength = 1_024 * 1_024
    private static let textExtensions: Set<String> = [
        "c", "cc", "cpp", "cs", "css", "go", "h", "hpp", "html",
        "java", "js", "jsx", "kt", "m", "md", "mm", "php", "py",
        "rb", "rs", "scss", "sh", "sql", "svelte", "swift", "toml",
        "ts", "tsx", "txt", "vue", "xml", "yaml", "yml", "zsh"
    ]
    private static let directoryLoadingQueue = DispatchQueue(
        label: "com.hjalmarkarlsen.Kvist.directory-loading",
        qos: .userInitiated
    )

    private final class DirectoryLoadCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    static func loadChildren(
        of directoryURL: URL,
        parentRelativePath: String = ""
    ) async throws -> [RepositoryFileTreeItem] {
        let cancellation = DirectoryLoadCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                directoryLoadingQueue.async {
                    guard !cancellation.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        let items = try children(
                            of: directoryURL,
                            parentRelativePath: parentRelativePath,
                            fileManager: FileManager()
                        )
                        guard !cancellation.isCancelled else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume(returning: items)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    static func children(
        of directoryURL: URL,
        parentRelativePath: String = "",
        fileManager: FileManager = .default
    ) throws -> [RepositoryFileTreeItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard name != ".git", name != ".DS_Store" else { return nil }

            guard let values = try? url.resourceValues(forKeys: keys) else {
                return nil
            }
            let isSymbolicLink = values.isSymbolicLink ?? false
            let isDirectory = (values.isDirectory ?? false) && !isSymbolicLink
            let relativePath = parentRelativePath.isEmpty
                ? name
                : "\(parentRelativePath)/\(name)"
            return RepositoryFileTreeItem(
                url: url,
                relativePath: relativePath,
                name: name,
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func document(at url: URL) throws -> RepositoryFileDocument {
        let keys: Set<URLResourceKey> = [
            .contentTypeKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isRegularFile != false else {
            return .preview
        }
        let fileSize = values.fileSize ?? 0
        let hasKnownTextExtension = textExtensions.contains(
            url.pathExtension.lowercased()
        )
        let declaredText = isText(values.contentType, url: url)
        if !hasKnownTextExtension, prefersNativePreview(values.contentType) {
            return fileSize <= maximumNativePreviewFileSize
                ? .preview
                : .message("This file is too large to preview efficiently.")
        }
        guard fileSize <= maximumReadOnlySourceFileSize else {
            return .message("This file is too large to view efficiently.")
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let dimensions = sourceDimensions(in: data)
        guard dimensions.maximumLineLength <= maximumReadOnlySourceLineLength else {
            return .message("This file contains a line too large to view efficiently.")
        }
        let text = declaredText
            ? decodeText(data, allowsLegacyEncoding: true)
            : decodeUTF8Text(data)
        guard let text else {
            return .preview
        }
        let isEditable = fileSize <= maximumSourceFileSize
            && dimensions.lineCount <= maximumSourceLineCount
            && dimensions.maximumLineLength <= maximumSourceLineLength
        return isEditable ? .source(text) : .largeSource(text)
    }

    static func isImage(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = values.contentType else {
            return false
        }
        return contentType.conforms(to: .image)
    }

    static func prefersGitPreview(for urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        if urls.contains(where: prefersTextDiff) { return false }
        let documents = urls.compactMap { try? document(at: $0) }
        guard !documents.isEmpty else { return false }
        return documents.allSatisfy { document in
            switch document {
            case .source, .largeSource: return false
            case .preview, .message: return true
            }
        }
    }

    private static func prefersTextDiff(_ url: URL) -> Bool {
        return textExtensions.contains(url.pathExtension.lowercased())
    }

    private static func prefersNativePreview(_ contentType: UTType?) -> Bool {
        contentType?.conforms(to: .image) == true
            || contentType?.conforms(to: .pdf) == true
            || contentType?.conforms(to: .audiovisualContent) == true
    }

    private struct SourceDimensions {
        let lineCount: Int
        let maximumLineLength: Int
    }

    private static func sourceDimensions(in data: Data) -> SourceDimensions {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return SourceDimensions(lineCount: 1, maximumLineLength: 0)
            }
            var cursor = baseAddress.assumingMemoryBound(to: UInt8.self)
            var remaining = rawBuffer.count
            var lineCount = 1
            var maximumLineLength = 0

            while remaining > 0 {
                guard let match = memchr(cursor, Int32(0x0A), remaining) else {
                    maximumLineLength = max(maximumLineLength, remaining)
                    break
                }
                let newline = match.assumingMemoryBound(to: UInt8.self)
                let lineLength = cursor.distance(to: newline)
                maximumLineLength = max(maximumLineLength, lineLength)
                lineCount += 1
                let consumed = lineLength + 1
                cursor = cursor.advanced(by: consumed)
                remaining -= consumed
            }
            return SourceDimensions(
                lineCount: lineCount,
                maximumLineLength: maximumLineLength
            )
        }
    }

    private static func isText(_ contentType: UTType?, url: URL) -> Bool {
        if contentType?.conforms(to: .text) == true
            || contentType?.conforms(to: .sourceCode) == true {
            return true
        }
        if textExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        switch url.lastPathComponent.lowercased() {
        case "dockerfile", "gemfile", "license", "makefile", "podfile",
             ".dockerignore", ".editorconfig", ".env", ".gitattributes",
             ".gitignore", ".gitmodules":
            return true
        default:
            return false
        }
    }

    private static func decodeUTF8Text(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard !text.unicodeScalars.contains(where: { scalar in
            scalar.value < 32
                && scalar.value != 9
                && scalar.value != 10
                && scalar.value != 12
                && scalar.value != 13
        }) else { return nil }
        return text
    }

    private static func decodeText(
        _ data: Data,
        allowsLegacyEncoding: Bool
    ) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00])
            || data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return String(data: data, encoding: .utf32)
        }
        if data.starts(with: [0xFF, 0xFE])
            || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if allowsLegacyEncoding {
            return String(data: data, encoding: .isoLatin1)
        }
        return nil
    }
}

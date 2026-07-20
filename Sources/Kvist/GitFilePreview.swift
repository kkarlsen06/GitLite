import Foundation

enum GitFileDetailMode: String, CaseIterable, Identifiable {
    case diff
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diff: return "Diff"
        case .preview: return "Preview"
        }
    }
}

struct GitFilePreviewVersion: Equatable, Sendable {
    let title: String
    let context: String
    let url: URL
}

struct GitFilePreview: Equatable, Sendable {
    let old: GitFilePreviewVersion?
    let new: GitFilePreviewVersion?
    let temporaryDirectoryURL: URL?
    let prefersPreview: Bool

    var isAvailable: Bool {
        old != nil || new != nil
    }

    func removeTemporaryFiles() {
        guard let temporaryDirectoryURL else { return }
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}

enum GitFilePreviewSource: Sendable {
    case blob(object: String, path: String)
    case workingTree(URL)
}

enum GitFilePreviewMaterializer {
    static func make(
        old oldSource: GitFilePreviewSource?,
        new newSource: GitFilePreviewSource?,
        oldContext: String,
        newContext: String,
        client: GitClient
    ) throws -> GitFilePreview? {
        guard oldSource != nil || newSource != nil else { return nil }

        let requiresTemporaryDirectory = [oldSource, newSource].contains { source in
            guard let source else { return false }
            if case .blob = source { return true }
            return false
        }
        let temporaryDirectoryURL = requiresTemporaryDirectory
            ? FileManager.default.temporaryDirectory.appendingPathComponent(
                "Kvist-Git-Preview-\(UUID().uuidString)",
                isDirectory: true
            )
            : nil

        do {
            if let temporaryDirectoryURL {
                try FileManager.default.createDirectory(
                    at: temporaryDirectoryURL,
                    withIntermediateDirectories: true
                )
            }
            let old = try materialize(
                oldSource,
                title: "Old",
                context: oldContext,
                sideDirectoryName: "Old",
                temporaryDirectoryURL: temporaryDirectoryURL,
                client: client
            )
            let new = try materialize(
                newSource,
                title: "New",
                context: newContext,
                sideDirectoryName: "New",
                temporaryDirectoryURL: temporaryDirectoryURL,
                client: client
            )
            let urls = [old?.url, new?.url].compactMap { $0 }
            return GitFilePreview(
                old: old,
                new: new,
                temporaryDirectoryURL: temporaryDirectoryURL,
                prefersPreview: RepositoryFileLoader.prefersGitPreview(for: urls)
            )
        } catch {
            if let temporaryDirectoryURL {
                try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            }
            throw error
        }
    }

    private static func materialize(
        _ source: GitFilePreviewSource?,
        title: String,
        context: String,
        sideDirectoryName: String,
        temporaryDirectoryURL: URL?,
        client: GitClient
    ) throws -> GitFilePreviewVersion? {
        guard let source else { return nil }

        let url: URL
        switch source {
        case .workingTree(let workingTreeURL):
            url = workingTreeURL
        case .blob(let object, let path):
            guard let temporaryDirectoryURL else { return nil }
            let sideDirectoryURL = temporaryDirectoryURL.appendingPathComponent(
                sideDirectoryName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: sideDirectoryURL,
                withIntermediateDirectories: true
            )
            let name = URL(fileURLWithPath: path).lastPathComponent
            url = sideDirectoryURL.appendingPathComponent(
                name.isEmpty ? "Preview" : name,
                isDirectory: false
            )
            try client.writePreviewBlob(object: object, to: url)
        }

        return GitFilePreviewVersion(title: title, context: context, url: url)
    }
}

final class GitFilePreviewDirectoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var directoryURLs: Set<URL> = []

    func insert(_ preview: GitFilePreview?) {
        guard let directoryURL = preview?.temporaryDirectoryURL else { return }
        lock.lock()
        directoryURLs.insert(directoryURL)
        lock.unlock()
    }

    func remove(_ preview: GitFilePreview?, after delay: TimeInterval = 0) {
        guard let directoryURL = preview?.temporaryDirectoryURL else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            self.lock.lock()
            self.directoryURLs.remove(directoryURL)
            self.lock.unlock()
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func removeAll() {
        lock.lock()
        let urls = directoryURLs
        directoryURLs.removeAll()
        lock.unlock()
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    deinit {
        removeAll()
    }
}

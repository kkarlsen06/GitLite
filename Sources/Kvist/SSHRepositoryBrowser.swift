import SwiftUI

/// A folder on the remote machine shown in the SSH repository browser.
struct SSHBrowserEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder
        /// Contains a `.git` entry, so Kvist can open it directly.
        case repository
        /// Looks like a bare repository; Kvist needs a working tree to open it.
        case bareRepository
    }

    let name: String
    let path: String
    let kind: Kind

    var id: String { path }
}

/// Shell scripts and parsers for browsing a remote machine over SSH. Every
/// script runs through `/bin/sh -c` so the remote login shell never
/// interprets Kvist's POSIX syntax, and every remote path is single-quoted.
enum SSHBrowserRemote {
    /// Repository detection shared by the current-directory marker and the
    /// per-entry loop: a `.git` entry means a checkout (or worktree link),
    /// HEAD + objects + refs means a bare repository.
    private static let kindProbe = """
    if [ -e "$1/.git" ]; then t=r; \
    elif [ -f "$1/HEAD" ] && [ -d "$1/objects" ] && [ -d "$1/refs" ]; then t=b; \
    else t=d; fi
    """

    static var homeCommand: String {
        posixShellCommand("printf '%s' \"$HOME\"")
    }

    static func listCommand(directory: String, includeHidden: Bool) -> String {
        let hiddenFilter = includeHidden ? "" : "! -name '.*' "
        let script = """
        d=\(shellQuote(directory))
        set -- "$d"
        \(kindProbe)
        printf '%s\\0.\\0' "$t"
        find "$d" -mindepth 1 -maxdepth 1 \(hiddenFilter)-exec sh -c '\
        for item do \
        [ -d "$item" ] || continue; \
        set -- "$item"; \
        \(kindProbe); \
        printf "%s\\0%s\\0" "$t" "${item##*/}"; \
        done' sh {} +
        """
        return posixShellCommand(script)
    }

    /// Best-effort sweep for checkouts near the home folder so most users
    /// never have to navigate at all. Hidden folders other than `.git` are
    /// pruned, and the trailing `exit 0` keeps unreadable subfolders from
    /// failing the whole sweep.
    static var suggestionsCommand: String {
        posixShellCommand("""
        find "$HOME" -mindepth 1 -maxdepth 4 \
        \\( -name '.?*' ! -name .git -prune \\) -o -name .git -prune -print \
        2>/dev/null | head -n 40
        exit 0
        """)
    }

    static func parseListing(
        _ data: Data,
        directory: String
    ) -> (currentKind: SSHBrowserEntry.Kind, entries: [SSHBrowserEntry]) {
        let fields = data
            .split(separator: 0, omittingEmptySubsequences: false)
            .dropLast()
        var currentKind = SSHBrowserEntry.Kind.folder
        var entries: [SSHBrowserEntry] = []
        for index in stride(from: 0, to: fields.count, by: 2) {
            guard index + 1 < fields.count,
                  let type = String(data: fields[index], encoding: .utf8),
                  let name = String(data: fields[index + 1], encoding: .utf8) else {
                continue
            }
            let kind = kind(forType: type)
            if name == "." {
                currentKind = kind
                continue
            }
            guard name != ".git", name != "..", !name.isEmpty else { continue }
            entries.append(SSHBrowserEntry(
                name: name,
                path: join(directory, name),
                kind: kind
            ))
        }
        entries.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return (currentKind, entries)
    }

    /// Maps `find … -name .git` hits to the folders that contain them.
    static func parseSuggestions(_ data: Data) -> [String] {
        let text = String(decoding: data, as: UTF8.self)
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let path = String(line)
            guard path.hasSuffix("/.git") else { return nil }
            let repository = String(path.dropLast("/.git".count))
            guard repository.hasPrefix("/"),
                  seen.insert(repository).inserted else { return nil }
            return repository
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/\(name)" : "\(directory)/\(name)"
    }

    static func displayPath(_ path: String, home: String) -> String {
        guard home.hasPrefix("/"), home != "/" else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private static func kind(forType type: String) -> SSHBrowserEntry.Kind {
        switch type {
        case "r": return .repository
        case "b": return .bareRepository
        default: return .folder
        }
    }

    private static func posixShellCommand(_ script: String) -> String {
        "/bin/sh -c \(shellQuote(script))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

@MainActor
final class SSHRepositoryBrowserModel: ObservableObject {
    enum Phase: Equatable {
        case connecting
        case ready
        case failed(String)
    }

    let host: String

    @Published private(set) var phase: Phase = .connecting
    @Published private(set) var currentPath = "/"
    @Published private(set) var currentDirectoryKind: SSHBrowserEntry.Kind = .folder
    @Published private(set) var entries: [SSHBrowserEntry] = []
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var listingError: String?
    @Published var includeHiddenFolders = false {
        didSet {
            guard includeHiddenFolders != oldValue, phase == .ready else { return }
            navigate(to: currentPath)
        }
    }

    private(set) var homePath = "/"
    private var navigationGeneration = 0
    private var suggestionsTask: Task<Void, Never>?

    init(host: String) {
        self.host = host
    }

    func connect() async {
        phase = .connecting
        let host: String
        do {
            host = try SSHRepository.validatedHost(self.host)
        } catch {
            phase = .failed(Self.message(for: error))
            return
        }
        do {
            let homeData = try await Task.detached(priority: .userInitiated) {
                try GitClient.runSSH(host: host, command: SSHBrowserRemote.homeCommand)
            }.value
            let home = String(decoding: homeData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            homePath = home.hasPrefix("/") ? home : "/"
            phase = .ready
            navigate(to: homePath)
            loadSuggestions()
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func navigate(to path: String) {
        navigationGeneration += 1
        let generation = navigationGeneration
        let host = host
        let includeHidden = includeHiddenFolders
        isLoading = true
        listingError = nil
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try GitClient.runSSH(
                        host: host,
                        command: SSHBrowserRemote.listCommand(
                            directory: path,
                            includeHidden: includeHidden
                        )
                    )
                }.value
                guard generation == navigationGeneration else { return }
                let listing = SSHBrowserRemote.parseListing(data, directory: path)
                currentPath = path
                currentDirectoryKind = listing.currentKind
                entries = listing.entries
                isLoading = false
            } catch {
                guard generation == navigationGeneration else { return }
                isLoading = false
                listingError = Self.message(for: error)
            }
        }
    }

    func cancel() {
        navigationGeneration += 1
        suggestionsTask?.cancel()
    }

    private func loadSuggestions() {
        let host = host
        suggestionsTask = Task {
            guard let data = try? await Task.detached(priority: .utility, operation: {
                try GitClient.runSSH(
                    host: host,
                    command: SSHBrowserRemote.suggestionsCommand
                )
            }).value else { return }
            guard !Task.isCancelled else { return }
            suggestions = SSHBrowserRemote.parseSuggestions(data)
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? GitCommandError {
            let output = error.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? error.localizedDescription : output
        }
        return error.localizedDescription
    }
}

/// Finder-style picker for a repository on a remote machine: breadcrumb
/// navigation, repository badges, home-folder suggestions, and a manual path
/// field as the escape hatch.
struct SSHRepositoryBrowserView: View {
    let host: String
    let onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SSHRepositoryBrowserModel
    @State private var selectedTag: String?
    @State private var pathText = ""

    /// List tags carry a prefix so a repository that appears both as a
    /// suggestion and as a folder row keeps distinct selection identities.
    private static let suggestionTagPrefix = "suggestion:"
    private static let entryTagPrefix = "entry:"

    init(host: String, onOpen: @escaping (String) -> Void) {
        self.host = host
        self.onOpen = onOpen
        _model = StateObject(wrappedValue: SSHRepositoryBrowserModel(host: host))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.edge)
            content
            Divider().overlay(AppTheme.edge)
            footer
        }
        .frame(width: 620, height: 480)
        .background(AppTheme.canvas)
        .foregroundStyle(AppTheme.primary)
        .task { await model.connect() }
        .onDisappear { model.cancel() }
        .onChange(of: model.currentPath) { _, newPath in
            selectedTag = nil
            pathText = newPath
        }
        .onChange(of: selectedTag) { _, newTag in
            guard let path = resolvedPath(fromTag: newTag) else { return }
            pathText = path
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SSHLogo()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open over SSH")
                        .font(AppType.sectionTitle)
                    Text(host)
                        .font(AppType.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if model.phase == .ready {
                    Toggle("Show hidden folders", isOn: $model.includeHiddenFolders)
                        .toggleStyle(.checkbox)
                        .font(AppType.caption)
                        .foregroundStyle(AppTheme.secondary)
                }
            }
            if model.phase == .ready {
                breadcrumb
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(breadcrumbComponents, id: \.path) { crumb in
                    if crumb.path != "/" {
                        Image(systemName: "chevron.compact.right")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.muted)
                    }
                    Button {
                        model.navigate(to: crumb.path)
                    } label: {
                        Text(crumb.name)
                            .font(AppType.rowDetail)
                            .foregroundStyle(
                                crumb.path == model.currentPath
                                    ? AppTheme.primary
                                    : AppTheme.secondary
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(crumb.path == model.currentPath)
                }
                if model.currentDirectoryKind == .repository {
                    BranchGlyph(size: 11, color: AppTheme.graphBlue)
                        .padding(.leading, 4)
                        .help("This folder is a Git repository")
                }
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 6)
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .frame(height: 18)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .connecting:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Connecting to \(host)…")
                    .font(AppType.rowDetail)
                    .foregroundStyle(AppTheme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.conflict)
                Text("Could Not Connect")
                    .font(AppType.sectionTitle)
                Text(message)
                    .font(AppType.rowDetail)
                    .foregroundStyle(AppTheme.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Button("Try Again") {
                    Task { await model.connect() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        case .ready:
            browser
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            if let listingError = model.listingError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.conflict)
                    Text(listingError)
                        .font(AppType.caption)
                        .foregroundStyle(AppTheme.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(AppTheme.conflict.opacity(0.08))
            }
            List(selection: $selectedTag) {
                if showsSuggestions {
                    Section("Repositories in Your Home Folder") {
                        ForEach(model.suggestions, id: \.self) { path in
                            suggestionRow(path)
                                .tag(Self.suggestionTagPrefix + path)
                        }
                    }
                }
                Section(foldersSectionTitle) {
                    if model.entries.isEmpty && !model.isLoading {
                        Text("No subfolders")
                            .font(AppType.rowDetail)
                            .foregroundStyle(AppTheme.muted)
                    }
                    ForEach(model.entries) { entry in
                        entryRow(entry)
                            .tag(Self.entryTagPrefix + entry.path)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { tags in
                if let tag = tags.first,
                   let path = resolvedPath(fromTag: tag),
                   let entry = model.entries.first(where: { $0.path == path }) {
                    if entry.kind == .repository {
                        Button("Open Repository") { open(entry.path) }
                    } else {
                        Button("Open Folder Without Git") { open(entry.path) }
                        Button("Show Contents") { model.navigate(to: entry.path) }
                    }
                } else if let tag = tags.first, tag.hasPrefix(Self.suggestionTagPrefix) {
                    Button("Open Repository") {
                        open(String(tag.dropFirst(Self.suggestionTagPrefix.count)))
                    }
                }
            } primaryAction: { tags in
                handlePrimaryAction(tags)
            }
        }
    }

    private func entryRow(_ entry: SSHBrowserEntry) -> some View {
        HStack(spacing: 6) {
            switch entry.kind {
            case .folder:
                FolderIconView(expanded: false)
            case .repository:
                BranchGlyph(size: 13, color: AppTheme.graphBlue)
                    .frame(width: 19)
            case .bareRepository:
                BranchGlyph(size: 13, color: AppTheme.muted)
                    .frame(width: 19)
            }
            Text(entry.name)
                .font(AppType.rowDetail)
                .lineLimit(1)
            Spacer()
            switch entry.kind {
            case .repository:
                Text("Git repository")
                    .font(AppType.caption)
                    .foregroundStyle(AppTheme.muted)
            case .bareRepository:
                Text("bare — no working tree")
                    .font(AppType.caption)
                    .foregroundStyle(AppTheme.muted)
                    .help("Kvist needs a repository with a working tree")
            case .folder:
                EmptyView()
            }
        }
        .accessibilityLabel(accessibilityLabel(for: entry))
    }

    private func suggestionRow(_ path: String) -> some View {
        HStack(spacing: 6) {
            BranchGlyph(size: 13, color: AppTheme.graphBlue)
                .frame(width: 19)
            Text(SSHBrowserRemote.displayPath(path, home: model.homePath))
                .font(AppType.rowDetail)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .accessibilityLabel("Repository \(path)")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TextField(
                "Remote path",
                text: $pathText,
                prompt: Text("/srv/repository")
            )
            .textFieldStyle(.roundedBorder)
            .font(AppType.rowDetail)
            .onSubmit { openIfValid() }
            .accessibilityLabel("Remote path")

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(openButtonTitle) { openIfValid() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canOpen)
                .help(
                    opensRepository
                        ? "Open this Git repository"
                        : "Browse and edit this folder's files without Git"
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canOpen: Bool {
        pathText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    /// The button names what the typed or selected path will open as, so a
    /// plain folder is never mistaken for a repository. A typed path the
    /// browser has not listed reads "Open Folder"; the model probes it on
    /// open and still gives a Git repository the full workspace.
    private var openButtonTitle: String {
        opensRepository ? "Open Repository" : "Open Folder"
    }

    private var opensRepository: Bool {
        let path = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == model.currentPath {
            return model.currentDirectoryKind == .repository
        }
        if let entry = model.entries.first(where: { $0.path == path }) {
            return entry.kind == .repository
        }
        return model.suggestions.contains(path)
    }

    private var showsSuggestions: Bool {
        model.currentPath == model.homePath && !model.suggestions.isEmpty
    }

    private var foldersSectionTitle: String {
        model.currentPath == "/"
            ? "Folders at /"
            : "Folders in \(SSHBrowserRemote.displayPath(model.currentPath, home: model.homePath))"
    }

    private var breadcrumbComponents: [(name: String, path: String)] {
        var components: [(name: String, path: String)] = [(name: "/", path: "/")]
        var path = ""
        for component in model.currentPath.split(separator: "/") {
            path += "/\(component)"
            components.append((name: String(component), path: path))
        }
        return components
    }

    private func handlePrimaryAction(_ tags: Set<String>) {
        guard let tag = tags.first else { return }
        if tag.hasPrefix(Self.suggestionTagPrefix) {
            open(String(tag.dropFirst(Self.suggestionTagPrefix.count)))
            return
        }
        guard let path = resolvedPath(fromTag: tag),
              let entry = model.entries.first(where: { $0.path == path }) else { return }
        switch entry.kind {
        case .repository:
            open(entry.path)
        case .folder, .bareRepository:
            model.navigate(to: entry.path)
        }
    }

    private func resolvedPath(fromTag tag: String?) -> String? {
        guard let tag else { return nil }
        if tag.hasPrefix(Self.suggestionTagPrefix) {
            return String(tag.dropFirst(Self.suggestionTagPrefix.count))
        }
        if tag.hasPrefix(Self.entryTagPrefix) {
            return String(tag.dropFirst(Self.entryTagPrefix.count))
        }
        return nil
    }

    private func openIfValid() {
        let path = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else { return }
        open(path)
    }

    private func open(_ path: String) {
        dismiss()
        onOpen(path)
    }

    private func accessibilityLabel(for entry: SSHBrowserEntry) -> String {
        switch entry.kind {
        case .folder: return "Folder \(entry.name)"
        case .repository: return "Git repository \(entry.name)"
        case .bareRepository: return "Bare Git repository \(entry.name)"
        }
    }
}

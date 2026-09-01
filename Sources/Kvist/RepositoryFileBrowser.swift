import AppKit
import SwiftUI

private struct RepositoryFileTreeRevision: Hashable {
    let repositoryPath: String?
    let automatic: Int
}

struct RepositoryFileBrowser: View {
    @EnvironmentObject private var model: RepositoryModel
    @State private var items: [RepositoryFileTreeItem] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            browserHeader

            if model.isFileSearchPresented {
                repositorySearchField
            }

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            browserContents
        }
        .task(id: reloadRevision) {
            await loadRootItems()
        }
        .onChange(of: model.isFileSearchPresented) { _, isPresented in
            searchFieldFocused = isPresented
        }
    }

    private var browserHeader: some View {
        HStack(spacing: 8) {
            if model.isPlainFolder {
                PlainFolderBadge()
            } else {
                RepositoryModePicker()
            }

            Spacer()

            if model.sshRepository != nil {
                RepositoryReloadButton()
            }

            Button {
                model.toggleRepositorySearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                model.isFileSearchPresented
                    ? AppTheme.graphBlue
                    : AppTheme.secondary
            )
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .accessibilityLabel(
                model.isFileSearchPresented
                    ? "Close Repository Search"
                    : "Search Repository"
            )
            .help("Search Files and Contents (⇧⌘F)")

            RepositoryTerminalButton()
        }
        // 22pt leading and 46pt height match ChangesActionBar so the mode
        // picker stays in the same place when switching workspace modes.
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .frame(height: 46)
    }

    private var repositorySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.muted)

            TextField(
                "Search file names and contents",
                text: $model.repositorySearchQuery
            )
            .textFieldStyle(.plain)
            .font(AppType.rowDetail)
            .focused($searchFieldFocused)
            .accessibilityLabel("Search file names and contents")

            if model.isRepositorySearchLoading {
                ProgressView()
                    .controlSize(.mini)
            } else if !model.repositorySearchQuery.isEmpty {
                Button {
                    model.repositorySearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .frame(width: 18, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.muted)
                .accessibilityLabel("Clear Search")
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(AppTheme.inputFill)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    searchFieldFocused ? AppTheme.actionBlue : AppTheme.inputBorder,
                    lineWidth: 1
                )
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var browserContents: some View {
        if isSearching && model.isRepositorySearchLoading
            && model.repositorySearchResults.fileMatches.isEmpty {
            searchLoadingView
        } else if isSearching, let repositorySearchError = model.repositorySearchError {
            FileTreeMessage(
                symbol: "exclamationmark.triangle",
                message: repositorySearchError
            )
        } else if isSearching
                    && model.repositorySearchResults.fileMatches.isEmpty {
            FileTreeMessage(
                symbol: "magnifyingglass",
                message: "No matching file names."
            )
        } else if isLoading && items.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading files…")
                    .font(AppType.rowDetail)
                    .foregroundStyle(AppTheme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, items.isEmpty {
            FileTreeMessage(
                symbol: "exclamationmark.triangle",
                message: loadError
            )
        } else if items.isEmpty {
            FileTreeMessage(
                symbol: "folder",
                message: model.isPlainFolder
                    ? "This folder has no files."
                    : "This repository has no files."
            )
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        RepositoryFileTreeRow(
                            item: item,
                            depth: 0,
                            reloadRevision: reloadRevision,
                            matchingPaths: matchingPaths
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.visible)
        }
    }

    private var searchLoadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Searching files…")
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isSearching: Bool {
        model.isFileSearchPresented
            && !model.repositorySearchQuery
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private var matchingPaths: Set<String>? {
        isSearching ? model.repositorySearchResults.matchingFilePaths : nil
    }

    private var visibleItems: [RepositoryFileTreeItem] {
        guard let matchingPaths else { return items }
        return items.filter { item in
            Self.isVisible(item, matchingPaths: matchingPaths)
        }
    }

    fileprivate static func isVisible(
        _ item: RepositoryFileTreeItem,
        matchingPaths: Set<String>
    ) -> Bool {
        if item.isDirectory {
            let prefix = item.relativePath + "/"
            return matchingPaths.contains { $0.hasPrefix(prefix) }
        }
        return matchingPaths.contains(item.relativePath)
    }

    private var reloadRevision: RepositoryFileTreeRevision {
        RepositoryFileTreeRevision(
            repositoryPath: model.repositoryURL?.standardizedFileURL.path,
            automatic: model.repositoryFilesRevision
        )
    }

    private func loadRootItems() async {
        guard let repositoryURL = model.repositoryURL else {
            items = []
            loadError = nil
            return
        }

        isLoading = true
        loadError = nil
        do {
            let loaded = try await model.repositoryFileChildren(
                at: repositoryURL
            )
            guard !Task.isCancelled,
                  model.repositoryURL == repositoryURL else {
                isLoading = false
                return
            }
            items = loaded
        } catch {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            items = []
            loadError = "Could not load this repository’s files."
        }
        isLoading = false
    }
}

struct RepositoryReloadButton: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.secondary)
        .disabled(model.isBusy)
        .accessibilityLabel(model.isPlainFolder ? "Reload SSH Folder" : "Reload SSH Repository")
        .help(model.isPlainFolder ? "Reload SSH Folder (⌘R)" : "Reload SSH Repository (⌘R)")
    }
}

/// Stands in for the Git/Files mode picker when a folder is open without
/// Git: there is no source-control mode to switch to.
struct PlainFolderBadge: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.secondary)
            Text("Files")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.primary)
            Button("No Git") {
                model.requestRepositoryInitialization()
            }
            .buttonStyle(.plain)
            .font(AppType.caption)
            .foregroundStyle(AppTheme.muted)
            .disabled(model.isBusy)
            .accessibilityLabel("Initialize Git Repository")
            .help("This folder is opened without Git. Click to initialize a Git repository.")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

private struct RepositoryFileTreeRow: View {
    @EnvironmentObject private var model: RepositoryModel
    let item: RepositoryFileTreeItem
    let depth: Int
    let reloadRevision: RepositoryFileTreeRevision
    let matchingPaths: Set<String>?

    @State private var children: [RepositoryFileTreeItem] = []
    @State private var isLoadingChildren = false
    @State private var childrenLoadFailed = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: activate) {
                rowLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(rowBackground)
            .onHover { hovering = $0 }
            .help(item.relativePath)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }

                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.path, forType: .string)
                }
            }

            if item.isDirectory && isExpanded {
                if isLoadingChildren && children.isEmpty {
                    childStatusRow(symbol: nil, text: "Loading…")
                } else if childrenLoadFailed && children.isEmpty {
                    childStatusRow(
                        symbol: "exclamationmark.triangle",
                        text: "Could not open folder"
                    )
                } else if children.isEmpty {
                    childStatusRow(symbol: nil, text: "Empty folder")
                } else {
                    ForEach(visibleChildren) { child in
                        RepositoryFileTreeRow(
                            item: child,
                            depth: depth + 1,
                            reloadRevision: reloadRevision,
                            matchingPaths: matchingPaths
                        )
                    }
                }
            }
        }
        .task(id: folderLoadRequest) {
            guard item.isDirectory, isExpanded else { return }
            await loadChildren()
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: item.isDirectory ? disclosureSymbol : "")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 11)
                .opacity(item.isDirectory ? 1 : 0)

            if item.isDirectory {
                FolderIconView(expanded: isExpanded, size: 13, width: 19)
            } else {
                FileIconView(path: item.relativePath, size: 13, width: 19)
            }

            Text(item.name)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if item.isSymbolicLink {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16 + CGFloat(depth) * 16)
        .padding(.trailing, 22)
        .frame(height: 28)
    }

    private var rowBackground: Color {
        if isSelected { return AppTheme.selection }
        return hovering ? AppTheme.hover : .clear
    }

    private var isSelected: Bool {
        !item.isDirectory
            && model.selectedRepositoryFilePath == item.relativePath
    }

    private var isExpanded: Bool {
        if let matchingPaths, item.isDirectory {
            return RepositoryFileBrowser.isVisible(
                item,
                matchingPaths: matchingPaths
            )
        }
        return model.expandedFileDirectories.contains(item.relativePath)
    }

    private var visibleChildren: [RepositoryFileTreeItem] {
        guard let matchingPaths else { return children }
        return children.filter { child in
            RepositoryFileBrowser.isVisible(
                child,
                matchingPaths: matchingPaths
            )
        }
    }

    private var disclosureSymbol: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }

    private var folderSymbol: String {
        isExpanded ? "folder.fill" : "folder"
    }

    private var fileSymbol: String {
        FileGlyph.symbol(forPath: item.relativePath)
    }

    private var accessibilityLabel: String {
        guard item.isDirectory else { return item.name }
        return "\(item.name), folder, \(isExpanded ? "expanded" : "collapsed")"
    }

    private var accessibilityHint: String {
        if item.isDirectory { return "Toggles this folder" }
        return isSelected ? "Closes this file" : "Opens this file"
    }

    private var folderLoadRequest: FolderLoadRequest {
        FolderLoadRequest(
            revision: reloadRevision,
            isExpanded: isExpanded
        )
    }

    private func activate() {
        if item.isDirectory {
            model.toggleFileDirectory(item.relativePath)
        } else if model.isFileSearchPresented {
            model.openRepositorySearchMatch(item.relativePath)
        } else {
            model.activateRepositoryFile(item.relativePath)
        }
    }

    private func loadChildren() async {
        isLoadingChildren = true
        childrenLoadFailed = false
        do {
            let loaded = try await model.repositoryFileChildren(
                at: item.url,
                parentRelativePath: item.relativePath
            )
            guard !Task.isCancelled, isExpanded else {
                isLoadingChildren = false
                return
            }
            children = loaded
        } catch {
            guard !Task.isCancelled else {
                isLoadingChildren = false
                return
            }
            children = []
            childrenLoadFailed = true
        }
        isLoadingChildren = false
    }

    private func childStatusRow(symbol: String?, text: String) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10))
            } else if isLoadingChildren {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(text)
                .font(AppType.caption)

            Spacer()
        }
        .foregroundStyle(AppTheme.muted)
        .padding(.leading, 53 + CGFloat(depth) * 16)
        .padding(.trailing, 22)
        .frame(height: 26)
    }
}

private struct FolderLoadRequest: Hashable {
    let revision: RepositoryFileTreeRevision
    let isExpanded: Bool
}

private struct FileTreeMessage: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.muted)

            Text(message)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RepositorySearchResultsPanel: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            panelContents
        }
        .background(AppTheme.diffCanvas)
        .background {
            EscapeKeyMonitor {
                model.dismissRepositorySearch()
            }
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.secondary)

            Text("Search Results")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.primary)

            if !model.repositorySearchQuery.isEmpty {
                Text("\(model.repositorySearchResults.textMatches.count)")
                    .font(AppType.caption)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityLabel(
                        "\(model.repositorySearchResults.textMatches.count) text matches"
                    )
            }

            Spacer(minLength: 4)

            Button {
                model.dismissRepositorySearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondary)
            .accessibilityLabel("Close Search Results")
            .help("Close Search Results (⎋)")
        }
        .padding(.leading, 10)
        .frame(height: 36)
        .background(AppTheme.raisedFill)
    }

    @ViewBuilder
    private var panelContents: some View {
        let query = model.repositorySearchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            SearchPanelMessage(
                symbol: "text.magnifyingglass",
                message: "Type to search inside repository files."
            )
        } else if model.isRepositorySearchLoading
                    && model.repositorySearchResults.textMatches.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching contents…")
                    .font(AppType.rowDetail)
                    .foregroundStyle(AppTheme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let repositorySearchError = model.repositorySearchError {
            SearchPanelMessage(
                symbol: "exclamationmark.triangle",
                message: repositorySearchError
            )
        } else if textMatchGroups.isEmpty {
            SearchPanelMessage(
                symbol: "doc.text.magnifyingglass",
                message: "No text matches. File-name matches appear in Files."
            )
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(textMatchGroups) { group in
                        Section {
                            ForEach(group.matches) { match in
                                RepositoryTextSearchResultRow(match: match)
                            }
                        } header: {
                            searchGroupHeader(group)
                        }
                    }

                    if model.repositorySearchResults.textMatchesWereLimited {
                        Text("More text matches are available. Refine the search to narrow the results.")
                            .font(AppType.caption)
                            .foregroundStyle(AppTheme.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }

    private func searchGroupHeader(_ group: RepositoryTextSearchMatchGroup) -> some View {
        HStack(spacing: 7) {
            FileIconView(path: group.path, size: 12, width: 18)

            Text(URL(fileURLWithPath: group.path).lastPathComponent)
                .font(AppType.captionEmphasis)
                .foregroundStyle(AppTheme.primary)
                .lineLimit(1)

            let parentPath = (group.path as NSString).deletingLastPathComponent
            if parentPath != "." {
                Text(parentPath)
                    .font(AppType.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Text("\(group.matches.count)")
                .font(AppType.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(AppTheme.raisedFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)
        }
    }

    private var textMatchGroups: [RepositoryTextSearchMatchGroup] {
        let grouped = Dictionary(
            grouping: model.repositorySearchResults.textMatches,
            by: \.path
        )
        return grouped.map { path, matches in
            RepositoryTextSearchMatchGroup(path: path, matches: matches)
        }
        .sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }
}

private struct RepositoryTextSearchMatchGroup: Identifiable {
    let path: String
    let matches: [RepositoryTextSearchMatch]

    var id: String { path }
}

private struct RepositoryTextSearchResultRow: View {
    @EnvironmentObject private var model: RepositoryModel
    let match: RepositoryTextSearchMatch
    @State private var hovering = false

    var body: some View {
        Button {
            model.openRepositorySearchMatch(match.path, line: match.line)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(match.line)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
                    .frame(minWidth: 34, alignment: .trailing)

                Text(match.preview.isEmpty ? " " : match.preview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? AppTheme.hover : AppTheme.diffCanvas)
        .onHover { hovering = $0 }
        .help("\(match.path):\(match.line)")
        .accessibilityLabel(
            "\(match.path), line \(match.line), \(match.preview)"
        )
        .accessibilityHint("Opens the file at this line")
    }
}

private struct SearchPanelMessage: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.muted)

            Text(message)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

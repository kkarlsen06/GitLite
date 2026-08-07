import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppTheme {
    private(set) static var palette = AppThemePalette.ayuDark

    static func apply(_ palette: AppThemePalette) {
        self.palette = palette
    }

    // Surfaces
    static var canvas: Color { Color(hex: palette.canvas) }
    static var edge: Color { Color(hex: palette.edge) }
    static var inputFill: Color { Color(hex: palette.inputFill) }
    static var hover: Color { Color(hex: palette.hover) }
    static var raisedFill: Color { Color(hex: palette.raisedFill) }
    static var diffCanvas: Color { Color(hex: palette.diffCanvas) }
    static var disabledFill: Color { Color(hex: palette.disabledFill) }
    /// Recessed fill for the tab strip. Always darker than the canvas so the
    /// active tab and the panel it merges into read as one elevated surface
    /// in front of the strip (browser-style), never as content showing
    /// through a slot in a raised bar.
    static var tabStripFill: Color {
        let isDark = ColorMath.luminance(palette.canvas) < 0.5
        return Color(hex: ColorMath.mix(palette.canvas, 0x000000, isDark ? 0.28 : 0.10))
    }
    static var selection: Color { Color(hex: palette.selection).opacity(0.26) }
    static var selectionNSColor: NSColor {
        NSColor(hex: palette.selection).withAlphaComponent(0.26)
    }

    // Text
    static var primary: Color { Color(hex: palette.primary) }
    static var secondary: Color { Color(hex: palette.secondary) }
    static var muted: Color { Color(hex: palette.muted) }
    static var onAccent: Color { Color(hex: palette.onAccent) }
    static var onDestructive: Color { Color(hex: palette.onDestructive) }
    static var onPill: Color { Color(hex: palette.onPill) }
    static var badgeText: Color { Color(hex: palette.badgeText) }

    // Accents
    static var actionBlue: Color { Color(hex: palette.actionBlue) }
    static var graphBlue: Color { Color(hex: palette.graphBlue) }
    static var graphRemote: Color { Color(hex: palette.graphRemote) }
    static var graphReferenceBackground: Color { Color(hex: palette.graphReferenceBackground) }
    static var badgeBlue: Color { Color(hex: palette.badgeBlue) }
    static var inputBorder: Color { Color(hex: palette.inputBorder) }

    // File status colors
    static var modified: Color { Color(hex: palette.modified) }
    static var added: Color { Color(hex: palette.added) }
    static var deleted: Color { Color(hex: palette.deleted) }
    static var conflict: Color { Color(hex: palette.conflict) }
    static var destructiveButton: Color { Color(hex: palette.readableDestructiveButton) }
    static var swift: Color { Color(hex: palette.swift) }

    // Diff rendering
    static var diffHeaderText: Color { Color(hex: palette.diffHeaderText) }
    static var diffHunkText: Color { Color(hex: palette.diffHunkText) }
    static var diffHunkBackground: Color { Color(hex: palette.diffHunkBackground) }
    static var diffAddedText: Color { Color(hex: palette.diffAddedText) }
    static var diffAddedBackground: Color { Color(hex: palette.diffAddedBackground) }
    static var diffRemovedText: Color { Color(hex: palette.diffRemovedText) }
    static var diffRemovedBackground: Color { Color(hex: palette.diffRemovedBackground) }

    /// Graph lanes cycle through fixed hues; adjust them so they stay
    /// visible against whichever canvas the active theme brings.
    static func graphLane(_ hex: UInt32) -> Color {
        Color(hex: ColorMath.ensureContrast(hex, over: palette.canvas, ratio: 2.2))
    }

    static var canvasNSColor: NSColor { NSColor(hex: palette.canvas) }
    static var diffCanvasNSColor: NSColor { NSColor(hex: palette.diffCanvas) }
    static var primaryNSColor: NSColor { NSColor(hex: palette.primary) }
    static var secondaryNSColor: NSColor { NSColor(hex: palette.secondary) }
    static var mutedNSColor: NSColor { NSColor(hex: palette.muted) }
    static var edgeNSColor: NSColor { NSColor(hex: palette.edge) }
    static var graphBlueNSColor: NSColor { NSColor(hex: palette.graphBlue) }
    static var addedNSColor: NSColor { NSColor(hex: palette.added) }
    static var conflictNSColor: NSColor { NSColor(hex: palette.conflict) }
}

/// Panel-wide type scale. Every text style in the app draws from this ramp so
/// hierarchy stays consistent: panel titles < supporting detail < row content.
enum AppType {
    /// Uppercase panel titles (CHANGES, GRAPH).
    static let panelTitle = Font.system(size: 13, weight: .semibold)
    /// Section headers such as "Staged Changes".
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    /// Primary row content: filenames and commit subjects.
    static let row = Font.system(size: 15)
    static let rowEmphasis = Font.system(size: 15, weight: .semibold)
    /// Supporting labels beside row content: paths and branch names.
    static let rowDetail = Font.system(size: 13)
    /// Nested rows inside graph expansions.
    static let nestedRow = Font.system(size: 13)
    static let nestedRowDetail = Font.system(size: 12)
    /// Counts, pagination, hints, and the status strip.
    static let caption = Font.system(size: 12)
    static let captionEmphasis = Font.system(size: 12, weight: .medium)
    /// Single-letter Git status codes.
    static let statusLetter = Font.system(size: 13, weight: .semibold, design: .monospaced)
    static let nestedStatusLetter = Font.system(size: 12, weight: .semibold, design: .monospaced)
}

/// Shared file-type iconography so working-tree rows and history rows always
/// render the same glyph for the same file.
enum FileGlyph {
    static func symbol(forPath path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift":
            return "swift"
        case "md", "txt", "rst":
            return "doc.text"
        case "json", "yml", "yaml", "toml", "plist", "xcconfig":
            return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "icns", "pdf":
            return "photo"
        case "sh", "zsh", "bash", "fish":
            return "terminal"
        case "js", "ts", "jsx", "tsx", "py", "rb", "go", "rs", "c", "h",
             "cpp", "hpp", "m", "mm", "java", "kt", "cs", "html", "css", "scss":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }

    static func color(forSymbol symbol: String) -> Color {
        symbol == "swift" ? AppTheme.swift : AppTheme.secondary
    }
}

/// File icon shared by every row: the active icon pack's image when one is
/// selected, otherwise the built-in SF Symbol glyph.
struct FileIconView: View {
    let path: String
    var size: CGFloat = 14
    var width: CGFloat = 21

    var body: some View {
        if let image = AppIcons.image(forPath: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size + 2, height: size + 2)
                .frame(width: width)
        } else {
            let symbol = FileGlyph.symbol(forPath: path)
            Image(systemName: symbol)
                .font(.system(size: symbol == "swift" ? size + 3 : size, weight: .regular))
                .foregroundStyle(FileGlyph.color(forSymbol: symbol))
                .frame(width: width)
        }
    }
}

struct FolderIconView: View {
    let expanded: Bool
    var size: CGFloat = 13
    var width: CGFloat = 19

    var body: some View {
        if let image = AppIcons.folderImage(expanded: expanded) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size + 2, height: size + 2)
                .frame(width: width)
        } else {
            Image(systemName: expanded ? "folder.fill" : "folder")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(AppTheme.secondary)
                .frame(width: width)
        }
    }
}

/// The VS Code Codicon "git-branch" (CC BY 4.0, see THIRD_PARTY_NOTICES).
struct BranchGlyph: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        CodiconGlyph(icon: .gitBranch, size: size, color: color)
    }
}

struct SSHLogo: View {
    private static let image = Bundle.kvistResources.url(
        forResource: "Unofficial_SSH_Logo",
        withExtension: "svg"
    ).flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        }
    }
}
struct ContentView: View {
    @EnvironmentObject private var tabsModel: WorkspaceTabsModel

    var body: some View {
        VStack(spacing: 0) {
            RepositoryTopBar()

            ActiveRepositoryView(tab: tabsModel.activeTab)

            RepositoryStatusBar(tab: tabsModel.activeTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvas)
        .foregroundStyle(AppTheme.primary)
        .ignoresSafeArea(edges: .top)
    }
}

private struct RepositoryStatusBar: View {
    @ObservedObject private var tab: RepositoryTab
    @ObservedObject var model: RepositoryModel

    init(tab: RepositoryTab) {
        _tab = ObservedObject(wrappedValue: tab)
        _model = ObservedObject(wrappedValue: tab.model)
    }

    var body: some View {
        HStack(spacing: 0) {
            if model.repositoryURL != nil {
                branchMenu

                Spacer(minLength: 0)

                if model.activeOperation != nil {
                    activeOperationControls

                    Spacer(minLength: 0)
                } else if showsActivity {
                    activityLabel

                    Spacer(minLength: 0)
                }

                syncButton
            } else if model.isBusy || tab.isRepositoryLoadPending {
                Spacer(minLength: 0)

                activityLabel

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        // Matches the 34pt top tab bar.
        .frame(height: 34)
        .background(AppTheme.inputFill)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)
        }
        .foregroundStyle(AppTheme.primary)
        .accessibilityElement(children: .contain)
    }

    private var branchMenu: some View {
        Menu {
            Button("New Branch…") {
                guard let name = GitPrompt.branchName(from: model.branch) else { return }
                Task { await model.createBranchAtHead(named: name) }
            }
            .disabled(model.headHash == nil)

            Button("Rename Current Branch…") {
                guard let reference = currentBranchReference,
                      let name = GitPrompt.renamedBranch(reference) else { return }
                Task { await model.renameBranch(reference, to: name) }
            }
            .disabled(currentBranchReference == nil)

            Menu("Upstream") {
                if remoteBranches.isEmpty {
                    Text("No remote branches")
                } else {
                    ForEach(remoteBranches) { reference in
                        Button {
                            Task { await model.setUpstream(reference) }
                        } label: {
                            if reference.id == model.upstreamReference?.id {
                                Label(reference.name, systemImage: "checkmark")
                            } else {
                                Text(reference.name)
                            }
                        }
                    }
                }

                if model.hasUpstream {
                    Divider()

                    Button("Unset Upstream") {
                        Task { await model.unsetUpstream() }
                    }
                }
            }
            .disabled(model.branch == "detached HEAD" || model.headHash == nil)

            Divider()

            if localBranches.isEmpty && remoteBranches.isEmpty {
                Text(model.repositoryURL == nil ? "Open a repository first" : "No branches")
            } else {
                if !localBranches.isEmpty {
                    Section("Branches") {
                        ForEach(localBranches) { reference in
                            branchMenuItem(reference)
                        }
                    }
                }

                if !remoteBranches.isEmpty {
                    Section("Remote Branches") {
                        ForEach(remoteBranches) { reference in
                            branchMenuItem(reference)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                branchIcon

                Text(branchLabel)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 250, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(AppTheme.primary)
        .help("Checkout Branch…")
        .accessibilityLabel("Current branch: \(branchLabel)")
        .disabled(
            model.repositoryURL == nil
                || model.isBusy
                || model.isGeneratingCommitMessage
                || model.hasPendingChangeOperations
        )
    }

    private func branchMenuItem(_ reference: GitReference) -> some View {
        Button {
            Task { await model.checkout(reference) }
        } label: {
            if reference.isHead {
                Label(reference.name, systemImage: "checkmark")
            } else {
                Text(reference.name)
            }
        }
    }

    private var branchIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            BranchGlyph(size: 14, color: AppTheme.primary)

            if model.hasStagedChanges {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.added)
                    .background(AppTheme.inputFill, in: Circle())
                    .offset(x: 3, y: 3)
            } else if !model.unstaged.isEmpty {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4, weight: .bold))
                    .foregroundStyle(AppTheme.modified)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var syncButton: some View {
        Button {
            Task {
                if model.hasUpstream {
                    await model.sync()
                } else {
                    await model.publish()
                }
            }
        } label: {
            HStack(spacing: 5) {
                SpinningCodiconGlyph(
                    icon: syncIcon,
                    isSpinning: model.isSyncing && model.hasUpstream,
                    size: 14
                )

                if !syncCountLabel.isEmpty {
                    Text(syncCountLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.secondary)
        .disabled(syncOperationsDisabled)
        .help(syncHelp)
        .accessibilityLabel(syncHelp)
    }

    private var syncOperationsDisabled: Bool {
        model.repositoryURL == nil
            || model.isBusy
            || model.isGeneratingCommitMessage
            || model.hasPendingChangeOperations
            || (!model.hasUpstream && model.branch == "detached HEAD")
            || (!model.hasUpstream && model.headHash == nil)
    }

    private var activityLabel: some View {
        HStack(spacing: 5) {
            if activityIsInProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppTheme.secondary)
            }

            Text(activityText)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(AppTheme.secondary)
        .frame(maxWidth: 180)
        .help(activityText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Repository status: \(activityText)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var activeOperationControls: some View {
        if let operation = model.activeOperation {
            HStack(spacing: 9) {
                Text(operation.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)

                Button("Continue") {
                    Task { await model.continueActiveOperation() }
                }
                .help("Continue " + operation.displayName.lowercased())
                .disabled(model.hasUnresolvedConflicts)

                if model.canSkipActiveOperation {
                    Button("Skip") {
                        Task { await model.skipActiveOperation() }
                    }
                    .help("Skip the current commit")
                }

                Button("Abort", role: .destructive) {
                    Task { await model.abortActiveOperation() }
                }
                .foregroundStyle(AppTheme.deleted)
                .help("Abort " + operation.displayName.lowercased())
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .disabled(model.isBusy || model.hasPendingChangeOperations)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(operation.displayName + " in progress")
        }
    }

    private var showsActivity: Bool {
        model.activity != "Ready" && model.activity != "Up to date"
    }

    private var activityIsInProgress: Bool {
        tab.isRepositoryLoadPending
            || model.isBusy
            || model.isGeneratingCommitMessage
            || model.hasPendingChangeOperations
            || model.isLoadingMoreGraph
            || !model.loadingCommitFileHashes.isEmpty
    }

    private var activityText: String {
        if tab.isRepositoryLoadPending && !model.isBusy {
            return "Opening repository…"
        }
        return model.activity
    }

    private var localBranches: [GitReference] {
        model.references
            .filter { $0.kind == .localBranch }
            .sorted { lhs, rhs in
                if lhs.isHead != rhs.isHead { return lhs.isHead }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var currentBranchReference: GitReference? {
        localBranches.first(where: \.isHead)
    }

    private var remoteBranches: [GitReference] {
        model.references
            .filter {
                $0.kind == .remoteBranch && !$0.name.hasSuffix("/HEAD")
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var branchLabel: String {
        guard model.repositoryURL != nil else {
            return model.isBusy ? "Opening…" : "No Repository"
        }

        let head = model.branch.isEmpty ? "detached HEAD" : model.branch
        let workingTreeMarker = model.unstaged.isEmpty ? "" : "*"
        let stagedMarker = model.hasStagedChanges ? "+" : ""
        return head + workingTreeMarker + stagedMarker
    }

    private var syncIcon: Codicon {
        model.hasUpstream ? .sync : .repoPush
    }

    private var syncCountLabel: String {
        guard model.hasUpstream else { return "" }
        var parts: [String] = []
        if model.behind > 0 { parts.append("\(model.behind)↓") }
        if model.ahead > 0 { parts.append("\(model.ahead)↑") }
        return parts.joined(separator: " ")
    }

    private var syncHelp: String {
        guard model.repositoryURL != nil else { return "Open a repository" }
        guard model.hasUpstream else {
            return model.branch == "detached HEAD" ? "No upstream branch" : "Publish Branch"
        }
        if model.ahead == 0 && model.behind == 0 {
            return "Synchronize Changes"
        }
        return "Synchronize Changes\(syncCountLabel.isEmpty ? "" : " (\(syncCountLabel))")"
    }
}

private struct ActiveRepositoryView: View {
    @ObservedObject private var tab: RepositoryTab
    @ObservedObject private var model: RepositoryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("repositorySplitFraction")
    private var repositorySplitFraction = RepositorySplitLayout.defaultFraction
    @State private var repositoryWidthAtDragStart: CGFloat?

    init(tab: RepositoryTab) {
        _tab = ObservedObject(wrappedValue: tab)
        _model = ObservedObject(wrappedValue: tab.model)
    }

    var body: some View {
        GeometryReader { geometry in
            let split = RepositorySplitLayout.metrics(
                totalWidth: geometry.size.width,
                preferredFraction: repositorySplitFraction,
                minimumDetailWidth: model.conflictResolution != nil
                    && !model.isFileSearchResultsPresented
                    ? RepositorySplitLayout.conflictDiffWidth
                    : RepositorySplitLayout.minimumPaneWidth
            )
            let repositoryWidth = model.isRepositorySidePanelPresented
                ? split.repositoryWidth
                : geometry.size.width

            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        RepositoryContentView(
                            isRepositoryLoadPending: tab.isRepositoryLoadPending,
                            pendingRepositoryName: tab.displayName
                        )
                        .frame(width: repositoryWidth)
                        .frame(maxHeight: .infinity)
                        .background(AppTheme.canvas)

                        if model.isRepositorySidePanelPresented {
                            Color.clear
                                .frame(width: RepositorySplitLayout.separatorWidth)

                            Group {
                                if model.isFileSearchResultsPresented {
                                    RepositorySearchResultsPanel()
                                } else {
                                    RepositoryEditorPanel()
                                }
                            }
                                .frame(width: split.detailWidth)
                                .frame(maxHeight: .infinity)
                                .clipped()
                        }
                    }

                    if model.isRepositorySidePanelPresented {
                        RepositorySplitResizeHandle(
                            fraction: $repositorySplitFraction,
                            widthAtDragStart: $repositoryWidthAtDragStart,
                            currentRepositoryWidth: split.repositoryWidth,
                            availablePaneWidth: split.availablePaneWidth,
                            allowedRepositoryWidths: split.allowedRepositoryWidths
                        )
                        .offset(
                            x: split.repositoryWidth
                                - RepositorySplitLayout.resizeHandleInset
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(model)
        .overlay(alignment: .topLeading) {
            DiffPanelWindowExpansion(
                isExpanded: model.isRepositorySidePanelPresented,
                minimumExpandedWidth: model.conflictResolution != nil
                    && !model.isFileSearchResultsPresented
                    ? RepositorySplitLayout.conflictExpandedWidth
                    : nil,
                reduceMotion: reduceMotion
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }
}

enum RepositorySplitLayout {
    static let defaultFraction = 0.5
    static let repositoryWidth: CGFloat = 465
    static let separatorWidth: CGFloat = 1
    static let resizeHandleWidth: CGFloat = 5
    static let resizeHandleInset = (resizeHandleWidth - separatorWidth) / 2
    static let minimumPaneWidth: CGFloat = 300
    static let diffWidth: CGFloat = repositoryWidth
    /// The conflict resolver's toolbar needs ~526pt before its fixed labels
    /// ("Edit File Manually", "Resolve All", "Mark Resolved") start
    /// truncating; only the branch-name choice buttons may give way.
    static let conflictDiffWidth: CGFloat = 560
    static let expandedWidth = repositoryWidth + separatorWidth + diffWidth
    static let conflictExpandedWidth =
        repositoryWidth + separatorWidth + conflictDiffWidth

    static func metrics(
        totalWidth: CGFloat,
        preferredFraction: Double,
        minimumDetailWidth: CGFloat = minimumPaneWidth
    ) -> RepositorySplitMetrics {
        let availablePaneWidth = max(0, totalWidth - separatorWidth)
        let effectiveRepositoryMinimum = min(
            minimumPaneWidth,
            availablePaneWidth / 2
        )
        let effectiveDetailMinimum = min(
            minimumDetailWidth,
            availablePaneWidth - effectiveRepositoryMinimum
        )
        let allowedRepositoryWidths: ClosedRange<CGFloat> =
            effectiveRepositoryMinimum...(availablePaneWidth - effectiveDetailMinimum)
        let fraction = preferredFraction.isFinite
            ? min(max(CGFloat(preferredFraction), 0), 1)
            : CGFloat(defaultFraction)
        let repositoryWidth = min(
            max(availablePaneWidth * fraction, allowedRepositoryWidths.lowerBound),
            allowedRepositoryWidths.upperBound
        )

        return RepositorySplitMetrics(
            repositoryWidth: repositoryWidth,
            detailWidth: max(0, availablePaneWidth - repositoryWidth),
            availablePaneWidth: availablePaneWidth,
            allowedRepositoryWidths: allowedRepositoryWidths
        )
    }
}

struct RepositorySplitMetrics {
    let repositoryWidth: CGFloat
    let detailWidth: CGFloat
    let availablePaneWidth: CGFloat
    let allowedRepositoryWidths: ClosedRange<CGFloat>
}

private struct RepositorySplitResizeHandle: View {
    @Binding var fraction: Double
    @Binding var widthAtDragStart: CGFloat?
    let currentRepositoryWidth: CGFloat
    let availablePaneWidth: CGFloat
    let allowedRepositoryWidths: ClosedRange<CGFloat>
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: RepositorySplitLayout.resizeHandleWidth)
            .overlay {
                Rectangle()
                    .fill(
                        isHovered || widthAtDragStart != nil
                            ? AppTheme.actionBlue
                            : AppTheme.edge
                    )
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovered {
                    NSCursor.pop()
                    isHovered = false
                }
                widthAtDragStart = nil
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if widthAtDragStart == nil {
                            widthAtDragStart = currentRepositoryWidth
                        }
                        guard let widthAtDragStart else { return }
                        setRepositoryWidth(
                            widthAtDragStart + value.translation.width
                        )
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                    }
            )
            .onTapGesture(count: 2) {
                setRepositoryWidth(
                    availablePaneWidth * CGFloat(RepositorySplitLayout.defaultFraction)
                )
            }
            .accessibilityLabel("Resize repository and side panels")
            .accessibilityValue(
                "\(Int((currentRepositoryWidth / max(1, availablePaneWidth) * 100).rounded()))% repository"
            )
            .help("Drag to resize repository and side panels. Double-click to reset.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    setRepositoryWidth(currentRepositoryWidth + 24)
                case .decrement:
                    setRepositoryWidth(currentRepositoryWidth - 24)
                @unknown default:
                    break
                }
            }
    }

    private func setRepositoryWidth(_ proposedWidth: CGFloat) {
        guard availablePaneWidth > 0 else {
            fraction = RepositorySplitLayout.defaultFraction
            return
        }
        let resolvedWidth = min(
            max(proposedWidth, allowedRepositoryWidths.lowerBound),
            allowedRepositoryWidths.upperBound
        )
        fraction = Double(resolvedWidth / availablePaneWidth)
    }
}

private struct DiffPanelWindowExpansion: NSViewRepresentable {
    let isExpanded: Bool
    let minimumExpandedWidth: CGFloat?
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
            context.coordinator.update(
                isExpanded: isExpanded,
                minimumExpandedWidth: minimumExpandedWidth,
                reduceMotion: reduceMotion
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
            context.coordinator.update(
                isExpanded: isExpanded,
                minimumExpandedWidth: minimumExpandedWidth,
                reduceMotion: reduceMotion
            )
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var collapsedContentWidth: CGFloat?
        private var lastExpandedState: Bool?
        private var lastMinimumExpandedWidth: CGFloat?
        private var automaticExpandedContentWidth: CGFloat?
        private let sizing = RepositoryViewerSizing()

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            self.window = window
            collapsedContentWidth = nil
            lastExpandedState = nil
            lastMinimumExpandedWidth = nil
            automaticExpandedContentWidth = nil
        }

        func update(
            isExpanded: Bool,
            minimumExpandedWidth: CGFloat?,
            reduceMotion: Bool
        ) {
            guard let window else { return }

            // The conflict resolver asks for a wider panel and can appear
            // after the panel is already open (its session loads
            // asynchronously), so a raised width request must also widen an
            // expanded window. Growth only: a lowered request never shrinks
            // the window mid-session, and manual resizes are respected.
            let stateChanged = lastExpandedState != isExpanded
            let widthRequestGrew = isExpanded && !stateChanged
                && (minimumExpandedWidth ?? 0)
                    > (lastMinimumExpandedWidth ?? 0)
            lastMinimumExpandedWidth = minimumExpandedWidth
            guard stateChanged || widthRequestGrew else { return }

            if lastExpandedState == nil, !isExpanded {
                lastExpandedState = false
                return
            }

            let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
            let currentContentWidth = window.contentLayoutRect.width
            let targetContentWidth: CGFloat

            if isExpanded {
                if stateChanged {
                    collapsedContentWidth = currentContentWidth
                } else {
                    persistManualResize(currentContentWidth)
                }
                targetContentWidth = min(visibleFrame.width, sizing.targetContentWidth(
                    currentContentWidth: currentContentWidth,
                    defaultExpandedContentWidth: RepositorySplitLayout.expandedWidth,
                    minimumExpandedContentWidth: minimumExpandedWidth
                ))
                automaticExpandedContentWidth = targetContentWidth
            } else {
                if lastExpandedState == true {
                    persistManualResize(currentContentWidth)
                }
                targetContentWidth = collapsedContentWidth
                    ?? currentContentWidth
                collapsedContentWidth = nil
                automaticExpandedContentWidth = nil
            }
            lastExpandedState = isExpanded

            guard abs(targetContentWidth - currentContentWidth) > 0.5 else {
                return
            }

            let oldFrame = window.frame
            var targetFrame = window.frameRect(
                forContentRect: NSRect(
                    origin: .zero,
                    size: NSSize(
                        width: targetContentWidth,
                        height: window.contentLayoutRect.height
                    )
                )
            )
            // This transition is horizontal only. contentLayoutRect excludes
            // title-bar space, so converting its height back to a window frame
            // would otherwise make the window shorter on every open/close cycle.
            targetFrame.size.height = oldFrame.height
            // Keep the window centered as the detail panel appears or closes so
            // the added width is shared evenly between the leading and trailing
            // edges. Screen-edge clamping below still keeps the window visible.
            targetFrame.origin.x = oldFrame.midX - (targetFrame.width / 2)
            targetFrame.origin.y = oldFrame.minY

            if targetFrame.maxX > visibleFrame.maxX {
                targetFrame.origin.x -= targetFrame.maxX - visibleFrame.maxX
            }
            targetFrame.origin.x = max(targetFrame.minX, visibleFrame.minX)
            targetFrame.origin.y = min(
                max(targetFrame.minY, visibleFrame.minY),
                visibleFrame.maxY - targetFrame.height
            )

            // Let AppKit retain the existing backing surface while resizing,
            // then refresh SwiftUI once the short frame animation completes.
            window.setFrame(targetFrame, display: true, animate: !reduceMotion)
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (reduceMotion ? 0 : 0.3)
            ) { [weak window] in
                window?.contentView?.needsLayout = true
                window?.contentView?.needsDisplay = true
                window?.contentView?.layoutSubtreeIfNeeded()
                window?.contentView?.displayIfNeeded()
            }
        }

        private func persistManualResize(_ currentContentWidth: CGFloat) {
            guard let resizedWidth = RepositoryViewerSizing.manuallyResizedWidth(
                currentContentWidth: currentContentWidth,
                automaticContentWidth: automaticExpandedContentWidth
            ) else {
                return
            }
            sizing.saveExpandedContentWidth(resizedWidth)
            automaticExpandedContentWidth = resizedWidth
        }
    }
}

private struct RepositoryEditorPanel: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: editorSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(editorSymbolColor)

                Text(model.detailTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if model.conflictResolution == nil,
                   model.gitFilePreview?.isAvailable == true {
                    Picker("File detail", selection: gitFileDetailModeBinding) {
                        ForEach(GitFileDetailMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 116)
                    .accessibilityLabel("File Detail")
                }

                if model.currentDiffFilePath != nil {
                    Button {
                        model.viewCurrentDiffInFiles()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondary)
                    .disabled(!model.canViewCurrentDiffInFiles)
                    .accessibilityLabel("View File in Files")
                    .help("View File in Files at First Change")
                }

                if model.workspaceMode == .fileEditor,
                   model.selectedRepositoryFilePath != nil {
                    Button {
                        model.showChangesForCurrentFile()
                    } label: {
                        BranchGlyph(size: 12, color: AppTheme.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondary)
                    .disabled(!model.canShowChangesForCurrentFile)
                    .accessibilityLabel("Show Changes for This File")
                    .help("Show Changes for This File in Git")
                }

                if model.detailKind == .source {
                    if model.isRepositoryFileDirty {
                        Circle()
                            .fill(AppTheme.primary)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("Unsaved changes")
                    }

                    Button {
                        Task { await model.saveRepositoryFile() }
                    } label: {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondary)
                    .disabled(!model.canSaveRepositoryFile)
                    .accessibilityLabel("Save File")
                    .help("Save File (⌘S)")
                }

                Button {
                    closeEditorOrReturnToSearch()
                } label: {
                    Image(
                        systemName: model.isFileSearchPresented
                            ? "chevron.backward"
                            : "xmark"
                    )
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondary)
                .disabled(model.isSavingRepositoryFile)
                .accessibilityLabel(editorCloseLabel)
                .help("\(editorCloseLabel) (⎋)")
            }
            .padding(.leading, 10)
            .frame(height: 36)
            .background(AppTheme.raisedFill)

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            if model.detailKind == .source {
                if let conflictDocument = openFileConflictDocument {
                    conflictEditorNotice(for: conflictDocument)

                    Rectangle()
                        .fill(AppTheme.edge)
                        .frame(height: 1)
                }

                SourceDocument(
                    text: Binding(
                        get: { model.repositoryFileText },
                        set: { model.updateRepositoryFileTextFromEditor($0) }
                    ),
                    scrollRequest: model.repositoryFileScrollRequest,
                    isEditable: !model.isBusy && !model.isSavingRepositoryFile
                        && !model.isDetailLoading
                ) {
                    Task { await model.saveRepositoryFile() }
                } onExit: {
                    closeEditorOrReturnToSearch()
                }
                .overlay {
                    if model.isDetailLoading {
                        HStack(spacing: 9) {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.detailText)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.diffCanvas)
                    }
                }
            } else if model.detailKind == .largeSource {
                LargeSourceDocument(
                    text: model.repositoryFileText,
                    scrollRequest: model.repositoryFileScrollRequest
                )
                .equatable()
            } else if model.isDetailLoading {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.detailText)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.diffCanvas)
            } else if let conflictResolution = model.conflictResolution {
                ConflictResolverView(session: conflictResolution)
            } else if model.detailKind == .diff,
                      model.gitFileDetailMode == .preview,
                      let preview = model.gitFilePreview {
                GitFileComparisonPreview(preview: preview)
            } else if model.detailKind == .diff {
                DiffDocument(text: model.detailText)
                    .equatable()
            } else if model.detailKind == .preview,
                      let url = model.selectedRepositoryFileURL {
                RepositoryQuickLookPreview(url: url)
                    .padding(RepositoryFileLoader.isImage(at: url) ? 20 : 0)
                    .background(AppTheme.diffCanvas)
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(AppTheme.muted)

                    Text(model.detailText)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.diffCanvas)
            }
        }
        .background(AppTheme.diffCanvas)
    }

    private func closeEditorOrReturnToSearch() {
        if model.isFileSearchPresented {
            model.showRepositorySearchResults()
        } else {
            model.closeEditorPanel()
        }
    }

    private var editorCloseLabel: String {
        model.isFileSearchPresented
            ? "Return to Search Results"
            : "Close \(editorName)"
    }

    private var openFileConflictDocument: ConflictDocument? {
        guard model.detailKind == .source,
              let path = model.selectedRepositoryFilePath else { return nil }
        return ConflictDocument.parse(path: path, text: model.repositoryFileText)
    }

    private func conflictEditorNotice(for document: ConflictDocument) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.conflict)

            Text("\(document.hunks.count) unresolved \(document.hunks.count == 1 ? "conflict" : "conflicts")")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.primary)

            // Swatches instead of color names: imported themes repaint the
            // side hues, so naming them here could lie.
            conflictLegendItem(color: AppTheme.graphBlue, label: "Current")
            conflictLegendItem(color: AppTheme.added, label: "Incoming")

            Spacer(minLength: 8)

            if model.canShowChangesForCurrentFile {
                Button("Open Resolver") {
                    model.showChangesForCurrentFile()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppTheme.graphBlue)
                .accessibilityHint("Opens the hunk-by-hunk conflict resolver")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(AppTheme.conflict.opacity(0.07))
    }

    private func conflictLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.muted)
        }
        .lineLimit(1)
    }

    private var editorSymbol: String {
        if model.conflictResolution != nil { return "arrow.triangle.branch" }
        guard model.detailKind != .diff || model.gitFileDetailMode == .preview else {
            return "doc.text"
        }
        return FileGlyph.symbol(forPath: model.detailTitle)
    }

    private var editorSymbolColor: Color {
        FileGlyph.color(forSymbol: editorSymbol)
    }

    private var editorName: String {
        if model.conflictResolution != nil { return "Conflict Resolver" }
        if model.detailKind == .diff {
            return model.gitFileDetailMode == .preview ? "Preview" : "Diff"
        }
        return "File"
    }

    private var gitFileDetailModeBinding: Binding<GitFileDetailMode> {
        Binding(
            get: { model.gitFileDetailMode },
            set: { model.setGitFileDetailMode($0) }
        )
    }
}

private struct ConflictResolverView: View {
    @EnvironmentObject private var model: RepositoryModel
    let session: ConflictResolutionSession
    @State private var navigationCursor: Int?

    var body: some View {
        if let document = session.document {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    resolverToolbar(document: document, proxy: proxy)

                    Rectangle()
                        .fill(AppTheme.edge)
                        .frame(height: 1)

                    ScrollView {
                        // A plain VStack keeps every hunk view alive so an
                        // in-progress custom edit survives scrolling away.
                        VStack(spacing: 0) {
                            ForEach(Array(document.hunks.enumerated()), id: \.element.id) { index, hunk in
                                ConflictHunkView(
                                    number: index + 1,
                                    hunk: hunk,
                                    contextBefore: document.contextBefore(hunkID: hunk.id),
                                    contextAfter: document.contextAfter(hunkID: hunk.id),
                                    currentTitle: session.currentTitle,
                                    incomingTitle: session.incomingTitle,
                                    choice: session.choices[hunk.id],
                                    choose: { choice in
                                        model.chooseConflictHunk(hunk.id, choice: choice)
                                    }
                                )
                                .id(hunk.id)
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                }
                .background(AppTheme.diffCanvas)
                // Reset scroll position, navigation cursor, and editor drafts
                // when the resolver moves to a different conflicted file.
                .id(session.path)
            }
        } else {
            wholeFileResolver
        }
    }

    private func resolverToolbar(
        document: ConflictDocument,
        proxy: ScrollViewProxy
    ) -> some View {
        HStack(spacing: 10) {
            Text("\(session.resolvedCount) of \(document.hunks.count) resolved")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    session.resolvedCount == document.hunks.count
                        ? AppTheme.added
                        : AppTheme.secondary
                )
                .monospacedDigit()

            if document.hunks.count > 1 {
                HStack(spacing: 2) {
                    conflictStepButton(
                        symbol: "chevron.up",
                        help: "Previous unresolved conflict",
                        document: document,
                        proxy: proxy,
                        forward: false
                    )

                    conflictStepButton(
                        symbol: "chevron.down",
                        help: "Next unresolved conflict",
                        document: document,
                        proxy: proxy,
                        forward: true
                    )
                }
            }

            Spacer(minLength: 8)

            Button("Edit File Manually") {
                model.viewCurrentDiffInFiles()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                model.canViewCurrentDiffInFiles ? AppTheme.graphBlue : AppTheme.muted
            )
            .disabled(!model.canViewCurrentDiffInFiles)
            .help("Open the conflicted file in Files, with markers, to resolve it by hand")

            Menu("Resolve All") {
                Button("Use \(session.currentTitle)") {
                    model.chooseAllConflictHunks(.current)
                }

                Button("Use \(session.incomingTitle)") {
                    model.chooseAllConflictHunks(.incoming)
                }

                Button("Use Both") {
                    model.chooseAllConflictHunks(.both)
                }

                Divider()

                Button("Clear All Choices") {
                    model.clearConflictChoices()
                }
                .disabled(session.choices.isEmpty)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isBusy || model.hasPendingChangeOperations)

            Button("Mark Resolved") {
                Task { await model.applyConflictResolution() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(session.resolvedText == nil ? AppTheme.muted : AppTheme.onAccent)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                session.resolvedText == nil ? AppTheme.disabledFill : AppTheme.actionBlue,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .disabled(
                session.resolvedText == nil
                    || model.isBusy
                    || model.hasPendingChangeOperations
            )
            .help("Write the selected results and stage this file")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(AppTheme.raisedFill)
    }

    private func conflictStepButton(
        symbol: String,
        help: String,
        document: ConflictDocument,
        proxy: ScrollViewProxy,
        forward: Bool
    ) -> some View {
        let unresolved = document.hunks.map(\.id).filter { session.choices[$0] == nil }
        return Button {
            jumpToUnresolved(unresolved, proxy: proxy, forward: forward)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(unresolved.isEmpty ? AppTheme.muted : AppTheme.secondary)
                .frame(width: 22, height: 22)
                .background(AppTheme.hover, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(unresolved.isEmpty)
        .help(help)
        .accessibilityLabel(help)
    }

    private func jumpToUnresolved(
        _ unresolved: [Int],
        proxy: ScrollViewProxy,
        forward: Bool
    ) {
        guard !unresolved.isEmpty else { return }
        let target: Int
        if forward {
            target = unresolved.first { $0 > (navigationCursor ?? -1) } ?? unresolved[0]
        } else {
            target = unresolved.last { $0 < (navigationCursor ?? .max) }
                ?? unresolved[unresolved.count - 1]
        }
        navigationCursor = target
        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private var wholeFileResolver: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.conflict)

                Text("Choose a complete version")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                Text("Compare both files, then keep one side.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.muted)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(AppTheme.raisedFill)

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            HStack(spacing: 0) {
                ConflictWholeFilePane(
                    title: session.currentTitle,
                    role: "Current side",
                    side: wholeFileSide(model.gitFilePreview?.old),
                    choose: { keepWholeFile(.current) }
                )

                Rectangle()
                    .fill(AppTheme.edge)
                    .frame(width: 1)

                ConflictWholeFilePane(
                    title: session.incomingTitle,
                    role: "Incoming side",
                    side: wholeFileSide(model.gitFilePreview?.new),
                    choose: { keepWholeFile(.incoming) }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            HStack(spacing: 14) {
                Button("Edit File Manually") {
                    model.viewCurrentDiffInFiles()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.graphBlue)
                .disabled(!model.canViewCurrentDiffInFiles)

                Spacer(minLength: 8)

                Button("Use Edited File") {
                    guard let change = model.selectedChange else { return }
                    Task { await model.stage(change) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.secondary)
                .disabled(
                    model.selectedChange == nil
                        || model.isBusy
                        || model.hasPendingChangeOperations
                )
                .help("Stage the current working-tree file as the resolved result")
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(AppTheme.raisedFill)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.diffCanvas)
    }

    private func wholeFileSide(
        _ version: GitFilePreviewVersion?
    ) -> ConflictWholeFileSide {
        guard model.gitFilePreview != nil else { return .unavailable }
        guard let version else { return .deleted }
        return .file(version)
    }

    private func keepWholeFile(_ version: ConflictVersion) {
        guard let change = model.selectedChange else { return }
        Task { await model.resolveConflict(change, keeping: version) }
    }
}

private enum ConflictWholeFileSide: Equatable {
    case file(GitFilePreviewVersion)
    case deleted
    case unavailable

    var id: String {
        switch self {
        case .file(let version): return version.url.path
        case .deleted: return "deleted"
        case .unavailable: return "unavailable"
        }
    }
}

private enum ConflictWholeFileContent: Sendable {
    case text(String)
    case quickLook
    case message(String)
}

private struct ConflictWholeFilePane: View {
    let title: String
    let role: String
    let side: ConflictWholeFileSide
    let choose: () -> Void
    @State private var content: ConflictWholeFileContent?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(role)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer(minLength: 6)

                Button("Use \(title)", action: choose)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.graphBlue)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(AppTheme.hover, in: RoundedRectangle(cornerRadius: 4))
                    .disabled(isLoading || side == .unavailable)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(AppTheme.inputFill)

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: side.id) {
            await loadContent()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch side {
        case .deleted:
            wholeFileMessage(
                symbol: "trash",
                title: "File deleted",
                detail: "This file does not exist on \(title)."
            )
        case .unavailable:
            wholeFileMessage(
                symbol: "doc.questionmark",
                title: "Preview unavailable",
                detail: "Open the file manually to inspect this side."
            )
        case .file(let version):
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch content {
                case .text(let text):
                    LargeSourceDocument(text: text, scrollRequest: nil)
                        .equatable()
                case .quickLook:
                    RepositoryQuickLookPreview(url: version.url)
                        .padding(RepositoryFileLoader.isImage(at: version.url) ? 16 : 0)
                case .message(let message):
                    wholeFileMessage(
                        symbol: "doc.questionmark",
                        title: "Preview unavailable",
                        detail: message
                    )
                case nil:
                    EmptyView()
                }
            }
        }
    }

    private func wholeFileMessage(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.muted)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondary)

            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.diffCanvas)
    }

    private func loadContent() async {
        guard case .file(let version) = side else {
            content = nil
            isLoading = false
            return
        }
        content = nil
        isLoading = true
        let loaded = await Task.detached(priority: .userInitiated) {
            do {
                switch try RepositoryFileLoader.document(at: version.url) {
                case .source(let text), .largeSource(let text):
                    return ConflictWholeFileContent.text(text)
                case .preview:
                    return ConflictWholeFileContent.quickLook
                case .message(let message):
                    return ConflictWholeFileContent.message(message)
                }
            } catch {
                return ConflictWholeFileContent.message(error.localizedDescription)
            }
        }.value
        guard !Task.isCancelled else { return }
        content = loaded
        isLoading = false
    }
}

private struct ConflictHunkView: View {
    let number: Int
    let hunk: ConflictHunk
    let contextBefore: ConflictContext?
    let contextAfter: ConflictContext?
    let currentTitle: String
    let incomingTitle: String
    let choice: ConflictChoice?
    let choose: (ConflictChoice?) -> Void
    @State private var isEditingCustom = false
    @State private var customDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Conflict \(number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                Text("Lines \(hunk.markerLine)–\(hunk.endLine)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
                    .monospacedDigit()

                Spacer(minLength: 8)

                ConflictChoiceButton(
                    title: currentTitle,
                    selected: choice == .current,
                    action: { select(choice == .current ? nil : .current) }
                )

                ConflictChoiceButton(
                    title: incomingTitle,
                    selected: choice == .incoming,
                    action: { select(choice == .incoming ? nil : .incoming) }
                )

                ConflictChoiceButton(
                    title: "Both",
                    selected: choice == .both,
                    action: { select(choice == .both ? nil : .both) }
                )

                ConflictChoiceButton(
                    title: "Custom",
                    icon: "pencil",
                    selected: choice?.isCustom == true || isEditingCustom,
                    action: {
                        if isEditingCustom {
                            isEditingCustom = false
                        } else {
                            beginCustomEditing()
                        }
                    }
                )
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(AppTheme.raisedFill)

            if let contextBefore {
                ConflictContextCode(context: contextBefore)
            }

            HStack(spacing: 0) {
                ConflictVersionPane(
                    title: currentTitle,
                    gitLabel: hunk.currentLabel,
                    text: hunk.currentText,
                    startLine: hunk.currentStartLine,
                    accent: AppTheme.graphBlue,
                    selected: choice == .current || choice == .both
                )

                Rectangle()
                    .fill(AppTheme.edge)
                    .frame(width: 1)

                ConflictVersionPane(
                    title: incomingTitle,
                    gitLabel: hunk.incomingLabel,
                    text: hunk.incomingText,
                    startLine: hunk.incomingStartLine,
                    accent: AppTheme.added,
                    selected: choice == .incoming || choice == .both
                )
            }

            if isEditingCustom {
                customEditor
            } else if case .custom(let text) = choice {
                customPreview(text)
            }

            if let contextAfter {
                ConflictContextCode(context: contextAfter)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    /// Every explicit pick closes the inline editor so a stale draft never
    /// lingers under a different selection.
    private func select(_ newChoice: ConflictChoice?) {
        isEditingCustom = false
        choose(newChoice)
    }

    private func beginCustomEditing() {
        switch choice {
        case .custom(let text):
            customDraft = text
        case .current:
            customDraft = hunk.currentText
        case .incoming:
            customDraft = hunk.incomingText
        case .both, nil:
            customDraft = hunk.currentText + hunk.incomingText
        }
        isEditingCustom = true
    }

    private var customEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Custom Resolution")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                Text("Replaces the conflicted block with this text")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button("Cancel") {
                    isEditingCustom = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)

                Button("Use This Text") {
                    select(.custom(customDraft))
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(AppTheme.actionBlue, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(AppTheme.selection)

            TextEditor(text: $customDraft)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppTheme.primary)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .frame(height: customEditorHeight)
                .background(AppTheme.diffCanvas)
                .accessibilityLabel("Custom resolution text")
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)
        }
    }

    private var customEditorHeight: CGFloat {
        let lines = customDraft.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        return min(max(CGFloat(lines) * 16 + 22, 96), 240)
    }

    private func customPreview(_ text: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Custom Resolution")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                Spacer(minLength: 0)

                Button("Edit…") {
                    beginCustomEditing()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.graphBlue)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(AppTheme.selection)

            if text.isEmpty {
                Text("No content — the conflicted block will be removed")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.selection.opacity(0.35))
            } else {
                ScrollView(.horizontal) {
                    ConflictCodeText(text: text, startLine: nil)
                        .padding(9)
                }
                .frame(maxHeight: 180)
                .background(AppTheme.selection.opacity(0.35))
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)
        }
    }
}

private struct ConflictChoiceButton: View {
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                }

                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(selected ? AppTheme.onAccent : AppTheme.secondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                selected ? AppTheme.actionBlue : AppTheme.hover,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(title)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

private struct ConflictVersionPane: View {
    let title: String
    let gitLabel: String
    let text: String
    let startLine: Int
    /// Side hue shared with the file editor's conflict regions: blue for the
    /// current side, green for the incoming side.
    let accent: Color
    let selected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? AppTheme.primary : AppTheme.secondary)

                if !gitLabel.isEmpty {
                    Text(gitLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(selected ? accent.opacity(0.26) : AppTheme.inputFill)

            ScrollView([.horizontal, .vertical]) {
                Group {
                    if text.isEmpty {
                        Text("No content — this side deletes these lines")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(AppTheme.muted)
                    } else {
                        ConflictCodeText(text: text, startLine: startLine)
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 72, idealHeight: 110, maxHeight: 180)
            .background(selected ? accent.opacity(0.12) : AppTheme.diffCanvas)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ConflictContextCode: View {
    let context: ConflictContext

    var body: some View {
        ScrollView(.horizontal) {
            ConflictCodeText(
                text: context.text,
                startLine: context.startLine,
                codeColor: AppTheme.muted
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.inputFill.opacity(0.72))
    }
}

/// Monospaced code with an optional right-aligned line-number gutter. The
/// gutter mirrors the working-tree file's numbering so the resolver matches
/// what an editor would show, and it stays outside text selection so copying
/// code never captures the numbers.
private struct ConflictCodeText: View {
    let text: String
    let startLine: Int?
    var codeColor: Color = AppTheme.primary

    private var lineCount: Int {
        guard !text.isEmpty else { return 0 }
        let newlines = text.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        return newlines + (text.hasSuffix("\n") ? 0 : 1)
    }

    private var displayText: String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let startLine, lineCount > 0 {
                Text(
                    (startLine..<startLine + lineCount)
                        .map(String.init)
                        .joined(separator: "\n")
                )
                .foregroundStyle(AppTheme.muted.opacity(0.75))
                .multilineTextAlignment(.trailing)
            }

            Text(displayText)
                .foregroundStyle(codeColor)
                .textSelection(.enabled)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct GitFileComparisonPreview: View {
    let preview: GitFilePreview
    @State private var scrollSynchronizer = QuickLookPreviewScrollSynchronizer()

    var body: some View {
        HStack(spacing: 0) {
            if let old = preview.old {
                versionPane(old)
            }

            if preview.old != nil, preview.new != nil {
                Rectangle()
                    .fill(AppTheme.edge)
                    .frame(width: 1)
            }

            if let new = preview.new {
                versionPane(new)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.diffCanvas)
    }

    private func versionPane(_ version: GitFilePreviewVersion) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(version.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                Text(version.context)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(AppTheme.raisedFill)

            Rectangle()
                .fill(AppTheme.edge)
                .frame(height: 1)

            RepositoryQuickLookPreview(
                url: version.url,
                scrollSynchronizer: scrollSynchronizer
            )
                .padding(RepositoryFileLoader.isImage(at: version.url) ? 20 : 0)
                .background(AppTheme.diffCanvas)
                .accessibilityLabel("\(version.title) file preview, \(version.context)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RepositoryModePicker: View {
    @EnvironmentObject private var model: RepositoryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RepositoryWorkspaceMode.allCases) { mode in
                RepositoryModeSegment(
                    mode: mode,
                    isSelected: mode == model.workspaceMode,
                    selectionNamespace: selectionNamespace
                ) {
                    guard mode != model.workspaceMode else { return }
                    if reduceMotion {
                        model.setWorkspaceMode(mode)
                    } else {
                        withAnimation(.easeOut(duration: 0.14)) {
                            model.setWorkspaceMode(mode)
                        }
                    }
                }
            }
        }
        // 2pt inset keeps the selection pill nearly flush with the capsule,
        // matching the proportions of Xcode's navigator switcher.
        .padding(2)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace Mode")
        .accessibilityValue(model.workspaceMode.title)
    }
}

struct RepositoryTerminalButton: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        Button {
            openRepositoryInTerminal()
        } label: {
            Image(systemName: "apple.terminal")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.secondary)
        .disabled(model.repositoryURL == nil)
        .accessibilityLabel("Open Repository in Terminal")
        .help("Open Repository in Terminal")
    }

    private func openRepositoryInTerminal() {
        guard let repositoryURL = model.repositoryURL else { return }
        do {
            try RepositoryTerminalLauncher.open(
                repositoryURL: repositoryURL,
                sshRepository: model.sshRepository
            ) { error in
                Task { @MainActor in
                    model.errorMessage = error.localizedDescription
                }
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
enum RepositoryLocationSymbol {
    static let image: NSImage? = {
        let image = NSImage(
            systemSymbolName: "folder.badge.gearshape",
            accessibilityDescription: nil
        ) ?? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        guard let image else { return nil }
        image.isTemplate = true
        return image
    }()
}

@MainActor
enum RepositoryLocationActions {
    static func copyDirectoryPath(
        _ repositoryURL: URL,
        to pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()
        pasteboard.setString(
            repositoryURL.standardizedFileURL.path,
            forType: .string
        )
    }

    static func revealInFinder(_ repositoryURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([
            repositoryURL.standardizedFileURL
        ])
    }
}

private struct RepositoryLocationMenu: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        Menu {
            Button("Copy Directory as Path") {
                guard let repositoryURL = model.repositoryURL else { return }
                RepositoryLocationActions.copyDirectoryPath(repositoryURL)
            }

            Button("Reveal in Finder") {
                guard let repositoryURL = model.repositoryURL else { return }
                RepositoryLocationActions.revealInFinder(repositoryURL)
            }
        } label: {
            if let image = RepositoryLocationSymbol.image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 16)
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: 26)
        .foregroundStyle(AppTheme.secondary)
        .tint(AppTheme.secondary)
        .disabled(model.repositoryURL == nil)
        .accessibilityLabel("Repository Location")
        .help("Repository Location")
    }
}

private struct RepositoryModeSegment: View {
    let mode: RepositoryWorkspaceMode
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if mode == .sourceControl {
                    BranchGlyph(size: 14, color: iconColor)
                } else {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: 36, height: 26)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(AppTheme.raisedFill)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                    } else if hovering {
                        Capsule()
                            .fill(AppTheme.hover.opacity(0.6))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(mode.title) (\(mode.shortcutHint))")
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var iconColor: Color {
        if isSelected { return AppTheme.primary }
        return hovering ? AppTheme.secondary : AppTheme.muted
    }
}

private struct RepositoryContentView: View {
    @EnvironmentObject private var model: RepositoryModel
    let isRepositoryLoadPending: Bool
    let pendingRepositoryName: String

    var body: some View {
        Group {
            if let url = model.repositoryInitializationURL {
                InitializeRepositoryView(folderURL: url)
            } else if model.repositoryURL == nil {
                if model.isBusy || isRepositoryLoadPending {
                    RepositoryLoadingView(repositoryName: pendingRepositoryName)
                } else {
                    WelcomeView()
                }
            } else {
                switch model.workspaceMode {
                case .sourceControl:
                    WorkspaceView()
                case .fileEditor:
                    RepositoryFileBrowser()
                }
            }
        }
        .onChange(of: model.errorPresentation) { _, presentation in
            guard let presentation else { return }
            DispatchQueue.main.async {
                AppDialog.message(
                    title: presentation.title,
                    message: presentation.message,
                    details: presentation.details
                )
                if model.errorPresentation == presentation {
                    model.errorPresentation = nil
                }
            }
        }
    }
}

private struct RepositoryLoadingView: View {
    let repositoryName: String

    var body: some View {
        WorkspaceView(isOpeningRepository: true)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Opening \(repositoryName)")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct InitializeRepositoryView: View {
    @EnvironmentObject private var model: RepositoryModel
    let folderURL: URL

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(AppTheme.graphBlue)

                VStack(spacing: 5) {
                    Text("Initialize Git Repository")
                        .font(.system(size: 16, weight: .semibold))

                    Text(folderURL.lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("This folder is not currently tracked by Git.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.muted)
                }

                Button("Initialize with .gitignore") {
                    Task { await model.initializeRepository(createGitIgnore: true) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 210, height: 36)
                .disabled(model.isBusy)

                HStack(spacing: 16) {
                    Button("Initialize without .gitignore") {
                        Task { await model.initializeRepository(createGitIgnore: false) }
                    }
                    .buttonStyle(.plain)

                    Button("Choose Another Folder…") {
                        model.chooseRepository()
                    }
                    .buttonStyle(.plain)

                    Button("Back") {
                        model.cancelRepositoryInitialization()
                    }
                    .buttonStyle(.plain)

                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondary)
                .disabled(model.isBusy)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SSHBrowserSession: Identifiable {
    let id = UUID()
    let host: String
}

private struct WelcomeView: View {
    @EnvironmentObject private var model: RepositoryModel
    @EnvironmentObject private var tabsModel: WorkspaceTabsModel
    @State private var isDropTargeted = false
    @State private var sshBrowserSession: SSHBrowserSession?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 16) {
                BranchGlyph(size: 38, color: AppTheme.graphBlue)

                VStack(spacing: 6) {
                    Text("Open a Git repository")
                        .font(.system(size: 16, weight: .semibold))

                    Text("Drop a folder here, or press ⌘O to browse.")
                        .font(AppType.rowDetail)
                        .foregroundStyle(AppTheme.muted)
                }

                Button("Open Repository…") {
                    model.chooseRepository()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 210, height: 34)
                .disabled(
                    model.isBusy
                        || model.isGeneratingCommitMessage
                        || model.hasPendingChangeOperations
                )

                Button("Clone Repository…") {
                    cloneRepository()
                }
                .buttonStyle(.plain)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.secondary)
                .disabled(
                    model.isBusy
                        || model.isGeneratingCommitMessage
                        || model.hasPendingChangeOperations
                )
                .help("Clone a remote repository into a local folder")

                Button("Open Repository over SSH…") {
                    openSSHRepository()
                }
                .buttonStyle(.plain)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.secondary)
                .disabled(
                    model.isBusy
                        || model.isGeneratingCommitMessage
                        || model.hasPendingChangeOperations
                )
                .help("Run Git directly in a repository on a remote machine")
            }

            if !recentRepositories.isEmpty {
                RecentRepositoriesList(repositories: recentRepositories)
                    .padding(.top, 34)
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        AppTheme.graphBlue,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(
                        AppTheme.graphBlue.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await model.openRepository(directoryURL(for: url))
                }
            }
            return true
        }
        .sheet(item: $sshBrowserSession) { session in
            SSHRepositoryBrowserView(host: session.host) { path in
                Task {
                    await model.openSSHRepository(host: session.host, path: path)
                }
            }
        }
    }

    private func openSSHRepository() {
        guard let location = GitPrompt.sshRepository() else { return }
        if location.path.isEmpty {
            sshBrowserSession = SSHBrowserSession(host: location.host)
            return
        }
        Task {
            await model.openSSHRepository(host: location.host, path: location.path)
        }
    }

    private var recentRepositories: [URL] {
        tabsModel.recentRepositoryURLs
    }

    private func cloneRepository() {
        guard let remoteURL = GitPrompt.cloneRemoteURL(),
              let destinationURL = GitPrompt.cloneDestinationFolder() else { return }
        Task {
            await model.cloneRepository(from: remoteURL, to: destinationURL)
        }
    }

    /// Dropping a file inside a repository should open its enclosing folder.
    private func directoryURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? url : url.deletingLastPathComponent()
    }
}

private struct RecentRepositoriesList: View {
    let repositories: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECENT")
                .font(AppType.panelTitle)
                .tracking(0.8)
                .foregroundStyle(AppTheme.muted)
                .padding(.leading, 9)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(repositories.prefix(5), id: \.path) { url in
                RecentRepositoryRow(url: url)
            }
        }
        .frame(width: 300)
    }
}

private struct RecentRepositoryRow: View {
    @EnvironmentObject private var model: RepositoryModel
    @EnvironmentObject private var tabsModel: WorkspaceTabsModel
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button {
            Task { await model.openRepository(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondary)
                    .frame(width: 16)

                Text(url.lastPathComponent)
                    .font(AppType.rowDetail)
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Text(abbreviatedParentPath)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(
                hovering ? AppTheme.hover : .clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
        .disabled(
            model.isBusy
                || model.isGeneratingCommitMessage
                || model.hasPendingChangeOperations
        )
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            Button("Remove from Recents") {
                tabsModel.removeRecentRepository(path: url.path)
            }
        }
    }

    private var abbreviatedParentPath: String {
        (url.deletingLastPathComponent().path as NSString)
            .abbreviatingWithTildeInPath
    }
}

private struct WorkspaceView: View {
    let isOpeningRepository: Bool

    init(isOpeningRepository: Bool = false) {
        self.isOpeningRepository = isOpeningRepository
    }

    @AppStorage("graphPanelHeight") private var graphPanelHeight = 260.0
    @State private var graphHeightAtDragStart: CGFloat?

    private let resizeHandleHeight: CGFloat = 5
    private let minimumChangesHeight: CGFloat = 175
    private let minimumGraphHeight: CGFloat = 98

    var body: some View {
        GeometryReader { geometry in
            let graphRange = minimumGraphHeight...maximumGraphHeight(
                availableHeight: geometry.size.height
            )
            let resolvedGraphHeight = min(
                max(CGFloat(graphPanelHeight), graphRange.lowerBound),
                graphRange.upperBound
            )

            VStack(spacing: 0) {
                ChangesPanel(isOpeningRepository: isOpeningRepository)
                    .frame(maxHeight: .infinity)

                GraphResizeHandle(
                    height: $graphPanelHeight,
                    heightAtDragStart: $graphHeightAtDragStart,
                    currentHeight: resolvedGraphHeight,
                    allowedRange: graphRange
                )

                GraphPanel(isOpeningRepository: isOpeningRepository)
                    .frame(height: resolvedGraphHeight)
            }
            .onChange(of: geometry.size.height) {
                graphPanelHeight = Double(resolvedGraphHeight)
            }
        }
        .clipped()
    }

    private func maximumGraphHeight(availableHeight: CGFloat) -> CGFloat {
        max(
            minimumGraphHeight,
            availableHeight
                - resizeHandleHeight
                - minimumChangesHeight
        )
    }
}

private struct RepositoryTopBar: View {
    @EnvironmentObject private var tabsModel: WorkspaceTabsModel
    @State private var pendingTabScroll: DispatchWorkItem?
    @StateObject private var dragState = TabDragState()

    /// Coordinate space of the whole bar; tab frames are reported in it so
    /// the AppKit drag area behind the bar can hit-test tabs for ⌘-drag.
    static let coordinateSpaceName = "repositoryTopBar"

    // Leading inset that clears the traffic lights now that the bar sits in
    // the titlebar region of the full-size-content window.
    private let trafficLightInset: CGFloat = 78

    var body: some View {
        HStack(spacing: 4) {
            // When the tabs fit, hug their content so the leftover width is
            // empty (and therefore draggable via WindowDragArea); fall back to
            // the scrolling strip only on overflow.
            if tabsModel.tabs.count <= 3 {
                HStack(spacing: 3) {
                    tabItems
                }
            } else {
                scrollingTabs
            }

            Button {
                tabsModel.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondary)
            .accessibilityLabel("New Repository Tab")
            .help("New Repository Tab (⌘T)")

            Spacer(minLength: 4)
        }
        .padding(.leading, trafficLightInset)
        .padding(.trailing, 4)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .coordinateSpace(name: Self.coordinateSpaceName)
        // No divider under the strip: a dark line there reads as the bar
        // casting shade on the content, which pushes the panel (and the tab
        // merged into it) visually behind the bar. The recessed strip color
        // alone defines the boundary, keeping tab + panel one front surface.
        .backgroundPreferenceValue(TabFramesPreferenceKey.self) { frames in
            WindowDragArea(
                orderedTabIDs: tabsModel.tabs.map(\.id),
                tabFrames: frames,
                dragState: dragState,
                selectTab: { tabsModel.select($0) },
                // The strip already renders drag-shifted positions, so the
                // committed order change must not animate: the reordered
                // layout lands exactly where the tabs are drawn.
                moveTab: { tabID, index in
                    tabsModel.moveTab(tabID, toIndex: index)
                }
            )
        }
        .background(AppTheme.tabStripFill)
        // Confine the active tab's shadow to the bar so it never smudges the
        // panel below the divider, where the tab merges with the content.
        .clipped()
    }

    private var tabItems: some View {
        ForEach(tabsModel.tabs) { tab in
            RepositoryTabItem(
                tab: tab,
                isActive: tab.id == tabsModel.activeTabID,
                dragState: dragState
            )
            .id(tab.id)
        }
    }

    private var scrollingTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 3) {
                    tabItems
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: tabsModel.activeTabID) {
                pendingTabScroll?.cancel()
                let tabID = tabsModel.activeTabID
                let workItem = DispatchWorkItem {
                    proxy.scrollTo(tabID, anchor: .center)
                    pendingTabScroll = nil
                }
                pendingTabScroll = workItem
                let delayMilliseconds = KvistPerformanceInstrumentation.configuration?.mode
                    == .tabs ? 2_000 : 100
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(delayMilliseconds),
                    execute: workItem
                )
            }
            .onDisappear { pendingTabScroll?.cancel() }
        }
    }
}

/// Live state of an in-progress tab drag. The event monitor in
/// `WindowDragArea` writes to it; the tab items read it to render the dragged
/// tab under the pointer and slide its neighbors aside. The model's order is
/// untouched until the drop, so the layout (and the tab frames captured at
/// drag start) stays stable for the whole gesture.
@MainActor
final class TabDragState: ObservableObject {
    @Published private(set) var draggedTabID: UUID?
    @Published private(set) var pointerX: CGFloat = 0
    private var grabOffsetX: CGFloat = 0
    private var frames: [UUID: CGRect] = [:]
    private var order: [UUID] = []

    /// Spacing of the tab strip's HStack; a neighbor making room for the
    /// dragged tab moves by the tab's width plus this.
    private let stripSpacing: CGFloat = 3

    var isDragging: Bool { draggedTabID != nil }

    func begin(
        tabID: UUID,
        pointerX: CGFloat,
        frames: [UUID: CGRect],
        order: [UUID]
    ) {
        guard let frame = frames[tabID] else { return }
        self.frames = frames
        self.order = order
        grabOffsetX = pointerX - frame.minX
        self.pointerX = pointerX
        draggedTabID = tabID
    }

    func update(pointerX: CGFloat) {
        guard isDragging else { return }
        self.pointerX = pointerX
    }

    func end() {
        draggedTabID = nil
        frames = [:]
        order = []
    }

    /// Index the dragged tab would land at if dropped now: the number of
    /// other tabs whose midpoint sits left of the dragged tab's visual
    /// center. In the lazy scrolling strip, tabs scrolled out of view report
    /// no frame; those before the first laid-out tab are to the left, so
    /// they count toward the index as well.
    var targetIndex: Int {
        guard let draggedTabID,
              let draggedFrame = frames[draggedTabID] else { return 0 }
        let center = pointerX - grabOffsetX + draggedFrame.width / 2
        let others = order.filter { $0 != draggedTabID }
        let hiddenLeadingCount = others.firstIndex {
            frames[$0] != nil
        } ?? others.count
        return hiddenLeadingCount + others
            .compactMap { frames[$0]?.midX }
            .count { $0 < center }
    }

    /// Visual x-offset for a tab while a drag is in progress. The dragged
    /// tab tracks the pointer; a neighbor shifts one slot when it is between
    /// the dragged tab's original index and its current target index.
    func offsetX(for tabID: UUID) -> CGFloat {
        guard let draggedTabID,
              let draggedFrame = frames[draggedTabID],
              let draggedIndex = order.firstIndex(of: draggedTabID) else {
            return 0
        }
        if tabID == draggedTabID {
            // Keep the dragged tab inside the strip even when the pointer
            // overshoots it.
            let stripMinX = frames.values.map(\.minX).min() ?? draggedFrame.minX
            let stripMaxX = frames.values.map(\.maxX).max() ?? draggedFrame.maxX
            let desiredLeft = min(
                max(pointerX - grabOffsetX, stripMinX),
                stripMaxX - draggedFrame.width
            )
            return desiredLeft - draggedFrame.minX
        }
        guard let index = order.firstIndex(of: tabID) else { return 0 }
        let slot = draggedFrame.width + stripSpacing
        let othersIndex = index > draggedIndex ? index - 1 : index
        let makesRoom: CGFloat = othersIndex >= targetIndex ? slot : 0
        let alreadyAfter: CGFloat = othersIndex >= draggedIndex ? slot : 0
        return makesRoom - alreadyAfter
    }
}

/// Transparent view behind the tab row's content that restores the standard
/// titlebar behaviors — window dragging and double-click zoom/minimize — for
/// the empty areas of the bar, since it now occupies the titlebar region.
///
/// It also implements drag-to-reorder for the tabs. That cannot live in the
/// SwiftUI layer or in an AppKit subview: the hosting hierarchy swallows
/// modified clicks before they reach tab buttons, gestures, or any overlay's
/// `hitTest`, and a drag that begins on a button belongs to that button. A
/// local event monitor sees every event ahead of dispatch: presses on a tab
/// pass through untouched (so click-to-select and the close button keep
/// working), and once the pointer moves past a small threshold the monitor
/// claims the rest of the sequence and drives `TabDragState`. This view
/// spans the whole bar, so converting event locations into its (flipped)
/// bounds yields the same coordinates as the tab frames reported in the
/// bar's named coordinate space — one coordinate system, pure AppKit
/// conversion.
private struct WindowDragArea: NSViewRepresentable {
    var orderedTabIDs: [UUID]
    var tabFrames: [UUID: CGRect]
    var dragState: TabDragState
    var selectTab: (UUID) -> Void
    var moveTab: (UUID, Int) -> Void

    final class DragView: NSView {
        var orderedTabIDs: [UUID] = []
        var tabFrames: [UUID: CGRect] = [:]
        var dragState: TabDragState?
        var selectTab: ((UUID) -> Void)?
        var moveTab: ((UUID, Int) -> Void)?
        private var reorderMonitor: Any?
        private var pendingTabID: UUID?
        private var pendingStartX: CGFloat = 0

        /// Horizontal movement, in points, that turns a press on a tab into
        /// a reorder drag instead of a click.
        private let dragThreshold: CGFloat = 4

        // Match SwiftUI's top-left-origin coordinates so event locations can
        // be compared against the tab frames from the bar's named space.
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            teardownMonitor()
            guard window != nil else { return }
            reorderMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handleReorder(event) ?? event
            }
        }

        deinit {
            teardownMonitor()
        }

        private func teardownMonitor() {
            if let reorderMonitor {
                NSEvent.removeMonitor(reorderMonitor)
            }
            reorderMonitor = nil
            pendingTabID = nil
        }

        /// Tracks presses on tabs; consumes the mouse sequence only once a
        /// drag is in progress, returning every other event unchanged.
        private func handleReorder(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let pointerX = convert(event.locationInWindow, from: nil).x
            switch event.type {
            case .leftMouseDown:
                guard let tabID = tabID(at: event) else { return event }
                pendingTabID = tabID
                pendingStartX = pointerX
                return event
            case .leftMouseDragged:
                if let dragState, dragState.isDragging {
                    dragState.update(pointerX: pointerX)
                    return nil
                }
                guard let pendingTabID,
                      abs(pointerX - pendingStartX) >= dragThreshold else {
                    return event
                }
                // The grabbed tab activates, matching a plain click.
                selectTab?(pendingTabID)
                dragState?.begin(
                    tabID: pendingTabID,
                    pointerX: pointerX,
                    frames: tabFrames,
                    order: orderedTabIDs
                )
                self.pendingTabID = nil
                return nil
            case .leftMouseUp:
                pendingTabID = nil
                guard let dragState, dragState.isDragging,
                      let draggedTabID = dragState.draggedTabID else {
                    return event
                }
                moveTab?(draggedTabID, dragState.targetIndex)
                dragState.end()
                // Swallow the up: the press passed through to the tab's
                // buttons, and completing it here could re-click whatever
                // ended under the pointer (notably the close button).
                return nil
            default:
                return event
            }
        }

        private func tabID(at event: NSEvent) -> UUID? {
            let local = convert(event.locationInWindow, from: nil)
            return orderedTabIDs.first { tabFrames[$0]?.contains(local) == true }
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize":
                    window.performMiniaturize(nil)
                case "None":
                    break
                default:
                    window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: DragView) {
        view.orderedTabIDs = orderedTabIDs
        view.tabFrames = tabFrames
        view.dragState = dragState
        view.selectTab = selectTab
        view.moveTab = moveTab
    }
}

/// Frames of each tab, keyed by tab ID, in the top bar's named coordinate
/// space. Reported by `RepositoryTabItem` and consumed by `WindowDragArea`
/// to hit-test tabs during ⌘-drag reordering.
private struct TabFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Concave quarter-circle fillet drawn just outside the active tab's base so
/// its edges curve outward into the panel surface below (an "inverted" corner
/// radius, like browser tabs).
private struct TabBaseFillet: Shape {
    var trailing = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if trailing {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.maxX, y: rect.minY), radius: rect.height,
                startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX, y: rect.minY), radius: rect.height,
                startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

private struct RepositoryTabItem: View {
    @EnvironmentObject private var tabsModel: WorkspaceTabsModel
    @ObservedObject var tab: RepositoryTab
    @ObservedObject var dragState: TabDragState
    let tabID: UUID
    let tabName: String
    let isActive: Bool
    @State private var hovering = false

    init(tab: RepositoryTab, isActive: Bool, dragState: TabDragState) {
        _tab = ObservedObject(wrappedValue: tab)
        _dragState = ObservedObject(wrappedValue: dragState)
        tabID = tab.id
        tabName = tab.displayName
        self.isActive = isActive
    }

    private var isDragged: Bool {
        dragState.draggedTabID == tabID
    }

    private var dragOffsetX: CGFloat {
        dragState.offsetX(for: tabID)
    }

    var body: some View {
        HStack(spacing: 1) {
            Button {
                tabsModel.select(tabID)
            } label: {
                HStack(spacing: 5) {
                    if tab.isSSH {
                        SSHLogo()
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                    }

                    Text(tabName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        // Hug the name instead of always expanding to the cap.
                        .frame(maxWidth: 140)
                        .fixedSize(horizontal: true, vertical: false)

                    if tab.hasChanges {
                        Circle()
                            .fill(AppTheme.modified)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Has changes")
                    }
                }
                .padding(.leading, 9)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAction(named: "Close \(tabName) Tab") {
                tabsModel.close(tabID)
            }

            Button {
                tabsModel.close(tabID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering || isActive ? 1 : 0)
            .allowsHitTesting(hovering || isActive)
            .accessibilityHidden(!(hovering || isActive))
            .accessibilityLabel("Close \(tabName) Tab")
            .help("Close Tab (⌘W)")
            .padding(.trailing, 2)
        }
        .foregroundStyle(isActive ? AppTheme.primary : AppTheme.secondary)
        .frame(minWidth: 64)
        .frame(height: 24)
        // The active tab grows a skirt down to the bar's bottom edge and is
        // filled with the panel's canvas color, so it flows seamlessly into
        // the content below (the bar's divider is drawn beneath the tabs).
        // Its top edge also rises above the inactive tabs and it casts a soft
        // shadow, so it reads as sitting on top of the bar rather than inset.
        .padding(.top, isActive ? 3 : 0)
        .padding(.bottom, isActive ? 5 : 0)
        .background {
            if isActive {
                UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: 5, bottomLeading: 0, bottomTrailing: 0, topTrailing: 5
                ))
                .fill(AppTheme.canvas)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            } else if hovering {
                RoundedRectangle(cornerRadius: 5)
                    .fill(AppTheme.raisedFill)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isActive {
                TabBaseFillet()
                    .fill(AppTheme.canvas)
                    .frame(width: 5, height: 5)
                    .offset(x: -5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isActive {
                TabBaseFillet(trailing: true)
                    .fill(AppTheme.canvas)
                    .frame(width: 5, height: 5)
                    .offset(x: 5)
            }
        }
        .padding(.bottom, isActive ? 0 : 5)
        .frame(height: 34, alignment: .bottom)
        // The offset comes before the frame-reporting background: modifiers
        // after .offset see the untranslated layout frame, so the reported
        // tab frames stay stable for hit-testing while the drag renders the
        // tab under the pointer.
        .offset(x: dragOffsetX)
        // Neighbors ease aside while a drag is in progress; the dragged tab
        // tracks the pointer directly. On drop everything changes in one
        // unanimated pass so the committed order lands exactly where the
        // tabs are already drawn.
        .animation(
            dragState.isDragging && !isDragged
                ? .easeInOut(duration: 0.13)
                : nil,
            value: dragOffsetX
        )
        .zIndex(isDragged ? 1 : 0)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TabFramesPreferenceKey.self,
                    value: [
                        tabID: proxy.frame(
                            in: .named(RepositoryTopBar.coordinateSpaceName)
                        )
                    ]
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(tab.repositoryURL?.path ?? "Open a repository")
        .contextMenu {
            Button("Close Tab") {
                tabsModel.close(tabID)
            }

            Button("Close Other Tabs") {
                tabsModel.closeOthers(tabID)
            }
            .disabled(tabsModel.tabs.count < 2)

            if let url = tab.repositoryURL {
                Divider()

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }

                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        }
    }
}

private struct GraphResizeHandle: View {
    @Binding var height: Double
    @Binding var heightAtDragStart: CGFloat?
    let currentHeight: CGFloat
    let allowedRange: ClosedRange<CGFloat>
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 5)
            .overlay {
                Rectangle()
                    .fill(isHovered ? AppTheme.actionBlue : AppTheme.edge)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if heightAtDragStart == nil {
                            heightAtDragStart = currentHeight
                        }
                        guard let heightAtDragStart else { return }
                        height = Double(clamp(
                            heightAtDragStart - value.translation.height
                        ))
                    }
                    .onEnded { _ in
                        heightAtDragStart = nil
                    }
            )
            .onTapGesture(count: 2) {
                height = Double(clamp(260))
            }
            .accessibilityLabel("Resize graph")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    height = Double(clamp(currentHeight + 24))
                case .decrement:
                    height = Double(clamp(currentHeight - 24))
                @unknown default:
                    break
                }
            }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, allowedRange.lowerBound), allowedRange.upperBound)
    }
}

private struct ChangesPanel: View {
    @EnvironmentObject private var model: RepositoryModel
    let isOpeningRepository: Bool
    @State private var stagedExpanded = true
    @State private var unstagedExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            ChangesActionBar()

            if isOpeningRepository || isModelOpeningRepository {
                ChangesPanelLoadingContent()
            } else {
                if let operation = model.activeOperation {
                    ConflictResolutionGuide(operation: operation)
                        .padding(.horizontal, 30)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                } else {
                    VStack(spacing: 10) {
                        CommitMessageField()
                        SplitCommitButton()
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !model.staged.isEmpty {
                            FileSection(
                                title: "Staged Changes",
                                changes: model.staged,
                                expanded: $stagedExpanded,
                                action: { Task { await model.unstageAll() } }
                            )
                        }

                        FileSection(
                            title: "Changes",
                            changes: model.unstaged,
                            expanded: $unstagedExpanded,
                            action: { Task { await model.stageAll() } }
                        )

                        if model.staged.isEmpty && model.unstaged.isEmpty {
                            Text("No changes — working tree is clean")
                                .font(AppType.rowDetail)
                                .foregroundStyle(AppTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 31)
                                .padding(.top, 8)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var isModelOpeningRepository: Bool {
        model.repositoryURL == nil && model.isBusy
    }
}

private struct ConflictResolutionGuide: View {
    @EnvironmentObject private var model: RepositoryModel
    let operation: GitOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: unresolvedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }

            Text(instructions)
                .font(AppType.rowDetail)
                .foregroundStyle(AppTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Abort \(operation.displayName)", role: .destructive) {
                    Task { await model.abortActiveOperation() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.deleted)

                Spacer(minLength: 8)

                Button(primaryActionTitle) {
                    if model.hasUnresolvedConflicts {
                        model.openNextConflict()
                    } else {
                        Task { await model.continueActiveOperation() }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    AppTheme.actionBlue,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .help(primaryActionHelp)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(AppTheme.inputFill)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(statusColor.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }

    private var unresolvedCount: Int {
        model.unresolvedConflicts.count
    }

    private var title: String {
        if unresolvedCount == 0 { return "\(operation.displayName) ready to continue" }
        return unresolvedCount == 1
            ? "Resolve 1 conflict"
            : "Resolve \(unresolvedCount) conflicts"
    }

    private var instructions: String {
        if unresolvedCount == 0 {
            return operation == .merge
                ? "All conflicts are staged. Continue to create the merge commit."
                : "All conflicts are staged. Continue replaying commits onto the target branch."
        }
        return "Open a conflicted file, choose a result for each hunk, then mark it resolved."
    }

    private var statusColor: Color {
        unresolvedCount == 0 ? AppTheme.added : AppTheme.conflict
    }

    private var primaryActionTitle: String {
        model.hasUnresolvedConflicts
            ? "Resolve Next Conflict"
            : "Continue \(operation.displayName)"
    }

    private var primaryActionHelp: String {
        if model.hasUnresolvedConflicts { return "Open the next conflicted file" }
        return operation == .merge ? "Create the merge commit" : "Continue the operation"
    }
}

private struct ChangesPanelLoadingContent: View {
    private let rowWidths: [CGFloat] = [132, 184, 106, 156]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                LoadingFieldPlaceholder()

                LoadingPlaceholder(width: nil, height: 32, cornerRadius: 6)
            }
            .padding(.horizontal, 30)
            .padding(.top, 2)
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                LoadingPlaceholder(width: 82, height: 13, cornerRadius: 3)
                LoadingPlaceholder(width: 22, height: 17, cornerRadius: 8.5)
                Spacer()
            }
            .padding(.horizontal, 31)
            .frame(height: 33)

            ForEach(Array(rowWidths.enumerated()), id: \.offset) { index, width in
                HStack(spacing: 9) {
                    LoadingPlaceholder(width: 17, height: 17, cornerRadius: 3)

                    VStack(alignment: .leading, spacing: 4) {
                        LoadingPlaceholder(width: width, height: 10, cornerRadius: 3)
                        LoadingPlaceholder(
                            width: max(54, width * 0.58),
                            height: 7,
                            cornerRadius: 2.5
                        )
                    }

                    Spacer(minLength: 8)

                    LoadingPlaceholder(
                        width: index == 1 ? 18 : 12,
                        height: 10,
                        cornerRadius: 3
                    )
                }
                .padding(.horizontal, 31)
                .frame(height: 32)
            }

            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

private struct LoadingFieldPlaceholder: View {
    var body: some View {
        HStack {
            LoadingPlaceholder(width: 146, height: 10, cornerRadius: 3)
            Spacer()
            LoadingPlaceholder(width: 17, height: 17, cornerRadius: 5)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(AppTheme.inputFill)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.inputBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct LoadingPlaceholder: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(AppTheme.secondary.opacity(0.13))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
    }
}

private struct ChangesActionBar: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        HStack(spacing: 0) {
            RepositoryModePicker()

            Spacer()

            if model.sshRepository != nil {
                RepositoryReloadButton()
                    .padding(.trailing, 4)
            }

            RepositoryTerminalButton()

            RepositoryLocationMenu()
                .padding(.leading, 4)
        }
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .frame(maxWidth: .infinity)
        // Tall enough to give the 30pt mode picker capsule clear air above
        // and below, matching Xcode's navigator-switcher bar.
        .frame(height: 46)
        // With window-server dragging disabled (`isMovable = false`), give
        // the empty areas of this bar back to window dragging.
        .background(WindowDragHandle())
    }
}

/// Background view whose empty areas drag the window. Needed because
/// AppKit-initiated window dragging is disabled (`NSWindow.isMovable` is
/// false, see `WindowConfigurator`), so any region that should move the
/// window must call `performDrag` explicitly.
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView {
        HandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SpinningCodiconGlyph: View {
    let icon: Codicon
    let isSpinning: Bool
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isSpinning && !reduceMotion {
            RotatingCodiconGlyph(icon: icon, size: size)
        } else {
            CodiconGlyph(icon: icon, size: size)
        }
    }
}

private struct RotatingCodiconGlyph: View {
    let icon: Codicon
    let size: CGFloat
    @State private var rotating = false

    var body: some View {
        CodiconGlyph(icon: icon, size: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}

private struct CodiconButton: View {
    let icon: Codicon
    let help: String
    var size: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CodiconGlyph(icon: icon, size: size)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.primary)
        .accessibilityLabel(help)
        .help(help)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.primary)
        .accessibilityLabel(help)
        .help(help)
    }
}

private struct CommitMessageField: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        CommitMessageInput(
            model: model,
            messageState: model.commitMessageState
        )
    }
}

private struct CommitMessageInput: View {
    @ObservedObject var model: RepositoryModel
    @ObservedObject var messageState: CommitMessageState
    @AppStorage(AICommitMessagePreferences.providerKey)
    private var aiProviderRawValue = AICommitMessageProvider.codex.rawValue
    @FocusState private var focused: Bool

    private var aiProvider: AICommitMessageProvider {
        AICommitMessageProvider(rawValue: aiProviderRawValue) ?? .codex
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .leading) {
                if messageState.text.isEmpty {
                    Text("Message (⌘Enter to commit on \"\(model.branch)\")")
                        .font(AppType.row)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                TextField("", text: $messageState.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppType.row)
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityLabel("Commit message")
                    .focused($focused)
                    .lineLimit(1...10)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(
                        model.isBusy
                            || model.isSavingRepositoryFile
                            || model.hasPendingChangeOperations
                    )
            }

            Button {
                Task { await model.generateCommitMessage() }
            } label: {
                Group {
                    if model.isGeneratingCommitMessage {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.primary.opacity(0.9))
            .padding(.top, 1)
            .accessibilityLabel("Generate Commit Message from Staged Changes")
            .help(
                model.hasStagedChanges
                    ? (messageState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Generate a Commit Message from Staged Changes with \(aiProvider.displayName)"
                        : "Use This Text as Instructions for \(aiProvider.displayName)")
                    : "Stage changes before generating a commit message"
            )
            .disabled(
                !model.hasStagedChanges
                || model.isBusy
                || model.isSavingRepositoryFile
                || model.hasPendingChangeOperations
                || model.isGeneratingCommitMessage
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 34)
        .background(AppTheme.inputFill)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    focused ? AppTheme.graphBlue : AppTheme.inputBorder,
                    lineWidth: focused ? 1.5 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SplitCommitButton: View {
    @EnvironmentObject private var model: RepositoryModel

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Task { await model.performPrimaryAction() }
            } label: {
                HStack(spacing: 7) {
                    SpinningCodiconGlyph(
                        icon: primaryActionIcon,
                        isSpinning: model.isSyncing && model.primaryAction == .sync,
                        size: 15
                    )
                    Text(model.primaryActionTitle)
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(buttonBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .disabled(!model.primaryActionEnabled)

            if model.primaryAction != .publish {
                Menu {
                    if model.primaryAction == .commit {
                        Button("Commit Staged Changes") {
                            Task { await model.commit() }
                        }
                        .disabled(!model.hasStagedChanges)

                        Button("Commit All Changes") {
                            Task { await model.commitAll() }
                        }

                        Divider()

                        Button("Amend Last Commit") {
                            Task { await model.amend() }
                        }

                        Button("Amend Last Commit, Keep Message") {
                            Task { await model.amendNoEdit() }
                        }
                        .disabled(!model.hasStagedChanges)

                        Divider()

                        Button(commitAndRemoteTitle) {
                            Task { await commitAndRemote() }
                        }

                        if let operation = model.activeOperation {
                            Divider()

                            Button("Continue \(operation.displayName)") {
                                Task { await model.continueActiveOperation() }
                            }

                            if model.canSkipActiveOperation {
                                Button("Skip Current Commit") {
                                    Task { await model.skipActiveOperation() }
                                }
                            }

                            Button("Abort \(operation.displayName)…", role: .destructive) {
                                Task { await model.abortActiveOperation() }
                            }
                        }
                    } else {
                        Button("Push") {
                            Task { await model.push() }
                        }

                        Button("Pull") {
                            Task { await model.pull() }
                        }

                        Divider()

                        Button("Force Push with Lease…") {
                            Task { await model.forcePushWithLease() }
                        }

                        Button("Force Push Without Lease…") {
                            Task { await model.forcePush() }
                        }
                    }
                } label: {
                    ZStack {
                        Rectangle()
                            .fill(buttonBackground)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(buttonForeground)
                    }
                    .frame(width: Self.menuWidth, height: 32)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .tint(buttonForeground)
                .frame(width: Self.menuWidth, height: 32)
                .background(buttonBackground)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(buttonForeground.opacity(0.32))
                        .frame(width: 1)
                        .padding(.vertical, 5)
                }
                .contentShape(Rectangle())
                .help(actionMenuLabel)
                .accessibilityLabel(actionMenuLabel)
            }
        }
        .foregroundStyle(buttonForeground)
        .frame(height: 32)
        .background(buttonBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .disabled(actionsDisabled)
    }

    private static let menuWidth: CGFloat = 38

    private var buttonBackground: Color {
        model.primaryActionEnabled
            ? AppTheme.actionBlue
            : AppTheme.disabledFill
    }

    private var buttonForeground: Color {
        model.primaryActionEnabled
            ? AppTheme.onAccent
            : AppTheme.muted
    }

    private var actionMenuLabel: String {
        model.primaryAction == .sync ? "Sync Actions" : "Commit Actions"
    }

    private var actionsDisabled: Bool {
        model.isBusy
            || model.isSavingRepositoryFile
            || model.isGeneratingCommitMessage
            || model.hasPendingChangeOperations
    }

    private var primaryActionIcon: Codicon {
        switch model.primaryAction {
        case .commit: return .check
        case .publish: return .repoPush
        case .sync: return .sync
        }
    }

    private var commitAndRemoteTitle: String {
        if !model.hasUpstream { return "Commit and Publish Branch" }
        if model.behind > 0 { return "Commit, then Sync" }
        return "Commit and Push"
    }

    private func commitAndRemote() async {
        if model.hasUpstream && model.behind > 0 {
            await model.commitAndSync()
        } else {
            await model.commitAndPush()
        }
    }
}

private struct FileSection: View {
    @EnvironmentObject private var model: RepositoryModel
    let title: String
    let changes: [FileChange]
    @Binding var expanded: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var selectedGroupID: String?
    @State private var filePage = 0
    @State private var groupPage = 0

    private let directFileLimit = 250
    private let filesPerPage = 200
    private let groupsPerPage = 100

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 0) {
                        Text(title)
                            .font(AppType.sectionTitle)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(expanded ? "Collapse" : "Expand") \(title)"
                )

                if !changes.isEmpty {
                    if title == "Changes" {
                        IconButton(
                            symbol: "arrow.uturn.backward",
                            help: "Discard All Unstaged Changes",
                            size: 13
                        ) {
                            guard GitPrompt.confirmDiscardAllUnstagedChanges() else { return }
                            Task { await model.discardAllUnstagedChanges() }
                        }
                        .disabled(actionsDisabled || model.hasUnresolvedConflicts)
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(hovering)
                    }

                    IconButton(
                        symbol: title == "Changes" ? "plus" : "minus",
                        help: title == "Changes"
                            ? "Stage All Changes"
                            : "Unstage All Changes",
                        size: 13,
                        action: action
                    )
                    .disabled(
                        actionsDisabled
                    )
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)

                    Text("\(changes.count)")
                        .font(AppType.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.badgeText)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(AppTheme.badgeBlue, in: Capsule())
                        .help(
                            title == "Changes"
                                ? "\(changes.count) unstaged changes"
                                : "\(changes.count) staged changes"
                        )
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 21)
            .frame(height: 33)
            .contentShape(Rectangle())
            .foregroundStyle(AppTheme.primary)
            .background(hovering ? AppTheme.hover : .clear)
            .onHover { hovering = $0 }
            .contextMenu {
                Button(title == "Changes" ? "Stage All" : "Unstage All", action: action)
                    .disabled(changes.isEmpty || actionsDisabled)

                if title == "Changes" {
                    Divider()

                    Button("Stash Changes…") {
                        guard let stash = GitPrompt.stash() else { return }
                        Task {
                            await model.stashChanges(
                                message: stash.message,
                                includeUntracked: stash.includeUntracked
                            )
                        }
                    }
                    .disabled(!model.hasChanges || actionsDisabled)

                    Button("Discard All Changes…", role: .destructive) {
                        guard GitPrompt.confirmDiscardAllChanges() else { return }
                        Task { await model.discardAllChanges() }
                    }
                    .disabled(!model.hasChanges || model.headHash == nil || actionsDisabled)
                }
            }
            .accessibilityActions {
                Button(title == "Changes" ? "Stage All Changes" : "Unstage All Changes") {
                    guard !changes.isEmpty, !actionsDisabled else { return }
                    action()
                }

                if title == "Changes" {
                    Button("Discard All Unstaged Changes") {
                        guard !changes.isEmpty,
                              !actionsDisabled,
                              !model.hasUnresolvedConflicts,
                              GitPrompt.confirmDiscardAllUnstagedChanges() else { return }
                        Task { await model.discardAllUnstagedChanges() }
                    }
                }
            }

            if expanded {
                if changes.count <= directFileLimit {
                    ForEach(changes) { change in
                        FileChangeRow(change: change)
                    }
                } else {
                    largeChangesContent
                }
            }
        }
        .onChange(of: changes) {
            normalizePagination()
        }
    }

    @ViewBuilder
    private var largeChangesContent: some View {
        let groups = changeGroups
        if let selectedGroup = groups.first(where: { $0.id == selectedGroupID }) {
            LargeChangeGroupHeader(
                group: selectedGroup,
                page: filePage,
                pageCount: pageCount(selectedGroup.changes.count, size: filesPerPage),
                back: {
                    selectedGroupID = nil
                    filePage = 0
                },
                previous: { filePage = max(0, filePage - 1) },
                next: {
                    filePage = min(
                        pageCount(selectedGroup.changes.count, size: filesPerPage) - 1,
                        filePage + 1
                    )
                }
            )

            ForEach(fileSlice(for: selectedGroup)) { change in
                FileChangeRow(change: change)
            }
        } else {
            ForEach(groupSlice(from: groups)) { group in
                Button {
                    selectedGroupID = group.id
                    filePage = 0
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondary)
                            .frame(width: 20)

                        Text(group.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.primary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(group.changes.count)")
                            .font(AppType.captionEmphasis)
                            .foregroundStyle(AppTheme.secondary)
                    }
                    .padding(.horizontal, 28)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(group.title)
            }

            if groups.count > groupsPerPage {
                ChangePaginationRow(
                    page: groupPage,
                    pageCount: pageCount(groups.count, size: groupsPerPage),
                    label: "folders",
                    previous: { groupPage = max(0, groupPage - 1) },
                    next: {
                        groupPage = min(
                            pageCount(groups.count, size: groupsPerPage) - 1,
                            groupPage + 1
                        )
                    }
                )
            }
        }
    }

    private var changeGroups: [FileChangeGroup] {
        let grouped = Dictionary(grouping: changes) { change -> String in
            let components = change.path.split(separator: "/", maxSplits: 1)
            return components.count > 1 ? String(components[0]) : ""
        }
        return grouped.map { key, values in
            FileChangeGroup(
                id: key,
                title: key.isEmpty ? "Repository root" : key,
                changes: values
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func groupSlice(from groups: [FileChangeGroup]) -> ArraySlice<FileChangeGroup> {
        let start = min(groupPage * groupsPerPage, groups.count)
        let end = min(start + groupsPerPage, groups.count)
        return groups[start..<end]
    }

    private func fileSlice(for group: FileChangeGroup) -> ArraySlice<FileChange> {
        let start = min(filePage * filesPerPage, group.changes.count)
        let end = min(start + filesPerPage, group.changes.count)
        return group.changes[start..<end]
    }

    private func pageCount(_ count: Int, size: Int) -> Int {
        max(1, Int(ceil(Double(count) / Double(size))))
    }

    private var actionsDisabled: Bool {
        model.isBusy
            || model.hasPendingChangeOperations
            || model.isGeneratingCommitMessage
    }

    private func normalizePagination() {
        let groups = changeGroups
        groupPage = min(
            groupPage,
            pageCount(groups.count, size: groupsPerPage) - 1
        )

        guard let selectedGroupID,
              let selectedGroup = groups.first(where: { $0.id == selectedGroupID }) else {
            self.selectedGroupID = nil
            filePage = 0
            return
        }

        filePage = min(
            filePage,
            pageCount(selectedGroup.changes.count, size: filesPerPage) - 1
        )
    }
}

private struct FileChangeGroup: Identifiable {
    let id: String
    let title: String
    let changes: [FileChange]
}

private struct LargeChangeGroupHeader: View {
    let group: FileChangeGroup
    let page: Int
    let pageCount: Int
    let back: () -> Void
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to change folders")
            .help("Back to change folders")

            Text(group.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Text("\(group.changes.count) files")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondary)

            Spacer()

            if pageCount > 1 {
                PaginationButtons(page: page, pageCount: pageCount, previous: previous, next: next)
            }
        }
        .padding(.horizontal, 23)
        .frame(height: 32)
        .background(AppTheme.inputFill)
    }
}

private struct ChangePaginationRow: View {
    let page: Int
    let pageCount: Int
    let label: String
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            Text("Page \(page + 1) of \(pageCount) \(label)")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondary)
            Spacer()
            PaginationButtons(page: page, pageCount: pageCount, previous: previous, next: next)
        }
        .padding(.horizontal, 28)
        .frame(height: 32)
    }
}

private struct PaginationButtons: View {
    let page: Int
    let pageCount: Int
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: previous) {
                Image(systemName: "chevron.left").frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(page == 0)
            .accessibilityLabel("Previous page")
            .help("Previous page")

            Text("\(page + 1)/\(pageCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.secondary)

            Button(action: next) {
                Image(systemName: "chevron.right").frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(page + 1 >= pageCount)
            .accessibilityLabel("Next page")
            .help("Next page")
        }
    }
}

private struct FileChangeRow: View {
    @EnvironmentObject private var model: RepositoryModel
    let change: FileChange
    @State private var hovering = false
    @State private var discardConfirmationPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.activate(change)
            } label: {
                HStack(spacing: 8) {
                    FileIconView(path: change.path, size: 14, width: 21)

                    HStack(spacing: 8) {
                        Text(change.name)
                            .font(AppType.row)
                            .foregroundStyle(AppTheme.primary)
                            .lineLimit(1)
                            .layoutPriority(1)

                        if !change.parentPath.isEmpty {
                            Text(change.parentPath)
                                .font(AppType.rowDetail)
                                .foregroundStyle(AppTheme.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(change.path)

            if model.isChangeOperationPending(change) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppTheme.secondary)
                    .frame(width: 18)
                    .accessibilityLabel("Updating \(change.name)")
            } else if isReopenableConflict {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.conflict)
                    .frame(width: 18, alignment: .trailing)
                    .accessibilityLabel(statusDescription)
                    .help(statusDescription)
            } else {
                Text(change.status)
                    .font(AppType.statusLetter)
                    .foregroundStyle(statusColor)
                    .frame(width: 18, alignment: .trailing)
                    .accessibilityLabel(statusDescription)
                    .help(statusDescription)
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 23)
        .frame(height: 31)
        .contentShape(Rectangle())
        .background(
            model.selectedChange == change
                ? AppTheme.selection
                : (hovering ? AppTheme.hover : .clear)
        )
        // The hover actions float above the label instead of sitting in the
        // HStack, so they never steal width from the filename; the text fades
        // out beneath them behind a scrim.
        .overlay(alignment: .trailing) {
            hoverActions
        }
        .onHover { hovering = $0 }
        .alert(discardConfirmationTitle, isPresented: $discardConfirmationPresented) {
            Button(discardConfirmationAction, role: .destructive) {
                Task { await model.discard(change) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(discardConfirmationMessage)
        }
        .contextMenu {
            if isResolvableConflict {
                Button("Resolve Conflict") {
                    model.select(change)
                }
                .disabled(operationDisabled)
            } else {
                if isReopenableConflict {
                    Button("Reopen Conflict") {
                        Task { await model.reopenConflict(change) }
                    }
                    .disabled(operationDisabled)

                    Divider()
                }

                if change.area == .unstaged {
                    Button("Discard Changes…") {
                        discardConfirmationPresented = true
                    }

                    Divider()
                }

                if change.area == .unstaged || !isReopenableConflict {
                    Button(change.area == .staged ? "Unstage" : "Stage") {
                        performStageToggle()
                    }
                    .disabled(operationDisabled)
                }
            }

            Divider()

            Button("Open in Files") {
                model.openInFiles(change)
            }
            .disabled(!model.canOpenInFiles(change))

            Button("Reveal in Finder") {
                revealRepositoryFileInFinder(change.path, repositoryURL: model.repositoryURL)
            }

            Button("Copy Path") {
                copyRepositoryFilePath(change.path, repositoryURL: model.repositoryURL)
            }
        }
        .accessibilityActions {
            if isResolvableConflict {
                Button("Resolve Conflict in \(change.name)") {
                    model.select(change)
                }
                .disabled(operationDisabled)
            } else {
                if isReopenableConflict {
                    Button("Reopen conflict in \(change.name)") {
                        Task { await model.reopenConflict(change) }
                    }
                    .disabled(operationDisabled)
                }

                if change.area == .unstaged || !isReopenableConflict {
                    Button(change.area == .staged ? "Unstage \(change.name)" : "Stage \(change.name)") {
                        performStageToggle()
                    }
                    .disabled(operationDisabled)
                }
            }

            if change.status != "D" {
                Button("Open \(change.name) in Files") {
                    model.openInFiles(change)
                }
            }

            if change.area == .unstaged && !isResolvableConflict {
                Button("Discard Changes in \(change.name)") {
                    discardConfirmationPresented = true
                }
                .disabled(operationDisabled)
            }
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 8) {
            if change.status != "D" {
                Button {
                    model.openInFiles(change)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(change.name) in Files")
                .help("Open in Files")
            }

            if isResolvableConflict {
                Button {
                    model.select(change)
                } label: {
                    Text("Resolve")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(operationDisabled)
                .accessibilityLabel("Resolve conflict in \(change.name)")
                .help("Resolve Conflict")
            } else if isReopenableConflict {
                Button {
                    Task { await model.reopenConflict(change) }
                } label: {
                    Text("Reopen")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(operationDisabled)
                .accessibilityLabel("Reopen conflict in \(change.name)")
                .help("Restore the conflict versions and reopen the resolver")
            } else if change.area == .unstaged {
                Button {
                    discardConfirmationPresented = true
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard Changes in \(change.name)")
                .help("Discard Changes")
                .disabled(operationDisabled)
            }

            if !isResolvableConflict && (change.area == .unstaged || !isReopenableConflict) {
                Button {
                    performStageToggle()
                } label: {
                    Image(systemName: change.area == .staged ? "minus" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    change.area == .staged ? "Unstage \(change.name)" : "Stage \(change.name)"
                )
                .disabled(operationDisabled)
            }
        }
        .foregroundStyle(AppTheme.primary)
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .background(hoverActionScrim)
        // Stop short of the status letter (23pt row inset + its 18pt slot)
        // so it stays visible beside the actions.
        .padding(.trailing, 41)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
        .accessibilityHidden(!hovering)
    }

    /// Opaque backdrop for the floating actions with a soft leading fade.
    /// Canvas sits underneath because the selection tint is translucent and
    /// would otherwise let the covered text bleed through.
    private var hoverActionScrim: some View {
        ZStack {
            AppTheme.canvas

            if model.selectedChange == change {
                AppTheme.selection
            } else {
                AppTheme.hover
            }
        }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 20)

                Rectangle()
            }
        )
    }

    private var discardConfirmationTitle: String {
        change.status == "U" ? "Delete Untracked File?" : "Discard Changes?"
    }

    private var discardConfirmationAction: String {
        change.status == "U" ? "Delete" : "Discard Changes"
    }

    private var discardConfirmationMessage: String {
        if change.status == "U" {
            return "Delete “\(change.path)” from disk. This action cannot be undone by Kvist."
        }
        return "Discard all unstaged changes in “\(change.path)”. This action cannot be undone by Kvist."
    }

    private var fileIcon: String {
        FileGlyph.symbol(forPath: change.path)
    }

    private var statusColor: Color {
        switch change.status {
        case "A", "U": return AppTheme.added
        case "D": return AppTheme.deleted
        case "R", "C": return AppTheme.graphBlue
        case "!": return AppTheme.conflict
        default: return AppTheme.modified
        }
    }

    private var statusDescription: String {
        if isReopenableConflict {
            return "Conflict resolution was unstaged; the conflict can be reopened"
        }
        switch change.status {
        case "A": return "Added"
        case "U": return "Untracked"
        case "D": return "Deleted"
        case "R": return "Renamed"
        case "C": return "Copied"
        case "!": return "Conflict"
        default: return "Modified"
        }
    }

    private var operationDisabled: Bool {
        model.isBusy
            || model.isGeneratingCommitMessage
            || model.isChangeOperationPending(change)
    }

    private var isResolvableConflict: Bool {
        model.activeOperation != nil
            && change.area == .unstaged
            && change.status == "!"
    }

    private var isReopenableConflict: Bool {
        model.isReopenableConflict(change)
    }

    private func performStageToggle() {
        guard !operationDisabled else { return }
        Task {
            if change.area == .staged {
                await model.unstage(change)
            } else {
                await model.stage(change)
            }
        }
    }
}

@MainActor
private final class GraphNestedFileHoverState: ObservableObject {
    @Published var hoveredID: String?
}

private struct GraphPanel: View {
    @EnvironmentObject private var model: RepositoryModel
    let isOpeningRepository: Bool
    @State private var revealHeadRequest = 0
    @StateObject private var nestedFileHoverState = GraphNestedFileHoverState()

    var body: some View {
        VStack(spacing: 0) {
            GraphHeader {
                guard model.headHash != nil else { return }
                revealHeadRequest &+= 1
            }

            if isOpeningRepository || (model.repositoryURL == nil && model.isBusy) {
                GraphPanelLoadingContent()
            } else {
                GraphHistoryTable(revealHeadRequest: revealHeadRequest)
            }
        }
        .environmentObject(nestedFileHoverState)
    }
}

private struct GraphPanelLoadingContent: View {
    private let rowWidths: [CGFloat] = [176, 214, 148, 192]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rowWidths.enumerated()), id: \.offset) { index, width in
                HStack(spacing: 8) {
                    LoadingGraphMark(
                        isFirst: index == 0,
                        isLast: index == rowWidths.count - 1
                    )
                    .frame(width: 22, height: 32)

                    LoadingPlaceholder(width: width, height: 10, cornerRadius: 3)

                    if index == 0 || index == 2 {
                        LoadingPlaceholder(
                            width: index == 0 ? 48 : 62,
                            height: 16,
                            cornerRadius: 8
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 31)
                .frame(height: 32)
            }

            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

private struct LoadingGraphMark: View {
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppTheme.graphBlue.opacity(0.3))
                    .frame(width: 1, height: isFirst ? 16 : 14)
                    .opacity(isFirst ? 0 : 1)

                Rectangle()
                    .fill(AppTheme.graphBlue.opacity(0.3))
                    .frame(width: 1, height: isLast ? 16 : 18)
                    .opacity(isLast ? 0 : 1)
            }

            Circle()
                .stroke(AppTheme.graphBlue.opacity(0.5), lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .background(AppTheme.canvas, in: Circle())
        }
    }
}

private struct GraphHistoryTable: NSViewRepresentable {
    @EnvironmentObject private var model: RepositoryModel
    let revealHeadRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        // The automatic style resolves to the inset style and pads rows by
        // ~16pt per side, shrinking the commit-message column. Plain keeps
        // the full panel width for rows.
        table.style = .plain
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.wantsLayer = true
        table.layerContentsRedrawPolicy = .onSetNeedsDisplay
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Graph")))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = table
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.install(scrollView: scrollView, tableView: table)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            model: model,
            revealHeadRequest: revealHeadRequest
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private enum DisplayRowKind: UInt8 {
            case commit
            case loading
            case empty
            case file
        }

        private struct DisplayRow {
            let kind: DisplayRowKind
            let graphIndex: Int
            let fileIndex: Int
        }

        private var model: RepositoryModel
        private weak var tableView: NSTableView?
        private weak var scrollView: NSScrollView?
        private var displayRows: [DisplayRow] = []
        private var graphRowCount = 0
        private var firstGraphID: String?
        private var lastGraphID: String?
        private var graphPublicationVersion = 0
        private var graphScope: GraphScope?
        private var expandedSignature: [String: Int] = [:]
        private var revealHeadRequest = 0
        private var boundsObserver: NSObjectProtocol?
        private weak var hoveredNestedCell: GraphNestedTableCell?

        init(model: RepositoryModel) {
            self.model = model
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func install(scrollView: NSScrollView, tableView: NSTableView) {
            self.scrollView = scrollView
            self.tableView = tableView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.loadMoreIfNeeded() }
            }
        }

        func update(model: RepositoryModel, revealHeadRequest: Int) {
            self.model = model
            guard let tableView else { return }
            let newExpandedSignature = expansionSignature(model: model)
            let newFirstID = model.graph.first?.id
            let newLastID = model.graph.last?.id
            let isAppend = newExpandedSignature.isEmpty
                && expandedSignature.isEmpty
                && model.graph.count > graphRowCount
                && model.graph.indices.contains(max(0, graphRowCount - 1))
                && model.graph[max(0, graphRowCount - 1)].id == lastGraphID
                && model.graph.first?.id == firstGraphID
                && model.graphScope == graphScope
            if isAppend {
                let oldDisplayCount = displayRows.count
                displayRows.append(contentsOf: (graphRowCount..<model.graph.count).map {
                    DisplayRow(kind: .commit, graphIndex: $0, fileIndex: -1)
                })
                let inserted = IndexSet(oldDisplayCount..<displayRows.count)
                tableView.insertRows(at: inserted, withAnimation: [])
            } else if model.graph.count != graphRowCount
                        || newFirstID != firstGraphID
                        || newLastID != lastGraphID
                        || model.graphPublicationVersion != graphPublicationVersion
                        || model.graphScope != graphScope
                        || newExpandedSignature != expandedSignature {
                displayRows = makeDisplayRows(model: model)
                tableView.reloadData()
            }
            graphRowCount = model.graph.count
            firstGraphID = newFirstID
            lastGraphID = newLastID
            graphPublicationVersion = model.graphPublicationVersion
            graphScope = model.graphScope
            expandedSignature = newExpandedSignature

            if revealHeadRequest != self.revealHeadRequest {
                self.revealHeadRequest = revealHeadRequest
                if let headHash = model.headHash,
                   let graphIndex = model.graph.firstIndex(where: {
                       $0.commit.hash == headHash
                   }),
                   let index = displayRows.firstIndex(where: {
                       $0.kind == .commit && $0.graphIndex == graphIndex
                   }) {
                    tableView.scrollRowToVisible(index)
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            displayRows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard displayRows.indices.contains(row) else { return 32 }
            return displayRows[row].kind == .commit ? 32 : 28
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard displayRows.indices.contains(row) else { return nil }
            let displayRow = displayRows[row]
            guard model.graph.indices.contains(displayRow.graphIndex) else { return nil }
            let graphRow = model.graph[displayRow.graphIndex]
            switch displayRow.kind {
            case .commit:
                let identifier = NSUserInterfaceItemIdentifier("GraphCommit")
                let view = tableView.makeView(
                    withIdentifier: identifier,
                    owner: nil
                ) as? GraphCommitTableCell ?? GraphCommitTableCell()
                view.identifier = identifier
                view.configure(
                    row: graphRow,
                    model: model
                )
                return view
            case .loading:
                return nestedView(
                    tableView: tableView,
                    identifier: "GraphLoading",
                    row: graphRow,
                    commit: nil,
                    file: nil,
                    message: "Loading changed files…"
                )
            case .empty:
                return nestedView(
                    tableView: tableView,
                    identifier: "GraphEmpty",
                    row: graphRow,
                    commit: nil,
                    file: nil,
                    message: "No changed files"
                )
            case .file:
                let commit = graphRow.commit
                let files = model.files(for: commit)
                guard files.indices.contains(displayRow.fileIndex) else { return nil }
                return nestedView(
                    tableView: tableView,
                    identifier: "GraphFile",
                    row: graphRow,
                    commit: commit,
                    file: files[displayRow.fileIndex],
                    message: nil
                )
            }
        }

        private func loadMoreIfNeeded() {
            guard let scrollView, let tableView, model.canLoadMoreGraph,
                  !model.isLoadingMoreGraph else { return }
            let visibleBottom = scrollView.contentView.bounds.maxY
            if visibleBottom >= tableView.bounds.height - 160 {
                Task { await model.loadMoreGraph() }
            }
        }

        private func makeDisplayRows(model: RepositoryModel) -> [DisplayRow] {
            var result: [DisplayRow] = []
            result.reserveCapacity(model.graph.count + model.commitFilesByHash.values.reduce(0) {
                $0 + $1.count
            })
            for (graphIndex, row) in model.graph.enumerated() {
                result.append(DisplayRow(
                    kind: .commit,
                    graphIndex: graphIndex,
                    fileIndex: -1
                ))
                guard model.expandedCommitHashes.contains(row.commit.hash) else { continue }
                if model.loadingCommitFileHashes.contains(row.commit.hash) {
                    result.append(DisplayRow(
                        kind: .loading,
                        graphIndex: graphIndex,
                        fileIndex: -1
                    ))
                } else {
                    let files = model.files(for: row.commit)
                    if files.isEmpty {
                        result.append(DisplayRow(
                            kind: .empty,
                            graphIndex: graphIndex,
                            fileIndex: -1
                        ))
                    } else {
                        result.append(contentsOf: files.indices.map {
                            DisplayRow(
                                kind: .file,
                                graphIndex: graphIndex,
                                fileIndex: $0
                            )
                        })
                    }
                }
            }
            return result
        }

        private func expansionSignature(model: RepositoryModel) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: model.expandedCommitHashes.map { hash in
                let count = model.loadingCommitFileHashes.contains(hash)
                    ? -1
                    : model.commitFilesByHash[hash]?.count ?? 0
                return (hash, count)
            })
        }

        private func nestedView(
            tableView: NSTableView,
            identifier rawIdentifier: String,
            row: GraphRow,
            commit: CommitInfo?,
            file: CommitFileChange?,
            message: String?
        ) -> GraphNestedTableCell {
            let identifier = NSUserInterfaceItemIdentifier(rawIdentifier)
            let view = tableView.makeView(
                withIdentifier: identifier,
                owner: nil
            ) as? GraphNestedTableCell ?? GraphNestedTableCell()
            view.identifier = identifier
            view.hoverChanged = { [weak self] cell, hovering in
                self?.setNestedCell(cell, hovering: hovering)
            }
            view.configure(
                row: row,
                commit: commit,
                file: file,
                message: message,
                model: model
            )
            return view
        }

        private func setNestedCell(
            _ cell: GraphNestedTableCell,
            hovering: Bool
        ) {
            if hovering {
                if hoveredNestedCell !== cell {
                    hoveredNestedCell?.setHovering(false)
                }
                hoveredNestedCell = cell
                cell.setHovering(true)
            } else {
                cell.setHovering(false)
                if hoveredNestedCell === cell {
                    hoveredNestedCell = nil
                }
            }
        }
    }
}

@MainActor
private final class GraphCommitTableCell: NSView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installHostingView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installHostingView()
    }

    func configure(row: GraphRow, model: RepositoryModel) {
        hostingView.rootView = AnyView(
            GraphCommitRow(
                row: row,
                showsExpandedFiles: false
            )
            .environmentObject(model)
        )
    }

    private func installHostingView() {
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }
}
@MainActor
private final class GraphNestedTableCell: NSView {
    private weak var model: RepositoryModel?
    private var row: GraphRow?
    private var commit: CommitInfo?
    private var file: CommitFileChange?
    private var message: String?
    private var trackingAreaReference: NSTrackingArea?
    private var hovering = false
    private let laneWidth: CGFloat = 11
    var hoverChanged: ((GraphNestedTableCell, Bool) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    func configure(
        row: GraphRow,
        commit: CommitInfo?,
        file: CommitFileChange?,
        message: String?,
        model: RepositoryModel
    ) {
        // NSTableView recycles cells while scrolling. A recycled view may not
        // receive mouseExited before it is assigned to another file, so never
        // carry hover state across configurations.
        setHovering(false)
        self.row = row
        self.commit = commit
        self.file = file
        self.message = message
        self.model = model
        toolTip = file?.previousPath.map { "\($0) → \(file?.path ?? "")" }
            ?? file?.path
            ?? message
        setAccessibilityElement(true)
        setAccessibilityRole(file == nil ? .staticText : .button)
        setAccessibilityLabel(file?.path ?? message ?? "")
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaReference = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged?(self, true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged?(self, false)
    }

    func setHovering(_ hovering: Bool) {
        guard self.hovering != hovering else { return }
        self.hovering = hovering
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, let file, let commit, let model else { return }
        model.activate(file, in: commit)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let file, let commit, let model else { return false }
        model.activate(file, in: commit)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let row else { return }
        if hovering, file != nil {
            NSColor(AppTheme.hover).setFill()
            dirtyRect.fill()
        }

        for (index, lane) in row.outputLanes.enumerated() {
            lane.color.nsColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            let x = 9 + laneWidth * CGFloat(index + 1)
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: bounds.height))
            path.stroke()
        }
        let topologyWidth = laneWidth
            * CGFloat(max(row.inputLanes.count, row.outputLanes.count, 1) + 1)
        let textX = 9 + topologyWidth + 18

        if let file {
            let statusWidth: CGFloat = 18
            let statusRect = NSRect(
                x: bounds.maxX - 19 - statusWidth,
                y: 6,
                width: statusWidth,
                height: 17
            )
            drawText(
                file.status,
                in: statusRect,
                font: .monospacedSystemFont(ofSize: 12, weight: .semibold),
                color: statusColor(file.status),
                alignment: .right
            )
            let nameFont = NSFont.systemFont(ofSize: 13)
            let nameWidth = min(
                (file.name as NSString).size(withAttributes: [.font: nameFont]).width,
                max(0, bounds.width * 0.55)
            )
            drawText(
                file.name,
                in: NSRect(x: textX, y: 5, width: nameWidth, height: 18),
                font: nameFont,
                color: AppTheme.primaryNSColor,
                alignment: .left
            )
            if !file.parentPath.isEmpty {
                drawText(
                    file.parentPath,
                    in: NSRect(
                        x: textX + nameWidth + 8,
                        y: 6,
                        width: max(0, statusRect.minX - textX - nameWidth - 16),
                        height: 17
                    ),
                    font: .systemFont(ofSize: 12),
                    color: NSColor(AppTheme.secondary),
                    alignment: .left
                )
            }
        } else if let message {
            drawText(
                message,
                in: NSRect(
                    x: textX,
                    y: 5,
                    width: max(0, bounds.maxX - textX - 18),
                    height: 18
                ),
                font: .systemFont(ofSize: 12),
                color: AppTheme.mutedNSColor,
                alignment: .left
            )
        }
    }

    private func statusColor(_ status: String) -> NSColor {
        switch status {
        case "A": return NSColor(AppTheme.added)
        case "D": return NSColor(AppTheme.deleted)
        case "R", "C": return NSColor(AppTheme.graphBlue)
        default: return NSColor(AppTheme.modified)
        }
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

private struct GraphHeader: View {
    @EnvironmentObject private var model: RepositoryModel
    let revealHead: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("GRAPH")
                .font(AppType.panelTitle)
                .tracking(0.8)
                .foregroundStyle(AppTheme.secondary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            HStack(spacing: 12) {
                Menu {
                    ForEach(GraphScope.allCases) { scope in
                        Button {
                            Task { await model.setGraphScope(scope) }
                        } label: {
                            if model.graphScope == scope {
                                Label(
                                    graphScopeDescription(scope),
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(graphScopeDescription(scope))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        BranchGlyph(size: 14, color: AppTheme.primary)
                        Text(model.graphScope.title)
                    }
                    .font(AppType.rowDetail)
                    .frame(width: 72, height: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .contentShape(Rectangle())
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .tint(AppTheme.primary)
                .accessibilityLabel("Graph Scope")
                .accessibilityValue(graphScopeDescription(model.graphScope))
                .disabled(operationsDisabled)

                CodiconButton(icon: .target, help: "Reveal current HEAD", action: revealHead)
                    .disabled(!headIsVisible || operationsDisabled)

                CodiconButton(icon: .repoFetch, help: "Fetch all remotes") {
                    Task { await model.fetch() }
                }
                .disabled(operationsDisabled)

                Menu {
                    Button("Pull") {
                        Task { await model.pull() }
                    }

                    Button("Pull with Rebase") {
                        Task { await model.pullRebasing() }
                    }
                } label: {
                    CodiconGlyph(
                        icon: .repoPull,
                        size: 16,
                        color: AppTheme.primary
                    )
                        .frame(width: 25, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 25, height: 28)
                .contentShape(Rectangle())
                .tint(AppTheme.primary)
                .help("Pull")
                .accessibilityLabel("Pull Options")
                .disabled(
                    operationsDisabled || !model.hasUpstream
                )

                CodiconButton(
                    icon: .repoPush,
                    help: model.hasUpstream ? "Push" : "Publish Branch"
                ) {
                    Task { await model.pushOrPublish() }
                }
                .disabled(
                    operationsDisabled
                        || (!model.hasUpstream
                            && (model.branch == "detached HEAD" || model.headHash == nil))
                )

                Menu {
                    Button("Force Push with Lease…") {
                        Task { await model.forcePushWithLease() }
                    }

                    Button("Force Push Without Lease…") {
                        Task { await model.forcePush() }
                    }
                } label: {
                    Image(systemName: "cloud.bolt")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: 25, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 25, height: 28)
                .contentShape(Rectangle())
                .tint(AppTheme.primary)
                .help("Force Push")
                .accessibilityLabel("Force Push")
                .disabled(
                    operationsDisabled
                        || !model.hasUpstream
                        || model.branch == "detached HEAD"
                )

                repositoryMenu

            }
        }
        .foregroundStyle(AppTheme.primary)
        .padding(.leading, 22)
        .padding(.trailing, 21)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
    }

    private var headIsVisible: Bool {
        guard let headHash = model.headHash else { return false }
        return model.graph.contains(where: { $0.commit.hash == headHash })
    }

    private var operationsDisabled: Bool {
        model.isBusy
            || model.isGeneratingCommitMessage
            || model.hasPendingChangeOperations
    }

    private var repositoryMenu: some View {
        Menu {
            Menu("Remotes") {
                if model.remotes.isEmpty {
                    Text("No remotes")
                } else {
                    ForEach(model.remotes, id: \.name) { remote in
                        Menu(remote.name) {
                            Button("Edit URL…") {
                                guard let url = GitPrompt.remoteURL(for: remote) else { return }
                                Task { await model.editRemote(remote, url: url) }
                            }

                            Button("Remove Remote…", role: .destructive) {
                                Task { await model.removeRemote(remote) }
                            }
                        }
                    }
                }

                Divider()

                Button("Add Remote…") {
                    guard let remote = GitPrompt.newRemote() else { return }
                    Task { await model.addRemote(name: remote.name, url: remote.url) }
                }
            }

            Menu("Upstream") {
                if remoteBranchReferences.isEmpty {
                    Text("No remote branches")
                } else {
                    ForEach(remoteBranchReferences) { reference in
                        Button {
                            Task { await model.setUpstream(reference) }
                        } label: {
                            if reference.id == model.upstreamReference?.id {
                                Label(reference.name, systemImage: "checkmark")
                            } else {
                                Text(reference.name)
                            }
                        }
                    }
                }

                if model.hasUpstream {
                    Divider()

                    Button("Unset Upstream") {
                        Task { await model.unsetUpstream() }
                    }
                }
            }
            .disabled(model.branch == "detached HEAD" || model.headHash == nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 25, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 25, height: 28)
        .contentShape(Rectangle())
        .tint(AppTheme.primary)
        .help("Repository Settings")
        .accessibilityLabel("Repository Settings")
        .disabled(operationsDisabled)
    }

    private var remoteBranchReferences: [GitReference] {
        model.references
            .filter { $0.kind == .remoteBranch && !$0.name.hasSuffix("/HEAD") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func graphScopeDescription(_ scope: GraphScope) -> String {
        switch scope {
        case .all: return "All Branches"
        case .current: return "Current Branch"
        case .everything: return "Everything (All Git Refs)"
        case .reflog: return "Reflog Recovery"
        }
    }
}

private struct GraphCommitRow: View {
    @EnvironmentObject private var model: RepositoryModel
    let row: GraphRow
    let showsExpandedFiles: Bool
    @State private var hovering = false

    init(row: GraphRow, showsExpandedFiles: Bool = true) {
        self.row = row
        self.showsExpandedFiles = showsExpandedFiles
    }

    var body: some View {
        let presentedItems = GraphReferencePresentation.displayItems(
            row.commit.references,
            upstreamReferenceID: model.upstreamReference?.id
        )
        let presentedReferenceIDs = Set(presentedItems.flatMap {
            [$0.reference.id] + $0.syncedRemotes.map(\.id)
        })
        let visibleItems = Array(presentedItems.prefix(2))
        let hiddenReferences = presentedItems
            .dropFirst(visibleItems.count)
            .map(\.reference)
        VStack(spacing: 0) {
            Button {
                model.toggleCommitExpansion(row.commit)
            } label: {
                HStack(spacing: 8) {
                    GraphTopology(row: row)

                    Text(row.commit.displaySubject)
                        .font(isHead ? AppType.rowEmphasis : AppType.row)
                        .foregroundStyle(AppTheme.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(2)

                    ForEach(visibleItems) { item in
                        BranchPill(
                            reference: item.reference,
                            syncedRemotes: item.syncedRemotes,
                            commitIsHead: isHead,
                            referenceIDsAtCommit: presentedReferenceIDs
                        )
                    }

                    if !hiddenReferences.isEmpty {
                        Text("+\(hiddenReferences.count)")
                            .font(AppType.captionEmphasis)
                            .foregroundStyle(AppTheme.secondary)
                            .fixedSize()
                            .help(hiddenReferences.map(referenceDescription).joined(separator: "\n"))
                            .contextMenu {
                                ForEach(Array(hiddenReferences)) { reference in
                                    Menu(reference.name) {
                                        ReferenceContextMenuItems(
                                            reference: reference,
                                            commitIsHead: isHead,
                                            referenceIDsAtCommit: presentedReferenceIDs
                                        )
                                    }
                                }
                            }
                    }

                }
                .padding(.leading, 9)
                .padding(.trailing, 18)
                .frame(height: 32)
                .contentShape(Rectangle())
                .background(hovering ? AppTheme.hover : .clear)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(commitHelp)
            .accessibilityLabel(
                "\(row.commit.displaySubject), \(row.commit.shortHash), by \(row.commit.author), \(row.commit.relativeDate)"
            )
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .contextMenu {
                if row.commit.isStash {
                    stashContextMenu
                } else {
                    commitContextMenu
                }
            }

            if showsExpandedFiles && isExpanded {
                if model.loadingCommitFileHashes.contains(row.commit.hash) {
                    GraphCommitLoadingRow(row: row)
                } else if model.files(for: row.commit).isEmpty {
                    GraphCommitEmptyRow(row: row)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.files(for: row.commit)) { file in
                            GraphCommitFileRow(
                                row: row,
                                commit: row.commit,
                                file: file
                            )
                        }
                    }
                }
            }
        }
    }

    private var isHead: Bool {
        row.kind == .head
    }

    private var isExpanded: Bool {
        model.expandedCommitHashes.contains(row.commit.hash)
    }

    private var displayReferences: [GitReference] {
        GraphReferencePresentation.displayReferences(
            row.commit.references,
            upstreamReferenceID: model.upstreamReference?.id
        )
    }

    private var checkoutReferences: [GitReference] {
        guard !isHead else { return [] }
        return displayReferences.filter { $0.kind != .other && !$0.isHead }
    }

    private var comparisonReferences: [GitReference] {
        let selectedReferenceIDs = Set(displayReferences.map(\.id))
        return model.references.filter {
            !$0.name.hasSuffix("/HEAD")
                && $0.id != model.upstreamReference?.id
                && !selectedReferenceIDs.contains($0.id)
        }
    }

    private var hasGitHubOrigin: Bool {
        model.remotes.contains { $0.name == "origin" && $0.isGitHub }
    }

    private var githubPullRequestReferences: [GitReference] {
        displayReferences
            .filter { reference in
                guard let remoteBranch = reference.remoteBranchComponents,
                      remoteBranch.branch != "HEAD" else { return false }
                return model.remotes.contains {
                    $0.name == remoteBranch.remote && $0.isGitHub
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var operationsDisabled: Bool {
        model.isBusy
            || model.isGeneratingCommitMessage
            || model.hasPendingChangeOperations
    }

    @ViewBuilder
    private var stashContextMenu: some View {
        Button("Open Changes") {
            model.openCommitChanges(row.commit)
        }

        Divider()

        Button("Apply Stash") {
            Task { await model.applyStash(row.commit) }
        }
        .disabled(operationsDisabled)

        Button("Pop Stash") {
            Task { await model.popStash(row.commit) }
        }
        .disabled(operationsDisabled)

        Button("Drop Stash…") {
            guard GitPrompt.confirmDelete(
                kind: "stash",
                name: row.commit.subject
            ) else { return }
            Task { await model.dropStash(row.commit) }
        }
        .disabled(operationsDisabled)

        Divider()

        Button("Copy Commit Hash") {
            copyToPasteboard(row.commit.hash)
        }

        Button("Copy Commit Message") {
            Task { await model.copyCommitMessage(row.commit) }
        }
    }

    @ViewBuilder
    private var commitContextMenu: some View {
        Button("Show Changes") {
            model.openCommitChanges(row.commit)
        }

        if hasGitHubOrigin {
            Button("View Commit on GitHub") {
                Task {
                    if let url = await model.githubURL(for: row.commit) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        if githubPullRequestReferences.count == 1,
           let reference = githubPullRequestReferences.first {
            Button("Create PR on GitHub") {
                openGitHubPullRequest(for: reference)
            }
        } else if !githubPullRequestReferences.isEmpty {
            Menu("Create PR on GitHub") {
                ForEach(githubPullRequestReferences) { reference in
                    Button(reference.name) {
                        openGitHubPullRequest(for: reference)
                    }
                }
            }
        }

        Divider()

        if checkoutReferences.count == 1, let reference = checkoutReferences.first {
            Button(checkoutTitle(for: reference)) {
                Task { await model.checkout(reference) }
            }
            .disabled(operationsDisabled)
        } else if !checkoutReferences.isEmpty {
            Menu("Checkout") {
                referenceMenuItems(
                    checkoutReferences,
                    action: { reference in
                        Task { await model.checkout(reference) }
                    }
                )
            }
            .disabled(operationsDisabled)
        }

        if !isHead {
            Button("Checkout Commit (Detached HEAD)") {
                Task { await model.checkoutDetached(row.commit) }
            }
            .disabled(operationsDisabled)
        }

        Divider()

        Button("Create Branch from Commit…") {
            guard let name = GitPrompt.branchName(at: row.commit) else { return }
            Task { await model.createBranch(named: name, at: row.commit) }
        }
        .disabled(operationsDisabled)

        Button("Create Tag from Commit…") {
            guard let tag = GitPrompt.tag(at: row.commit) else { return }
            Task {
                await model.createTag(
                    named: tag.name,
                    message: tag.message,
                    at: row.commit
                )
            }
        }
        .disabled(operationsDisabled)

        Divider()

        if !isHead {
            Button("Cherry-Pick Commit") {
                Task { await model.cherryPick(row.commit) }
            }
            .disabled(operationsDisabled)
        }

        if row.commit.parentHashes.count <= 1 {
            Button("Revert Commit…") {
                Task { await model.revert(row.commit) }
            }
            .disabled(operationsDisabled)
        }

        if !isHead, !model.branch.isEmpty, model.branch != "detached HEAD" {
            Menu("Reset “\(model.branch)” to This Commit") {
                Button("Soft Reset (Keep Changes Staged)…") {
                    Task { await model.reset(to: row.commit, mode: .soft) }
                }

                Button("Mixed Reset (Keep Changes Unstaged)…") {
                    Task { await model.reset(to: row.commit, mode: .mixed) }
                }

                Divider()

                Button("Hard Reset (Discard Changes)…") {
                    Task { await model.reset(to: row.commit, mode: .hard) }
                }
            }
            .disabled(operationsDisabled)
        }

        if model.upstreamReference != nil || !comparisonReferences.isEmpty {
            Divider()

            Menu("Compare") {
                if let upstream = model.upstreamReference {
                    Button("With \(upstream.name)") {
                        model.compareWithUpstream(row.commit)
                    }

                    Button("Changes Since Divergence from \(upstream.name)") {
                        model.compareWithUpstream(
                            row.commit,
                            fromMergeBase: true
                        )
                    }
                }

                if !comparisonReferences.isEmpty {
                    if model.upstreamReference != nil {
                        Divider()
                    }

                    Menu("With Branch or Tag") {
                        referenceMenuItems(
                            comparisonReferences,
                            action: { reference in
                                model.compare(row.commit, against: reference)
                            }
                        )
                    }
                }
            }
            .disabled(operationsDisabled)
        }

        Divider()

        Button("Copy Commit Hash") {
            copyToPasteboard(row.commit.hash)
        }

        Button("Copy Commit Message") {
            Task { await model.copyCommitMessage(row.commit) }
        }
    }

    private func checkoutTitle(for reference: GitReference) -> String {
        switch reference.kind {
        case .tag:
            return "Checkout Tag “\(reference.name)”"
        case .localBranch, .remoteBranch, .other:
            return "Checkout “\(reference.name)”"
        }
    }

    @ViewBuilder
    private func referenceMenuItems(
        _ references: [GitReference],
        action: @escaping (GitReference) -> Void
    ) -> some View {
        let localBranches = references.filter { $0.kind == .localBranch }
        let remoteBranches = references.filter { $0.kind == .remoteBranch }
        let tags = references.filter { $0.kind == .tag }

        if !localBranches.isEmpty {
            Section("Branches") {
                ForEach(localBranches) { reference in
                    Button(reference.name) {
                        action(reference)
                    }
                }
            }
        }

        if !remoteBranches.isEmpty {
            Section("Remote Branches") {
                ForEach(remoteBranches) { reference in
                    Button(reference.name) {
                        action(reference)
                    }
                }
            }
        }

        if !tags.isEmpty {
            Section("Tags") {
                ForEach(tags) { reference in
                    Button(reference.name) {
                        action(reference)
                    }
                }
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func openGitHubPullRequest(for reference: GitReference) {
        Task {
            if let url = await model.githubPullRequestURL(for: reference) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var commitHelp: String {
        var lines = [
            row.commit.displaySubject,
            "\(row.commit.shortHash) · \(row.commit.author) · \(row.commit.relativeDate)"
        ]
        if let selector = row.commit.reflogSelector {
            lines.insert("\(selector) · \(row.commit.subject)", at: 1)
        }
        if !displayReferences.isEmpty {
            lines.append(displayReferences.map(referenceDescription).joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    private func referenceDescription(_ reference: GitReference) -> String {
        switch reference.kind {
        case .localBranch:
            return "Local branch: \(reference.name)"
        case .remoteBranch:
            return "Remote branch: \(reference.name)"
        case .tag:
            return "Tag: \(reference.name)"
        case .other:
            return reference.name
        }
    }
}

enum GraphReferencePresentation {
    struct DisplayItem: Identifiable, Hashable {
        let reference: GitReference
        /// Remote branches on the same commit that track this local branch
        /// (`origin/main` on `main`). Folded into the local pill so a synced
        /// branch shows one badge and the commit message keeps its width.
        let syncedRemotes: [GitReference]

        var id: String { reference.id }
    }

    static func displayItems(
        _ references: [GitReference],
        upstreamReferenceID: String?
    ) -> [DisplayItem] {
        let ordered = displayReferences(
            references,
            upstreamReferenceID: upstreamReferenceID
        )
        let localNames = Set(
            ordered.filter { $0.kind == .localBranch }.map(\.name)
        )
        var syncedRemotesByLocalName: [String: [GitReference]] = [:]
        var items: [DisplayItem] = []

        for reference in ordered where reference.kind == .remoteBranch {
            guard let localName = trackedLocalName(of: reference),
                  localNames.contains(localName) else { continue }
            syncedRemotesByLocalName[localName, default: []].append(reference)
        }

        for reference in ordered {
            if reference.kind == .remoteBranch,
               let localName = trackedLocalName(of: reference),
               localNames.contains(localName) {
                continue
            }
            items.append(DisplayItem(
                reference: reference,
                syncedRemotes: reference.kind == .localBranch
                    ? syncedRemotesByLocalName[reference.name] ?? []
                    : []
            ))
        }
        return items
    }

    /// `origin/main` tracks `main`: the branch name after the remote's own
    /// name. Nil when the name has no remote prefix to strip.
    private static func trackedLocalName(of reference: GitReference) -> String? {
        let components = reference.name.split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard components.count == 2, !components[1].isEmpty else { return nil }
        return String(components[1])
    }

    static func displayReferences(
        _ references: [GitReference],
        upstreamReferenceID: String?
    ) -> [GitReference] {
        var seenNames = Set<String>()
        return references
            .filter { reference in
                !(reference.kind == .remoteBranch && reference.name.hasSuffix("/HEAD"))
            }
            .sorted { lhs, rhs in
                let lhsPriority = priority(
                    of: lhs,
                    upstreamReferenceID: upstreamReferenceID
                )
                let rhsPriority = priority(
                    of: rhs,
                    upstreamReferenceID: upstreamReferenceID
                )
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.name != rhs.name {
                    return lhs.name < rhs.name
                }
                return lhs.id < rhs.id
            }
            .filter { seenNames.insert($0.name).inserted }
    }

    private static func priority(
        of reference: GitReference,
        upstreamReferenceID: String?
    ) -> Int {
        if reference.isHead { return 0 }
        if reference.id == upstreamReferenceID { return 1 }
        switch reference.kind {
        case .localBranch: return 2
        case .remoteBranch: return 3
        case .tag: return 4
        case .other: return 5
        }
    }
}

private struct GraphCommitLoadingRow: View {
    let row: GraphRow

    var body: some View {
        HStack(spacing: 8) {
            GraphExpansionTopology(row: row)

            Color.clear
                .frame(width: 10)

            ProgressView()
                .controlSize(.small)

            Text("Loading changed files…")
                .font(AppType.nestedRowDetail)
                .foregroundStyle(AppTheme.secondary)

            Spacer()
        }
        .padding(.leading, 9)
        .padding(.trailing, 18)
        .frame(height: 28)
    }
}

private struct GraphCommitEmptyRow: View {
    let row: GraphRow

    var body: some View {
        HStack(spacing: 8) {
            GraphExpansionTopology(row: row)

            Color.clear
                .frame(width: 10)

            Text("No changed files")
                .font(AppType.nestedRowDetail)
                .foregroundStyle(AppTheme.muted)

            Spacer()
        }
        .padding(.leading, 9)
        .padding(.trailing, 18)
        .frame(height: 28)
    }
}

private struct GraphCommitFileRow: View {
    @EnvironmentObject private var model: RepositoryModel
    let row: GraphRow
    let commit: CommitInfo
    let file: CommitFileChange

    var body: some View {
        GraphNestedFileRow(
            row: row,
            file: file,
            hoverID: "\(commit.hash):\(file.id)",
            isSelected: model.selectedCommit?.hash == commit.hash
                && model.selectedCommitFile?.id == file.id
        ) {
            model.activate(file, in: commit)
        }
    }
}

/// Shared layout for the file rows nested under an expanded commit.
private struct GraphNestedFileRow: View {
    @EnvironmentObject private var model: RepositoryModel
    @EnvironmentObject private var hoverState: GraphNestedFileHoverState
    let row: GraphRow
    let file: CommitFileChange
    let hoverID: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                GraphExpansionTopology(row: row)

                Color.clear
                    .frame(width: 10)

                FileIconView(path: file.path, size: 12, width: 18)

                Text(file.name)
                    .font(AppType.nestedRow)
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(1)
                    .layoutPriority(1)

                if !file.parentPath.isEmpty {
                    Text(file.parentPath)
                        .font(AppType.nestedRowDetail)
                        .foregroundStyle(AppTheme.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                Text(file.status)
                    .font(AppType.nestedStatusLetter)
                    .foregroundStyle(statusColor)
                    .frame(width: 16, alignment: .trailing)
                    .accessibilityLabel(statusDescription)
                    .help(statusDescription)
            }
            .padding(.leading, 9)
            .padding(.trailing, 19)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? AppTheme.selection
                    : (hoverState.hoveredID == hoverID ? AppTheme.hover : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoverState.hoveredID = hoverID
            } else if hoverState.hoveredID == hoverID {
                hoverState.hoveredID = nil
            }
        }
        .help(file.previousPath.map { "\($0) → \(file.path)" } ?? file.path)
        .contextMenu {
            Button("Copy Path") {
                copyRepositoryFilePath(file.path, repositoryURL: model.repositoryURL)
            }
        }
    }

    private var fileIcon: String {
        FileGlyph.symbol(forPath: file.path)
    }

    private var statusColor: Color {
        switch file.status {
        case "A": return AppTheme.added
        case "D": return AppTheme.deleted
        case "R", "C": return AppTheme.graphBlue
        default: return AppTheme.modified
        }
    }

    private var statusDescription: String {
        switch file.status {
        case "A": return "Added"
        case "D": return "Deleted"
        case "R": return "Renamed"
        case "C": return "Copied"
        default: return "Modified"
        }
    }
}

private func copyRepositoryFilePath(_ relativePath: String, repositoryURL: URL?) {
    guard let repositoryURL else { return }

    let path = URL(
        fileURLWithPath: relativePath,
        relativeTo: repositoryURL
    )
    .standardizedFileURL
    .path

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
}

private func revealRepositoryFileInFinder(_ relativePath: String, repositoryURL: URL?) {
    guard let repositoryURL else { return }

    let url = URL(
        fileURLWithPath: relativePath,
        relativeTo: repositoryURL
    )
    .standardizedFileURL

    NSWorkspace.shared.activateFileViewerSelecting([url])
}

private struct GraphExpansionTopology: View {
    let row: GraphRow

    private let laneWidth: CGFloat = 11
    private let rowHeight: CGFloat = 28

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
            for (index, lane) in row.outputLanes.enumerated() {
                let x = laneWidth * CGFloat(index + 1)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: rowHeight))
                context.stroke(
                    path,
                    with: .color(lane.color.swiftUIColor),
                    lineWidth: 1.2
                )
            }
        }
        .frame(width: graphWidth, height: rowHeight)
        .accessibilityHidden(true)
    }

    private var graphWidth: CGFloat {
        laneWidth * CGFloat(
            max(row.inputLanes.count, row.outputLanes.count, 1) + 1
        )
    }
}

@MainActor
private enum GitPrompt {
    static func stash() -> (message: String?, includeUntracked: Bool)? {
        let result = AppDialog.run(
            title: "Stash Changes",
            message: "Temporarily store staged and unstaged changes. Choose Include Untracked to stash new files too.",
            fields: [
                AppDialogField(
                    label: "Message",
                    placeholder: "Optional",
                    isRequired: false
                )
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Tracked Changes", role: .secondary),
                AppDialogAction(title: "Include Untracked", role: .primary)
            ]
        )
        guard let actionIndex = result.actionIndex, actionIndex == 1 || actionIndex == 2 else {
            return nil
        }
        let message = result.values[0]
        return (
            message: message.isEmpty ? nil : message,
            includeUntracked: actionIndex == 2
        )
    }

    static func confirmDiscardAllChanges() -> Bool {
        let result = AppDialog.run(
            title: "Discard All Changes?",
            message: "Permanently discard every staged and unstaged change, including untracked files and folders. Ignored files are kept. This cannot be undone by Kvist.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Discard All", role: .destructive)
            ]
        )
        return result.actionIndex == 1
    }

    static func confirmDiscardAllUnstagedChanges() -> Bool {
        let result = AppDialog.run(
            title: "Discard All Unstaged Changes?",
            message: "Permanently discard every unstaged change, including untracked files and folders. Staged and ignored files are kept. This cannot be undone by Kvist.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Discard Unstaged", role: .destructive)
            ]
        )
        return result.actionIndex == 1
    }

    static func branchName(at commit: CommitInfo) -> String? {
        text(
            title: "Create Branch",
            message: "Create and check out a branch at \(commit.shortHash).",
            placeholder: "Branch name"
        )
    }

    static func branchName(from branch: String) -> String? {
        let source = branch.isEmpty || branch == "detached HEAD"
            ? "the current HEAD"
            : "“\(branch)”"
        return text(
            title: "Create Branch",
            message: "Create and check out a branch from \(source).",
            placeholder: "Branch name"
        )
    }

    static func renamedBranch(_ reference: GitReference) -> String? {
        let result = AppDialog.run(
            title: "Rename Branch",
            message: "Rename “\(reference.name)”. Remote branches are not renamed automatically.",
            fields: [
                AppDialogField(label: "New branch name", placeholder: reference.name)
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Rename", role: .primary)
            ]
        )
        guard result.actionIndex == 1,
              let value = result.values.first,
              !value.isEmpty,
              value != reference.name else { return nil }
        return value
    }

    static func cloneRemoteURL() -> String? {
        let result = AppDialog.run(
            title: "Clone Repository",
            message: "Enter an HTTPS URL, SSH URL, or local Git repository path.",
            fields: [
                AppDialogField(
                    label: "Repository URL",
                    placeholder: "https://github.com/owner/repository.git"
                )
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Choose Destination", role: .primary)
            ]
        )
        guard result.actionIndex == 1,
              let value = result.values.first,
              !value.isEmpty else { return nil }
        return value
    }

    static func sshRepository() -> (host: String, path: String)? {
        let result = AppDialog.run(
            title: "Open Repository over SSH",
            message: "Kvist uses your existing SSH config and keys to run Git on the remote machine. Leave the path empty to browse the remote machine's folders.",
            fields: [
                AppDialogField(label: "SSH host", placeholder: "user@example.com"),
                AppDialogField(
                    label: "Repository path",
                    placeholder: "Optional — leave empty to browse",
                    isRequired: false
                )
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Connect", role: .primary)
            ]
        )
        guard result.actionIndex == 1, result.values.count == 2 else { return nil }
        return (result.values[0], result.values[1])
    }

    static func cloneDestinationFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Clone Destination"
        panel.message = "Choose the folder where the cloned repository should be created."
        panel.prompt = "Choose Destination Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func newRemote() -> (name: String, url: String)? {
        let result = AppDialog.run(
            title: "Add Remote",
            message: "Add a named remote repository.",
            fields: [
                AppDialogField(label: "Name", placeholder: "origin"),
                AppDialogField(
                    label: "Repository URL",
                    placeholder: "https://github.com/owner/repository.git"
                )
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Add Remote", role: .primary)
            ]
        )
        guard result.actionIndex == 1,
              result.values.count == 2,
              !result.values[0].isEmpty,
              !result.values[1].isEmpty else { return nil }
        return (result.values[0], result.values[1])
    }

    static func remoteURL(for remote: GitRemote) -> String? {
        let result = AppDialog.run(
            title: "Edit Remote",
            message: "Replace the fetch URL for “\(remote.name)”.\nCurrent URL: \(remote.fetchURL)",
            fields: [
                AppDialogField(label: "Repository URL", placeholder: remote.fetchURL)
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Save", role: .primary)
            ]
        )
        guard result.actionIndex == 1,
              let value = result.values.first,
              !value.isEmpty else { return nil }
        return value
    }

    static func tag(at commit: CommitInfo) -> (name: String, message: String?)? {
        let result = AppDialog.run(
            title: "Create Tag",
            message: "Create a tag at \(commit.shortHash). Add an annotation if this is a notable point in history.",
            fields: [
                AppDialogField(label: "Tag name", placeholder: "v1.0.0"),
                AppDialogField(
                    label: "Annotation",
                    placeholder: "Optional",
                    isRequired: false
                )
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Create Tag", role: .primary)
            ]
        )
        guard result.actionIndex == 1 else { return nil }
        let name = result.values[0]
        guard !name.isEmpty else { return nil }
        let message = result.values[1]
        return (name, message.isEmpty ? nil : message)
    }

    static func confirmDelete(kind: String, name: String) -> Bool {
        let result = AppDialog.run(
            title: "Delete \(kind.capitalized)?",
            message: "Delete “\(name)” from this repository. This action cannot be undone by Kvist.",
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Delete", role: .destructive)
            ]
        )
        return result.actionIndex == 1
    }

    private static func text(
        title: String,
        message: String,
        placeholder: String
    ) -> String? {
        let result = AppDialog.run(
            title: title,
            message: message,
            fields: [
                AppDialogField(label: placeholder, placeholder: placeholder)
            ],
            actions: [
                AppDialogAction(title: "Cancel", role: .cancel),
                AppDialogAction(title: "Create", role: .primary)
            ]
        )
        guard result.actionIndex == 1 else { return nil }
        let value = result.values[0]
        return value.isEmpty ? nil : value
    }
}

enum GraphTopologyMetrics {
    static func nodeIndex(for row: GraphRow) -> Int {
        row.inputLanes.firstIndex(where: { $0.id == row.commit.hash })
            ?? row.inputLanes.count
    }

    static func width(for row: GraphRow, laneWidth: CGFloat) -> CGFloat {
        let nodeLaneCount = nodeIndex(for: row) + 1
        let visibleLaneCount = [
            row.inputLanes.count,
            row.outputLanes.count,
            nodeLaneCount,
            1
        ].max() ?? 1
        return laneWidth * CGFloat(visibleLaneCount + 1)
    }
}

private struct GraphTopology: View {
    let row: GraphRow

    private let laneWidth: CGFloat = 11
    private let rowHeight: CGFloat = 32
    private let curveRadius: CGFloat = 5

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
            drawGraph(context: &context)
        }
        .frame(width: graphWidth, height: rowHeight)
        .accessibilityHidden(true)
    }

    private var graphWidth: CGFloat {
        GraphTopologyMetrics.width(for: row, laneWidth: laneWidth)
    }

    private func drawGraph(context: inout GraphicsContext) {
        let inputIndex = row.inputLanes.firstIndex(where: { $0.id == row.commit.hash })
        let circleIndex = GraphTopologyMetrics.nodeIndex(for: row)
        let circleX = x(for: circleIndex)
        let middleY = rowHeight / 2
        let circleColor = laneColor(at: circleIndex)
        let nodeColor = circleColor

        var outputIndex = 0
        for index in row.inputLanes.indices {
            let lane = row.inputLanes[index]
            let color = lane.color.swiftUIColor

            if lane.id == row.commit.hash {
                if index != circleIndex {
                    var path = Path()
                    path.move(to: CGPoint(x: x(for: index), y: 0))
                    appendConnection(
                        to: &path,
                        fromX: x(for: index),
                        toX: circleX,
                        middleY: middleY,
                        continueToBottom: false
                    )
                    stroke(path, color: color, context: &context)
                } else if !row.commit.parentHashes.isEmpty {
                    outputIndex += 1
                }
            } else if outputIndex < row.outputLanes.count,
                      lane.id == row.outputLanes[outputIndex].id {
                if index == outputIndex {
                    var path = Path()
                    path.move(to: CGPoint(x: x(for: index), y: 0))
                    path.addLine(to: CGPoint(x: x(for: index), y: rowHeight))
                    stroke(path, color: color, context: &context)
                } else {
                    var path = Path()
                    path.move(to: CGPoint(x: x(for: index), y: 0))
                    appendConnection(
                        to: &path,
                        fromX: x(for: index),
                        toX: x(for: outputIndex),
                        middleY: middleY,
                        continueToBottom: true
                    )
                    stroke(path, color: color, context: &context)
                }
                outputIndex += 1
            }
        }

        for parentHash in row.commit.parentHashes.dropFirst() {
            guard let parentIndex = row.outputLanes.lastIndex(where: { $0.id == parentHash }) else {
                continue
            }
            let parentX = x(for: parentIndex)
            let direction: CGFloat = parentX >= circleX ? 1 : -1
            var path = Path()
            path.move(to: CGPoint(x: circleX, y: middleY))
            path.addLine(to: CGPoint(
                x: parentX - (direction * curveRadius),
                y: middleY
            ))
            path.addCurve(
                to: CGPoint(x: parentX, y: middleY + curveRadius),
                control1: CGPoint(x: parentX, y: middleY),
                control2: CGPoint(x: parentX, y: middleY)
            )
            path.addLine(to: CGPoint(x: parentX, y: rowHeight))
            stroke(
                path,
                color: row.outputLanes[parentIndex].color.swiftUIColor,
                context: &context
            )
        }

        if let inputIndex {
            var incoming = Path()
            incoming.move(to: CGPoint(x: circleX, y: 0))
            incoming.addLine(to: CGPoint(x: circleX, y: middleY))
            stroke(
                incoming,
                color: row.inputLanes[inputIndex].color.swiftUIColor,
                context: &context
            )
        }

        if !row.commit.parentHashes.isEmpty {
            var outgoing = Path()
            outgoing.move(to: CGPoint(x: circleX, y: middleY))
            outgoing.addLine(to: CGPoint(x: circleX, y: rowHeight))
            stroke(outgoing, color: circleColor, context: &context)
        }

        drawNode(
            at: CGPoint(x: circleX, y: middleY),
            color: nodeColor,
            context: &context
        )
    }

    private func appendConnection(
        to path: inout Path,
        fromX: CGFloat,
        toX: CGFloat,
        middleY: CGFloat,
        continueToBottom: Bool
    ) {
        guard fromX != toX else {
            path.addLine(to: CGPoint(x: fromX, y: continueToBottom ? rowHeight : middleY))
            return
        }

        let direction: CGFloat = toX > fromX ? 1 : -1
        path.addLine(to: CGPoint(x: fromX, y: middleY - curveRadius))
        path.addCurve(
            to: CGPoint(x: fromX + (direction * curveRadius), y: middleY),
            control1: CGPoint(x: fromX, y: middleY),
            control2: CGPoint(x: fromX, y: middleY)
        )
        path.addLine(to: CGPoint(x: toX - (direction * curveRadius), y: middleY))

        if continueToBottom {
            path.addCurve(
                to: CGPoint(x: toX, y: middleY + curveRadius),
                control1: CGPoint(x: toX, y: middleY),
                control2: CGPoint(x: toX, y: middleY)
            )
            path.addLine(to: CGPoint(x: toX, y: rowHeight))
        } else {
            path.addLine(to: CGPoint(x: toX, y: middleY))
        }
    }

    private func drawNode(
        at point: CGPoint,
        color: Color,
        context: inout GraphicsContext
    ) {
        if row.kind == .head {
            let outer = Path(ellipseIn: CGRect(
                x: point.x - 7,
                y: point.y - 7,
                width: 14,
                height: 14
            ))
            context.fill(outer, with: .color(AppTheme.canvas))
            context.stroke(outer, with: .color(color), lineWidth: 2)

            let inner = Path(ellipseIn: CGRect(
                x: point.x - 2,
                y: point.y - 2,
                width: 4,
                height: 4
            ))
            context.fill(inner, with: .color(color))
        } else if row.commit.parentHashes.count > 1 {
            let outer = Path(ellipseIn: CGRect(
                x: point.x - 6,
                y: point.y - 6,
                width: 12,
                height: 12
            ))
            context.fill(outer, with: .color(AppTheme.canvas))
            context.stroke(outer, with: .color(color), lineWidth: 2)

            let inner = Path(ellipseIn: CGRect(
                x: point.x - 3,
                y: point.y - 3,
                width: 6,
                height: 6
            ))
            context.stroke(inner, with: .color(color), lineWidth: 2)
        } else {
            let circle = Path(ellipseIn: CGRect(
                x: point.x - 5,
                y: point.y - 5,
                width: 10,
                height: 10
            ))
            context.fill(circle, with: .color(color))
        }
    }

    private func stroke(
        _ path: Path,
        color: Color,
        context: inout GraphicsContext
    ) {
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
        )
    }

    private func x(for index: Int) -> CGFloat {
        laneWidth * CGFloat(index + 1)
    }

    private func laneColor(at index: Int) -> Color {
        if index < row.outputLanes.count {
            return row.outputLanes[index].color.swiftUIColor
        }
        if index < row.inputLanes.count {
            return row.inputLanes[index].color.swiftUIColor
        }
        return AppTheme.graphBlue
    }
}

private struct ReferenceContextMenuItems: View {
    @EnvironmentObject private var model: RepositoryModel
    let reference: GitReference
    let commitIsHead: Bool
    let referenceIDsAtCommit: Set<String>

    @ViewBuilder
    var body: some View {
        switch reference.kind {
        case .localBranch:
            if !reference.isHead {
                checkoutButton
            }

            if canMergeIntoCurrent || !rebaseTargets.isEmpty {
                if !reference.isHead {
                    Divider()
                }

                if canMergeIntoCurrent {
                    mergeIntoCurrentButton
                }

                rebaseAction

                Divider()
            }

            if let githubPullRequestReference {
                createGitHubPullRequestButton(for: githubPullRequestReference)

                Divider()
            }

            Button("Rename “\(reference.name)”…") {
                guard let name = GitPrompt.renamedBranch(reference) else { return }
                Task { await model.renameBranch(reference, to: name) }
            }
            .disabled(operationsDisabled)

            if !reference.isHead {
                Divider()

                Button("Delete Branch “\(reference.name)”…", role: .destructive) {
                    Task { await model.deleteBranchWithConfirmation(reference) }
                }
                .disabled(operationsDisabled)
            }

        case .remoteBranch:
            if !commitIsHead {
                checkoutButton
            }

            if githubPullRequestReference != nil {
                Divider()

                createGitHubPullRequestButton(for: reference)
            }

            if canMergeIntoCurrent {
                Divider()

                mergeIntoCurrentButton
            }

            if !commitIsHead || canMergeIntoCurrent {
                Divider()
            }

            Button("Delete Remote Branch “\(reference.name)”…", role: .destructive) {
                Task { await model.deleteBranchWithConfirmation(reference) }
            }
            .disabled(operationsDisabled)

        case .tag:
            if !commitIsHead {
                checkoutButton
            }

            if !model.remotes.isEmpty {
                Menu("Push Tag to Remote") {
                    ForEach(model.remotes, id: \.name) { remote in
                        Button(remote.name) {
                            Task { await model.pushTag(reference, to: remote) }
                        }
                    }
                }
                .disabled(operationsDisabled)

                Menu("Delete Tag from Remote") {
                    ForEach(model.remotes, id: \.name) { remote in
                        Button(remote.name, role: .destructive) {
                            Task { await model.deleteRemoteTag(reference, from: remote) }
                        }
                    }
                }
                .disabled(operationsDisabled)
            }

            if !commitIsHead || !model.remotes.isEmpty {
                Divider()
            }

            Button("Delete Tag “\(reference.name)”…", role: .destructive) {
                guard GitPrompt.confirmDelete(
                    kind: "tag",
                    name: reference.name
                ) else { return }
                Task { await model.deleteTag(reference) }
            }
            .disabled(operationsDisabled)

        case .other:
            Button("Copy Reference Name") {
                copyReferenceName()
            }
        }
    }

    @ViewBuilder
    private var mergeIntoCurrentButton: some View {
        if model.canFastForward(to: reference) {
            Button("Fast-Forward “\(model.branch)” to “\(reference.name)”") {
                Task {
                    await model.integrate(
                        reference,
                        strategy: .fastForward
                    )
                }
            }
            .disabled(operationsDisabled)
        } else {
            Button("Merge “\(reference.name)” into “\(model.branch)”") {
                Task {
                    await model.integrate(
                        reference,
                        strategy: .merge
                    )
                }
            }
            .disabled(operationsDisabled)
        }
    }

    @ViewBuilder
    private var rebaseAction: some View {
        if rebaseTargets.count == 1, let target = rebaseTargets.first {
            rebaseButton(onto: target, includesBranchName: true)
        } else if !rebaseTargets.isEmpty {
            Menu("Rebase “\(reference.name)” onto") {
                if !localRebaseTargets.isEmpty {
                    Section("Branches") {
                        ForEach(localRebaseTargets) { target in
                            rebaseButton(onto: target)
                        }
                    }
                }

                if !remoteRebaseTargets.isEmpty {
                    Section("Remote Branches") {
                        ForEach(remoteRebaseTargets) { target in
                            rebaseButton(onto: target)
                        }
                    }
                }
            }
            .disabled(operationsDisabled)
        }
    }

    private func rebaseButton(
        onto target: GitReference,
        includesBranchName: Bool = false
    ) -> some View {
        Button(
            includesBranchName
                ? "Rebase “\(reference.name)” onto “\(target.name)”"
                : target.name
        ) {
            Task { await model.rebase(reference, onto: target) }
        }
        .disabled(operationsDisabled)
    }

    private var checkoutButton: some View {
        Button(checkoutTitle) {
            Task { await model.checkout(reference) }
        }
        .disabled(operationsDisabled)
    }

    private var checkoutTitle: String {
        reference.kind == .tag
            ? "Checkout Tag “\(reference.name)”"
            : "Checkout “\(reference.name)”"
    }

    @ViewBuilder
    private func createGitHubPullRequestButton(for remoteBranch: GitReference) -> some View {
        Button("Create PR on GitHub") {
            Task {
                if let url = await model.githubPullRequestURL(for: remoteBranch) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var githubPullRequestReference: GitReference? {
        switch reference.kind {
        case .remoteBranch:
            guard let remoteBranch = reference.remoteBranchComponents,
                  remoteBranch.branch != "HEAD",
                  model.remotes.contains(where: {
                      $0.name == remoteBranch.remote && $0.isGitHub
                  }) else { return nil }
            return reference

        case .localBranch:
            let candidates = model.references.filter { candidate in
                guard referenceIDsAtCommit.contains(candidate.id),
                      let remoteBranch = candidate.remoteBranchComponents,
                      remoteBranch.branch == reference.name else { return false }
                return model.remotes.contains {
                    $0.name == remoteBranch.remote && $0.isGitHub
                }
            }
            return candidates.sorted { lhs, rhs in
                let lhsOrigin = lhs.name.hasPrefix("origin/")
                let rhsOrigin = rhs.name.hasPrefix("origin/")
                if lhsOrigin != rhsOrigin { return lhsOrigin }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }.first

        case .tag, .other:
            return nil
        }
    }

    private var canMergeIntoCurrent: Bool {
        !reference.isHead
            && !commitIsHead
            && model.branch != "detached HEAD"
    }

    private var rebaseTargets: [GitReference] {
        guard reference.kind == .localBranch else { return [] }
        return model.references
            .filter {
                ($0.kind == .localBranch || $0.kind == .remoteBranch)
                    && !referenceIDsAtCommit.contains($0.id)
                    && !$0.name.hasSuffix("/HEAD")
            }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind == .localBranch
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var localRebaseTargets: [GitReference] {
        rebaseTargets.filter { $0.kind == .localBranch }
    }

    private var remoteRebaseTargets: [GitReference] {
        rebaseTargets.filter { $0.kind == .remoteBranch }
    }

    private var operationsDisabled: Bool {
        model.isBusy
            || model.isGeneratingCommitMessage
            || model.hasPendingChangeOperations
    }

    private func copyReferenceName() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference.name, forType: .string)
    }
}

private struct BranchPill: View {
    @EnvironmentObject private var model: RepositoryModel
    let reference: GitReference
    var syncedRemotes: [GitReference] = []
    let commitIsHead: Bool
    let referenceIDsAtCommit: Set<String>

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
            } else {
                BranchGlyph(size: 12, color: foregroundColor)
            }
            Text(reference.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if !syncedRemotes.isEmpty {
                Image(systemName: "cloud")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .frame(height: 21)
        .frame(maxWidth: 130)
        // Hug the label: cap long names at 130, but never expand past the
        // content's ideal width and never compress the label away.
        .fixedSize(horizontal: true, vertical: false)
        .background(backgroundColor, in: Capsule())
        .help(helpText)
        .contextMenu {
            ReferenceContextMenuItems(
                reference: reference,
                commitIsHead: commitIsHead,
                referenceIDsAtCommit: referenceIDsAtCommit
            )

            if !syncedRemotes.isEmpty {
                Divider()

                ForEach(syncedRemotes) { remote in
                    Menu(remote.name) {
                        ReferenceContextMenuItems(
                            reference: remote,
                            commitIsHead: commitIsHead,
                            referenceIDsAtCommit: referenceIDsAtCommit
                        )
                    }
                }
            }
        }
    }

    /// Local branches use the git-branch glyph (rendered when `symbol` is
    /// nil); remote, tag, and other refs keep their SF Symbols.
    private var symbol: String? {
        switch reference.kind {
        case .localBranch: return nil
        case .remoteBranch: return "cloud"
        case .tag: return "tag"
        case .other: return "bookmark"
        }
    }

    private var foregroundColor: Color {
        isCurrentReference ? AppTheme.onPill : AppTheme.primary
    }

    private var backgroundColor: Color {
        guard isCurrentReference else { return AppTheme.graphReferenceBackground }

        // Mirrors VS Code's source-control graph: the current branch pill and
        // its graph lane share one color (charts.blue), the upstream pill and
        // lane another (charts.purple).
        return isCurrentRemoteReference ? AppTheme.graphRemote : AppTheme.graphBlue
    }

    private var isCurrentReference: Bool {
        if reference.isHead { return true }
        return isCurrentRemoteReference
    }

    private var isCurrentRemoteReference: Bool {
        reference.id == model.upstreamReference?.id
    }

    private var helpText: String {
        switch reference.kind {
        case .localBranch:
            let base = reference.isHead
                ? "Current local branch: \(reference.name)"
                : "Local branch: \(reference.name)"
            guard !syncedRemotes.isEmpty else { return base }
            let names = syncedRemotes.map(\.name).joined(separator: ", ")
            return "\(base) — in sync with \(names)"
        case .remoteBranch:
            return "Remote branch: \(reference.name)"
        case .tag:
            return "Tag: \(reference.name)"
        case .other:
            return reference.name
        }
    }
}

private extension GraphLaneColor {
    var swiftUIColor: Color {
        switch self {
        case .current: return AppTheme.graphBlue
        case .remote: return AppTheme.graphRemote
        case .base: return AppTheme.graphLane(0xD19A66)
        case .lane1: return AppTheme.graphLane(0xE5C07B)
        case .lane2: return AppTheme.graphLane(0xE06C75)
        case .lane3: return AppTheme.graphLane(0x98C379)
        case .lane4: return AppTheme.graphLane(0x56B6C2)
        case .lane5: return AppTheme.graphLane(0x528BFF)
        }
    }

    var nsColor: NSColor { NSColor(swiftUIColor) }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.onAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                configuration.isPressed
                    ? AppTheme.actionBlue.opacity(0.78)
                    : AppTheme.actionBlue
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

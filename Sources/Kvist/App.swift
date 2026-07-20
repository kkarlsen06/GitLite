import AppKit
import QuartzCore
import SwiftUI

@main
struct KvistApp: App {
    @NSApplicationDelegateAdaptor(KvistAppDelegate.self) private var appDelegate
    @StateObject private var tabsModel: WorkspaceTabsModel
    @StateObject private var themePreferences: ThemePreferences
    @State private var hasPresentedInitialFrame = false

    init() {
        let benchmark = KvistPerformanceInstrumentation.configuration
        if benchmark != nil {
            KvistRuntimeMetrics.reset()
        }
        let defaults: UserDefaults
        if benchmark != nil,
           let benchmarkDefaults = UserDefaults(
               suiteName: "com.hjalmarkarlsen.Kvist.PerformanceBenchmark"
           ) {
            benchmarkDefaults.removePersistentDomain(
                forName: "com.hjalmarkarlsen.Kvist.PerformanceBenchmark"
            )
            defaults = benchmarkDefaults
        } else {
            defaults = .standard
        }
        let restoresWorkspace = defaults.object(forKey: "restoreWorkspaceOnLaunch")
            .map { ($0 as? Bool) ?? true }
            ?? true
        _tabsModel = StateObject(
            wrappedValue: WorkspaceTabsModel(
                restoreSavedTabs: benchmark == nil && restoresWorkspace,
                initialRepositoryURL: benchmark?.opensRepository == true
                    ? benchmark?.repositoryURL
                    : nil,
                restoredRepositoryURLs: benchmark?.mode == .tabs
                    ? benchmark?.tabRepositoryURLs
                    : nil,
                persistenceEnabled: benchmark == nil,
                automaticallyActivatesInitialTab: false,
                monitoringActivationDelayMilliseconds: benchmark?.mode == .tabs
                    ? 2_000
                    : 100
            )
        )
        _themePreferences = StateObject(
            wrappedValue: ThemePreferences(defaults: defaults)
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasPresentedInitialFrame {
                    ContentView()
                } else {
                    InitialWindowContent()
                }
            }
                .id(themePreferences.appearanceStamp)
                .environmentObject(tabsModel)
                .environmentObject(themePreferences)
                .onAppear {
                    appDelegate.tabsModel = tabsModel
                }
                .preferredColorScheme(themePreferences.preferredColorScheme)
                .tint(AppTheme.actionBlue)
                .frame(
                    minWidth: 420,
                    maxWidth: .infinity,
                    minHeight: 588,
                    maxHeight: .infinity
                )
                .overlay(alignment: .topLeading) {
                    WindowConfigurator {
                        guard !hasPresentedInitialFrame else { return }
                        KvistPerformanceInstrumentation.recordInitialFrame()
                        KvistPerformanceInstrumentation.recordTabsBeforeInitialSelection(
                            tabsModel
                        )
                        DispatchQueue.main.async {
                            guard !hasPresentedInitialFrame else { return }
                            hasPresentedInitialFrame = true
                            tabsModel.activateInitialTab()
                            KvistPerformanceInstrumentation.runTabMeasurementsIfRequested(
                                tabsModel: tabsModel
                            )
                            KvistInteractionPerformanceInstrumentation.runIfRequested(
                                model: tabsModel.activeModel
                            )
                            KvistHistoryPerformanceInstrumentation.runIfRequested(
                                model: tabsModel.activeModel
                            )
                        }
                    }
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }
        }
        .defaultSize(width: 465, height: 886)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Menu validation reads the active repository model, so publish
            // the first frame before constructing the command hierarchy.
            if hasPresentedInitialFrame {
                CommandGroup(replacing: .newItem) {
                Button("Open Repository…") {
                    tabsModel.activeModel.chooseRepository()
                }
                .keyboardShortcut("o")
                .disabled(
                    tabsModel.activeModel.isBusy
                    || tabsModel.activeModel.isSavingRepositoryFile
                    || tabsModel.activeModel.isGeneratingCommitMessage
                    || tabsModel.activeModel.hasPendingChangeOperations
                )

                Button("New Repository Tab") {
                    tabsModel.addTab()
                }
                .keyboardShortcut("t")

                Button("Close Repository Tab") {
                    tabsModel.close(tabsModel.activeTabID)
                }
                .keyboardShortcut("w")

                Divider()

                Button("Show Next Tab") {
                    tabsModel.selectNext()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(tabsModel.tabs.count < 2)

                Button("Show Previous Tab") {
                    tabsModel.selectPrevious()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(tabsModel.tabs.count < 2)
            }

            CommandGroup(before: .toolbar) {
                Button("Show Git") {
                    tabsModel.activeModel.setWorkspaceMode(.sourceControl)
                }
                .keyboardShortcut("1")

                Button("Show Files") {
                    tabsModel.activeModel.setWorkspaceMode(.fileEditor)
                }
                .keyboardShortcut("2")
                .disabled(tabsModel.activeModel.repositoryURL == nil)

                Button(
                    tabsModel.activeModel.workspaceMode == .sourceControl
                        ? "Switch to Files"
                        : "Switch to Git"
                ) {
                    tabsModel.activeModel.toggleWorkspaceMode()
                }
                .keyboardShortcut(.tab, modifiers: [.control])
                .disabled(tabsModel.activeModel.repositoryURL == nil)

                Divider()

                Button("Show Changes for This File") {
                    tabsModel.activeModel.showChangesForCurrentFile()
                }
                .disabled(!tabsModel.activeModel.canShowChangesForCurrentFile)

                Divider()
            }

            CommandGroup(after: .toolbar) {
                Button("Save File") {
                    Task { await tabsModel.activeModel.saveRepositoryFile() }
                }
                .keyboardShortcut("s")
                .disabled(!tabsModel.activeModel.canSaveRepositoryFile)

                Button("Close Editor Panel") {
                    tabsModel.activeModel.closeEditorPanel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!tabsModel.activeModel.isDiffPanelPresented)
            }

            CommandMenu("Repository") {
                Button("Refresh") {
                    Task { await tabsModel.activeModel.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(
                    tabsModel.activeModel.repositoryURL == nil
                    || tabsModel.activeModel.isBusy
                    || tabsModel.activeModel.isSavingRepositoryFile
                    || tabsModel.activeModel.isGeneratingCommitMessage
                    || tabsModel.activeModel.hasPendingChangeOperations
                )

                Divider()

                Button("Fetch") {
                    Task { await tabsModel.activeModel.fetch() }
                }
                .disabled(!repositoryOperationAvailable)

                Button("Pull") {
                    Task { await tabsModel.activeModel.pull() }
                }
                .disabled(
                    !repositoryOperationAvailable
                        || !tabsModel.activeModel.hasUpstream
                )

                Button(
                    tabsModel.activeModel.hasUpstream
                        ? "Push"
                        : "Publish Branch"
                ) {
                    Task { await tabsModel.activeModel.pushOrPublish() }
                }
                .disabled(
                    !repositoryOperationAvailable
                        || (!tabsModel.activeModel.hasUpstream
                            && (tabsModel.activeModel.branch == "detached HEAD"
                                || tabsModel.activeModel.headHash == nil))
                )

                Button("Sync Changes") {
                    Task { await tabsModel.activeModel.sync() }
                }
                .disabled(
                    !repositoryOperationAvailable
                        || !tabsModel.activeModel.hasUpstream
                )

                Divider()

                Button("Commit") {
                    Task { await tabsModel.activeModel.commit() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(
                    !tabsModel.activeModel.hasChanges
                    || tabsModel.activeModel.isBusy
                    || tabsModel.activeModel.isSavingRepositoryFile
                    || tabsModel.activeModel.hasPendingChangeOperations
                    || tabsModel.activeModel.isGeneratingCommitMessage
                )
                }
            }
        }

        Settings {
            if hasPresentedInitialFrame {
                PreferencesView()
                    .environmentObject(themePreferences)
            } else {
                EmptyView()
            }
        }

    }

    private var repositoryOperationAvailable: Bool {
        tabsModel.activeModel.repositoryURL != nil
            && !tabsModel.activeModel.isBusy
            && !tabsModel.activeModel.isSavingRepositoryFile
            && !tabsModel.activeModel.isGeneratingCommitMessage
            && !tabsModel.activeModel.hasPendingChangeOperations
    }
}

private struct InitialWindowContent: View {
    var body: some View {
        Color(nsColor: AppTheme.canvasNSColor)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

@MainActor
private final class KvistAppDelegate: NSObject, NSApplicationDelegate {
    weak var tabsModel: WorkspaceTabsModel?
    private var tabCycleKeyMonitor: Any?

    // Option-Tab / Option-Shift-Tab cycle repository tabs. Menu items can
    // only carry one key equivalent (⌘⇧] / ⌘⇧[), so the alternates are
    // handled with an event monitor instead of duplicate menu entries.
    func applicationDidFinishLaunching(_ notification: Notification) {
        KvistPerformanceInstrumentation.runGitMeasurementsIfRequested()
        tabCycleKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let tabsModel = self?.tabsModel,
                  event.keyCode == 48 else { return event }
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
            if flags == .option {
                tabsModel.selectNext()
                return nil
            }
            if flags == [.option, .shift] {
                tabsModel.selectPrevious()
                return nil
            }
            return event
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        let defaults = UserDefaults.standard
        let restoresWorkspace = defaults.object(forKey: "restoreWorkspaceOnLaunch")
            .map { ($0 as? Bool) ?? true }
            ?? true
        if restoresWorkspace {
            tabsModel?.prepareForTermination()
            return .terminateNow
        }
        return tabsModel?.confirmDiscardAllRepositoryFileChanges() == false
            ? .terminateCancel
            : .terminateNow
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let didDisplayInitialFrame: () -> Void

    init(didDisplayInitialFrame: @escaping () -> Void = {}) {
        self.didDisplayInitialFrame = didDisplayInitialFrame
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(didDisplayInitialFrame: didDisplayInitialFrame)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window != nil {
            context.coordinator.configureIfNeeded(nsView.window)
        } else {
            DispatchQueue.main.async {
                context.coordinator.configureIfNeeded(nsView.window)
            }
        }
    }

    final class Coordinator {
        private let didDisplayInitialFrame: () -> Void
        private weak var configuredWindow: NSWindow?

        init(didDisplayInitialFrame: @escaping () -> Void) {
            self.didDisplayInitialFrame = didDisplayInitialFrame
        }

        func configureIfNeeded(_ window: NSWindow?) {
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            // Keep content gestures, including the Changes/Graph resize handle,
            // from being interpreted as window drags. The tab row occupies the
            // titlebar region and provides window dragging via WindowDragArea.
            window.isMovableByWindowBackground = false
            window.backgroundColor = AppTheme.canvasNSColor
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
            // The window and its SwiftUI hierarchy are installed at this point.
            // Render immediately instead of paying another main-run-loop turn;
            // model activation remains deferred by the caller to avoid changing
            // observable state during view reconciliation.
            window.displayIfNeeded()
            CATransaction.flush()
            didDisplayInitialFrame()
        }
    }
}

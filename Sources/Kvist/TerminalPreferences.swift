import AppKit
import Foundation
import UniformTypeIdentifiers

struct TerminalApplication: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let name: String
    let applicationURL: URL?

    var id: String { bundleIdentifier }

    var isInstalled: Bool { applicationURL != nil }

    var menuTitle: String {
        isInstalled ? name : "\(name) (not installed)"
    }

    @MainActor
    var icon: NSImage? {
        guard let applicationURL else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

enum TerminalPreferences {
    static let bundleIdentifierKey = "terminalApplicationBundleIdentifier"
    static let defaultBundleIdentifier = "com.apple.Terminal"

    // Terminals Kvist offers directly; anything else is reachable through the
    // "Choose…" panel, which stores whatever bundle identifier it finds.
    static let suggestedBundleIdentifiers = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "com.raphaelamorim.rio",
        "org.tabby",
        "co.zeit.hyper"
    ]

    private static let suggestedNames = [
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm",
        "com.mitchellh.ghostty": "Ghostty",
        "dev.warp.Warp-Stable": "Warp",
        "net.kovidgoyal.kitty": "kitty",
        "org.alacritty": "Alacritty",
        "com.github.wez.wezterm": "WezTerm",
        "com.raphaelamorim.rio": "Rio",
        "org.tabby": "Tabby",
        "co.zeit.hyper": "Hyper"
    ]

    // LaunchServices lists every terminal as a .command handler, including ones
    // that accept the file and drop it, so Kvist trusts only these for SSH.
    private static let shellScriptBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]

    static func runsShellScripts(_ bundleIdentifier: String) -> Bool {
        shellScriptBundleIdentifiers.contains(bundleIdentifier)
    }

    /// The app that should run an SSH `.command` file: the selected terminal
    /// when it executes shell scripts, otherwise the system's own handler.
    static func shellScriptApplicationURL(
        bundleIdentifier: String,
        applicationURL: URL,
        defaultHandlerURL: URL?
    ) -> URL {
        if runsShellScripts(bundleIdentifier) { return applicationURL }
        return defaultHandlerURL ?? applicationURL
    }

    static func selectedBundleIdentifier(defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: bundleIdentifierKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultBundleIdentifier : stored
    }

    /// Installed suggestions in listed order, plus the current selection so the
    /// picker never silently drops an app the user chose or uninstalled.
    static func availableApplications(
        selectedBundleIdentifier: String,
        workspace: NSWorkspace = .shared
    ) -> [TerminalApplication] {
        var identifiers = suggestedBundleIdentifiers
        let selected = selectedBundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty, !identifiers.contains(selected) {
            identifiers.append(selected)
        }

        return identifiers.compactMap { identifier in
            let applicationURL = workspace.urlForApplication(
                withBundleIdentifier: identifier
            )
            guard applicationURL != nil || identifier == selected else { return nil }
            return TerminalApplication(
                bundleIdentifier: identifier,
                name: displayName(forBundleIdentifier: identifier, applicationURL: applicationURL),
                applicationURL: applicationURL
            )
        }
    }

    static func displayName(
        forBundleIdentifier bundleIdentifier: String,
        workspace: NSWorkspace = .shared
    ) -> String {
        displayName(
            forBundleIdentifier: bundleIdentifier,
            applicationURL: workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        )
    }

    static func displayName(
        forBundleIdentifier bundleIdentifier: String,
        applicationURL: URL?
    ) -> String {
        if let applicationURL {
            return displayName(forApplicationAt: applicationURL)
        }
        return suggestedNames[bundleIdentifier] ?? bundleIdentifier
    }

    static func displayName(forApplicationAt applicationURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: applicationURL.path)
        guard name.lowercased().hasSuffix(".app") else { return name }
        return String(name.dropLast(4))
    }

    /// Returns `nil` when the user cancels; throws when the chosen bundle has no
    /// identifier to store.
    @MainActor
    static func chooseApplication() throws -> TerminalApplication? {
        let panel = NSOpenPanel()
        panel.title = "Choose Terminal App"
        panel.message = "Choose the app Kvist opens repositories in."
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let identifier = Bundle(url: url)?.bundleIdentifier else {
            throw RepositoryTerminalError.unreadableApplication
        }
        return TerminalApplication(
            bundleIdentifier: identifier,
            name: displayName(forApplicationAt: url),
            applicationURL: url
        )
    }
}

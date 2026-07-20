import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AppThemePalette: Codable, Equatable {
    var canvas: UInt32
    var edge: UInt32
    var inputFill: UInt32
    var hover: UInt32
    var raisedFill: UInt32
    var diffCanvas: UInt32
    var disabledFill: UInt32
    var selection: UInt32
    var primary: UInt32
    var secondary: UInt32
    var muted: UInt32
    var onAccent: UInt32
    var onPill: UInt32
    var badgeText: UInt32
    var actionBlue: UInt32
    var graphBlue: UInt32
    var graphRemote: UInt32
    var graphReferenceBackground: UInt32
    var badgeBlue: UInt32
    var inputBorder: UInt32
    var modified: UInt32
    var added: UInt32
    var deleted: UInt32
    var conflict: UInt32
    var destructiveButton: UInt32
    var swift: UInt32
    var diffHeaderText: UInt32
    var diffHunkText: UInt32
    var diffHunkBackground: UInt32
    var diffAddedText: UInt32
    var diffAddedBackground: UInt32
    var diffRemovedText: UInt32
    var diffRemovedBackground: UInt32

    static let oneDark = AppThemePalette(
        canvas: 0x21252B, edge: 0x181A1F, inputFill: 0x1B1D23,
        hover: 0x2C313A, raisedFill: 0x282C34, diffCanvas: 0x282C34,
        disabledFill: 0x323842, selection: 0x528BFF,
        primary: 0xABB2BF, secondary: 0x9DA5B4, muted: 0x5C6370,
        onAccent: 0xFFFFFF, onPill: 0x282C34, badgeText: 0xFFFFFF,
        actionBlue: 0x4D78CC, graphBlue: 0x61AFEF, graphRemote: 0xC678DD,
        graphReferenceBackground: 0x3E4451, badgeBlue: 0x4D78CC,
        inputBorder: 0x3E4451, modified: 0xE5C07B, added: 0x98C379,
        deleted: 0xE06C75, conflict: 0xD19A66,
        destructiveButton: 0xBE5046, swift: 0xF05138,
        diffHeaderText: 0x61AFEF, diffHunkText: 0x56B6C2,
        diffHunkBackground: 0x2C3A4D, diffAddedText: 0x98C379,
        diffAddedBackground: 0x2A3429, diffRemovedText: 0xE06C75,
        diffRemovedBackground: 0x3A2C2E
    )

    /// Ayu Dark 1.1.12, mapped from the upstream VS Code workbench colors.
    /// Source: https://github.com/ayu-theme/vscode-ayu/blob/master/ayu-dark-unbordered.json
    static let ayuDark = AppThemePalette.importing([
        "editor.background": "#0d1017",
        "editor.foreground": "#bfbdb6",
        "foreground": "#5a6378",
        "descriptionForeground": "#5a6378",
        "disabledForeground": "#5a637880",
        "panel.border": "#1b1f29",
        "input.background": "#10141c",
        "input.border": "#5a637833",
        "list.hoverBackground": "#47526640",
        "sideBarSectionHeader.background": "#0d1017",
        "button.background": "#e6b450",
        "button.foreground": "#765b24",
        "button.secondaryBackground": "#5a637833",
        "activityBarBadge.background": "#e6b450",
        "activityBarBadge.foreground": "#765b24",
        "badge.background": "#e6b45033",
        "badge.foreground": "#e6b450",
        "editor.selectionBackground": "#3388ff40",
        "gitDecoration.modifiedResourceForeground": "#73b8ff",
        "gitDecoration.addedResourceForeground": "#70bf56",
        "gitDecoration.untrackedResourceForeground": "#70bf56",
        "gitDecoration.deletedResourceForeground": "#f26d78",
        "errorForeground": "#d95757",
        "symbolIcon.classForeground": "#59c2ff",
        "symbolIcon.methodForeground": "#ffb454",
        "editorGutter.modifiedBackground": "#73b8ff",
        "diffEditor.insertedTextBackground": "#70bf561f",
        "diffEditor.removedTextBackground": "#f26d781f",
        "diffEditor.diagonalFill": "#1b1f29"
    ])

    /// Builds an app palette from an editor theme's `colors` dictionary.
    ///
    /// Imported themes rarely define every token the app needs, and many of
    /// the values they do define are translucent. Missing surfaces and text
    /// tiers are derived from the theme's own canvas and foreground, alpha
    /// values are composited over the surface they render on, and text-like
    /// tokens are nudged toward a minimum contrast ratio so every theme stays
    /// legible.
    static func importing(_ colors: [String: String]) -> AppThemePalette {
        func themed(_ keys: [String]) -> ThemeColor? {
            for key in keys {
                if let raw = colors[key], let parsed = ThemeColorParser.parse(raw) {
                    return parsed
                }
            }
            return nil
        }

        let canvas = themed(["editor.background", "sideBar.background"])?.rgb
            ?? oneDark.canvas
        let isDark = ColorMath.luminance(canvas) < 0.5
        let towardForeground: UInt32 = isDark ? 0xFFFFFF : 0x000000
        let awayFromForeground: UInt32 = isDark ? 0x000000 : 0xFFFFFF
        func elevate(_ amount: Double) -> UInt32 {
            ColorMath.mix(canvas, towardForeground, amount)
        }
        func recede(_ amount: Double) -> UInt32 {
            ColorMath.mix(canvas, awayFromForeground, amount)
        }
        func surface(_ keys: [String], derived: UInt32) -> UInt32 {
            themed(keys)?.composited(over: canvas) ?? derived
        }
        func text(
            _ keys: [String],
            derived: UInt32,
            minimumContrast ratio: Double,
            over background: UInt32? = nil
        ) -> UInt32 {
            let base = background ?? canvas
            let raw = themed(keys)?.composited(over: base) ?? derived
            return ColorMath.ensureContrast(raw, over: base, ratio: ratio)
        }

        let primary = text(
            ["foreground", "editor.foreground", "sideBar.foreground"],
            derived: isDark ? 0xD4D7DD : 0x24292F,
            minimumContrast: 4.5
        )
        let secondary = text(
            ["descriptionForeground", "sideBar.foreground"],
            derived: ColorMath.mix(primary, canvas, 0.2),
            minimumContrast: 3.0
        )
        let muted = text(
            ["disabledForeground", "editorLineNumber.foreground"],
            derived: ColorMath.mix(primary, canvas, 0.42),
            minimumContrast: 2.4
        )

        let action = ColorMath.ensureContrast(
            themed(["button.background", "focusBorder", "activityBarBadge.background"])?
                .composited(over: canvas) ?? oneDark.actionBlue,
            over: canvas,
            ratio: 1.6
        )
        let badgeBlue = ColorMath.ensureContrast(
            themed(["activityBarBadge.background", "badge.background"])?
                .composited(over: canvas) ?? action,
            over: canvas,
            ratio: 1.6
        )
        // charts.blue is what VS Code uses for the current-branch ref pill
        // and graph lane; themes without it get the accent blue rather than
        // the grayish submodule decoration color.
        let graphBlue = ColorMath.ensureContrast(
            themed(["charts.blue"])?.rgb ?? action,
            over: canvas,
            ratio: 2.2
        )
        let graphRemote = ColorMath.ensureContrast(
            themed(["charts.purple", "symbolIcon.classForeground"])?.rgb ?? oneDark.graphRemote,
            over: canvas,
            ratio: 2.2
        )

        func status(_ keys: [String], derived: UInt32) -> UInt32 {
            text(keys, derived: derived, minimumContrast: 2.6)
        }
        let added = status(
            ["gitDecoration.addedResourceForeground",
             "gitDecoration.untrackedResourceForeground", "charts.green"],
            derived: oneDark.added
        )
        let deleted = status(
            ["gitDecoration.deletedResourceForeground", "errorForeground", "charts.red"],
            derived: oneDark.deleted
        )

        // Selection is rendered by the app at reduced opacity, so it wants the
        // theme's saturated accent rather than a pre-blended row background.
        let selection = ColorMath.ensureContrast(
            themed(["editor.selectionBackground", "list.activeSelectionBackground",
                    "focusBorder"])?.rgb ?? action,
            over: canvas,
            ratio: 1.8
        )

        let addedBackground = surface(
            ["diffEditor.insertedTextBackground", "diffEditor.insertedLineBackground"],
            derived: ColorMath.mix(canvas, added, 0.18)
        )
        let removedBackground = surface(
            ["diffEditor.removedTextBackground", "diffEditor.removedLineBackground"],
            derived: ColorMath.mix(canvas, deleted, 0.18)
        )
        let hunkBackground = surface(
            ["diffEditor.diagonalFill", "editor.wordHighlightBackground"],
            derived: ColorMath.mix(canvas, graphBlue, 0.16)
        )

        return AppThemePalette(
            canvas: canvas,
            edge: surface(
                ["contrastBorder", "panel.border", "editorGroup.border"],
                derived: isDark ? recede(0.35) : elevate(0.12)
            ),
            inputFill: surface(
                ["input.background"],
                derived: recede(isDark ? 0.18 : 0.5)
            ),
            hover: surface(["list.hoverBackground"], derived: elevate(0.05)),
            raisedFill: surface(
                ["sideBarSectionHeader.background", "editorGroupHeader.tabsBackground"],
                derived: isDark ? elevate(0.04) : recede(0.35)
            ),
            diffCanvas: canvas,
            disabledFill: surface(
                ["button.secondaryBackground", "list.inactiveSelectionBackground"],
                derived: elevate(0.10)
            ),
            selection: selection,
            primary: primary,
            secondary: secondary,
            muted: muted,
            onAccent: ColorMath.readableText(
                themed(["button.foreground"])?.rgb ?? 0xFFFFFF,
                over: action
            ),
            onPill: ColorMath.readableText(awayFromForeground, over: graphBlue),
            badgeText: ColorMath.readableText(
                themed(["activityBarBadge.foreground", "badge.foreground"])?.rgb ?? 0xFFFFFF,
                over: badgeBlue
            ),
            actionBlue: action,
            graphBlue: graphBlue,
            graphRemote: graphRemote,
            graphReferenceBackground: surface(
                ["badge.background"],
                derived: elevate(0.13)
            ),
            badgeBlue: badgeBlue,
            inputBorder: surface(
                ["input.border", "focusBorder"],
                derived: elevate(0.2)
            ),
            modified: status(
                ["gitDecoration.modifiedResourceForeground", "charts.yellow"],
                derived: oneDark.modified
            ),
            added: added,
            deleted: deleted,
            conflict: status(
                ["gitDecoration.conflictingResourceForeground", "charts.orange"],
                derived: oneDark.conflict
            ),
            destructiveButton: ColorMath.darkened(
                themed(["statusBarItem.errorBackground"])?.composited(over: canvas) ?? deleted,
                untilReadable: 0xFFFFFF,
                ratio: 4.5
            ),
            swift: status(
                ["symbolIcon.methodForeground", "charts.orange"],
                derived: oneDark.swift
            ),
            diffHeaderText: text(
                ["editorInfo.foreground", "charts.blue"],
                derived: graphBlue,
                minimumContrast: 3.0
            ),
            diffHunkText: text(
                ["editorGutter.modifiedBackground", "charts.blue"],
                derived: oneDark.diffHunkText,
                minimumContrast: 3.0,
                over: hunkBackground
            ),
            diffHunkBackground: hunkBackground,
            diffAddedText: ColorMath.ensureContrast(added, over: addedBackground, ratio: 3.0),
            diffAddedBackground: addedBackground,
            diffRemovedText: ColorMath.ensureContrast(deleted, over: removedBackground, ratio: 3.0),
            diffRemovedBackground: removedBackground
        )
    }

    /// Palettes stored by older imports darkened this fill only until white
    /// text reached 3.0:1; clamp when reading so saved themes stay readable
    /// without a migration.
    var readableDestructiveButton: UInt32 {
        ColorMath.darkened(destructiveButton, untilReadable: 0xFFFFFF, ratio: 4.5)
    }

    /// Text for destructive fills. `onAccent` is only validated against the
    /// accent fill and can be illegible on the darkened red.
    var onDestructive: UInt32 {
        ColorMath.readableText(0xFFFFFF, over: readableDestructiveButton)
    }
}

struct ImportedAppTheme: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let publisher: String
    let license: String
    let licenseURL: URL?
    let sourceURL: URL?
    let palette: AppThemePalette
}

struct BuiltInAppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let publisher: String
    let license: String
    let sourceURL: URL
    let palette: AppThemePalette
}

/// A file-icon theme imported from an editor extension. Icon assets are
/// copied into Application Support; the maps reference file names inside
/// the pack's directory.
struct ImportedIconPack: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let publisher: String
    let license: String
    let licenseURL: URL?
    let sourceURL: URL?
    let directoryName: String
    let iconsByExtension: [String: String]
    let iconsByFileName: [String: String]
    let defaultFileIcon: String?
    let folderIcon: String?
    let folderExpandedIcon: String?
}

/// Everything importable found inside one extension archive.
struct ImportedExtensionContent {
    var themes: [ImportedAppTheme] = []
    var iconPacks: [ImportedIconPack] = []

    var isEmpty: Bool { themes.isEmpty && iconPacks.isEmpty }

    mutating func merge(_ other: ImportedExtensionContent) {
        themes.append(contentsOf: other.themes)
        iconPacks.append(contentsOf: other.iconPacks)
    }
}

struct OpenVSXThemeResult: Decodable, Identifiable, Equatable {
    struct Files: Decodable, Equatable {
        let download: URL?
    }

    let url: URL
    let files: Files
    let name: String
    let namespace: String
    let version: String
    let displayName: String
    let description: String
    let downloadCount: Int?
    let deprecated: Bool?

    var id: String { "\(namespace).\(name)" }
    var pageURL: URL? {
        URL(string: "https://open-vsx.org/extension/\(namespace)/\(name)")
    }
}

private struct OpenVSXSearchResponse: Decodable {
    let extensions: [OpenVSXThemeResult]
}

private struct OpenVSXExtensionDetail: Decodable {
    struct Files: Decodable {
        let download: URL?
        let license: URL?
    }

    struct BundledExtension: Decodable {
        let url: URL
    }

    let files: Files
    let name: String
    let namespace: String
    let displayName: String
    let categories: [String]
    let license: String
    let downloadable: Bool?
    let bundledExtensions: [BundledExtension]?

    var pageURL: URL? {
        URL(string: "https://open-vsx.org/extension/\(namespace)/\(name)")
    }

    func hasCategory(_ category: String) -> Bool {
        categories.contains {
            $0.localizedCaseInsensitiveCompare(category) == .orderedSame
        }
    }
}

@MainActor
final class ThemePreferences: ObservableObject {
    static let oneDarkThemeID = "builtin.one-dark"
    static let ayuDarkThemeID = "builtin.ayu-dark"
    static let defaultThemeID = ayuDarkThemeID
    static let builtInIconPackID = "builtin.system-symbols"
    static let materialIconPackID = "builtin.material-icon-theme"
    static let defaultIconPackID = materialIconPackID

    static let builtInThemes = [
        BuiltInAppTheme(
            id: ayuDarkThemeID,
            name: "Ayu Dark",
            publisher: "teabyii",
            license: "MIT",
            sourceURL: URL(string: "https://github.com/ayu-theme/vscode-ayu")!,
            palette: .ayuDark
        ),
        BuiltInAppTheme(
            id: oneDarkThemeID,
            name: "One Dark Pro",
            publisher: "Binaryify",
            license: "MIT",
            sourceURL: URL(string: "https://github.com/Binaryify/OneDark-Pro")!,
            palette: .oneDark
        )
    ]

    private static let materialIconPackManifestURL = Bundle.module.url(
        forResource: "manifest",
        withExtension: "json",
        subdirectory: "MaterialIconTheme"
    ) ?? Bundle.module.url(
        forResource: "manifest",
        withExtension: "json"
    )

    static let builtInMaterialIconPack: ImportedIconPack? = {
        guard let url = materialIconPackManifestURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ImportedIconPack.self, from: data)
    }()

    static var builtInMaterialIconPackRoot: URL? {
        materialIconPackManifestURL?.deletingLastPathComponent()
    }

    @Published private(set) var importedThemes: [ImportedAppTheme]
    @Published private(set) var importedIconPacks: [ImportedIconPack]
    @Published private(set) var selectedThemeID: String
    @Published private(set) var selectedIconPackID: String
    @Published var searchText = ""
    @Published private(set) var searchResults: [OpenVSXThemeResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var importingExtensionID: String?
    @Published var statusMessage: String?

    private let defaults: UserDefaults
    private let selectedThemeKey = "selectedAppThemeID"
    private let importedThemesKey = "importedAppThemesV1"
    private let selectedIconPackKey = "selectedIconPackID"
    private let importedIconPacksKey = "importedIconPacksV1"

    static var iconPacksRoot: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Kvist/IconPacks", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        importedThemes = defaults.data(forKey: importedThemesKey).flatMap {
            try? JSONDecoder().decode([ImportedAppTheme].self, from: $0)
        } ?? []
        importedIconPacks = defaults.data(forKey: importedIconPacksKey).flatMap {
            try? JSONDecoder().decode([ImportedIconPack].self, from: $0)
        } ?? []
        let savedID = defaults.string(forKey: selectedThemeKey)
            ?? Self.defaultThemeID
        let savedIconID = defaults.string(forKey: selectedIconPackKey)
            ?? Self.defaultIconPackID
        selectedThemeID = savedID
        selectedIconPackID = savedIconID

        let savedBuiltInTheme = Self.builtInThemes.first(where: { $0.id == savedID })
        let savedImportedTheme = importedThemes.first(where: { $0.id == savedID })
        if savedBuiltInTheme == nil, savedImportedTheme == nil {
            selectedThemeID = Self.defaultThemeID
        }
        AppTheme.apply(savedBuiltInTheme?.palette ?? savedImportedTheme?.palette ?? .ayuDark)

        if let resolved = resolvedIconPack(id: savedIconID) {
            AppIcons.apply(resolved.pack, directory: resolved.directory)
        } else if let fallback = resolvedIconPack(id: Self.defaultIconPackID) {
            selectedIconPackID = Self.defaultIconPackID
            AppIcons.apply(fallback.pack, directory: fallback.directory)
        } else {
            selectedIconPackID = Self.builtInIconPackID
            AppIcons.apply(nil, directory: nil)
        }
    }

    /// Changes whenever the selected theme or icon pack changes. Views read
    /// colors from the static `AppTheme`, so the main window re-renders by
    /// keying its identity on this stamp.
    var appearanceStamp: String {
        "\(selectedThemeID)|\(selectedIconPackID)"
    }

    var selectedThemeName: String {
        if let theme = Self.builtInThemes.first(where: { $0.id == selectedThemeID }) {
            return theme.name
        }
        return importedThemes.first(where: { $0.id == selectedThemeID })?.name
            ?? "Ayu Dark"
    }

    var preferredColorScheme: ColorScheme {
        let palette = Self.builtInThemes.first(where: { $0.id == selectedThemeID })?.palette
            ?? importedThemes.first(where: { $0.id == selectedThemeID })?.palette
            ?? .ayuDark
        let red = Double((palette.canvas >> 16) & 0xFF) / 255
        let green = Double((palette.canvas >> 8) & 0xFF) / 255
        let blue = Double(palette.canvas & 0xFF) / 255
        return (0.2126 * red + 0.7152 * green + 0.0722 * blue) < 0.52
            ? .dark
            : .light
    }

    func selectTheme(id: String) {
        let palette: AppThemePalette
        if let builtIn = Self.builtInThemes.first(where: { $0.id == id }) {
            palette = builtIn.palette
        } else if let imported = importedThemes.first(where: { $0.id == id }) {
            palette = imported.palette
        } else {
            return
        }
        selectedThemeID = id
        defaults.set(id, forKey: selectedThemeKey)
        AppTheme.apply(palette)
        objectWillChange.send()
        for window in NSApplication.shared.windows {
            window.backgroundColor = AppTheme.canvasNSColor
            window.contentView?.needsDisplay = true
        }
    }

    func removeTheme(_ theme: ImportedAppTheme) {
        removeThemes(ids: [theme.id])
    }

    func removeThemes(ids: Set<String>) {
        let removesSelectedTheme = importedThemes.contains {
            $0.id == selectedThemeID && ids.contains($0.id)
        }
        importedThemes.removeAll { ids.contains($0.id) }
        if removesSelectedTheme {
            selectTheme(id: Self.defaultThemeID)
        }
        persistImportedThemes()
    }

    func selectIconPack(id: String) {
        guard let resolved = resolvedIconPack(id: id) else { return }
        selectedIconPackID = id
        defaults.set(id, forKey: selectedIconPackKey)
        AppIcons.apply(resolved.pack, directory: resolved.directory)
        objectWillChange.send()
        for window in NSApplication.shared.windows {
            window.contentView?.needsDisplay = true
        }
    }

    private func resolvedIconPack(
        id: String
    ) -> (pack: ImportedIconPack?, directory: URL?)? {
        if id == Self.builtInIconPackID {
            return (nil, nil)
        }
        if id == Self.materialIconPackID,
           let pack = Self.builtInMaterialIconPack,
           let root = Self.builtInMaterialIconPackRoot {
            return (pack, root)
        }
        if let imported = importedIconPacks.first(where: { $0.id == id }) {
            return (
                imported,
                Self.iconPacksRoot.appendingPathComponent(
                    imported.directoryName,
                    isDirectory: true
                )
            )
        }
        return nil
    }

    func removeIconPack(_ pack: ImportedIconPack) {
        removeIconPacks(ids: [pack.id])
    }

    func removeIconPacks(ids: Set<String>) {
        let removedPacks = importedIconPacks.filter { ids.contains($0.id) }
        let removesSelectedPack = removedPacks.contains { $0.id == selectedIconPackID }
        importedIconPacks.removeAll { ids.contains($0.id) }
        if removesSelectedPack {
            selectIconPack(id: Self.defaultIconPackID)
        }
        for pack in removedPacks {
            try? FileManager.default.removeItem(
                at: Self.iconPacksRoot.appendingPathComponent(
                    pack.directoryName,
                    isDirectory: true
                )
            )
        }
        persistImportedIconPacks()
    }

    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        statusMessage = nil
        defer { isSearching = false }
        do {
            var components = URLComponents(string: "https://open-vsx.org/api/-/search")!
            components.queryItems = [
                URLQueryItem(name: "query", value: "\(query) theme"),
                URLQueryItem(name: "size", value: "20")
            ]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            try Self.validate(response: response, data: data)
            let result = try JSONDecoder().decode(OpenVSXSearchResponse.self, from: data)
            searchResults = result.extensions.filter {
                $0.deprecated != true && $0.files.download != nil
            }
            if searchResults.isEmpty {
                statusMessage = "No importable themes found."
            }
        } catch {
            searchResults = []
            statusMessage = "Theme search failed: \(error.localizedDescription)"
        }
    }

    func importTheme(_ result: OpenVSXThemeResult) async {
        importingExtensionID = result.id
        statusMessage = nil
        defer { importingExtensionID = nil }
        do {
            let metadata = try await fetchExtensionDetail(from: result.url)
            let content = try await importExtension(
                metadata,
                followsBundles: true
            )
            install(content)
        } catch {
            statusMessage = "Could not import \(result.displayName): \(error.localizedDescription)"
        }
    }

    /// Imports one resolved extension. Extension packs (such as combined
    /// theme + icon bundles) contain no theme files themselves, so their
    /// bundled extensions are followed one level deep.
    private func importExtension(
        _ metadata: OpenVSXExtensionDetail,
        followsBundles: Bool
    ) async throws -> ImportedExtensionContent {
        if metadata.hasCategory("Themes") {
            return try await downloadAndImport(metadata)
        }
        guard followsBundles, metadata.hasCategory("Extension Packs"),
              let bundled = metadata.bundledExtensions, !bundled.isEmpty else {
            throw ThemeImportError.notAThemeExtension
        }
        var content = ImportedExtensionContent()
        for reference in bundled.prefix(8) {
            guard let detail = try? await fetchExtensionDetail(from: reference.url),
                  let piece = try? await importExtension(detail, followsBundles: false) else {
                continue
            }
            content.merge(piece)
        }
        guard !content.isEmpty else { throw ThemeImportError.emptyExtensionPack }
        return content
    }

    private func fetchExtensionDetail(from url: URL) async throws -> OpenVSXExtensionDetail {
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(OpenVSXExtensionDetail.self, from: data)
    }

    private func downloadAndImport(
        _ metadata: OpenVSXExtensionDetail
    ) async throws -> ImportedExtensionContent {
        guard metadata.downloadable != false,
              let downloadURL = metadata.files.download else {
            throw ThemeImportError.notDownloadable
        }
        guard !metadata.license.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ThemeImportError.missingLicense
        }
        let (temporaryURL, response) = try await URLSession.shared.download(from: downloadURL)
        try Self.validate(response: response, data: nil)
        let size = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 50 * 1_024 * 1_024 else { throw ThemeImportError.archiveTooLarge }
        let iconPacksRoot = Self.iconPacksRoot
        return try await Task.detached(priority: .userInitiated) {
            try EditorThemeImporter.importVSIX(
                at: temporaryURL,
                publisher: metadata.namespace,
                extensionName: metadata.name,
                license: metadata.license,
                licenseURL: metadata.files.license,
                sourceURL: metadata.pageURL,
                iconPacksRoot: iconPacksRoot
            )
        }.value
    }

    func chooseLocalTheme() async {
        let panel = NSOpenPanel()
        panel.title = "Import Editor Theme"
        panel.message = "Choose a color-theme JSON file or a licensed VSIX theme extension."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .json,
            UTType(filenameExtension: "vsix") ?? .data
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let iconPacksRoot = Self.iconPacksRoot
            let content = try await Task.detached(priority: .userInitiated) {
                if url.pathExtension.lowercased() == "vsix" {
                    return try EditorThemeImporter.importVSIX(
                        at: url,
                        publisher: "Local import",
                        extensionName: url.deletingPathExtension().lastPathComponent,
                        license: "User-provided file",
                        licenseURL: nil,
                        sourceURL: nil,
                        iconPacksRoot: iconPacksRoot
                    )
                }
                return ImportedExtensionContent(
                    themes: [try EditorThemeImporter.importJSON(at: url)]
                )
            }.value
            install(content)
        } catch {
            statusMessage = "Could not import theme: \(error.localizedDescription)"
        }
    }

    private func install(_ content: ImportedExtensionContent) {
        guard !content.isEmpty else {
            statusMessage = "The extension does not contain a color theme or icon pack."
            return
        }
        for theme in content.themes {
            importedThemes.removeAll { $0.id == theme.id }
            importedThemes.append(theme)
        }
        importedThemes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistImportedThemes()
        for pack in content.iconPacks {
            importedIconPacks.removeAll { $0.id == pack.id }
            importedIconPacks.append(pack)
        }
        importedIconPacks.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistImportedIconPacks()
        if let theme = content.themes.first {
            selectTheme(id: theme.id)
        }
        if let pack = content.iconPacks.first {
            selectIconPack(id: pack.id)
        }
        var pieces: [String] = []
        if !content.themes.isEmpty {
            pieces.append(
                content.themes.count == 1
                    ? "theme \(content.themes[0].name)"
                    : "\(content.themes.count) themes"
            )
        }
        if !content.iconPacks.isEmpty {
            pieces.append(
                content.iconPacks.count == 1
                    ? "icon pack \(content.iconPacks[0].name)"
                    : "\(content.iconPacks.count) icon packs"
            )
        }
        statusMessage = "Imported \(pieces.joined(separator: " and "))."
    }

    private func persistImportedThemes() {
        if let data = try? JSONEncoder().encode(importedThemes) {
            defaults.set(data, forKey: importedThemesKey)
        }
    }

    private func persistImportedIconPacks() {
        if let data = try? JSONEncoder().encode(importedIconPacks) {
            defaults.set(data, forKey: importedIconPacksKey)
        }
    }

    nonisolated private static func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ThemeImportError.invalidServerResponse
        }
        if let data, data.count > 2 * 1_024 * 1_024 {
            throw ThemeImportError.metadataTooLarge
        }
    }
}

private enum ThemeImportError: LocalizedError {
    case invalidServerResponse, metadataTooLarge, archiveTooLarge
    case notAThemeExtension, emptyExtensionPack, notDownloadable, missingLicense
    case invalidArchive, invalidManifest, invalidTheme, unsafePath

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse: return "the registry returned an invalid response"
        case .metadataTooLarge: return "the registry metadata is unexpectedly large"
        case .archiveTooLarge: return "the theme archive is larger than 50 MB"
        case .notAThemeExtension: return "this extension is not categorized as a theme or extension pack"
        case .emptyExtensionPack: return "none of the extensions bundled in this pack could be imported"
        case .notDownloadable: return "this extension cannot be downloaded"
        case .missingLicense: return "the extension does not declare a license"
        case .invalidArchive: return "the VSIX archive could not be expanded"
        case .invalidManifest: return "the extension has no valid theme manifest"
        case .invalidTheme: return "the theme JSON is invalid or has no colors"
        case .unsafePath: return "the archive contains an unsafe file path"
        }
    }
}

enum EditorThemeImporter {
    static func importVSIX(
        at archiveURL: URL,
        publisher: String,
        extensionName: String,
        license: String,
        licenseURL: URL?,
        sourceURL: URL?,
        iconPacksRoot: URL
    ) throws -> ImportedExtensionContent {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KvistTheme-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ThemeImportError.invalidArchive }

        let extensionRoot = root.appendingPathComponent("extension", isDirectory: true)
        let manifestURL = try safeURL(relativePath: "package.json", under: extensionRoot)
        let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        guard data.count <= 2 * 1_024 * 1_024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contributes = object["contributes"] as? [String: Any] else {
            throw ThemeImportError.invalidManifest
        }
        let themeDeclarations = contributes["themes"] as? [[String: Any]] ?? []
        let iconDeclarations = contributes["iconThemes"] as? [[String: Any]] ?? []
        guard !themeDeclarations.isEmpty || !iconDeclarations.isEmpty else {
            throw ThemeImportError.invalidManifest
        }

        func slugAndName(
            of declaration: [String: Any],
            themeURL: URL
        ) -> (slug: String, name: String) {
            let name = (declaration["label"] as? String)
                ?? (declaration["id"] as? String)
                ?? themeURL.deletingPathExtension().lastPathComponent
            let slug = name.lowercased().replacingOccurrences(
                of: "[^a-z0-9]+",
                with: "-",
                options: .regularExpression
            )
            return (slug, name)
        }

        var content = ImportedExtensionContent()
        content.themes = try themeDeclarations.compactMap { declaration in
            guard let path = declaration["path"] as? String else { return nil }
            let themeURL = try safeURL(relativePath: path, under: extensionRoot)
            let (slug, name) = slugAndName(of: declaration, themeURL: themeURL)
            let colors = try loadColors(at: themeURL, root: extensionRoot, depth: 0)
            guard !colors.isEmpty else { return nil }
            return ImportedAppTheme(
                id: "openvsx.\(publisher).\(extensionName).\(slug)",
                name: name,
                publisher: publisher,
                license: license,
                licenseURL: licenseURL,
                sourceURL: sourceURL,
                palette: .importing(colors)
            )
        }
        content.iconPacks = try iconDeclarations.compactMap { declaration in
            guard let path = declaration["path"] as? String else { return nil }
            let themeURL = try safeURL(relativePath: path, under: extensionRoot)
            let (slug, name) = slugAndName(of: declaration, themeURL: themeURL)
            return try importIconTheme(
                at: themeURL,
                extensionRoot: extensionRoot,
                id: "openvsx.\(publisher).\(extensionName).icons.\(slug)",
                name: name,
                publisher: publisher,
                license: license,
                licenseURL: licenseURL,
                sourceURL: sourceURL,
                iconPacksRoot: iconPacksRoot
            )
        }
        return content
    }

    /// Parses an editor file-icon theme and copies the referenced SVG/PNG
    /// assets into the app's icon-pack store. Font-glyph based definitions
    /// are skipped; the pack is dropped when nothing usable remains.
    private static func importIconTheme(
        at themeURL: URL,
        extensionRoot: URL,
        id: String,
        name: String,
        publisher: String,
        license: String,
        licenseURL: URL?,
        sourceURL: URL?,
        iconPacksRoot: URL
    ) throws -> ImportedIconPack? {
        let object = try loadJSONObject(at: themeURL, root: extensionRoot)
        guard let definitions = object["iconDefinitions"] as? [String: Any] else {
            return nil
        }
        var pathsByIconID: [String: String] = [:]
        for (iconID, value) in definitions {
            if let detail = value as? [String: Any],
               let iconPath = detail["iconPath"] as? String {
                pathsByIconID[iconID] = iconPath
            }
        }
        guard !pathsByIconID.isEmpty else { return nil }

        func iconIDMap(_ key: String, limit: Int = 1_500) -> [String: String] {
            guard let raw = object[key] as? [String: Any] else { return [:] }
            var map: [String: String] = [:]
            for (name, value) in raw.prefix(limit) {
                if let iconID = value as? String {
                    map[name.lowercased()] = iconID
                }
            }
            return map
        }
        let extensionIcons = iconIDMap("fileExtensions")
        let fileNameIcons = iconIDMap("fileNames")
        let defaultFileIcon = object["file"] as? String
        let folderIcon = object["folder"] as? String
        let folderExpandedIcon = object["folderExpanded"] as? String

        let directoryName = stableIdentifier(for: id)
        let packDirectory = iconPacksRoot.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: packDirectory)
        try FileManager.default.createDirectory(
            at: packDirectory,
            withIntermediateDirectories: true
        )

        // Copy each referenced asset once; icon ids that fail to copy are
        // dropped from the maps so lookups never point at missing files.
        var copiedFileByIconID: [String: String] = [:]
        var neededIconIDs = Set(extensionIcons.values)
            .union(fileNameIcons.values)
        for iconID in [defaultFileIcon, folderIcon, folderExpandedIcon] {
            if let iconID { neededIconIDs.insert(iconID) }
        }
        for iconID in neededIconIDs {
            guard let iconPath = pathsByIconID[iconID] else { continue }
            let fileExtension = (iconPath as NSString).pathExtension.lowercased()
            guard fileExtension == "svg" || fileExtension == "png" else { continue }
            guard let source = try? safeURL(
                relativePath: themeURL.deletingLastPathComponent()
                    .appendingPathComponent(iconPath).path,
                under: extensionRoot,
                permitsAbsolutePath: true
            ) else { continue }
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size <= 1_024 * 1_024 else { continue }
            let fileName = "\(stableIdentifier(for: iconID)).\(fileExtension)"
            do {
                try FileManager.default.copyItem(
                    at: source,
                    to: packDirectory.appendingPathComponent(fileName)
                )
                copiedFileByIconID[iconID] = fileName
            } catch {
                continue
            }
        }

        func resolved(_ map: [String: String]) -> [String: String] {
            map.compactMapValues { copiedFileByIconID[$0] }
        }
        let iconsByExtension = resolved(extensionIcons)
        let iconsByFileName = resolved(fileNameIcons)
        let defaultFile = defaultFileIcon.flatMap { copiedFileByIconID[$0] }
        guard !iconsByExtension.isEmpty || !iconsByFileName.isEmpty || defaultFile != nil else {
            try? FileManager.default.removeItem(at: packDirectory)
            return nil
        }
        return ImportedIconPack(
            id: id,
            name: name,
            publisher: publisher,
            license: license,
            licenseURL: licenseURL,
            sourceURL: sourceURL,
            directoryName: directoryName,
            iconsByExtension: iconsByExtension,
            iconsByFileName: iconsByFileName,
            defaultFileIcon: defaultFile,
            folderIcon: folderIcon.flatMap { copiedFileByIconID[$0] },
            folderExpandedIcon: folderExpandedIcon.flatMap { copiedFileByIconID[$0] }
        )
    }

    static func importJSON(at url: URL) throws -> ImportedAppTheme {
        let colors = try loadColors(
            at: url,
            root: url.deletingLastPathComponent(),
            depth: 0
        )
        guard !colors.isEmpty else { throw ThemeImportError.invalidTheme }
        let name = url.deletingPathExtension().lastPathComponent
        return ImportedAppTheme(
            id: "local.\(name.lowercased()).\(stableIdentifier(for: url.path))",
            name: name,
            publisher: "Local import",
            license: "User-provided file",
            licenseURL: nil,
            sourceURL: nil,
            palette: .importing(colors)
        )
    }

    private static func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    /// Loads a JSONC document from inside the extension, enforcing the
    /// path-safety and size limits shared by all theme files.
    private static func loadJSONObject(at url: URL, root: URL) throws -> [String: Any] {
        let safe = try safeURL(relativePath: url.path, under: root, permitsAbsolutePath: true)
        let data = try Data(contentsOf: safe, options: .mappedIfSafe)
        guard data.count <= 4 * 1_024 * 1_024,
              let text = String(data: data, encoding: .utf8) else {
            throw ThemeImportError.invalidTheme
        }
        let cleaned = JSONC.clean(text)
        guard let cleanData = cleaned.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: cleanData) as? [String: Any] else {
            throw ThemeImportError.invalidTheme
        }
        return object
    }

    private static func loadColors(
        at url: URL,
        root: URL,
        depth: Int
    ) throws -> [String: String] {
        guard depth < 8 else { throw ThemeImportError.invalidTheme }
        let object = try loadJSONObject(at: url, root: root)
        let safe = try safeURL(relativePath: url.path, under: root, permitsAbsolutePath: true)
        var colors: [String: String] = [:]
        if let include = object["include"] as? String {
            let includeURL = safe.deletingLastPathComponent().appendingPathComponent(include)
            colors = try loadColors(at: includeURL, root: root, depth: depth + 1)
        }
        if let own = object["colors"] as? [String: Any] {
            for (key, value) in own {
                if let value = value as? String { colors[key] = value }
            }
        }
        return colors
    }

    private static func safeURL(
        relativePath: String,
        under root: URL,
        permitsAbsolutePath: Bool = false
    ) throws -> URL {
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate: URL
        if permitsAbsolutePath, relativePath.hasPrefix("/") {
            candidate = URL(fileURLWithPath: relativePath)
        } else {
            candidate = root.appendingPathComponent(relativePath)
        }
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard resolved.path.hasPrefix(prefix) else { throw ThemeImportError.unsafePath }
        return resolved
    }
}

struct ThemeColor: Equatable {
    let rgb: UInt32
    let alpha: Double

    func composited(over background: UInt32) -> UInt32 {
        alpha >= 1 ? rgb : ColorMath.mix(background, rgb, alpha)
    }
}

enum ThemeColorParser {
    static func parse(_ value: String) -> ThemeColor? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.removeFirstIfPresent("#") else { return nil }
        var alpha = 1.0
        if hex.count == 3 || hex.count == 4 {
            if hex.count == 4 {
                let digit = String(hex.removeLast())
                guard let value = UInt32(digit + digit, radix: 16) else { return nil }
                alpha = Double(value) / 255
            }
            hex = hex.map { "\($0)\($0)" }.joined()
        } else if hex.count == 8 {
            guard let value = UInt32(hex.suffix(2), radix: 16) else { return nil }
            alpha = Double(value) / 255
            hex = String(hex.prefix(6))
        }
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        return ThemeColor(rgb: rgb, alpha: alpha)
    }
}

enum ColorMath {
    static func mix(_ from: UInt32, _ to: UInt32, _ amount: Double) -> UInt32 {
        let (fr, fg, fb) = channels(from)
        let (tr, tg, tb) = channels(to)
        return pack(
            fr + (tr - fr) * amount,
            fg + (tg - fg) * amount,
            fb + (tb - fb) * amount
        )
    }

    /// WCAG relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        let (red, green, blue) = channels(hex)
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1...21.
    static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Moves `color` toward white or black — whichever is opposite the
    /// background — until it reaches the requested contrast ratio.
    static func ensureContrast(
        _ color: UInt32,
        over background: UInt32,
        ratio: Double
    ) -> UInt32 {
        guard contrast(color, background) < ratio else { return color }
        let pole: UInt32 = luminance(background) < 0.5 ? 0xFFFFFF : 0x000000
        var adjusted = color
        for step in stride(from: 0.1, through: 1.0, by: 0.1) {
            adjusted = mix(color, pole, step)
            if contrast(adjusted, background) >= ratio { return adjusted }
        }
        return adjusted
    }

    /// Keeps `candidate` when it is readable over `background`, otherwise
    /// moves it toward plain white or black — whichever contrasts more —
    /// until it reads, so the theme's hue survives when possible. The
    /// default ratio is WCAG AA for the small text these tokens label.
    static func readableText(
        _ candidate: UInt32,
        over background: UInt32,
        ratio: Double = 4.5
    ) -> UInt32 {
        if contrast(candidate, background) >= ratio { return candidate }
        let pole: UInt32 = contrast(0xFFFFFF, background) >= contrast(0x000000, background)
            ? 0xFFFFFF
            : 0x000000
        var adjusted = candidate
        for step in stride(from: 0.1, through: 1.0, by: 0.1) {
            adjusted = mix(candidate, pole, step)
            if contrast(adjusted, background) >= ratio { return adjusted }
        }
        return adjusted
    }

    /// Darkens a fill color until the given text color reads on top of it.
    static func darkened(
        _ color: UInt32,
        untilReadable text: UInt32,
        ratio: Double
    ) -> UInt32 {
        var adjusted = color
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            adjusted = mix(color, 0x000000, step)
            if contrast(text, adjusted) >= ratio { return adjusted }
        }
        return adjusted
    }

    private static func channels(_ hex: UInt32) -> (Double, Double, Double) {
        (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    private static func pack(_ red: Double, _ green: Double, _ blue: Double) -> UInt32 {
        func byte(_ value: Double) -> UInt32 {
            UInt32((min(max(value, 0), 1) * 255).rounded())
        }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

/// The active file-icon pack. `nil` pack means the built-in SF Symbol
/// glyphs from `FileGlyph` are used.
@MainActor
enum AppIcons {
    private static var pack: ImportedIconPack?
    private static var directory: URL?
    private static var cache: [String: NSImage] = [:]

    static func apply(_ newPack: ImportedIconPack?, directory: URL?) {
        pack = newPack
        self.directory = directory
        cache.removeAll()
    }

    static func image(forPath path: String) -> NSImage? {
        guard let pack else { return nil }
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        var candidates: [String] = []
        if let byName = pack.iconsByFileName[fileName] {
            candidates.append(byName)
        }
        // Editor icon themes support compound extensions ("spec.ts"), so try
        // the longest suffix first.
        let parts = fileName.split(separator: ".").map(String.init)
        if parts.count > 1 {
            for index in 1..<parts.count {
                let compound = parts[index...].joined(separator: ".")
                if let byExtension = pack.iconsByExtension[compound] {
                    candidates.append(byExtension)
                    break
                }
            }
        }
        if let defaultIcon = pack.defaultFileIcon {
            candidates.append(defaultIcon)
        }
        for candidate in candidates {
            if let image = load(candidate) { return image }
        }
        return nil
    }

    static func folderImage(expanded: Bool) -> NSImage? {
        guard let pack else { return nil }
        let fileName = expanded
            ? (pack.folderExpandedIcon ?? pack.folderIcon)
            : pack.folderIcon
        return fileName.flatMap(load)
    }

    private static func load(_ fileName: String) -> NSImage? {
        if let cached = cache[fileName] { return cached }
        guard let directory,
              let image = NSImage(contentsOf: directory.appendingPathComponent(fileName)),
              image.isValid else {
            return nil
        }
        cache[fileName] = image
        return image
    }
}

private enum JSONC {
    static func clean(_ source: String) -> String {
        let scalars = Array(source.unicodeScalars)
        var output = ""
        var index = 0
        var inString = false
        var escaped = false
        while index < scalars.count {
            let current = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if inString {
                output.unicodeScalars.append(current)
                if escaped {
                    escaped = false
                } else if current == "\\" {
                    escaped = true
                } else if current == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            if current == "\"" {
                inString = true
                output.unicodeScalars.append(current)
                index += 1
            } else if current == "/", next == "/" {
                index += 2
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
            } else if current == "/", next == "*" {
                index += 2
                while index + 1 < scalars.count,
                      !(scalars[index] == "*" && scalars[index + 1] == "/") {
                    index += 1
                }
                index = min(index + 2, scalars.count)
            } else {
                output.unicodeScalars.append(current)
                index += 1
            }
        }
        return removingTrailingCommas(from: output)
    }

    private static func removingTrailingCommas(from source: String) -> String {
        let scalars = Array(source.unicodeScalars)
        var output = ""
        var index = 0
        var inString = false
        var escaped = false
        while index < scalars.count {
            let current = scalars[index]
            if inString {
                output.unicodeScalars.append(current)
                if escaped {
                    escaped = false
                } else if current == "\\" {
                    escaped = true
                } else if current == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            if current == "\"" {
                inString = true
                output.unicodeScalars.append(current)
                index += 1
                continue
            }
            if current == "," {
                var lookahead = index + 1
                while lookahead < scalars.count,
                      CharacterSet.whitespacesAndNewlines.contains(scalars[lookahead]) {
                    lookahead += 1
                }
                if lookahead < scalars.count,
                   scalars[lookahead] == "}" || scalars[lookahead] == "]" {
                    index += 1
                    continue
                }
            }
            output.unicodeScalars.append(current)
            index += 1
        }
        return output
    }
}

private extension String {
    mutating func removeFirstIfPresent(_ prefix: Character) -> Bool {
        guard first == prefix else { return false }
        removeFirst()
        return true
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var themes: ThemePreferences

    var body: some View {
        TabView {
            GeneralPreferencesPane()
                .tabItem { Label("General", systemImage: "gearshape") }

            ThemePreferencesPane()
                .environmentObject(themes)
                .tabItem { Label("Themes", systemImage: "paintpalette") }

            LegalPreferencesPane()
                .tabItem { Label("Privacy & Legal", systemImage: "hand.raised") }
        }
        .frame(width: 700, height: 520)
        .preferredColorScheme(themes.preferredColorScheme)
        .tint(AppTheme.actionBlue)
    }
}

private struct GeneralPreferencesPane: View {
    @AppStorage("restoreWorkspaceOnLaunch") private var restoreWorkspaceOnLaunch = true
    @AppStorage("smartCommitPreference") private var smartCommitPreference = 0
    @AppStorage(AICommitMessagePreferences.providerKey)
    private var aiProviderRawValue = AICommitMessageProvider.codex.rawValue
    @AppStorage(AICommitMessagePreferences.codexModelKey)
    private var codexModel = AICommitMessageProvider.codex.defaultModel
    @AppStorage(AICommitMessagePreferences.claudeModelKey)
    private var claudeModel = AICommitMessageProvider.claude.defaultModel
    @AppStorage(AICommitMessagePreferences.codexReasoningEffortKey)
    private var codexReasoningEffortRawValue = AICommitMessageReasoningEffort.xhigh.rawValue
    @AppStorage(AICommitMessagePreferences.codexCommandTemplateKey)
    private var codexCommandTemplate = AICommitMessageProvider.codex.defaultCommandTemplate
    @AppStorage(AICommitMessagePreferences.claudeCommandTemplateKey)
    private var claudeCommandTemplate = AICommitMessageProvider.claude.defaultCommandTemplate
    @AppStorage(PrivacyPreferences.codexProcessingConsentKey)
    private var allowsCodexProcessing = false
    @AppStorage(PrivacyPreferences.claudeProcessingConsentKey)
    private var allowsClaudeProcessing = false
    @State private var showsAdvancedAISettings = false
    @State private var availableModels: [AICommitMessageModel] = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: String?

    private var provider: AICommitMessageProvider {
        AICommitMessageProvider(rawValue: aiProviderRawValue) ?? .codex
    }

    private var selectedModel: Binding<String> {
        switch provider {
        case .codex: $codexModel
        case .claude: $claudeModel
        }
    }

    private var selectedCommandTemplate: Binding<String> {
        switch provider {
        case .codex: $codexCommandTemplate
        case .claude: $claudeCommandTemplate
        }
    }

    private var allowsProcessing: Binding<Bool> {
        switch provider {
        case .codex: $allowsCodexProcessing
        case .claude: $allowsClaudeProcessing
        }
    }

    private var availableCodexReasoningEfforts: [AICommitMessageReasoningEffort] {
        guard let model = availableModels.first(where: { $0.id == codexModel }),
              !model.supportedReasoningEfforts.isEmpty else {
            return AICommitMessageReasoningEffort.allCases
        }
        return model.supportedReasoningEfforts
    }

    var body: some View {
        Form {
            Section("Workspace") {
                Toggle("Restore repositories and workspace state when Kvist opens", isOn: $restoreWorkspaceOnLaunch)
                Text("Open tabs, the selected tab, Files mode, expanded folders, commit text, and unsaved editor drafts are recovered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Commits") {
                Picker("When nothing is staged", selection: $smartCommitPreference) {
                    Text("Ask Each Time").tag(0)
                    Text("Stage All Changes and Commit").tag(1)
                    Text("Require Manual Staging").tag(2)
                }
                .pickerStyle(.menu)
            }

            Section("AI Commit Message") {
                Picker("Agent", selection: $aiProviderRawValue) {
                    ForEach(AICommitMessageProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Model") {
                    HStack(spacing: 6) {
                        TextField("Model ID", text: selectedModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 230)

                        Menu {
                            ForEach(availableModels) { model in
                                Button {
                                    selectedModel.wrappedValue = model.id
                                    normalizeCodexReasoningEffort()
                                } label: {
                                    if model.name == model.id {
                                        Text(model.id)
                                    } else {
                                        Text("\(model.name) (\(model.id))")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(availableModels.isEmpty)
                        .help("Choose an available model")

                        Button {
                            Task { await refreshModels() }
                        } label: {
                            if isLoadingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLoadingModels)
                        .help("Refresh available models")
                    }
                }

                if provider == .codex {
                    Picker(
                        "Reasoning effort",
                        selection: $codexReasoningEffortRawValue
                    ) {
                        ForEach(availableCodexReasoningEfforts) { effort in
                            Text(effort.displayName).tag(effort.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    if !codexCommandTemplate.contains("{reasoning-effort}") {
                        Text("The custom command does not use the selected reasoning effort.")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }
                }

                Text(modelLoadError ?? provider.modelSourceDescription)
                    .font(.caption)
                    .foregroundStyle(
                        modelLoadError == nil ? Color.secondary : Color.orange
                    )

                Toggle(
                    "Allow \(provider.displayName) to process staged changes",
                    isOn: allowsProcessing
                )
                Text("Kvist runs the installed \(provider.displayName) CLI using your account. It may send the staged diff, repository path, and your instructions to \(provider.serviceName). Unstaged and untracked changes are excluded by the prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup(
                    "Advanced",
                    isExpanded: $showsAdvancedAISettings
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Command template")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Terminal command", text: selectedCommandTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .accessibilityLabel("AI commit message command template")

                        HStack {
                            Button("Reset to \(provider.displayName) Default") {
                                selectedCommandTemplate.wrappedValue =
                                    provider.defaultCommandTemplate
                            }
                            Spacer()
                            Text("Prompt: standard input")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Kvist runs this command through /bin/zsh -lc in the repository. It shell-quotes and expands {executable}, {model}, {repository}, {schema}, {schema-json}, and {output}; Codex also expands {reasoning-effort}. Editing the template can run arbitrary shell commands with your user permissions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
        .task(id: aiProviderRawValue) {
            migrateLegacyCodexCommandIfNeeded()
            await refreshModels()
        }
        .onChange(of: codexModel) {
            normalizeCodexReasoningEffort()
        }
    }

    @MainActor
    private func refreshModels() async {
        let requestedProvider = provider
        isLoadingModels = true
        modelLoadError = nil
        do {
            let models = try await Task.detached(priority: .utility) {
                try AICommitMessageModelCatalog.load(for: requestedProvider)
            }.value
            guard provider == requestedProvider else { return }
            availableModels = models
            normalizeCodexReasoningEffort()
        } catch {
            guard provider == requestedProvider else { return }
            availableModels = requestedProvider.suggestedModels
            normalizeCodexReasoningEffort()
            modelLoadError = "Could not refresh from \(requestedProvider.displayName); showing built-in suggestions"
        }
        isLoadingModels = false
    }

    @MainActor
    private func normalizeCodexReasoningEffort() {
        guard provider == .codex,
              let model = availableModels.first(where: { $0.id == codexModel }),
              !model.supportedReasoningEfforts.isEmpty else { return }
        let selected = AICommitMessageReasoningEffort(
            rawValue: codexReasoningEffortRawValue
        )
        guard selected.map(model.supportedReasoningEfforts.contains) != true else {
            return
        }
        codexReasoningEffortRawValue = (
            model.defaultReasoningEffort ?? model.supportedReasoningEfforts[0]
        ).rawValue
    }

    @MainActor
    private func migrateLegacyCodexCommandIfNeeded() {
        guard codexCommandTemplate == AICommitMessageProvider.codex
            .legacyDefaultCommandTemplate else { return }
        codexCommandTemplate = AICommitMessageProvider.codex.defaultCommandTemplate
    }
}

private struct LegalPreferencesPane: View {
    var body: some View {
        Form {
            Section("Privacy") {
                Text("Repository operations stay on this Mac unless you explicitly use AI commit-message generation or Open VSX theme discovery.")
                Button("Open Privacy Notice") {
                    openBundledDocument(named: "PRIVACY", fileExtension: "md")
                }
            }

            Section("Licenses") {
                Text("Kvist is MIT licensed. The built-in themes and Material Icon Theme are distributed under the open-source licenses included with the app.")
                HStack {
                    Button("Kvist License") {
                        openBundledDocument(named: "LICENSE", fileExtension: "txt")
                    }
                    Button("Third-Party Notices") {
                        openBundledDocument(
                            named: "THIRD_PARTY_NOTICES",
                            fileExtension: "txt"
                        )
                    }
                }
            }

            Section("Trademarks") {
                Text("Git and the Git logo are either registered trademarks or trademarks of Software Freedom Conservancy, Inc. Kvist is independent and is not affiliated with or endorsed by the Git Project or Software Freedom Conservancy.")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private func openBundledDocument(named name: String, fileExtension: String) {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ThemePreferencesPane: View {
    @EnvironmentObject private var themes: ThemePreferences
    @State private var selectedLibraryIDs: Set<String> = []
    @State private var isConfirmingRemoval = false

    var body: some View {
        HSplitView {
            themeLibrary
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            discovery
                .frame(minWidth: 400, maxWidth: .infinity)
        }
        .background(AppTheme.canvas)
        .onAppear {
            selectedLibraryIDs = [themes.selectedThemeID]
        }
        .onChange(of: selectedLibraryIDs) { _, ids in
            activateSingleSelection(ids)
        }
        .onChange(of: themes.selectedThemeID) { _, id in
            if selectedLibraryIDs.count <= 1 {
                selectedLibraryIDs = [id]
            }
        }
        .onChange(of: themes.selectedIconPackID) { _, id in
            if selectedLibraryIDs.count <= 1 {
                selectedLibraryIDs = [id]
            }
        }
    }

    private var themeLibrary: some View {
        VStack(spacing: 0) {
            HStack {
                Text("THEME LIBRARY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            List(selection: $selectedLibraryIDs) {
                ForEach(ThemePreferences.builtInThemes) { theme in
                    ThemeLibraryRow(
                        id: theme.id,
                        name: theme.name,
                        detail: "Built in · \(theme.publisher)",
                        palette: theme.palette
                    )
                    .tag(theme.id)
                }

                if !themes.importedThemes.isEmpty {
                    Section("Imported") {
                        ForEach(themes.importedThemes) { theme in
                            ThemeLibraryRow(
                                id: theme.id,
                                name: theme.name,
                                detail: "\(theme.publisher) · \(theme.license)",
                                palette: theme.palette
                            )
                            .tag(theme.id)
                        }
                    }
                }

                Section("Icon Packs") {
                    IconPackRow(
                        name: "System Symbols",
                        detail: "Built in",
                        isActive: themes.selectedIconPackID
                            == ThemePreferences.builtInIconPackID
                    )
                    .tag(ThemePreferences.builtInIconPackID)

                    if let material = ThemePreferences.builtInMaterialIconPack {
                        IconPackRow(
                            name: material.name,
                            detail: "Built in · \(material.publisher)",
                            isActive: themes.selectedIconPackID
                                == ThemePreferences.materialIconPackID
                        )
                        .tag(material.id)
                    }

                    ForEach(themes.importedIconPacks) { pack in
                        IconPackRow(
                            name: pack.name,
                            detail: "\(pack.publisher) · \(pack.license)",
                            isActive: themes.selectedIconPackID == pack.id
                        )
                        .tag(pack.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onDeleteCommand(perform: requestRemoval)

            if let license = selectedThemeLicense {
                VStack(alignment: .leading, spacing: 2) {
                    Text("License: \(license)")
                    if let source = selectedThemeSource {
                        Link(source.label, destination: source.url)
                    } else if let licenseURL = selectedLibraryLicenseURL {
                        Link("View license", destination: licenseURL)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Divider() }
            }

            HStack {
                Button {
                    Task { await themes.chooseLocalTheme() }
                } label: {
                    Label("Import File", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                if selectedLibraryIDs.count > 1 {
                    Text("\(selectedLibraryIDs.count) selected")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.muted)
                }

                if removableSelectionCount > 0 {
                    Button(role: .destructive) {
                        requestRemoval()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(removalButtonLabel)
                    .accessibilityLabel(removalButtonLabel)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .overlay(alignment: .top) { Divider() }
        }
        .background(AppTheme.raisedFill)
        .alert(removalAlertTitle, isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive, action: removeSelection)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalAlertMessage)
        }
    }

    private var inspectedLibraryID: String? {
        selectedLibraryIDs.count == 1 ? selectedLibraryIDs.first : nil
    }

    private var selectedImportedTheme: ImportedAppTheme? {
        themes.importedThemes.first { $0.id == inspectedLibraryID }
    }

    private var selectedBuiltInTheme: BuiltInAppTheme? {
        ThemePreferences.builtInThemes.first { $0.id == inspectedLibraryID }
    }

    private var selectedImportedIconPack: ImportedIconPack? {
        themes.importedIconPacks.first { $0.id == inspectedLibraryID }
    }

    private var selectedMaterialIconPack: ImportedIconPack? {
        guard inspectedLibraryID == ThemePreferences.materialIconPackID else {
            return nil
        }
        return ThemePreferences.builtInMaterialIconPack
    }

    private var selectedThemeLicense: String? {
        selectedBuiltInTheme?.license
            ?? selectedImportedTheme?.license
            ?? selectedMaterialIconPack?.license
            ?? selectedImportedIconPack?.license
    }

    private var selectedLibraryLicenseURL: URL? {
        selectedImportedTheme?.licenseURL
            ?? selectedMaterialIconPack?.licenseURL
            ?? selectedImportedIconPack?.licenseURL
    }

    private var selectedThemeSource: (label: String, url: URL)? {
        if let builtIn = selectedBuiltInTheme {
            return ("View source", builtIn.sourceURL)
        }
        if let sourceURL = selectedImportedTheme?.sourceURL {
            return ("View source in Open VSX", sourceURL)
        }
        if let sourceURL = selectedMaterialIconPack?.sourceURL {
            return ("View source", sourceURL)
        }
        if let sourceURL = selectedImportedIconPack?.sourceURL {
            return ("View source in Open VSX", sourceURL)
        }
        return nil
    }

    private var removableSelectionIDs: Set<String> {
        let themeIDs = themes.importedThemes.lazy
            .map(\.id)
            .filter(selectedLibraryIDs.contains)
        let iconPackIDs = themes.importedIconPacks.lazy
            .map(\.id)
            .filter(selectedLibraryIDs.contains)
        return Set(themeIDs).union(iconPackIDs)
    }

    private var removableSelectionCount: Int {
        removableSelectionIDs.count
    }

    private var selectedRemovableNames: [String] {
        let themeNames = themes.importedThemes.lazy
            .filter { removableSelectionIDs.contains($0.id) }
            .map(\.name)
        let iconPackNames = themes.importedIconPacks.lazy
            .filter { removableSelectionIDs.contains($0.id) }
            .map(\.name)
        return Array(themeNames) + Array(iconPackNames)
    }

    private var removalButtonLabel: String {
        if let name = selectedRemovableNames.first, removableSelectionCount == 1 {
            return "Remove \(name)"
        }
        return "Remove \(removableSelectionCount) Selected Items"
    }

    private var removalAlertTitle: String {
        if let name = selectedRemovableNames.first, removableSelectionCount == 1 {
            return "Remove “\(name)”?"
        }
        return "Remove \(removableSelectionCount) Items?"
    }

    private var removalAlertMessage: String {
        if removableSelectionCount == 1 {
            return "The selected import will be removed from Kvist. You can import it again later."
        }
        return "The selected imported themes and icon packs will be removed from Kvist. Built-in items will be kept."
    }

    private func activateSingleSelection(_ ids: Set<String>) {
        guard ids.count == 1, let id = ids.first else { return }
        if ThemePreferences.builtInThemes.contains(where: { $0.id == id })
            || themes.importedThemes.contains(where: { $0.id == id }) {
            themes.selectTheme(id: id)
        } else if id == ThemePreferences.builtInIconPackID
                    || id == ThemePreferences.materialIconPackID
                    || themes.importedIconPacks.contains(where: { $0.id == id }) {
            themes.selectIconPack(id: id)
        }
    }

    private func requestRemoval() {
        guard removableSelectionCount > 0 else { return }
        isConfirmingRemoval = true
    }

    private func removeSelection() {
        let ids = removableSelectionIDs
        themes.removeThemes(ids: ids)
        themes.removeIconPacks(ids: ids)
        selectedLibraryIDs.subtract(ids)
        if selectedLibraryIDs.isEmpty {
            selectedLibraryIDs = [themes.selectedThemeID]
        }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Find editor themes and icon packs")
                    .font(.system(size: 17, weight: .semibold))
                Text("Search the Eclipse Open VSX registry. Kvist checks that an extension is downloadable, contains a theme or icon pack, and declares a license before importing it. Extension packs are unbundled automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("Theme name or publisher", text: $themes.searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await themes.search() } }
                    Button("Search") {
                        Task { await themes.search() }
                    }
                    .disabled(
                        themes.isSearching
                            || themes.searchText.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
                .padding(.top, 5)
            }
            .padding(18)

            Divider()

            if themes.isSearching {
                ProgressView("Searching Open VSX…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if themes.searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(AppTheme.muted)
                    Text("Search for a color theme or icon pack to preview it in Kvist.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(themes.searchResults) { result in
                    OpenVSXResultRow(result: result)
                        .environmentObject(themes)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            if let status = themes.statusMessage {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Divider() }
            }

            HStack(spacing: 4) {
                Text("Themes remain subject to their publisher's license.")
                Link("Open VSX", destination: URL(string: "https://open-vsx.org")!)
            }
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.muted)
            .padding(.horizontal, 18)
            .frame(height: 30)
            .overlay(alignment: .top) { Divider() }
        }
        .foregroundStyle(AppTheme.primary)
        .background(AppTheme.canvas)
    }
}

private struct IconPackRow: View {
    let name: String
    let detail: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? AppTheme.actionBlue : AppTheme.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct ThemeLibraryRow: View {
    let id: String
    let name: String
    let detail: String
    let palette: AppThemePalette

    var body: some View {
        HStack(spacing: 9) {
            ThemeSwatch(palette: palette)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ThemeSwatch: View {
    let palette: AppThemePalette

    var body: some View {
        HStack(spacing: 0) {
            Color(hex: palette.canvas)
            Color(hex: palette.actionBlue)
            Color(hex: palette.added)
        }
        .frame(width: 34, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(hex: palette.edge), lineWidth: 1)
        }
    }
}

private struct OpenVSXResultRow: View {
    @EnvironmentObject private var themes: ThemePreferences
    let result: OpenVSXThemeResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let pageURL = result.pageURL {
                    Link(result.displayName, destination: pageURL)
                        .font(.system(size: 13, weight: .medium))
                } else {
                    Text(result.displayName)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(result.description)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(result.namespace)
                    Text("v\(result.version)")
                    if let downloads = result.downloadCount {
                        Label(downloads.formatted(), systemImage: "arrow.down.circle")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 8)
            Button(themes.importingExtensionID == result.id ? "Importing…" : "Import") {
                Task { await themes.importTheme(result) }
            }
            .disabled(themes.importingExtensionID != nil)
        }
        .padding(.vertical, 5)
    }
}

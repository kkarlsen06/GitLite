import Foundation
import XCTest
@testable import Kvist

final class ThemePreferencesTests: XCTestCase {
    @MainActor
    func testAyuDarkIsTheDefaultTheme() {
        let suiteName = "ThemePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ThemePreferences(defaults: defaults)

        XCTAssertEqual(ThemePreferences.defaultThemeID, ThemePreferences.ayuDarkThemeID)
        XCTAssertEqual(preferences.selectedThemeID, ThemePreferences.ayuDarkThemeID)
        XCTAssertEqual(preferences.selectedThemeName, "Ayu Dark")
    }

    @MainActor
    func testMaterialIconThemeIsTheDefaultIconPack() {
        let suiteName = "ThemePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ThemePreferences(defaults: defaults)

        XCTAssertEqual(
            ThemePreferences.defaultIconPackID,
            ThemePreferences.materialIconPackID
        )
        XCTAssertEqual(
            preferences.selectedIconPackID,
            ThemePreferences.materialIconPackID
        )
        XCTAssertNotNil(AppIcons.image(forPath: "Example.swift"))
    }

    @MainActor
    func testSavedSystemSymbolsChoiceStillRestores() {
        let suiteName = "ThemePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ThemePreferences.builtInIconPackID,
            forKey: "selectedIconPackID"
        )

        let preferences = ThemePreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.selectedIconPackID,
            ThemePreferences.builtInIconPackID
        )
        XCTAssertNil(AppIcons.image(forPath: "Example.swift"))
    }

    func testBundledAyuDarkUsesUpstreamWorkbenchColors() {
        let palette = AppThemePalette.ayuDark

        XCTAssertEqual(palette.canvas, 0x0D1017)
        XCTAssertEqual(palette.actionBlue, 0xE6B450)
        XCTAssertEqual(palette.modified, 0x73B8FF)
        XCTAssertEqual(palette.added, 0x70BF56)
        XCTAssertEqual(palette.deleted, 0xF26D78)
    }

    @MainActor
    func testBundledAyuDarkSelectionIsRestored() {
        let suiteName = "ThemePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ThemePreferences.ayuDarkThemeID,
            forKey: "selectedAppThemeID"
        )

        let preferences = ThemePreferences(defaults: defaults)

        XCTAssertEqual(preferences.selectedThemeID, ThemePreferences.ayuDarkThemeID)
        XCTAssertEqual(preferences.selectedThemeName, "Ayu Dark")
        XCTAssertEqual(preferences.preferredColorScheme, .dark)
    }

    @MainActor
    func testBundledMaterialIconPackLoadsAndRestores() throws {
        let pack = try XCTUnwrap(ThemePreferences.builtInMaterialIconPack)
        let root = try XCTUnwrap(ThemePreferences.builtInMaterialIconPackRoot)
        XCTAssertEqual(pack.id, ThemePreferences.materialIconPackID)
        XCTAssertEqual(pack.name, "Material Icon Theme")
        XCTAssertEqual(pack.publisher, "PKief")
        XCTAssertEqual(pack.license, "MIT")
        XCTAssertNotNil(pack.iconsByExtension["swift"])
        XCTAssertNotNil(pack.iconsByFileName["package.json"])

        for fileName in [pack.defaultFileIcon, pack.folderIcon, pack.folderExpandedIcon] {
            let fileURL = root.appendingPathComponent(try XCTUnwrap(fileName))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }

        let suiteName = "ThemePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ThemePreferences.materialIconPackID,
            forKey: "selectedIconPackID"
        )

        let preferences = ThemePreferences(defaults: defaults)

        XCTAssertEqual(preferences.selectedIconPackID, ThemePreferences.materialIconPackID)
        XCTAssertNotNil(AppIcons.image(forPath: "Example.swift"))
        XCTAssertNotNil(AppIcons.folderImage(expanded: false))
        XCTAssertNotNil(AppIcons.folderImage(expanded: true))
    }

    @MainActor
    func testBulkRemovalDeletesOnlyImportedThemesAndIconPacks() throws {
        let suiteName = "ThemePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstTheme = ImportedAppTheme(
            id: "imported.theme.first",
            name: "First Theme",
            publisher: "Test",
            license: "MIT",
            licenseURL: nil,
            sourceURL: nil,
            palette: .oneDark
        )
        let secondTheme = ImportedAppTheme(
            id: "imported.theme.second",
            name: "Second Theme",
            publisher: "Test",
            license: "MIT",
            licenseURL: nil,
            sourceURL: nil,
            palette: .ayuDark
        )
        let firstPack = testIconPack(id: "imported.icons.first")
        let secondPack = testIconPack(id: "imported.icons.second")
        defaults.set(
            try JSONEncoder().encode([firstTheme, secondTheme]),
            forKey: "importedAppThemesV1"
        )
        defaults.set(
            try JSONEncoder().encode([firstPack, secondPack]),
            forKey: "importedIconPacksV1"
        )
        defaults.set(firstTheme.id, forKey: "selectedAppThemeID")
        defaults.set(firstPack.id, forKey: "selectedIconPackID")

        let preferences = ThemePreferences(defaults: defaults)
        preferences.removeThemes(ids: [
            firstTheme.id,
            ThemePreferences.ayuDarkThemeID
        ])
        preferences.removeIconPacks(ids: [
            firstPack.id,
            ThemePreferences.materialIconPackID
        ])

        XCTAssertEqual(preferences.importedThemes, [secondTheme])
        XCTAssertEqual(preferences.importedIconPacks, [secondPack])
        XCTAssertEqual(preferences.selectedThemeID, ThemePreferences.defaultThemeID)
        XCTAssertEqual(
            preferences.selectedIconPackID,
            ThemePreferences.defaultIconPackID
        )
    }

    func testPaletteMapsEditorWorkbenchAndGitColors() {
        let palette = AppThemePalette.importing([
            "editor.background": "#101820",
            "editor.foreground": "#F0F1F2",
            "button.background": "#336699",
            "gitDecoration.modifiedResourceForeground": "#E5C07B",
            "gitDecoration.addedResourceForeground": "#98C379",
            "gitDecoration.deletedResourceForeground": "#E06C75"
        ])

        XCTAssertEqual(palette.canvas, 0x101820)
        XCTAssertEqual(palette.primary, 0xF0F1F2)
        XCTAssertEqual(palette.actionBlue, 0x336699)
        XCTAssertEqual(palette.modified, 0xE5C07B)
        XCTAssertEqual(palette.added, 0x98C379)
        XCTAssertEqual(palette.deleted, 0xE06C75)
    }

    private func testIconPack(id: String) -> ImportedIconPack {
        ImportedIconPack(
            id: id,
            name: id,
            publisher: "Test",
            license: "MIT",
            licenseURL: nil,
            sourceURL: nil,
            directoryName: "ThemePreferencesTests-\(UUID().uuidString)",
            iconsByExtension: [:],
            iconsByFileName: [:],
            defaultFileIcon: nil,
            folderIcon: nil,
            folderExpandedIcon: nil
        )
    }

    func testTranslucentColorsCompositeOverTheirSurface() {
        let palette = AppThemePalette.importing([
            "editor.background": "#000000",
            "diffEditor.insertedTextBackground": "#00FF0080"
        ])

        // 50% green over black must blend, not become a solid loud fill.
        XCTAssertEqual(palette.diffAddedBackground, 0x008000)
    }

    func testLowContrastTextIsLiftedToReadable() {
        let palette = AppThemePalette.importing([
            "editor.background": "#101820",
            "editor.foreground": "#26303A",
            "disabledForeground": "#182028",
            "gitDecoration.addedResourceForeground": "#123456"
        ])

        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.primary, palette.canvas), 4.5
        )
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.muted, palette.canvas), 2.4
        )
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.added, palette.canvas), 2.6
        )
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.diffAddedText, palette.diffAddedBackground), 3.0
        )
    }

    func testMissingTokensAreDerivedFromThemeCanvasNotOneDark() {
        let light = AppThemePalette.importing(["editor.background": "#FAFAFA"])

        let oneDark = AppThemePalette.oneDark
        XCTAssertNotEqual(light.hover, oneDark.hover)
        XCTAssertNotEqual(light.raisedFill, oneDark.raisedFill)
        XCTAssertNotEqual(light.edge, oneDark.edge)
        // Derived surfaces stay near the theme's own canvas.
        XCTAssertLessThan(ColorMath.contrast(light.hover, light.canvas), 1.5)
        // Text derived for a light canvas must be dark.
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(light.primary, light.canvas), 4.5
        )
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(light.onAccent, light.actionBlue), 4.5
        )
    }

    func testButtonTextMeetsSmallTextContrastOnItsOwnFill() {
        let palette = AppThemePalette.ayuDark

        // Ayu's upstream button.foreground (#765B24) sits at 3.3:1 on the
        // gold fill; the import must darken it to AA without discarding the
        // bronze hue for plain black.
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.onAccent, palette.actionBlue), 4.5
        )
        XCTAssertNotEqual(palette.onAccent, 0x000000)
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.badgeText, palette.badgeBlue), 4.5
        )
    }

    func testDestructiveButtonKeepsWhiteTextReadable() {
        let palette = AppThemePalette.importing([
            "editor.background": "#FFFFFF",
            "gitDecoration.deletedResourceForeground": "#FF9999"
        ])

        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(0xFFFFFF, palette.destructiveButton), 4.5
        )
        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.onDestructive, palette.readableDestructiveButton),
            4.5
        )
    }

    func testStoredDestructiveFillIsClampedWhenRead() {
        // Palettes saved before the 4.5:1 floor kept fills that only white
        // text at 3.0:1 could read; the read-time accessor must re-darken.
        var palette = AppThemePalette.oneDark
        palette.destructiveButton = 0xF26D78

        XCTAssertGreaterThanOrEqual(
            ColorMath.contrast(palette.onDestructive, palette.readableDestructiveButton),
            4.5
        )
    }

    func testVSIXImportsColorThemesAndIconPacks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KvistIconPackTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let package = base.appendingPathComponent("pkg", isDirectory: true)
        let extensionDir = package.appendingPathComponent("extension", isDirectory: true)
        let iconsDir = extensionDir.appendingPathComponent("icons", isDirectory: true)
        try FileManager.default.createDirectory(
            at: iconsDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: base) }

        try """
        {
          "contributes": {
            "themes": [
              { "label": "Test Dark", "path": "./theme.json" }
            ],
            "iconThemes": [
              { "id": "test-icons", "label": "Test Icons", "path": "./icons/icons.json" }
            ]
          }
        }
        """.write(
            to: extensionDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        { "colors": { "editor.background": "#101820", "editor.foreground": "#F0F1F2" } }
        """.write(
            to: extensionDir.appendingPathComponent("theme.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "iconDefinitions": {
            "_file": { "iconPath": "./file.svg" },
            "_swift": { "iconPath": "./swift.svg" },
            "_folder": { "iconPath": "./folder.svg" },
            "_font_icon": { "fontCharacter": "\\uE001" }
          },
          "file": "_file",
          "folder": "_folder",
          "fileExtensions": { "swift": "_swift", "spec.ts": "_file" },
          "fileNames": { "package.json": "_file" }
        }
        """.write(
            to: iconsDir.appendingPathComponent("icons.json"),
            atomically: true,
            encoding: .utf8
        )
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"
        for name in ["file.svg", "swift.svg", "folder.svg"] {
            try svg.write(
                to: iconsDir.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        let archive = base.appendingPathComponent("pkg.vsix")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", package.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        let iconPacksRoot = base.appendingPathComponent("packs", isDirectory: true)
        let content = try EditorThemeImporter.importVSIX(
            at: archive,
            publisher: "pub",
            extensionName: "ext",
            license: "MIT",
            licenseURL: nil,
            sourceURL: nil,
            iconPacksRoot: iconPacksRoot
        )

        XCTAssertEqual(content.themes.count, 1)
        XCTAssertEqual(content.themes[0].palette.canvas, 0x101820)

        XCTAssertEqual(content.iconPacks.count, 1)
        let pack = content.iconPacks[0]
        XCTAssertEqual(pack.name, "Test Icons")
        XCTAssertNotNil(pack.defaultFileIcon)
        XCTAssertNotNil(pack.folderIcon)
        XCTAssertNotNil(pack.iconsByExtension["swift"])
        XCTAssertNotNil(pack.iconsByExtension["spec.ts"])
        XCTAssertNotNil(pack.iconsByFileName["package.json"])
        let packDirectory = iconPacksRoot.appendingPathComponent(pack.directoryName)
        for file in [pack.defaultFileIcon, pack.folderIcon, pack.iconsByExtension["swift"]] {
            let copied = packDirectory.appendingPathComponent(try XCTUnwrap(file))
            XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        }
    }

    func testLocalJSONImportSupportsCommentsIncludesAndTrailingCommas() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KvistThemeTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let baseURL = directory.appendingPathComponent("base.json")
        let themeURL = directory.appendingPathComponent("example.json")
        try """
        {
          "colors": {
            "editor.background": "#112233",
            "editor.foreground": "#DDEEFF"
          }
        }
        """.write(to: baseURL, atomically: true, encoding: .utf8)
        try """
        {
          // Editor theme files commonly use JSON with comments.
          "include": "./base.json",
          "colors": {
            "button.background": "#445566",
          },
        }
        """.write(to: themeURL, atomically: true, encoding: .utf8)

        let theme = try EditorThemeImporter.importJSON(at: themeURL)

        XCTAssertEqual(theme.name, "example")
        XCTAssertEqual(theme.palette.canvas, 0x112233)
        XCTAssertEqual(theme.palette.primary, 0xDDEEFF)
        XCTAssertEqual(theme.palette.actionBlue, 0x445566)
    }
}

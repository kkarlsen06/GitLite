#!/usr/bin/env swift

import Foundation

struct BundledIconPackManifest: Codable {
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

private func stableIdentifier(for value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: vendor_material_icon_theme.swift <upstream-root> <output-directory>")
}

let fileManager = FileManager.default
let upstreamRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    .standardizedFileURL
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    .standardizedFileURL
let themeURL = upstreamRoot.appendingPathComponent("dist/material-icons.json")
let packageURL = upstreamRoot.appendingPathComponent("package.json")

guard let packageData = try? Data(contentsOf: packageURL),
      let package = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
      package["version"] as? String == "5.37.0" else {
    fail("expected a Material Icon Theme v5.37.0 checkout")
}

guard let data = try? Data(contentsOf: themeURL),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let definitions = object["iconDefinitions"] as? [String: Any] else {
    fail("generate dist/material-icons.json in the pinned upstream checkout first")
}

var pathsByIconID: [String: String] = [:]
for (iconID, value) in definitions {
    if let detail = value as? [String: Any],
       let iconPath = detail["iconPath"] as? String {
        pathsByIconID[iconID] = iconPath
    }
}

func iconIDMap(_ key: String) -> [String: String] {
    guard let raw = object[key] as? [String: Any] else { return [:] }
    return raw.reduce(into: [:]) { map, item in
        if let iconID = item.value as? String {
            map[item.key.lowercased()] = iconID
        }
    }
}

let extensionIcons = iconIDMap("fileExtensions")
let fileNameIcons = iconIDMap("fileNames")
let defaultFileIcon = object["file"] as? String
let folderIcon = object["folder"] as? String
let folderExpandedIcon = object["folderExpanded"] as? String

var neededIconIDs = Set(extensionIcons.values).union(fileNameIcons.values)
for iconID in [defaultFileIcon, folderIcon, folderExpandedIcon] {
    if let iconID { neededIconIDs.insert(iconID) }
}

try? fileManager.removeItem(at: output)
do {
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
} catch {
    fail("cannot create output directory: \(error.localizedDescription)")
}

let resolvedRoot = upstreamRoot.resolvingSymlinksInPath().path
var copiedFileByIconID: [String: String] = [:]
for iconID in neededIconIDs.sorted() {
    guard let iconPath = pathsByIconID[iconID] else { continue }
    let source = themeURL.deletingLastPathComponent()
        .appendingPathComponent(iconPath)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    guard source.path.hasPrefix(resolvedRoot + "/") else { continue }
    let fileExtension = source.pathExtension.lowercased()
    guard fileExtension == "svg" || fileExtension == "png" else { continue }
    let fileName = "\(stableIdentifier(for: iconID)).\(fileExtension)"
    do {
        try fileManager.copyItem(
            at: source,
            to: output.appendingPathComponent(fileName)
        )
        copiedFileByIconID[iconID] = fileName
    } catch {
        fail("cannot copy \(source.lastPathComponent): \(error.localizedDescription)")
    }
}

func resolved(_ map: [String: String]) -> [String: String] {
    map.compactMapValues { copiedFileByIconID[$0] }
}

let manifest = BundledIconPackManifest(
    id: "builtin.material-icon-theme",
    name: "Material Icon Theme",
    publisher: "PKief",
    license: "MIT",
    licenseURL: URL(
        string: "https://github.com/material-extensions/vscode-material-icon-theme/blob/v5.37.0/LICENSE"
    ),
    sourceURL: URL(
        string: "https://github.com/material-extensions/vscode-material-icon-theme/tree/v5.37.0"
    ),
    directoryName: "MaterialIconTheme",
    iconsByExtension: resolved(extensionIcons),
    iconsByFileName: resolved(fileNameIcons),
    defaultFileIcon: defaultFileIcon.flatMap { copiedFileByIconID[$0] },
    folderIcon: folderIcon.flatMap { copiedFileByIconID[$0] },
    folderExpandedIcon: folderExpandedIcon.flatMap { copiedFileByIconID[$0] }
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
do {
    let manifestData = try encoder.encode(manifest)
    try manifestData.write(
        to: output.appendingPathComponent("manifest.json"),
        options: .atomic
    )
} catch {
    fail("cannot write bundled manifest: \(error.localizedDescription)")
}

print(
    "Vendored \(copiedFileByIconID.count) icons, "
        + "\(manifest.iconsByExtension.count) extensions, and "
        + "\(manifest.iconsByFileName.count) file names."
)

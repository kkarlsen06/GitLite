import AppKit
import SwiftUI

/// Exact SVG geometry from Microsoft's Visual Studio Code Codicons set.
///
/// Source: https://github.com/microsoft/vscode-codicons/tree/main/src/icons
/// License: CC BY 4.0. See THIRD_PARTY_NOTICES.
enum Codicon: String, CaseIterable {
    case gitBranch
    case target
    case repoFetch
    case repoPull
    case repoPush
    case sync
    case check

    var svg: String {
        switch self {
        case .gitBranch:
            return #"<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M14 5.5C14 4.121 12.879 3 11.5 3C10.121 3 9 4.121 9 5.5C9 6.682 9.826 7.669 10.93 7.928C10.744 8.546 10.177 9 9.5 9H6.5C5.935 9 5.419 9.195 5 9.512V4.949C6.14 4.717 7 3.707 7 2.5C7 1.121 5.879 0 4.5 0C3.121 0 2 1.121 2 2.5C2 3.708 2.86 4.717 4 4.949V11.05C2.86 11.282 2 12.292 2 13.499C2 14.878 3.121 15.999 4.5 15.999C5.879 15.999 7 14.878 7 13.499C7 12.317 6.174 11.33 5.07 11.071C5.256 10.453 5.823 9.999 6.5 9.999H9.5C10.723 9.999 11.74 9.115 11.954 7.953C13.116 7.738 14 6.723 14 5.5ZM3 2.5C3 1.673 3.673 1 4.5 1C5.327 1 6 1.673 6 2.5C6 3.327 5.327 4 4.5 4C3.673 4 3 3.327 3 2.5ZM6 13.5C6 14.327 5.327 15 4.5 15C3.673 15 3 14.327 3 13.5C3 12.673 3.673 12 4.5 12C5.327 12 6 12.673 6 13.5ZM11.5 7C10.673 7 10 6.327 10 5.5C10 4.673 10.673 4 11.5 4C12.327 4 13 4.673 13 5.5C13 6.327 12.327 7 11.5 7Z"/></svg>"#
        case .target:
            return #"<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M9 8C9 8.552 8.552 9 8 9C7.448 9 7 8.552 7 8C7 7.448 7.448 7 8 7C8.552 7 9 7.448 9 8ZM12 8C12 10.209 10.209 12 8 12C5.791 12 4 10.209 4 8C4 5.791 5.791 4 8 4C10.209 4 12 5.791 12 8ZM11 8C11 6.343 9.657 5 8 5C6.343 5 5 6.343 5 8C5 9.657 6.343 11 8 11C9.657 11 11 9.657 11 8ZM15 8C15 11.866 11.866 15 8 15C4.134 15 1 11.866 1 8C1 4.134 4.134 1 8 1C11.866 1 15 4.134 15 8ZM14 8C14 4.686 11.314 2 8 2C4.686 2 2 4.686 2 8C2 11.314 4.686 14 8 14C11.314 14 14 11.314 14 8Z"/></svg>"#
        case .repoFetch:
            return #"<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M7.5 3C7.776 3 8 2.776 8 2.5V1.5C8 1.224 7.776 1 7.5 1C7.224 1 7 1.224 7 1.5V2.5C7 2.776 7.224 3 7.5 3Z"/><path d="M7.5 10C7.372 10 7.245 9.95 7.15 9.85L4.15 6.85C4.05 6.755 4 6.628 4 6.5C4 6.372 4.05 6.245 4.15 6.15C4.245 6.05 4.373 6 4.5 6C4.627 6 4.755 6.05 4.85 6.15L7 8.29V7.5C7 7.22 7.22 7 7.5 7C7.78 7 8 7.22 8 7.5V8.29L10.15 6.15C10.245 6.05 10.372 6 10.5 6C10.628 6 10.755 6.05 10.85 6.15C10.95 6.245 11 6.373 11 6.5C11 6.627 10.95 6.755 10.85 6.85L7.85 9.85C7.755 9.95 7.628 10 7.5 10Z"/><path fill-rule="evenodd" clip-rule="evenodd" d="M9.95 13H12.5C12.78 13 13 13.22 13 13.5C13 13.78 12.78 14 12.5 14H9.95C9.72 15.14 8.71 16 7.5 16C6.29 16 5.28 15.14 5.05 14H2.5C2.22 14 2 13.78 2 13.5C2 13.22 2.22 13 2.5 13H5.05C5.28 11.86 6.29 11 7.5 11C8.71 11 9.72 11.86 9.95 13ZM7.5 15C8.15 15 8.71 14.58 8.91 14C8.97 13.84 9 13.68 9 13.5C9 13.32 8.97 13.16 8.91 13C8.71 12.42 8.15 12 7.5 12C6.85 12 6.29 12.42 6.09 13C6.03 13.16 6 13.32 6 13.5C6 13.68 6.03 13.84 6.09 14C6.29 14.58 6.85 15 7.5 15Z"/><path d="M8 5.5C8 5.776 7.776 6 7.5 6C7.224 6 7 5.776 7 5.5V4.5C7 4.224 7.224 4 7.5 4C7.776 4 8 4.224 8 4.5V5.5Z"/></svg>"#
        case .repoPull:
            return #"<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M4.85 6.15C4.755 6.05 4.627 6 4.5 6C4.372 6 4.245 6.05 4.15 6.15C4.05 6.245 4 6.373 4 6.5C4 6.627 4.05 6.755 4.15 6.85L7.15 9.85C7.245 9.95 7.372 10 7.5 10C7.628 10 7.755 9.95 7.85 9.85L10.85 6.85C10.95 6.755 11 6.628 11 6.5C11 6.372 10.95 6.245 10.85 6.15C10.755 6.05 10.627 6 10.5 6C10.373 6 10.245 6.05 10.15 6.15L8 8.29V1.5C8 1.22 7.78 1 7.5 1C7.22 1 7 1.22 7 1.5V8.29L4.85 6.15Z"/><path fill-rule="evenodd" clip-rule="evenodd" d="M9.95 13H12.5C12.78 13 13 13.22 13 13.5C13 13.78 12.78 14 12.5 14H9.95C9.72 15.14 8.71 16 7.5 16C6.29 16 5.28 15.14 5.05 14H2.5C2.22 14 2 13.78 2 13.5C2 13.22 2.22 13 2.5 13H5.05C5.28 11.86 6.29 11 7.5 11C8.71 11 9.72 11.86 9.95 13ZM6.09 14C6.29 14.58 6.85 15 7.5 15C8.15 15 8.71 14.58 8.91 14C8.97 13.84 9 13.68 9 13.5C9 13.32 8.97 13.16 8.91 13C8.71 12.42 8.15 12 7.5 12C6.85 12 6.29 12.42 6.09 13C6.03 13.16 6 13.32 6 13.5C6 13.68 6.03 13.84 6.09 14Z"/></svg>"#
        case .repoPush:
            return #"<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M4.85 4.85C4.755 4.95 4.627 5 4.5 5C4.372 5 4.245 4.95 4.15 4.85C4.05 4.755 4 4.627 4 4.5C4 4.373 4.05 4.245 4.15 4.15L7.15 1.15C7.245 1.05 7.372 1 7.5 1C7.628 1 7.755 1.05 7.85 1.15L10.85 4.15C10.95 4.245 11 4.372 11 4.5C11 4.628 10.95 4.755 10.85 4.85C10.755 4.95 10.627 5 10.5 5C10.373 5 10.245 4.95 10.15 4.85L8 2.71V9.5C8 9.78 7.78 10 7.5 10C7.22 10 7 9.78 7 9.5V2.71L4.85 4.85Z"/><path fill-rule="evenodd" clip-rule="evenodd" d="M9.95 13H12.5C12.78 13 13 13.22 13 13.5C13 13.78 12.78 14 12.5 14H9.95C9.72 15.14 8.71 16 7.5 16C6.29 16 5.28 15.14 5.05 14H2.5C2.22 14 2 13.78 2 13.5C2 13.22 2.22 13 2.5 13H5.05C5.28 11.86 6.29 11 7.5 11C8.71 11 9.72 11.86 9.95 13ZM6.09 14C6.29 14.58 6.85 15 7.5 15C8.15 15 8.71 14.58 8.91 14C8.97 13.84 9 13.68 9 13.5C9 13.32 8.97 13.16 8.91 13C8.71 12.42 8.15 12 7.5 12C6.85 12 6.29 12.42 6.09 13C6.03 13.16 6 13.32 6 13.5C6 13.68 6.03 13.84 6.09 14Z"/></svg>"#
        case .sync:
            return #"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M14 3.5V6.5C14 6.78 13.78 7 13.5 7H10.5C10.22 7 9.99999 6.78 9.99999 6.5C9.99999 6.22 10.22 6 10.5 6H12.58C11.78 4.17 10.01 3 7.99999 3C5.77999 3 3.79999 4.5 3.18999 6.64C3.12999 6.86 2.92999 7 2.70999 7C2.65999 7 2.61999 7 2.56999 6.98C2.29999 6.9 2.14999 6.63 2.22999 6.36C2.95999 3.79 5.32999 2 7.99999 2C10.05 2 11.91 3.02 13 4.69V3.5C13 3.22 13.22 3 13.5 3C13.78 3 14 3.22 14 3.5ZM13.42 9.02C13.16 8.95 12.88 9.1 12.8 9.37C12.19 11.51 10.22 13.01 7.98999 13.01C5.97999 13.01 4.20999 11.84 3.40999 10.01H5.48999C5.76999 10.01 5.98999 9.79 5.98999 9.51C5.98999 9.23 5.76999 9.01 5.48999 9.01H2.48999C2.20999 9.01 1.98999 9.23 1.98999 9.51V12.51C1.98999 12.79 2.20999 13.01 2.48999 13.01C2.76999 13.01 2.98999 12.79 2.98999 12.51V11.32C4.07999 12.98 5.93999 14.01 7.98999 14.01C10.66 14.01 13.03 12.22 13.76 9.65C13.84 9.38 13.68 9.11 13.41 9.03L13.42 9.02Z"/></svg>"#
        case .check:
            return #"<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M13.6572 3.13573C13.8583 2.9465 14.175 2.95614 14.3643 3.15722C14.5535 3.35831 14.5438 3.675 14.3428 3.86425L5.84277 11.8642C5.64597 12.0494 5.33756 12.0446 5.14648 11.8535L1.64648 8.35351C1.45121 8.15824 1.45121 7.84174 1.64648 7.64647C1.84174 7.45121 2.15825 7.45121 2.35351 7.64647L5.50976 10.8027L13.6572 3.13573Z"/></svg>"#
        }
    }
}

struct CodiconGlyph: View {
    let icon: Codicon
    var size: CGFloat = 16
    var color: Color?

    var body: some View {
        if let image = CodiconImage.image(for: icon, color: color) {
            Image(nsImage: image)
                .renderingMode(color == nil ? .template : .original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

@MainActor
private enum CodiconImage {
    private static var cache: [Codicon: NSImage] = [:]
    private static var colorCache: [Codicon: [UInt32: NSImage]] = [:]

    static func image(for icon: Codicon, color: Color? = nil) -> NSImage? {
        if let color, let rgb = rgbValue(for: color) {
            if let cached = colorCache[icon]?[rgb] { return cached }
            let fill = String(format: "#%06X", rgb)
            let svg = icon.svg.replacingOccurrences(of: "currentColor", with: fill)
            guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
            image.isTemplate = false
            colorCache[icon, default: [:]][rgb] = image
            return image
        }

        if let cached = cache[icon] { return cached }
        guard let image = NSImage(data: Data(icon.svg.utf8)) else { return nil }
        image.isTemplate = true
        cache[icon] = image
        return image
    }

    private static func rgbValue(for color: Color) -> UInt32? {
        guard let resolved = NSColor(color).usingColorSpace(.deviceRGB) else {
            return nil
        }
        let red = UInt32((resolved.redComponent * 255).rounded())
        let green = UInt32((resolved.greenComponent * 255).rounded())
        let blue = UInt32((resolved.blueComponent * 255).rounded())
        return red << 16 | green << 8 | blue
    }
}

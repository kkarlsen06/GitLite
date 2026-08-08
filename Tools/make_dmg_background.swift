import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift make_dmg_background.swift OUTPUT.png\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

// 540x380pt window, rendered at @2x. The point size assigned below writes
// 144-dpi metadata into the PNG so Finder draws it at window scale.
let pointSize = NSSize(width: 540, height: 380)
guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1080,
        pixelsHigh: 760,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fputs("Could not create background canvas.\n", stderr)
    exit(1)
}
bitmap.size = pointSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let scaleToPixels = NSAffineTransform()
scaleToPixels.scale(by: 2)
scaleToPixels.concat()

// A light background keeps Finder's black icon labels legible in light mode.
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.925, green: 0.935, blue: 0.955, alpha: 1),
    ending: NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.982, alpha: 1)
)
gradient?.draw(in: NSRect(origin: .zero, size: pointSize), angle: 90)

// The same codicon "git-branch" glyph as make_icon.swift (CC BY 4.0, see
// THIRD_PARTY_NOTICES), centered above the icon row as a small wordmark.
let glyphScale: CGFloat = 3.5
let glyphCenter = NSPoint(x: 270, y: 312)
let branch = NSBezierPath()
branch.appendOval(in: NSRect(x: 2.5, y: 0.5, width: 4, height: 4))
branch.appendOval(in: NSRect(x: 2.5, y: 11.5, width: 4, height: 4))
branch.appendOval(in: NSRect(x: 9.5, y: 3.5, width: 4, height: 4))
branch.move(to: NSPoint(x: 4.5, y: 4.5))
branch.line(to: NSPoint(x: 4.5, y: 11.5))
branch.move(to: NSPoint(x: 4.5, y: 9.5))
branch.line(to: NSPoint(x: 9.5, y: 9.5))
branch.appendArc(
    withCenter: NSPoint(x: 9.5, y: 7.5),
    radius: 2,
    startAngle: 90,
    endAngle: 0,
    clockwise: true
)
var glyphTransform = AffineTransform(
    translationByX: glyphCenter.x - 8 * glyphScale,
    byY: glyphCenter.y + 8 * glyphScale
)
glyphTransform.scale(x: glyphScale, y: -glyphScale)
branch.transform(using: glyphTransform)
branch.lineWidth = 1.1 * glyphScale
branch.lineCapStyle = .round
branch.lineJoinStyle = .round
NSColor(calibratedRed: 0.18, green: 0.55, blue: 1.0, alpha: 1).setStroke()
branch.stroke()

// Arrow between the app icon (window 140,180) and the Applications link
// (window 400,180); window y 180 is image y 200 in this flipped context.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 226, y: 200))
arrow.line(to: NSPoint(x: 310, y: 200))
arrow.move(to: NSPoint(x: 297, y: 214))
arrow.line(to: NSPoint(x: 313, y: 200))
arrow.line(to: NSPoint(x: 297, y: 186))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(calibratedWhite: 0.44, alpha: 1).setStroke()
arrow.stroke()

let caption = NSAttributedString(
    string: "Drag Kvist into Applications to install",
    attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
    ]
)
caption.draw(at: NSPoint(x: 270 - caption.size().width / 2, y: 44))

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render background.\n", stderr)
    exit(1)
}

try png.write(to: outputURL)

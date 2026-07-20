import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift make_icon.swift OUTPUT.png\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1024,
        pixelsHigh: 1024,
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
    fputs("Could not create icon canvas.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let outer = NSBezierPath(
    roundedRect: NSRect(x: 36, y: 36, width: 952, height: 952),
    xRadius: 220,
    yRadius: 220
)
NSColor(calibratedRed: 0.055, green: 0.067, blue: 0.09, alpha: 1).setFill()
outer.fill()

let inner = NSBezierPath(
    roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
    xRadius: 180,
    yRadius: 180
)
NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.125, alpha: 1).setFill()
inner.fill()

// The VS Code codicon "git-branch" (CC BY 4.0, see THIRD_PARTY_NOTICES),
// same 16pt design-space coordinates as BranchGlyph in Views.swift. The
// codicon is authored with a top-left origin, so the transform flips it
// into this context's bottom-left coordinate system.
let scale: CGFloat = 44
let offset = (1024 - 16 * scale) / 2
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
var transform = AffineTransform(translationByX: offset, byY: offset + 16 * scale)
transform.scale(x: scale, y: -scale)
branch.transform(using: transform)
branch.lineWidth = 1.1 * scale
branch.lineCapStyle = .round
branch.lineJoinStyle = .round
NSColor(calibratedRed: 0.18, green: 0.55, blue: 1.0, alpha: 1).setStroke()
branch.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon.\n", stderr)
    exit(1)
}

try png.write(to: outputURL)

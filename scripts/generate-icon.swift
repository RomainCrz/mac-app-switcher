#!/usr/bin/env swift

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = root.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSpecs: [(points: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

for spec in iconSpecs {
    let pixels = spec.points * spec.scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    rect.fill()

    let cornerRadius = CGFloat(pixels) * 0.225
    let iconRect = rect.insetBy(dx: CGFloat(pixels) * 0.055, dy: CGFloat(pixels) * 0.055)
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.current?.saveGraphicsState()
    iconPath.addClip()

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.18, alpha: 1.0),
        NSColor(calibratedRed: 0.17, green: 0.22, blue: 0.34, alpha: 1.0),
        NSColor(calibratedRed: 0.40, green: 0.27, blue: 0.45, alpha: 1.0)
    ])
    background?.draw(in: iconRect, angle: 45)

    let glowRect = NSRect(
        x: CGFloat(pixels) * 0.05,
        y: CGFloat(pixels) * 0.50,
        width: CGFloat(pixels) * 0.90,
        height: CGFloat(pixels) * 0.42
    )
    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 0.39, green: 0.72, blue: 1.00, alpha: 0.45),
        NSColor(calibratedRed: 0.83, green: 0.42, blue: 0.72, alpha: 0.18),
        NSColor.clear
    ])
    glow?.draw(in: glowRect, angle: -20)

    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    iconPath.lineWidth = max(1, CGFloat(pixels) * 0.010)
    iconPath.stroke()

    let barRect = NSRect(
        x: CGFloat(pixels) * 0.15,
        y: CGFloat(pixels) * 0.58,
        width: CGFloat(pixels) * 0.70,
        height: CGFloat(pixels) * 0.20
    )
    let barPath = NSBezierPath(roundedRect: barRect, xRadius: barRect.height / 2, yRadius: barRect.height / 2)
    NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
    barPath.fill()
    NSColor(calibratedWhite: 1, alpha: 0.24).setStroke()
    barPath.lineWidth = max(1, CGFloat(pixels) * 0.006)
    barPath.stroke()

    let dotColors: [NSColor] = [
        NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.25, alpha: 1.0),
        NSColor(calibratedRed: 0.36, green: 0.78, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 0.56, green: 0.92, blue: 0.48, alpha: 1.0),
        NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.72, alpha: 1.0),
        NSColor(calibratedRed: 0.70, green: 0.63, blue: 1.00, alpha: 1.0)
    ]

    let dotDiameter = CGFloat(pixels) * 0.095
    let spacing = CGFloat(pixels) * 0.026
    let totalWidth = dotDiameter * CGFloat(dotColors.count) + spacing * CGFloat(dotColors.count - 1)
    var x = rect.midX - totalWidth / 2
    let y = barRect.midY - dotDiameter / 2

    for color in dotColors {
        let dotRect = NSRect(x: x, y: y, width: dotDiameter, height: dotDiameter)
        let dotPath = NSBezierPath(roundedRect: dotRect, xRadius: dotDiameter * 0.25, yRadius: dotDiameter * 0.25)
        color.setFill()
        dotPath.fill()
        NSColor(calibratedWhite: 1, alpha: 0.55).setStroke()
        dotPath.lineWidth = max(0.5, CGFloat(pixels) * 0.004)
        dotPath.stroke()
        x += dotDiameter + spacing
    }

    let arrowColor = NSColor(calibratedWhite: 1, alpha: 0.72)
    arrowColor.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = max(1.2, CGFloat(pixels) * 0.014)
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: CGFloat(pixels) * 0.38, y: CGFloat(pixels) * 0.37))
    arrow.line(to: NSPoint(x: CGFloat(pixels) * 0.50, y: CGFloat(pixels) * 0.27))
    arrow.line(to: NSPoint(x: CGFloat(pixels) * 0.62, y: CGFloat(pixels) * 0.37))
    arrow.stroke()

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render \(spec.name)")
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(spec.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fatalError("iconutil failed")
}

print("Generated \(icnsURL.path)")

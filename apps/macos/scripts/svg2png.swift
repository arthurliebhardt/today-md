import AppKit
import Foundation

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let svgPath = projectDir.appendingPathComponent("docs/appicon.svg")
let outputDir = projectDir.appendingPathComponent("today-md/Assets.xcassets/AppIcon.appiconset")

guard let svgData = try? Data(contentsOf: svgPath),
      let svgImage = NSImage(data: svgData) else {
    print("Failed to load SVG from \(svgPath.path)")
    exit(1)
}

for size in sizes {
    let px = size.px
    // Use NSBitmapImageRep directly to avoid Retina 2x scaling
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px) // 1:1 pixel-to-point

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    svgImage.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
                  from: NSRect(origin: .zero, size: svgImage.size),
                  operation: .copy,
                  fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(size.name)")
        continue
    }

    let outputPath = outputDir.appendingPathComponent("\(size.name).png")
    do {
        try pngData.write(to: outputPath)
        print("Created \(size.name).png (\(px)x\(px))")
    } catch {
        print("Failed to write \(outputPath.path): \(error)")
    }
}

print("Done!")

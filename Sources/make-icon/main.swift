import AppKit
import CoreGraphics
import Foundation

// Draws the Hark app icon and writes PNGs for iconutil.
//
//   make-icon <output-directory>
//
// Concept: two stacked speech waveforms in two colours — the two speakers Hark
// separates. At 16pt it reads as a clean abstract mark; up close it's a
// conversation. Warm ink-on-paper palette rather than the usual tech blue.

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("icon.iconset")

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Relative bar heights for the two voices. Deliberately irregular so it reads
/// as speech rather than a bar chart, and the two rows never mirror each other.
///
/// Five bars, not eight: at 32pt and below, eight rounded bars per row blur into
/// a single smudge. Verified by rendering and looking at it.
let voiceA: [CGFloat] = [0.34, 0.78, 1.00, 0.52, 0.66]
let voiceB: [CGFloat] = [0.62, 0.38, 0.84, 1.00, 0.44]

func draw(size: CGFloat) -> CGImage? {
    let scale = size / 1024.0
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Rounded-square background with a warm vertical gradient.
    let inset = 62.0 * scale
    let body = rect.insetBy(dx: inset, dy: inset)
    let corner = 228.0 * scale
    let squircle = CGPath(
        roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil
    )

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.16, green: 0.15, blue: 0.20, alpha: 1),
            CGColor(red: 0.09, green: 0.09, blue: 0.12, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: []
    )
    ctx.restoreGState()

    // Two rows of rounded bars: the two voices.
    let barWidth = 112.0 * scale
    let gap = 54.0 * scale
    let count = voiceA.count
    let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
    let startX = rect.midX - totalWidth / 2
    let maxBar = 224.0 * scale
    let rowGap = 82.0 * scale
    let centerY = rect.midY

    func drawRow(_ heights: [CGFloat], baseY: CGFloat, upward: Bool, color: CGColor) {
        ctx.setFillColor(color)
        for (i, h) in heights.enumerated() {
            let barHeight = max(barWidth, maxBar * h)
            let x = startX + CGFloat(i) * (barWidth + gap)
            let y = upward ? baseY : baseY - barHeight
            let r = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            ctx.addPath(CGPath(
                roundedRect: r, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
                transform: nil
            ))
            ctx.fillPath()
        }
    }

    // Warm amber above, cool sky below — two distinct voices, high contrast on dark.
    drawRow(
        voiceA, baseY: centerY + rowGap / 2, upward: true,
        color: CGColor(red: 0.98, green: 0.72, blue: 0.32, alpha: 1)
    )
    drawRow(
        voiceB, baseY: centerY - rowGap / 2, upward: false,
        color: CGColor(red: 0.46, green: 0.78, blue: 0.94, alpha: 1)
    )

    return ctx.makeImage()
}

// The sizes iconutil expects in an .iconset.
let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for spec in specs {
    guard let image = draw(size: spec.px) else {
        FileHandle.standardError.write(Data("failed to draw \(spec.name)\n".utf8))
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: spec.px, height: spec.px)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try data.write(to: outDir.appendingPathComponent("\(spec.name).png"))
}

print(outDir.path)

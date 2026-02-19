#!/usr/bin/env swift

import AppKit

// --- Configuration ---
let iconSize = 1024
let outputDir = "Resources"
let iconsetName = "AppIcon.iconset"
let icnsName = "AppIcon.icns"

let sizes: [(name: String, size: Int)] = [
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

// --- Drawing ---
// Draw directly into a CGContext with exact pixel dimensions (avoids Retina 2x scaling)
func drawIcon(into ctx: CGContext, pixelSize: Int) {
    let size = CGFloat(pixelSize)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Rounded-rect clipping (macOS icon shape — ~18.5% corner radius)
    let cornerRadius = size * 0.185
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Sky gradient (bottom-left to top-right: warm orange → blue)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1.0), // warm orange
        CGColor(red: 0.90, green: 0.45, blue: 0.45, alpha: 1.0), // pink-red
        CGColor(red: 0.45, green: 0.55, blue: 0.80, alpha: 1.0), // soft blue
        CGColor(red: 0.25, green: 0.40, blue: 0.75, alpha: 1.0), // deep blue
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.35, 0.7, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size, y: size),
            options: []
        )
    }

    // Sun glow — a radial gradient circle
    let sunCenter = CGPoint(x: size * 0.5, y: size * 0.38)
    let sunRadius = size * 0.18
    let sunColors = [
        CGColor(red: 1.0, green: 0.85, blue: 0.50, alpha: 0.9),
        CGColor(red: 1.0, green: 0.70, blue: 0.40, alpha: 0.3),
        CGColor(red: 1.0, green: 0.60, blue: 0.35, alpha: 0.0),
    ] as CFArray
    let sunLocations: [CGFloat] = [0.0, 0.5, 1.0]

    if let sunGradient = CGGradient(colorsSpace: colorSpace, colors: sunColors, locations: sunLocations) {
        ctx.drawRadialGradient(
            sunGradient,
            startCenter: sunCenter, startRadius: 0,
            endCenter: sunCenter, endRadius: sunRadius * 2.5,
            options: []
        )
    }

    // Mountain silhouette (back range — darker, taller)
    ctx.setFillColor(CGColor(red: 0.18, green: 0.20, blue: 0.30, alpha: 0.85))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: -size * 0.05, y: size * 0.18))
    ctx.addLine(to: CGPoint(x: size * 0.15, y: size * 0.52))
    ctx.addLine(to: CGPoint(x: size * 0.28, y: size * 0.42))
    ctx.addLine(to: CGPoint(x: size * 0.45, y: size * 0.62))
    ctx.addLine(to: CGPoint(x: size * 0.55, y: size * 0.55))
    ctx.addLine(to: CGPoint(x: size * 0.72, y: size * 0.68))
    ctx.addLine(to: CGPoint(x: size * 0.85, y: size * 0.48))
    ctx.addLine(to: CGPoint(x: size * 1.05, y: size * 0.55))
    ctx.addLine(to: CGPoint(x: size * 1.05, y: -size * 0.05))
    ctx.addLine(to: CGPoint(x: -size * 0.05, y: -size * 0.05))
    ctx.closePath()
    ctx.fillPath()

    // Mountain silhouette (front range — darker, shorter)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.13, blue: 0.20, alpha: 0.95))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: -size * 0.05, y: size * 0.10))
    ctx.addLine(to: CGPoint(x: size * 0.20, y: size * 0.38))
    ctx.addLine(to: CGPoint(x: size * 0.35, y: size * 0.28))
    ctx.addLine(to: CGPoint(x: size * 0.50, y: size * 0.42))
    ctx.addLine(to: CGPoint(x: size * 0.65, y: size * 0.32))
    ctx.addLine(to: CGPoint(x: size * 0.80, y: size * 0.40))
    ctx.addLine(to: CGPoint(x: size * 1.05, y: size * 0.25))
    ctx.addLine(to: CGPoint(x: size * 1.05, y: -size * 0.05))
    ctx.addLine(to: CGPoint(x: -size * 0.05, y: -size * 0.05))
    ctx.closePath()
    ctx.fillPath()
}

func renderPNG(pixelSize: Int) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext for size \(pixelSize)")
    }

    drawIcon(into: ctx, pixelSize: pixelSize)

    guard let cgImage = ctx.makeImage() else {
        fatalError("Failed to create CGImage for size \(pixelSize)")
    }

    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    bitmap.size = NSSize(width: pixelSize, height: pixelSize) // 72 DPI
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to create PNG data for size \(pixelSize)")
    }
    return pngData
}

// --- Main ---
let fm = FileManager.default

// Create iconset directory
let iconsetPath = "\(outputDir)/\(iconsetName)"
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// Generate all sizes (each drawn at exact pixel dimensions)
for entry in sizes {
    let filePath = "\(iconsetPath)/\(entry.name).png"
    let pngData = renderPNG(pixelSize: entry.size)
    try! pngData.write(to: URL(fileURLWithPath: filePath))
    print("  \(entry.name).png (\(entry.size)x\(entry.size))")
}

// Run iconutil to create .icns
let icnsPath = "\(outputDir)/\(icnsName)"
try? fm.removeItem(atPath: icnsPath)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

// Clean up iconset
try? fm.removeItem(atPath: iconsetPath)

print("Generated \(icnsPath)")

#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let preview = resources.appendingPathComponent("AppIcon.png")
let output = resources.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.saveGState()
    context.scaleBy(x: size / 1024, y: size / 1024)

    let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    context.clear(bounds)

    let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 36, dy: 36), xRadius: 218, yRadius: 218)
    outer.addClip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(0x0a6f83).cgColor,
            color(0x122e4a).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 180, y: 960),
        end: CGPoint(x: 850, y: 80),
        options: []
    )
    let starColor = color(0xe4fbff, alpha: 0.46)
    for star in [
        CGRect(x: 185, y: 772, width: 12, height: 12),
        CGRect(x: 260, y: 820, width: 7, height: 7),
        CGRect(x: 792, y: 742, width: 10, height: 10),
        CGRect(x: 835, y: 672, width: 6, height: 6),
        CGRect(x: 712, y: 835, width: 8, height: 8)
    ] {
        drawRoundedRect(star, radius: star.width / 2, fill: starColor)
    }

    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x02111f, alpha: 0.28).cgColor)
    drawRoundedRect(CGRect(x: 246, y: 357, width: 532, height: 336), radius: 58, fill: color(0xe8f3f5))
    context.setShadow(offset: .zero, blur: 0)
    drawRoundedRect(CGRect(x: 286, y: 400, width: 452, height: 245), radius: 34, fill: color(0x101a27))

    let accent = color(0x47e5d2)
    let promptAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 132, weight: .semibold),
        .foregroundColor: accent
    ]
    ">".draw(at: CGPoint(x: 348, y: 455), withAttributes: promptAttributes)
    drawRoundedRect(CGRect(x: 474, y: 463, width: 112, height: 28), radius: 14, fill: accent)

    let baseGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(0xf8fbfb).cgColor,
            color(0x9fb1b9).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    let basePath = NSBezierPath(roundedRect: CGRect(x: 184, y: 258, width: 656, height: 106), xRadius: 32, yRadius: 32)
    basePath.addClip()
    context.drawLinearGradient(
        baseGradient,
        start: CGPoint(x: 184, y: 364),
        end: CGPoint(x: 184, y: 258),
        options: []
    )
    context.resetClip()
    drawRoundedRect(CGRect(x: 430, y: 309, width: 164, height: 18), radius: 9, fill: color(0x6f8790, alpha: 0.45))

    color(0xffffff, alpha: 0.12).setStroke()
    let lidHighlight = NSBezierPath()
    lidHighlight.move(to: CGPoint(x: 312, y: 651))
    lidHighlight.line(to: CGPoint(x: 710, y: 651))
    lidHighlight.lineWidth = 8
    lidHighlight.stroke()

    let moonCenter = CGPoint(x: 698, y: 719)
    color(0xfff2a8).setFill()
    NSBezierPath(ovalIn: CGRect(x: moonCenter.x - 76, y: moonCenter.y - 76, width: 152, height: 152)).fill()
    color(0x122e4a).setFill()
    NSBezierPath(ovalIn: CGRect(x: moonCenter.x - 35, y: moonCenter.y - 51, width: 139, height: 139)).fill()

    context.restoreGState()
    image.unlockFocus()
    return image
}

func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }

    try data.write(to: url)
}

let icons: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in icons {
    try writePNG(image: drawIcon(size: size), to: iconset.appendingPathComponent(name))
}

try writePNG(image: drawIcon(size: 512), to: preview)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    iconset.path,
    "-o",
    output.path
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus))
}

print(output.path)

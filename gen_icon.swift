// Renders the Murmur app icon (1024x1024 PNG): dark indigo gradient
// rounded square with a white waveform. Run: swift gen_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// Big Sur-style icons float inside the canvas with ~10% margin.
let margin = size * 0.10
let tile = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
let radius = tile.width * 0.225
let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Soft drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.045,
              color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Gradient fill: deep indigo -> violet
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = [
    CGColor(red: 0.13, green: 0.10, blue: 0.32, alpha: 1),
    CGColor(red: 0.33, green: 0.18, blue: 0.62, alpha: 1),
    CGColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 1),
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 0.6, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: tile.midX, y: tile.minY),
                       end: CGPoint(x: tile.midX, y: tile.maxY),
                       options: [])

// Subtle top sheen
let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen,
                       start: CGPoint(x: tile.midX, y: tile.maxY),
                       end: CGPoint(x: tile.midX, y: tile.midY),
                       options: [])

// Waveform: symmetric capsule bars
let heights: [CGFloat] = [0.16, 0.30, 0.48, 0.72, 0.94, 0.66, 0.42, 0.58, 0.34, 0.20]
let barWidth = tile.width * 0.045
let gap = tile.width * 0.032
let totalW = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = tile.midX - totalW / 2
let maxH = tile.height * 0.52
ctx.setFillColor(CGColor(gray: 1, alpha: 0.96))
for h in heights {
    let barH = maxH * h
    let bar = CGRect(x: x, y: tile.midY - barH / 2, width: barWidth, height: barH)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    ctx.fillPath()
    x += barWidth + gap
}
ctx.restoreGState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

// Draws .claude-plugin/icon.png: Clawd under a notch, on a dark plate.
//   swift tools/icon.swift
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// plate
let plate = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: 230, cornerHeight: 230, transform: nil)
ctx.addPath(plate); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(red: 0.235, green: 0.235, blue: 0.25, alpha: 1).cgColor,
                               NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// notch hanging from the top
let nw: CGFloat = 560, nh: CGFloat = 250, r: CGFloat = 90, ear: CGFloat = 28
let x0 = (size - nw) / 2, top = size
let p = CGMutablePath()
p.move(to: CGPoint(x: x0 - ear, y: top))
p.addQuadCurve(to: CGPoint(x: x0, y: top - ear), control: CGPoint(x: x0, y: top))
p.addLine(to: CGPoint(x: x0, y: top - nh + r))
p.addQuadCurve(to: CGPoint(x: x0 + r, y: top - nh), control: CGPoint(x: x0, y: top - nh))
p.addLine(to: CGPoint(x: x0 + nw - r, y: top - nh))
p.addQuadCurve(to: CGPoint(x: x0 + nw, y: top - nh + r), control: CGPoint(x: x0 + nw, y: top - nh))
p.addLine(to: CGPoint(x: x0 + nw, y: top - ear))
p.addQuadCurve(to: CGPoint(x: x0 + nw + ear, y: top), control: CGPoint(x: x0 + nw, y: top))
p.closeSubpath()
ctx.setFillColor(NSColor.black.cgColor)
ctx.addPath(p); ctx.fillPath()

// Clawd
let grid = [
    "..XXXXXXXX..",
    "..XXXXXXXX..",
    "..XOXXXXOX..",
    "XXXOXXXXOXXX",
    "..XXXXXXXX..",
    "..XXXXXXXX..",
    "..X.X..X.X..",
    "..X.X..X.X..",
]
let px: CGFloat = 52
let gx = (size - 12 * px) / 2, gy: CGFloat = 175
ctx.setFillColor(NSColor(red: 0.97, green: 0.52, blue: 0.34, alpha: 1).cgColor)
for (y, row) in grid.enumerated() {
    for (x, ch) in row.enumerated() where ch == "X" {
        ctx.fill(CGRect(x: gx + CGFloat(x) * px, y: gy + CGFloat(7 - y) * px, width: px + 0.5, height: px + 0.5))
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".claude-plugin/icon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")

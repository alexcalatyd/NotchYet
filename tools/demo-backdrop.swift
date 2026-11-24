// Covers the top of the screen with a neutral wallpaper, a menu bar and a drawn notch, so the
// README demo can be recorded without showing whatever is on your screen.
//   swift tools/demo-backdrop.swift [seconds]
import AppKit

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "15") ?? 15
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
let barH = max(screen.safeAreaInsets.top, 24)
var notchW: CGFloat = 0
if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
    notchW = screen.frame.width - l.width - r.width
}

final class Backdrop: NSView {
    override func draw(_ dirty: NSRect) {
        let b = bounds
        NSGradient(colors: [NSColor(red: 0.30, green: 0.22, blue: 0.52, alpha: 1),
                            NSColor(red: 0.85, green: 0.45, blue: 0.40, alpha: 1)])!
            .draw(in: b, angle: -70)
        NSColor(white: 1, alpha: 0.10).setFill()
        NSRect(x: 0, y: b.maxY - barH, width: b.width, height: barH).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                    .foregroundColor: NSColor.white]
        let y = b.maxY - barH + (barH - 16) / 2
        ("\u{F8FF}   Terminal" as NSString).draw(at: NSPoint(x: 18, y: y), withAttributes: attrs)
        ("Mon 9:41" as NSString).draw(at: NSPoint(x: b.maxX - 90, y: y), withAttributes: attrs)
        if notchW > 0 {   // the physical notch shows up as content in screen recordings: draw it
            let r: CGFloat = 10
            let rect = NSRect(x: b.midX - notchW / 2, y: b.maxY - barH, width: notchW, height: barH + r)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
        }
    }
}

let h: CGFloat = 220
let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
w.collectionBehavior = [.canJoinAllSpaces, .stationary]
w.ignoresMouseEvents = true
w.contentView = Backdrop(frame: NSRect(origin: .zero, size: frame.size))
w.setFrame(frame, display: true)
w.orderFrontRegardless()
print("screen \(screen.frame.width)x\(screen.frame.height) notch \(notchW)x\(barH)")
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
app.run()

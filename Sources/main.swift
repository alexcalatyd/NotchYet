// Notch Yet — grows the MacBook notch and shows Clawd when Claude Code is done or needs you.
// Nothing stays running: a Claude Code hook starts this binary, it shows itself, waits until you
// touch the mouse, trackpad or keyboard, and quits.
//
//   notch-yet done                 "Claude is done"
//   notch-yet need                 "Claude needs you"
//   notch-yet done "Custom title"  your own title
//   notch-yet install-hooks        add the hooks to ~/.claude/settings.json (non-plugin installs)
//   notch-yet uninstall-hooks      remove them
//
// When the hook's JSON arrives on stdin, the project folder (cwd) and the message become the subtitle.
//
// Settings (environment variables, e.g. in the "env" block of ~/.claude/settings.json):
//   NOTCH_YET_LANG=en|es        language (default: the system's)
//   NOTCH_YET_SOUND=Glass       play a system sound (any name in /System/Library/Sounds); off by default
//   NOTCH_YET_TIMEOUT=3600      seconds before it hides by itself if you're away

import AppKit
import SwiftUI

let version = "1.0.0"

enum Mode: String { case done, need }

let env = ProcessInfo.processInfo.environment
let pidFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("notch-yet.pid")
let gracePeriod: TimeInterval = 0.8      // input before this doesn't count, so it doesn't vanish instantly
let maxLifetime: TimeInterval = TimeInterval(env["NOTCH_YET_TIMEOUT"] ?? "") ?? 3600

// MARK: - Language

let spanish: Bool = {
    if let l = env["NOTCH_YET_LANG"]?.lowercased() { return l.hasPrefix("es") }
    return (Locale.preferredLanguages.first ?? "en").hasPrefix("es")
}()

func L(_ en: String, _ es: String) -> String { spanish ? es : en }

func translate(_ msg: String) -> String {
    let prefix = "Claude needs your permission to use "
    if msg.hasPrefix(prefix) { return L("Permission to use ", "Permiso para usar ") + msg.dropFirst(prefix.count) }
    if msg.hasPrefix("Claude is waiting for your input") { return L("Waiting for your answer", "Esperando tu respuesta") }
    return msg
}

// MARK: - Launcher (what the hook runs: read stdin, start the UI detached, exit right away)

func launcher(_ rest0: [String]) -> Never {
    var rest = rest0
    var mode = Mode.done
    if let first = rest.first, let m = Mode(rawValue: first) { mode = m; rest.removeFirst() }
    let title = rest.isEmpty ? (mode == .done ? L("Claude is done", "Claude ha terminado")
                                              : L("Claude needs you", "Claude te necesita"))
                             : rest.joined(separator: " ")
    var subtitleParts: [String] = []

    if isatty(STDIN_FILENO) == 0 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                subtitleParts.append((cwd as NSString).lastPathComponent)
            }
            if mode == .need, let msg = obj["message"] as? String, !msg.isEmpty {
                subtitleParts.append(translate(msg))
            }
        }
    }

    // The UI runs as its own detached process so Claude Code never waits on it.
    let p = Process()
    p.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    p.arguments = ["--show", mode.rawValue, title, subtitleParts.joined(separator: " · ")]
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch {
        FileHandle.standardError.write("notch-yet: couldn't start the UI: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
    exit(0)
}

// MARK: - Hooks in ~/.claude/settings.json (for installs without the plugin)

let settingsPath = ((env["HOME"] ?? NSHomeDirectory()) as NSString).appendingPathComponent(".claude/settings.json")

func loadSettings() -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: settingsPath), !data.isEmpty else { return [:] }
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        fail("\(settingsPath) isn't valid JSON; not touching it.")
    }
    return obj
}

func saveSettings(_ s: [String: Any]) {
    let dir = (settingsPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: settingsPath) {
        try? FileManager.default.removeItem(atPath: settingsPath + ".bak")
        try? FileManager.default.copyItem(atPath: settingsPath, toPath: settingsPath + ".bak")
    }
    do {
        let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        // JSONSerialization writes `"key" : value`; tidy it to the usual `"key": value`.
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: #"(?m)^(\s*"(?:[^"\\]|\\.)*") : "#, with: "$1: ", options: .regularExpression)
        try (text + "\n").write(toFile: settingsPath, atomically: true, encoding: .utf8)
    } catch { fail("couldn't write \(settingsPath): \(error)") }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("notch-yet: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

/// Removes every hook entry whose command mentions notch-yet; drops groups and events left empty.
func stripOurHooks(_ hooks: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (event, value) in hooks {
        guard let groups = value as? [[String: Any]] else { out[event] = value; continue }
        let kept: [[String: Any]] = groups.compactMap { group in
            guard let list = group["hooks"] as? [[String: Any]] else { return group }
            let rest = list.filter { !(($0["command"] as? String) ?? "").contains("notch-yet") }
            if rest.isEmpty { return nil }
            var g = group; g["hooks"] = rest; return g
        }
        if !kept.isEmpty { out[event] = kept }
    }
    return out
}

func installHooks() -> Never {
    let exe = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    var s = loadSettings()
    var hooks = stripOurHooks(s["hooks"] as? [String: Any] ?? [:])
    func add(_ event: String, _ entry: [String: Any]) {
        hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [entry]
    }
    add("Stop", ["hooks": [["type": "command", "command": "\"\(exe)\" done"]]])
    add("Notification", ["matcher": "permission_prompt|elicitation_dialog",
                         "hooks": [["type": "command", "command": "\"\(exe)\" need"]]])
    s["hooks"] = hooks
    saveSettings(s)
    print("Hooks added to \(settingsPath) (backup in settings.json.bak). New Claude Code sessions will use them.")
    exit(0)
}

func uninstallHooks() -> Never {
    var s = loadSettings()
    let hooks = stripOurHooks(s["hooks"] as? [String: Any] ?? [:])
    if hooks.isEmpty { s.removeValue(forKey: "hooks") } else { s["hooks"] = hooks }
    saveSettings(s)
    print("Hooks removed from \(settingsPath).")
    exit(0)
}

let usage = """
Notch Yet \(version) — the notch tells you when Claude Code is done.

  notch-yet done [title]      show "Claude is done"
  notch-yet need [title]      show "Claude needs you"
  notch-yet install-hooks     add the hooks to ~/.claude/settings.json
  notch-yet uninstall-hooks   remove them
  notch-yet --version

Installed as a Claude Code plugin, the hooks come with it: you don't need install-hooks.
"""

// MARK: - Single instance (a new notification replaces the one on screen)

func takeOverPreviousInstance() {
    if let s = try? String(contentsOfFile: pidFile, encoding: .utf8),
       let old = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)),
       old > 0, old != getpid() {
        kill(old, SIGTERM)
    }
    try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)
}

func cleanupPid() {
    if let s = try? String(contentsOfFile: pidFile, encoding: .utf8),
       s.trimmingCharacters(in: .whitespacesAndNewlines) == "\(getpid())" {
        try? FileManager.default.removeItem(atPath: pidFile)
    }
}

// MARK: - Notch shape (concave ears on top, rounded corners below)

struct NotchShape: Shape {
    var topR: CGFloat
    var botR: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topR, botR) }
        set { topR = newValue.first; botR = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let br = min(botR, h / 2, (w - 2 * topR) / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: topR, y: topR), control: CGPoint(x: topR, y: 0))
        p.addLine(to: CGPoint(x: topR, y: h - br))
        p.addQuadCurve(to: CGPoint(x: topR + br, y: h), control: CGPoint(x: topR, y: h))
        p.addLine(to: CGPoint(x: w - topR - br, y: h))
        p.addQuadCurve(to: CGPoint(x: w - topR, y: h - br), control: CGPoint(x: w - topR, y: h))
        p.addLine(to: CGPoint(x: w - topR, y: topR))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - topR, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Clawd, in pixel art

let clawdOrange = Color(red: 0.97, green: 0.52, blue: 0.34)   // a livelier Claude orange: the brighter it is, the deeper the black looks

struct Clawd: View {
    let mode: Mode
    let px: CGFloat = 4
    @State private var start = Date()

    // X = body, . = empty, O = eye (a black hole)
    static let idle = [
        "..XXXXXXXX..",
        "..XXXXXXXX..",
        "..XOXXXXOX..",
        "XXXOXXXXOXXX",
        "..XXXXXXXX..",
        "..XXXXXXXX..",
        "..X.X..X.X..",
        "..X.X..X.X..",
    ]
    static let waving = [
        "..XXXXXXXX.X",
        "..XXXXXXXX.X",
        "..XOXXXXOXX.",
        "XXXOXXXXOX..",
        "..XXXXXXXX..",
        "..XXXXXXXX..",
        "..X.X..X.X..",
        "..X.X..X.X..",
    ]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { gc, _ in
                var grid = (mode == .need && Int(t * 4) % 2 == 0) ? Clawd.waving : Clawd.idle
                // blink every ~3 s
                if t.truncatingRemainder(dividingBy: 3.2) > 3.05 {
                    grid[2] = grid[2].replacingOccurrences(of: "O", with: "X")
                }
                let hop: CGFloat
                switch mode {
                case .done: hop = t < 1.6 ? (abs(sin(t * 7)) * 3).rounded() : (abs(sin(t * 2.2)) * 1).rounded()
                case .need: hop = 0
                }
                for (y, row) in grid.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "X" {
                        let rect = CGRect(x: CGFloat(x) * px,
                                          y: CGFloat(y) * px + 4 - hop,
                                          width: px, height: px)
                        gc.fill(Path(rect), with: .color(clawdOrange))
                    }
                }
            }
        }
        .frame(width: 12 * px, height: 8 * px + 4)
    }
}

// MARK: - View

final class Model: ObservableObject { @Published var open = false }

struct NotchView: View {
    @ObservedObject var model: Model
    let mode: Mode
    let title: String
    let subtitle: String
    let collapsed: CGSize
    let expanded: CGSize
    let topInset: CGFloat

    var body: some View {
        let size = model.open ? expanded : collapsed
        ZStack(alignment: .top) {
            HStack(spacing: 14) {
                Clawd(mode: mode)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(mode == .need ? clawdOrange : Color.white.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 30)
            .padding(.trailing, 24)
            .padding(.top, topInset + 10)
            .frame(width: expanded.width, height: expanded.height, alignment: .topLeading)
            .opacity(model.open ? 1 : 0)
            .blur(radius: model.open ? 0 : 8)
            .scaleEffect(model.open ? 1 : 0.85, anchor: .top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(NotchShape(topR: model.open ? 12 : 6, botR: model.open ? 24 : 10))
        // soft black halo: hides the edge between the LCD's black and the physical notch
        .background(
            NotchShape(topR: model.open ? 12 : 6, botR: model.open ? 24 : 10)
                .fill(Color.black)
                .shadow(color: .black.opacity(model.open ? 0.85 : 0), radius: 6)
                .shadow(color: .black.opacity(model.open ? 0.6 : 0), radius: 18, y: 4)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - UI

var keepAlive: [AnyObject] = []

func runUI(mode: Mode, title: String, subtitle: String) {
    setsid()
    takeOverPreviousInstance()
    signal(SIGTERM) { _ in exit(0) }   // whoever replaced us already rewrote the pidfile

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    let hasNotch = screen.safeAreaInsets.top > 0

    var notchW: CGFloat = 190
    var notchH: CGFloat = 0
    var topInset: CGFloat = 6
    if hasNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
        notchW = screen.frame.width - l.width - r.width
        notchH = screen.safeAreaInsets.top
        topInset = notchH
    }

    // the width includes the "ears" (topR) on each side
    let collapsed = CGSize(width: notchW + 12, height: max(notchH, 1))
    let expandedW = max(notchW + 200, 380)
    let expanded = CGSize(width: expandedW, height: topInset + 60)

    let pad: CGFloat = 48   // room for the spring's overshoot and the halo
    let winRect = NSRect(x: screen.frame.midX - (expanded.width + 2 * pad) / 2,
                         y: screen.frame.maxY - (expanded.height + pad),
                         width: expanded.width + 2 * pad,
                         height: expanded.height + pad)

    let model = Model()
    let panel = NSPanel(contentRect: winRect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .screenSaver
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    let host = NSHostingView(rootView: NotchView(model: model, mode: mode, title: title, subtitle: subtitle,
                                                 collapsed: collapsed, expanded: expanded, topInset: topInset))
    host.frame = NSRect(origin: .zero, size: winRect.size)
    panel.contentView = host
    panel.setFrame(winRect, display: true)
    panel.orderFrontRegardless()
    keepAlive = [panel, model]

    if let name = env["NOTCH_YET_SOUND"], !name.isEmpty, name.lowercased() != "off" {
        NSSound(named: NSSound.Name(name))?.play()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { model.open = true }
    }

    var closing = false
    func close() {
        guard !closing else { return }
        closing = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { model.open = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            cleanupPid()
            exit(0)
        }
    }

    // Hide on any input (mouse, trackpad, keyboard). Needs no permissions.
    let shownAt = Date()
    let anyInput = CGEventType(rawValue: ~0)!
    let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
        let elapsed = Date().timeIntervalSince(shownAt)
        if elapsed > maxLifetime { close(); return }
        guard elapsed > gracePeriod else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle < elapsed - gracePeriod { close() }
    }
    RunLoop.main.add(timer, forMode: .common)
    keepAlive.append(timer)

    app.run()
}

// MARK: - Entry point

let argv = CommandLine.arguments
switch argv.count > 1 ? argv[1] : "done" {
case "--show":
    let mode = Mode(rawValue: argv.count > 2 ? argv[2] : "done") ?? .done
    runUI(mode: mode,
          title: argv.count > 3 ? argv[3] : L("Claude is done", "Claude ha terminado"),
          subtitle: argv.count > 4 ? argv[4] : "")
case "install-hooks": installHooks()
case "uninstall-hooks": uninstallHooks()
case "-v", "--version": print(version)
case "-h", "--help", "help": print(usage)
default: launcher(Array(argv.dropFirst()))
}

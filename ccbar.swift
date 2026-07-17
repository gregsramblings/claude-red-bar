import Cocoa

// ---- config ----
let stateDir = ("~/.claude/ccbar/state" as NSString).expandingTildeInPath
let barHeight: CGFloat = 13.6        // px thickness of the edge bar (15% thinner than 16)
let atTop = false                    // true = top edge, false = bottom edge
let pollInterval = 0.4               // seconds
let staleAfter: TimeInterval = 12 * 3600  // ignore state files older than this

let barColor = NSColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1) // red

// solid = a session is busy (Claude working);
// pulse = a session needs a response from you now (permission prompt / blocked
//         waiting for input — the Notification hook);
// off   = a turn simply finished, or nothing running.
enum Mode { case off, solid, pulse }

func currentMode() -> Mode {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: stateDir) else { return .off }
    let now = Date().timeIntervalSince1970
    var needsInput = false
    for f in files where f.hasSuffix(".json") {
        let p = (stateDir as NSString).appendingPathComponent(f)
        guard let data = fm.contents(atPath: p),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = obj["state"] as? String else { continue }
        let ts = (obj["ts"] as? Double) ?? now
        if now - ts > staleAfter { continue }
        if s == "busy" { return .solid }              // busy wins immediately
        if s == "needs_input" { needsInput = true }   // "waiting" (turn done) → no bar
    }
    return needsInput ? .pulse : .off
}

final class Bar {
    let win: NSWindow
    let view: NSView
    init(screen: NSScreen) {
        let sf = screen.frame
        let rect = NSRect(x: sf.minX,
                          y: atTop ? sf.maxY - barHeight : sf.minY,
                          width: sf.width, height: barHeight)
        win = NSWindow(contentRect: rect, styleMask: .borderless,
                       backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver          // above menu bar + fullscreen apps
        win.ignoresMouseEvents = true     // clicks pass through
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                  .fullScreenAuxiliary, .ignoresCycle]
        view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        win.contentView = view
        win.orderFrontRegardless()
    }
    func apply(_ mode: Mode) {
        let layer = view.layer!
        switch mode {
        case .off:
            layer.removeAnimation(forKey: "pulse")
            layer.backgroundColor = NSColor.clear.cgColor
        case .solid:
            layer.removeAnimation(forKey: "pulse")
            layer.opacity = 1
            layer.backgroundColor = barColor.cgColor
        case .pulse:
            layer.backgroundColor = barColor.cgColor
            if layer.animation(forKey: "pulse") == nil {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1.0
                a.toValue = 0.25
                a.duration = 0.7
                a.autoreverses = true
                a.repeatCount = .infinity
                layer.add(a, forKey: "pulse")
            }
        }
    }
    func close() { win.orderOut(nil) }
}

final class App: NSObject, NSApplicationDelegate {
    var bars: [Bar] = []
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no dock icon
        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    @objc func rebuild() {
        bars.forEach { $0.close() }
        bars = NSScreen.screens.map { Bar(screen: $0) }
        tick()
    }

    func tick() {
        let mode = currentMode()
        bars.forEach { $0.apply(mode) }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()

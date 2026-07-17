import Cocoa

// ---- config ----
let stateDir = ("~/.claude/ccbar/state" as NSString).expandingTildeInPath
let barHeight: CGFloat = 16          // px thickness of the edge bar
let atTop = false                    // true = top edge, false = bottom edge
let pollInterval = 0.4               // seconds
let staleAfter: TimeInterval = 12 * 3600  // ignore state files older than this

// priority: higher wins the bar
enum St: Int { case waiting = 1, needsInput = 2 }

func colorFor(_ s: St) -> NSColor {
    switch s {
    case .needsInput: return NSColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1) // red
    case .waiting:    return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1) // green
    }
}

// scan all session files, return the top-priority visible state
func topState() -> St? {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: stateDir) else { return nil }
    let now = Date().timeIntervalSince1970
    var best: St? = nil
    for f in files where f.hasSuffix(".json") {
        let p = (stateDir as NSString).appendingPathComponent(f)
        guard let data = fm.contents(atPath: p),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = obj["state"] as? String else { continue }
        let ts = (obj["ts"] as? Double) ?? now
        if now - ts > staleAfter { continue }
        let st: St?
        switch s {
        case "needs_input": st = .needsInput
        case "waiting":     st = .waiting
        default:            st = nil            // busy -> no bar
        }
        if let st = st, st.rawValue > (best?.rawValue ?? 0) { best = st }
    }
    return best
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
    func apply(_ s: St?) {
        let layer = view.layer!
        guard let s = s else {
            layer.removeAnimation(forKey: "pulse")
            layer.backgroundColor = NSColor.clear.cgColor
            return
        }
        layer.backgroundColor = colorFor(s).cgColor
        if s == .needsInput {
            if layer.animation(forKey: "pulse") == nil {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1.0; a.toValue = 0.35
                a.duration = 0.7
                a.autoreverses = true
                a.repeatCount = .infinity
                layer.add(a, forKey: "pulse")
            }
        } else {
            layer.removeAnimation(forKey: "pulse")
            layer.opacity = 1.0
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
        let s = topState()
        bars.forEach { $0.apply(s) }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()

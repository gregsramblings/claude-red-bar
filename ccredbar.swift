import Cocoa

// ---- config ----
let ccredbarVersion = "1.0"
let stateDir = ("~/.claude/ccredbar/state" as NSString).expandingTildeInPath
let pollInterval = 0.4               // seconds
let staleAfter: TimeInterval = 12 * 3600  // ignore state files older than this

// Runtime config lives in UserDefaults, driven by the menu-bar item. These are
// the fallback defaults; the menu writes overrides that persist across launches.
let defaultAtTop = true              // true = top edge, false = bottom edge
let defaultBarHeight: Double = 6     // px thickness of the edge bar
let defaultBarColor = NSColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1) // red
let thicknessPresets: [Double] = [4, 6, 8, 10, 14, 20, 30]
let defaultDoneSound = "Glass"       // "" = no sound
let doneSoundNames = ["Glass", "Ping", "Pop", "Purr", "Tink", "Blow", "Hero", "Submarine"]

let ud = UserDefaults.standard
func cfgAtTop() -> Bool { ud.bool(forKey: "atTop") }
func cfgBarHeight() -> CGFloat { CGFloat(ud.double(forKey: "barHeight")) }
func cfgBarColor() -> NSColor {
    if let d = ud.data(forKey: "barColor"),
       let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: d) {
        return c
    }
    return defaultBarColor
}
func cfgDoneSound() -> String { ud.string(forKey: "doneSound") ?? defaultDoneSound }

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
        let barHeight = cfgBarHeight()
        let rect = NSRect(x: sf.minX,
                          y: cfgAtTop() ? sf.maxY - barHeight : sf.minY,
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
            layer.backgroundColor = cfgBarColor().cgColor
        case .pulse:
            layer.backgroundColor = cfgBarColor().cgColor
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
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no dock icon
        ud.register(defaults: ["atTop": defaultAtTop, "barHeight": defaultBarHeight,
                               "doneSound": defaultDoneSound])
        setupMenuBar()
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

    // ---- menu bar ----
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = barIcon()
        rebuildMenu()
    }

    // A small red horizontal bar, drawn to match barColor. isTemplate=false keeps
    // it red (template mode would force the system monochrome tint).
    func barIcon() -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let img = NSImage(size: size)
        img.lockFocus()
        cfgBarColor().setFill()
        let h: CGFloat = 4
        let r = NSRect(x: 1, y: (size.height - h) / 2, width: size.width - 2, height: h)
        NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    func rebuildMenu() {
        let m = NSMenu()

        let pos = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let posSub = NSMenu()
        for (title, top) in [("Top", true), ("Bottom", false)] {
            let it = NSMenuItem(title: title, action: #selector(setPosition(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = top
            it.state = (cfgAtTop() == top) ? .on : .off
            posSub.addItem(it)
        }
        pos.submenu = posSub
        m.addItem(pos)

        let thick = NSMenuItem(title: "Thickness", action: nil, keyEquivalent: "")
        let thickSub = NSMenu()
        let cur = Double(cfgBarHeight())
        for t in thicknessPresets {
            let it = NSMenuItem(title: "\(Int(t)) px", action: #selector(setThickness(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = t
            it.state = (t == cur) ? .on : .off
            thickSub.addItem(it)
        }
        thick.submenu = thickSub
        m.addItem(thick)

        let color = NSMenuItem(title: "Bar Color…", action: #selector(pickColor), keyEquivalent: "")
        color.target = self
        m.addItem(color)

        let sound = NSMenuItem(title: "Done Sound", action: nil, keyEquivalent: "")
        let soundSub = NSMenu()
        let curSound = cfgDoneSound()
        for name in ["None"] + doneSoundNames {
            let it = NSMenuItem(title: name, action: #selector(setDoneSound(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = (name == "None") ? "" : name
            it.state = ((it.representedObject as? String) == curSound) ? .on : .off
            soundSub.addItem(it)
            if name == "None" { soundSub.addItem(.separator()) }
        }
        sound.submenu = soundSub
        m.addItem(sound)

        m.addItem(.separator())
        let about = NSMenuItem(title: "About ccredbar", action: #selector(about), keyEquivalent: "")
        about.target = self
        m.addItem(about)

        let uninstall = NSMenuItem(title: "Uninstall ccredbar…", action: #selector(uninstall), keyEquivalent: "")
        uninstall.target = self
        m.addItem(uninstall)

        let quit = NSMenuItem(title: "Quit ccredbar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        statusItem.menu = m
    }

    @objc func pickColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = cfgBarColor()
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        if let d = try? NSKeyedArchiver.archivedData(withRootObject: sender.color,
                                                      requiringSecureCoding: false) {
            ud.set(d, forKey: "barColor")
        }
        statusItem.button?.image = barIcon()   // keep the menu-bar icon in sync
        rebuild()
    }

    @objc func about() {
        let a = NSAlert()
        a.icon = barIcon()
        a.messageText = "ccredbar \(ccredbarVersion)"
        a.informativeText = """
            A full-width red edge bar that signals, from across the room, what \
            Claude Code is doing: solid = working, pulsing = needs your input.

            Author: Greg Wilson
            """
        a.addButton(withTitle: "GitHub Repo")
        a.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://github.com/gregsramblings/claude-red-bar") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func setPosition(_ sender: NSMenuItem) {
        ud.set(sender.representedObject as? Bool ?? defaultAtTop, forKey: "atTop")
        rebuildMenu()   // refresh checkmarks
        rebuild()
    }

    @objc func setThickness(_ sender: NSMenuItem) {
        if let t = sender.representedObject as? Double { ud.set(t, forKey: "barHeight") }
        rebuildMenu()
        rebuild()
    }

    @objc func setDoneSound(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        ud.set(name, forKey: "doneSound")
        rebuildMenu()
        if !name.isEmpty { NSSound(named: name)?.play() }   // preview
    }

    @objc func uninstall() {
        let a = NSAlert()
        a.icon = barIcon()
        a.alertStyle = .warning
        a.messageText = "Uninstall ccredbar?"
        a.informativeText = """
            This stops and removes the LaunchAgent and deletes the state \
            directory (~/.claude/ccredbar), then quits.

            You must still remove the ccredbar "hooks" block from \
            ~/.claude/settings.json yourself, and delete the repo folder to \
            remove the binary.
            """
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        // Unload before deleting the plist so launchd doesn't relaunch us.
        let plist = ("~/Library/LaunchAgents/com.ccredbar.plist" as NSString).expandingTildeInPath
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["unload", plist]
        try? p.run()
        p.waitUntilExit()

        let fm = FileManager.default
        try? fm.removeItem(atPath: plist)
        try? fm.removeItem(atPath: ("~/.claude/ccredbar" as NSString).expandingTildeInPath)
        NSApp.terminate(nil)
    }

    @objc func quit() {
        // KeepAlive=true in the LaunchAgent would relaunch us within seconds, so a
        // plain terminate wouldn't stick. Unload the agent first, then exit.
        let plist = ("~/Library/LaunchAgents/com.ccredbar.plist" as NSString).expandingTildeInPath
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["unload", plist]
        try? p.run()
        p.waitUntilExit()
        NSApp.terminate(nil)
    }

    var lastMode: Mode = .off

    func tick() {
        let mode = currentMode()
        bars.forEach { $0.apply(mode) }
        // Bar just went away = every session finished (or answered) — chime once.
        if lastMode != .off && mode == .off {
            let name = cfgDoneSound()
            if !name.isEmpty { NSSound(named: name)?.play() }
        }
        lastMode = mode
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()

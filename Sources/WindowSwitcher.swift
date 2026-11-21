import Cocoa

// MARK: - Переключение окон по ⌥Tab (для тех, кто пришёл с Windows)
//
// Option+Tab показывает все окна (а не приложения целиком) с миниатюрами. Пока Option зажат: Tab / ⇧Tab или ← → —
// выбор окна, Esc — отмена; отпустили Option — выбранное окно выходит вперёд. Окно можно выбрать и щелчком.
// Для перехвата клавиш нужен доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»), для миниатюр — «Запись экрана»
// (без него вместо миниатюры показывается значок приложения).

struct SwitchItem {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let bounds: CGRect
    var icon: NSImage?
    var thumb: NSImage?
}

private typealias WindowImageFn = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
private let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
/// CGWindowListCreateImage в новых SDK помечена устаревшей, поэтому вызываем её по имени
private let cgWindowImage: WindowImageFn? = dlsym(cgHandle, "CGWindowListCreateImage")
    .map { unsafeBitCast($0, to: WindowImageFn.self) }

final class WindowSwitcher {
    static let shared = WindowSwitcher()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "switcher.enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "switcher.enabled") }
    }
    static var thumbsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "switcher.thumbs") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "switcher.thumbs") }
    }

    private static let marker: Int64 = 0x53464D43
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var panel: SwitcherPanel?
    private var items: [SwitchItem] = []
    private var index = 0
    private(set) var active = false

    func setEnabled(_ on: Bool) { on ? start() : stop() }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                               | (1 << CGEventType.flagsChanged.rawValue))
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in WindowSwitcher.shared.handle(type, event) },
                                        userInfo: nil) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        cancel()
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    // MARK: Клавиши

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if type == .flagsChanged {
            if active && !flags.contains(.maskAlternate) { DispatchQueue.main.async { self.commit() } }
            return pass
        }
        if type == .keyUp { return active && (key == 48 || key == 53 || key == 123 || key == 124) ? nil : pass }

        // keyDown
        if !active {
            let mods = flags.intersection([.maskCommand, .maskControl, .maskAlternate])
            guard key == 48, mods == .maskAlternate else { return pass }
            let back = flags.contains(.maskShift)
            active = true                                  // сразу: следующие Tab уже относятся к открытой панели
            DispatchQueue.main.async { self.begin(backwards: back) }
            return nil
        }
        switch key {
        case 48:                                           // Tab / ⇧Tab
            let back = flags.contains(.maskShift)
            DispatchQueue.main.async { self.move(back ? -1 : 1) }
            return nil
        case 124: DispatchQueue.main.async { self.move(1) }; return nil
        case 123: DispatchQueue.main.async { self.move(-1) }; return nil
        case 53: DispatchQueue.main.async { self.cancel() }; return nil
        default: return pass
        }
    }

    // MARK: Список окон

    private func collect() -> [SwitchItem] {
        var apps: [pid_t: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular || a.bundleIdentifier == "com.apple.finder" {
            apps[a.processIdentifier] = a
        }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var out: [SwitchItem] = []
        let wantThumbs = WindowSwitcher.thumbsEnabled && CGPreflightScreenCaptureAccess()
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, let app = apps[pid],
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) > 60, (b["Height"] ?? 0) > 40,
                  let numInt = w[kCGWindowNumber as String] as? Int else { continue }
            let num = CGWindowID(numInt)
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            var it = SwitchItem(id: num, pid: pid, appName: app.localizedName ?? "",
                                title: (w[kCGWindowName as String] as? String) ?? "", bounds: rect,
                                icon: app.icon, thumb: nil)
            if wantThumbs, let fn = cgWindowImage {
                // список: только это окно (1<<3); изображение: boundsIgnoreFraming (1<<0) | nominalResolution (1<<4)
                if let img = fn(.null, 1 << 3, num, (1 << 0) | (1 << 4))?.takeRetainedValue() {
                    it.thumb = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                }
            }
            out.append(it)
        }
        return out
    }

    private func begin(backwards: Bool) {
        let list = collect()
        guard list.count >= 2 else { active = false; return }
        items = list
        index = backwards ? list.count - 1 : 1
        let p = SwitcherPanel(items: list, selected: index)
        p.onPick = { [weak self] i in self?.index = i; self?.commit() }
        panel = p
        p.present()
    }

    private func move(_ d: Int) {
        guard active, !items.isEmpty else { return }
        index = (index + d + items.count) % items.count
        panel?.select(index)
    }

    private func cancel() {
        active = false
        panel?.close()
        panel = nil
        items = []
    }

    private func commit() {
        guard active, index < items.count else { cancel(); return }
        let it = items[index]
        cancel()
        raise(it)
    }

    // MARK: Вывод окна вперёд

    private func raise(_ it: SwitchItem) {
        guard let app = NSRunningApplication(processIdentifier: it.pid) else { return }
        let wins = WindowFinder.windows(pid: it.pid)
        var target = wins.first { WindowFinder.windowID($0) == it.id }
        if target == nil {                                  // запасной способ: по положению и размеру
            target = wins.first { w in
                guard let pv = WindowFinder.attr(w, kAXPositionAttribute), let sv = WindowFinder.attr(w, kAXSizeAttribute) else { return false }
                var p = CGPoint.zero, s = CGSize.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
                return abs(p.x - it.bounds.minX) < 3 && abs(p.y - it.bounds.minY) < 3 && abs(s.width - it.bounds.width) < 3
            }
        }
        // В новых macOS обычный activate() от неактивной программы часто игнорируется, поэтому приложение
        // выводим вперёд через Accessibility (frontmost) и дополнительно обычной активацией
        let axApp = AXUIElementCreateApplication(it.pid)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate(options: [.activateIgnoringOtherApps])
        func raiseWindow() {
            guard let w = target else { return }
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, w)
        }
        raiseWindow()
        // второй раз чуть позже: к этому моменту приложение уже стало активным и окно точно встанет наверх
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            raiseWindow()
        }
    }
}

// MARK: - Панель с миниатюрами

final class SwitcherPanel: NSPanel {
    var onPick: ((Int) -> Void)?
    private let grid: SwitcherGrid

    init(items: [SwitchItem], selected: Int) {
        grid = SwitcherGrid(items: items, selected: selected)
        super.init(contentRect: NSRect(origin: .zero, size: grid.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: grid.frame.size))
        fx.material = .menu
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 16
        fx.layer?.masksToBounds = true
        contentView = fx
        grid.onPick = { [weak self] i in self?.onPick?(i) }
        fx.addSubview(grid)
    }

    override var canBecomeKey: Bool { false }

    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2))
        orderFrontRegardless()
    }

    func select(_ i: Int) { grid.select(i) }
}

final class SwitcherGrid: NSView {
    private let items: [SwitchItem]
    private var selected: Int
    var onPick: ((Int) -> Void)?
    private static let tw: CGFloat = 200, th: CGFloat = 150, gp: CGFloat = 12, pd: CGFloat = 18
    private var tileW: CGFloat { SwitcherGrid.tw }
    private var tileH: CGFloat { SwitcherGrid.th }
    private var gap: CGFloat { SwitcherGrid.gp }
    private var pad: CGFloat { SwitcherGrid.pd }
    private var cols = 1

    init(items: [SwitchItem], selected: Int) {
        self.items = items
        self.selected = selected
        let screenW = (NSScreen.main?.visibleFrame.width ?? 1400) - 120
        let maxCols = max(2, Int((screenW - 2 * SwitcherGrid.pd + SwitcherGrid.gp) / (SwitcherGrid.tw + SwitcherGrid.gp)))
        let c = min(items.count, min(maxCols, 8))
        let rows = Int(ceil(Double(items.count) / Double(c)))
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: CGFloat(c) * (SwitcherGrid.tw + SwitcherGrid.gp) - SwitcherGrid.gp + 2 * SwitcherGrid.pd,
                                 height: CGFloat(rows) * (SwitcherGrid.th + SwitcherGrid.gp) - SwitcherGrid.gp + 2 * SwitcherGrid.pd))
        cols = c
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ i: Int) { selected = i; needsDisplay = true }

    private func tileRect(_ i: Int) -> NSRect {
        let r = i / cols, c = i % cols
        return NSRect(x: pad + CGFloat(c) * (tileW + gap),
                      y: bounds.height - pad - CGFloat(r + 1) * tileH - CGFloat(r) * gap,
                      width: tileW, height: tileH)
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        for i in items.indices where tileRect(i).contains(p) { onPick?(i); return }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, it) in items.enumerated() {
            let r = tileRect(i)
            if i == selected {
                NSColor.labelColor.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
                NSColor.controlAccentColor.setStroke()
                let b = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
                b.lineWidth = 2
                b.stroke()
            }
            // миниатюра или значок приложения
            let area = NSRect(x: r.minX + 8, y: r.minY + 30, width: r.width - 16, height: r.height - 38)
            if let t = it.thumb, t.size.width > 0, t.size.height > 0 {
                let k = min(area.width / t.size.width, area.height / t.size.height, 1.5)
                let sz = NSSize(width: t.size.width * k, height: t.size.height * k)
                let dst = NSRect(x: area.midX - sz.width / 2, y: area.midY - sz.height / 2, width: sz.width, height: sz.height)
                NSGraphicsContext.saveGraphicsState()
                t.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
                NSColor.separatorColor.setStroke()
                NSBezierPath(rect: dst).stroke()
                it.icon?.draw(in: NSRect(x: dst.minX + 4, y: dst.minY + 4, width: 26, height: 26))
            } else if let ic = it.icon {
                let s: CGFloat = min(area.width, area.height, 72)
                ic.draw(in: NSRect(x: area.midX - s / 2, y: area.midY - s / 2, width: s, height: s))
            }
            // подпись: название окна, а если его нет — название приложения
            let text = it.title.isEmpty ? it.appName : it.title
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            (text as NSString).draw(in: NSRect(x: r.minX + 8, y: r.minY + 6, width: r.width - 16, height: 18),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                                     .foregroundColor: NSColor.labelColor,
                                                     .paragraphStyle: para])
        }
    }
}

import AppKit
import ApplicationServices

// MARK: - Окна при наведении на значок приложения в Dock
// Курсор над значком ~0,3 с → панель с окнами этого приложения (значки или миниатюры).
// Клик — вывести окно вперёд; на плитке есть кнопки «закрыть / свернуть / на весь экран».
// Все обращения к Dock и к чужим приложениям (Accessibility) идут не в главном потоке — «Пуск» не подвисает.

final class DockPreview {
    static let shared = DockPreview()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "dockPreview.enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "dockPreview.enabled") }
    }
    /// Задержка перед показом, секунд (потом подберём по реальной проверке)
    static var delay: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "dockPreview.delay")
        return v > 0 ? v : 0.3
    }
    /// Задержка при переходе с одного значка на соседний, когда панель уже была открыта
    private static let switchDelay: TimeInterval = 0.12

    private struct Hit { let url: URL; let frame: NSRect }

    private var monitor: Any?
    private var panel: SwitcherPanel?
    private var items: [SwitchItem] = []
    private var shownPID: pid_t = 0
    private var shownKey: String?            // приложение, окна которого показаны сейчас
    private var hoverKey: String?            // значок, над которым ждём показа
    private var work: DispatchWorkItem?
    private var suppressed = false          // открыто контекстное меню Dock: панель не показываем
    private var poll: Timer?
    private var lastPoint = NSPoint(x: -1, y: -1)
    private var lastProbe = Date.distantPast
    private var probing = false
    private var generation = 0               // устаревшие ответы фоновых запросов отбрасываются
    private var itemFrame = NSRect.zero      // в координатах Cocoa
    private let probeQueue = DispatchQueue(label: "dockpreview.probe", qos: .userInitiated)
    private let windowsQueue = DispatchQueue(label: "dockpreview.windows", qos: .userInitiated, attributes: .concurrent)

    func setEnabled(_ on: Bool) { on ? start() : stop() }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] e in
            guard let self = self else { return }
            switch e.type {
            case .rightMouseDown:                    // контекстное меню значка в Dock важнее панели
                self.suppressed = true
                self.hide()
            case .leftMouseDown where e.modifierFlags.contains(.control):
                self.suppressed = true
                self.hide()
            case .leftMouseDown, .otherMouseDown:    // выбор пункта меню или щелчок мимо — меню закрылось
                self.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.suppressed = false }
            case .keyDown:
                if e.keyCode == 53 { self.suppressed = false }   // Esc закрывает меню
            default: break
            }
        }
        // Положение курсора опрашиваем таймером: события мыши не доходят до глобального монитора,
        // пока «Пуск» активен (например, после щелчка по нему), а таймер от этого не зависит
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        poll?.invalidate()
        poll = nil
        hide()
    }

    // MARK: Наведение

    private func nearScreenEdge(_ p: NSPoint) -> Bool {
        guard let s = NSScreen.screens.first(where: { $0.frame.contains(p) }) else { return false }
        let f = s.frame
        return p.y - f.minY < 160 || p.x - f.minX < 160 || f.maxX - p.x < 160
    }

    /// Опрос положения курсора: что под ним в Dock (в фоне), затем решение в главном потоке
    private func tick() {
        guard !suppressed else { return }
        let p = NSEvent.mouseLocation
        if let pn = panel, pn.frame.insetBy(dx: -8, dy: -8).contains(p) { return }       // курсор на панели
        if panel == nil {
            if !nearScreenEdge(p) { cancelPending(); lastPoint = p; return }
            if p == lastPoint { return }                                                  // курсор стоит, ничего не изменилось
        }
        lastPoint = p
        let now = Date()
        guard !probing, now.timeIntervalSince(lastProbe) > 0.05 else { lastPoint = NSPoint(x: -1, y: -1); return }
        lastProbe = now
        // Над собственными окнами AppKit обходит доступность внутри процесса — из фонового потока это падает
        if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(p) }) {
            if panel != nil { hide() } else { cancelPending() }
            return
        }
        probing = true
        let gen = generation
        let h = NSScreen.screens.first?.frame.height ?? 0
        probeQueue.async { [weak self] in
            let hit = autoreleasepool { DockPreview.dockApp(at: p, screenHeight: h) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.probing = false
                if gen == self.generation { self.decide(hit) }
            }
        }
    }

    private func decide(_ hit: Hit?) {
        let key = hit?.url.path
        if panel != nil {
            if let pn = panel, pn.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) { return }
            if let h = hit, key == shownKey { itemFrame = h.frame; return }      // всё ещё тот же значок
            hide()                                                              // ушли: на другой значок или мимо
            if let h = hit { schedule(h, after: DockPreview.switchDelay) }
            return
        }
        if key == hoverKey { return }
        cancelPending()
        if let h = hit { schedule(h, after: DockPreview.delay) }
    }

    private func schedule(_ h: Hit, after: TimeInterval) {
        hoverKey = h.url.path
        let w = DispatchWorkItem { [weak self] in self?.show(h.url, h.frame) }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
    }

    private func cancelPending() {
        hoverKey = nil
        work?.cancel()
        work = nil
    }

    /// Значок приложения в Dock под курсором: путь к программе и рамка (Cocoa-координаты)
    private static func dockApp(at p: NSPoint, screenHeight h: CGFloat) -> Hit? {
        var el: AXUIElement?
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.2)
        guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(h - p.y), &el) == .success, let e = el else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(e, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock",
              (WindowFinder.attr(e, kAXSubroleAttribute) as? String) == "AXApplicationDockItem" else { return nil }
        var url: URL?
        if let u = WindowFinder.attr(e, kAXURLAttribute) {
            if let x = u as? URL { url = x } else if let s = u as? String { url = URL(string: s) }
        }
        guard let url = url,
              let pv = WindowFinder.attr(e, kAXPositionAttribute), let sv = WindowFinder.attr(e, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        return Hit(url: url, frame: NSRect(x: pos.x, y: h - pos.y - size.height, width: size.width, height: size.height))
    }

    // MARK: Показ

    private func app(for url: URL) -> NSRunningApplication? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy != .prohibited
                && $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
        }
    }

    private func thumbsOn() -> Bool { WindowSwitcher.thumbsEnabled && CGPreflightScreenCaptureAccess() }

    private func show(_ url: URL, _ frame: NSRect) {
        work = nil
        guard panel == nil, !suppressed, DockPreview.enabled, AXIsProcessTrusted(),
              let a = app(for: url), a.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = a.processIdentifier
        let key = url.path
        let thumbs = thumbsOn()
        let gen = generation
        // окна собираем вне главного потока, чтобы медленное приложение не вешало «Пуск»
        windowsQueue.async { [weak self] in
            let list = WindowTools.windows(pid: pid, thumbs: thumbs)
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                self.present(list, pid: pid, key: key, frame: frame)
            }
        }
    }

    private func present(_ list: [SwitchItem], pid: pid_t, key: String, frame: NSRect) {
        // пока собирали окна, курсор мог уйти с этого значка
        guard !list.isEmpty,                                   // у приложения нет окон — ничего не показываем
              panel == nil, !suppressed, DockPreview.enabled, hoverKey == key,
              frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
        items = list
        shownPID = pid
        shownKey = key
        itemFrame = frame
        let p = SwitcherPanel(items: list, selected: -1, header: false)
        p.onPick = { [weak self] i in self?.pick(i) }
        p.onAction = { [weak self] i, act in self?.act(i, act) }
        panel = p
        place(p)
        p.orderFrontRegardless()
        p.invalidateShadow()
    }

    /// Над значком (Dock снизу) или сбоку от него (Dock слева/справа), панель остаётся в пределах экрана
    private func place(_ p: SwitcherPanel) {
        let screen = NSScreen.screens.first { $0.frame.intersects(itemFrame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame, s = p.frame.size
        var o = NSPoint.zero
        if itemFrame.midX - screen.frame.minX < 100 && itemFrame.minY - screen.frame.minY > 100 {          // Dock слева
            o = NSPoint(x: itemFrame.maxX + 6, y: itemFrame.midY - s.height / 2)
        } else if screen.frame.maxX - itemFrame.midX < 100 && itemFrame.minY - screen.frame.minY > 100 { // Dock справа
            o = NSPoint(x: itemFrame.minX - s.width - 6, y: itemFrame.midY - s.height / 2)
        } else {                                                                                          // Dock снизу
            o = NSPoint(x: itemFrame.midX - s.width / 2, y: itemFrame.maxY + 6)
        }
        o.x = min(max(o.x, f.minX + 6), f.maxX - s.width - 6)
        o.y = min(max(o.y, f.minY + 6), f.maxY - s.height - 6)
        p.setFrameOrigin(o)
    }

    func hide() {
        generation += 1
        cancelPending()
        lastPoint = NSPoint(x: -1, y: -1)
        panel?.close()
        panel = nil
        shownKey = nil
        items = []
    }

    // MARK: Действия

    private func pick(_ i: Int) {
        guard items.indices.contains(i) else { return }
        let it = items[i]
        hide()
        if it.minimized, let a = NSRunningApplication(processIdentifier: it.pid) {
            a.activate(options: [.activateIgnoringOtherApps])
            if let w = WindowTools.axWindow(for: it) {
                AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            }
        } else {
            WindowSwitcher.shared.raise(it)
        }
    }

    private func act(_ i: Int, _ a: TileAction) {
        guard items.indices.contains(i) else { return }
        let it = items[i]
        switch a {
        case .close, .minimize:
            windowsQueue.async { WindowTools.perform(a, on: it) }
            // окно закрывается не мгновенно — обновляем список чуть позже
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
        case .fullscreen:
            hide()
            WindowSwitcher.shared.raise(it)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { WindowTools.perform(.fullscreen, on: it) }
        }
    }

    private func refresh() {
        guard panel != nil, let key = shownKey else { return }
        let pid = shownPID, thumbs = thumbsOn(), gen = generation
        windowsQueue.async { [weak self] in
            let list = WindowTools.windows(pid: pid, thumbs: thumbs)
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation, self.shownKey == key, let p = self.panel else { return }
                if list.isEmpty { self.hide(); return }          // закрыли последнее окно
                self.items = list
                p.update(items: list, selected: -1, query: "")
                self.place(p)
            }
        }
    }
}

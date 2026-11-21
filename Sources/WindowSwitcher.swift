import Cocoa

// MARK: - Переключение окон по ⌥Tab (для тех, кто пришёл с Windows)
//
// Option+Tab показывает все окна (а не приложения целиком) с миниатюрами. Пока Option зажат: Tab / ⇧Tab или ← → —
// выбор окна, Esc — отмена; отпустили Option — выбранное окно выходит вперёд. Окно можно выбрать и щелчком.
// Для перехвата клавиш нужен доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»); «Запись экрана и системного звука» — только для миниатюр окон
// (без него вместо миниатюры показывается значок приложения).

struct SwitchItem {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let bounds: CGRect
    var icon: NSImage?
    var thumb: NSImage?
    var minimized = false
}

enum TileAction { case close, minimize, fullscreen }

/// Общие действия над окнами (для ⌥Tab и превью из Dock)
enum WindowTools {
    /// Последние снимки окон: свёрнутое окно система обычно не отдаёт, тогда показываем снимок, сделанный, пока оно было на экране
    private static var cache: [CGWindowID: NSImage] = [:]
    private static var cacheOrder: [CGWindowID] = []
    private static let cacheLock = NSLock()

    private static func store(_ id: CGWindowID, _ im: NSImage) {
        cacheLock.lock()
        if cache[id] == nil { cacheOrder.append(id) }
        cache[id] = im
        if cacheOrder.count > 40 { cache[cacheOrder.removeFirst()] = nil }
        cacheLock.unlock()
    }

    /// Снимок свёрнутого окна без разворачивания: закрытая функция CGSHWCaptureWindowList (так делает, например, AltTab).
    /// Принимается только если пропорции картинки совпадают с размером окна — иначе это искажённый кадр анимации сворачивания.
    /// Если не вышло — последний сохранённый снимок.
    static func minimizedThumb(_ id: CGWindowID, size: CGSize) -> NSImage? {
        guard id != 0, CGPreflightScreenCaptureAccess(), let conn = cgsMainConnection, let cap = cgsCapture,
              size.width > 10, size.height > 10 else { return cachedThumb(id) }
        var wid = id
        // 1<<11 — без обрезки по форме, 1<<8 — лучшее разрешение
        if let arr = cap(conn(), &wid, 1, (1 << 11) | (1 << 8))?.takeRetainedValue(),
           let first = (arr as [AnyObject]).first, CFGetTypeID(first) == CGImage.typeID {
            let img = first as! CGImage
            if img.width > 8, img.height > 8 {
                let a = CGFloat(img.width) / CGFloat(img.height), b = size.width / size.height
                if abs(a - b) / b < 0.03 {
                    let im = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                    store(id, im)
                    return im
                }
            }
        }
        return cachedThumb(id)
    }

    /// Последний сохранённый снимок окна (без нового снимка)
    static func cachedThumb(_ id: CGWindowID) -> NSImage? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache[id]
    }

    /// live == false — только сохранённый снимок: окно сворачивается/движется, снимок сейчас будет искажён (эффект «джинна»)
    static func thumb(_ id: CGWindowID, live: Bool = true) -> NSImage? {
        guard live else { return cachedThumb(id) }
        guard id != 0, CGPreflightScreenCaptureAccess(), let fn = cgWindowImage else { return nil }
        // список: только это окно (1<<3); изображение: boundsIgnoreFraming (1<<0) | nominalResolution (1<<4)
        if let img = fn(.null, 1 << 3, id, (1 << 0) | (1 << 4))?.takeRetainedValue(), img.width > 8, img.height > 8 {
            let im = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
            store(id, im)
            return im
        }
        return cachedThumb(id)
    }

    /// Окна на экране: положение и прозрачность (для проверки, что окно неподвижно)
    private static func onScreenState() -> [CGWindowID: (CGRect, Double)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var r: [CGWindowID: (CGRect, Double)] = [:]
        for w in list {
            guard let n = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            r[CGWindowID(n)] = (CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0),
                                w[kCGWindowAlpha as String] as? Double ?? 1)
        }
        return r
    }

    /// Окна приложения, свёрнутые в Dock (нужен Accessibility). Снимок — только сохранённый, живой у свёрнутого окна искажён
    static func minimized(pid: pid_t, app: NSRunningApplication, thumbs: Bool, shown: Set<CGWindowID>, timeout: Float) -> [SwitchItem] {
        var out: [SwitchItem] = []
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, timeout)
        var wins = (WindowFinder.attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        for c in (WindowFinder.attr(ax, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            where WindowFinder.isWindow(c) && !wins.contains(where: { CFEqual($0, c) }) { wins.append(c) }
        for w in wins {
            guard (WindowFinder.attr(w, kAXMinimizedAttribute) as? NSNumber)?.boolValue == true else { continue }
            let id = WindowFinder.windowID(w)
            if let id = id, shown.contains(id) { continue }
            var size = CGSize.zero
            if let sv = WindowFinder.attr(w, kAXSizeAttribute) { AXValueGetValue(sv as! AXValue, .cgSize, &size) }
            out.append(SwitchItem(id: id ?? 0, pid: pid, appName: app.localizedName ?? "",
                                  title: (WindowFinder.attr(w, kAXTitleAttribute) as? String) ?? "", bounds: .zero,
                                  icon: app.icon, thumb: thumbs ? minimizedThumb(id ?? 0, size: size) : nil, minimized: true))
        }
        return out
    }

    private static func isStill(_ id: CGWindowID, _ a: [CGWindowID: (CGRect, Double)], _ b: [CGWindowID: (CGRect, Double)]) -> Bool {
        guard let x = a[id], let y = b[id], x.1 >= 0.99, y.1 >= 0.99 else { return false }
        return abs(x.0.minX - y.0.minX) < 1 && abs(x.0.minY - y.0.minY) < 1
            && abs(x.0.width - y.0.width) < 1 && abs(x.0.height - y.0.height) < 1
    }

    /// Окна одного приложения: видимые (с миниатюрами, если разрешено) и свёрнутые в Dock
    static func windows(pid: pid_t, thumbs: Bool) -> [SwitchItem] {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return [] }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var out: [SwitchItem] = []
        // снимок делаем только у неподвижных окон: положение не изменилось за 0,12 с и окно не полупрозрачное
        let before = thumbs ? onScreenState() : [:]
        if thumbs { usleep(120_000) }
        let after = thumbs ? onScreenState() : [:]
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) > 60, (b["Height"] ?? 0) > 40,
                  let numInt = w[kCGWindowNumber as String] as? Int else { continue }
            let num = CGWindowID(numInt)
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            out.append(SwitchItem(id: num, pid: pid, appName: app.localizedName ?? "",
                                  title: (w[kCGWindowName as String] as? String) ?? "", bounds: rect,
                                  icon: app.icon, thumb: thumbs ? thumb(num, live: isStill(num, before, after)) : nil))
        }
        if AXIsProcessTrusted() { out += minimized(pid: pid, app: app, thumbs: thumbs, shown: Set(out.map { $0.id }), timeout: 1.0) }
        return out
    }

    static func axWindow(for it: SwitchItem) -> AXUIElement? {
        let wins = WindowFinder.windows(pid: it.pid)
        if let w = wins.first(where: { WindowFinder.windowID($0) == it.id }) { return w }
        guard it.bounds != .zero else { return nil }
        return wins.first { w in
            guard let pv = WindowFinder.attr(w, kAXPositionAttribute), let sv = WindowFinder.attr(w, kAXSizeAttribute) else { return false }
            var p = CGPoint.zero, s = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
            return abs(p.x - it.bounds.minX) < 3 && abs(p.y - it.bounds.minY) < 3 && abs(s.width - it.bounds.width) < 3
        }
    }

    static func perform(_ a: TileAction, on it: SwitchItem) {
        guard let w = axWindow(for: it) else { return }
        switch a {
        case .close:
            if let b = WindowFinder.attr(w, kAXCloseButtonAttribute) {
                AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
            }
        case .minimize:
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        case .fullscreen:
            let now = (WindowFinder.attr(w, "AXFullScreen") as? Bool) ?? false
            AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, (now ? kCFBooleanFalse : kCFBooleanTrue)!)
        }
    }
}

private typealias WindowImageFn = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
private let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
/// CGWindowListCreateImage в новых SDK помечена устаревшей, поэтому вызываем её по имени
private typealias CGSConnFn = @convention(c) () -> Int32
private typealias CGSCaptureFn = @convention(c) (Int32, UnsafeMutablePointer<CGWindowID>, UInt32, UInt32) -> Unmanaged<CFArray>?
private let cgsMainConnection: CGSConnFn? = (dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSMainConnectionID"))
    .map { unsafeBitCast($0, to: CGSConnFn.self) }
private let cgsCapture: CGSCaptureFn? = (dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSHWCaptureWindowList"))
    .map { unsafeBitCast($0, to: CGSCaptureFn.self) }
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
    private var allItems: [SwitchItem] = []
    private var items: [SwitchItem] = []
    private var query = ""
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
        if type == .keyUp { return active ? nil : pass }

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
        case 125: DispatchQueue.main.async { self.moveRow(1) }; return nil
        case 126: DispatchQueue.main.async { self.moveRow(-1) }; return nil
        case 36, 76: DispatchQueue.main.async { self.commit() }; return nil
        case 53: DispatchQueue.main.async { self.cancel() }; return nil
        case 51:                                           // ⌫ — стереть букву поиска
            DispatchQueue.main.async { if !self.query.isEmpty { self.query.removeLast(); self.applyQuery() } }
            return nil
        default:
            // поиск: набранные буквы и цифры (с учётом раскладки; зажатый ⌥ символ не меняет)
            guard !flags.contains(.maskCommand), !flags.contains(.maskControl),
                  let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, !chars.isEmpty,
                  !chars.unicodeScalars.contains(where: { $0.value < 32 || (0xF700...0xF8FF).contains($0.value) }) else { return pass }
            DispatchQueue.main.async { self.query += chars; self.applyQuery() }
            return nil
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
            if wantThumbs { it.thumb = WindowTools.thumb(num, live: (w[kCGWindowAlpha as String] as? Double ?? 1) >= 0.99) }
            out.append(it)
        }
        // свёрнутые окна — в конце списка
        if AXIsProcessTrusted() {
            let shown = Set(out.map { $0.id })
            for pid in apps.keys.sorted() {
                if let a = apps[pid] { out += WindowTools.minimized(pid: pid, app: a, thumbs: wantThumbs, shown: shown, timeout: 0.25) }
            }
        }
        return out
    }

    private func begin(backwards: Bool) {
        let list = collect()
        guard list.count >= 2 else { active = false; return }
        allItems = list
        items = list
        query = ""
        index = backwards ? list.count - 1 : 1
        let p = SwitcherPanel(items: list, selected: index)
        p.onPick = { [weak self] i in self?.index = i; self?.commit() }
        p.onAction = { [weak self] i, a in self?.tileAction(i, a) }
        panel = p
        p.present()
    }

    private func move(_ d: Int) {
        guard active, !items.isEmpty else { return }
        index = (index + d + items.count) % items.count
        panel?.select(index)
    }

    /// ↑ / ↓ — на строку вверх или вниз
    private func moveRow(_ d: Int) {
        guard active, !items.isEmpty else { return }
        let n = index + d * (panel?.columns ?? 1)
        if items.indices.contains(n) { index = n; panel?.select(index) }
    }

    private func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    private static let ruKeys = Array("йцукенгшщзхъфывапролджэячсмитьбюё")
    private static let enKeys = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`")

    /// Та же строка, набранная в другой раскладке (русская ↔ английская)
    private func swapLayout(_ s: String, toLatin: Bool) -> String {
        let from = toLatin ? WindowSwitcher.ruKeys : WindowSwitcher.enKeys
        let to = toLatin ? WindowSwitcher.enKeys : WindowSwitcher.ruKeys
        return String(s.map { ch in from.firstIndex(of: ch).map { to[$0] } ?? ch })
    }

    /// Поиск по названию окна и приложения
    private func applyQuery() {
        guard active else { return }
        let q = fold(query)
        // без учёта раскладки: «хром» и «xhjv» находят одно и то же
        let variants = [q, swapLayout(q, toLatin: true), swapLayout(q, toLatin: false)]
        items = q.isEmpty ? allItems : allItems.filter { it in
            let t = fold(it.title), n = fold(it.appName)
            return variants.contains { t.contains($0) || n.contains($0) }
        }
        index = q.isEmpty ? min(index, max(0, items.count - 1)) : 0
        panel?.update(items: items, selected: items.isEmpty ? -1 : index, query: query)
    }

    /// Кнопки на плитке окна
    private func tileAction(_ i: Int, _ a: TileAction) {
        guard active, items.indices.contains(i) else { return }
        let it = items[i]
        switch a {
        case .close, .minimize:
            WindowTools.perform(a, on: it)
            allItems.removeAll { $0.id == it.id }
            if allItems.isEmpty { cancel() } else { applyQuery() }
        case .fullscreen:
            cancel()
            raise(it)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { WindowTools.perform(.fullscreen, on: it) }
        }
    }

    private func cancel() {
        active = false
        panel?.close()
        panel = nil
        items = []
        allItems = []
        query = ""
    }

    private func commit() {
        guard active, items.indices.contains(index) else { cancel(); return }
        let it = items[index]
        cancel()
        raise(it)
    }

    // MARK: Вывод окна вперёд

    func raise(_ it: SwitchItem) {
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

enum TilesBlur {
    static func make(size: NSSize) -> NSVisualEffectView {
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .menu
        fx.blendingMode = .behindWindow
        fx.state = .active
        // скругление маской самого эффекта: слой с cornerRadius блюр не обрезает, и из-под углов виден светлый фон
        let r: CGFloat = 16
        let mask = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        fx.maskImage = mask
        return fx
    }
}

final class SwitcherPanel: NSPanel {
    var onPick: ((Int) -> Void)?
    var onAction: ((Int, TileAction) -> Void)?
    private let grid: SwitcherGrid
    private let fx: NSVisualEffectView
    var columns: Int { grid.cols }

    private var centered = true

    init(items: [SwitchItem], selected: Int, header: Bool = true) {
        centered = header
        grid = SwitcherGrid(items: items, selected: selected, header: header)
        fx = TilesBlur.make(size: grid.frame.size)
        super.init(contentRect: NSRect(origin: .zero, size: grid.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        contentView = fx
        grid.onPick = { [weak self] i in self?.onPick?(i) }
        grid.onAction = { [weak self] i, a in self?.onAction?(i, a) }
        fx.addSubview(grid)
    }

    override var canBecomeKey: Bool { false }

    private func centerOnScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2))
    }

    func present() {
        if centered { centerOnScreen() }
        orderFrontRegardless()
        invalidateShadow()
    }

    func select(_ i: Int) { grid.select(i) }
    var emptyText: String { get { grid.emptyText } set { grid.emptyText = newValue } }

    /// Список изменился (поиск, закрытое окно): размер панели подстраивается
    func update(items: [SwitchItem], selected: Int, query: String) {
        let size = grid.update(items: items, selected: selected, query: query)
        fx.frame = NSRect(origin: .zero, size: size)
        setContentSize(size)
        if centered { centerOnScreen() }
        invalidateShadow()
    }
}

final class SwitcherGrid: NSView {
    private(set) var items: [SwitchItem]
    private var selected: Int
    private var hovered = -1
    private var query = ""
    var emptyText = "Ничего не найдено"
    private let hasHeader: Bool
    var onPick: ((Int) -> Void)?
    var onAction: ((Int, TileAction) -> Void)?
    private static let tw: CGFloat = 200, th: CGFloat = 150, gp: CGFloat = 12, pd: CGFloat = 18, hh: CGFloat = 34
    private(set) var cols = 1
    private var tile = NSSize(width: 200, height: 150)

    /// Раскладка плиток. Для панели у Dock (без заголовка) размер не больше двух плиток по каждой стороне:
    /// если окон больше, плитки уменьшаются и всё помещается в эти размеры.
    private static func geometry(count: Int, header: Bool) -> (cols: Int, tile: NSSize, size: NSSize) {
        let n = max(count, 1)
        // панель у Dock на 10 % меньше панели ⌥Tab
        let sc: CGFloat = header ? 1 : 0.9
        let tw = SwitcherGrid.tw * sc, th = SwitcherGrid.th * sc
        var c: Int, k: CGFloat = 1
        if header {
            let screenW = (NSScreen.main?.visibleFrame.width ?? 1400) - 120
            let maxCols = max(2, Int((screenW - 2 * pd + gp) / (tw + gp)))
            c = min(n, min(maxCols, 8))
        } else {
            // не шире двух плиток; ряды добавляются вниз/вверх, а если не помещаются по высоте экрана — плитки уменьшаются
            c = min(n, 2)
            let rows = Int(ceil(Double(n) / Double(c)))
            let maxH = (NSScreen.main?.visibleFrame.height ?? 900) * 0.6
            k = min(1, maxH / (CGFloat(rows) * (th + gp) - gp))
        }
        let tile = NSSize(width: (tw * k).rounded(), height: (th * k).rounded())
        let rows = Int(ceil(Double(n) / Double(c)))
        let h = CGFloat(rows) * (tile.height + gp) - gp + 2 * pd + (header ? hh : 0)
        var w = CGFloat(c) * (tile.width + gp) - gp + 2 * pd
        if header { w = max(w, 380) }
        return (c, tile, NSSize(width: w, height: h))
    }

    init(items: [SwitchItem], selected: Int, header: Bool) {
        self.items = items
        self.selected = selected
        self.hasHeader = header
        let g = SwitcherGrid.geometry(count: items.count, header: header)
        super.init(frame: NSRect(origin: .zero, size: g.size))
        cols = g.cols
        tile = g.tile
    }
    required init?(coder: NSCoder) { fatalError() }

    func select(_ i: Int) { selected = i; needsDisplay = true }

    func update(items: [SwitchItem], selected: Int, query: String) -> NSSize {
        self.items = items
        self.selected = selected
        self.query = query
        hovered = -1
        let g = SwitcherGrid.geometry(count: items.count, header: hasHeader)
        cols = g.cols
        tile = g.tile
        setFrameSize(g.size)
        needsDisplay = true
        return g.size
    }

    private var headerH: CGFloat { hasHeader ? SwitcherGrid.hh : 0 }

    private func tileRect(_ i: Int) -> NSRect {
        let tw = tile.width, th = tile.height, gp = SwitcherGrid.gp, pd = SwitcherGrid.pd
        let r = i / cols, c = i % cols
        let rowW = CGFloat(cols) * (tw + gp) - gp
        let offX = (bounds.width - rowW) / 2
        return NSRect(x: offX + CGFloat(c) * (tw + gp),
                      y: bounds.height - pd - headerH - CGFloat(r + 1) * th - CGFloat(r) * gp,
                      width: tw, height: th)
    }

    // MARK: Мышь

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func tile(at p: NSPoint) -> Int? { items.indices.first { tileRect($0).contains(p) } }

    override func mouseMoved(with e: NSEvent) {
        let h = tile(at: convert(e.locationInWindow, from: nil)) ?? -1
        if h != hovered { hovered = h; needsDisplay = true }
    }

    override func mouseExited(with e: NSEvent) {
        hovered = -1
        needsDisplay = true
    }

    /// Круглые кнопки в левом верхнем углу плитки: закрыть, свернуть, на весь экран
    private func buttonCenter(_ i: Int, _ k: Int) -> NSPoint {
        let r = tileRect(i)
        return NSPoint(x: r.minX + 18 + CGFloat(k) * 20, y: r.maxY - 17)
    }
    private static let actions: [TileAction] = [.close, .minimize, .fullscreen]

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let i = tile(at: p) else { return }
        if hovered == i {
            for (k, a) in SwitcherGrid.actions.enumerated() {
                let c = buttonCenter(i, k)
                if hypot(p.x - c.x, p.y - c.y) <= 10 { onAction?(i, a); return }
            }
        }
        onPick?(i)
    }

    // MARK: Рисование

    override func draw(_ dirtyRect: NSRect) {
        if hasHeader {
            let f = NSRect(x: SwitcherGrid.pd, y: bounds.height - SwitcherGrid.pd - 26,
                           width: bounds.width - 2 * SwitcherGrid.pd, height: 26)
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: f, xRadius: 7, yRadius: 7).fill()
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingHead
            let text = query.isEmpty ? T("Печатайте, чтобы найти окно") : query
            (text as NSString).draw(in: NSRect(x: f.minX + 10, y: f.minY + 5, width: f.width - 20, height: 17),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 13),
                                                     .foregroundColor: query.isEmpty ? NSColor.secondaryLabelColor : NSColor.labelColor,
                                                     .paragraphStyle: para])
        }
        if items.isEmpty {
            let r = tileRect(0)
            (T(emptyText) as NSString).draw(in: NSRect(x: r.minX, y: r.midY - 9, width: r.width, height: 18),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor,
                                 .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()])
            return
        }
        for (i, it) in items.enumerated() {
            let r = tileRect(i)
            if i == selected {
                NSColor.labelColor.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
                NSColor.controlAccentColor.setStroke()
                let b = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
                b.lineWidth = 2
                b.stroke()
            } else if i == hovered {
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            }
            // миниатюра или значок приложения
            let small = r.height < 110
            let lab: CGFloat = small ? 20 : 30
            let area = NSRect(x: r.minX + 8, y: r.minY + lab, width: r.width - 16, height: r.height - lab - 8)
            if let t = it.thumb, t.size.width > 0, t.size.height > 0 {
                let k = min(area.width / t.size.width, area.height / t.size.height, 1.5)
                let sz = NSSize(width: t.size.width * k, height: t.size.height * k)
                let dst = NSRect(x: area.midX - sz.width / 2, y: area.midY - sz.height / 2, width: sz.width, height: sz.height)
                NSGraphicsContext.saveGraphicsState()
                t.draw(in: dst, from: .zero, operation: .sourceOver, fraction: it.minimized ? 0.55 : 1)
                NSGraphicsContext.restoreGraphicsState()
                NSColor.separatorColor.setStroke()
                NSBezierPath(rect: dst).stroke()
                it.icon?.draw(in: NSRect(x: dst.minX + 4, y: dst.minY + 4, width: 26, height: 26))
            } else if let ic = it.icon {
                let s: CGFloat = min(area.width, area.height, 72)
                ic.draw(in: NSRect(x: area.midX - s / 2, y: area.midY - s / 2, width: s, height: s),
                        from: .zero, operation: .sourceOver, fraction: it.minimized ? 0.55 : 1)
            }
            // подпись: название окна, а если его нет — название приложения
            var text = it.title.isEmpty ? it.appName : it.title
            if it.minimized { text += T(" — свёрнуто") }
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            (text as NSString).draw(in: NSRect(x: r.minX + 8, y: r.minY + 6, width: r.width - 16, height: 18),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: small ? 10 : 12),
                                                     .foregroundColor: NSColor.labelColor,
                                                     .paragraphStyle: para])
            // кнопки управления окном видны на плитке под курсором
            if i == hovered {
                let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
                let glyphs = ["×", "−", "+"]
                for k in 0..<3 {
                    let c = buttonCenter(i, k)
                    colors[k].setFill()
                    NSBezierPath(ovalIn: NSRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)).fill()
                    (glyphs[k] as NSString).draw(at: NSPoint(x: c.x - (k == 0 ? 3.5 : 3.2), y: c.y - 8),
                                                 withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold),
                                                                  .foregroundColor: NSColor.black.withAlphaComponent(0.55)])
                }
            }
        }
    }
}

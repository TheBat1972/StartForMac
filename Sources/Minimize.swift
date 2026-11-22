// «Свернуть всё» — функции бывшего приложения MinimizeAll, встроенные в «Пуск»:
// кнопка в строке меню, горячая клавиша, клик по иконке активного приложения в Dock.
import Cocoa
import UniformTypeIdentifiers
import Carbon.HIToolbox
import ServiceManagement
import Combine

// MARK: - Горячая клавиша (Carbon, не требует прав на ввод)

struct Combo {
    var keyCode: UInt32
    var mods: UInt32
    var keyTitle: String

    var title: String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey) != 0 { s += "⌥" }
        if mods & UInt32(shiftKey) != 0 { s += "⇧" }
        if mods & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyTitle
    }

    static let fallback = Combo(keyCode: 46, mods: UInt32(controlKey | optionKey), keyTitle: "M") // ⌃⌥M

    static let startFallback = Combo(keyCode: 35, mods: UInt32(controlKey | optionKey), keyTitle: "P") // ⌃⌥P

    static func load(prefix: String = "hk", fallback: Combo = Combo.fallback) -> Combo {
        let d = UserDefaults.standard
        guard d.object(forKey: prefix + ".code") != nil else { return fallback }
        return Combo(keyCode: UInt32(d.integer(forKey: prefix + ".code")),
                     mods: UInt32(d.integer(forKey: prefix + ".mods")),
                     keyTitle: d.string(forKey: prefix + ".title") ?? "?")
    }
    func save(prefix: String = "hk") {
        let d = UserDefaults.standard
        d.set(Int(keyCode), forKey: prefix + ".code")
        d.set(Int(mods), forKey: prefix + ".mods")
        d.set(keyTitle, forKey: prefix + ".title")
    }
}

func carbonMods(_ f: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if f.contains(.command) { m |= UInt32(cmdKey) }
    if f.contains(.option) { m |= UInt32(optionKey) }
    if f.contains(.control) { m |= UInt32(controlKey) }
    if f.contains(.shift) { m |= UInt32(shiftKey) }
    return m
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    /// id 1 — «Свернуть всё», id 2 — открыть/скрыть «Пуск»
    func register(_ c: Combo, id: UInt32, handler: @escaping () -> Void) {
        handlers[id] = handler
        if let r = refs[id] { UnregisterEventHotKey(r); refs[id] = nil }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                HotKeyCenter.shared.handlers[hk.id]?()
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        var ref: EventHotKeyRef?
        let hid = EventHotKeyID(signature: OSType(0x4D494E41), id: id)
        RegisterEventHotKey(c.keyCode, c.mods, hid, GetApplicationEventTarget(), 0, &ref)
        if let r = ref { refs[id] = r }
    }

    func unregister(id: UInt32) {
        if let r = refs[id] { UnregisterEventHotKey(r); refs[id] = nil }
        handlers[id] = nil
    }
}

// MARK: - Поиск окон приложения (несколько способов)

private typealias CreateWithTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let axHandle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
private let axCreateWithToken: CreateWithTokenFn? = dlsym(axHandle, "_AXUIElementCreateWithRemoteToken")
    .map { unsafeBitCast($0, to: CreateWithTokenFn.self) }
private let axGetWindow: GetWindowFn? = dlsym(axHandle, "_AXUIElementGetWindow")
    .map { unsafeBitCast($0, to: GetWindowFn.self) }

enum WindowFinder {
    static func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }
    static func isWindow(_ e: AXUIElement) -> Bool {
        (attr(e, kAXRoleAttribute) as? String) == kAXWindowRole
    }
    static func windowID(_ e: AXUIElement) -> CGWindowID? {
        guard let f = axGetWindow else { return nil }
        var id: CGWindowID = 0
        return f(e, &id) == .success && id != 0 ? id : nil
    }
    /// ID обычных окон приложения, видимых на экране
    static func screenWindowIDs(_ pid: pid_t) -> Set<CGWindowID> {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return Set(list.compactMap {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
                ? $0[kCGWindowNumber as String] as? CGWindowID : nil
        })
    }

    /// 1) AXWindows  2) AXChildren  3) AXMainWindow/AXFocusedWindow  4) перебор по remote token
    static func windows(pid: pid_t, log: ((String) -> Void)? = nil) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2.0)
        var result: [AXUIElement] = []
        var seen = Set<CGWindowID>()
        func add(_ w: AXUIElement) {
            if let id = windowID(w) { if seen.contains(id) { return }; seen.insert(id) }
            else if result.contains(where: { CFEqual($0, w) }) { return }
            result.append(w)
        }
        let byWindows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        byWindows.forEach(add)
        let byChildren = ((attr(app, kAXChildrenAttribute) as? [AXUIElement]) ?? []).filter(isWindow)
        byChildren.forEach(add)
        var byFocus = 0
        for a in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let v = attr(app, a), CFGetTypeID(v) == AXUIElementGetTypeID() { add(v as! AXUIElement); byFocus += 1 }
        }
        // Если на экране есть окна, которых мы ещё не нашли — перебираем элементы по токену
        let onScreen = screenWindowIDs(pid)
        var byToken = 0
        if let create = axCreateWithToken, !onScreen.subtracting(seen).isEmpty {
            var token = Data(count: 20)
            token.replaceSubrange(0..<4, with: withUnsafeBytes(of: Int32(pid)) { Data($0) })
            token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
            token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
            for elementID in UInt64(0)..<2000 {
                token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
                guard let el = create(token as CFData)?.takeRetainedValue() else { continue }
                AXUIElementSetMessagingTimeout(el, 0.3)
                guard isWindow(el), let id = windowID(el), onScreen.contains(id) else { continue }
                add(el); byToken += 1
                if onScreen.isSubset(of: seen) { break }
            }
        }
        log?("AXWindows \(byWindows.count), AXChildren \(byChildren.count), main/focused \(byFocus), token \(byToken); на экране \(onScreen.count), найдено \(result.count)")
        return result
    }
}

// MARK: - Сворачивание окон через Accessibility API

final class Minimizer {
    private var minimized: [AXUIElement] = []

    /// Есть ли на экране хоть одно видимое окно обычных приложений (кроме нашего)
    private func screenHasWindows() -> Bool {
        let pids = Set(appPids())
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.contains { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) > 50, (b["Height"] ?? 0) > 50 else { return false }
            return true
        }
    }

    /// Сворачивать ли и сам «Пуск» с его окнами (по умолчанию нет)
    static var includeSelf: Bool {
        get { UserDefaults.standard.bool(forKey: "minimizeSelf") }
        set { UserDefaults.standard.set(newValue, forKey: "minimizeSelf") }
    }

    /// Программы, чьи окна сворачиваем
    private func appPids() -> [pid_t] {
        let me = ProcessInfo.processInfo.processIdentifier
        let inc = Minimizer.includeSelf
        var a = NSWorkspace.shared.runningApplications.filter {
            ($0.activationPolicy == .regular || $0.bundleIdentifier == "com.apple.finder")
                && (inc || $0.processIdentifier != me)
        }.map { $0.processIdentifier }
        if inc && !a.contains(me) { a.append(me) }
        return a
    }

    static var restoreEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "restoreOnEmpty") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "restoreOnEmpty") }
    }

    /// Экран не пуст → свернуть всё. Экран пуст и есть что вернуть → вернуть свёрнутые окна.
    func toggle() {
        if Minimizer.restoreEnabled && !screenHasWindows() && !minimized.isEmpty { restore() } else { minimizeAll() }
    }

    func minimizeAll() {
        minimize(pids: appPids())
    }

    /// remember: запомнить окна для «вернуть» (заменяет прошлый список). Клик по Dock ничего не запоминает.
    func minimize(pids allPids: [pid_t], remember: Bool = true) {
        // Свои окна сворачиваем средствами AppKit в главном потоке: через Accessibility из фонового потока AppKit падает
        let me = ProcessInfo.processInfo.processIdentifier
        let pids = allPids.filter { $0 != me }
        if allPids.contains(me) { minimizeOwn(remember: remember) }
        DispatchQueue.global(qos: .userInteractive).async {
            let lock = NSLock()
            let key = kAXMinimizedAttribute as CFString
            func isMin(_ w: AXUIElement) -> Bool {
                var m: CFTypeRef?
                return AXUIElementCopyAttributeValue(w, key, &m) == .success && (m as? Bool) == true
            }

            // 1. Параллельно собираем окна всех приложений
            var targets: [AXUIElement] = []
            DispatchQueue.concurrentPerform(iterations: pids.count) { i in
                let wins = WindowFinder.windows(pid: pids[i]).filter {
                    var m: CFTypeRef?
                    return AXUIElementCopyAttributeValue($0, key, &m) == .success && (m as? Bool) == false
                }
                lock.lock(); targets += wins; lock.unlock()
            }
            guard !targets.isEmpty else { return }

            // 2. Сворачиваем все сразу, без пауз
            DispatchQueue.concurrentPerform(iterations: targets.count) { i in
                AXUIElementSetMessagingTimeout(targets[i], 1.0)
                _ = AXUIElementSetAttributeValue(targets[i], key, kCFBooleanTrue)
            }

            // 3. Одна общая проверка; кто не свернулся — жмём жёлтую кнопку
            usleep(250_000)
            let stubborn = targets.filter { !isMin($0) }
            DispatchQueue.concurrentPerform(iterations: stubborn.count) { i in
                if let b = WindowFinder.attr(stubborn[i], kAXMinimizeButtonAttribute),
                   CFGetTypeID(b) == AXUIElementGetTypeID() {
                    AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
                }
            }
            if remember { DispatchQueue.main.async { self.minimized = targets } }
        }
    }

    private var ownMinimized: [NSWindow] = []

    private func minimizeOwn(remember: Bool) {
        DispatchQueue.main.async {
            let ws = NSApp.windows.filter {
                $0.isVisible && !$0.isMiniaturized && $0.styleMask.contains(.miniaturizable) && !($0 is PopupWindow)
            }
            ws.forEach { $0.miniaturize(nil) }
            NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }     // само окно «Пуска» просто закрывается
            if remember { self.ownMinimized = ws }
        }
    }

    func restore() {
        let list = minimized
        minimized = []
        let own = ownMinimized
        ownMinimized = []
        DispatchQueue.main.async { own.forEach { $0.deminiaturize(nil) } }
        DispatchQueue.global(qos: .userInteractive).async {
            DispatchQueue.concurrentPerform(iterations: list.count) { i in
                AXUIElementSetAttributeValue(list[i], kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
        }
    }

}

// MARK: - Автозапуск при входе

enum LoginItem {
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/ru.local.StartMenu.plist")
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                return true
            } catch { return false }
        }
        // macOS 11–12: LaunchAgent
        if on {
            guard let exe = Bundle.main.executablePath else { return false }
            let plist: [String: Any] = [
                "Label": "ru.local.StartMenu",
                "ProgramArguments": [exe],
                "RunAtLoad": true
            ]
            do {
                try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                (plist as NSDictionary).write(to: agentURL, atomically: true)
                return true
            } catch { return false }
        } else {
            try? FileManager.default.removeItem(at: agentURL)
            return true
        }
    }
}

// MARK: - Клик по иконке активного приложения в Dock → свернуть его окна

final class DockClickWatcher {
    var onMinimize: ((pid_t) -> Void)?
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "dockClick") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dockClick") }
    }
    private var downMonitor: Any?
    private var upMonitor: Any?
    private var pending: (pid: pid_t, point: NSPoint)?

    func start() {
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.mouseDown()
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.mouseUp()
        }
    }

    private func mouseDown() {
        pending = nil
        guard enabled, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pt = NSEvent.mouseLocation
        // Запоминаем, какое приложение было активным ДО клика, и проверяем, что кликнули по его иконке
        guard let url = dockItemURL(at: pt),
              let frontURL = front.bundleURL,
              url.standardizedFileURL.resolvingSymlinksInPath().path
                == frontURL.standardizedFileURL.resolvingSymlinksInPath().path else { return }
        // Если у приложения нет видимых окон (всё свёрнуто), клик по иконке должен их вернуть, а не свернуть снова
        guard !WindowFinder.screenWindowIDs(front.processIdentifier).isEmpty else { return }
        pending = (front.processIdentifier, pt)
    }

    private func mouseUp() {
        guard let p = pending else { return }
        pending = nil
        let pt = NSEvent.mouseLocation
        guard abs(pt.x - p.point.x) < 5, abs(pt.y - p.point.y) < 5 else { return } // это был drag
        onMinimize?(p.pid)
    }

    /// URL приложения под курсором, если курсор на иконке приложения в Dock
    private func dockItemURL(at p: NSPoint) -> URL? {
        let h = NSScreen.screens.first?.frame.height ?? 0
        var el: AXUIElement?
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.2)
        guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(h - p.y), &el) == .success,
              let e = el else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(e, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock",
              (WindowFinder.attr(e, kAXSubroleAttribute) as? String) == "AXApplicationDockItem"
        else { return nil }
        if let u = WindowFinder.attr(e, kAXURLAttribute) {
            if let url = u as? URL { return url }
            if let str = u as? String { return URL(string: str) }
        }
        return nil
    }
}

// MARK: - Закрепление в Dock

enum DockPin {
    /// Окна, свёрнутые в Dock сейчас (нужен Accessibility; без него вернётся пусто)
    private static func minimizedWindows() -> [AXUIElement] {
        guard AXIsProcessTrusted() else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        let pids = NSWorkspace.shared.runningApplications.filter {
            ($0.activationPolicy == .regular || $0.bundleIdentifier == "com.apple.finder")
                && $0.processIdentifier != me
        }.map { $0.processIdentifier }
        var result: [AXUIElement] = []
        for pid in pids {
            for w in WindowFinder.windows(pid: pid) {
                var m: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m) == .success,
                   (m as? Bool) == true { result.append(w) }
            }
        }
        return result
    }

    /// Ставит «Пуск» первым значком в Dock — сразу справа от Finder (левее Finder встать нельзя).
    /// Перезапуск Dock разворачивает свёрнутые окна, поэтому запоминаем их и сворачиваем обратно.
    static func pinFirst(_ done: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = write()
            DispatchQueue.main.async { done?(ok) }
        }
    }

    private static func write() -> Bool {
        let domain = "com.apple.dock" as CFString
        let path = Bundle.main.bundlePath
        guard let bid = Bundle.main.bundleIdentifier else { return false }
        var apps = (CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]]) ?? []

        // убираем прежнюю запись «Пуск», чтобы не было дубля
        apps.removeAll { item in
            guard let td = item["tile-data"] as? [String: Any] else { return false }
            if (td["bundle-identifier"] as? String) == bid { return true }
            if let fd = td["file-data"] as? [String: Any], let u = fd["_CFURLString"] as? String,
               let url = URL(string: u), url.path == path { return true }
            return false
        }

        let url = URL(fileURLWithPath: path, isDirectory: true).absoluteString
        let tile: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": ["_CFURLString": url, "_CFURLStringType": 15],
                "file-label": "StartForMac",
                "bundle-identifier": bid,
                "file-type": 41
            ] as [String: Any]
        ]
        apps.insert(tile, at: 0)

        let wasMinimized = minimizedWindows()

        CFPreferencesSetAppValue("persistent-apps" as CFString, apps as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else { return false }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        do { try p.run() } catch { return false }
        p.waitUntilExit()

        // Dock поднялся и развернул окна — сворачиваем обратно те, что были свёрнуты
        if !wasMinimized.isEmpty {
            usleep(1_800_000)
            DispatchQueue.concurrentPerform(iterations: wasMinimized.count) { i in
                AXUIElementSetMessagingTimeout(wasMinimized[i], 1.0)
                _ = AXUIElementSetAttributeValue(wasMinimized[i], kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
        return true
    }
}

// MARK: - Контроллер «Свернуть всё» (строка меню + горячая клавиша + клик по Dock)

final class MinimizeController: NSObject, ObservableObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let minimizer = Minimizer()
    private var combo = Combo.load()
    private var startCombo = Combo.load(prefix: "start.hk", fallback: Combo.startFallback)
    private let dockWatcher = DockClickWatcher()
    private let pinch = PinchGesture()

    // Состояние настроек для окна «Настройки» внутри «Пуска»
    @Published var startComboTitle = ""
    @Published var minimizeComboTitle = ""
    @Published var pinchOn = false
    @Published var restoreOn = true
    @Published var selfOn = false
    @Published var dockOn = false
    @Published var loginOn = false
    /// Значок в верхней панели (строке меню); по умолчанию есть
    /// Окна по ⌃⌥ + стрелки (по умолчанию выключено)
    @Published var snapOn = WindowSnap.enabled
    /// Кнопка «+» — новый чистый рабочий стол (по умолчанию выключено)
    @Published var cleanDeskOn = CleanDesktop.shared.enabled
    /// ⌘X в Finder как «вырезать» (по умолчанию выключено)
    @Published var finderCutOn = FinderCut.enabled
    /// Переключение окон по ⌥Tab и миниатюры (по умолчанию оба выключены)
    @Published var switcherOn = WindowSwitcher.enabled
    @Published var thumbsOn = WindowSwitcher.thumbsEnabled
    /// Умный буфер обмена (⇧⌘V) и сколько записей хранить (по умолчанию выключен)
    @Published var dockPreviewOn = DockPreview.enabled
    /// Автоматический переключатель раскладки, его сочетание, исключения и флаг раскладки (по умолчанию всё выключено)
    @Published var layoutOn = LayoutSwitcher.enabled
    @Published var layoutAutoOn = LayoutSwitcher.autoFix
    @Published var layoutExcluded = LayoutSwitcher.excluded
    @Published var layoutComboTitle = LayoutSwitcher.loadCombo().title
    @Published var switchKind = LayoutKey.kind
    @Published var hideIndicatorOn = MinimizeController.systemIndicatorHidden()
    @Published var layoutFlagOn = LayoutFlag.enabled
    @Published var layoutStatusFlagOn = LayoutFlag.statusEnabled
    @Published var clipOn = ClipboardHistory.enabled
    @Published var clipLimit = ClipboardHistory.limit
    @Published var trayOn = (UserDefaults.standard.object(forKey: "ui.trayIcon") as? Bool) ?? true
    /// Идёт запись сочетания: 1 — «Свернуть всё», 2 — «Пуск»
    @Published var recordingFor: Int? = nil
    private var recordMonitor: Any?
    /// Открыть окно «Пуск» (задаёт AppDelegate)
    var openStart: (() -> Void)?
    /// Открыть/скрыть «Пуск» по горячей клавише (задаёт AppDelegate)
    var toggleStart: (() -> Void)?
    /// «Не давать уснуть»: переключить (задаёт AppDelegate) и текущее состояние для значка и меню
    var toggleAwake: (() -> Void)?
    private(set) var awakeOn = false

    /// Пока компьютеру не дают уснуть, значок в строке меню голубой (цвет акцента)
    func setAwake(_ on: Bool) {
        awakeOn = on
        setTrayIcon(on)
        statusItem.button?.toolTip = on
            ? T("Компьютеру не дают уснуть. Клик — свернуть все окна, правый клик — меню")
            : T("Клик — свернуть все окна (если экран пуст — вернуть), правый клик — меню")
    }

    /// Обычный значок — шаблонный (цвет задаёт система); при «не давать уснуть» — того же рисунка цвета акцента
    private func setTrayIcon(_ awake: Bool) {
        guard let b = statusItem.button,
              let base = NSImage(systemSymbolName: "rectangle.bottomhalf.inset.filled",
                                 accessibilityDescription: T("Свернуть все окна")) else { return }
        if awake, #available(macOS 12.0, *) {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor])
            let tinted = base.withSymbolConfiguration(cfg) ?? base
            tinted.isTemplate = false
            b.image = tinted
        } else {
            base.isTemplate = true
            b.image = base
        }
        b.contentTintColor = nil
    }

    func setCleanDesk(_ on: Bool) {
        CleanDesktop.shared.enabled = on
        cleanDeskOn = on
        if on { DispatchQueue.main.async { CleanDesktop.shared.checkPermissions() } }
    }

    func setSnap(_ on: Bool) {
        WindowSnap.enabled = on
        snapOn = on
        WindowSnap.registerAll(on)
        if on { _ = requestAccessibility(prompt: true) }
    }

    func setSwitcher(_ on: Bool) {
        WindowSwitcher.enabled = on
        switcherOn = on
        WindowSwitcher.shared.setEnabled(on)
        if on && thumbsOn && !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    func setThumbs(_ on: Bool) {
        WindowSwitcher.thumbsEnabled = on
        thumbsOn = on
        if on && (switcherOn || dockPreviewOn) && !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    func setLayout(_ on: Bool) {
        LayoutSwitcher.enabled = on
        layoutOn = on
        LayoutSwitcher.shared.setEnabled(on)             // сам просит доступ «Управление устройством и доступ к данным»
    }

    /// Системная плашка с буквой раскладки у текстового курсора (macOS Sonoma и новее)
    static func systemIndicatorHidden() -> Bool {
        let v = CFPreferencesCopyValue("TSMLanguageIndicatorEnabled" as CFString, kCFPreferencesAnyApplication,
                                       kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (v as? NSNumber)?.boolValue == false
    }

    func setHideIndicator(_ on: Bool) {
        // выключено системой = false; вернуть по умолчанию = убрать ключ
        let value: CFPropertyList? = on ? (NSNumber(value: false) as CFPropertyList) : nil
        CFPreferencesSetValue("TSMLanguageIndicatorEnabled" as CFString, value,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        hideIndicatorOn = MinimizeController.systemIndicatorHidden()
    }

    func setSwitchKind(_ k: String) {
        LayoutKey.kind = k
        switchKind = k
        LayoutKey.shared.apply()
    }

    func setLayoutAuto(_ on: Bool) {
        LayoutSwitcher.autoFix = on
        layoutAutoOn = on
    }

    func setLayoutFlag(_ on: Bool) {
        LayoutFlag.enabled = on
        layoutFlagOn = on
        LayoutFlag.shared.setEnabled(on)
    }

    func setLayoutStatusFlag(_ on: Bool) {
        LayoutFlag.statusEnabled = on
        layoutStatusFlagOn = on
        LayoutFlag.shared.setStatusEnabled(on)
    }

    func layoutAppTitle(_ id: String) -> String {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
        }
        return id
    }

    func addLayoutExcluded() {
        let p = NSOpenPanel()
        p.title = T("Программа, в которой переключатель раскладки не должен работать")
        p.allowedContentTypes = [.applicationBundle]
        p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        guard p.runModal() == .OK, let u = p.url, let id = Bundle(url: u)?.bundleIdentifier else { return }
        var list = LayoutSwitcher.excluded
        if !list.contains(id) { list.append(id) }
        LayoutSwitcher.excluded = list
        layoutExcluded = list
    }

    func removeLayoutExcluded(_ id: String) {
        let list = LayoutSwitcher.excluded.filter { $0 != id }
        LayoutSwitcher.excluded = list
        layoutExcluded = list
    }

    func setDockPreview(_ on: Bool) {
        DockPreview.enabled = on
        dockPreviewOn = on
        DockPreview.shared.setEnabled(on)
        // чтобы находить значок под курсором в Dock, нужен доступ «Управление устройством и доступ к данным»
        if on { _ = requestAccessibility(prompt: true) }
        if on && thumbsOn && !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    func setClip(_ on: Bool) {
        clipOn = on
        ClipboardHistory.shared.setEnabled(on)
        // автоматическая вставка (⌘V от имени программы) требует «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ») — просим при включении
        if on { _ = requestAccessibility(prompt: true) }
    }

    func setClipLimit(_ n: Int) {
        clipLimit = n
        ClipboardHistory.shared.setLimit(n)
    }

    func setFinderCut(_ on: Bool) {
        FinderCut.enabled = on
        finderCutOn = on
        FinderCut.shared.setEnabled(on)
    }

    func setTray(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "ui.trayIcon")
        trayOn = on
        statusItem.isVisible = on
    }

    func start() {
        statusItem.isVisible = trayOn
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "rectangle.bottomhalf.inset.filled",
                              accessibilityDescription: T("Свернуть все окна"))
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = T("Клик — свернуть все окна (если экран пуст — вернуть), правый клик — меню")
        }
        HotKeyCenter.shared.register(combo, id: 1) { [weak self] in self?.doToggle() }
        HotKeyCenter.shared.register(startCombo, id: 2) { [weak self] in self?.toggleStart?() }
        WindowSnap.registerAll(WindowSnap.enabled)
        CleanDesktop.shared.launch()
        if FinderCut.enabled { FinderCut.shared.start() }
        if ClipboardHistory.enabled { ClipboardHistory.shared.start() }
        if WindowSwitcher.enabled { WindowSwitcher.shared.start() }
        if DockPreview.enabled { DockPreview.shared.start() }
        if LayoutSwitcher.enabled { LayoutSwitcher.shared.start() }
        LayoutKey.shared.apply()
        if LayoutFlag.enabled { LayoutFlag.shared.setEnabled(true) }
        if LayoutFlag.statusEnabled { LayoutFlag.shared.setStatusEnabled(true) }
        NotificationCenter.default.addObserver(forName: .layoutFlagChanged, object: nil, queue: .main) { [weak self] _ in
            self?.layoutFlagOn = LayoutFlag.enabled              // флаг скрыли из его собственного меню
            self?.layoutStatusFlagOn = LayoutFlag.statusEnabled
        }
        pinch.onPinch = { [weak self] in self?.toggleStart?() }
        pinch.start()
        dockWatcher.onMinimize = { [weak self] pid in self?.minimizer.minimize(pids: [pid], remember: false) }
        dockWatcher.start()
        // после переименования или переезда программы автозапуск должен указывать на новый файл
        let here = Bundle.main.bundlePath
        if UserDefaults.standard.string(forKey: "login.path") != here {
            if LoginItem.isEnabled { LoginItem.set(false); LoginItem.set(true) }
            UserDefaults.standard.set(here, forKey: "login.path")
        }
        syncSettings()
    }

    func syncSettings() {
        startComboTitle = startCombo.title
        minimizeComboTitle = combo.title
        pinchOn = pinch.enabled
        restoreOn = Minimizer.restoreEnabled
        selfOn = Minimizer.includeSelf
        dockOn = dockWatcher.enabled
        loginOn = LoginItem.isEnabled
    }

    @discardableResult
    func requestAccessibility(prompt: Bool) -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func doToggle() {
        guard requestAccessibility(prompt: true) else { return }
        minimizer.toggle()
    }

    /// Только свернуть все окна (без «вернуть» при повторном нажатии) — кнопка в «Пуске»
    func minimizeOnly() {
        guard requestAccessibility(prompt: true) else { return }
        minimizer.minimizeAll()
    }

    @objc func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            doToggle()
        }
    }

    /// В строке меню: «Открыть «Пуск»», «Настройки…», «Не давать уснуть» и «Выход»; остальные настройки — внутри «Пуска»
    func showMenu() {
        let m = NSMenu()
        m.addItem(withTitle: T("Открыть «StartForMac»"), action: #selector(openStartMenu), keyEquivalent: "").target = self
        m.addItem(withTitle: T("Настройки…"), action: #selector(openSettingsItem), keyEquivalent: "").target = self
        let awake = m.addItem(withTitle: T("Не давать компьютеру уснуть"), action: #selector(toggleAwakeItem), keyEquivalent: "")
        awake.target = self
        awake.state = awakeOn ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: T("Выход"), action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = m
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func openStartMenu() { openStart?() }
    @objc func openSettingsItem() { (NSApp.delegate as? AppDelegate)?.openSettings() }
    @objc func toggleAwakeItem() { toggleAwake?() }
    @objc func quit() { NSApp.terminate(nil) }

    // MARK: Настройки (вызываются из окна «Настройки» в «Пуске»)

    func setPinch(_ on: Bool) { pinch.enabled = on; pinchOn = pinch.enabled; if on { pinch.restart() } }
    func pinchDiagnostic() -> String { pinch.diagnostic() }
    func setRestore(_ on: Bool) { Minimizer.restoreEnabled = on; restoreOn = on }
    func setSelf(_ on: Bool) { Minimizer.includeSelf = on; selfOn = on }
    func setDock(_ on: Bool) { dockWatcher.enabled = on; dockOn = dockWatcher.enabled }
    func setLogin(_ on: Bool) {
        if !LoginItem.set(on) { NSSound.beep() }
        loginOn = LoginItem.isEnabled
    }

    func pinToDock() {
        DockPin.pinFirst { ok in if !ok { NSSound.beep() } }
    }

    func cancelRecording() {
        if let m = recordMonitor { NSEvent.removeMonitor(m) }
        recordMonitor = nil
        recordingFor = nil
    }

    /// Записывает новое сочетание прямо в окне «Пуск» (без системных окон). Esc — отмена.
    func record(forStart: Bool) { record(slot: forStart ? 2 : 1) }

    /// slot: 1 — «Свернуть всё», 2 — «Пуск», 3 — исправление раскладки
    func record(slot: Int) {
        let forStart = slot == 2
        cancelRecording()
        recordingFor = slot
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return e }
            if e.keyCode == 53 { self.cancelRecording(); return nil }
            let mods = carbonMods(e.modifierFlags.intersection(.deviceIndependentFlagsMask))
            guard mods != 0 else { NSSound.beep(); return nil }
            var t = (e.charactersIgnoringModifiers ?? "").uppercased()
            if t.isEmpty || t.unicodeScalars.contains(where: { $0.value < 33 }) {
                t = e.keyCode == 49 ? "Space" : "#\(e.keyCode)"
            }
            let newCombo = Combo(keyCode: UInt32(e.keyCode), mods: mods, keyTitle: t)
            if slot == 3 {
                newCombo.save(prefix: "layout.hk")
                self.layoutComboTitle = newCombo.title
                LayoutSwitcher.shared.reregisterHotkey()
            } else if forStart {
                self.startCombo = newCombo
                newCombo.save(prefix: "start.hk")
                HotKeyCenter.shared.register(newCombo, id: 2) { [weak self] in self?.toggleStart?() }
            } else {
                self.combo = newCombo
                newCombo.save()
                HotKeyCenter.shared.register(newCombo, id: 1) { [weak self] in self?.doToggle() }
            }
            self.syncSettings()
            self.cancelRecording()
            return nil
        }
    }
}

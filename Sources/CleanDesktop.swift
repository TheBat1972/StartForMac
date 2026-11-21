import Cocoa
import ApplicationServices

// MARK: - Новые чистые рабочие столы (кнопка «+» на верхней панели)
//
// Кнопка создаёт новый рабочий стол macOS (Space) и переходит на него. На новом столе программа показывает своё окно:
// оно лежит на уровне значков рабочего стола, закрывает значки Finder копией обоев и показывает собственные значки —
// файлы из обычной локальной папки «Рабочие столы/Стол N» в домашней папке. Окно принадлежит только своему столу, поэтому
// при переключении ничего не пишется на диск и ничего не перекачивается в iCloud: система сама показывает нужное окно.
//
//  • Основной рабочий стол (любой, созданный не этой кнопкой) и его файлы не затрагиваются.
//  • Файлы на новый стол можно перетащить из Finder (они перемещаются в папку стола) и обратно — на основной стол.
//  • Если новый стол удалили (в Mission Control), программа спрашивает: переместить его файлы в Корзину,
//    перенести на основной рабочий стол или оставить папку как есть.
//
// Для нажатия «+» в Mission Control нужно разрешение «Управление устройством и доступ к данным» (Accessibility).
// Точная копия обоев — с разрешением «Запись экрана и системного звука»; без него берётся файл обоев. Выключено по умолчанию.

private typealias CDWindowImageFn = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
private let cdHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
private let cdWindowImage: CDWindowImageFn? = dlsym(cdHandle, "CGWindowListCreateImage")
    .map { unsafeBitCast($0, to: CDWindowImageFn.self) }

final class CleanDesktop: ObservableObject {
    static let shared = CleanDesktop()

    private static let key = "cleanDesktop.enabled"
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: CleanDesktop.key) as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(enabled, forKey: CleanDesktop.key)
            if oldValue != enabled { enabled ? start() : stop() }
        }
    }
    @Published var busy = false

    struct Desk: Codable {
        /// путь папки стола относительно домашней папки
        var folder: String
    }
    private struct State: Codable {
        /// «UUID стола macOS» → папка. Основной стол в списке не хранится
        var desktops: [String: Desk] = [:]
    }
    /// Состояние прежней версии (файлы прятались признаком «скрытый»)
    private struct LegacyState: Codable {
        var hidden: [String] = []
    }

    private var state = State()
    private var loaded = false
    private var observer: NSObjectProtocol?
    private var pendingSync: DispatchWorkItem?
    private var timer: Timer?
    private var panels: [String: DeskPanel] = [:]
    private var misses: [String: Int] = [:]
    private var asking = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var supportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StartForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private var storeURL: URL { supportURL.appendingPathComponent("desktops.json") }

    private init() {}

    // MARK: Запуск, включение, выключение

    /// Вызывается при старте программы
    func launch() {
        load()
        restoreLegacy()
        if enabled { start() }
    }

    private func start() {
        load()
        if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.sync()
            }
        }
        // удаление стола в Mission Control не всегда даёт сигнал о смене стола, поэтому ещё и проверяем несколько раз в секунду
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.sync() }
        }
        sync()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        if let o = observer { NSWorkspace.shared.notificationCenter.removeObserver(o); observer = nil }
        pendingSync?.cancel()
        for k in Array(panels.keys) { closePanel(k) }
        misses = [:]
    }

    // MARK: Файл состояния

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: storeURL), let s = try? JSONDecoder().decode(State.self, from: d) { state = s }
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(state) else { return }
        try? d.write(to: storeURL, options: .atomic)
    }

    /// Прежняя версия прятала файлы основного стола признаком «скрытый»: при первом запуске новой версии всё возвращается
    private func restoreLegacy() {
        let old = supportURL.appendingPathComponent("clean-desktops.json")
        guard let d = try? Data(contentsOf: old) else { return }
        if let s = try? JSONDecoder().decode(LegacyState.self, from: d) {
            let desktop = home.appendingPathComponent("Desktop")
            for n in s.hidden {
                var u = desktop.appendingPathComponent(n)
                guard FileManager.default.fileExists(atPath: u.path) else { continue }
                var v = URLResourceValues()
                v.isHidden = false
                if (try? u.setResourceValues(v)) == nil {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
                    p.arguments = ["nohidden", u.path]
                    try? p.run()
                    p.waitUntilExit()
                }
            }
        }
        try? FileManager.default.removeItem(at: old)
    }

    // MARK: Папки столов

    private func folderURL(_ d: Desk) -> URL { home.appendingPathComponent(d.folder, isDirectory: true) }

    private func visibleItems(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])) ?? []
    }

    /// Запоминает новый стол и создаёт для него папку «Рабочие столы/Стол N»
    private func registerDesk(_ key: String) {
        guard state.desktops[key] == nil else { return }
        let root = T("Рабочие столы")
        let used = Set(state.desktops.values.map { $0.folder })
        var n = 2
        var rel = ""
        repeat {
            rel = root + "/" + T("Стол") + " \(n)"
            n += 1
        } while used.contains(rel) || FileManager.default.fileExists(atPath: home.appendingPathComponent(rel).path)
        try? FileManager.default.createDirectory(at: home.appendingPathComponent(rel), withIntermediateDirectories: true)
        state.desktops[key] = Desk(folder: rel)
        save()
    }

    // MARK: Столы macOS (закрытые вызовы системы читаем без привязки при сборке)

    private func spacesInfo() -> (active: String, all: Set<String>)? {
        typealias ConnFn = @convention(c) () -> Int32
        typealias ActiveFn = @convention(c) (Int32) -> UInt64
        typealias ListFn = @convention(c) (Int32) -> UnsafeRawPointer?
        let def = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
        guard let c = dlsym(def, "CGSMainConnectionID"),
              let a = dlsym(def, "CGSGetActiveSpace"),
              let l = dlsym(def, "CGSCopyManagedDisplaySpaces") else { return nil }
        let conn = unsafeBitCast(c, to: ConnFn.self)()
        let activeID = unsafeBitCast(a, to: ActiveFn.self)(conn)
        guard let raw = unsafeBitCast(l, to: ListFn.self)(conn),
              let displays = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue() as? [[String: Any]] else { return nil }
        var all = Set<String>()
        var active: String?
        for d in displays {
            for sp in (d["Spaces"] as? [[String: Any]]) ?? [] {
                let id = (sp["id64"] as? NSNumber)?.uint64Value ?? 0
                let uuid = (sp["uuid"] as? String) ?? ""
                let key = uuid.isEmpty ? "id\(id)" : uuid
                all.insert(key)
                if id == activeID { active = key }
            }
        }
        guard let act = active, !all.isEmpty else { return nil }
        return (act, all)
    }

    // MARK: Синхронизация окон со столами

    private func sync() {
        guard enabled, !asking, let info = spacesInfo() else { return }

        // 1. Окно удалённого стола система переносит на соседний: сразу убираем, чтобы оно не закрыло основной стол
        for (k, p) in panels where p.isOnActiveSpace && k != info.active { closePanel(k) }

        // 2. Удалённые столы (стол должен пропасть из списка два раза подряд — защита от случайного сбоя чтения)
        for (k, d) in state.desktops {
            if info.all.contains(k) { misses[k] = nil; continue }
            misses[k, default: 0] += 1
            if misses[k]! >= 2 { handleRemoved(k, d); misses[k] = nil }
        }

        // 3. На новом столе — своё окно
        if state.desktops[info.active] != nil, panels[info.active] == nil { showPanel(info.active) }
    }

    private func showPanel(_ key: String) {
        guard let d = state.desktops[key], let screen = NSScreen.screens.first else { return }
        let folder = folderURL(d)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let p = DeskPanel(screen: screen, folder: folder, wallpaper: fileWallpaper(screen))
        p.onRefreshWallpaper = { [weak self, weak p] in
            guard let self = self, let p = p, let s = NSScreen.screens.first else { return }
            p.setWallpaper(self.capturedWallpaper(s) ?? self.fileWallpaper(s))
        }
        p.onMoveToMain = { [weak self] urls in self?.moveToMain(urls) }
        panels[key] = p
        p.orderFrontRegardless()
        // точная копия обоев (нужно разрешение «Запись экрана»): подставляем, когда стол уже показан
        if CGPreflightScreenCaptureAccess() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak p] in
                guard let self = self, let p = p, let s = NSScreen.screens.first, let img = self.capturedWallpaper(s) else { return }
                p.setWallpaper(img)
            }
        }
    }

    private func closePanel(_ key: String) {
        guard let p = panels.removeValue(forKey: key) else { return }
        p.shutdown()
        p.orderOut(nil)
    }

    // MARK: Обои

    /// Обои из файла (быстрый запасной вариант)
    private func fileWallpaper(_ screen: NSScreen) -> NSImage? {
        guard var u = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
            let files = ((try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["jpg", "jpeg", "png", "heic", "tif", "tiff"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard let f = files.first else { return nil }
            u = f
        }
        return NSImage(contentsOf: u)
    }

    /// Точная копия того, что сейчас нарисовано как обои (без значков), — через снимок окна обоев
    private func capturedWallpaper(_ screen: NSScreen) -> NSImage? {
        guard CGPreflightScreenCaptureAccess(), let fn = cdWindowImage,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let deskLevel = Int(CGWindowLevelForKey(.desktopWindow))
        var best: (id: CGWindowID, area: CGFloat)?
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == deskLevel,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary),
                  abs(r.width - screen.frame.width) < 2, abs(r.height - screen.frame.height) < 2 else { continue }
            if best == nil || r.width * r.height > best!.area { best = (CGWindowID(id), r.width * r.height) }
        }
        guard let b = best,
              let cg = fn(.null, UInt32(CGWindowListOption.optionIncludingWindow.rawValue), b.id,
                          UInt32(CGWindowImageOption.bestResolution.rawValue))?.takeRetainedValue(),
              cg.width > 100 else { return nil }
        return NSImage(cgImage: cg, size: screen.frame.size)
    }

    // MARK: Удаление стола и перенос файлов

    private func uniqueURL(_ dir: URL, _ name: String) -> URL {
        var u = dir.appendingPathComponent(name)
        var n = 2
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return u
    }

    /// Переносит файлы на основной рабочий стол (папка «Рабочий стол»). Возвращает, сколько не удалось
    @discardableResult
    private func moveToMain(_ urls: [URL]) -> Int {
        let desktop = home.appendingPathComponent("Desktop")
        var failed: [String] = []
        for u in urls {
            let dst = uniqueURL(desktop, u.lastPathComponent)
            do { try FileManager.default.moveItem(at: u, to: dst) }
            catch { failed.append(u.lastPathComponent + " — " + (error as NSError).localizedDescription) }
        }
        if !failed.isEmpty {
            alert(T("Не удалось перенести на основной рабочий стол"), failed.prefix(6).joined(separator: "\n"))
        }
        return failed.count
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.window.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        a.layout()
        a.window.center()
        a.runModal()
    }

    /// Стол удалён: спрашиваем, что сделать с его файлами и ярлыками
    private func handleRemoved(_ key: String, _ d: Desk) {
        closePanel(key)
        let folder = folderURL(d)
        let items = visibleItems(in: folder)
        if items.isEmpty {
            try? FileManager.default.removeItem(at: folder)   // пустая папка не нужна
        } else {
            asking = true
            defer { asking = false }
            let shown = items.prefix(8).map { $0.lastPathComponent }.joined(separator: "\n")
            let more = items.count > 8 ? "\n…" : ""
            let a = NSAlert()
            a.messageText = T("Рабочий стол удалён")
            a.informativeText = T("На нём остались файлы:") + "\n\n" + shown + more + "\n\n" + T("Что с ними сделать?")
            a.addButton(withTitle: T("Переместить в Корзину"))
            a.addButton(withTitle: T("Перенести на основной стол"))
            a.addButton(withTitle: T("Оставить папку"))
            a.window.collectionBehavior.insert(.moveToActiveSpace)
            a.window.level = .modalPanel
            NSApp.activate(ignoringOtherApps: true)
            a.layout()
            a.window.center()          // строго по центру экрана
            a.window.makeKeyAndOrderFront(nil)
            switch a.runModal() {
            case .alertFirstButtonReturn:
                do { try FileManager.default.trashItem(at: folder, resultingItemURL: nil) }
                catch {
                    // запасной путь: системная служба «переместить в Корзину»
                    NSWorkspace.shared.recycle([folder]) { _, err in
                        if let err = err {
                            DispatchQueue.main.async {
                                self.alert(T("Не удалось переместить в Корзину"), err.localizedDescription)
                            }
                        }
                    }
                }
            case .alertSecondButtonReturn:
                if moveToMain(items) == 0 { try? FileManager.default.removeItem(at: folder) }
            default:
                break
            }
        }
        state.desktops[key] = nil
        save()
    }

    // MARK: Создание нового стола

    private func ax(_ e: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v : nil
    }

    private func kids(_ e: AXUIElement) -> [AXUIElement] {
        (ax(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private func ident(_ e: AXUIElement) -> String {
        (ax(e, "AXIdentifier") as? String) ?? ""
    }

    private func find(_ root: AXUIElement, _ depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(root) { return root }
        if depth >= 9 { return nil }
        for c in kids(root) {
            if let r = find(c, depth + 1, match) { return r }
        }
        return nil
    }

    /// Описание дерева элементов Dock (для отчёта об ошибке): понять, как устроен Mission Control в этой версии macOS
    private var lastReport = ""

    private func dump(_ e: AXUIElement, _ depth: Int, _ out: inout [String]) {
        if depth > 8 || out.count > 400 { return }
        let role = (ax(e, kAXRoleAttribute as String) as? String) ?? "?"
        let id = ident(e)
        let desc = (ax(e, kAXDescriptionAttribute as String) as? String) ?? ""
        let title = (ax(e, kAXTitleAttribute as String) as? String) ?? ""
        out.append(String(repeating: "  ", count: depth) + "\(role) id=\(id) desc=\(desc) title=\(title)")
        for c in kids(e) { dump(c, depth + 1, &out) }
    }

    private func attrNames(_ e: AXUIElement) -> String {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(e, &names) == .success, let n = names as? [String] else { return "?" }
        return n.joined(separator: ",")
    }

    private func report(_ roots: [AXUIElement], _ step: String) {
        var out = ["macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", "шаг: \(step)"]
        for app in roots {
            out.append("=== процесс: атрибуты \(attrNames(app))")
            dump(app, 0, &out)
            if let wins = ax(app, "AXWindows") as? [AXUIElement] {
                out.append("--- AXWindows: \(wins.count)")
                for w in wins { dump(w, 0, &out) }
            }
        }
        // какие окна есть на экране у служебных процессов
        let want: Set<String> = ["Dock", "WindowManager", "Mission Control", "SystemUIServer", "ControlCenter", "Spaces"]
        out.append("--- окна служебных процессов")
        if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
            for w in list {
                let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
                guard want.contains(owner) else { continue }
                let name = (w[kCGWindowName as String] as? String) ?? ""
                let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
                let b = (w[kCGWindowBounds as String] as? [String: Any]) ?? [:]
                out.append("\(owner) \"\(name)\" layer=\(layer) bounds=\(b)")
            }
        }
        // запущены ли процессы, связанные с Mission Control
        out.append("--- процессы")
        for a in NSWorkspace.shared.runningApplications {
            let n = a.localizedName ?? ""
            if n.contains("Mission") || n.contains("Dock") || n.contains("WindowManager") || n.contains("Spaces") {
                out.append("\(n) \(a.bundleIdentifier ?? "") pid=\(a.processIdentifier)")
            }
        }
        lastReport = out.joined(separator: "\n")
    }

    /// Кнопка «+» в полосе столов: по идентификатору (macOS 12–15) или по подписи («Add Desktop» / «Добавить рабочий стол»)
    private func isAddButton(_ e: AXUIElement) -> Bool {
        if ident(e).hasPrefix("mc.spaces.add") { return true }
        guard (ax(e, kAXRoleAttribute as String) as? String) == "AXButton" else { return false }
        let text = [(ax(e, kAXDescriptionAttribute as String) as? String) ?? "",
                    (ax(e, kAXTitleAttribute as String) as? String) ?? ""].joined(separator: " ").lowercased()
        return text.contains("add desktop") || text.contains("add space") || text.contains("добавить рабочий стол")
            || text.contains("добавить пространство")
    }

    private func pressEscape() {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func wait(_ seconds: Double, until cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cond() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return cond()
    }

    private func ask(title: String, text: String, open: () -> Void) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: T("Открыть настройки"))
        a.addButton(withTitle: T("Позже"))
        if a.runModal() == .alertFirstButtonReturn { open() }
    }

    /// Проверяет разрешение. Если его нет — объясняет, что это и зачем, и открывает нужный раздел Системных настроек
    @discardableResult
    func checkPermissions() -> Bool {
        if !Permissions.hasAccessibility() {
            ask(title: T("Нужно разрешение «Управление устройством и доступ к данным»"),
                text: T("Чтобы «StartForMac» сам нажал «+» в Mission Control и создал новый рабочий стол, macOS требует разрешение «Управление устройством и доступ к данным» (по-английски Accessibility; в ранних версиях macOS: «Универсальный доступ»).\n\nСейчас откроются Системные настройки → Конфиденциальность и безопасность. Найдите пункт «Управление устройством и доступ к данным» и включите переключатель у «StartForMac». Если программы нет в списке, нажмите «+» под списком и выберите её в папке «Программы».\n\nПосле этого вернитесь в «StartForMac»; если кнопка «+» не заработает, перезапустите программу."),
                open: { Permissions.requestAccessibility(); Permissions.openAccessibilityPane() })
            return false
        }
        return true
    }

    func create() {
        guard enabled, !busy else { return }
        guard checkPermissions() else { return }
        guard let before = spacesInfo() else {
            fail(T("Не удалось определить текущий рабочий стол."))
            return
        }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ok = self.createSpaceViaMissionControl(known: before.all)
            DispatchQueue.main.async {
                self.busy = false
                if !ok {
                    var msg = T("Не удалось создать рабочий стол или перейти на него.") + "\n\n" + T("Если стол создался, но переход не сработал, включите в Системных настройках → Клавиатура → Сочетания клавиш → Mission Control пункт «Переместить вправо на одно пространство» (⌃→).")
                    if !self.lastReport.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(self.lastReport, forType: .string)
                        msg += "\n\n" + T("Отчёт об ошибке скопирован в буфер обмена: вставьте его в чат разработчику.")
                    }
                    self.fail(msg)
                }
            }
        }
    }

    /// Рамка полосы со столами сверху в Mission Control (в новых macOS её рисует процесс WindowManager)
    private func spacesBarFrame() -> CGRect {
        if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
            for w in list where (w[kCGWindowName as String] as? String) == "Spaces Bar" {
                if let b = w[kCGWindowBounds as String] as? NSDictionary,
                   let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.width > 100 { return r }
            }
        }
        return NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func click(_ p: CGPoint) {
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    /// ⌃→ — перейти на следующий рабочий стол
    private func pressCtrlRight() {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 124, keyDown: down)
            e?.flags = [.maskControl, .maskSecondaryFn]
            e?.post(tap: .cghidEventTap)
        }
    }

    private func createSpaceViaMissionControl(known: Set<String>) -> Bool {
        // в разных версиях macOS Mission Control рисует то Dock, то WindowManager: смотрим оба процесса
        var roots: [AXUIElement] = []
        for id in ["com.apple.dock", "com.apple.WindowManager"] {
            if let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                roots.append(AXUIElementCreateApplication(a.processIdentifier))
            }
        }
        guard !roots.isEmpty else { return false }
        lastReport = ""
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        Thread.sleep(forTimeInterval: 0.9)
        // полоса со столами раскрывается и показывает «+», когда курсор у верхнего края экрана
        let top = CGPoint(x: (NSScreen.screens.first?.frame.width ?? 800) / 2, y: 6)
        CGWarpMouseCursorPosition(top)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: top, mouseButton: .left)?.post(tap: .cghidEventTap)

        func newSpace() -> String? { spacesInfo()?.all.subtracting(known).first }
        var newKey: String?

        // 1. кнопка «+» через Accessibility
        var addButton: AXUIElement?
        _ = wait(3) {
            for r in roots where addButton == nil {
                addButton = find(r) { isAddButton($0) }
            }
            return addButton != nil
        }
        if let add = addButton, AXUIElementPerformAction(add, kAXPressAction as CFString) == .success {
            _ = wait(3) { newKey = newSpace(); return newKey != nil }
        }

        // 2. запасной путь: щелчок по «+» в правом верхнем углу полосы со столами
        if newKey == nil {
            let bar = spacesBarFrame()
            for (dx, dy) in [(32.0, 36.0), (48.0, 52.0), (24.0, 24.0), (60.0, 40.0)] {
                click(CGPoint(x: bar.maxX - dx, y: bar.minY + dy))
                if wait(1.5, until: { newKey = newSpace(); return newKey != nil }) { break }
            }
        }
        guard let key = newKey else {
            report(roots, "стол не создан: кнопка «+» не найдена и щелчок по углу не помог")
            pressEscape()
            return false
        }

        // запомнить новый стол ДО переключения на него, иначе он сочтётся основным и файлы основного откроются
        DispatchQueue.main.sync { self.registerDesk(key) }

        // 3. выйти из Mission Control и перейти на новый стол сочетанием ⌃→ (он создаётся последним)
        pressEscape()
        Thread.sleep(forTimeInterval: 0.9)
        for _ in 0..<12 {
            if spacesInfo()?.active == key { return true }
            pressCtrlRight()
            Thread.sleep(forTimeInterval: 0.7)
        }
        if spacesInfo()?.active == key { return true }
        lastReport = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nстол создан, но перейти на него не удалось (⌃→)"
        return false
    }

    private func fail(_ message: String) {
        let a = NSAlert()
        a.messageText = T("Новый рабочий стол")
        a.informativeText = message
        a.runModal()
    }
}

// MARK: - Окно нового рабочего стола: обои и значки

final class DeskPanel: NSPanel {
    var onRefreshWallpaper: (() -> Void)? { didSet { deskView.onRefreshWallpaper = onRefreshWallpaper } }
    var onMoveToMain: (([URL]) -> Void)? { didSet { deskView.onMoveToMain = onMoveToMain } }
    private let deskView: DeskView

    init(screen: NSScreen, folder: URL, wallpaper: NSImage?) {
        deskView = DeskView(screen: screen, folder: folder, wallpaper: wallpaper)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        // на один уровень выше значков рабочего стола Finder и ниже всех обычных окон
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.ignoresCycle, .fullScreenNone]
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        isReleasedWhenClosed = false
        contentView = deskView
        setFrame(screen.frame, display: false)
        makeFirstResponder(deskView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func setWallpaper(_ img: NSImage?) { deskView.setWallpaper(img) }
    func shutdown() { deskView.stopWatching() }
}

final class DeskView: NSView, NSDraggingSource {
    var onRefreshWallpaper: (() -> Void)?
    var onMoveToMain: (([URL]) -> Void)?

    private let screen: NSScreen
    private let folder: URL
    private var wallpaper: NSImage?
    private var items: [URL] = []
    private var selection = Set<URL>()
    private var icons: [URL: NSImage] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var downPoint = NSPoint.zero
    private var dragCandidate = false
    /// Положение значков: имя файла → [колонка, строка] (колонки считаются справа, строки сверху); хранится в папке стола
    private var slots: [String: [Int]] = [:]
    private var grabbedName: String?
    private var layoutURL: URL { folder.appendingPathComponent(".layout.json") }

    private let cellW: CGFloat = 96
    private let cellH: CGFloat = 108
    private let iconSize: CGFloat = 52

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(screen: NSScreen, folder: URL, wallpaper: NSImage?) {
        self.screen = screen
        self.folder = folder
        self.wallpaper = wallpaper
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        registerForDraggedTypes([.fileURL])
        if let d = try? Data(contentsOf: layoutURL),
           let m = try? JSONDecoder().decode([String: [Int]].self, from: d) { slots = m }
        reload()
        startWatching()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setWallpaper(_ img: NSImage?) {
        wallpaper = img
        needsDisplay = true
    }

    // MARK: Содержимое папки

    private func startWatching() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in self?.reload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func reload() {
        let list = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        items = list.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        selection = selection.filter { items.contains($0) }
        icons = icons.filter { items.contains($0.key) }
        assignSlots()
        needsDisplay = true
    }

    // MARK: Свободное размещение значков (по сетке)

    private var rows: Int { max(1, Int((area.height - 8) / cellH)) }
    private var cols: Int { max(1, Int((area.width - 8) / cellW)) }

    private func saveLayout() {
        if let d = try? JSONEncoder().encode(slots) { try? d.write(to: layoutURL, options: .atomic) }
    }

    /// Каждому файлу — своя ячейка: запомненная, а новым — первая свободная
    private func assignSlots() {
        let r = rows, c = cols
        var taken = Set<Int>()
        var result: [String: [Int]] = [:]
        for u in items {
            let n = u.lastPathComponent
            if let s = slots[n], s.count == 2, s[0] >= 0, s[1] >= 0, s[0] < c, s[1] < r, !taken.contains(s[0] * r + s[1]) {
                result[n] = s
                taken.insert(s[0] * r + s[1])
            }
        }
        var next = 0
        for u in items where result[u.lastPathComponent] == nil {
            while taken.contains(next) && next < r * c { next += 1 }
            let k = min(next, r * c - 1)
            result[u.lastPathComponent] = [k / r, k % r]
            taken.insert(k)
        }
        if result != slots {
            slots = result
            saveLayout()
        }
    }

    /// Ячейка под точкой
    private func slot(at p: NSPoint) -> (Int, Int) {
        let a = area
        let col = Int(((a.maxX - 6 - p.x) / cellW).rounded(.up)) - 1
        let row = Int(((p.y - a.minY - 6) / cellH).rounded(.down))
        return (min(max(col, 0), cols - 1), min(max(row, 0), rows - 1))
    }

    /// Ближайшая свободная ячейка к заданной (занятыми считаются ячейки файлов, кроме перечисленных)
    private func freeSlot(near t: (Int, Int), ignoring: Set<String>, extraTaken: Set<Int> = []) -> [Int] {
        let r = rows, c = cols
        var taken = extraTaken
        for (n, s) in slots where !ignoring.contains(n) && s.count == 2 { taken.insert(s[0] * r + s[1]) }
        var best: (Int, Int)?
        var bestD = Int.max
        for col in 0..<c {
            for row in 0..<r where !taken.contains(col * r + row) {
                let d = (col - t.0) * (col - t.0) + (row - t.1) * (row - t.1)
                if d < bestD { bestD = d; best = (col, row) }
            }
        }
        let b = best ?? (0, 0)
        return [b.0, b.1]
    }

    private func icon(_ u: URL) -> NSImage {
        if let i = icons[u] { return i }
        let i = NSWorkspace.shared.icon(forFile: u.path)
        i.size = NSSize(width: iconSize, height: iconSize)
        icons[u] = i
        return i
    }

    // MARK: Раскладка: колонки справа налево, сверху вниз — как у Finder

    private var area: NSRect {
        let sf = screen.frame, vf = screen.visibleFrame
        return NSRect(x: vf.minX - sf.minX, y: sf.maxY - vf.maxY, width: vf.width, height: vf.height)
    }

    private func rect(_ i: Int) -> NSRect {
        let a = area
        let s = slots[items[i].lastPathComponent] ?? [0, 0]
        return NSRect(x: a.maxX - cellW * CGFloat(s[0] + 1) - 6, y: a.minY + 6 + cellH * CGFloat(s[1]), width: cellW, height: cellH)
    }

    private func index(at p: NSPoint) -> Int? {
        items.indices.first { rect($0).contains(p) }
    }

    // MARK: Рисование

    override func draw(_ dirtyRect: NSRect) {
        if let w = wallpaper, w.size.width > 0, w.size.height > 0 {
            let k = max(bounds.width / w.size.width, bounds.height / w.size.height)
            let r = NSRect(x: (bounds.width - w.size.width * k) / 2, y: (bounds.height - w.size.height * k) / 2,
                           width: w.size.width * k, height: w.size.height * k)
            w.draw(in: r, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            NSColor(white: 0.18, alpha: 1).setFill()
            bounds.fill()
        }

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingMiddle

        for (i, u) in items.enumerated() {
            let r = rect(i)
            guard r.intersects(dirtyRect) else { continue }
            let sel = selection.contains(u)
            if sel {
                NSColor.white.withAlphaComponent(0.20).setFill()
                NSBezierPath(roundedRect: NSRect(x: r.midX - iconSize / 2 - 6, y: r.minY + 2, width: iconSize + 12, height: iconSize + 12),
                             xRadius: 7, yRadius: 7).fill()
            }
            icon(u).draw(in: NSRect(x: r.midX - iconSize / 2, y: r.minY + 8, width: iconSize, height: iconSize),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

            let name = u.lastPathComponent as NSString
            let textRect = NSRect(x: r.minX + 2, y: r.minY + iconSize + 16, width: cellW - 4, height: 32)
            if sel {
                let tw = min(cellW - 4, name.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 10)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: r.midX - tw / 2, y: textRect.minY - 1, width: tw, height: 17),
                             xRadius: 4, yRadius: 4).fill()
                name.draw(with: textRect, options: [.usesLineFragmentOrigin],
                          attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white, .paragraphStyle: para])
            } else {
                name.draw(with: textRect, options: [.usesLineFragmentOrigin],
                          attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white,
                                       .shadow: shadow, .paragraphStyle: para])
            }
        }
    }

    // MARK: Мышь

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        downPoint = p
        dragCandidate = false
        guard let i = index(at: p) else {
            if !e.modifierFlags.contains(.command) { selection = [] }
            needsDisplay = true
            return
        }
        let u = items[i]
        if e.clickCount >= 2 {
            NSWorkspace.shared.open(u)
            return
        }
        if e.modifierFlags.contains(.command) {
            if selection.contains(u) { selection.remove(u) } else { selection.insert(u) }
        } else if !selection.contains(u) {
            selection = [u]
        }
        dragCandidate = selection.contains(u)
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard dragCandidate else { return }
        let p = convert(e.locationInWindow, from: nil)
        guard hypot(p.x - downPoint.x, p.y - downPoint.y) > 4 else { return }
        dragCandidate = false
        grabbedName = index(at: downPoint).map { items[$0].lastPathComponent }
        let drag: [NSDraggingItem] = items.enumerated().compactMap { (i, u) in
            guard selection.contains(u) else { return nil }
            let di = NSDraggingItem(pasteboardWriter: u as NSURL)
            let r = rect(i)
            di.setDraggingFrame(NSRect(x: r.midX - iconSize / 2, y: r.minY + 8, width: iconSize, height: iconSize), contents: icon(u))
            return di
        }
        guard !drag.isEmpty else { return }
        beginDraggingSession(with: drag, event: e, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.move, .copy, .generic] : [.move]
    }

    /// Отпустили значок на самом столе — ставим его в ту ячейку, куда отпустили (остальные выделенные — со сдвигом)
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { grabbedName = nil }
        guard let w = window, let g = grabbedName, let g0 = slots[g], g0.count == 2,
              NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0) == w.windowNumber else { return }
        let target = slot(at: convert(w.convertPoint(fromScreen: screenPoint), from: nil))
        let dc = target.0 - g0[0], dr = target.1 - g0[1]
        let moving = Set(selection.map { $0.lastPathComponent })
        guard !moving.isEmpty, dc != 0 || dr != 0 else { return }
        let r = rows, c = cols
        var newTaken = Set<Int>()
        var updated: [String: [Int]] = [:]
        for n in moving.sorted() {
            guard let s = slots[n], s.count == 2 else { continue }
            let want = (min(max(s[0] + dc, 0), c - 1), min(max(s[1] + dr, 0), r - 1))
            // ячейка может быть занята другим значком или уже выбрана для другого перемещаемого
            let f = freeSlot(near: want, ignoring: moving, extraTaken: newTaken)
            updated[n] = f
            newTaken.insert(f[0] * r + f[1])
        }
        for (n, s) in updated { slots[n] = s }
        saveLayout()
        needsDisplay = true
    }

    // MARK: Клавиатура

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let m = e.modifierFlags.intersection([.command, .shift, .option, .control])
        guard m.contains(.command) else { return false }
        if m == [.command] {
            switch e.keyCode {
            case 8: copySelection(cut: false)                                   // ⌘C
            case 7:                                                             // ⌘X (если включено «⌘X — вырезать»)
                guard FinderCut.enabled else { return false }
                copySelection(cut: true)
            case 9: pasteFiles(move: FinderCut.shared.cutPending)               // ⌘V
            case 0: selection = Set(items); needsDisplay = true                 // ⌘A
            case 51, 117: trash(selected())                                     // ⌘⌫ — в Корзину
            case 31, 125: selected().forEach { NSWorkspace.shared.open($0) }   // ⌘O / ⌘↓
            default: return false
            }
            return true
        }
        if m == [.command, .option], e.keyCode == 9 {                           // ⌘⌥V — «Переместить объект сюда»
            pasteFiles(move: true)
            return true
        }
        return false
    }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 {
            selection = []
            needsDisplay = true
        } else {
            super.keyDown(with: e)
        }
    }

    // MARK: Копировать, вырезать, вставить

    private func copySelection(cut: Bool) {
        let urls = selected()
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
        if cut {
            FinderCut.shared.markCut()
            FinderCut.shared.showToast()
        } else {
            FinderCut.shared.cancelCut()
        }
    }

    /// Вставляет файлы из буфера обмена в папку стола: вырезанные переносятся, скопированные копируются
    private func pasteFiles(move: Bool) {
        guard let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                          options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return }
        transfer(urls, move: move)
        if move { FinderCut.shared.cancelCut() }
    }

    private func selected() -> [URL] { items.filter { selection.contains($0) } }

    // MARK: Меню

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let m = NSMenu()
        if let i = index(at: p) {
            if !selection.contains(items[i]) { selection = [items[i]]; needsDisplay = true }
            add(m, T("Открыть"), #selector(openSel))
            add(m, T("Показать в Finder"), #selector(revealSel))
            m.addItem(.separator())
            add(m, T("Скопировать"), #selector(copySel))
            if FinderCut.enabled { add(m, T("Вырезать"), #selector(cutSel)) }
            add(m, T("Вставить"), #selector(pasteSel))
            m.addItem(.separator())
            add(m, T("Перенести на основной рабочий стол"), #selector(toMainSel))
            add(m, T("Переместить в Корзину"), #selector(trashSel))
        } else {
            add(m, T("Вставить"), #selector(pasteSel))
            add(m, T("Новая папка"), #selector(newFolder))
            add(m, T("Показать папку стола в Finder"), #selector(revealFolder))
            m.addItem(.separator())
            add(m, T("Обновить фон"), #selector(refreshWallpaper))
            add(m, T("Сменить фон рабочего стола…"), #selector(openWallpaperSettings))
        }
        return m
    }

    private func add(_ m: NSMenu, _ title: String, _ sel: Selector) {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        m.addItem(it)
    }

    @objc private func copySel() { copySelection(cut: false) }
    @objc private func cutSel() { copySelection(cut: true) }
    @objc private func pasteSel() { pasteFiles(move: FinderCut.shared.cutPending) }
    @objc private func openSel() { selected().forEach { NSWorkspace.shared.open($0) } }
    @objc private func revealSel() { NSWorkspace.shared.activateFileViewerSelecting(selected()) }
    @objc private func toMainSel() { let s = selected(); if !s.isEmpty { onMoveToMain?(s) } }
    @objc private func trashSel() { trash(selected()) }
    @objc private func revealFolder() { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
    @objc private func refreshWallpaper() { onRefreshWallpaper?() }
    @objc private func openWallpaperSettings() {
        for s in ["x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
                  "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"] {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { break }
        }
    }

    @objc private func newFolder() {
        var u = folder.appendingPathComponent(T("Новая папка"))
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = folder.appendingPathComponent(T("Новая папка") + " \(n)")
            n += 1
        }
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
        selection = [u]
        reload()
    }

    private func trash(_ urls: [URL]) {
        for u in urls { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
        reload()
    }

    // MARK: Перетаскивание файлов на стол

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { operation(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { operation(sender) }

    private func operation(_ s: NSDraggingInfo) -> NSDragOperation {
        s.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        transfer(urls, move: sender.draggingSourceOperationMask.contains(.move),
                 at: convert(sender.draggingLocation, from: nil))
        return true
    }

    /// Кладёт файлы в папку стола (переносит или копирует), имена при совпадении получают номер
    private func transfer(_ urls: [URL], move: Bool, at point: NSPoint? = nil) {
        let myPath = folder.standardizedFileURL.path
        var failed: [String] = []
        for u in urls {
            if u.deletingLastPathComponent().standardizedFileURL.path == myPath { continue }   // уже здесь
            var dst = folder.appendingPathComponent(u.lastPathComponent)
            var n = 2
            let base = (u.lastPathComponent as NSString).deletingPathExtension
            let ext = u.pathExtension
            while FileManager.default.fileExists(atPath: dst.path) {
                dst = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                n += 1
            }
            do {
                if move {
                    try FileManager.default.moveItem(at: u, to: dst)
                } else {
                    try FileManager.default.copyItem(at: u, to: dst)
                }
                // новый файл — в ячейку, куда отпустили (при вставке — первая свободная)
                if let p = point {
                    slots[dst.lastPathComponent] = freeSlot(near: slot(at: p), ignoring: [])
                }
            } catch {
                failed.append(u.lastPathComponent + " — " + (error as NSError).localizedDescription)
            }
        }
        reload()
        if !failed.isEmpty {
            let a = NSAlert()
            a.messageText = T("Не удалось перенести на этот рабочий стол")
            a.informativeText = failed.prefix(6).joined(separator: "\n")
            a.runModal()
        }
    }
}

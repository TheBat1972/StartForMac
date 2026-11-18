// «Пуск» — меню приложений в стиле кнопки ПУСК из Windows.
// Открывается кликом по иконке в Dock. Категории — автоматические (из Info.plist приложений)
// и свои; раскладку можно менять перетаскиванием или через контекстное меню.
import SwiftUI
import AppKit
import CoreServices
import IOKit.pwr_mgt
import Carbon
import ApplicationServices
import Security
import UniformTypeIdentifiers

let allCategory = "Все приложения"
/// Вкладка быстрого доступа к сайтам (служебное имя, как у категорий)
let webCategory = "Сайты"

// Допустимые размеры окна — чтобы вёрстка не ломалась
let minWindowSize = NSSize(width: 640, height: 440)
let maxWindowSize = NSSize(width: 1100, height: 800)
let defaultWindowSize = NSSize(width: 800, height: 679)   // +114: ещё один ряд значков (значок 52 + название 32 + отступы)

let builtInNames = ["Работа", "Разработка", "Графика и фото", "Медиа", "Игры", "Общение",
                    "Утилиты", "Образование", "Финансы", "Образ жизни", "Прочее"]

func symbol(for category: String) -> String {
    switch category {
    case allCategory: return "square.grid.2x2.fill"
    case webCategory: return "globe"
    case "Работа": return "briefcase"
    case "Разработка": return "hammer"
    case "Графика и фото": return "paintbrush"
    case "Медиа": return "play.rectangle"
    case "Игры": return "gamecontroller"
    case "Общение": return "bubble.left.and.bubble.right"
    case "Утилиты": return "wrench.and.screwdriver"
    case "Образование": return "book"
    case "Финансы": return "creditcard"
    case "Образ жизни": return "leaf"
    case "Прочее": return "square.grid.2x2"
    default: return "folder"
    }
}

// MARK: - Модель

struct AppItem: Identifiable, Hashable {
    let id: String          // bundle id (или путь, если его нет)
    let name: String
    let path: String
    let autoCategory: String
    var aliases: [String] = []     // другие названия (русское, английское, из локализаций) — для поиска
}

struct WebLink: Codable, Identifiable {
    var id = UUID()
    var title: String
    var url: String
    var folder: UUID? = nil
}

struct WebFolder: Codable, Identifiable {
    var id = UUID()
    var title: String
}

/// Черновик папки (id == nil — новая)
struct FolderDraft: Identifiable {
    let key = UUID()
    var id: UUID?
    var title: String
}

/// Черновик ссылки в окне добавления/правки (id == nil — новая)
struct LinkDraft: Identifiable {
    let key = UUID()
    var id: UUID?
    var title: String
    var url: String
    var folder: UUID? = nil
}

struct Config: Codable {
    var customCategories: [String] = []
    var assignments: [String: String] = [:]
    var links: [WebLink]? = nil
    var folders: [WebFolder]? = nil
}

extension Notification.Name {
    static let languageChanged = Notification.Name("ru.local.StartMenu.languageChanged")
}

final class Store: ObservableObject, @unchecked Sendable {
    @Published var apps: [AppItem] = []
    @Published var customCategories: [String] = []
    @Published var assignments: [String: String] = [:]
    @Published var selected = allCategory
    @Published var showTick = 0
    @Published var uninstall: UninstallModel? = nil
    @Published var clean: CleanModel? = nil
    @Published var maint: MaintModel? = nil
    @Published var big: BigFilesModel? = nil
    @Published var pwRequest: PasswordRequest? = nil
    @Published var pwTool: ToolKind? = nil
    @Published var language: AppLanguage = Loc.setting
    @Published var theme: AppTheme = AppTheme.setting
    @Published var links: [WebLink] = []
    @Published var linkDraft: LinkDraft? = nil
    @Published var folders: [WebFolder] = []
    @Published var openFolder: UUID? = nil
    @Published var folderDraft: FolderDraft? = nil
    @Published var showSettings = false

    // «Не давать уснуть»: пока включено, Мак и экран не засыпают от бездействия (как Amphetamine).
    // Закрытие крышки всё равно усыпляет Мак. При выходе из приложения система снимает блокировку сама.
    @Published var keepAwake = false
    private var awakeAssertion: IOPMAssertionID = 0
    func setKeepAwake(_ on: Bool) {
        if on {
            guard awakeAssertion == 0 else { keepAwake = true; return }
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Пуск: не давать компьютеру уснуть" as CFString, &id)
            if r == kIOReturnSuccess { awakeAssertion = id; keepAwake = true }
        } else {
            if awakeAssertion != 0 { IOPMAssertionRelease(awakeAssertion); awakeAssertion = 0 }
            keepAwake = false
        }
        minimize?.setAwake(keepAwake)
    }
    @Published var quitAll: QuitAllModel? = nil
    @Published var fmt: FormatModel? = nil
    var minimize: MinimizeController?
    @Published var iconTick = 0
    private var iconMemory: [UUID: NSImage] = [:]
    private var iconAttempted = Set<UUID>()
    static weak var current: Store?
    @Published var showPermissions = false
    @Published var fullDiskAccess = true
    @Published var accessibility = true
    static var suppressAutoHide = false

    private var iconCache: [String: NSImage] = [:]
    private let configURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StartMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            customCategories = cfg.customCategories
            assignments = cfg.assignments
            links = cfg.links ?? []
            folders = cfg.folders ?? []
        }
        Store.current = self
        rescan()
        refreshPermissions()
        // при первом запуске сами спрашиваем про разрешения
        if (!fullDiskAccess || !accessibility) && !UserDefaults.standard.bool(forKey: "askedPermissions") {
            UserDefaults.standard.set(true, forKey: "askedPermissions")
            showPermissions = true
        }
    }

    func refreshPermissions() {
        fullDiskAccess = Permissions.hasFullDiskAccess()
        accessibility = Permissions.hasAccessibility()
    }

    var permissionsOK: Bool { fullDiskAccess && accessibility }

    private func save() {
        let cfg = Config(customCategories: customCategories, assignments: assignments, links: links, folders: folders)
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    // Категории

    func category(of app: AppItem) -> String { assignments[app.id] ?? app.autoCategory }

    // Быстрый доступ к сайтам

    /// Адрес для открытия: если схема не указана, для IP-адреса и localhost берём http://, для сайтов https://.
    /// Сохраняем адрес в том виде, как его ввёл пользователь.
    static func normalizedURL(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.contains("://") {
            guard let u = URL(string: t), let h = u.host, !h.isEmpty,
                  u.scheme == "http" || u.scheme == "https" else { return nil }
            return u
        }
        guard let probe = URL(string: "http://" + t), let h = probe.host, !h.isEmpty else { return nil }
        let isIPv4 = h.split(separator: ".", omittingEmptySubsequences: false).count == 4
            && h.split(separator: ".").allSatisfy { Int($0) != nil }
        let isIPv6 = h.contains(":")
        if isIPv4 || isIPv6 || h == "localhost" { return probe }
        guard h.contains(".") else { return nil }
        return URL(string: "https://" + t)
    }

    // Значки сайтов: берём у самого сайта (apple-touch-icon / favicon) и кладём в ~/Library/Application Support/StartMenu/icons

    private var iconDir: URL {
        let dir = configURL.deletingLastPathComponent().appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func linkIcon(_ l: WebLink) -> NSImage? {
        if let i = iconMemory[l.id] { return i }
        if let i = NSImage(contentsOf: linkCustomURL(l.id)) {
            iconMemory[l.id] = i
            return i
        }
        if let i = NSImage(contentsOf: iconDir.appendingPathComponent("\(l.id.uuidString).png")) {
            iconMemory[l.id] = i
            return i
        }
        return nil
    }

    /// Докачивает значки тем сайтам, у которых их ещё нет (по одной попытке за запуск)
    func ensureIcons() {
        for l in links where linkIcon(l) == nil && !iconAttempted.contains(l.id) {
            iconAttempted.insert(l.id)
            fetchIcon(l)
        }
    }

    // Свои иконки сайтов (только в «Пуске»): лежат отдельно от значков, взятых у самих сайтов

    private var linkCustomDir: URL { configURL.deletingLastPathComponent().appendingPathComponent("LinkIcons", isDirectory: true) }

    private func linkCustomURL(_ id: UUID) -> URL { linkCustomDir.appendingPathComponent(id.uuidString + ".png") }

    func hasCustomLinkIcon(_ l: WebLink) -> Bool {
        FileManager.default.fileExists(atPath: linkCustomURL(l.id).path)
    }

    func chooseIcon(for link: WebLink) {
        IconPickerController.shared.show(
            name: link.title,
            icon: { [weak self] in self?.linkIcon(link) ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage() },
            hasCustom: { [weak self] in self?.hasCustomLinkIcon(link) ?? false },
            apply: { [weak self] img in self?.setCustomIcon(for: link, image: img) },
            reset: { [weak self] in self?.resetIcon(link) },
            store: self)
    }

    func setCustomIcon(for link: WebLink, image src: NSImage) {
        guard let png = Store.squarePNG(src) else { return }
        try? FileManager.default.createDirectory(at: linkCustomDir, withIntermediateDirectories: true)
        try? png.write(to: linkCustomURL(link.id), options: .atomic)
        iconMemory[link.id] = nil
        iconTick += 1
    }

    /// Возвращает значок, взятый у самого сайта (если его не было — докачивает)
    func resetIcon(_ link: WebLink) {
        try? FileManager.default.removeItem(at: linkCustomURL(link.id))
        iconMemory[link.id] = nil
        iconAttempted.remove(link.id)
        iconTick += 1
        ensureIcons()
    }

    private func forgetIcon(_ id: UUID) {
        iconMemory[id] = nil
        iconAttempted.remove(id)
        try? FileManager.default.removeItem(at: iconDir.appendingPathComponent("\(id.uuidString).png"))
    }

    private func fetchIcon(_ l: WebLink) {
        guard let base = Store.normalizedURL(l.url) else { return }
        let id = l.id
        let file = iconDir.appendingPathComponent("\(id.uuidString).png")
        Task.detached(priority: .utility) { [weak self] in
            guard let png = await Store.downloadIconPNG(for: base) else { return }
            try? png.write(to: file, options: .atomic)
            DispatchQueue.main.async {
                self?.iconMemory[id] = nil
                self?.iconTick += 1
            }
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 6)
        r.setValue("Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                   forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Ищет значок сайта: сперва в разметке страницы, потом /favicon.ico
    private static func downloadIconPNG(for base: URL) async -> Data? {
        var candidates: [(Int, URL)] = []
        if let (data, _) = try? await URLSession.shared.data(for: request(base)) {
            let html = String(decoding: data.prefix(600_000), as: UTF8.self)
            let tagRx = try? NSRegularExpression(pattern: "<link[^>]+>", options: [.caseInsensitive])
            let relRx = try? NSRegularExpression(pattern: "rel\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive])
            let hrefRx = try? NSRegularExpression(pattern: "href\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive])
            func first(_ rx: NSRegularExpression?, _ str: String) -> String? {
                let ns = str as NSString
                guard let m = rx?.firstMatch(in: str, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
                return ns.substring(with: m.range(at: 1))
            }
            let ns = html as NSString
            for m in tagRx?.matches(in: html, range: NSRange(location: 0, length: ns.length)) ?? [] {
                let tag = ns.substring(with: m.range)
                guard let rel = first(relRx, tag)?.lowercased(), rel.contains("icon"),
                      let href = first(hrefRx, tag),
                      let u = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL else { continue }
                candidates.append((rel.contains("apple-touch") ? 0 : 1, u))
            }
        }
        candidates.sort { $0.0 < $1.0 }
        var urls = candidates.map { $0.1 }
        if var c = URLComponents(url: base, resolvingAgainstBaseURL: true) {
            c.path = "/favicon.ico"; c.query = nil; c.fragment = nil
            if let u = c.url { urls.append(u) }
        }
        for u in urls {
            guard let (data, resp) = try? await URLSession.shared.data(for: request(u)),
                  (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let img = NSImage(data: data), img.size.width >= 16,
                  let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            return png
        }
        return nil
    }

    func saveLink(_ d: LinkDraft) {
        guard let u = Store.normalizedURL(d.url) else { return }
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = d.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = d.id.flatMap { id in links.first(where: { $0.id == id }) }
        let link = WebLink(id: d.id ?? UUID(), title: title.isEmpty ? (u.host ?? typed) : title, url: typed,
                           folder: existing?.folder ?? d.folder)
        if let id = d.id, let i = links.firstIndex(where: { $0.id == id }) {
            if links[i].url != link.url { forgetIcon(id) }
            links[i] = link
        } else { links.append(link) }
        save()
        ensureIcons()
    }

    func saveFolder(_ d: FolderDraft) {
        let t = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let id = d.id, let i = folders.firstIndex(where: { $0.id == id }) { folders[i].title = t }
        else { folders.append(WebFolder(title: t)) }
        save()
    }

    /// Удаляет папку; сайты из неё не пропадают, а выходят в корень вкладки
    func deleteFolder(_ f: WebFolder) {
        for i in links.indices where links[i].folder == f.id { links[i].folder = nil }
        folders.removeAll { $0.id == f.id }
        if openFolder == f.id { openFolder = nil }
        save()
    }

    func moveLink(_ id: UUID, to folder: UUID?) {
        guard let i = links.firstIndex(where: { $0.id == id }), links[i].folder != folder else { return }
        links[i].folder = folder
        save()
    }

    func deleteLink(_ l: WebLink) {
        links.removeAll { $0.id == l.id }
        forgetIcon(l.id)
        try? FileManager.default.removeItem(at: linkCustomURL(l.id))
        save()
    }

    func setLanguage(_ l: AppLanguage) {
        Loc.setting = l
        language = l
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    func setTheme(_ t: AppTheme) {
        AppTheme.setting = t
        theme = t
        AppTheme.apply()
    }

    var categoryList: [String] {
        let used = Set(apps.map { category(of: $0) })
        var builtIn = used.subtracting(customCategories).sorted()
        if let i = builtIn.firstIndex(of: "Прочее") { builtIn.remove(at: i); builtIn.append("Прочее") }
        return builtIn + customCategories
    }

    var assignableCategories: [String] {
        builtInNames + customCategories
    }

    var currentSelection: String {
        (selected == allCategory || selected == webCategory || categoryList.contains(selected)) ? selected : allCategory
    }

    func count(in category: String) -> Int {
        category == webCategory ? links.count : category == allCategory ? apps.count : apps.filter { self.category(of: $0) == category }.count
    }

    func isValidNewName(_ name: String) -> Bool {
        !name.isEmpty && name != allCategory && name != webCategory && !builtInNames.contains(name) && !customCategories.contains(name)
    }

    func addCategory(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidNewName(name) else { return }
        customCategories.append(name)
        selected = name
        save()
    }

    func renameCategory(_ old: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != old, isValidNewName(name), let i = customCategories.firstIndex(of: old) else { return }
        customCategories[i] = name
        for (k, v) in assignments where v == old { assignments[k] = name }
        if selected == old { selected = name }
        save()
    }

    func deleteCategory(_ name: String) {
        customCategories.removeAll { $0 == name }
        assignments = assignments.filter { $0.value != name }
        if selected == name { selected = allCategory }
        save()
    }

    func assign(id: String, to category: String) {
        guard let app = apps.first(where: { $0.id == id }) else { return }
        assign(app, to: category)
    }

    func assign(_ app: AppItem, to category: String) {
        if category == app.autoCategory { assignments.removeValue(forKey: app.id) }
        else { assignments[app.id] = category }
        save()
    }

    func resetAssignment(_ app: AppItem) {
        assignments.removeValue(forKey: app.id)
        save()
    }

    // Удаление

    func beginUninstall(_ app: AppItem) {
        let m = UninstallModel(app: app)
        m.wasRunning = Uninstaller.isRunning(app)
        uninstall = m
        let ids = Set(apps.map { $0.id })
        DispatchQueue.global(qos: .userInitiated).async {
            var items = Uninstaller.find(for: app, installedIDs: ids)
            for i in items.indices { items[i].size = Uninstaller.size(of: items[i].url) }
            DispatchQueue.main.async {
                m.items = items
                m.stage = .review
            }
        }
    }

    func performUninstall(_ m: UninstallModel) {
        m.stage = .working
        m.workText = T("Перемещаю в Корзину…")
        Store.suppressAutoHide = true
        let selected = m.selectedItems
        let direct = selected.filter { !$0.needsAdmin }
        let app = m.app
        DispatchQueue.global(qos: .userInitiated).async {
            // закрываем приложение, если оно запущено
            if let bid = Uninstaller.bundleID(of: app) {
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                running.forEach { $0.terminate() }
                var waited = 0
                while running.contains(where: { !$0.isTerminated }) && waited < 30 {
                    usleep(100_000); waited += 1
                }
                running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
                if !running.isEmpty { usleep(300_000) }
            }
            DispatchQueue.main.async {
                if direct.isEmpty {
                    self.afterRecycle(m, selected: selected, trashedPaths: [])
                } else {
                    NSWorkspace.shared.recycle(direct.map { $0.url }) { trashed, _ in
                        DispatchQueue.main.async {
                            self.afterRecycle(m, selected: selected, trashedPaths: Set(trashed.keys.map { $0.path }))
                        }
                    }
                }
            }
        }
    }

    private func afterRecycle(_ m: UninstallModel, selected: [Leftover], trashedPaths: Set<String>) {
        m.trashedCount = selected.filter { trashedPaths.contains($0.url.path) }.count
        let remaining = selected.filter { !trashedPaths.contains($0.url.path) }.map { $0.url.path }
        if remaining.isEmpty { finishUninstall(m, failed: []) }
        else { removeWithAdmin(m, paths: remaining) }
    }

    /// То, что не удалось переместить в Корзину, удаляем с правами администратора (запрашивается пароль)
    func removeWithAdmin(_ m: UninstallModel, paths: [String]) {
        m.stage = .working
        m.workText = T("Введите пароль администратора в окне системы…")
        Store.suppressAutoHide = true
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Uninstaller.removeAsAdmin(paths)
            DispatchQueue.main.async {
                let fm = FileManager.default
                let left = paths.filter { fm.fileExists(atPath: $0) }
                m.adminRemoved += paths.count - left.count
                self.finishUninstall(m, failed: left)
            }
        }
    }

    private func finishUninstall(_ m: UninstallModel, failed: [String]) {
        m.failed = failed
        if !FileManager.default.fileExists(atPath: m.app.path) {
            assignments.removeValue(forKey: m.app.id)
            save()
        }
        m.stage = .done
        Store.suppressAutoHide = false
        rescan()
    }

    // Очистка мусора

    func beginClean() {
        if let c = clean, c.stage == .working { ToolWindows.shared.show(.clean, store: self); return }
        let m = CleanModel()
        clean = m
        ToolWindows.shared.show(.clean, store: self)
        let ids = Set(apps.map { $0.id }.filter { !$0.hasPrefix("/") })
        DispatchQueue.global(qos: .userInitiated).async {
            let cats = Junk.scan(installedIDs: ids) { text in
                DispatchQueue.main.async { m.scanText = text }
            }
            DispatchQueue.main.async {
                m.categories = cats
                m.stage = .review
            }
        }
    }

    func performClean(_ m: CleanModel) {
        m.stage = .working
        m.workText = T("Удаляю…")
        let items = m.selectedItems
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var freed: Int64 = 0
            var removed = 0
            var failed: [JunkItem] = []
            for it in items {
                if it.needsAdmin { failed.append(it); continue }
                do { try fm.removeItem(at: it.url); freed += it.size; removed += 1 }
                catch { failed.append(it) }
            }
            // системные файлы удаляем с паролем администратора
            let admin = failed.filter { $0.needsAdmin }
            if !admin.isEmpty {
                DispatchQueue.main.async { m.workText = T("Введите пароль администратора в окне системы…") }
                _ = Uninstaller.removeAsAdmin(admin.map { $0.url.path })
                for it in admin where !fm.fileExists(atPath: it.url.path) {
                    freed += it.size; removed += 1
                }
            }
            let left = failed.filter { fm.fileExists(atPath: $0.url.path) }.map { $0.url.path }
            DispatchQueue.main.async {
                m.freed = freed
                m.removedCount = removed
                m.failed = left
                m.stage = .done
            }
        }
    }

    // Обслуживание

    func beginMaint() {
        if maint?.running != true { maint = MaintModel() }
        ToolWindows.shared.show(.maint, store: self)
    }
    func beginQuitAll() { quitAll = QuitAllModel() }
    func beginFormat() {
        if fmt == nil || (fmt?.stage != .working && fmt?.speed.running != true) { fmt = FormatModel() }
        ToolWindows.shared.show(.fmt, store: self)
    }
    func beginDisk() { DiskWindowController.shared.show(store: self) }

    func runMaint(_ m: MaintModel) {
        let ids = m.tasks.filter { $0.selected }.map { $0.id }
        guard !ids.isEmpty, !m.running else { return }
        m.running = true
        m.note = T("Выполняю…")
        for id in ids { m.set(id, .running) }
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. то, что не требует пароля
            for id in ids {
                if let result = Maintenance.runUser(id) {
                    DispatchQueue.main.async { m.set(id, result) }
                }
            }
            // 2. всё, что требует администратора, — одним запуском и одним вводом пароля
            let adminIDs = ids.filter { Maintenance.adminCommand($0) != nil }
            if !adminIDs.isEmpty {
                DispatchQueue.main.async { m.note = T("Введите пароль администратора в окне системы…") }
                let script = adminIDs.map { "\(Maintenance.adminCommand($0)!); echo \"@@\($0):$?\"" }
                    .joined(separator: "\n")
                let res = Admin.run(tool: "/bin/sh", args: ["-c", script])
                var codes: [String: String] = [:]
                for line in res.output.split(separator: "\n") where line.hasPrefix("@@") {
                    let parts = line.dropFirst(2).split(separator: ":")
                    if parts.count == 2 { codes[String(parts[0])] = String(parts[1]) }
                }
                DispatchQueue.main.async {
                    for id in adminIDs {
                        if !res.ok { m.set(id, .failed(Tf("Нет прав администратора: %@", "\(res.detail)"))) }
                        else if codes[id] == "0" { m.set(id, .ok(T("Готово"))) }
                        else { m.set(id, .failed(Tf("Не удалось (код %@)", "\(codes[id] ?? "?")"))) }
                    }
                }
            }
            DispatchQueue.main.async {
                m.running = false
                m.note = ""
            }
        }
    }

    // Большие и старые файлы

    func beginBig() {
        if let b = big, b.stage == .working { ToolWindows.shared.show(.big, store: self); return }
        let m = BigFilesModel()
        big = m
        ToolWindows.shared.show(.big, store: self)
        DispatchQueue.global(qos: .userInitiated).async {
            let files = BigFiles.scan { text in
                DispatchQueue.main.async { m.scanText = text }
            }
            DispatchQueue.main.async {
                m.items = files
                m.stage = .review
            }
        }
    }

    func performBig(_ m: BigFilesModel) {
        m.stage = .working
        let selected = m.selectedVisible
        NSWorkspace.shared.recycle(selected.map { $0.url }) { trashed, _ in
            DispatchQueue.main.async {
                let ok = Set(trashed.keys.map { $0.path })
                let done = selected.filter { ok.contains($0.url.path) }
                m.trashedCount = done.count
                m.trashedSize = done.reduce(0) { $0 + $1.size }
                m.failed = selected.filter { !ok.contains($0.url.path) }.map { $0.url.path }
                m.items.removeAll { f in ok.contains(f.url.path) }
                m.stage = .done
            }
        }
    }

    // Иконки

    func icon(for app: AppItem) -> NSImage {
        if let i = iconCache[app.id] { return i }
        let custom = customIconURL(app.id)
        let i = FileManager.default.fileExists(atPath: custom.path) ? (NSImage(contentsOf: custom) ?? NSWorkspace.shared.icon(forFile: app.path))
                                                                   : NSWorkspace.shared.icon(forFile: app.path)
        iconCache[app.id] = i
        return i
    }

    // Свои иконки приложений (только в «Пуске»; сами программы не меняются)

    private var iconsDir: URL { configURL.deletingLastPathComponent().appendingPathComponent("Icons", isDirectory: true) }

    private func customIconURL(_ id: String) -> URL {
        iconsDir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    func hasCustomIcon(_ app: AppItem) -> Bool {
        FileManager.default.fileExists(atPath: customIconURL(app.id).path)
    }

    /// Открывает окно выбора иконки: готовые иконки или картинка с диска
    func chooseIcon(for app: AppItem) {
        IconPickerController.shared.show(
            name: app.name,
            icon: { [weak self] in self?.icon(for: app) ?? NSImage() },
            hasCustom: { [weak self] in self?.hasCustomIcon(app) ?? false },
            apply: { [weak self] img in self?.setCustomIcon(for: app, image: img) },
            reset: { [weak self] in self?.resetIcon(app) },
            store: self)
    }

    func setCustomIcon(for app: AppItem, from url: URL) {
        guard let src = NSImage(contentsOf: url) else { return }
        setCustomIcon(for: app, image: src)
    }

    /// Приводит картинку к квадрату 512×512 (пропорции сохраняются) и возвращает PNG
    static func squarePNG(_ src: NSImage) -> Data? {
        guard src.size.width > 0, src.size.height > 0 else { return nil }
        let side: CGFloat = 512
        let img = NSImage(size: NSSize(width: side, height: side))
        img.lockFocus()
        let k = min(side / src.size.width, side / src.size.height)
        let w = src.size.width * k, h = src.size.height * k
        src.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h),
                 from: .zero, operation: .sourceOver, fraction: 1)
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    func setCustomIcon(for app: AppItem, image src: NSImage) {
        guard let png = Store.squarePNG(src) else { return }
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        try? png.write(to: customIconURL(app.id), options: .atomic)
        iconCache[app.id] = nil
        iconTick += 1
    }

    func resetIcon(_ app: AppItem) {
        try? FileManager.default.removeItem(at: customIconURL(app.id))
        iconCache[app.id] = nil
        iconTick += 1
    }

    // Сканирование

    func rescan() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Store.scan()
            DispatchQueue.main.async { self.apps = found }
        }
    }

    static func mapCategory(_ type: String) -> String {
        let s = type.replacingOccurrences(of: "public.app-category.", with: "")
        if s.hasSuffix("games") { return "Игры" }
        switch s {
        case "productivity", "business": return "Работа"
        case "developer-tools": return "Разработка"
        case "graphics-design", "photography": return "Графика и фото"
        case "music", "video", "entertainment": return "Медиа"
        case "social-networking": return "Общение"
        case "utilities": return "Утилиты"
        case "education", "reference", "news", "books": return "Образование"
        case "finance": return "Финансы"
        case "lifestyle", "healthcare-fitness", "medical", "food-drink", "travel", "weather", "sports", "navigation":
            return "Образ жизни"
        default: return "Прочее"
        }
    }

    static func scan() -> [AppItem] {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        let myID = Bundle.main.bundleIdentifier
        var result: [String: AppItem] = [:]

        func add(_ url: URL) {
            let info = Bundle(url: url)?.infoDictionary
            let bid = info?["CFBundleIdentifier"] as? String
            if bid != nil && bid == myID { return }
            let id = bid ?? url.path
            if result[id] != nil { return }
            var name = fm.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            if url.lastPathComponent == "AddPrinter.app" { name = "Центр печати" }   // в системе он называется AddPrinter
            var cat: String
            if let t = info?["LSApplicationCategoryType"] as? String { cat = mapCategory(t) }
            else { cat = "Прочее" }
            if cat == "Прочее" && url.path.contains("/Utilities/") { cat = "Утилиты" }
            // у системных программ несколько названий: файл называется по-английски, а показывается русское
            var aliases = Set<String>()
            func addAlias(_ s: String?) {
                guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return }
                if t.hasSuffix(".app") { t = String(t.dropLast(4)) }
                if t != name { aliases.insert(t) }
            }
            addAlias((try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName)
            addAlias(url.deletingPathExtension().lastPathComponent)
            addAlias(info?["CFBundleDisplayName"] as? String)
            addAlias(info?["CFBundleName"] as? String)
            if let res = Bundle(url: url)?.resourceURL {
                for lp in ["ru.lproj", "Russian.lproj", "en.lproj", "English.lproj"] {
                    let f = res.appendingPathComponent(lp).appendingPathComponent("InfoPlist.strings").path
                    if let d = NSDictionary(contentsOfFile: f) as? [String: Any] {
                        addAlias(d["CFBundleDisplayName"] as? String)
                        addAlias(d["CFBundleName"] as? String)
                    }
                }
            }
            if url.lastPathComponent == "Passwords.app" { aliases.formUnion(["Пароли", "Пароль", "Password", "Связка ключей"]) }
            // «Связка ключей» — это и есть менеджер паролей старого образца, ищут её по слову «пароли»
            if url.lastPathComponent == "Keychain Access.app" { aliases.formUnion(["Пароли", "Пароль", "Password", "Passwords", "Keychain"]) }
            if url.lastPathComponent == "AddPrinter.app" { aliases.formUnion(["AddPrinter", "Print Center", "Принтеры", "Printers"]) }
            result[id] = AppItem(id: id, name: name, path: url.path, autoCategory: cat, aliases: Array(aliases))
        }

        func walk(_ dir: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { return }
            for u in items {
                if u.pathExtension == "app" { add(u) }
                else if depth < 2, (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    walk(u, depth: depth + 1)
                }
            }
        }

        for r in roots { walk(URL(fileURLWithPath: r), depth: 0) }
        // служебные программы лежат в CoreServices (Launchpad их показывает): целиком папка Applications и
        // выбранные программы из самой CoreServices — остальное там фоновые агенты и установщики
        let coreWanted: Set<String> = ["Finder.app", "AddPrinter.app", "Apple Diagnostics.app", "Batteries.app",
                                       "Certificate Assistant.app", "Erase Assistant.app", "Screen Time.app"]
        for r in ["/System/Library/CoreServices/Applications", "/System/Library/CoreServices"] {
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: r), includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { continue }
            for u in items where u.pathExtension == "app" {
                if r.hasSuffix("CoreServices") {
                    if coreWanted.contains(u.lastPathComponent) { add(u) }
                    continue
                }
                let i = Bundle(url: u)?.infoDictionary
                if let v = i?["LSUIElement"], "\(v)" == "1" || "\(v)" == "true" { continue }
                if let v = i?["LSBackgroundOnly"], "\(v)" == "1" || "\(v)" == "true" { continue }
                add(u)
            }
        }
        return result.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Удаление приложений

struct Leftover: Identifiable {
    let id = UUID()
    let url: URL
    let kind: String
    var size: Int64 = 0
    var selected: Bool = true
    var needsAdmin: Bool = false
}

final class UninstallModel: ObservableObject {
    enum Stage { case scanning, review, confirm, working, done }
    let app: AppItem
    @Published var stage: Stage = .scanning
    @Published var items: [Leftover] = []
    @Published var wasRunning = false
    @Published var trashedCount = 0
    @Published var adminRemoved = 0
    @Published var workText = T("Перемещаю в Корзину…")
    @Published var failed: [String] = []
    init(app: AppItem) { self.app = app }
    var selectedItems: [Leftover] { items.filter { $0.selected } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
}

enum Uninstaller {
    static func bundleID(of app: AppItem) -> String? { Bundle(path: app.path)?.bundleIdentifier }

    static func isRunning(_ app: AppItem) -> Bool {
        guard let bid = bundleID(of: app) else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
    }

    /// Имена, которые никогда не считаем «остатками» по совпадению названия — это данные самой системы
    private static let protectedNames: Set<String> = [
        "mail", "safari", "messages", "calendars", "calendar", "addressbook", "contacts", "photos", "notes",
        "icloud", "clouddocs", "knowledge", "music", "tv", "podcasts", "books", "keychains", "preferences",
        "caches", "logs", "containers", "fonts", "colorsync", "dock", "finder", "mobile documents"
    ]

    static func find(for app: AppItem, installedIDs: Set<String>) -> [Leftover] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let info = Bundle(path: app.path)?.infoDictionary
        let bid = info?["CFBundleIdentifier"] as? String
        let exe = info?["CFBundleExecutable"] as? String
        let fileName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
        let appIsApple = bid?.hasPrefix("com.apple.") ?? false

        let names: Set<String> = Set([app.name, fileName, exe ?? ""]
            .filter { $0.count >= 3 }
            .map { $0.lowercased() }
            .filter { !protectedNames.contains($0) })

        func stem(_ n: String) -> String {
            for suf in [".plist", ".savedState", ".binarycookies", ".binarycookies-journal"] where n.hasSuffix(suf) {
                return String(n.dropLast(suf.count))
            }
            return n
        }
        func idMatch(_ n: String) -> Bool {
            guard let bid = bid else { return false }
            if n.hasPrefix("com.apple.") && !appIsApple { return false }
            let st = stem(n)
            guard st == bid || st.hasPrefix(bid + ".") else { return false }
            // запись принадлежит другому установленному приложению (например, Chrome и Chrome.canary)
            for other in installedIDs where other != app.id && other.count > bid.count && other.hasPrefix(bid + ".") {
                if st == other || st.hasPrefix(other + ".") { return false }
            }
            return true
        }
        func nameMatch(_ n: String) -> Bool { names.contains(n.lowercased()) }
        func reportMatch(_ n: String) -> Bool {
            let l = n.lowercased()
            return names.contains { l.hasPrefix($0 + "_") || l.hasPrefix($0 + "-") }
        }

        struct Spec { let dir: String; let kind: String; let match: (String) -> Bool }
        let U = home + "/Library"
        let S = "/Library"
        let anyMatch: (String) -> Bool = { idMatch($0) || nameMatch($0) }
        let groupMatch: (String) -> Bool = { n in
            guard let bid = bid else { return false }
            return n.contains(bid) && !n.hasPrefix("com.apple.") || (appIsApple && n.contains(bid))
        }
        let specs: [Spec] = [
            Spec(dir: U + "/Application Support", kind: "Данные приложения", match: anyMatch),
            Spec(dir: U + "/Caches", kind: "Кэш", match: anyMatch),
            Spec(dir: U + "/Preferences", kind: "Настройки", match: idMatch),
            Spec(dir: U + "/Preferences/ByHost", kind: "Настройки", match: idMatch),
            Spec(dir: U + "/Containers", kind: "Контейнер", match: idMatch),
            Spec(dir: U + "/Group Containers", kind: "Общие данные", match: groupMatch),
            Spec(dir: U + "/Saved Application State", kind: "Состояние окон", match: idMatch),
            Spec(dir: U + "/Logs", kind: "Логи", match: anyMatch),
            Spec(dir: U + "/Logs/DiagnosticReports", kind: "Отчёты о сбоях", match: reportMatch),
            Spec(dir: U + "/Application Support/CrashReporter", kind: "Отчёты о сбоях", match: reportMatch),
            Spec(dir: U + "/WebKit", kind: "Данные WebKit", match: idMatch),
            Spec(dir: U + "/HTTPStorages", kind: "Сетевое хранилище", match: idMatch),
            Spec(dir: U + "/Cookies", kind: "Cookies", match: idMatch),
            Spec(dir: U + "/Application Scripts", kind: "Скрипты", match: idMatch),
            Spec(dir: U + "/LaunchAgents", kind: "Автозапуск", match: idMatch),
            Spec(dir: S + "/Application Support", kind: "Данные (система)", match: anyMatch),
            Spec(dir: S + "/Caches", kind: "Кэш (система)", match: anyMatch),
            Spec(dir: S + "/Preferences", kind: "Настройки (система)", match: idMatch),
            Spec(dir: S + "/LaunchAgents", kind: "Автозапуск (система)", match: idMatch),
            Spec(dir: S + "/LaunchDaemons", kind: "Службы (система)", match: idMatch),
            Spec(dir: S + "/PrivilegedHelperTools", kind: "Помощник (система)", match: idMatch),
        ]

        var found: [String: Leftover] = [:]
        found[app.path] = Leftover(url: URL(fileURLWithPath: app.path), kind: "Приложение",
                                   needsAdmin: !fm.isDeletableFile(atPath: app.path))
        for spec in specs {
            guard let entries = try? fm.contentsOfDirectory(atPath: spec.dir) else { continue }
            for n in entries where spec.match(n) {
                let p = spec.dir + "/" + n
                if found[p] != nil { continue }
                found[p] = Leftover(url: URL(fileURLWithPath: p), kind: spec.kind,
                                    needsAdmin: !fm.isDeletableFile(atPath: p))
            }
        }
        return found.values.sorted { a, b in
            if (a.kind == "Приложение") != (b.kind == "Приложение") { return a.kind == "Приложение" }
            return a.url.path < b.url.path
        }
    }

    /// Удаляет пути навсегда с правами администратора.
    /// Используется стандартное окно авторизации macOS (то же, что у установщиков): имя пользователя подставляется само.
    static func removeAsAdmin(_ paths: [String]) -> Bool {
        let home = NSHomeDirectory()
        let safe = paths.filter { p in
            let comps = (p as NSString).pathComponents
            return p.hasPrefix("/") && comps.count >= 3 && !comps.contains("..")
                && !p.hasPrefix("/System/") && p != home
        }
        guard !safe.isEmpty else { return false }

        return Admin.run(tool: "/bin/rm", args: ["-rf", "--"] + safe).ok
    }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: keys)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                     errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in en {
            if let v = try? u.resourceValues(forKeys: keys), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

struct UninstallOverlay: View {
    @ObservedObject var model: UninstallModel
    let store: Store

    private func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    private func shortDir(_ u: URL) -> String {
        u.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 0) {
                header
                Divider()
                content
            }
            .frame(width: 540, height: 400)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: store.icon(for: model.app)).resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(Tf("Удаление «%@»", "\(model.app.name)")).font(.headline)
                Text(T("Приложение и связанные с ним файлы")).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .scanning:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(T("Ищу связанные файлы…")).foregroundColor(.secondary)
                Spacer()
                HStack { Spacer(); Button(T("Отмена")) { store.uninstall = nil } }.padding(12)
            }
        case .review:
            review
        case .confirm:
            confirm
        case .working:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(model.workText).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            }
        case .done:
            done
        }
    }

    private var review: some View {
        VStack(spacing: 0) {
            if model.wasRunning {
                Label(T("Приложение запущено — оно будет закрыто перед удалением"), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange).padding(.top, 8)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($model.items) { $item in row($item) }
                }
                .padding(.horizontal, 14)
            }
            Divider()
            HStack {
                Text(Tf("Выбрано: %@ из %@ · %@", "\(model.selectedItems.count)", "\(model.items.count)", "\(fmt(model.selectedSize))"))
                    .font(.callout)
                Spacer()
                Button(T("Отмена")) { store.uninstall = nil }
                Button(T("Удалить…")) { model.stage = .confirm }
                    .disabled(model.selectedItems.isEmpty)
            }
            .padding(12)
        }
    }

    private func row(_ item: Binding<Leftover>) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: item.selected).labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.wrappedValue.url.lastPathComponent).lineLimit(1)
                Text(shortDir(item.wrappedValue.url))
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.wrappedValue.needsAdmin {
                Image(systemName: "lock").foregroundColor(.secondary).help(T("Могут понадобиться права администратора"))
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(T(item.wrappedValue.kind)).font(.caption).foregroundColor(.secondary)
                Text(fmt(item.wrappedValue.size)).font(.caption)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .hoverHighlight(6)
        .contentShape(Rectangle())
        .onTapGesture { item.wrappedValue.selected.toggle() }
    }

    private var confirm: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundColor(.orange)
            Text(T("Вы уверены?")).font(.title3.bold())
            Text(Tf("В Корзину будет перемещено объектов: %@ (%@).\n", "\(model.selectedItems.count)", "\(fmt(model.selectedSize))")
                 + (model.wasRunning ? T("Приложение сейчас запущено и будет закрыто.\n") : "")
                 + T("Вернуть файлы можно из Корзины, пока вы её не очистили.\n")
                 + T("Что не удастся переместить в Корзину (нужны права администратора), будет удалено сразу и безвозвратно — система запросит пароль."))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            HStack {
                Button(T("Нет, вернуться")) { model.stage = .review }
                Button(T("Да, удалить")) { store.performUninstall(model) }
                    .foregroundColor(.red)
            }
            .padding(.bottom, 16)
        }
    }

    private var done: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(model.failed.isEmpty ? .green : .orange)
            Text(Tf("Перемещено в Корзину: %@", "\(model.trashedCount)")).font(.title3.bold())
            if model.adminRemoved > 0 {
                Text(Tf("Удалено с паролем администратора (без Корзины): %@", "\(model.adminRemoved)"))
                    .font(.callout).foregroundColor(.secondary)
            }
            if !model.failed.isEmpty {
                Text(Tf("Не удалось удалить (%@). Пароль не введён, файл защищён системой или нужен «Полный доступ к диску» для «Пуск»:", "\(model.failed.count)"))
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.failed, id: \.self) { p in
                            Text(p.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxHeight: 90)
            }
            Spacer()
            HStack {
                if !model.failed.isEmpty {
                    Button(T("Повторить с паролем")) { store.removeWithAdmin(model, paths: model.failed) }
                }
                Button(T("Закрыть")) { store.uninstall = nil }
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Разрешения

enum Permissions {
    /// Полный доступ к диску: без него системная база TCC не открывается на чтение
    static func hasFullDiskAccess() -> Bool {
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return false
    }

    /// Универсальный доступ (Accessibility): нужен для «Свернуть всё»
    static func hasAccessibility() -> Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openFullDiskAccessPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Bundle.main.bundlePath)])
    }

    /// Запрошенный доступ вступает в силу только после перезапуска приложения
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}

struct PermissionsOverlay: View {
    @ObservedObject var store: Store

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield").font(.system(size: 28)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T("Разрешения")).font(.headline)
                        Text(T("Что нужно «Пуск» для полного удаления приложений")).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        fullDisk
                        accessibilityRow
                        info("key", T("Права администратора"),
                             T("Заранее не нужны. Окно с паролем появится само, когда понадобится удалить файлы в /Library."))
                        info("lock.open", T("Данные других приложений"),
                             T("Если macOS спросит про доступ к данным других приложений — нажмите «Разрешить». Полный доступ к диску снимает эти вопросы."))
                    }
                    .padding(14)
                }
                Divider()
                HStack {
                    Spacer()
                    Button(T("Закрыть")) { store.showPermissions = false }
                }
                .padding(12)
            }
            .frame(width: 540, height: 400)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
        .onAppear { store.refreshPermissions() }
    }

    private var fullDisk: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: store.fullDiskAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(store.fullDiskAccess ? .green : .orange)
                Text(T("Полный доступ к диску")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(store.fullDiskAccess ? T("Выдан") : T("Не выдан"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(T("Нужен, чтобы полностью чистить данные приложений: контейнеры, почту, данные Safari и другие защищённые папки."))
                .font(.caption).foregroundColor(.secondary)
            if !store.fullDiskAccess {
                Text(T("1. Нажмите «Открыть настройки».\n2. Нажмите «+» и выберите «Пуск» (кнопка «Показать в Finder» покажет файл, его можно перетащить в список).\n3. Включите переключатель и нажмите «Перезапустить»."))
                    .font(.caption)
                HStack {
                    Button(T("Открыть настройки")) { Permissions.openFullDiskAccessPane() }
                    Button(T("Показать в Finder")) { Permissions.revealApp() }
                    Button(T("Проверить снова")) { store.refreshPermissions() }
                    Button(T("Перезапустить")) { Permissions.relaunch() }
                }
            }
        }
    }

    private var accessibilityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: store.accessibility ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(store.accessibility ? .green : .orange)
                Text(T("Универсальный доступ")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(store.accessibility ? T("Выдан") : T("Не выдан"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(T("Нужен для «Свернуть всё»: кнопка в строке меню, горячая клавиша и сворачивание кликом по иконке в Dock."))
                .font(.caption).foregroundColor(.secondary)
            if !store.accessibility {
                HStack {
                    Button(T("Запросить")) { Permissions.requestAccessibility() }
                    Button(T("Открыть настройки")) { Permissions.openAccessibilityPane() }
                    Button(T("Проверить снова")) { store.refreshPermissions() }
                }
            }
        }
    }

    private func info(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundColor(.secondary)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            Text(text).font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - Очистка мусора (как «Системный мусор» в CleanMyMac)

struct JunkItem: Identifiable {
    let id = UUID()
    let url: URL
    var size: Int64
    var needsAdmin: Bool
    var selected = false
}

struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let note: String
    var items: [JunkItem]
    var expanded = false
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter { $0.selected }.count }
    var selectedSize: Int64 { items.filter { $0.selected }.reduce(0) { $0 + $1.size } }
    var allSelected: Bool { !items.isEmpty && selectedCount == items.count }
    mutating func setAll(_ on: Bool) { for i in items.indices { items[i].selected = on } }
}

final class CleanModel: ObservableObject {
    enum Stage { case scanning, review, confirm, working, done }
    @Published var stage: Stage = .scanning
    @Published var categories: [JunkCategory] = []
    @Published var scanText = T("Начинаю проверку…")
    @Published var workText = T("Удаляю…")
    @Published var freed: Int64 = 0
    @Published var removedCount = 0
    @Published var failed: [String] = []
    var selectedItems: [JunkItem] { categories.flatMap { $0.items.filter { $0.selected } } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var totalSize: Int64 { categories.reduce(0) { $0 + $1.size } }
}

enum Junk {
    private static let skipNames: Set<String> = [".DS_Store", ".localized", ".com.apple.timemachine.donotpresent"]

    static func children(_ dir: String, skip: (String) -> Bool = { _ in false }) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return names.filter { !skipNames.contains($0) && !skip($0) }.map { URL(fileURLWithPath: dir + "/" + $0) }
    }

    /// Размеры считаем параллельно — кэши бывают огромными
    static func sizes(_ urls: [URL]) -> [Int64] {
        var out = [Int64](repeating: 0, count: urls.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            let s = Uninstaller.size(of: urls[i])
            lock.lock(); out[i] = s; lock.unlock()
        }
        return out
    }

    static func isInstalled(_ bid: String, ids: Set<String>) -> Bool {
        if ids.contains(bid) { return true }
        if ids.contains(where: { bid.hasPrefix($0 + ".") || $0.hasPrefix(bid + ".") }) { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil
    }

    static func scan(installedIDs: Set<String>, progress: @escaping (String) -> Void) -> [JunkCategory] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let lib = home + "/Library"
        var result: [JunkCategory] = []

        func make(_ id: String, _ title: String, _ symbol: String, _ note: String,
                  _ urls: [URL], selected: Bool) {
            guard !urls.isEmpty else { return }
            progress(title)
            let sz = sizes(urls)
            var items: [JunkItem] = []
            for (i, u) in urls.enumerated() where sz[i] > 0 {
                items.append(JunkItem(url: u, size: sz[i], needsAdmin: !fm.isDeletableFile(atPath: u.path)))
            }
            guard !items.isEmpty else { return }
            items.sort { $0.size > $1.size }
            for i in items.indices { items[i].selected = selected }
            result.append(JunkCategory(id: id, title: title, symbol: symbol, note: note, items: items))
        }

        // 1. Пользовательские кэши (данные Apple не трогаем)
        make("caches", T("Кэш приложений"), "internaldrive",
             T("Временные данные программ из ~/Library/Caches. Программы создадут их заново."),
             children(lib + "/Caches", skip: { $0.hasPrefix("com.apple.") }), selected: true)

        // 2. Логи и отчёты о сбоях
        var logs: [URL] = []
        for u in children(lib + "/Logs") {
            if u.lastPathComponent == "DiagnosticReports" { logs += children(u.path) } else { logs.append(u) }
        }
        make("logs", T("Логи и отчёты о сбоях"), "doc.text",
             T("Журналы работы программ и отчёты о сбоях из ~/Library/Logs."), logs, selected: true)

        // 3. Системные кэши и логи (нужен пароль)
        make("syscaches", T("Системные кэши и логи"), "gearshape.2",
             T("Файлы из /Library/Caches и /Library/Logs. Для удаления понадобится пароль администратора."),
             children("/Library/Caches", skip: { $0.hasPrefix("com.apple.") }) + children("/Library/Logs"),
             selected: true)

        // 4. Корзина
        make("trash", T("Корзина"), "trash",
             T("Всё, что лежит в Корзине. Удаляется безвозвратно. Для чтения нужен «Полный доступ к диску»."),
             children(home + "/.Trash"), selected: true)

        // 5. Xcode
        let dev = lib + "/Developer"
        make("xcode", T("Xcode: временные сборки"), "hammer",
             T("DerivedData и кэши симуляторов. Xcode пересоберёт их при следующей сборке."),
             children(dev + "/Xcode/DerivedData") + children(dev + "/CoreSimulator/Caches"), selected: true)
        make("xcodeDevice", T("Xcode: данные устройств"), "iphone",
             T("Файлы поддержки iOS/watchOS/tvOS (DeviceSupport). Xcode скачает их заново при подключении устройства."),
             children(dev + "/Xcode/iOS DeviceSupport") + children(dev + "/Xcode/watchOS DeviceSupport")
                + children(dev + "/Xcode/tvOS DeviceSupport"), selected: false)

        // 6. Установщики в «Загрузках»
        let installers = children(home + "/Downloads").filter {
            ["dmg", "pkg", "iso"].contains($0.pathExtension.lowercased())
        }
        make("installers", T("Установщики в «Загрузках»"), "shippingbox",
             T("Файлы .dmg, .pkg и .iso. Проверьте список: вдруг что-то ещё нужно."), installers, selected: false)

        // 7. Остатки удалённых приложений
        progress(T("Остатки удалённых приложений"))
        var orphans: [URL] = []
        for u in children(lib + "/Preferences") where u.pathExtension == "plist" && !u.lastPathComponent.hasPrefix(".") {
            let bid = u.deletingPathExtension().lastPathComponent
            if isOrphanID(bid, ids: installedIDs) { orphans.append(u) }
        }
        for u in children(lib + "/Saved Application State") where u.pathExtension == "savedState" {
            let bid = u.deletingPathExtension().lastPathComponent
            if isOrphanID(bid, ids: installedIDs) { orphans.append(u) }
        }
        make("orphans", T("Остатки удалённых приложений"), "puzzlepiece",
             T("Настройки и состояние окон программ, которых уже нет на Маке. Проверьте список перед удалением."),
             orphans, selected: false)

        return result
    }

    private static func isOrphanID(_ bid: String, ids: Set<String>) -> Bool {
        guard bid.split(separator: ".").count >= 3,
              !bid.hasPrefix("com.apple."), !bid.hasPrefix("group."), !bid.hasPrefix(".") else { return false }
        return !isInstalled(bid, ids: ids)
    }
}

struct CleanOverlay: View {
    @ObservedObject var model: CleanModel
    let store: Store

    private func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    var body: some View {
        ZStack {
            ToolScrim()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 28)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T("Очистка мусора")).font(.headline)
                        Text(T("Кэши, логи, Корзина, временные файлы Xcode")).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                content
            }
            .frame(width: 560, height: 410)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .scanning:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(T("Ищу мусор…")).foregroundColor(.secondary)
                Text(model.scanText).font(.caption).foregroundColor(.secondary)
                Spacer()
                HStack { Spacer(); Button(T("Отмена")) { store.clean = nil } }.padding(12)
            }
        case .review: review
        case .confirm: confirm
        case .working:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(model.workText).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            }
        case .done: done
        }
    }

    private var review: some View {
        VStack(spacing: 0) {
            if model.categories.isEmpty {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 36)).foregroundColor(.green)
                Text(T("Мусора не найдено")).font(.title3.bold()).padding(.top, 6)
                Spacer()
                HStack { Spacer(); Button(T("Закрыть")) { store.clean = nil } }.padding(12)
            } else {
                Text(Tf("Найдено: %@", "\(fmt(model.totalSize))")).font(.title3.bold()).padding(.top, 10)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($model.categories) { $cat in categoryRow($cat); Divider() }
                    }
                    .padding(.horizontal, 14)
                }
                Divider()
                HStack {
                    Text(Tf("Выбрано: %@", "\(fmt(model.selectedSize))")).font(.callout)
                    Spacer()
                    Button(T("Отмена")) { store.clean = nil }
                    Button(T("Очистить…")) { model.stage = .confirm }.disabled(model.selectedItems.isEmpty)
                }
                .padding(12)
            }
        }
    }

    private func categoryRow(_ cat: Binding<JunkCategory>) -> some View {
        let c = cat.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    cat.wrappedValue.setAll(!c.allSelected)
                } label: {
                    Image(systemName: c.allSelected ? "checkmark.square.fill"
                          : (c.selectedCount > 0 ? "minus.square.fill" : "square"))
                        .font(.system(size: 15))
                        .foregroundColor(c.selectedCount > 0 ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Image(systemName: c.symbol).frame(width: 22).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.system(size: 13, weight: .medium))
                        Text(c.note).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(fmt(c.size)).font(.callout)
                        if c.selectedCount > 0 && !c.allSelected {
                            Text(Tf("выбрано %@", "\(fmt(c.selectedSize))")).font(.caption2).foregroundColor(.accentColor)
                        }
                    }
                    Image(systemName: c.expanded ? "chevron.down" : "chevron.right")
                        .frame(width: 14).foregroundColor(.secondary)
                }
                .padding(.vertical, 3).padding(.horizontal, 4)
                .hoverHighlight(6)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { cat.wrappedValue.expanded.toggle() } }
            }
            if c.expanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(cat.items) { $it in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $it.selected).labelsHidden().toggleStyle(.checkbox)
                            Text(it.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            if it.needsAdmin { Image(systemName: "lock").foregroundColor(.secondary) }
                            Spacer()
                            Text(fmt(it.size)).foregroundColor(.secondary)
                        }
                        .font(.caption)
                        .padding(.vertical, 2).padding(.horizontal, 4)
                        .hoverHighlight(5)
                        .contentShape(Rectangle())
                        .onTapGesture { it.selected.toggle() }
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 7)
    }

    private var confirm: some View {
        let needsPassword = model.selectedItems.contains { $0.needsAdmin }
        return VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundColor(.orange)
            Text(T("Вы уверены?")).font(.title3.bold())
            Text(Tf("Будет удалено безвозвратно: %@ объектов (%@).\n", "\(model.selectedItems.count)", "\(fmt(model.selectedSize))")
                 + T("Вернуть их из Корзины не получится.")
                 + (needsPassword ? T("\nДля системных файлов система запросит пароль.") : ""))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            HStack {
                Button(T("Нет, вернуться")) { model.stage = .review }
                Button(T("Да, очистить")) { store.performClean(model) }.foregroundColor(.red)
            }
            .padding(.bottom, 16)
        }
    }

    private var done: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(model.failed.isEmpty ? .green : .orange)
            Text(Tf("Освобождено: %@", "\(fmt(model.freed))")).font(.title3.bold())
            Text(Tf("Удалено объектов: %@", "\(model.removedCount)")).font(.callout).foregroundColor(.secondary)
            if !model.failed.isEmpty {
                Text(Tf("Не удалось удалить (%@): файлы используются, защищены системой или нужен «Полный доступ к диску»:", "\(model.failed.count)"))
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.failed, id: \.self) { p in
                            Text(p.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxHeight: 80)
            }
            Spacer()
            Button(T("Закрыть")) { store.clean = nil }.padding(.bottom, 16)
        }
    }
}

// MARK: - Права администратора (стандартное окно авторизации macOS)

/// Запрос пароля администратора: показывается внутри окна «Пуск»
final class PasswordRequest: Identifiable {
    let id = UUID()
    let user: String
    let message: String?
    let completion: (String?) -> Void
    init(user: String, message: String?, completion: @escaping (String?) -> Void) {
        self.user = user
        self.message = message
        self.completion = completion
    }
}

enum Admin {
    struct Result {
        var ok: Bool
        var output: String = ""
        /// Короткое пояснение, если что-то пошло не так (попадает в сообщение пользователю)
        var detail: String = ""
    }

    private static var cached: (password: String, date: Date)?
    private static let lock = NSLock()

    /// Спрашиваем пароль в окне «Пуск» и ждём ответа (вызывать только не из главного потока)
    private static func ask(message: String?) -> String? {
        let sem = DispatchSemaphore(value: 0)
        var answer: String?
        DispatchQueue.main.async {
            guard let store = Store.current else { sem.signal(); return }
            store.pwTool = ToolWindows.shared.keyKind()
            store.pwRequest = PasswordRequest(user: NSUserName(), message: message) { pw in
                answer = pw
                sem.signal()
            }
        }
        sem.wait()
        return answer
    }

    /// sudo читает пароль со стандартного входа — в списке процессов он не виден
    private static func sudo(_ password: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-S", "-k", "-p", ""] + args
        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = outPipe
        do { try p.run() } catch { return (-1, "") }
        inPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8) ?? Data())
        try? inPipe.fileHandleForWriting.close()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Запускает программу с правами администратора. Пароль пользователь вводит в окне «Пуск»;
    /// он держится в памяти 5 минут, чтобы не спрашивать несколько раз подряд.
    static func run(tool: String, args: [String]) -> Result {
        var message: String? = nil
        for _ in 0..<3 {
            let password: String
            lock.lock(); let c = cached; lock.unlock()
            if let c = c, Date().timeIntervalSince(c.date) < 300 {
                password = c.password
            } else {
                guard let asked = ask(message: message) else {
                    return Result(ok: false, detail: T("отменено пользователем"))
                }
                password = asked
            }
            if sudo(password, ["/usr/bin/true"]).0 != 0 {
                lock.lock(); cached = nil; lock.unlock()
                message = T("Неверный пароль, попробуйте ещё раз")
                continue
            }
            lock.lock(); cached = (password, Date()); lock.unlock()
            let (code, out) = sudo(password, [tool] + args)
            return Result(ok: true, output: out, detail: code == 0 ? "" : Tf("код %@", "\(code)"))
        }
        return Result(ok: false, detail: T("неверный пароль"))
    }
}

/// На время ввода пароля переключаем раскладку на английскую, потом возвращаем прежнюю
enum InputSourceSwitcher {
    private static var saved: TISInputSource?

    static func switchToASCII() {
        saved = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            TISSelectInputSource(ascii)
        }
    }

    static func restore() {
        if let s = saved { TISSelectInputSource(s) }
        saved = nil
    }
}

/// Невидимый элемент, который ловит нажатия клавиш и собирает пароль
struct PasswordCapture: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    final class Catcher: NSView {
        var parent: PasswordCapture?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let w = self.window else { return }
                w.makeFirstResponder(self)
            }
        }
        override func keyDown(with event: NSEvent) {
            guard let p = parent else { return }
            switch event.keyCode {
            case 36, 76: p.onSubmit(); return
            case 53: p.onCancel(); return
            case 51:
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) { p.text = "" }
                else if !p.text.isEmpty { p.text.removeLast() }
                return
            default: break
            }
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { return }
            if let chars = event.characters {
                let printable = chars.filter { !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
                p.text += printable
            }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard let p = parent else { return false }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
                if let str = NSPasteboard.general.string(forType: .string) {
                    p.text += str.filter { !$0.isNewline }
                }
                return true
            }
            return false
        }
    }

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher()
        v.parent = self
        return v
    }

    func updateNSView(_ v: Catcher, context: Context) { v.parent = self }
}

struct PasswordOverlay: View {
    let request: PasswordRequest
    let store: Store
    @State private var password = ""
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 30)).foregroundColor(.accentColor)
                Text(T("Нужен пароль администратора")).font(.headline)
                Text(Tf("«Пуск» вносит изменения в систему.\nПользователь: %@", "\(request.user)"))
                    .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                if let m = request.message {
                    Text(m).font(.callout).foregroundColor(.orange)
                }
                // Своё поле ввода: никаких подсказок менеджеров паролей и пароль никогда не виден
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor))
                    RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                    if password.isEmpty {
                        Text(T("Пароль")).foregroundColor(.secondary)
                    } else {
                        Text(String(repeating: "●", count: password.count))
                            .lineLimit(1).truncationMode(.head).padding(.horizontal, 8)
                    }
                    PasswordCapture(text: $password, onSubmit: { submit() }, onCancel: {
                        cancel()
                        // Esc закрывает и само окно «Пуск»
                        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
                    })
                }
                .frame(width: 260, height: 26)
                HStack {
                    Button(T("Отмена")) { cancel() }
                    Button(T("Разрешить")) { submit() }.disabled(password.isEmpty)
                }
            }
            .padding(22)
            .frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
        .onAppear {
            InputSourceSwitcher.switchToASCII()
        }
        .onDisappear { InputSourceSwitcher.restore() }
    }

    private func submit() {
        let pw = password
        password = ""
        store.pwRequest = nil
        request.completion(pw)
    }

    private func cancel() {
        password = ""
        store.pwRequest = nil
        request.completion(nil)
    }
}

// MARK: - Обслуживание системы

enum MaintStatus: Equatable {
    case idle, running, ok(String), failed(String)
}

struct MaintTask: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let info: String
    let needsAdmin: Bool
    var selected = false
    var status: MaintStatus = .idle
}

final class MaintModel: ObservableObject {
    @Published var tasks: [MaintTask] = Maintenance.allTasks
    @Published var running = false
    @Published var note = ""

    var selectedCount: Int { tasks.filter { $0.selected }.count }

    func set(_ id: String, _ status: MaintStatus) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].status = status }
    }
}

enum Maintenance {
    static let allTasks: [MaintTask] = [
        MaintTask(id: "ram", title: T("Освободить оперативную память"), symbol: "memorychip",
                  info: T("Выгружает неиспользуемые данные из памяти, чтобы программы открывались быстрее."),
                  needsAdmin: true),
        MaintTask(id: "scripts", title: T("Запустить скрипты обслуживания"), symbol: "checklist",
                  info: T("Ежедневные, еженедельные и ежемесячные задачи macOS: ротация логов и очистка временных данных."),
                  needsAdmin: true),
        MaintTask(id: "dns", title: T("Сбросить кэш DNS"), symbol: "network",
                  info: T("Помогает, если сайты не открываются или открываются по старым адресам."),
                  needsAdmin: true),
        MaintTask(id: "mail", title: T("Ускорить Почту"), symbol: "envelope",
                  info: T("Оптимизирует базу писем в «Почте». Почта должна быть закрыта, нужен «Полный доступ к диску»."),
                  needsAdmin: false),
        MaintTask(id: "spotlight", title: T("Переиндексировать Spotlight"), symbol: "magnifyingglass",
                  info: T("Пересоздаёт поисковый индекс, если Spotlight не находит файлы. Индексация займёт какое-то время."),
                  needsAdmin: true),
        MaintTask(id: "perms", title: T("Восстановить права доступа"), symbol: "lock.rotation",
                  info: T("Сбрасывает права на файлы вашей домашней папки к стандартным."),
                  needsAdmin: false),
        MaintTask(id: "tm", title: T("Прореживание снимков Time Machine"), symbol: "clock.arrow.circlepath",
                  info: T("Удаляет локальные снимки Time Machine и освобождает занятое ими место."),
                  needsAdmin: true),
    ]

    /// Команды, которым нужен администратор (выполняются все вместе, пароль спрашивается один раз)
    static func adminCommand(_ id: String) -> String? {
        switch id {
        case "ram": return "/usr/sbin/purge"
        case "scripts": return "/usr/sbin/periodic daily weekly monthly"
        case "dns": return "/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder"
        case "spotlight": return "/usr/bin/mdutil -E /"
        case "tm": return "/usr/bin/tmutil thinlocalsnapshots / 99999999999 4"
        default: return nil
        }
    }

    /// Задачи, которые выполняются от имени пользователя
    static func runUser(_ id: String) -> MaintStatus? {
        switch id {
        case "mail": return speedUpMail()
        case "perms": return resetPermissions()
        default: return nil
        }
    }

    private static func shell(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func speedUpMail() -> MaintStatus {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty {
            return .failed(T("Закройте «Почту» и повторите"))
        }
        let fm = FileManager.default
        let base = NSHomeDirectory() + "/Library/Mail"
        guard let versions = try? fm.contentsOfDirectory(atPath: base) else {
            return .failed(T("Нет доступа к ~/Library/Mail — нужен «Полный доступ к диску»"))
        }
        var done = 0
        for v in versions where v.hasPrefix("V") {
            let db = "\(base)/\(v)/MailData/Envelope Index"
            if fm.fileExists(atPath: db), shell("/usr/bin/sqlite3", [db, "VACUUM;"]).0 == 0 { done += 1 }
        }
        return done > 0 ? .ok(Tf("Оптимизировано баз: %@", "\(done)")) : .failed(T("База «Почты» не найдена или нет доступа"))
    }

    private static func resetPermissions() -> MaintStatus {
        let r = shell("/usr/sbin/diskutil", ["resetUserPermissions", "/", String(getuid())])
        return r.0 == 0 ? .ok(T("Права восстановлены")) : .failed(Tf("Не удалось (код %@)", "\(r.0)"))
    }
}

// MARK: - Анализатор диска (как DaisyDisk)

final class DiskNode: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var size: Int64
    let isDir: Bool
    var isBucket = false
    var children: [DiskNode] = []
    weak var parent: DiskNode?

    init(name: String, url: URL, size: Int64, isDir: Bool) {
        self.name = name
        self.url = url
        self.size = size
        self.isDir = isDir
    }
}

enum DiskScanner {
    /// Файлы и папки меньше 1 МБ в дерево не попадают, а суммируются в «Мелкие объекты» — иначе дерево всего диска не поместилось бы в память
    static let threshold: Int64 = 1_048_576
    /// Папки, которые не обходим никогда: iCloud Drive и сторонние файловые провайдеры (обход идёт через сетевой провайдер и подвисает) и служебные дубликаты
    static let skipSuffixes = ["/Library/Mobile Documents", "/Library/CloudStorage"]
    static let skipAlways: Set<String> = ["/.nofollow", "/.vol", "/dev", "/net", "/home", "/Network", "/Volumes", "/System/Volumes", "/private/var/vm", "/.Spotlight-V100", "/.fseventsd", "/.DocumentRevisions-V100"]

    final class State {
        let lock = NSLock()
        var scanned = 0
        var unreadable = 0
        var cancelled = false
        var path = ""
        var links = Set<UInt64>()
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    static func scan(root: URL, skip: Set<String>, state: State) -> DiskNode {
        let path = root.path
        return scanDir(path, name: path == "/" ? "/" : root.lastPathComponent, depth: 0, skip: skip.union(skipAlways), state: state)
    }

    /// Пересканирование одной папки: kept-подпапки из `reuse` берутся готовыми, остальное (мелкое) читается заново
    static func scanNode(_ path: String, name: String, skip: Set<String>, state: State, reuse: [String: DiskNode]?) -> DiskNode {
        scanDir(path, name: name, depth: 0, skip: skip, state: state, reuse: reuse)
    }

    private static func scanDir(_ path: String, name: String, depth: Int, skip: Set<String>, state: State, reuse: [String: DiskNode]? = nil) -> DiskNode {
        let node = DiskNode(name: name, url: URL(fileURLWithPath: path), size: 0, isDir: true)
        if state.isCancelled { return node }
        if depth <= 5 { state.lock.lock(); state.path = path; state.lock.unlock() }
        guard let dir = opendir(path) else {
            state.lock.lock(); state.unreadable += 1; state.lock.unlock()
            return node
        }
        let fd = dirfd(dir)
        var total: Int64 = 0
        var small: Int64 = 0
        var smallCount = 0
        var count = 0
        var kept: [DiskNode] = []
        var dirs: [(String, String)] = []
        var reused: [DiskNode] = []
        var st = stat()
        while let ent = readdir(dir) {
            let nm = withUnsafePointer(to: &ent.pointee.d_name) { p in
                p.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if nm == "." || nm == ".." { continue }
            count += 1
            var type = ent.pointee.d_type
            if type == UInt8(DT_LNK) { continue }
            var haveStat = false
            if type == UInt8(DT_UNKNOWN) {
                guard fstatat(fd, nm, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
                haveStat = true
                switch st.st_mode & S_IFMT {
                case S_IFDIR: type = UInt8(DT_DIR)
                case S_IFREG: type = UInt8(DT_REG)
                default: continue
                }
            }
            if type == UInt8(DT_DIR) {
                let full = path == "/" ? "/" + nm : path + "/" + nm
                if skip.contains(full) { continue }
                if skipSuffixes.contains(where: { full.hasSuffix($0) }) { continue }
                if let r = reuse?[nm] { reused.append(r); continue }
                dirs.append((full, nm))
            } else if type == UInt8(DT_REG) {
                if !haveStat, fstatat(fd, nm, &st, AT_SYMLINK_NOFOLLOW) != 0 { continue }
                // жёсткие ссылки считаем один раз
                if st.st_nlink > 1, !state.markLink(UInt64(st.st_ino) ^ (UInt64(UInt32(bitPattern: st.st_dev)) << 48)) { continue }
                let sz = Int64(st.st_blocks) * 512
                total += sz
                if sz >= threshold {
                    kept.append(DiskNode(name: nm, url: URL(fileURLWithPath: path == "/" ? "/" + nm : path + "/" + nm), size: sz, isDir: false))
                } else {
                    small += sz
                    smallCount += 1
                }
            }
        }
        closedir(dir)
        state.lock.lock(); state.scanned += count; state.lock.unlock()

        var results = [DiskNode?](repeating: nil, count: dirs.count)
        let rlock = NSLock()
        let work: (Int) -> Void = { i in
            let child = scanDir(dirs[i].0, name: dirs[i].1, depth: depth + 1, skip: skip, state: state)
            rlock.lock(); results[i] = child; rlock.unlock()
        }
        if depth < 4 && dirs.count > 1 {
            DispatchQueue.concurrentPerform(iterations: dirs.count, execute: work)
        } else {
            for i in dirs.indices { work(i) }
        }
        for child in reused + results.compactMap({ $0 }) {
            total += child.size
            if child.size >= threshold { kept.append(child) } else { small += child.size; smallCount += 1 }
        }
        node.size = total
        if total < threshold { return node }
        if small > 0 {
            let b = DiskNode(name: Tf("Мелкие объекты (%@)", "\(smallCount)"), url: node.url, size: small, isDir: false)
            b.isBucket = true
            kept.append(b)
        }
        kept.sort { $0.size > $1.size }
        for c in kept { c.parent = node }
        node.children = kept
        return node
    }
}

extension DiskScanner.State {
    /// true — ссылка встретилась впервые и её размер надо учесть
    func markLink(_ key: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return links.insert(key).inserted
    }
}

struct DiskCacheNode: Codable {
    var n: String
    var s: Int64
    var d: Bool
    var b: Bool
    var c: [DiskCacheNode]
}

struct DiskCache: Codable {
    var root: String
    var event: UInt64
    var date: Date
    var unreadable: Int
    var tree: DiskCacheNode
}

extension DiskNode {
    func cacheNode() -> DiskCacheNode {
        DiskCacheNode(n: name, s: size, d: isDir, b: isBucket, c: children.map { $0.cacheNode() })
    }

    static func from(_ c: DiskCacheNode, url: URL, parent: DiskNode?) -> DiskNode {
        let node = DiskNode(name: c.n, url: url, size: c.s, isDir: c.d)
        node.isBucket = c.b
        node.parent = parent
        node.children = c.c.map { ch in
            DiskNode.from(ch, url: ch.b ? url : url.appendingPathComponent(ch.n), parent: node)
        }
        return node
    }
}

/// Журнал изменений файловой системы (FSEvents): какие папки менялись с момента `since`
final class FSHistory {
    private var paths: [(String, Bool)] = []
    private var bad = false
    private var finished = false
    private var stream: FSEventStreamRef?
    private var done: (([(String, Bool)]?) -> Void)?
    private let queue = DispatchQueue(label: "disk.fshistory")

    func start(root: String, since: UInt64, done: @escaping ([(String, Bool)]?) -> Void) {
        self.done = done
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let me = Unmanaged<FSHistory>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let droppedMask = UInt32(kFSEventStreamEventFlagUserDropped) | UInt32(kFSEventStreamEventFlagKernelDropped) | UInt32(kFSEventStreamEventFlagEventIdsWrapped)
            for i in 0..<count {
                let f = eventFlags[i]
                if f & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { me.finish(); return }
                if f & droppedMask != 0 { me.bad = true }
                if i < list.count { me.paths.append((list[i], f & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0)) }
            }
        }
        guard let s = FSEventStreamCreate(nil, callback, &ctx, [root] as CFArray, since, 0.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else {
            done(nil)
            return
        }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        queue.asyncAfter(deadline: .now() + 60) { [weak self] in self?.finish(timeout: true) }
    }

    private func finish(timeout: Bool = false) {
        if finished { return }
        finished = true
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        let result: [(String, Bool)]? = (bad || timeout) ? nil : paths
        let d = done
        done = nil
        d?(result)
    }
}

final class DiskModel: ObservableObject {
    static let shared = DiskModel()

    enum Stage { case choose, scanning, result }
    @Published var stage: Stage = .choose
    @Published var root: DiskNode?
    @Published var current: DiskNode?
    @Published var scanned = 0
    @Published var scanPath = ""
    @Published var unreadable = 0
    @Published var pendingDelete: DiskNode?
    @Published var message: String?
    @Published var refreshing = false
    @Published var scanDate: Date?
    private(set) var whole = false
    private var eventId: UInt64 = 0
    private var generation = 0
    private var state: DiskScanner.State?
    private var timer: Timer?
    private var history: FSHistory?

    private struct Target {
        let node: DiskNode
        var full: Bool
        let depth: Int
    }

    private var rootPath: String { whole ? "/" : NSHomeDirectory() }
    private var skipSet: Set<String> { whole ? ["/Volumes", "/System/Volumes", "/dev", "/net", "/home"] : [] }

    private static func cacheURL(whole: Bool) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StartMenu")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(whole ? "disk-whole.json" : "disk-home.json")
    }

    /// Открыть анализ: если есть сохранённый — показать его сразу и обновить только изменения; иначе полный обход
    func scan(whole: Bool, fresh: Bool = false) {
        self.whole = whole
        message = nil
        if fresh { fullScan(); return }
        generation += 1
        let gen = generation
        let rp = rootPath
        stage = .scanning
        scanned = 0
        scanPath = T("Загрузка сохранённого анализа…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var cache: DiskCache?
            if let data = try? Data(contentsOf: DiskModel.cacheURL(whole: whole)),
               let c = try? JSONDecoder().decode(DiskCache.self, from: data),
               c.root == rp, Date().timeIntervalSince(c.date) < 14 * 86400 {
                cache = c
            }
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation, self.stage == .scanning else { return }
                if let c = cache {
                    self.install(c)
                    self.refresh()
                } else {
                    self.fullScan()
                }
            }
        }
    }

    private func install(_ c: DiskCache) {
        let r = DiskNode.from(c.tree, url: URL(fileURLWithPath: c.root), parent: nil)
        root = r
        current = r
        eventId = c.event
        scanDate = c.date
        unreadable = c.unreadable
        stage = .result
    }

    private func saveCache() {
        guard let root = root else { return }
        let cache = DiskCache(root: rootPath, event: eventId, date: scanDate ?? Date(), unreadable: unreadable, tree: root.cacheNode())
        let url = DiskModel.cacheURL(whole: whole)
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func fullScan() {
        generation += 1
        let gen = generation
        stage = .scanning
        scanned = 0
        scanPath = ""
        message = nil
        refreshing = false
        let ev = FSEventsGetCurrentEventId()
        let st = DiskScanner.State()
        state = st
        let rootURL = URL(fileURLWithPath: rootPath)
        let skip = skipSet
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            st.lock.lock(); let n = st.scanned; let p = st.path; st.lock.unlock()
            self?.scanned = n
            self?.scanPath = p
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let node = DiskScanner.scan(root: rootURL, skip: skip, state: st)
            st.lock.lock(); let bad = st.unreadable; st.lock.unlock()
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation, !st.isCancelled else { return }
                self.timer?.invalidate()
                self.root = node
                self.current = node
                self.unreadable = bad
                self.eventId = ev
                self.scanDate = Date()
                self.stage = .result
                self.saveCache()
            }
        }
    }

    /// Дешёвое обновление: берём из журнала FSEvents только папки, менявшиеся после прошлого анализа, и перечитываем их
    func refresh() {
        guard stage == .result, root != nil, !refreshing else { return }
        refreshing = true
        let gen = generation
        let newEvent = FSEventsGetCurrentEventId()
        let h = FSHistory()
        history = h
        h.start(root: rootPath, since: eventId) { [weak self] events in
            DispatchQueue.main.async { self?.applyChanges(events, newEvent: newEvent, gen: gen) }
        }
    }

    private func applyChanges(_ events: [(String, Bool)]?, newEvent: UInt64, gen: Int) {
        history = nil
        guard gen == generation, stage == .result else { refreshing = false; return }
        guard let events = events, events.count < 50000, let rootNode = root else {
            refreshing = false
            fullScan()
            return
        }
        let rp = rootPath
        let prefix = rp == "/" ? "/" : rp + "/"
        let skip = skipSet.union(DiskScanner.skipAlways)
        var targets: [Target] = []
        for (raw, must) in events {
            var p = raw
            if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
            guard p == rp || p.hasPrefix(prefix) else { continue }
            if skip.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { continue }
            if DiskScanner.skipSuffixes.contains(where: { p.hasSuffix($0) || p.contains($0 + "/") }) { continue }
            var node = rootNode
            var depth = 0
            if p != rp {
                for comp in p.dropFirst(prefix.count).split(separator: "/") {
                    let name = String(comp)
                    if let ch = node.children.first(where: { $0.isDir && !$0.isBucket && $0.name == name }) {
                        node = ch
                        depth += 1
                    } else { break }
                }
            }
            let exact = node.url.path == p
            if let idx = targets.firstIndex(where: { $0.node === node }) {
                if must && exact { targets[idx].full = true }
            } else {
                targets.append(Target(node: node, full: must && exact, depth: depth))
            }
        }
        targets.sort { $0.depth < $1.depth }
        let curPath = current?.url.path
        let st = DiskScanner.State()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [(DiskNode, DiskNode)] = []
            for t in targets {
                var reuse: [String: DiskNode]? = nil
                if !t.full {
                    var r: [String: DiskNode] = [:]
                    for c in t.node.children where c.isDir && !c.isBucket { r[c.name] = c }
                    reuse = r
                }
                let n = DiskScanner.scanNode(t.node.url.path, name: t.node.name, skip: skip, state: st, reuse: reuse)
                results.append((t.node, n))
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                defer { self.refreshing = false }
                guard gen == self.generation else { return }
                self.objectWillChange.send()
                for (old, new) in results { self.replace(old, with: new) }
                if let cp = curPath, let r = self.root { self.current = self.find(cp, in: r) } else { self.current = self.root }
                self.eventId = newEvent
                self.scanDate = Date()
                self.saveCache()
            }
        }
    }

    private func find(_ path: String, in rootNode: DiskNode) -> DiskNode {
        let rp = rootPath
        let prefix = rp == "/" ? "/" : rp + "/"
        guard path != rp, path.hasPrefix(prefix) else { return rootNode }
        var node = rootNode
        for comp in path.dropFirst(prefix.count).split(separator: "/") {
            let name = String(comp)
            guard let ch = node.children.first(where: { $0.isDir && !$0.isBucket && $0.name == name }) else { return node }
            node = ch
        }
        return node
    }

    private func isAttached(_ n: DiskNode) -> Bool {
        var x = n
        while let p = x.parent {
            if !p.children.contains(where: { $0 === x }) { return false }
            x = p
        }
        return x === root
    }

    private func replace(_ old: DiskNode, with new: DiskNode) {
        guard isAttached(old) else { return }
        guard let parent = old.parent else { root = new; return }
        let delta = new.size - old.size
        parent.children.removeAll { $0 === old }
        if new.size >= DiskScanner.threshold {
            new.parent = parent
            parent.children.append(new)
        } else if let b = parent.children.first(where: { $0.isBucket }) {
            b.size += new.size
        } else {
            let b = DiskNode(name: Tf("Мелкие объекты (%@)", "1"), url: parent.url, size: new.size, isDir: false)
            b.isBucket = true
            b.parent = parent
            parent.children.append(b)
        }
        var p: DiskNode? = parent
        while let q = p {
            q.size += delta
            q.children.sort { $0.size > $1.size }
            p = q.parent
        }
    }

    func cancel() {
        generation += 1
        if let st = state { st.lock.lock(); st.cancelled = true; st.lock.unlock() }
        timer?.invalidate()
        refreshing = false
        stage = .choose
    }

    func drill(_ n: DiskNode) { if n.isDir && !n.isBucket { current = n } }
    func up() { if let p = current?.parent { current = p } }

    func trash(_ n: DiskNode) {
        NSWorkspace.shared.recycle([n.url]) { _, error in
            DispatchQueue.main.async {
                if let e = error {
                    self.message = Tf("Не удалось переместить в Корзину: %@", e.localizedDescription)
                    return
                }
                let size = n.size
                var p = n.parent
                p?.children.removeAll { $0 === n }
                while let q = p { q.size -= size; p = q.parent }
                self.objectWillChange.send()
                self.saveCache()
            }
        }
    }
}

struct DiskSeg {
    let node: DiskNode
    let a0: Double
    let a1: Double
    let ring: Int
    let color: Color
}

struct SunburstView: View {
    let current: DiskNode
    let onPick: (DiskNode) -> Void
    let onUp: () -> Void
    private let rings = 3

    private func segments() -> [DiskSeg] {
        var out: [DiskSeg] = []
        func walk(_ n: DiskNode, _ a0: Double, _ a1: Double, _ ring: Int, _ hue: Double?) {
            guard ring < rings else { return }
            let total = Double(n.children.reduce(0) { $0 + $1.size })
            guard total > 0 else { return }
            var start = a0
            for c in n.children {
                let span = (a1 - a0) * Double(c.size) / total
                if span >= 0.012 {
                    let h = hue ?? ((start + span / 2) / (2 * Double.pi))
                    let color: Color = c.isBucket
                        ? Color(white: 0.6 - 0.05 * Double(ring))
                        : Color(hue: h, saturation: 0.55 - 0.07 * Double(ring), brightness: 0.95 - 0.07 * Double(ring))
                    out.append(DiskSeg(node: c, a0: start, a1: start + span, ring: ring, color: color))
                    if c.isDir && !c.isBucket { walk(c, start, start + span, ring + 1, h) }
                }
                start += span
            }
        }
        walk(current, 0, 2 * Double.pi, 0, nil)
        return out
    }

    private func geometry(_ size: CGSize) -> (c: CGPoint, R: CGFloat, hole: CGFloat, ringW: CGFloat) {
        let R = max(10, min(size.width, size.height) / 2 - 4)
        let hole = R * 0.28
        return (CGPoint(x: size.width / 2, y: size.height / 2), R, hole, (R - hole) / CGFloat(rings))
    }

    var body: some View {
        GeometryReader { geo in
            let g = geometry(geo.size)
            let segs = segments()
            ZStack {
                Canvas { ctx, size in
                    for sg in segs {
                        let r0 = g.hole + g.ringW * CGFloat(sg.ring) + 1
                        let r1 = g.hole + g.ringW * CGFloat(sg.ring + 1) - 1
                        var path = Path()
                        let steps = max(2, Int((sg.a1 - sg.a0) / 0.04))
                        for i in 0...steps {
                            let a = sg.a0 + (sg.a1 - sg.a0) * Double(i) / Double(steps) - Double.pi / 2
                            let pt = CGPoint(x: g.c.x + r1 * CGFloat(cos(a)), y: g.c.y + r1 * CGFloat(sin(a)))
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        for i in stride(from: steps, through: 0, by: -1) {
                            let a = sg.a0 + (sg.a1 - sg.a0) * Double(i) / Double(steps) - Double.pi / 2
                            path.addLine(to: CGPoint(x: g.c.x + r0 * CGFloat(cos(a)), y: g.c.y + r0 * CGFloat(sin(a))))
                        }
                        path.closeSubpath()
                        ctx.fill(path, with: .color(sg.color))
                    }
                    let hole = Path(ellipseIn: CGRect(x: g.c.x - g.hole, y: g.c.y - g.hole, width: g.hole * 2, height: g.hole * 2))
                    ctx.fill(hole, with: .color(Color.primary.opacity(0.08)))
                }
                VStack(spacing: 2) {
                    if current.parent != nil { Image(systemName: "arrow.up").font(.caption).foregroundColor(.secondary) }
                    Text(current.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: current.size, countStyle: .file))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                .frame(width: g.hole * 1.7)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                let dx = v.location.x - g.c.x
                let dy = v.location.y - g.c.y
                let r = (dx * dx + dy * dy).squareRoot()
                if r <= g.hole { onUp(); return }
                guard r <= g.R else { return }
                let ring = Int((r - g.hole) / g.ringW)
                var a = Double(atan2(dy, dx)) + Double.pi / 2
                if a < 0 { a += 2 * Double.pi }
                if let hit = segs.first(where: { $0.ring == ring && a >= $0.a0 && a < $0.a1 }) { onPick(hit.node) }
            })
        }
    }
}

struct DiskPanel: View {
    @ObservedObject var model: DiskModel
    @ObservedObject var store: Store

    private func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func openFullDiskSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(u) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "chart.pie.fill").font(.system(size: 26)).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Анализатор диска")).font(.headline)
                    Text(T("Что занимает место: нажмите на сектор или папку, чтобы заглянуть внутрь"))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            Divider()
            content
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay { if let d = model.pendingDelete { confirm(d) } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .choose:
            VStack(spacing: 14) {
                Spacer()
                HStack(spacing: 16) {
                    Button { model.scan(whole: false) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "house").font(.system(size: 26))
                            Text(T("Домашняя папка"))
                        }.frame(width: 150, height: 90)
                    }
                    Button { model.scan(whole: true) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "internaldrive").font(.system(size: 26))
                            Text(T("Весь диск"))
                        }.frame(width: 150, height: 90)
                    }
                }
                if !store.fullDiskAccess {
                    Text(T("Для анализа всего диска нужен «Полный доступ к диску», иначе часть папок будет недоступна."))
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
                    Button(T("Разрешения…")) { openFullDiskSettings() }
                }
                Spacer()
                HStack { Spacer(); Button(T("Закрыть")) { DiskWindowController.shared.close() } }.padding(12)
            }
        case .scanning:
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text(Tf("Просмотрено: %@", "\(model.scanned)")).foregroundColor(.secondary)
                Text(model.scanPath).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle).padding(.horizontal, 30)
                Spacer()
                HStack { Spacer(); Button(T("Отмена")) { model.cancel() } }.padding(12)
            }
        case .result:
            if let cur = model.current, let root = model.root {
                VStack(spacing: 0) {
                    crumbs(cur)
                    Divider()
                    HStack(spacing: 0) {
                        SunburstView(current: cur, onPick: { model.drill($0) }, onUp: { model.up() })
                            .padding(12)
                            .frame(minWidth: 240)
                        Divider()
                        list(cur, root)
                            .frame(minWidth: 280)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Tf("Всего: %@", "\(fmt(root.size))")).font(.callout)
                            if model.refreshing {
                                Text(T("Обновляется…")).font(.caption).foregroundColor(.secondary)
                            } else if let d = model.scanDate {
                                Text(Tf("Данные от %@", DiskPanel.dateFmt.string(from: d))).font(.caption).foregroundColor(.secondary)
                            }
                            if model.unreadable > 0 {
                                if store.fullDiskAccess {
                                    Text(Tf("Защищено macOS и не читается: %@ папок (системные данные)", "\(model.unreadable)"))
                                        .font(.caption).foregroundColor(.secondary)
                                } else {
                                    Text(Tf("Часть папок недоступна: %@. Выдайте «Полный доступ к диску».", "\(model.unreadable)"))
                                        .font(.caption).foregroundColor(.orange)
                                }
                            }
                            if let m = model.message { Text(m).font(.caption).foregroundColor(.orange) }
                        }
                        Spacer()
                        if model.unreadable > 0 && !store.fullDiskAccess { Button(T("Разрешения…")) { openFullDiskSettings() } }
                        Button(T("Пересканировать")) { model.scan(whole: model.whole, fresh: true) }
                        Button(T("Новый анализ")) { model.stage = .choose }
                        Button(T("Закрыть")) { DiskWindowController.shared.close() }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func crumbs(_ cur: DiskNode) -> some View {
        var chain: [DiskNode] = []
        var n: DiskNode? = cur
        while let x = n { chain.insert(x, at: 0); n = x.parent }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.offset) { i, node in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary) }
                    Button { model.current = node } label: {
                        Text(node.name).font(.system(size: 12, weight: node === cur ? .semibold : .regular))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(5)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private func list(_ cur: DiskNode, _ root: DiskNode) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(cur.children.prefix(300)) { c in
                    HStack(spacing: 8) {
                        Image(systemName: c.isBucket ? "ellipsis.circle" : (c.isDir ? "folder.fill" : "doc"))
                            .foregroundColor(c.isDir && !c.isBucket ? .accentColor : .secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).lineLimit(1).truncationMode(.middle)
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.5))
                                    .frame(width: g.size.width * CGFloat(Double(c.size) / Double(max(1, cur.size))), height: 3)
                            }
                            .frame(height: 3)
                        }
                        Text(fmt(c.size)).font(.callout).foregroundColor(.secondary)
                        if !c.isBucket {
                            Button { NSWorkspace.shared.activateFileViewerSelecting([c.url]) } label: {
                                Image(systemName: "magnifyingglass.circle").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain).help(T("Показать в Finder"))
                            Button { model.pendingDelete = c } label: {
                                Image(systemName: "trash").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain).disabled(model.refreshing).help(T("В Корзину…"))
                        }
                    }
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .hoverHighlight(6)
                    .contentShape(Rectangle())
                    .onTapGesture { model.drill(c) }
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
    }

    private func confirm(_ d: DiskNode) -> some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 12) {
                Image(systemName: "trash.circle.fill").font(.system(size: 34)).foregroundColor(.orange)
                Text(T("Переместить в Корзину?")).font(.title3.bold())
                Text("\(d.name) (\(fmt(d.size)))").multilineTextAlignment(.center).lineLimit(3)
                Text(T("Вернуть можно из Корзины, пока вы её не очистили.")).font(.caption).foregroundColor(.secondary)
                HStack {
                    Button(T("Нет, вернуться")) { model.pendingDelete = nil }
                    Button(T("Да, в Корзину")) { model.trash(d); model.pendingDelete = nil }.foregroundColor(.red)
                }
            }
            .padding(20)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }
}

final class DiskWindowController: NSObject, NSWindowDelegate {
    static let shared = DiskWindowController()
    private var window: NSWindow?

    /// Отдельное окно анализатора: «Пуск» его только запускает, дальше оно живёт само
    func show(store: Store) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = T("Анализатор диска")
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 440)
            w.contentView = NSHostingView(rootView: DiskWindowRoot(store: store, model: DiskModel.shared))
            w.delegate = self
            if !w.setFrameUsingName("DiskAnalyzerWindow") { w.center() }
            w.setFrameAutosaveName("DiskAnalyzerWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    @objc private func languageChanged() { window?.title = T("Анализатор диска") }

    func windowDidBecomeKey(_ notification: Notification) { DiskModel.shared.refresh() }
}

struct DiskWindowRoot: View {
    @ObservedObject var store: Store
    @ObservedObject var model: DiskModel
    var body: some View { DiskPanel(model: model, store: store).id(store.language) }
}

// MARK: - Форматирование флешек

enum FormatKind: String, CaseIterable, Identifiable {
    case fat32, fat16, exfat, hfs, apfs
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fat32: return "FAT32"
        case .fat16: return "FAT16"
        case .exfat: return "exFAT"
        case .hfs: return "Mac OS Extended (HFS+)"
        case .apfs: return "APFS"
        }
    }
    /// Имя формата для diskutil
    var personality: String {
        switch self {
        case .fat32: return "MS-DOS FAT32"
        case .fat16: return "MS-DOS FAT16"
        case .exfat: return "ExFAT"
        case .hfs: return "JHFS+"
        case .apfs: return "APFS"
        }
    }
    var isFAT: Bool { self == .fat32 || self == .fat16 }
    var maxName: Int {
        switch self {
        case .fat32, .fat16: return 11
        case .exfat: return 15
        default: return 27
        }
    }
    var supportsMBR: Bool { self != .apfs }
    var defaultScheme: String { (self == .hfs || self == .apfs) ? "GPT" : "MBR" }
    var maxSize: Int64? {
        switch self {
        case .fat16: return 4_294_967_296
        case .fat32: return 2_199_023_255_552
        default: return nil
        }
    }
    var note: String {
        switch self {
        case .fat32: return T("Самый совместимый: Windows, Mac, Linux, камеры, ТВ, магнитолы. Файлы до 4 ГБ.")
        case .fat16: return T("Для очень старых устройств. Объём до 4 ГБ, файлы до 2 ГБ.")
        case .exfat: return T("Для файлов больше 4 ГБ. Windows, Mac, современный Linux; старая техника может не понять.")
        case .hfs: return T("Только для Mac (журналируемая).")
        case .apfs: return T("Только для Mac, современная файловая система.")
        }
    }
}

struct FormatDrive: Identifiable {
    let id: String          // disk4
    let name: String
    let size: Int64
    let bus: String
    let volumes: [String]
}

final class FormatModel: ObservableObject {
    enum Stage { case pick, confirm, working, done }
    enum Tab { case format, speed }
    @Published var tab: Tab = .format
    let speed = SpeedModel()

    @Published var stage: Stage = .pick
    @Published var drives: [FormatDrive] = []
    @Published var loading = true
    @Published var selectedID: String?
    @Published var kind: FormatKind = .fat32 {
        didSet {
            if !kind.supportsMBR { scheme = "GPT" }
            else if oldValue.defaultScheme != kind.defaultScheme { scheme = kind.defaultScheme }
        }
    }
    @Published var scheme = "MBR"
    @Published var label = "USB"
    @Published var resultOK = false
    @Published var resultText = ""
    @Published var resultFS = ""
    @Published var ejectNote = ""
    private var observers: [NSObjectProtocol] = []
    private var lastDisk = ""

    init() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                guard let self = self, self.stage == .pick else { return }
                self.refresh()
            })
        }
    }

    deinit {
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    var selected: FormatDrive? { drives.first { $0.id == selectedID } }

    var cleanLabel: String {
        let t = label.trimmingCharacters(in: .whitespaces)
        let base = t.isEmpty ? "UNTITLED" : t
        return kind.isFAT ? base.uppercased() : base
    }

    var sizeProblem: String? {
        guard let d = selected, let m = kind.maxSize, d.size > m else { return nil }
        return kind == .fat16 ? T("Диск слишком велик для FAT16 (максимум 4 ГБ)") : T("Диск слишком велик для FAT32 (максимум 2 ТБ)")
    }

    var nameProblem: String? {
        let n = cleanLabel
        if n.count > kind.maxName { return Tf("Имя слишком длинное (максимум %@ символов)", "\(kind.maxName)") }
        let bad: Set<Character> = (kind == .hfs || kind == .apfs) ? ["/", ":"] : Set("*?.,;:/\\|+=<>[]\"")
        if n.contains(where: { bad.contains($0) }) || n.hasPrefix("-") { return T("В имени есть недопустимые символы") }
        return nil
    }

    var canFormat: Bool { selected != nil && sizeProblem == nil && nameProblem == nil && !speed.running }

    func refresh() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = FormatModel.loadDrives()
            DispatchQueue.main.async {
                self.drives = list
                self.loading = false
                if let s = self.selectedID, !list.contains(where: { $0.id == s }) { self.selectedID = nil }
                if self.selectedID == nil, list.count == 1 { self.selectedID = list[0].id }
            }
        }
    }

    // MARK: diskutil

    static func runTool(_ path: String, _ args: [String], mergeErrors: Bool, timeout: TimeInterval = 0) -> (Int32, Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = mergeErrors ? pipe : FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data()) }
        // зависший диск не должен подвесить операцию навсегда
        var killer: DispatchWorkItem?
        if timeout > 0 {
            let w = DispatchWorkItem { if p.isRunning { p.terminate() } }
            killer = w
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: w)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer?.cancel()
        return (p.terminationStatus, data)
    }

    static func plist(_ args: [String]) -> [String: Any]? {
        let (code, data) = runTool("/usr/sbin/diskutil", args, mergeErrors: false, timeout: 20)
        guard code == 0,
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return obj
    }

    static func wholeDisk(_ id: String) -> String {
        guard id.hasPrefix("disk") else { return id }
        return "disk" + String(id.dropFirst(4).prefix(while: { $0.isNumber }))
    }

    /// Только внешние физические диски; тот, с которого загружен Mac, не показываем никогда
    private static func loadDrives() -> [FormatDrive] {
        guard let list = plist(["list", "-plist", "external", "physical"]) else { return [] }
        var boot = Set<String>()
        if let root = plist(["info", "-plist", "/"]) {
            if let stores = root["APFSPhysicalStores"] as? [[String: Any]] {
                for st in stores { if let id = st["APFSPhysicalStore"] as? String { boot.insert(wholeDisk(id)) } }
            }
            if let pw = root["ParentWholeDisk"] as? String { boot.insert(pw) }
        }
        var out: [FormatDrive] = []
        for d in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            guard let id = d["DeviceIdentifier"] as? String, !boot.contains(id) else { continue }
            guard let info = plist(["info", "-plist", id]) else { continue }
            if (info["Internal"] as? Bool) == true { continue }
            let size = (info["TotalSize"] as? NSNumber)?.int64Value ?? (info["Size"] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else { continue }
            var name = (info["MediaName"] as? String) ?? ""
            if name.isEmpty { name = T("Внешний диск") }
            var vols: [String] = []
            for p in d["Partitions"] as? [[String: Any]] ?? [] {
                if let v = p["VolumeName"] as? String, !v.isEmpty { vols.append(v) }
            }
            out.append(FormatDrive(id: id, name: name, size: size, bus: (info["BusProtocol"] as? String) ?? "", volumes: vols))
        }
        return out
    }

    private static func resultFS(_ disk: String) -> String {
        guard let list = plist(["list", "-plist", disk]),
              let first = (list["AllDisksAndPartitions"] as? [[String: Any]])?.first else { return "" }
        for p in (first["Partitions"] as? [[String: Any]] ?? []).reversed() {
            if let id = p["DeviceIdentifier"] as? String, let n = p["VolumeName"] as? String, !n.isEmpty,
               let info = plist(["info", "-plist", id]) {
                return (info["FilesystemName"] as? String) ?? (info["FilesystemType"] as? String) ?? ""
            }
        }
        return ""
    }

    func run() {
        guard canFormat, let d = selected else { return }
        stage = .working
        let name = cleanLabel
        let scheme = self.scheme
        let kind = self.kind
        lastDisk = d.id
        let args = ["eraseDisk", kind.personality, name, scheme, d.id]
        DispatchQueue.global(qos: .userInitiated).async {
            // сначала размонтируем все тома диска; если они заняты — принудительно
            if FormatModel.runTool("/usr/sbin/diskutil", ["unmountDisk", d.id], mergeErrors: true, timeout: 25).0 != 0 {
                _ = FormatModel.runTool("/usr/sbin/diskutil", ["unmountDisk", "force", d.id], mergeErrors: true, timeout: 25)
            }
            var (code, data) = FormatModel.runTool("/usr/sbin/diskutil", args, mergeErrors: true, timeout: 900)
            var out = String(data: data, encoding: .utf8) ?? ""
            let low = out.lowercased()
            if code != 0 && (low.contains("privilege") || low.contains("authoriz") || low.contains("permission")) {
                let r = Admin.run(tool: "/usr/sbin/diskutil", args: args)
                if r.ok { out = r.output; code = r.detail.isEmpty ? 0 : 1 } else { out = r.detail; code = 1 }
            }
            let fs = code == 0 ? FormatModel.resultFS(d.id) : ""
            DispatchQueue.main.async {
                self.resultOK = code == 0
                self.resultFS = fs.isEmpty ? kind.title : fs
                let lines = out.split(separator: "\n").suffix(3).joined(separator: "\n")
                self.resultText = code == 0 ? Tf("Готово: «%@» отформатирована", name)
                    : (lines.isEmpty ? T("Диск не отвечает. Отключите его и подключите заново.")
                       : (out.contains("69888") || out.contains("unmount")
                          ? T("Не удалось размонтировать диск: он занят. Закройте программы, которые с ним работают, или отключите его и подключите заново.")
                          : String(lines.prefix(400))))
                self.ejectNote = ""
                self.stage = .done
            }
        }
    }

    func eject() {
        let id = lastDisk
        DispatchQueue.global(qos: .userInitiated).async {
            let (code, _) = FormatModel.runTool("/usr/sbin/diskutil", ["eject", id], mergeErrors: true, timeout: 30)
            DispatchQueue.main.async { self.ejectNote = code == 0 ? T("Можно вынимать") : T("Не удалось извлечь: диск занят") }
        }
    }

    func again() {
        stage = .pick
        refresh()
    }
}

final class SpeedModel: ObservableObject {
    enum Stage { case idle, writing, reading, done, failed }
    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let mbps: Double
        let mine: Bool
    }

    @Published var stage: Stage = .idle
    @Published var progress = 0.0
    @Published var liveMBps = 0.0
    @Published var writeMBps: Double?
    @Published var readMBps: Double?
    @Published var message = ""
    @Published var linkName = ""
    @Published var linkCeiling: Double?
    @Published var linkMbit: Double?
    @Published var sizeMB = 256
    @Published var phase = ""
    @Published var detecting = false

    private let lock = NSLock()
    private var cancelFlag = false
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelFlag }
    var running: Bool { stage == .writing || stage == .reading }

    /// Типичные скорости (последовательные, МБ/с): название, чтение, запись — приблизительные
    static var references: [(String, Double, Double)] {
        [(T("Флешка USB 2.0"), 35, 20),
         (T("Карта SD (UHS-I)"), 90, 60),
         (T("Недорогая флешка USB 3.0"), 100, 40),
         (T("Внешний жёсткий диск 2,5″"), 110, 100),
         (T("Внешний SSD (SATA, USB 3)"), 450, 400),
         (T("Внешний NVMe SSD, USB 3.2 Gen 2"), 900, 800),
         (T("Внешний NVMe SSD, Thunderbolt / USB4"), 2500, 2200)]
    }

    /// Строки для сравнения: чтение сравниваем с чтением, запись — с записью
    func rows(read: Bool) -> [Row] {
        var r = SpeedModel.references.map { Row(name: $0.0, mbps: read ? $0.1 : $0.2, mine: false) }
        if let v = read ? readMBps : writeMBps { r.append(Row(name: T("Ваш диск"), mbps: v, mine: true)) }
        return r.sorted { $0.mbps < $1.mbps }
    }

    func closest(read: Bool) -> String? {
        guard let x = read ? readMBps : writeMBps else { return nil }
        let refs = SpeedModel.references.sorted { ($0.1) < ($1.1) }.map { ($0.0, read ? $0.1 : $0.2) }.sorted { $0.1 < $1.1 }
        return (refs.last(where: { $0.1 <= x }) ?? refs.first)?.0
    }

    func reset() {
        guard !running else { return }
        stage = .idle
        writeMBps = nil
        readMBps = nil
        message = ""
        progress = 0
    }

    func cancel() { lock.lock(); cancelFlag = true; lock.unlock() }

    // MARK: подключение

    private static func walkSpeed(_ node: Any, _ inherited: String?, _ disk: String) -> String? {
        if let arr = node as? [Any] {
            for x in arr { if let r = walkSpeed(x, inherited, disk) { return r } }
            return nil
        }
        guard let d = node as? [String: Any] else { return nil }
        let own = (d["device_speed"] as? String) ?? (d["Speed"] as? String) ?? (d["speed"] as? String) ?? inherited
        if let b = d["bsd_name"] as? String, FormatModel.wholeDisk(b) == disk { return own ?? "" }
        for (_, v) in d where v is [Any] || v is [String: Any] {
            if let r = walkSpeed(v, own, disk) { return r }
        }
        return nil
    }

    /// Скорость подключения из системного профиля USB (JSON, затем текстовый вид)
    private static func usbSpeedString(for disk: String) -> String? {
        for type in ["SPUSBDataType", "SPUSBHostDataType"] {
            let (code, data) = FormatModel.runTool("/usr/sbin/system_profiler", [type, "-json"], mergeErrors: false, timeout: 40)
            if code == 0, let root = try? JSONSerialization.jsonObject(with: data),
               let r = walkSpeed(root, nil, disk), !r.isEmpty { return r }
        }
        let (code, data) = FormatModel.runTool("/usr/sbin/system_profiler", ["SPUSBDataType"], mergeErrors: false, timeout: 40)
        guard code == 0 else { return nil }
        let lines = (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("BSD Name:"),
                  FormatModel.wholeDisk(String(t.dropFirst(9)).trimmingCharacters(in: .whitespaces)) == disk else { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            var j = i - 1
            while j >= 0 {
                let l = lines[j]
                let ind = l.prefix(while: { $0 == " " }).count
                let lt = l.trimmingCharacters(in: .whitespaces)
                if ind < indent && lt.hasPrefix("Speed:") {
                    return String(lt.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                }
                j -= 1
            }
        }
        return nil
    }

    /// Название подключения, скорость линка (Мбит/с) и практический предел (МБ/с)
    private static func classify(_ raw: String) -> (String, Double, Double)? {
        let s = raw.lowercased()
        if s.contains("40 gb") || s.contains("thunderbolt") { return ("USB4 / Thunderbolt", 40000, 3000) }
        if s.contains("20 gb") { return ("USB 3.2 Gen 2×2", 20000, 1800) }
        if s.contains("10 gb") || s.contains("super_speed_plus") || s.contains("superspeed+") { return ("USB 3.1 Gen 2", 10000, 950) }
        if s.contains("5 gb") || s.contains("super_speed") || s.contains("superspeed") { return ("USB 3.0 (3.2 Gen 1)", 5000, 420) }
        if s.contains("480") || s.contains("high_speed") || s.contains("high speed") { return ("USB 2.0", 480, 38) }
        if s.contains("12 mb") || s.contains("full_speed") { return ("USB 1.1", 12, 1.1) }
        return nil
    }

    func detect(_ d: FormatDrive?) {
        linkName = ""
        linkCeiling = nil
        linkMbit = nil
        guard let d = d else { detecting = false; return }
        detecting = true
        let id = d.id
        DispatchQueue.global(qos: .utility).async {
            let raw = SpeedModel.usbSpeedString(for: id)
            let info = raw.flatMap { SpeedModel.classify($0) }
            DispatchQueue.main.async {
                self.detecting = false
                guard let (name, mbit, ceiling) = info else { return }
                let rate = mbit >= 1000 ? "\(Int(mbit / 1000)) " + T("Гбит/с") : "\(Int(mbit)) " + T("Мбит/с")
                self.linkName = name + " · " + rate
                self.linkCeiling = ceiling
                self.linkMbit = mbit
            }
        }
    }

    // MARK: тест

    /// Точка монтирования тома на этом диске: сначала по его собственным разделам, потом обходом томов (APFS)
    private static func mountPoint(of disk: String) -> String? {
        var best: String?
        if let list = FormatModel.plist(["list", "-plist", disk]),
           let first = (list["AllDisksAndPartitions"] as? [[String: Any]])?.first {
            for p in first["Partitions"] as? [[String: Any]] ?? [] {
                if let mp = p["MountPoint"] as? String, !mp.isEmpty {
                    if FileManager.default.isWritableFile(atPath: mp) { return mp }
                    if best == nil { best = mp }
                }
            }
            if best != nil { return best }
        }
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        for u in urls {
            var st = statfs()
            guard statfs(u.path, &st) == 0 else { continue }
            let from = withUnsafePointer(to: &st.f_mntfromname) { p in
                p.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard from.hasPrefix("/dev/") else { continue }
            let dev = String(from.dropFirst(5))
            if FormatModel.wholeDisk(dev) != disk {
                // том APFS живёт на синтезированном диске; физический диск указан в его описании
                guard let info = FormatModel.plist(["info", "-plist", dev]),
                      let stores = info["APFSPhysicalStores"] as? [[String: Any]] else { continue }
                let ids = stores.compactMap { ($0["APFSPhysicalStore"] as? String).map { FormatModel.wholeDisk($0) } }
                guard ids.contains(disk) else { continue }
            }
            if FileManager.default.isWritableFile(atPath: u.path) { return u.path }
            if best == nil { best = u.path }
        }
        return best
    }

    private func setPhase(_ text: String) {
        DispatchQueue.main.async { self.phase = text }
    }

    /// Каждая часть теста (запись, чтение) длится не дольше этого времени — медленная флешка не затянет тест
    private static let maxSeconds = 10.0
    /// Если за это время не записано ни байта, диск считаем не отвечающим
    private static let stallSeconds = 8.0

    /// Общее состояние между потоком ввода-вывода и контролёром (поток может зависнуть в системном вызове)
    private final class IOProbe {
        private let lock = NSLock()
        private var _done: Int64 = 0
        private var _finished = false
        private var _stop = false
        private var _abandoned = false
        private var _flushing = false
        private var _error: String?
        private var _start = 0.0
        private var _end = 0.0

        var done: Int64 { lock.lock(); defer { lock.unlock() }; return _done }
        var finished: Bool { lock.lock(); defer { lock.unlock() }; return _finished }
        var stopRequested: Bool { lock.lock(); defer { lock.unlock() }; return _stop }
        var abandoned: Bool { lock.lock(); defer { lock.unlock() }; return _abandoned }
        var flushing: Bool { lock.lock(); defer { lock.unlock() }; return _flushing }
        func setFlushing(_ v: Bool) { lock.lock(); _flushing = v; lock.unlock() }
        var error: String? { lock.lock(); defer { lock.unlock() }; return _error }
        func add(_ n: Int64) { lock.lock(); _done += n; lock.unlock() }
        func stop() { lock.lock(); _stop = true; lock.unlock() }
        func abandon() { lock.lock(); _stop = true; _abandoned = true; lock.unlock() }
        func fail(_ e: String) { lock.lock(); _error = e; lock.unlock() }
        func begin() { lock.lock(); _start = ProcessInfo.processInfo.systemUptime; lock.unlock() }
        func finish() { lock.lock(); _end = ProcessInfo.processInfo.systemUptime; _finished = true; lock.unlock() }
        func elapsed() -> Double {
            lock.lock(); defer { lock.unlock() }
            let e = _finished ? _end : ProcessInfo.processInfo.systemUptime
            return max(0.001, e - _start)
        }
    }

    private struct Outcome {
        var bytes: Int64
        var seconds: Double
        var stalled: Bool
        var cancelled: Bool
    }

    /// Последовательная запись всего файла мимо кэша системы, в конце сброс на носитель (F_FULLFSYNC).
    /// Время считается вместе со сбросом, поэтому буферы системы и самой флешки скорость не завышают.
    private static func writer(_ path: String, size: Int64, chunk: Int, data: [UInt8], probe: IOProbe) {
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else {
            probe.fail(String(cString: strerror(errno)))
            probe.finish()
            return
        }
        // пишем мимо кэша системы, чтобы файл не остался в памяти и чтение потом шло с самого диска
        _ = fcntl(fd, F_NOCACHE, 1)
        probe.begin()
        var done: Int64 = 0
        while done < size && !probe.stopRequested {
            let n = Int(min(Int64(chunk), size - done))
            let w = data.withUnsafeBytes { write(fd, $0.baseAddress, n) }
            if w <= 0 { probe.fail(String(cString: strerror(errno))); break }
            done += Int64(w)
            probe.add(Int64(w))
        }
        if !probe.abandoned && probe.error == nil {
            probe.setFlushing(true)
            _ = fcntl(fd, F_FULLFSYNC)
            probe.setFlushing(false)
        }
        close(fd)
        if probe.abandoned { unlink(path) }
        probe.finish()
    }

    private static func reader(_ path: String, size: Int64, chunk: Int, probe: IOProbe) {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else {
            probe.fail(String(cString: strerror(errno)))
            probe.finish()
            return
        }
        // читаем напрямую с устройства, минуя кэш системы (аналог purge перед чтением в dd)
        _ = fcntl(fd, F_NOCACHE, 1)
        var buf = [UInt8](repeating: 0, count: chunk)
        probe.begin()
        var got: Int64 = 0
        while got < size && !probe.stopRequested {
            let r = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, chunk) }
            if r < 0 { probe.fail(String(cString: strerror(errno))); break }
            if r == 0 { break }
            got += Int64(r)
            probe.add(Int64(r))
        }
        close(fd)
        probe.finish()
    }

    /// Следит за потоком ввода-вывода: обновляет экран, останавливает по времени, замечает зависание
    private func monitor(_ probe: IOProbe, size: Int64, base: Double, cap: Double?) -> Outcome {
        let t0 = ProcessInfo.processInfo.systemUptime
        var lastBytes: Int64 = 0
        var lastChange = t0
        var lastUI = t0
        var uiBytes: Int64 = 0
        var flushStart: Double?
        while true {
            usleep(100_000)
            let now = ProcessInfo.processInfo.systemUptime
            let b = probe.done
            if b != lastBytes { lastBytes = b; lastChange = now }
            if now - lastUI >= 0.25 {
                let live = Double(b - uiBytes) / 1_048_576 / (now - lastUI)
                let prog = base + max(Double(b) / Double(max(1, size)), cap.map { (now - t0) / $0 } ?? 0) * 0.5
                lastUI = now
                uiBytes = b
                DispatchQueue.main.async { self.liveMBps = live; self.progress = min(base + 0.5, prog) }
            }
            if probe.finished {
                return Outcome(bytes: probe.done, seconds: probe.elapsed(), stalled: false, cancelled: false)
            }
            if isCancelled {
                probe.abandon()
                return Outcome(bytes: probe.done, seconds: probe.elapsed(), stalled: false, cancelled: true)
            }
            // идёт сброс буфера диска на носитель — это не зависание, но ждём не бесконечно
            if probe.flushing {
                if flushStart == nil { flushStart = now }
                if now - (flushStart ?? now) > 900 {
                    probe.abandon()
                    return Outcome(bytes: probe.done, seconds: probe.elapsed(), stalled: true, cancelled: false)
                }
                lastChange = now
                continue
            }
            flushStart = nil
            if let cap = cap, now - t0 >= cap {
                probe.stop()
                let end = now + 4
                while !probe.finished && !probe.flushing && ProcessInfo.processInfo.systemUptime < end { usleep(50_000) }
                if probe.finished {
                    return Outcome(bytes: probe.done, seconds: probe.elapsed(), stalled: false, cancelled: false)
                }
                if probe.flushing { continue }
                probe.abandon()
                return Outcome(bytes: probe.done, seconds: probe.elapsed(), stalled: true, cancelled: false)
            }
            if now - lastChange >= SpeedModel.stallSeconds {
                probe.abandon()
                return Outcome(bytes: probe.done, seconds: probe.elapsed(), stalled: true, cancelled: false)
            }
        }
    }

    func start(_ d: FormatDrive) {
        guard !running else { return }
        lock.lock(); cancelFlag = false; lock.unlock()
        stage = .writing
        progress = 0
        liveMBps = 0
        writeMBps = nil
        readMBps = nil
        message = ""
        phase = T("Ищу том диска…")
        let want = Int64(sizeMB) * 1_048_576
        DispatchQueue.global(qos: .userInitiated).async {
            func fail(_ m: String) { DispatchQueue.main.async { self.message = m; self.stage = .failed; self.phase = "" } }
            func stopped() { DispatchQueue.main.async { self.message = T("Тест остановлен"); self.stage = .idle; self.phase = "" } }
            guard let vol = SpeedModel.mountPoint(of: d.id) else { fail(T("У диска нет подключённого тома — подключите его в Finder")); return }
            guard FileManager.default.isWritableFile(atPath: vol) else { fail(T("Том доступен только для чтения — тест записи невозможен")); return }
            self.setPhase(T("Проверяю свободное место…"))
            var sfs = statfs()
            var avail: Int64 = 0
            if statfs(vol, &sfs) == 0 { avail = Int64(sfs.f_bavail) * Int64(sfs.f_bsize) }
            let size = min(want, avail - 32 * 1_048_576)
            guard size >= 32 * 1_048_576 else { fail(T("Недостаточно свободного места для теста")); return }

            let base = vol + "/.pusk-speedtest-" + UUID().uuidString
            let path1 = base + "-a.tmp"
            let path2 = base + "-b.tmp"
            // удаляем временные файлы в отдельном потоке: если диск завис, тест от этого не зависнет
            func cleanup() { DispatchQueue.global(qos: .utility).async { unlink(path1); unlink(path2) } }

            let chunk = 2 * 1_048_576
            var data = [UInt8](repeating: 0, count: chunk)
            data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, chunk) }

            // --- запись
            self.setPhase(T("Идёт запись…"))
            let usedPath = path1
            let wProbe = IOProbe()
            Thread.detachNewThread { SpeedModel.writer(path1, size: size, chunk: chunk, data: data, probe: wProbe) }
            let wOut = self.monitor(wProbe, size: size, base: 0, cap: nil)
            if wOut.cancelled { cleanup(); stopped(); return }
            if wOut.bytes == 0 {
                cleanup()
                if let e = wProbe.error { fail(Tf("Ошибка во время теста: %@", e)) }
                else { fail(T("Диск не отвечает на запись. Возможно, он неисправен или защищён от записи.")) }
                return
            }
            let written = wOut.bytes
            let wSpeed = Double(written) / 1_048_576 / wOut.seconds
            DispatchQueue.main.async {
                self.writeMBps = wSpeed
                self.stage = .reading
                self.phase = T("Идёт чтение…")
                self.progress = 0.5
                self.liveMBps = 0
            }

            // --- чтение (в обход кэша)
            let rProbe = IOProbe()
            let readPath = usedPath
            Thread.detachNewThread { SpeedModel.reader(readPath, size: written, chunk: chunk, probe: rProbe) }
            let rOut = self.monitor(rProbe, size: written, base: 0.5, cap: SpeedModel.maxSeconds)
            cleanup()
            if rOut.cancelled { stopped(); return }
            if rOut.bytes == 0 {
                if let e = rProbe.error { fail(Tf("Ошибка во время теста: %@", e)) }
                else { fail(T("Диск не отвечает на чтение.")) }
                return
            }
            let rSpeed = Double(rOut.bytes) / 1_048_576 / rOut.seconds
            DispatchQueue.main.async {
                self.readMBps = rSpeed
                self.liveMBps = 0
                self.progress = 1
                self.phase = ""
                self.stage = .done
            }
        }
    }
}

struct SpeedPanel: View {
    @ObservedObject var model: FormatModel
    @ObservedObject var speed: SpeedModel
    let store: Store

    private func num(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "—" }

    private func stat(_ title: String, _ v: Double?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(num(v)).font(.system(size: 28, weight: .semibold))
            Text(T("МБ/с")).font(.caption).foregroundColor(.secondary)
        }
        .frame(minWidth: 90)
    }

    private func compare(_ title: String, read: Bool) -> some View {
        let rows = speed.rows(read: read)
        let maxV = max(1, rows.map { $0.mbps }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold()).padding(.top, 4)
            ForEach(rows) { r in
                HStack(spacing: 8) {
                    Text(r.name).font(.caption).fontWeight(r.mine ? .semibold : .regular)
                        .frame(width: 200, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(r.mine ? Color.accentColor : Color.gray.opacity(0.4))
                            .frame(width: max(2, g.size.width * CGFloat((r.mbps / maxV).squareRoot())), height: 10)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 12)
                    Text(num(r.mbps)).font(.caption).frame(width: 44, alignment: .trailing)
                }
            }
            if let name = speed.closest(read: read) {
                Text(Tf(read ? "По скорости чтения ближе всего к: %@" : "По скорости записи ближе всего к: %@", name))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if speed.detecting {
                Text(T("Определяю подключение…")).font(.caption).foregroundColor(.secondary)
            } else if speed.linkName.isEmpty {
                Text(model.selected.map { $0.bus.isEmpty ? T("Подключение определить не удалось") : Tf("Интерфейс: %@ (скорость подключения определить не удалось)", $0.bus) } ?? T("Подключение определить не удалось"))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text(Tf("Подключение: %@", speed.linkName)).font(.callout)
                if let c = speed.linkCeiling {
                    Text(Tf("Практический предел подключения ≈ %@ МБ/с", "\(Int(c))")).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack {
                Text(T("Объём теста")).font(.subheadline.bold())
                Picker("", selection: $speed.sizeMB) {
                    Text("64 " + T("МБ")).tag(64)
                    Text("256 " + T("МБ")).tag(256)
                    Text("512 " + T("МБ")).tag(512)
                    Text("1 " + T("ГБ")).tag(1024)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300).disabled(speed.running)
                Spacer()
            }
            if speed.running {
                ProgressView(value: speed.progress)
                Text(speed.phase + (speed.liveMBps > 0 ? " " + num(speed.liveMBps) + " " + T("МБ/с") : ""))
                    .font(.callout).foregroundColor(.secondary)
            }
            if !speed.message.isEmpty {
                Text(speed.message).font(.caption).foregroundColor(.orange)
            }
            if speed.writeMBps != nil || speed.readMBps != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 28) {
                            stat(T("Запись"), speed.writeMBps)
                            stat(T("Чтение"), speed.readMBps)
                            Spacer()
                        }
                        if speed.writeMBps != nil {
                            Text(T("Скорость записи у флешек может заметно колебаться — для точности повторите тест."))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Text(T("Сравнение с типичными устройствами (приблизительные значения)"))
                            .font(.caption).foregroundColor(.secondary)
                        if speed.readMBps != nil { compare(T("Чтение"), read: true) }
                        if speed.writeMBps != nil { compare(T("Запись"), read: false) }
                        if let c = speed.linkCeiling, let x = speed.readMBps {
                            Text(Tf("Это %@ практического предела подключения", "\(Int(min(999, x / c * 100)))%"))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if speed.linkMbit == 480 {
                            Text(T("Диск работает по USB 2.0. Если он умеет быстрее, проверьте кабель и порт."))
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                }
            } else {
                Text(T("Тест записывает и читает временный файл на диске (до выбранного объёма, но не дольше 10 секунд на каждую часть); файл удаляется."))
                    .font(.caption).foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            HStack {
                Spacer()
                Button(T("Закрыть")) { store.fmt = nil }
                if speed.running {
                    Button(T("Остановить")) { speed.cancel() }
                } else {
                    Button(T("Запустить тест")) { if let d = model.selected { speed.start(d) } }.disabled(model.selected == nil)
                }
            }
        }
    }
}

struct FormatOverlay: View {
    @ObservedObject var model: FormatModel
    let store: Store

    private func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    var body: some View {
        ZStack {
            ToolScrim()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 26)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T("Внешние диски")).font(.headline)
                        Text(model.tab == .speed
                             ? T("Измеряет последовательную скорость записи и чтения и сравнивает с типичными устройствами")
                             : T("Стирает диск и создаёт файловую систему, которую поймут любые устройства"))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                content
            }
            .frame(width: 540, height: 640)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
        .onChange(of: model.selectedID) { _ in
            model.speed.reset()
            model.speed.detect(model.selected)
        }
        .onChange(of: model.tab) { t in
            if t == .speed { model.speed.detect(model.selected) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .pick: pick
        case .confirm: confirm
        case .working:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(T("Форматирую… Не отключайте флешку.")).foregroundColor(.secondary)
                Spacer()
            }
        case .done: done
        }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("Диск")).font(.subheadline.bold())
                Spacer()
                Button(T("Обновить")) { model.refresh() }
            }
            Group {
                if model.loading && model.drives.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 90)
                } else if model.drives.isEmpty {
                    VStack(spacing: 4) {
                        Text(T("Нет подключённых внешних дисков")).foregroundColor(.secondary)
                        Text(T("Вставьте флешку и нажмите «Обновить»")).font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 90)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.drives) { d in
                                HStack(spacing: 10) {
                                    Image(systemName: model.selectedID == d.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(.accentColor)
                                    Image(systemName: "externaldrive").foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.name).lineLimit(1)
                                        Text(subtitle(d)).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .hoverHighlight(6)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selectedID = d.id }
                            }
                        }
                    }
                    .frame(height: 96)
                }
            }
            Picker("", selection: $model.tab) {
                Text(T("Форматирование")).tag(FormatModel.Tab.format)
                Text(T("Скорость")).tag(FormatModel.Tab.speed)
            }
            .pickerStyle(.segmented).labelsHidden()
            if model.tab == .speed {
                SpeedPanel(model: model, speed: model.speed, store: store)
            } else {
            Text(T("Формат")).font(.subheadline.bold())
            Picker("", selection: $model.kind) {
                ForEach(FormatKind.allCases) { k in
                    Text(k == .fat32 ? k.title + " — " + T("по умолчанию") : k.title).tag(k)
                }
            }
            .pickerStyle(.menu).labelsHidden()
            Text(model.kind.note).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.kind.supportsMBR {
                Text(T("Схема разделов")).font(.subheadline.bold())
                Picker("", selection: $model.scheme) {
                    Text("MBR").tag("MBR")
                    Text("GPT").tag("GPT")
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(model.scheme == "MBR"
                     ? T("MBR — максимальная совместимость: камеры, ТВ, магнитолы, Windows")
                     : T("GPT — современная схема, понимают только компьютеры"))
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(T("Имя")).font(.subheadline.bold())
            TextField("USB", text: $model.label).textFieldStyle(.roundedBorder)
            if let e = model.nameProblem ?? model.sizeProblem {
                Text(e).font(.caption).foregroundColor(.orange)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(T("Отмена")) { store.fmt = nil }
                Button(T("Стереть и отформатировать…")) { model.stage = .confirm }.disabled(!model.canFormat)
            }
            }
        }
        .padding(14)
    }

    private func subtitle(_ d: FormatDrive) -> String {
        var parts = [fmt(d.size)]
        if !d.bus.isEmpty { parts.append(d.bus) }
        parts.append(d.id)
        var s = parts.joined(separator: " · ")
        if !d.volumes.isEmpty { s += " · " + Tf("Тома: %@", d.volumes.joined(separator: ", ")) }
        return s
    }

    private var confirm: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 38)).foregroundColor(.orange)
            if let d = model.selected {
                Text(Tf("Стереть «%@»?", d.name)).font(.title3.bold()).multilineTextAlignment(.center)
                Text(Tf("Все данные на этом диске (%@) будут безвозвратно удалены.", fmt(d.size)))
                    .multilineTextAlignment(.center)
            }
            Text(Tf("Будет создано: %@, схема %@, имя «%@».", model.kind.title, model.kind.supportsMBR ? model.scheme : "GPT", model.cleanLabel))
                .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
            HStack {
                Button(T("Нет, вернуться")) { model.stage = .pick }
                Button(T("Да, стереть")) { model.run() }.foregroundColor(.red)
            }
            Spacer()
        }
        .padding(24)
    }

    private var done: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.resultOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 40)).foregroundColor(model.resultOK ? .green : .red)
            if model.resultOK {
                Text(model.resultText).font(.title3.bold()).multilineTextAlignment(.center)
                Text(Tf("Формат: %@", model.resultFS)).foregroundColor(.secondary)
                if !model.ejectNote.isEmpty { Text(model.ejectNote).font(.callout).foregroundColor(.secondary) }
            } else {
                Text(T("Не удалось отформатировать")).font(.title3.bold())
                Text(model.resultText).font(.caption).foregroundColor(.secondary).padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }
            HStack {
                if model.resultOK { Button(T("Извлечь")) { model.eject() } }
                Button(T("Ещё одну")) { model.again() }
                Button(T("Закрыть")) { store.fmt = nil }
            }
            .padding(.top, 6)
            Spacer()
        }
        .padding(20)
    }
}

// MARK: - Отдельные окна инструментов

private struct InToolWindowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inToolWindow: Bool {
        get { self[InToolWindowKey.self] }
        set { self[InToolWindowKey.self] = newValue }
    }
}

/// Затемнение под окном-карточкой: в «Пуске» оно нужно, в отдельном окне — нет
struct ToolScrim: View {
    @Environment(\.inToolWindow) private var inWindow
    var body: some View {
        if inWindow {
            Color.clear
        } else {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
        }
    }
}

enum ToolKind: String {
    case clean, big, maint, fmt

    var title: String {
        switch self {
        case .clean: return T("Очистка мусора")
        case .big: return T("Большие и старые файлы")
        case .maint: return T("Обслуживание")
        case .fmt: return T("Внешние диски")
        }
    }
    var size: NSSize {
        switch self {
        case .fmt: return NSSize(width: 540, height: 640)
        default: return NSSize(width: 560, height: 410)
        }
    }
}

struct ToolWindowRoot: View {
    @ObservedObject var store: Store
    let kind: ToolKind

    private var gone: Bool {
        switch kind {
        case .clean: return store.clean == nil
        case .big: return store.big == nil
        case .maint: return store.maint == nil
        case .fmt: return store.fmt == nil
        }
    }

    var body: some View {
        ZStack {
            switch kind {
            case .clean: if let m = store.clean { CleanOverlay(model: m, store: store) }
            case .big: if let m = store.big { BigFilesOverlay(model: m, store: store) }
            case .maint: if let m = store.maint { MaintenanceOverlay(model: m, store: store) }
            case .fmt: if let m = store.fmt { FormatOverlay(model: m, store: store) }
            }
            if let pr = store.pwRequest, store.pwTool == kind { PasswordOverlay(request: pr, store: store) }
        }
        .environment(\.inToolWindow, true)
        .frame(width: kind.size.width, height: kind.size.height)
        .id(store.language)
        .onChange(of: gone) { isGone in
            if isGone { ToolWindows.shared.close(kind) }
        }
    }
}

/// Инструменты открываются в своих окнах: «Пуск» их только запускает, дальше они живут независимо
final class ToolWindows: NSObject, NSWindowDelegate {
    static let shared = ToolWindows()
    private var windows: [ToolKind: NSWindow] = [:]
    private weak var store: Store?
    private var observing = false

    func show(_ kind: ToolKind, store: Store) {
        self.store = store
        let w: NSWindow
        if let existing = windows[kind] {
            w = existing
        } else {
            w = NSWindow(contentRect: NSRect(origin: .zero, size: kind.size),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ToolWindowRoot(store: store, kind: kind))
            w.setContentSize(kind.size)
            w.delegate = self
            w.center()
            windows[kind] = w
            if !observing {
                observing = true
                NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
            }
        }
        w.title = kind.title
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close(_ kind: ToolKind) { windows[kind]?.close() }

    func keyKind() -> ToolKind? {
        guard let kw = NSApp.keyWindow else { return nil }
        return windows.first { $0.value === kw }?.key
    }

    /// Esc закрывает окно инструмента, если оно ничего не делает прямо сейчас
    func handleEscape(_ w: NSWindow) -> Bool {
        guard let kind = windows.first(where: { $0.value === w })?.key, let st = store else { return false }
        if st.pwRequest != nil { return false }
        if isBusy(kind, st) { return true }
        w.close()
        return true
    }

    private func isBusy(_ kind: ToolKind, _ st: Store) -> Bool {
        switch kind {
        case .clean: return st.clean?.stage == .working
        case .big: return st.big?.stage == .working
        case .maint: return st.maint?.running == true
        case .fmt: return st.fmt?.stage == .working || st.fmt?.speed.running == true
        }
    }

    @objc private func languageChanged() {
        for (k, w) in windows { w.title = k.title }
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow,
              let kind = windows.first(where: { $0.value === w })?.key, let st = store else { return }
        if isBusy(kind, st) { return }   // операция продолжается; окно можно открыть снова
        switch kind {
        case .clean: st.clean = nil
        case .big: st.big = nil
        case .maint: st.maint = nil
        case .fmt: st.fmt = nil
        }
    }
}

// MARK: - Закрыть все программы

final class QuitAllModel: ObservableObject {
    struct Item: Identifiable {
        let app: NSRunningApplication
        let name: String
        let icon: NSImage
        var selected: Bool
        var id: pid_t { app.processIdentifier }
    }
    enum Stage { case review, working, done }

    private static let keepKey = "quitAll.keep"   // программы, которые пользователь снял с закрытия

    @Published var stage: Stage = .review
    @Published var items: [Item] = []
    @Published var closedCount = 0
    @Published var remaining: [String] = []

    var selectedCount: Int { items.filter { $0.selected }.count }

    init() {
        let keep = Set(UserDefaults.standard.stringArray(forKey: QuitAllModel.keepKey) ?? [])
        let me = Bundle.main.bundleIdentifier
        items = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated
                && $0.bundleIdentifier != me && $0.bundleIdentifier != "com.apple.finder" }
            .map { a in
                Item(app: a, name: a.localizedName ?? a.bundleIdentifier ?? "?",
                     icon: a.icon ?? NSImage(), selected: !keep.contains(a.bundleIdentifier ?? ""))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Вежливо просит выбранные программы завершиться: если есть несохранённое, они сами спросят
    func run() {
        let chosen = items.filter { $0.selected }
        guard !chosen.isEmpty else { return }
        var keep = Set(UserDefaults.standard.stringArray(forKey: QuitAllModel.keepKey) ?? [])
        for it in items {
            guard let bid = it.app.bundleIdentifier else { continue }
            if it.selected { keep.remove(bid) } else { keep.insert(bid) }
        }
        UserDefaults.standard.set(Array(keep), forKey: QuitAllModel.keepKey)
        stage = .working
        for it in chosen { it.app.terminate() }
        DispatchQueue.global(qos: .userInitiated).async {
            var waited = 0
            while waited < 50 && chosen.contains(where: { !$0.app.isTerminated }) {
                usleep(100_000); waited += 1
            }
            DispatchQueue.main.async {
                self.remaining = chosen.filter { !$0.app.isTerminated }.map { $0.name }
                self.closedCount = chosen.count - self.remaining.count
                self.stage = .done
            }
        }
    }
}

struct QuitAllOverlay: View {
    @ObservedObject var model: QuitAllModel
    let store: Store

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T("Закрыть все программы")).font(.headline)
                        Text(T("Если в программе есть несохранённые данные, она сама спросит, что делать"))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                content
            }
            .frame(width: 460, height: 440)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .review:
            if model.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text(T("Других запущенных программ нет")).foregroundColor(.secondary)
                    Button(T("Закрыть")) { store.quitAll = nil }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($model.items) { $it in
                            HStack(spacing: 10) {
                                Toggle("", isOn: $it.selected).labelsHidden().toggleStyle(.checkbox)
                                Image(nsImage: it.icon).resizable().frame(width: 24, height: 24)
                                Text(it.name).lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 5).padding(.horizontal, 6)
                            .hoverHighlight(6)
                            .contentShape(Rectangle())
                            .onTapGesture { it.selected.toggle() }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
                Divider()
                HStack {
                    Text(Tf("Будет закрыто: %@", "\(model.selectedCount)")).font(.callout).foregroundColor(.secondary)
                    Spacer()
                    Button(T("Отмена")) { store.quitAll = nil }
                    Button(T("Закрыть программы")) { model.run() }.disabled(model.selectedCount == 0)
                }
                .padding(12)
            }
        case .working:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(T("Закрываю…")).foregroundColor(.secondary)
                Spacer()
            }
        case .done:
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: model.remaining.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(model.remaining.isEmpty ? .green : .orange)
                Text(Tf("Закрыто: %@", "\(model.closedCount)")).font(.title3.bold())
                if !model.remaining.isEmpty {
                    Text(T("Эти программы ждут вашего ответа (например, сохранить документ):"))
                        .font(.callout).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Text(model.remaining.joined(separator: ", "))
                        .font(.callout).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                Spacer()
                HStack { Spacer(); Button(T("Закрыть")) { store.quitAll = nil } }.padding(12)
            }
        }
    }
}

struct MaintenanceOverlay: View {
    @ObservedObject var model: MaintModel
    let store: Store

    var body: some View {
        ZStack {
            ToolScrim()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 26)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T("Обслуживание")).font(.headline)
                        Text(T("Отметьте нужные задачи — каждая выполняется отдельно")).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($model.tasks) { $t in row($t); Divider() }
                    }
                    .padding(.horizontal, 14)
                }
                Divider()
                HStack {
                    Text(model.running ? model.note : Tf("Выбрано: %@", "\(model.selectedCount)"))
                        .font(.callout).foregroundColor(.secondary)
                    Spacer()
                    Button(T("Закрыть")) { store.maint = nil }.disabled(model.running)
                    Button(T("Выполнить")) { store.runMaint(model) }
                        .disabled(model.running || model.selectedCount == 0)
                }
                .padding(12)
            }
            .frame(width: 560, height: 410)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }

    private func row(_ t: Binding<MaintTask>) -> some View {
        let task = t.wrappedValue
        return HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: t.selected).labelsHidden().toggleStyle(.checkbox).disabled(model.running)
            Image(systemName: task.symbol).frame(width: 24).foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title).font(.system(size: 13, weight: .medium))
                    if task.needsAdmin {
                        Image(systemName: "lock").font(.caption).foregroundColor(.secondary)
                            .help(T("Потребуется пароль администратора"))
                    }
                }
                Text(task.info).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                switch task.status {
                case .ok(let m): Text(m).font(.caption).foregroundColor(.green)
                case .failed(let m): Text(m).font(.caption).foregroundColor(.orange)
                default: EmptyView()
                }
            }
            Spacer(minLength: 8)
            switch task.status {
            case .running: ProgressView().controlSize(.small)
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
            case .idle: EmptyView()
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .hoverHighlight(6)
        .contentShape(Rectangle())
        .onTapGesture { if !model.running { t.wrappedValue.selected.toggle() } }
    }
}

// MARK: - Большие и старые файлы

struct BigFile: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let date: Date          // когда последний раз открывали или меняли
    var selected = false
}

final class BigFilesModel: ObservableObject {
    enum Stage { case scanning, review, confirm, working, done }
    @Published var stage: Stage = .scanning
    @Published var items: [BigFile] = []
    @Published var scanText = ""
    @Published var minMB = 100
    @Published var ageDays = 0
    @Published var sortBySize = true
    @Published var trashedCount = 0
    @Published var trashedSize: Int64 = 0
    @Published var failed: [String] = []

    static var sizeOptions: [(String, Int)] { [(T("100 МБ"), 100), (T("500 МБ"), 500), (T("1 ГБ"), 1024), (T("5 ГБ"), 5120)] }
    static var ageOptions: [(String, Int)] { [(T("любое время"), 0), (T("3 месяца"), 90), (T("6 месяцев"), 180), (T("1 год"), 365)] }

    var visible: [BigFile] {
        let minBytes = Int64(minMB) * 1_048_576
        let cutoff: Date? = ageDays > 0 ? Date().addingTimeInterval(-Double(ageDays) * 86_400) : nil
        var r = items.filter { f in
            f.size >= minBytes && (cutoff == nil || f.date < cutoff!)
        }
        if !sortBySize { r.sort { $0.date < $1.date } }
        return r
    }
    var selectedVisible: [BigFile] { visible.filter { $0.selected } }
    var selectedSize: Int64 { selectedVisible.reduce(0) { $0 + $1.size } }

    func setSelected(_ id: UUID, _ on: Bool) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].selected = on }
    }
}

enum BigFiles {
    /// Ищем в домашней папке (кроме Библиотеки) файлы от 50 МБ; фильтры по размеру и возрасту применяются потом
    static func scan(progress: @escaping (String) -> Void) -> [BigFile] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let en = fm.enumerator(at: home, includingPropertiesForKeys: keys,
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                     errorHandler: { _, _ in true }) else { return [] }
        let minSize: Int64 = 50 * 1_048_576
        var out: [BigFile] = []
        var counter = 0
        for case let u as URL in en {
            let name = u.lastPathComponent
            if (name == "Library" && u.deletingLastPathComponent().path == home.path) || name == "node_modules" {
                en.skipDescendants()
                continue
            }
            counter += 1
            if counter % 1500 == 0 { progress(u.deletingLastPathComponent().path.replacingOccurrences(of: home.path, with: "~")) }
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            let date = [v.contentAccessDate, v.contentModificationDate].compactMap { $0 }.max() ?? .distantPast
            if v.isPackage == true {
                if u.pathExtension.lowercased() == "app" { continue }
                let size = Uninstaller.size(of: u)
                if size >= minSize { out.append(BigFile(url: u, size: size, date: date)) }
                continue
            }
            guard v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            if size >= minSize { out.append(BigFile(url: u, size: size, date: date)) }
        }
        out.sort { $0.size > $1.size }
        return Array(out.prefix(1000))
    }
}

struct BigFilesOverlay: View {
    @ObservedObject var model: BigFilesModel
    let store: Store

    private func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    private func shortDir(_ u: URL) -> String {
        u.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        ZStack {
            ToolScrim()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "archivebox").font(.system(size: 26)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T("Большие и старые файлы")).font(.headline)
                        Text(T("Домашняя папка, кроме Библиотеки")).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                content
            }
            .frame(width: 560, height: 410)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .scanning:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(T("Ищу большие файлы…")).foregroundColor(.secondary)
                Text(model.scanText).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 24)
                Spacer()
                HStack { Spacer(); Button(T("Отмена")) { store.big = nil } }.padding(12)
            }
        case .review: review
        case .confirm: confirm
        case .working:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(T("Перемещаю в Корзину…")).foregroundColor(.secondary)
                Spacer()
            }
        case .done: done
        }
    }

    private var filters: some View {
        HStack(spacing: 6) {
            Text(T("Размер от")).font(.caption).foregroundColor(.secondary)
            Picker("", selection: $model.minMB) {
                ForEach(BigFilesModel.sizeOptions, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
            Text(T("Не открывались")).font(.caption).foregroundColor(.secondary)
            Picker("", selection: $model.ageDays) {
                ForEach(BigFilesModel.ageOptions, id: \.1) { Text($0.0).tag($0.1) }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
            Spacer()
            Picker("", selection: $model.sortBySize) {
                Text(T("По размеру")).tag(true)
                Text(T("Сначала старые")).tag(false)
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var review: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            let list = model.visible
            if list.isEmpty {
                Spacer()
                Text(T("Ничего не найдено по этим условиям")).foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list) { f in row(f); Divider() }
                    }
                    .padding(.horizontal, 14)
                }
            }
            Divider()
            HStack {
                Text(Tf("Выбрано: %@ · %@", "\(model.selectedVisible.count)", "\(fmt(model.selectedSize))")).font(.callout)
                Spacer()
                Button(T("Закрыть")) { store.big = nil }
                Button(T("В Корзину…")) { model.stage = .confirm }.disabled(model.selectedVisible.isEmpty)
            }
            .padding(12)
        }
    }

    private func row(_ f: BigFile) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { f.selected }, set: { model.setSelected(f.id, $0) }))
                .labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(shortDir(f.url)).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(fmt(f.size)).font(.callout)
                Text(f.date, style: .date).font(.caption).foregroundColor(.secondary)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([f.url])
            } label: {
                Image(systemName: "magnifyingglass.circle").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(T("Показать в Finder"))
        }
        .padding(.vertical, 6).padding(.horizontal, 6)
        .hoverHighlight(6)
        .contentShape(Rectangle())
        .onTapGesture { model.setSelected(f.id, !f.selected) }
    }

    private var confirm: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundColor(.orange)
            Text(T("Вы уверены?")).font(.title3.bold())
            Text(Tf("В Корзину будет перемещено файлов: %@ (%@).\nВернуть их можно из Корзины, пока вы её не очистили.", "\(model.selectedVisible.count)", "\(fmt(model.selectedSize))"))
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 24)
            Spacer()
            HStack {
                Button(T("Нет, вернуться")) { model.stage = .review }
                Button(T("Да, в Корзину")) { store.performBig(model) }.foregroundColor(.red)
            }
            .padding(.bottom, 16)
        }
    }

    private var done: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(model.failed.isEmpty ? .green : .orange)
            Text(Tf("Перемещено в Корзину: %@ (%@)", "\(model.trashedCount)", "\(fmt(model.trashedSize))")).font(.title3.bold())
            if !model.failed.isEmpty {
                Text(Tf("Не удалось переместить (%@):", "\(model.failed.count)")).font(.caption).foregroundColor(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.failed, id: \.self) { p in
                            Text(p.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxHeight: 80)
            }
            Spacer()
            Button(T("Закрыть")) { store.big = nil }.padding(.bottom, 16)
        }
    }
}

// MARK: - Интерфейс

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Зона, за которую можно перетаскивать окно без рамки
struct DragArea: NSViewRepresentable {
    final class V: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) {}
}

/// Полоса сверху окна с «ручкой»: за неё окно двигается
struct DragBar: View {
    var body: some View {
        ZStack {
            DragArea()
            Capsule().fill(Color.secondary.opacity(0.45))
                .frame(width: 44, height: 4)
                .allowsHitTesting(false)
        }
        .frame(height: 22)
        .help(T("Потяните, чтобы переместить окно"))
    }
}

/// Подсветка строки или значка при наведении мыши (как у значков приложений)
struct HoverHighlight: ViewModifier {
    var radius: CGFloat
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .background(RoundedRectangle(cornerRadius: radius)
                .fill(hover ? Color.primary.opacity(0.12) : Color.clear))
    }
}

extension View {
    func hoverHighlight(_ radius: CGFloat = 7) -> some View { modifier(HoverHighlight(radius: radius)) }
}

struct ToolRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundColor(.accentColor)
            Text(title)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.accentColor.opacity(0.25) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action() }
    }
}

// MARK: - Быстрый ответ в поиске: калькулятор, единицы измерения, валюты

struct QuickItem {
    let expr: String      // что распознано
    let result: String    // как показать
    let copy: String      // что попадёт в буфер обмена
    var note: String? = nil
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

/// Безопасный разбор арифметики (без NSExpression, который падает на неверном вводе)
private struct MathParser {
    let chars: [Character]
    var i = 0
    var sawOp = false
    var failed = false

    init(_ s: String) { chars = Array(s) }

    private func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

    mutating func skipSpaces() { while i < chars.count, chars[i] == " " { i += 1 } }

    mutating func expression() -> Double {
        var v = term().0
        while true {
            skipSpaces()
            guard i < chars.count, chars[i] == "+" || chars[i] == "-" else { break }
            let op = chars[i]
            i += 1
            sawOp = true
            let (r0, pct) = term()
            let r = pct ? v * r0 : r0          // «8400 + 15%» — процент от 8400
            v = (op == "+") ? v + r : v - r
        }
        return v
    }

    mutating func term() -> (Double, Bool) {
        var (v, pct) = power()
        while true {
            skipSpaces()
            guard i < chars.count else { break }
            let c = chars[i]
            if c == "*" || c == "×" || c == "/" || c == "÷" {
                i += 1
                sawOp = true
                let (r, _) = power()
                if c == "/" || c == "÷" {
                    if r == 0 { failed = true; return (0, false) }
                    v /= r
                } else { v *= r }
                pct = false
            } else { break }
        }
        return (v, pct)
    }

    mutating func power() -> (Double, Bool) {
        let (b, pct) = unary()
        skipSpaces()
        if i < chars.count, chars[i] == "^" || (chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "*") {
            i += (chars[i] == "^") ? 1 : 2
            sawOp = true
            let (e, _) = power()
            return (pow(b, e), false)
        }
        return (b, pct)
    }

    mutating func unary() -> (Double, Bool) {
        skipSpaces()
        if i < chars.count, chars[i] == "-" { i += 1; let (v, p) = unary(); return (-v, p) }
        if i < chars.count, chars[i] == "+" { i += 1; return unary() }
        return primary()
    }

    mutating func primary() -> (Double, Bool) {
        skipSpaces()
        guard i < chars.count else { failed = true; return (0, false) }
        var v = 0.0
        let c = chars[i]
        if c == "(" {
            i += 1
            v = expression()
            skipSpaces()
            if i < chars.count, chars[i] == ")" { i += 1 } else { failed = true }
        } else if isDigit(c) || c == "." || c == "," {
            v = number()
        } else if c == "π" {
            i += 1
            v = Double.pi
        } else if c.isLetter {
            var w = ""
            while i < chars.count, chars[i].isLetter { w.append(chars[i]); i += 1 }
            switch w.lowercased() {
            case "pi":
                v = Double.pi
            case "sqrt", "корень":
                sawOp = true
                skipSpaces()
                guard i < chars.count, chars[i] == "(" else { failed = true; return (0, false) }
                i += 1
                let x = expression()
                skipSpaces()
                if i < chars.count, chars[i] == ")" { i += 1 } else { failed = true }
                if x < 0 { failed = true }
                v = x.squareRoot()
            default:
                failed = true
                return (0, false)
            }
        } else {
            failed = true
            return (0, false)
        }
        skipSpaces()
        if i < chars.count, chars[i] == "%" { i += 1; sawOp = true; return (v / 100, true) }
        return (v, false)
    }

    mutating func number() -> Double {
        var s = ""
        var sep = false
        while i < chars.count {
            let c = chars[i]
            if isDigit(c) {
                s.append(c)
                i += 1
            } else if (c == "." || c == ",") && !sep, i + 1 < chars.count, isDigit(chars[i + 1]) {
                s.append(".")
                sep = true
                i += 1
            } else { break }
        }
        guard let d = Double(s) else { failed = true; return 0 }
        return d
    }
}

enum QuickUnits {
    static let table: [String: Dimension] = {
        var t: [String: Dimension] = [:]
        func add(_ u: Dimension, _ names: [String]) { for n in names { t[n] = u } }
        // длина
        add(UnitLength.millimeters, ["мм", "mm", "миллиметр", "миллиметра", "миллиметров", "millimeter", "millimeters"])
        add(UnitLength.centimeters, ["см", "cm", "сантиметр", "сантиметра", "сантиметров", "centimeter", "centimeters"])
        add(UnitLength.meters, ["м", "m", "метр", "метра", "метров", "meter", "meters", "metre", "metres"])
        add(UnitLength.kilometers, ["км", "km", "километр", "километра", "километров", "kilometer", "kilometers"])
        add(UnitLength.inches, ["дюйм", "дюйма", "дюймов", "in", "inch", "inches"])
        add(UnitLength.feet, ["фут", "фута", "футов", "ft", "foot", "feet"])
        add(UnitLength.yards, ["ярд", "ярда", "ярдов", "yd", "yard", "yards"])
        add(UnitLength.miles, ["миля", "мили", "миль", "mi", "mile", "miles"])
        // масса
        add(UnitMass.milligrams, ["мг", "mg", "миллиграмм", "миллиграмма", "миллиграммов"])
        add(UnitMass.grams, ["г", "гр", "грамм", "грамма", "граммов", "g", "gram", "grams"])
        add(UnitMass.kilograms, ["кг", "kg", "килограмм", "килограмма", "килограммов", "kilogram", "kilograms"])
        add(UnitMass.metricTons, ["т", "тонна", "тонны", "тонн", "ton", "tons", "tonne", "tonnes"])
        add(UnitMass.pounds, ["фунт", "фунта", "фунтов", "lb", "lbs", "pound", "pounds"])
        add(UnitMass.ounces, ["унция", "унции", "унций", "oz", "ounce", "ounces"])
        // объём
        add(UnitVolume.milliliters, ["мл", "ml", "миллилитр", "миллилитра", "миллилитров"])
        add(UnitVolume.liters, ["л", "литр", "литра", "литров", "l", "liter", "liters", "litre", "litres"])
        add(UnitVolume.gallons, ["галлон", "галлона", "галлонов", "gal", "gallon", "gallons"])
        add(UnitVolume.pints, ["пинта", "пинты", "пинт", "pint", "pints"])
        // температура
        add(UnitTemperature.celsius, ["°c", "°с", "c", "цельсий", "цельсия", "градус цельсия", "градусов цельсия", "градуса цельсия"])
        add(UnitTemperature.fahrenheit, ["°f", "°ф", "f", "фаренгейт", "фаренгейта", "градус фаренгейта", "градусов фаренгейта", "градуса фаренгейта"])
        add(UnitTemperature.kelvin, ["k", "кельвин", "кельвина", "кельвинов"])
        // скорость
        add(UnitSpeed.kilometersPerHour, ["км/ч", "km/h", "kmh", "kph"])
        add(UnitSpeed.metersPerSecond, ["м/с", "m/s"])
        add(UnitSpeed.milesPerHour, ["миль/ч", "mph"])
        add(UnitSpeed.knots, ["узел", "узла", "узлов", "kn", "knot", "knots"])
        // время
        add(UnitDuration.seconds, ["с", "сек", "секунда", "секунды", "секунд", "s", "sec", "second", "seconds"])
        add(UnitDuration.minutes, ["мин", "минута", "минуты", "минут", "min", "minute", "minutes"])
        add(UnitDuration.hours, ["ч", "час", "часа", "часов", "h", "hr", "hour", "hours"])
        add(UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86400)),
            ["сут", "сутки", "суток", "день", "дня", "дней", "d", "day", "days"])
        add(UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604800)),
            ["нед", "неделя", "недели", "недель", "week", "weeks"])
        // данные
        add(UnitInformationStorage.bytes, ["байт", "байта", "байтов", "byte", "bytes"])
        add(UnitInformationStorage.kilobytes, ["кб", "kb", "килобайт", "килобайта", "килобайтов"])
        add(UnitInformationStorage.megabytes, ["мб", "mb", "мегабайт", "мегабайта", "мегабайтов"])
        add(UnitInformationStorage.gigabytes, ["гб", "gb", "гигабайт", "гигабайта", "гигабайтов"])
        add(UnitInformationStorage.terabytes, ["тб", "tb", "терабайт", "терабайта", "терабайтов"])
        add(UnitInformationStorage.kibibytes, ["kib", "кибибайт"])
        add(UnitInformationStorage.mebibytes, ["mib", "мебибайт"])
        add(UnitInformationStorage.gibibytes, ["gib", "гибибайт"])
        // площадь
        add(UnitArea.squareMeters, ["м2", "м²", "m2", "m²", "кв.м", "кв м"])
        add(UnitArea.squareKilometers, ["км2", "км²", "km2", "km²"])
        add(UnitArea.hectares, ["га", "гектар", "гектара", "гектаров", "ha", "hectare", "hectares"])
        add(UnitArea.acres, ["акр", "акра", "акров", "acre", "acres"])
        return t
    }()

    static func convert(_ v: Double, from: Dimension, to: Dimension) -> Double? {
        guard type(of: from) == type(of: to) else { return nil }
        let base = from.converter.baseUnitValue(fromValue: v)
        return to.converter.value(fromBaseUnitValue: base)
    }
}

/// Курсы валют: свежие берём из интернета (не чаще раза в час), без связи — последние сохранённые
final class Rates {
    static let shared = Rates()
    private(set) var rates: [String: Double] = [:]     // единиц валюты за 1 USD
    private(set) var date: Date?
    private var fetching = false
    private var waiters: [(Bool, Bool) -> Void] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: "pusk.rates"),
           let r = try? JSONDecoder().decode([String: Double].self, from: d) {
            rates = r
            date = UserDefaults.standard.object(forKey: "pusk.rates.date") as? Date
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(rates) { UserDefaults.standard.set(d, forKey: "pusk.rates") }
        UserDefaults.standard.set(date, forKey: "pusk.rates.date")
    }

    /// done(есть ли курсы, свежие ли они) вызывается на главном потоке
    func ensure(_ done: @escaping (Bool, Bool) -> Void) {
        if !rates.isEmpty, let d = date, Date().timeIntervalSince(d) < 3600 { done(true, true); return }
        waiters.append(done)
        if fetching { return }
        fetching = true
        fetch { newRates, newDate in
            DispatchQueue.main.async {
                self.fetching = false
                var fresh = false
                if let r = newRates, !r.isEmpty {
                    self.rates = r
                    self.date = newDate ?? Date()
                    self.save()
                    fresh = true
                }
                let has = !self.rates.isEmpty
                let ws = self.waiters
                self.waiters = []
                ws.forEach { $0(has, fresh) }
            }
        }
    }

    private func fetch(_ done: @escaping ([String: Double]?, Date?) -> Void) {
        func get(_ url: String, _ cb: @escaping (Data?) -> Void) {
            guard let u = URL(string: url) else { cb(nil); return }
            var req = URLRequest(url: u)
            req.timeoutInterval = 6
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                if let h = resp as? HTTPURLResponse, h.statusCode == 200 { cb(data) } else { cb(nil) }
            }.resume()
        }
        get("https://open.er-api.com/v6/latest/USD") { data in
            if let data = data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (j["result"] as? String) == "success",
               let r = j["rates"] as? [String: Any] {
                var out: [String: Double] = [:]
                for (k, v) in r { if let d = (v as? NSNumber)?.doubleValue, d > 0 { out[k] = d } }
                var date: Date? = nil
                if let t = (j["time_last_update_unix"] as? NSNumber)?.doubleValue { date = Date(timeIntervalSince1970: t) }
                if !out.isEmpty { done(out, date); return }
            }
            // запасной источник — Банк России (курсы к рублю)
            get("https://www.cbr-xml-daily.ru/daily_json.js") { data in
                guard let data = data,
                      let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let vals = j["Valute"] as? [String: Any] else { done(nil, nil); return }
                var rubPer: [String: Double] = ["RUB": 1]
                for (k, v) in vals {
                    if let o = v as? [String: Any],
                       let val = (o["Value"] as? NSNumber)?.doubleValue,
                       let nom = (o["Nominal"] as? NSNumber)?.doubleValue, nom > 0 { rubPer[k] = val / nom }
                }
                guard let usd = rubPer["USD"], usd > 0 else { done(nil, nil); return }
                var out: [String: Double] = [:]
                for (k, v) in rubPer where v > 0 { out[k] = usd / v }
                done(out, nil)
            }
        }
    }
}

struct CurrencyRequest {
    let value: Double
    let from: String
    let to: String
}

enum QuickCalc {
    // MARK: форматирование

    static func format(_ v: Double, maxFrac: Int, minFrac: Int = 0, grouping: Bool = true) -> String {
        if v == 0 { return "0" }
        if abs(v) >= 1e15 || abs(v) < 1e-9 { return String(format: "%.6g", v) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.current
        f.usesGroupingSeparator = grouping
        f.maximumFractionDigits = maxFrac
        f.minimumFractionDigits = minFrac
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private static func unitFrac(_ v: Double) -> Int { abs(v) >= 1000 ? 2 : (abs(v) >= 1 ? 4 : 6) }

    // MARK: разбор

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
    }

    private static func token(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespaces)
        while t.hasSuffix(".") { t.removeLast() }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }

    private static func calc(_ s: String, needOp: Bool) -> Double? {
        var p = MathParser(s)
        let v = p.expression()
        p.skipSpaces()
        guard !p.failed, p.i == p.chars.count, v.isFinite, !needOp || p.sawOp else { return nil }
        return v
    }

    private static let num = "([-+]?(?:\\d[\\d ]*(?:[.,]\\d+)?|[.,]\\d+))"

    /// «100 usd в rub» → (100, "usd", "rub"); «100 usd» → (100, "usd", nil); «$100» тоже понимаем
    private static func parseConversion(_ q: String) -> (Double, String, String?)? {
        var s = q
        if let m = match("^\\s*([$€£¥₽])\\s*" + num + "(.*)$", s) {
            s = m[2] + " " + m[1] + m[3]
        }
        if let m = match("^\\s*" + num + "\\s*([^\\d\\s=→\\-.,][^=→]*?)\\s+(?:в|во|to|in|into|->|=>|→|=)\\s+(.+?)\\s*$", s),
           let v = number(m[1]) {
            return (v, token(m[2]), token(m[3]))
        }
        if let m = match("^\\s*" + num + "\\s*([^\\d\\s=→\\-.,][^=→]*?)\\s*$", s), let v = number(m[1]) {
            return (v, token(m[2]), nil)
        }
        return nil
    }

    // MARK: ответы без сети: арифметика и единицы

    static func answer(_ q: String) -> QuickItem? {
        // даты и похожие записи не считаем
        if match("^\\d{1,4}[-./]\\d{1,2}[-./]\\d{1,4}$", q) != nil { return nil }

        // «15% от 8400»
        if let m = match("^\\s*(.+?)\\s*%\\s*(?:от|of)\\s+(.+?)\\s*$", q),
           let a = calc(m[1], needOp: false), let b = calc(m[2], needOp: false) {
            let r = a / 100 * b
            return QuickItem(expr: q, result: format(r, maxFrac: 10), copy: format(r, maxFrac: 10, grouping: false))
        }
        // арифметика
        if let r = calc(q, needOp: true) {
            return QuickItem(expr: q, result: format(r, maxFrac: 10), copy: format(r, maxFrac: 10, grouping: false))
        }
        // единицы измерения
        if let conv = parseConversion(q), let toTok = conv.2,
           let uf = QuickUnits.table[conv.1], let ut = QuickUnits.table[toTok],
           let r = QuickUnits.convert(conv.0, from: uf, to: ut) {
            let fr = unitFrac(r)
            return QuickItem(expr: format(conv.0, maxFrac: 6) + " " + conv.1 + " → " + toTok,
                             result: format(r, maxFrac: fr) + " " + toTok,
                             copy: format(r, maxFrac: fr, grouping: false))
        }
        return nil
    }

    // MARK: валюты

    private static let currencyAliases: [String: String] = {
        var t: [String: String] = [:]
        func add(_ code: String, _ names: [String]) { for n in names { t[n] = code } }
        add("USD", ["usd", "$", "доллар", "доллара", "долларов", "доллары", "доллар сша", "dollar", "dollars", "бакс", "баксов"])
        add("EUR", ["eur", "€", "евро", "euro", "euros"])
        add("RUB", ["rub", "₽", "руб", "рубль", "рубля", "рублей", "рубли", "ruble", "rubles"])
        add("GBP", ["gbp", "£", "фунт стерлингов", "фунта стерлингов", "фунтов стерлингов", "pound sterling"])
        add("CNY", ["cny", "rmb", "юань", "юаня", "юаней", "yuan"])
        add("JPY", ["jpy", "¥", "иена", "иены", "иен", "yen"])
        add("TRY", ["try", "лира", "лиры", "лир", "турецкая лира", "турецких лир"])
        add("KZT", ["kzt", "тенге"])
        add("UAH", ["uah", "гривна", "гривны", "гривен"])
        add("BYN", ["byn", "белорусский рубль", "белорусских рублей"])
        add("CHF", ["chf", "франк", "франка", "франков"])
        add("AED", ["aed", "дирхам", "дирхама", "дирхамов"])
        add("THB", ["thb", "бат", "бата", "батов"])
        add("INR", ["inr", "рупия", "рупии", "рупий"])
        add("KRW", ["krw", "вона", "воны", "вон"])
        add("GEL", ["gel", "лари"])
        add("AMD", ["amd", "драм", "драма", "драмов"])
        add("AZN", ["azn", "манат", "маната", "манатов"])
        add("UZS", ["uzs", "сум", "сума", "сумов"])
        add("KGS", ["kgs", "сом", "сома", "сомов"])
        add("PLN", ["pln", "злотый", "злотого", "злотых"])
        return t
    }()

    private static func currencyCode(_ tok: String) -> String? {
        if let c = currencyAliases[tok] { return c }
        if tok.count == 3, tok.allSatisfy({ $0 >= "a" && $0 <= "z" }) {
            let u = tok.uppercased()
            if Rates.shared.rates[u] != nil { return u }
        }
        return nil
    }

    /// Похоже ли на просьбу конвертировать валюту (курсы подтянутся отдельно)
    static func currencyRequest(_ q: String) -> CurrencyRequest? {
        guard let conv = parseConversion(q), QuickUnits.table[conv.1] == nil,
              let cf = currencyCode(conv.1) else { return nil }
        if let toTok = conv.2 {
            guard let ct = currencyCode(toTok) else { return nil }
            return CurrencyRequest(value: conv.0, from: cf, to: ct)
        }
        // «100 долларов» без «в …»: показываем в рублях (а рубли — в долларах)
        return CurrencyRequest(value: conv.0, from: cf, to: cf == "RUB" ? "USD" : "RUB")
    }

    static func currencyAnswer(_ r: CurrencyRequest, fresh: Bool) -> QuickItem? {
        let rates = Rates.shared.rates
        guard let rf = rates[r.from], let rt = rates[r.to], rf > 0 else { return nil }
        let out = r.value * rt / rf
        let frac = abs(out) < 1 ? 4 : 2
        var note: String? = nil
        if let d = Rates.shared.date {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            let ds = f.string(from: d)
            note = fresh ? Tf("Курс на %@", ds) : Tf("Нет связи — последний сохранённый курс на %@", ds)
        }
        return QuickItem(expr: format(r.value, maxFrac: 6) + " " + r.from + " → " + r.to,
                         result: format(out, maxFrac: frac, minFrac: 2) + " " + r.to,
                         copy: format(out, maxFrac: frac, minFrac: 2, grouping: false),
                         note: note)
    }
}

final class QuickAnswer: ObservableObject {
    @Published var item: QuickItem?
    private var gen = 0

    func update(_ raw: String) {
        gen += 1
        let g = gen
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, q.count <= 80 else { item = nil; return }
        if let it = QuickCalc.answer(q) { item = it; return }
        if let cur = QuickCalc.currencyRequest(q) {
            item = nil
            Rates.shared.ensure { [weak self] has, fresh in
                guard let self = self, g == self.gen else { return }
                self.item = has ? QuickCalc.currencyAnswer(cur, fresh: fresh) : nil
            }
            return
        }
        item = nil
    }
}

struct QuickAnswerCard: View {
    let item: QuickItem
    let onCopied: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.expr).font(.callout).foregroundColor(.secondary).lineLimit(1)
                Text(item.result).font(.system(size: 28, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let n = item.note { Text(n).font(.caption).foregroundColor(.secondary) }
            }
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc").font(.system(size: 16))
                Text(copied ? T("Скопировано") : T("Копировать")).font(.caption)
            }
            .foregroundColor(copied ? .green : .secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
        .contentShape(Rectangle())
        .onTapGesture {
            copyToPasteboard(item.copy)
            copied = true
            onCopied()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
        .help(T("Нажмите, чтобы скопировать результат"))
    }
}

// MARK: - Поиск файлов и папок через системный Spotlight (как в Spotlight на iPhone)

struct FileHit: Identifiable {
    let id: String      // полный путь
    let name: String
    let dir: String
    let kind: String
    let byContent: Bool   // найден по тексту внутри файла, а не по имени
    let inCloud: Bool     // лежит в облаке и не скачан на этот Мак
    let icon: NSImage
}

final class FileSearch: ObservableObject {
    @Published var hits: [FileHit] = []
    private var mdq: NSMetadataQuery?
    private var pending: DispatchWorkItem?
    private var tokens: [NSObjectProtocol] = []

    /// Вызывается при каждом изменении строки поиска (с небольшой задержкой, чтобы не искать на каждую букву)
    func update(_ raw: String) {
        pending?.cancel()
        stop()
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { if !hits.isEmpty { hits = [] }; return }
        let w = DispatchWorkItem { [weak self] in self?.run(t) }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    private func stop() {
        mdq?.stop()
        mdq = nil
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens = []
    }

    /// Домашняя папка и подключённые внешние тома (системные папки и загрузочный том не ищем)
    private static func scopes() -> [Any] {
        var r: [Any] = [NSMetadataQueryUserHomeScope]
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsLocalKey]
        for u in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            guard u.path.hasPrefix("/Volumes/") else { continue }
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.volumeIsInternal == true { continue }
            r.append(u.path)
        }
        // iCloud Drive и облачные папки (Dropbox, Google Drive…) лежат в ~/Library — добавляем явно
        let home = NSHomeDirectory()
        for sub in ["/Library/Mobile Documents/com~apple~CloudDocs", "/Library/CloudStorage"]
        where FileManager.default.fileExists(atPath: home + sub) { r.append(home + sub) }
        return r
    }

    private func run(_ t: String) {
        let q = NSMetadataQuery()
        // по имени и по тексту внутри файлов (то, что Spotlight проиндексировал)
        q.predicate = NSPredicate(format: "%K CONTAINS[cd] %@ OR %K CONTAINS[cd] %@",
                                  NSMetadataItemDisplayNameKey, t, "kMDItemTextContent", t)
        q.searchScopes = FileSearch.scopes()
        q.notificationBatchingInterval = 0.2
        for n in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            tokens.append(NotificationCenter.default.addObserver(forName: n, object: q, queue: .main) { [weak self, weak q] _ in
                guard let self = self, let q = q else { return }
                self.collect(q, t)
            })
        }
        mdq = q
        q.start()
    }

    private static let skipPrefixes = ["/System/", "/Library/", "/private/", "/usr/", "/opt/", "/bin/", "/sbin/", "/cores/", "/Applications/"]

    private static func skip(_ path: String, home: String) -> Bool {
        if path.hasSuffix(".app") || path.contains(".app/") { return true }    // приложения ищутся отдельно
        if skipPrefixes.contains(where: { path.hasPrefix($0) }) { return true }
        if path.hasPrefix(home + "/Library/") {
            // из Library нужны только iCloud Drive и облачные папки
            let ok = [home + "/Library/Mobile Documents/com~apple~CloudDocs/", home + "/Library/CloudStorage/"]
            if !ok.contains(where: { path.hasPrefix($0) }) { return true }
        }
        for c in path.split(separator: "/") where c == "node_modules" { return true }
        for c in path.split(separator: "/") where c.hasPrefix(".") && !(c.hasSuffix(".icloud")) { return true }
        return false
    }

    /// Файл числится в iCloud, но его содержимое ещё не скачано на этот Мак
    private static func notDownloaded(_ path: String) -> Bool {
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let st = v?.ubiquitousItemDownloadingStatus else { return false }
        return st != .current
    }

    private func collect(_ q: NSMetadataQuery, _ t: String) {
        q.disableUpdates()
        defer { q.enableUpdates() }
        let home = NSHomeDirectory()
        let lower = t.lowercased()
        var seen = Set<String>()
        var items: [(path: String, name: String, type: String, used: Date, placeholder: Bool)] = []
        for i in 0..<min(q.resultCount, 5000) {
            guard let it = q.result(at: i) as? NSMetadataItem,
                  var path = it.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if FileSearch.skip(path, home: home) { continue }
            // старый вид незагруженного файла iCloud: «.Имя.icloud» — показываем настоящее имя
            var placeholder = false
            let last = (path as NSString).lastPathComponent
            if last.hasPrefix(".") && last.hasSuffix(".icloud") && last.count > 8 {
                path = (path as NSString).deletingLastPathComponent + "/" + String(last.dropFirst().dropLast(7))
                placeholder = true
            }
            if !seen.insert(path).inserted { continue }
            let name = placeholder ? (path as NSString).lastPathComponent
                : ((it.value(forAttribute: NSMetadataItemDisplayNameKey) as? String) ?? (path as NSString).lastPathComponent)
            let type = (it.value(forAttribute: NSMetadataItemContentTypeKey) as? String) ?? ""
            let used = (it.value(forAttribute: "kMDItemLastUsedDate") as? Date)
                ?? (it.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date) ?? .distantPast
            items.append((path, name, type, used, placeholder))
        }
        // порядок: имя начинается с запроса → имя содержит запрос → найдено только в тексте; внутри группы — недавние выше
        func group(_ n: String) -> Int {
            let l = n.lowercased()
            return l.hasPrefix(lower) ? 0 : (l.contains(lower) ? 1 : 2)
        }
        items.sort {
            let a = group($0.name), b = group($1.name)
            if a != b { return a < b }
            return $0.used > $1.used
        }
        hits = items.prefix(40).map { i in
            FileHit(id: i.path, name: i.name,
                    dir: ((i.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath,
                    kind: UTType(i.type)?.localizedDescription ?? "",
                    byContent: group(i.name) == 2,
                    inCloud: i.placeholder || FileSearch.notDownloaded(i.path),
                    icon: NSWorkspace.shared.icon(forFile: i.path))
        }
    }
}

struct FileRow: View {
    let hit: FileHit
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: hit.icon).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.name).font(.system(size: 13)).lineLimit(1)
                Text(hit.dir).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            if hit.inCloud {
                Image(systemName: "icloud").font(.caption).foregroundColor(.secondary)
                    .help(T("Лежит в iCloud, не скачан на этот Мак — откроется после загрузки"))
            }
            if hit.byContent {
                Text(T("в тексте")).font(.caption).foregroundColor(.accentColor).lineLimit(1)
            }
            Text(hit.kind).font(.caption).foregroundColor(.secondary).lineLimit(1)
            // справа: показать файл в Finder (появляется при наведении)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hit.id)])
            } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(T("Показать в Finder"))
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onOpen() }
        // перетаскивание файла из результатов поиска в любое приложение или в Finder: уходит копия, оригинал остаётся на месте
        .onDrag { makeFileDragProvider(URL(fileURLWithPath: hit.id)) }
        .contextMenu {
            Button(T("Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hit.id)])
            }
            Button(T("Копировать файл")) {
                // как ⌘C в Finder: потом ⌘V вставит копию файла куда угодно
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([URL(fileURLWithPath: hit.id) as NSURL])
            }
            Button(T("Копировать путь")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hit.id, forType: .string)
            }
        }
    }
}

struct AppCell: View {
    let app: AppItem
    let icon: NSImage
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: icon).resizable().frame(width: 52, height: 52)
            Text(app.name)
                .font(.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onOpen() }
    }
}

struct LinkCell: View {
    let link: WebLink
    let icon: NSImage?
    var custom = false
    let onOpen: () -> Void
    @State private var hover = false

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
    private var color: Color {
        let n = link.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return LinkCell.palette[n % LinkCell.palette.count]
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if custom, let icon = icon {
                    // своя иконка из банка или с диска — на всю плитку, без белой подложки
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFill()
                } else if let icon = icon {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                        .padding(icon.size.width >= 100 ? 4 : 11)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.softGradient())
                    Text(String(link.title.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(icon == nil ? 0 : 0.12), lineWidth: 1))
            Text(link.title)
                .font(.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onOpen() }
        .help(link.url)
    }
}

extension Color {
    func softGradient() -> LinearGradient {
        LinearGradient(colors: [self.opacity(0.85), self], startPoint: .top, endPoint: .bottom)
    }
}

struct AddLinkCell: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: "plus").font(.system(size: 20)).foregroundColor(.secondary)
            }
            .frame(width: 52, height: 52)
            Text(T("Добавить сайт"))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action() }
    }
}

struct FolderCell: View {
    let folder: WebFolder
    let previews: [(WebLink, NSImage?)]
    let onOpen: () -> Void
    let onDropLink: ([NSItemProvider]) -> Bool
    @State private var hover = false
    @State private var targeted = false

    private func mini(_ l: WebLink, _ icon: NSImage?) -> some View {
        ZStack {
            if let icon = icon {
                RoundedRectangle(cornerRadius: 4).fill(Color.white)
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().padding(2)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.7))
                Text(String(l.title.prefix(1)).uppercased()).font(.system(size: 9, weight: .bold)).foregroundColor(.white)
            }
        }
        .frame(width: 20, height: 20)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(targeted ? 0.22 : 0.10))
                if previews.isEmpty {
                    Image(systemName: "folder").font(.system(size: 22)).foregroundColor(.secondary)
                } else {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            if previews.indices.contains(0) { mini(previews[0].0, previews[0].1) } else { Color.clear.frame(width: 20, height: 20) }
                            if previews.indices.contains(1) { mini(previews[1].0, previews[1].1) } else { Color.clear.frame(width: 20, height: 20) }
                        }
                        HStack(spacing: 4) {
                            if previews.indices.contains(2) { mini(previews[2].0, previews[2].1) } else { Color.clear.frame(width: 20, height: 20) }
                            if previews.indices.contains(3) { mini(previews[3].0, previews[3].1) } else { Color.clear.frame(width: 20, height: 20) }
                        }
                    }
                }
            }
            .frame(width: 52, height: 52)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor, lineWidth: targeted ? 2 : 0))
            Text(folder.title)
                .font(.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onOpen() }
        .onDrop(of: [UTType.plainText], isTargeted: $targeted) { providers in onDropLink(providers) }
    }
}

struct AddFolderCell: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                Image(systemName: "folder.badge.plus").font(.system(size: 20)).foregroundColor(.secondary)
            }
            .frame(width: 52, height: 52)
            Text(T("Новая папка"))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action() }
    }
}

struct FolderEditorOverlay: View {
    let draft: FolderDraft
    let store: Store
    @State private var title: String

    init(draft: FolderDraft, store: Store) {
        self.draft = draft
        self.store = store
        _title = State(initialValue: draft.title)
    }

    private var valid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 12) {
                Text(draft.id == nil ? T("Новая папка") : T("Переименовать папку")).font(.headline)
                TextField(T("Название"), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                HStack {
                    Button(T("Отмена")) { store.folderDraft = nil }
                    Button(T("Сохранить")) { save() }.disabled(!valid)
                }
            }
            .padding(20)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }

    private func save() {
        guard valid else { return }
        store.saveFolder(FolderDraft(id: draft.id, title: title))
        store.folderDraft = nil
    }
}

/// Окно добавления и правки ссылки (внутри окна «Пуск», без системных листов)
struct LinkEditorOverlay: View {
    let draft: LinkDraft
    let store: Store
    @State private var title: String
    @State private var url: String
    @State private var showError = false

    init(draft: LinkDraft, store: Store) {
        self.draft = draft
        self.store = store
        _title = State(initialValue: draft.title)
        _url = State(initialValue: draft.url)
    }

    private var valid: Bool { Store.normalizedURL(url) != nil }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 12) {
                Text(draft.id == nil ? T("Новый сайт") : T("Изменить сайт")).font(.headline)
                TextField(T("Название"), text: $title).textFieldStyle(.roundedBorder)
                TextField(T("Адрес"), text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                if showError && !valid {
                    Text(T("Некорректный адрес")).font(.caption).foregroundColor(.orange)
                }
                HStack {
                    Button(T("Отмена")) { store.linkDraft = nil }
                    Button(T("Сохранить")) { save() }.disabled(url.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }

    private func save() {
        guard valid else { showError = true; return }
        store.saveLink(LinkDraft(id: draft.id, title: title, url: url))
        store.linkDraft = nil
    }
}

/// Настройки «Пуска»: язык, горячие клавиши, жест, функции «Свернуть всё» и запуск (всё, что раньше было в меню строки меню)
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
    }
    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 Andy Khristoforov"
    }
}

struct SettingsOverlay: View {
    let store: Store
    @ObservedObject var mc: MinimizeController
    @State private var confirmPinch = false
    @State private var confirmPin = false

    private func languageTitle(_ l: AppLanguage) -> String {
        switch l {
        case .system: return T("Как в системе")
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    private func themeTitle(_ t: AppTheme) -> String {
        switch t {
        case .system: return T("Как в системе")
        case .light: return T("Светлая")
        case .dark: return T("Тёмная")
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
    }

    private func hotkeyRow(_ title: String, combo: String, forStart: Bool) -> some View {
        let active = mc.recordingFor == (forStart ? 2 : 1)
        return HStack {
            Text(title)
            Spacer()
            Button {
                if active { mc.cancelRecording() } else { mc.record(forStart: forStart) }
            } label: {
                Text(active ? T("Нажмите сочетание…") : combo)
                    .frame(minWidth: 110)
            }
        }
    }

    private func toggleRow(_ title: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { on }, set: set))
            .toggleStyle(.switch)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 0) {
                HStack {
                    Text(T("Настройки Пуска")).font(.headline)
                    Spacer()
                }
                .padding(16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section(T("Язык")) {
                            Picker("", selection: Binding(get: { store.language }, set: { store.setLanguage($0) })) {
                                ForEach(AppLanguage.allCases, id: \.self) { Text(languageTitle($0)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        section(T("Тема")) {
                            Picker("", selection: Binding(get: { store.theme }, set: { store.setTheme($0) })) {
                                ForEach(AppTheme.allCases, id: \.self) { Text(themeTitle($0)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        section(T("Горячие клавиши")) {
                            hotkeyRow(T("Открыть или скрыть «Пуск»"), combo: mc.startComboTitle, forStart: true)
                            hotkeyRow(T("Свернуть все окна"), combo: mc.minimizeComboTitle, forStart: false)
                            if mc.recordingFor != nil {
                                Text(T("Нужен хотя бы один модификатор (⌃ ⌥ ⌘ ⇧). Esc — отмена."))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        section(T("Жест")) {
                            toggleRow(T("Открывать «Пуск» жестом: большой + три пальца"), mc.pinchOn) { on in
                                if on { confirmPinch = true } else { mc.setPinch(false) }
                            }
                            if mc.pinchOn {
                                TimelineView(.periodic(from: Date(), by: 1)) { _ in
                                    Text(mc.pinchDiagnostic()).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            if confirmPinch {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(T("Включить жест «большой + три пальца»?")).font(.system(size: 13, weight: .semibold))
                                    Text(T("Чтобы системный жест не открывал своё приложение одновременно с «Пуском», ")
                                         + T("сначала отключите его: Настройки → Трекпад → Другие жесты → «Launchpad» («Приложения»)."))
                                        .font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Button(T("Отмена")) { confirmPinch = false }
                                        Button(T("Включить")) { mc.setPinch(true); confirmPinch = false }
                                    }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                            }
                        }
                        section(T("Свернуть всё")) {
                            toggleRow(T("Возвращать окна, если экран пуст"), mc.restoreOn) { mc.setRestore($0) }
                            toggleRow(T("Сворачивать по клику в Dock"), mc.dockOn) { mc.setDock($0) }
                            Button(T("Разрешения…")) { store.showSettings = false; store.showPermissions = true }
                        }
                        section(T("Система")) {
                            toggleRow(T("Запускать при входе в систему"), mc.loginOn) { mc.setLogin($0) }
                            Button(T("Закрепить в Dock первым (справа от Finder)…")) { confirmPin = true }
                            if confirmPin {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(T("Закрепить «Пуск» в Dock?")).font(.system(size: 13, weight: .semibold))
                                    Text(T("Иконка встанет первой справа от Finder. Dock на секунду перезапустится. Делайте это, когда «Пуск» лежит на своём постоянном месте."))
                                        .font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Button(T("Отмена")) { confirmPin = false }
                                        Button(T("Закрепить")) { confirmPin = false; mc.pinToDock() }
                                    }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                            }
                        }
                    }
                    .padding(16)
                }
                Divider()
                HStack {
                    Spacer()
                    Button(T("Готово")) { mc.cancelRecording(); store.showSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 440)
            .frame(maxHeight: 520)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
            .padding(20)
        }
        .onAppear { mc.syncSettings() }
    }
}

struct RootView: View {
    @ObservedObject var store: Store
    let close: () -> Void
    let resetPlacement: () -> Void

    @State private var query = ""
    /// Меняется при очистке поиска: поле создаётся заново, иначе после длинного текста оно остаётся прокрученным
    /// вправо и в нём не видно ни подсказки, ни вводимого текста
    @State private var searchGen = 0
    @State private var editingOriginal: String? = nil   // "" — новая категория
    @State private var draft = ""
    @State private var dropTarget: String? = nil
    @State private var showTools = false
    @StateObject private var files = FileSearch()
    @StateObject private var quick = QuickAnswer()
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var showingLinks: Bool { store.currentSelection == webCategory && !searching }

    private var linksGrid: some View {
        let current = store.openFolder
        let folder = store.folders.first { $0.id == current }
        let shown = store.links.filter { $0.folder == (folder?.id) }
        return VStack(alignment: .leading, spacing: 10) {
            if let f = folder {
                HStack(spacing: 6) {
                    Button { store.openFolder = nil } label: {
                        Label(T("Сайты"), systemImage: "chevron.left")
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(6)
                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                        dropLink(providers, to: nil)
                    }
                    .help(T("Перетащите сайт сюда, чтобы вынести из папки"))
                    Text(f.title).font(.headline)
                    Spacer()
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 8)], spacing: 8) {
                if folder == nil {
                    ForEach(store.folders) { f in
                        FolderCell(folder: f,
                                   previews: store.links.filter { $0.folder == f.id }.prefix(4).map { ($0, store.linkIcon($0)) },
                                   onOpen: { store.openFolder = f.id },
                                   onDropLink: { providers in dropLink(providers, to: f.id) })
                            .contextMenu {
                                Button(T("Переименовать")) { store.folderDraft = FolderDraft(id: f.id, title: f.title) }
                                Button(T("Удалить папку")) { store.deleteFolder(f) }
                            }
                    }
                }
                ForEach(shown) { l in
                    LinkCell(link: l, icon: store.linkIcon(l), custom: store.hasCustomLinkIcon(l), onOpen: { openLink(l) })
                        .onDrag { NSItemProvider(object: "link:\(l.id.uuidString)" as NSString) }
                        .contextMenu {
                            Button(T("Изменить…")) { store.linkDraft = LinkDraft(id: l.id, title: l.title, url: l.url) }
                            Button(T("Сменить иконку…")) { store.chooseIcon(for: l) }
                            if store.hasCustomLinkIcon(l) {
                                Button(T("Вернуть исходную иконку")) { store.resetIcon(l) }
                            }
                            if !store.folders.isEmpty {
                                Menu(T("Переместить в папку")) {
                                    ForEach(store.folders.filter { $0.id != l.folder }) { f in
                                        Button(f.title) { store.moveLink(l.id, to: f.id) }
                                    }
                                }
                            }
                            if l.folder != nil {
                                Button(T("Вынести из папки")) { store.moveLink(l.id, to: nil) }
                            }
                            Button(T("Удалить")) { store.deleteLink(l) }
                        }
                }
                AddLinkCell { store.linkDraft = LinkDraft(id: nil, title: "", url: "", folder: folder?.id) }
                if folder == nil {
                    AddFolderCell { store.folderDraft = FolderDraft(id: nil, title: "") }
                }
            }
            if store.links.isEmpty && store.folders.isEmpty {
                Text(T("Быстрый доступ к сайтам: нажмите «Добавить сайт»."))
                    .font(.callout).foregroundColor(.secondary).padding(.top, 8)
            }
        }
        .padding(14)
        .onAppear { store.ensureIcons() }
    }

    /// Перетаскивание сайта на папку (или на «назад», чтобы вынести из папки)
    private func dropLink(_ providers: [NSItemProvider], to folder: UUID?) -> Bool {
        guard let p = providers.first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let ns = obj as? NSString else { return }
            let str = String(ns)
            guard str.hasPrefix("link:"), let id = UUID(uuidString: String(str.dropFirst(5))) else { return }
            DispatchQueue.main.async { store.moveLink(id, to: folder) }
        }
        return true
    }

    private func openLink(_ l: WebLink) {
        if let u = Store.normalizedURL(l.url) { NSWorkspace.shared.open(u) }
        close()
    }

    private var visibleApps: [AppItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            return store.apps.filter { a in
                a.name.localizedCaseInsensitiveContains(q) || a.aliases.contains { $0.localizedCaseInsensitiveContains(q) }
            }
        }
        let sel = store.currentSelection
        if sel == allCategory { return store.apps }
        return store.apps.filter { store.category(of: $0) == sel }
    }

    var body: some View {
        VStack(spacing: 0) {
        DragBar()
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Divider()
            VStack(spacing: 0) {
                // своя рамка вокруг поля: крестик очистки стоит рядом с полем ввода, а не поверх него,
                // поэтому над ним обычная стрелка, а не «палочка» ввода
                HStack(spacing: 4) {
                    TextField(T("Поиск"), text: $query)
                        .id(searchGen)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .disabled(overlayOpen)
                        .onChange(of: overlayOpen) { open in
                            if open {
                                searchFocused = false
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                        }
                        .onChange(of: query) { q in
                            files.update(q)
                            quick.update(q)
                        }
                        .onSubmit {
                            if let first = visibleApps.first { launch(first) }
                            else if let a = quick.item { copyToPasteboard(a.copy); close() }
                            // документы из результатов поиска по Enter не открываются: только мышью
                        }
                    if !query.isEmpty {
                        Button {
                            clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .padding(2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(T("Очистить поиск"))
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(searchFocused ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.35),
                            lineWidth: searchFocused ? 2 : 1))
                .padding([.top, .horizontal], 14)
                HStack {
                    Text(searching ? T("Результаты поиска") : T(store.currentSelection))
                        .font(.headline)
                    Spacer()
                    if store.keepAwake {
                        Text(T("Не давать компьютеру уснуть"))
                            .font(.caption).foregroundColor(.accentColor).lineLimit(1)
                    }
                    Button { store.showSettings = true } label: {
                        Image(systemName: "gearshape.2")
                            .padding(5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(6)
                    .foregroundColor(.secondary)
                    .help(T("Настройки Пуска"))
                    Button { store.setKeepAwake(!store.keepAwake) } label: {
                        Image(systemName: store.keepAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .padding(5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(6)
                    .foregroundColor(store.keepAwake ? .accentColor : .secondary)
                    .help(store.keepAwake ? T("Компьютер не уснёт — нажмите, чтобы отключить") : T("Не давать компьютеру уснуть"))
                    Button { store.showPermissions = true } label: {
                        Image(systemName: store.permissionsOK ? "lock.shield" : "exclamationmark.shield")
                            .padding(5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(6)
                    .foregroundColor(store.permissionsOK ? .secondary : .orange)
                    .help(store.permissionsOK ? T("Разрешения") : T("Не все разрешения выданы — нажмите, чтобы настроить"))
                    Button { resetPlacement() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .padding(5).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(6)
                    .foregroundColor(.secondary)
                    .help(T("Вернуть размер и положение по умолчанию"))
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                ScrollView {
                  VStack(alignment: .leading, spacing: 0) {
                    if searching, let a = quick.item {
                        QuickAnswerCard(item: a, onCopied: {}).padding(.horizontal, 14).padding(.top, 14)
                    }
                    if showingLinks {
                        linksGrid
                    } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 8)], spacing: 8) {
                        ForEach(visibleApps) { app in
                            AppCell(app: app, icon: store.icon(for: app), onOpen: { launch(app) })
                                .onDrag { NSItemProvider(object: app.id as NSString) }
                                .contextMenu { appMenu(app) }
                        }
                    }
                    .padding(14)
                    }
                    if searching && !files.hits.isEmpty {
                        Text(T("Файлы и папки")).font(.headline)
                            .padding(.horizontal, 16).padding(.top, visibleApps.isEmpty ? 2 : 4).padding(.bottom, 4)
                        VStack(spacing: 0) {
                            ForEach(files.hits) { h in FileRow(hit: h, onOpen: { openFile(h) }) }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 12)
                    }
                  }
                }
            }
        }
        }
        .frame(minWidth: minWindowSize.width, maxWidth: maxWindowSize.width,
               minHeight: minWindowSize.height, maxHeight: maxWindowSize.height)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if let m = store.uninstall { UninstallOverlay(model: m, store: store) }
            if let q = store.quitAll { QuitAllOverlay(model: q, store: store) }
            if store.showSettings, let mc = store.minimize { SettingsOverlay(store: store, mc: mc) }
            if let d = store.folderDraft { FolderEditorOverlay(draft: d, store: store).id(d.key) }
            if let d = store.linkDraft { LinkEditorOverlay(draft: d, store: store).id(d.key) }
            if let pr = store.pwRequest, store.pwTool == nil { PasswordOverlay(request: pr, store: store) }
            if store.showPermissions { PermissionsOverlay(store: store) }
        }
        .overlay(alignment: .bottom) { dropBanner }
        .onExitCommand { close() }
        .id(store.language)
        .onReceive(store.$showTick) { _ in
            // строка поиска не сбрасывается при сворачивании и повторном открытии «Пуска» — только кнопкой очистки
            editingOriginal = nil
            showTools = false
            store.linkDraft = nil
            store.folderDraft = nil
            store.openFolder = nil
            store.showSettings = false
            if store.quitAll?.stage != .working { store.quitAll = nil }
            store.minimize?.cancelRecording()
            if store.uninstall?.stage != .working { store.uninstall = nil }
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var overlayOpen: Bool {
        store.quitAll != nil || store.showSettings || store.linkDraft != nil || store.folderDraft != nil
            || store.uninstall != nil
    }

    // Боковая панель

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    categoryRow(allCategory)
                    categoryRow(webCategory)
                    ForEach(store.categoryList, id: \.self) { categoryRow($0) }
                    if editingOriginal == "" { nameField }
                }
                .padding(10)
            }
            Divider()
            VStack(spacing: 10) {
                Button {
                    beginEdit("", text: "")
                } label: {
                    Label(T("Новая категория"), systemImage: "plus.circle")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(7)
                .help(T("Создать свою категорию"))

                HStack(spacing: 0) {
                    HStack(spacing: 7) {
                        shortcut("com.apple.Terminal", T("Терминал"), "terminal")
                        shortcut("com.apple.ActivityMonitor", T("Мониторинг системы"), "waveform.path.ecg")
                        shortcut("com.apple.AppStore", "App Store", "bag")
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 7) {
                    // Инструменты: меню открывается выше кнопки (см. toolsMenu)
                    Button { showTools.toggle() } label: {
                        // значок в том же стиле, что у «Системных настроек»: скруглённый квадрат с градиентом и белым знаком
                        ZStack {
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.68, blue: 1.0),
                                                              Color(red: 0.04, green: 0.40, blue: 0.95)],
                                                     startPoint: .top, endPoint: .bottom))
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        // у настоящих значков macOS есть прозрачные поля, поэтому наш квадрат чуть меньше рамки 24×24
                        .frame(width: 21, height: 21)
                        .frame(width: 24, height: 24)
                        .padding(4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(8)
                    .help(T("Инструменты"))
                    shortcut("com.apple.systempreferences", T("Системные настройки"), "gearshape")
                    }
                }
            }
            .padding(12)
        }
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .bottomTrailing) {
            if showTools {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { showTools = false }
                    toolsMenu
                        .padding(.trailing, 14)
                        .padding(.bottom, 82)
                }
            }
        }
    }

    /// Меню инструментов: появляется над кнопкой. Новые инструменты добавляем сюда.
    private var toolsMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ToolRow(title: T("Передохни"), symbol: "gamecontroller") {
                showTools = false
                RestWindowController.shared.show()
            }
            ToolRow(title: T("Калькулятор"), symbol: "plusminus.circle") {
                showTools = false
                CalcWindowController.shared.show()
            }
            ToolRow(title: T("Файл менеджер"), symbol: "rectangle.split.2x1") {
                showTools = false
                TPWindowController.shared.show()
            }
            ToolRow(title: T("Очистка мусора"), symbol: "sparkles") {
                showTools = false
                store.beginClean()
            }
            ToolRow(title: T("Большие и старые файлы"), symbol: "archivebox") {
                showTools = false
                store.beginBig()
            }
            ToolRow(title: T("Обслуживание"), symbol: "wrench.and.screwdriver") {
                showTools = false
                store.beginMaint()
            }
            ToolRow(title: T("Анализатор диска"), symbol: "chart.pie") {
                showTools = false
                store.beginDisk()
            }
            ToolRow(title: T("Внешние диски"), symbol: "externaldrive") {
                showTools = false
                store.beginFormat()
            }
            ToolRow(title: T("Загрузка и конвертация"), symbol: "arrow.down.circle") {
                showTools = false
                DCWindowController.shared.show(store: store)
            }
            ToolRow(title: T("Закрыть все программы"), symbol: "xmark.circle") {
                showTools = false
                store.beginQuitAll()
            }
        }
        .padding(6)
        .frame(minWidth: 190, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }

    private var nameField: some View {
        TextField(T("Название"), text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($nameFocused)
            .onSubmit { commitEdit() }
            .onChange(of: nameFocused) { focused in if !focused { commitEdit() } }
    }

    @ViewBuilder
    private func categoryRow(_ name: String) -> some View {
        if editingOriginal == name {
            nameField
        } else {
            let isCustom = store.customCategories.contains(name)
            let isSelected = store.currentSelection == name && !searching
            let isDropTarget = dropTarget == name && name != allCategory
            HStack(spacing: 8) {
                Image(systemName: symbol(for: name)).frame(width: 20)
                Text(T(name)).lineLimit(1)
                Spacer()
                Text("\(store.count(in: name))").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isDropTarget ? Color.accentColor.opacity(0.4)
                      : (isSelected ? Color.accentColor.opacity(0.25) : Color.clear)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color.accentColor, lineWidth: isDropTarget ? 2 : 0))
            .hoverHighlight(7)
            .contentShape(Rectangle())
            .onTapGesture { store.selected = name; clearSearch() }
            .contextMenu {
                if isCustom {
                    Button(T("Переименовать")) { beginEdit(name, text: name) }
                    Button(T("Удалить категорию")) { store.deleteCategory(name) }
                }
            }
            .onDrop(of: [UTType.plainText],
                    isTargeted: Binding(
                        get: { dropTarget == name },
                        set: { on in
                            if on { if name != webCategory { dropTarget = name } }
                            else if dropTarget == name { dropTarget = nil }
                        })) { providers in
                if name == webCategory { return false }
                return handleDrop(providers, to: name)
            }
        }
    }

    @ViewBuilder
    private func appMenu(_ app: AppItem) -> some View {
        Menu(T("Переместить в категорию")) {
            ForEach(store.assignableCategories, id: \.self) { c in
                Button(T(c)) { store.assign(app, to: c) }
            }
        }
        if store.assignments[app.id] != nil {
            Button(T("Вернуть в автоматическую категорию")) { store.resetAssignment(app) }
        }
        Button(T("Сменить иконку…")) { store.chooseIcon(for: app) }
        if store.hasCustomIcon(app) {
            Button(T("Вернуть исходную иконку")) { store.resetIcon(app) }
        }
        Button(T("Показать в Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
        }
        Divider()
        if app.path.hasPrefix("/System/") {
            Button(T("Удалить… (системное приложение)")) { }.disabled(true)
        } else {
            Button(T("Удалить…")) { store.beginUninstall(app) }
        }
    }

    @ViewBuilder
    private var dropBanner: some View {
        if let t = dropTarget, t != allCategory {
            Text(Tf("Переместить в «%@»", "\(T(t))"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.accentColor))
                .padding(.bottom, 14)
                .allowsHitTesting(false)
        }
    }

    // Действия

    private func beginEdit(_ original: String, text: String) {
        draft = text
        editingOriginal = original
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitEdit() {
        guard let orig = editingOriginal else { return }
        editingOriginal = nil
        let name = draft
        draft = ""
        if orig.isEmpty { store.addCategory(name) } else { store.renameCategory(orig, to: name) }
    }

    private func handleDrop(_ providers: [NSItemProvider], to category: String) -> Bool {
        guard category != allCategory, let p = providers.first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let ns = obj as? NSString else { return }
            let id = String(ns)
            if id.hasPrefix("link:") { return }   // это сайт, а не приложение
            DispatchQueue.main.async { store.assign(id: id, to: category) }
        }
        return true
    }

    private func bundleIcon(_ id: String, _ symbol: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
    }

    /// Быстрый запуск системного приложения иконкой внизу панели
    private func shortcut(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { openBundle(id) } label: {
            Image(nsImage: bundleIcon(id, symbol)).resizable().frame(width: 24, height: 24)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(8)
        .help(title)
    }

    private var appStoreIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.AppStore") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "bag.fill", accessibilityDescription: nil) ?? NSImage()
    }

    private func openBundle(_ id: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
        close()
    }

    private func openSettings() { openBundle("com.apple.systempreferences") }
    private func openAppStore() { openBundle("com.apple.AppStore") }

    private func clearSearch() {
        query = ""
        searchGen += 1
        DispatchQueue.main.async { searchFocused = true }
    }

    private func openFile(_ f: FileHit) {
        NSWorkspace.shared.open(URL(fileURLWithPath: f.id))
        close()
    }

    private func launch(_ app: AppItem) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path),
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
        close()
    }
}

// MARK: - Окно и приложение

final class PopupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    let minimize = MinimizeController()
    var window: PopupWindow!
    private var programmatic = false
    private let defaults = UserDefaults.standard

    /// Положение и размер, которые задал пользователь (nil — ставим у Dock автоматически)
    private var savedFrame: NSRect? {
        guard defaults.bool(forKey: "customPlacement"),
              let str = defaults.string(forKey: "windowFrame") else { return nil }
        let r = NSRectFromString(str)
        guard r.width > 0, r.height > 0 else { return nil }
        var out = r
        out.size.width = min(max(r.width, minWindowSize.width), maxWindowSize.width)
        out.size.height = min(max(r.height, minWindowSize.height), maxWindowSize.height)
        return out
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppTheme.apply()
        DispatchQueue.global(qos: .utility).async { cleanDropTemp() }
        setupMenu()
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            self?.setupMenu()
        }
        let host = NSHostingView(rootView: RootView(store: store, close: { [weak self] in self?.hide() },
                                              resetPlacement: { [weak self] in self?.resetPlacement() }))
        window = PopupWindow(contentRect: NSRect(origin: .zero, size: defaultWindowSize),
                             styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.minSize = minWindowSize
        window.maxSize = maxWindowSize
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                               object: window, queue: .main) { [weak self] _ in self?.hide() }
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.saveFrame()
            }
        }
        store.minimize = minimize
        minimize.toggleAwake = { [weak store] in if let st = store { st.setKeepAwake(!st.keepAwake) } }
        minimize.openStart = { [weak self] in self?.show() }
        minimize.toggleStart = { [weak self] in
            guard let self = self else { return }
            if self.window.isVisible && NSApp.isActive { self.window.orderOut(nil) } else { self.show() }
        }
        minimize.start()
        // Esc закрывает «Пуск» из любого места окна, даже если фокус не в SwiftUI-элементе
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53, let w = e.window, ToolWindows.shared.handleEscape(w) { return nil }
            guard let self = self, e.keyCode == 53, self.window.isKeyWindow,
                  NSApp.modalWindow == nil, self.window.attachedSheet == nil,
                  self.store.pwRequest == nil, self.minimize.recordingFor == nil else { return e }
            self.hide()
            return nil
        }
        show()
    }

    private func saveFrame() {
        guard !programmatic, window.isVisible else { return }
        defaults.set(NSStringFromRect(window.frame), forKey: "windowFrame")
        defaults.set(true, forKey: "customPlacement")
    }

    func resetPlacement() {
        defaults.set(false, forKey: "customPlacement")
        programmatic = true
        window.setContentSize(defaultWindowSize)
        positionNearDock()
        programmatic = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window.isVisible { hide() } else { show() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Если идёт загрузка или конвертация, перед выходом спрашиваем
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DCWindowController.shared.confirmQuit() ? .terminateNow : .terminateCancel
    }

    func applicationDidResignActive(_ notification: Notification) { hide() }

    func positionNearDock() {
        // Окно появляется у Dock и целиком выше него (в том числе при автоскрытии и увеличении иконок)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame, vf = screen.visibleFrame
        let w = window.frame.width, h = window.frame.height
        let m: CGFloat = 10

        let dock = UserDefaults(suiteName: "com.apple.dock")
        let orient = dock?.string(forKey: "orientation") ?? "bottom"
        var tile = CGFloat(dock?.double(forKey: "tilesize") ?? 0)
        if tile <= 0 { tile = 48 }
        let large = CGFloat(dock?.double(forKey: "largesize") ?? 0)
        let magnified = dock?.bool(forKey: "magnification") ?? false
        let est = (magnified ? max(tile, large) : tile) + 36   // запас на подложку Dock

        var x: CGFloat, y: CGFloat
        switch orient {
        case "left":
            let inset = max(vf.minX - f.minX, est)
            x = f.minX + inset + m
            y = mouse.y - h / 2
            y = max(vf.minY + m, min(y, vf.maxY - h - m))
        case "right":
            let inset = max(f.maxX - vf.maxX, est)
            x = f.maxX - inset - w - m
            y = mouse.y - h / 2
            y = max(vf.minY + m, min(y, vf.maxY - h - m))
        default:
            let inset = max(vf.minY - f.minY, est)
            y = f.minY + inset + m
            let onDock = mouse.y <= f.minY + inset + 20
            x = onDock ? mouse.x - w / 2 : vf.minX + m
            x = max(vf.minX + m, min(x, vf.maxX - w - m))
            y = min(y, vf.maxY - h - m)
        }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show() {
        programmatic = true
        if let r = savedFrame, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) {
            window.setFrame(r, display: true)
        } else {
            positionNearDock()
        }
        programmatic = false
        store.rescan()
        store.refreshPermissions()
        store.showTick += 1
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        if Store.suppressAutoHide { return }
        window.orderOut(nil)
    }

    private func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: T("О программе «Пуск»"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: T("Завершить Пуск"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: T("Правка")); editItem.submenu = edit
        edit.addItem(withTitle: T("Вырезать"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: T("Копировать"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: T("Вставить"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: T("Выбрать всё"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

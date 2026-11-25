import Cocoa
import FinderSync

// MARK: - «Создать» в контекстном меню Finder
//
// Пункт «Создать» в меню правого клика по пустому месту (рабочий стол и окна Finder) даёт расширение Finder Sync
// (StartFinderExt.appex внутри приложения). Само оно работает в песочнице и только сообщает, в какой папке щёлкнули
// и что создать; файл создаёт это приложение (у него есть нужный доступ к диску). Включённое расширение нужно
// выдать в «Системные настройки → Расширения → Расширения Finder» — на вкладке «Разрешения» есть подсказка.

final class FinderNew {
    static let shared = FinderNew()
    static let extensionID = "ru.local.StartMenu.FinderExt"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "finder.new") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "finder.new") }
    }

    /// Кнопка «Сортировка» на панели Finder (macOS 26 и новее): отдельная настройка, по умолчанию выключена
    static var sortEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "finder.sort") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "finder.sort") }
    }

    private var urlHandlerSet = false

    /// Принимает ссылки startformac://create?dir=…&kind=… от расширения Finder
    func registerURLHandler() {
        guard !urlHandlerSet else { return }
        urlHandlerSet = true
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let comps = URLComponents(string: str), comps.scheme == "startformac" else { return }
        var q: [String: String] = [:]
        for i in comps.queryItems ?? [] { if let v = i.value { q[i.name] = v } }
        if comps.host == "create" { create(dir: q["dir"], kind: q["kind"]) }
        else if comps.host == "sort" { sortFrontWindow(by: q["by"]) }
    }

    /// Кнопка «Сортировка» на панели Finder: нажимает в Finder пункт «Вид → Сортировать по …» (Finder сам применяет сортировку
    /// и перерисовывает окно). Пункт ищется по названию в меню самого Finder, потому что состав и порядок пунктов зависят
    /// от версии macOS. Нужен «Универсальный доступ». Если такого пункта в меню нет, ничего не происходит.
    private func sortFrontWindow(by key: String?) {
        guard FinderNew.sortEnabled, #available(macOS 26.0, *) else { return }
        guard let k = key,
              let finder = NSWorkspace.shared.frontmostApplication, finder.bundleIdentifier == "com.apple.finder" else { return }
        // части названия пункта (в нижнем регистре): русский и английский
        let words: [String: [String]] = [
            "none": ["нет", "без сорт", "none"],
            "name": ["имя", "имени", "name"],
            "kind": ["тип", "вид", "kind"],
            "opened": ["открыти", "opened"],
            "added": ["добавлени", "added"],
            "modified": ["изменени", "modified"],
            "created": ["создани", "created"],
            "size": ["размер", "size"],
            "label": ["тег", "метк", "tags", "label"]]
        guard let w = words[k] else { return }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        func kids(_ e: AXUIElement) -> [AXUIElement] {
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v)
            return (v as? [AXUIElement]) ?? []
        }
        func title(_ e: AXUIElement) -> String {
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXTitleAttribute as CFString, &v)
            return (v as? String) ?? ""
        }
        var mb: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &mb)
        guard let bar = mb else { return }
        // «Вид» — пятый пункт строки меню (Apple, Finder, Файл, Правка, Вид); внутри ищем подменю «Сортировать по»
        let barItems = kids(bar as! AXUIElement)
        guard barItems.count > 4, let viewMenu = kids(barItems[4]).first else { return }
        guard let sortItem = kids(viewMenu).first(where: {
            let t = title($0).lowercased()
            return t.hasPrefix("сортировать") || t.hasPrefix("sort by")
        }), let sortMenu = kids(sortItem).first else { return }
        let items = kids(sortMenu).filter { !title($0).isEmpty }
        if FinderNew.debugSort { NSLog("Sort menu: %@", items.map { title($0) }.joined(separator: " | ")) }
        // «Дата создания» не должна совпасть с «Дата изменения» и т. п. — ищем по самой специфичной части названия
        // «Без сортировки» — всегда первый пункт подменю, как бы он ни назывался
        if k == "none", let first = items.first {
            AXUIElementPerformAction(first, kAXPressAction as CFString)
            return
        }
        if let hit = items.first(where: { it in
            let t = title(it).lowercased()
            return w.contains(where: { t.contains($0) })
        }) {
            AXUIElementPerformAction(hit, kAXPressAction as CFString)
        }
    }
    static var debugSort = true

    private var appexPath: String { Bundle.main.bundlePath + "/Contents/PlugIns/StartFinderExt.appex" }

    private static func pluginkit(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Включено ли расширение в системе: true — да, false — выключено, nil — система его не знает
    static func extensionState() -> Bool? {
        let out = pluginkit(["-m", "-p", "com.apple.FinderSync", "-i", extensionID])
        guard let line = out.split(separator: "\n").first(where: { $0.contains(extensionID) }) else { return nil }
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("+")
    }

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    /// Регистрирует расширение, просит систему его включить и начинает принимать его команды
    func start() {
        let path = appexPath
        DispatchQueue.global(qos: .utility).async {
            _ = FinderNew.pluginkit(["-a", path])
            _ = FinderNew.pluginkit(["-e", "use", "-i", FinderNew.extensionID])
        }
    }

    func stop() {
        DispatchQueue.global(qos: .utility).async {
            _ = FinderNew.pluginkit(["-e", "ignore", "-i", FinderNew.extensionID])
        }
    }

    /// Просит включить расширение: сначала через систему, затем открывает список расширений Finder
    func requestEnable() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = FinderNew.pluginkit(["-a", self.appexPath])
            _ = FinderNew.pluginkit(["-e", "use", "-i", FinderNew.extensionID])
            DispatchQueue.main.async { Store.current?.refreshPermissions() }
        }
    }

    static func openManagement() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    // MARK: Создание файлов

    // MARK: Меню «Создать» (значок в строке меню, значок в Dock, горячая клавиша)
    // Работает и там, где расширение Finder молчит (рабочий стол в iCloud Drive): файл создаётся в папке
    // активного окна Finder, а если окна нет, на рабочем столе.

    private static func installed(_ id: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// Виды файлов в меню: (вид, название); офисные — только при наличии подходящей программы (как в расширении Finder)
    static func menuKinds() -> [(String, String)] {
        var r: [(String, String)] = [("txt", T("Текстовый документ")), ("md", T("Документ Markdown")), ("file", T("Пустой файл")),
                                     ("html", T("Страница HTML")), ("json", T("Файл JSON")), ("csv", T("Таблица CSV")), ("rtf", T("Документ RTF"))]
        let suites = ["org.libreoffice.script", "org.onlyoffice.desktopeditors", "com.kingsoft.wpsoffice.mac"]
        let office: [(kind: String, apps: [String], native: String, nativeTitle: String, plainTitle: String)] = [
            ("docx", ["com.microsoft.Word", "com.apple.iWork.Pages"] + suites, "com.microsoft.Word", T("Документ Word (.docx)"), T("Документ (.docx)")),
            ("xlsx", ["com.microsoft.Excel", "com.apple.iWork.Numbers"] + suites, "com.microsoft.Excel", T("Таблица Excel (.xlsx)"), T("Таблица (.xlsx)")),
            ("pptx", ["com.microsoft.Powerpoint", "com.apple.iWork.Keynote"] + suites, "com.microsoft.Powerpoint", T("Презентация PowerPoint (.pptx)"), T("Презентация (.pptx)")),
            ("odt", ["org.libreoffice.script"], "org.libreoffice.script", T("Документ LibreOffice (.odt)"), ""),
            ("ods", ["org.libreoffice.script"], "org.libreoffice.script", T("Таблица LibreOffice (.ods)"), ""),
            ("odp", ["org.libreoffice.script"], "org.libreoffice.script", T("Презентация LibreOffice (.odp)"), "")
        ]
        for o in office where o.apps.contains(where: installed) {
            r.append((o.kind, installed(o.native) || o.plainTitle.isEmpty ? o.nativeTitle : o.plainTitle))
        }
        return r
    }

    /// Папка для нового файла: папка активного окна Finder (через «Универсальный доступ»), иначе рабочий стол
    static func targetFolder() -> URL {
        let desk = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.finder" else { return desk }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let w = WindowFinder.attr(ax, kAXFocusedWindowAttribute),
              let doc = WindowFinder.attr(w as! AXUIElement, kAXDocumentAttribute) as? String,
              let u = URL(string: doc), u.isFileURL else { return desk }
        return u
    }

    /// Пункт «Создать» с подменю для меню значка в строке меню и в Dock (nil, если настройка выключена)
    func createMenuItem(dir folder: URL? = nil, target: AnyObject? = nil, action: Selector? = nil) -> NSMenuItem? {
        guard FinderNew.enabled else { return nil }
        let dir = folder ?? FinderNew.targetFolder()
        let sub = NSMenu()
        let head = sub.addItem(withTitle: Tf("Создать в: «%@»", FileManager.default.displayName(atPath: dir.path)), action: nil, keyEquivalent: "")
        head.isEnabled = false
        sub.addItem(.separator())
        for (kind, title) in FinderNew.menuKinds() {
            let it = sub.addItem(withTitle: title, action: action ?? #selector(menuPick(_:)), keyEquivalent: "")
            it.target = target ?? self
            it.representedObject = ["dir": dir.path, "kind": kind]
        }
        sub.addItem(NewImage.menuItem(dir: dir, target: target ?? self, action: action ?? #selector(menuPick(_:))))
        let top = NSMenuItem(title: T("Создать"), action: nil, keyEquivalent: "")
        top.submenu = sub
        return top
    }

    @objc func menuPick(_ sender: NSMenuItem) {
        guard let d = sender.representedObject as? [String: String] else { return }
        create(dir: d["dir"], kind: d["kind"])
    }

    /// Меню «Создать» у курсора — по горячей клавише
    func showPopup() {
        guard let sub = createMenuItem()?.submenu else { return }
        sub.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Команда от расширения или из меню: создаёт файл и выделяет его в Finder (только при включённой настройке)
    private func create(dir: String?, kind: String?) {
        guard FinderNew.enabled, let url = createFile(dir: dir, kind: kind) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Создаёт файл нужного вида в папке dir под свободным именем; возвращает адрес или nil
    @discardableResult
    func createFile(dir: String?, kind: String?) -> URL? {
        guard let dir = dir, let kind = kind else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
        let base = URL(fileURLWithPath: dir)
        if kind.contains(":") { return createImage(in: base, kind: kind) }
        let name: String, ext: String
        switch kind {
        case "txt":    name = T("Новый текстовый документ"); ext = "txt"
        case "md":     name = T("Новый документ Markdown"); ext = "md"
        case "file":   name = T("Новый файл"); ext = ""
        case "html":   name = T("Новая страница"); ext = "html"
        case "json":   name = T("Новый файл JSON"); ext = "json"
        case "csv":    name = T("Новая таблица CSV"); ext = "csv"
        case "rtf":    name = T("Новый документ RTF"); ext = "rtf"
        case "docx", "odt": name = T("Новый документ"); ext = kind
        case "xlsx", "ods": name = T("Новая таблица"); ext = kind
        case "pptx", "odp": name = T("Новая презентация"); ext = kind
        default: return nil
        }
        var url = base.appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let n = name + " \(i)"
            url = base.appendingPathComponent(ext.isEmpty ? n : n + "." + ext)
            i += 1
        }
        let ok: Bool
        if ["docx", "xlsx", "pptx", "odt", "ods", "odp"].contains(kind) {
            // пустой документ — копия заготовки из папки FinderTemplates внутри приложения
            let src = Bundle.main.resourceURL?.appendingPathComponent("FinderTemplates/blank." + kind)
            ok = src.map { (try? FileManager.default.copyItem(at: $0, to: url)) != nil } ?? false
        } else {
            // заготовки: HTML — пустая страница, JSON — пустой объект, RTF — пустой документ; остальные файлы пустые
            let text: String
            switch kind {
            case "html": text = "<!DOCTYPE html>\n<html lang=\"ru\">\n<head>\n<meta charset=\"utf-8\">\n<title></title>\n</head>\n<body>\n\n</body>\n</html>\n"
            case "json": text = "{}\n"
            case "rtf":  text = "{\\rtf1\\ansi\\ansicpg1251\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 }"
            default:     text = ""
            }
            ok = FileManager.default.createFile(atPath: url.path, contents: text.data(using: .utf8))
        }
        return ok ? url : nil
    }
}

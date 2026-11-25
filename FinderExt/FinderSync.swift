import Cocoa
import FinderSync

// Расширение Finder: пункт «Создать» в меню правого клика по пустому месту. Работает в песочнице, поэтому файлы
// не создаёт, а сообщает приложению «StartForMac» (папка и вид файла), и оно их создаёт.

@objc(StartFinderSync)
final class StartFinderSync: FIFinderSync {
    /// Что показывать в меню сейчас (вид файла по номеру пункта); офисные типы — только если в системе есть подходящая программа
    private var kinds: [String] = []

    private struct Office {
        let kind: String
        let apps: [String]           // программы, которые умеют открывать файл
        let nativeApp: String        // «родная» программа Microsoft: от неё название пункта
        let ruNative: String, enNative: String, ruPlain: String, enPlain: String
    }

    private static let suites = ["org.libreoffice.script", "org.onlyoffice.desktopeditors", "com.kingsoft.wpsoffice.mac"]
    private let offices: [Office] = [
        Office(kind: "docx", apps: ["com.microsoft.Word", "com.apple.iWork.Pages"] + StartFinderSync.suites, nativeApp: "com.microsoft.Word",
               ruNative: "Документ Word (.docx)", enNative: "Word document (.docx)", ruPlain: "Документ (.docx)", enPlain: "Document (.docx)"),
        Office(kind: "xlsx", apps: ["com.microsoft.Excel", "com.apple.iWork.Numbers"] + StartFinderSync.suites, nativeApp: "com.microsoft.Excel",
               ruNative: "Таблица Excel (.xlsx)", enNative: "Excel workbook (.xlsx)", ruPlain: "Таблица (.xlsx)", enPlain: "Spreadsheet (.xlsx)"),
        Office(kind: "pptx", apps: ["com.microsoft.Powerpoint", "com.apple.iWork.Keynote"] + StartFinderSync.suites, nativeApp: "com.microsoft.Powerpoint",
               ruNative: "Презентация PowerPoint (.pptx)", enNative: "PowerPoint presentation (.pptx)", ruPlain: "Презентация (.pptx)", enPlain: "Presentation (.pptx)"),
        Office(kind: "odt", apps: ["org.libreoffice.script"], nativeApp: "org.libreoffice.script",
               ruNative: "Документ LibreOffice (.odt)", enNative: "LibreOffice document (.odt)", ruPlain: "", enPlain: ""),
        Office(kind: "ods", apps: ["org.libreoffice.script"], nativeApp: "org.libreoffice.script",
               ruNative: "Таблица LibreOffice (.ods)", enNative: "LibreOffice spreadsheet (.ods)", ruPlain: "", enPlain: ""),
        Office(kind: "odp", apps: ["org.libreoffice.script"], nativeApp: "org.libreoffice.script",
               ruNative: "Презентация LibreOffice (.odp)", enNative: "LibreOffice presentation (.odp)", ruPlain: "", enPlain: "")
    ]

    private func installed(_ id: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    override init() {
        super.init()
        // следим за всем диском и отдельно за настоящей домашней папкой (в песочнице NSHomeDirectory() — не она)
        var dirs: Set<URL> = [URL(fileURLWithPath: "/")]
        if let pw = getpwuid(getuid()), let h = pw.pointee.pw_dir {
            let home = URL(fileURLWithPath: String(cString: h))
            dirs.insert(home)
            for sub in ["Desktop", "Documents", "Downloads"] { dirs.insert(home.appendingPathComponent(sub)) }
        }
        dirs.insert(URL(fileURLWithPath: "/Volumes"))
        FIFinderSyncController.default().directoryURLs = dirs
    }

    private var russian: Bool { return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false }

    /// Кнопка «Сортировка» только на macOS 26 и новее (там ошибка с группами в режиме значков)
    private static var sortAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// На старых системах не отвечаем на запросы про кнопку панели, и Finder её не показывает
    override func responds(to aSelector: Selector!) -> Bool {
        if !StartFinderSync.sortAvailable,
           aSelector == #selector(getter: FIFinderSync.toolbarItemName) || aSelector == #selector(getter: FIFinderSync.toolbarItemImage)
            || aSelector == #selector(getter: FIFinderSync.toolbarItemToolTip) { return false }
        return super.responds(to: aSelector)
    }

    // Кнопка «Сортировка» на панели Finder (добавляется в «Вид → Настроить панель инструментов»): сортировка значков без групп
    override var toolbarItemName: String { return russian ? "Сортировка" : "Sort" }
    override var toolbarItemToolTip: String { return russian ? "Сортировка значков без групп" : "Sort icons without groups" }
    override var toolbarItemImage: NSImage {
        let img = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16))
        img.isTemplate = true
        return img
    }

    private static let sortKeys = ["name", "kind", "opened", "added", "modified", "created", "size", "label", "none"]

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        if menuKind == .toolbarItemMenu {
            guard StartFinderSync.sortAvailable else { return menu }
            let titles = russian ? ["По имени", "По типу", "По дате последнего открытия", "По дате добавления", "По дате изменения", "По дате создания", "По размеру", "По тегам", "Без сортировки"]
                                 : ["Name", "Kind", "Date Last Opened", "Date Added", "Date Modified", "Date Created", "Size", "Tags", "None"]
            for (i, t) in titles.enumerated() {
                if i == titles.count - 1 { menu.addItem(.separator()) }
                let item = NSMenuItem(title: t, action: #selector(sortItems(_:)), keyEquivalent: "")
                item.tag = i
                menu.addItem(item)
            }
            return menu
        }
        guard menuKind == .contextualMenuForContainer else { return menu }
        var titles = russian ? ["Текстовый документ", "Документ Markdown", "Пустой файл", "Страница HTML", "Файл JSON", "Таблица CSV", "Документ RTF"]
                             : ["Text document", "Markdown document", "Empty file", "HTML page", "JSON file", "CSV table", "RTF document"]
        kinds = ["txt", "md", "file", "html", "json", "csv", "rtf"]
        for o in offices where o.apps.contains(where: installed) {
            kinds.append(o.kind)
            titles.append(installed(o.nativeApp) ? (russian ? o.ruNative : o.enNative) : (russian ? o.ruPlain : o.enPlain))
        }
        let sub = NSMenu(title: "")
        for (i, t) in titles.enumerated() {
            let item = NSMenuItem(title: t, action: #selector(create(_:)), keyEquivalent: "")
            item.tag = i
            sub.addItem(item)
        }
        // «Изображение» → формат → размер (PSD, XCF, KRA — только если есть программа)
        let gimp = ["org.gimp.gimp", "org.gimp.gimp-2.10", "org.gimp.gimp-3.0", "org.gimp.gimp-2.99", "org.gimp.gimp-2.8"]
        var fmts: [(String, String)] = [("png", "PNG"), ("jpg", "JPEG"), ("svg", "SVG")]
        if (["com.adobe.Photoshop", "com.pixelmatorteam.pixelmator.x", "com.seriflabs.affinityphoto2", "com.seriflabs.affinityphoto"] + gimp).contains(where: installed) {
            fmts.append(("psd", "Photoshop (.psd)"))
        }
        if gimp.contains(where: installed) { fmts.append(("xcf", "GIMP (.xcf)")) }
        if installed("org.kde.krita") { fmts.append(("kra", "Krita (.kra)")) }
        let imgMenu = NSMenu(title: "")
        for (fmt, title) in fmts {
            let fm = NSMenu(title: "")
            for (w, h) in [(1920, 1080), (1024, 1024), (512, 512)] {
                let it = NSMenuItem(title: "\(w)×\(h)", action: #selector(create(_:)), keyEquivalent: "")
                it.tag = kinds.count
                kinds.append("\(fmt):\(w)x\(h)")
                fm.addItem(it)
            }
            fm.addItem(.separator())
            let own = NSMenuItem(title: russian ? "Свой размер…" : "Custom size…", action: #selector(create(_:)), keyEquivalent: "")
            own.tag = kinds.count
            kinds.append("\(fmt):ask")
            fm.addItem(own)
            let fi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            fi.submenu = fm
            imgMenu.addItem(fi)
        }
        let imgItem = NSMenuItem(title: russian ? "Изображение" : "Image", action: nil, keyEquivalent: "")
        imgItem.submenu = imgMenu
        sub.addItem(imgItem)
        let top = NSMenuItem(title: russian ? "Создать" : "Create", action: nil, keyEquivalent: "")
        top.submenu = sub
        menu.addItem(top)
        return menu
    }

    @objc func sortItems(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem, item.tag >= 0, item.tag < StartFinderSync.sortKeys.count else { return }
        var c = URLComponents()
        c.scheme = "startformac"
        c.host = "sort"
        c.queryItems = [URLQueryItem(name: "by", value: StartFinderSync.sortKeys[item.tag])]
        guard let url = c.url else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.open(url, configuration: cfg, completionHandler: nil)
    }

    @objc func create(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem, item.tag >= 0, item.tag < kinds.count,
              let dir = FIFinderSyncController.default().targetedURL() else { return }
        // команда приложению — через ссылку startformac://create?... (рассылки между процессами в песочнице ненадёжны)
        var c = URLComponents()
        c.scheme = "startformac"
        c.host = "create"
        c.queryItems = [URLQueryItem(name: "dir", value: dir.path), URLQueryItem(name: "kind", value: kinds[item.tag])]
        guard let url = c.url else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.open(url, configuration: cfg, completionHandler: nil)
    }
}

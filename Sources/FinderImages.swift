import Cocoa

// MARK: - Пустые изображения для меню «Создать»
//
// PNG, JPEG и SVG доступны всегда; PSD, XCF (GIMP) и KRA (Krita) — если в системе есть подходящая программа.
// Файлы собираются самим «Пуском», без шаблонов: белое полотно заданного размера (SVG и KRA — прозрачное).

enum NewImage {
    static let sizes: [(Int, Int)] = [(1920, 1080), (1024, 1024), (512, 512)]
    static let maxSide = 16384
    static let maxPixels = 40_000_000

    /// Виды: (код, название в меню, программы, которые открывают файл; пусто — показывать всегда)
    static func formats() -> [(String, String)] {
        func has(_ ids: [String]) -> Bool { ids.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } }
        var r: [(String, String)] = [("png", "PNG"), ("jpg", "JPEG"), ("svg", "SVG")]
        let gimp = ["org.gimp.gimp", "org.gimp.gimp-2.10", "org.gimp.gimp-3.0", "org.gimp.gimp-2.99", "org.gimp.gimp-2.8"]
        if has(["com.adobe.Photoshop", "com.pixelmatorteam.pixelmator.x", "com.seriflabs.affinityphoto2", "com.seriflabs.affinityphoto"] + gimp) {
            r.append(("psd", "Photoshop (.psd)"))
        }
        if has(gimp) { r.append(("xcf", "GIMP (.xcf)")) }
        if has(["org.kde.krita"]) { r.append(("kra", "Krita (.kra)")) }
        return r
    }

    static func sizeTitle(_ w: Int, _ h: Int) -> String { "\(w)×\(h)" }

    /// Подменю «Изображение» → формат → размеры (для меню приложения)
    static func menuItem(dir: URL, target: AnyObject, action: Selector) -> NSMenuItem {
        let sub = NSMenu()
        for (fmt, title) in formats() {
            let f = NSMenu()
            for (w, h) in sizes {
                let it = f.addItem(withTitle: sizeTitle(w, h), action: action, keyEquivalent: "")
                it.target = target
                it.representedObject = ["dir": dir.path, "kind": "\(fmt):\(w)x\(h)"]
            }
            f.addItem(.separator())
            let own = f.addItem(withTitle: T("Свой размер…"), action: action, keyEquivalent: "")
            own.target = target
            own.representedObject = ["dir": dir.path, "kind": "\(fmt):ask"]
            let fi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            fi.submenu = f
            sub.addItem(fi)
        }
        let top = NSMenuItem(title: T("Изображение"), action: nil, keyEquivalent: "")
        top.submenu = sub
        return top
    }

    /// Разбор «1920x1080», «1920×1080», «1920 1080», «1920*1080»
    static func parse(_ s: String) -> (Int, Int)? {
        let parts = s.lowercased().split(whereSeparator: { !"0123456789".contains($0) }).compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return (parts[0], parts[1])
    }

    static func valid(_ w: Int, _ h: Int) -> Bool { w <= maxSide && h <= maxSide && w * h <= maxPixels }

    /// Спрашивает размер у пользователя; nil — отмена или неверный ввод
    static func askSize() -> (Int, Int)? {
        let d = UserDefaults.standard
        let a = NSAlert()
        a.messageText = T("Размер изображения")
        a.informativeText = T("Ширина и высота в пикселях, например 1920×1080.")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        f.stringValue = d.string(forKey: "finder.new.lastSize") ?? "1920×1080"
        a.accessoryView = f
        a.addButton(withTitle: T("Создать"))
        a.addButton(withTitle: T("Отмена"))
        a.window.initialFirstResponder = f
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        guard let (w, h) = parse(f.stringValue), valid(w, h) else {
            let e = NSAlert()
            e.messageText = T("Неверный размер")
            e.informativeText = Tf("Допустимо до %@ пикселей по стороне и до 40 мегапикселей всего.", "\(maxSide)")
            e.runModal()
            return nil
        }
        d.set("\(w)×\(h)", forKey: "finder.new.lastSize")
        return (w, h)
    }

    // MARK: сборка файлов

    static func data(_ fmt: String, _ w: Int, _ h: Int) -> Data? {
        switch fmt {
        case "png", "jpg": return bitmap(fmt, w, h)
        case "svg":
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">\n</svg>\n".data(using: .utf8)
        case "psd": return psd(w, h)
        case "xcf": return xcf(w, h)
        case "kra": return kra(w, h)
        default: return nil
        }
    }

    private static func bitmap(_ fmt: String, _ w: Int, _ h: Int) -> Data? {
        let alpha = fmt == "png"
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: alpha ? 4 : 3, hasAlpha: alpha, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let p = rep.bitmapData else { return nil }
        memset(p, 255, rep.bytesPerRow * h)
        return fmt == "png" ? rep.representation(using: .png, properties: [:])
                            : rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
    }

    private static func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 255), UInt8(v & 255)] }
    private static func be32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
    private static func le32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)] }

    /// Photoshop: RGB, 8 бит, один белый слой «Фон», строки сжаты PackBits
    private static func psd(_ w: Int, _ h: Int) -> Data? {
        var row = [UInt8]()
        var rem = w
        while rem > 0 {
            let n = min(128, rem)
            row.append(UInt8(bitPattern: Int8(-(n - 1))))
            row.append(255)
            rem -= n
        }
        var d = [UInt8]()
        d += Array("8BPS".utf8) + be16(1) + [UInt8](repeating: 0, count: 6) + be16(3) + be32(h) + be32(w) + be16(8) + be16(3)
        d += be32(0) + be32(0) + be32(0)          // данные цвета, ресурсы, слои — пусто
        d += be16(1)                              // сжатие RLE
        for _ in 0..<(3 * h) { d += be16(row.count) }
        d.reserveCapacity(d.count + 3 * h * row.count)
        for _ in 0..<(3 * h) { d += row }
        return Data(d)
    }

    /// GIMP: пустое изображение нужного размера (без слоёв, цвет RGB)
    private static func xcf(_ w: Int, _ h: Int) -> Data? {
        var d = [UInt8]()
        d += Array("gimp xcf file".utf8) + [0]
        d += be32(w) + be32(h) + be32(0)          // размеры, RGB
        d += be32(17) + be32(1) + [0]             // свойство «сжатие»: нет
        d += be32(0) + be32(0)                    // конец свойств
        d += be32(0) + be32(0)                    // список слоёв и каналов пуст
        return Data(d)
    }

    // MARK: Krita (ZIP без сжатия)

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc32(_ b: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for x in b { c = crcTable[Int((c ^ UInt32(x)) & 255)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func zip(_ files: [(String, [UInt8])]) -> Data {
        var out = [UInt8](), central = [UInt8]()
        for (name, body) in files {
            let nm = Array(name.utf8), crc = Int(crc32(body)), off = out.count
            out += le32(0x04034b50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(crc) + le32(body.count) + le32(body.count)
            out += le16(nm.count) + le16(0) + nm + body
            central += le32(0x02014b50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0x21) + le32(crc)
            central += le32(body.count) + le32(body.count) + le16(nm.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(off) + nm
        }
        let start = out.count
        out += central
        out += le32(0x06054b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count) + le32(central.count) + le32(start) + le16(0)
        return Data(out)
    }

    /// Krita: пустой документ (без слоёв) нужного размера
    private static func kra(_ w: Int, _ h: Int) -> Data? {
        let main = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DOC xmlns="http://www.calligra.org/DTD/krita" syntaxVersion="2.0" editor="Krita" kritaVersion="5.2.0">
         <IMAGE name="Unnamed" width="\(w)" height="\(h)" mime="application/x-kra" colorspacename="RGBA" profile="sRGB-elle-V2-srgbtrc.icc" x-res="100" y-res="100" description="">
          <layers/>
         </IMAGE>
        </DOC>
        """
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document-info xmlns="http://www.calligra.org/DTD/document-info"><about><title></title></about></document-info>
        """
        return zip([("mimetype", Array("application/x-krita".utf8)), ("maindoc.xml", Array(main.utf8)), ("documentinfo.xml", Array(info.utf8))])
    }
}

extension FinderNew {
    /// Создаёт пустое изображение: kind вида «png:1920x1080» или «png:ask» (размер спрашивается)
    func createImage(in base: URL, kind: String) -> URL? {
        let parts = kind.split(separator: ":").map(String.init)
        guard parts.count == 2 else { return nil }
        let fmt = parts[0]
        let size: (Int, Int)?
        if parts[1] == "ask" { size = NewImage.askSize() } else { size = NewImage.parse(parts[1]) }
        guard let (w, h) = size, NewImage.valid(w, h), let data = NewImage.data(fmt, w, h) else { return nil }
        let name = fmt == "svg" ? T("Новый рисунок") : T("Новое изображение")
        var url = base.appendingPathComponent(name + "." + fmt)
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = base.appendingPathComponent(name + " \(i)." + fmt)
            i += 1
        }
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

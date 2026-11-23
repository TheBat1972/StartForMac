// Инструмент «Загрузка и конвертация»: четвёртый раздел — текстовые форматы.
// TXT, RTF, HTML, DOC, DOCX, ODT, Markdown, PDF, FB2, EPUB друг в друга; картинки и сканы PDF — через
// встроенное распознавание текста macOS (Vision), без установки программ.
import SwiftUI
import AppKit
import PDFKit
import Vision
import UniformTypeIdentifiers

// MARK: - Форматы

enum TextFormat: String, CaseIterable, Identifiable {
    case txt, rtf, html, doc, docx, odt, md, pdf, fb2, epub
    var id: String { rawValue }
    var ext: String { rawValue }
    var title: String { self == .md ? "Markdown" : rawValue.uppercased() }

    static func from(_ url: URL) -> TextFormat? {
        switch url.pathExtension.lowercased() {
        case "txt", "text": return .txt
        case "rtf": return .rtf
        case "html", "htm", "xhtml": return .html
        case "doc": return .doc
        case "docx": return .docx
        case "odt": return .odt
        case "md", "markdown": return .md
        case "pdf": return .pdf
        case "fb2": return .fb2
        case "epub": return .epub
        default: return nil
        }
    }
}

let textImageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "bmp", "gif"]

func isTextJobFile(_ u: URL) -> Bool {
    TextFormat.from(u) != nil || textImageExtensions.contains(u.pathExtension.lowercased())
}

struct TextError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

// MARK: - Промежуточные представления

enum TextSource {
    case file(URL, TextFormat)      // RTF, DOC, DOCX, ODT: читает система
    case plain(String)
    case html(String)
}

struct TRun {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link: String? = nil
}

struct TBlock {
    var level: Int          // 0 — абзац, 1…3 — заголовок, -1 — пункт списка
    var runs: [TRun]
    var plain: String { runs.map { $0.text }.joined() }
}

// MARK: - Движок

enum TextEngine {

    // MARK: чтение (можно в фоне)

    static func prepare(_ url: URL, ocr: Bool, progress: (Double) -> Void, cancelled: () -> Bool) throws -> TextSource {
        let ext = url.pathExtension.lowercased()
        if textImageExtensions.contains(ext) {
            guard ocr else { throw TextError(L("txt.ocrOff")) }
            guard let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw TextError(L("txt.badImage")) }
            let t = try recognize(cg)
            if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw TextError(L("txt.noText")) }
            return .plain(t)
        }
        guard let fmt = TextFormat.from(url) else { throw TextError(L("txt.unsupported")) }
        switch fmt {
        case .rtf, .doc, .docx, .odt:
            return .file(url, fmt)
        case .txt:
            guard let d = try? Data(contentsOf: url) else { throw TextError(L("txt.readFail")) }
            return .plain(decode(d))
        case .html:
            guard let d = try? Data(contentsOf: url) else { throw TextError(L("txt.readFail")) }
            return .html(decode(d))
        case .md:
            guard let d = try? Data(contentsOf: url) else { throw TextError(L("txt.readFail")) }
            return .html(markdownToHTML(decode(d)))
        case .fb2:
            guard let d = try? Data(contentsOf: url) else { throw TextError(L("txt.readFail")) }
            let h = FB2Reader().parse(d)
            if h.isEmpty { throw TextError(L("txt.badFB2")) }
            return .html("<html><head><meta charset=\"utf-8\"></head><body>" + h + "</body></html>")
        case .epub:
            return .html(try epubToHTML(url))
        case .pdf:
            guard let doc = PDFDocument(url: url) else { throw TextError(L("txt.badPDF")) }
            if doc.isLocked { throw TextError(L("txt.pdfLocked")) }
            let layer = doc.string ?? ""
            if !layer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(layer) }
            guard ocr else { throw TextError(L("txt.noTextLayer")) }
            var parts: [String] = []
            let n = doc.pageCount
            for i in 0..<n {
                if cancelled() { throw TextError(L("job.stopped")) }
                if let page = doc.page(at: i), let img = renderPage(page) {
                    parts.append(try recognize(img))
                }
                progress(Double(i + 1) / Double(max(1, n)))
            }
            let text = parts.joined(separator: "\n\n")
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw TextError(L("txt.noText")) }
            return .plain(text)
        }
    }

    // MARK: оформленный текст (только в главном потоке: импорт HTML идёт через WebKit)

    static func baseFont() -> NSFont { NSFont(name: "Arial", size: 12) ?? NSFont.systemFont(ofSize: 12) }

    static func attributed(from src: TextSource) throws -> NSAttributedString {
        switch src {
        case .plain(let s):
            return NSAttributedString(string: s, attributes: [.font: baseFont()])
        case .html(let s):
            guard let data = s.data(using: .utf8) else { throw TextError(L("txt.readFail")) }
            return try NSAttributedString(data: data,
                                          options: [.documentType: NSAttributedString.DocumentType.html,
                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        case .file(let url, let fmt):
            let type: NSAttributedString.DocumentType
            switch fmt {
            case .rtf: type = .rtf
            case .doc: type = .docFormat
            case .docx: type = .officeOpenXML
            default: type = .openDocument
            }
            return try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        }
    }

    // MARK: запись

    static func export(_ a: NSAttributedString, as fmt: TextFormat, to url: URL, title: String) throws {
        let full = NSRange(location: 0, length: a.length)
        switch fmt {
        case .txt:
            try a.string.write(to: url, atomically: true, encoding: .utf8)
        case .rtf:
            try a.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: url)
        case .html:
            try a.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.html,
                                                        .characterEncoding: String.Encoding.utf8.rawValue]).write(to: url)
        case .doc:
            try a.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.docFormat]).write(to: url)
        case .docx:
            try a.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: url)
        case .odt:
            try a.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.openDocument]).write(to: url)
        case .md:
            try markdown(blocks(a)).write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try writePDF(a, to: url)
        case .fb2:
            try fb2(blocks(a), title: title).write(to: url, atomically: true, encoding: .utf8)
        case .epub:
            try writeEPUB(blocks(a), title: title, to: url)
        }
    }

    // MARK: блоки (заголовки, абзацы, списки, выделение)

    static func blocks(_ a: NSAttributedString) -> [TBlock] {
        let ns = a.string as NSString
        let all = NSRange(location: 0, length: ns.length)
        var sizes: [Int: Int] = [:]
        a.enumerateAttribute(.font, in: all, options: []) { v, r, _ in
            if let f = v as? NSFont { sizes[Int(f.pointSize.rounded()), default: 0] += r.length }
        }
        let base = CGFloat(sizes.max { $0.value < $1.value }?.key ?? 12)

        var result: [TBlock] = []
        ns.enumerateSubstrings(in: all, options: .byParagraphs) { _, range, _, _ in
            if range.length == 0 { return }
            var runs: [TRun] = []
            a.enumerateAttributes(in: range, options: []) { attrs, r, _ in
                var text = ns.substring(with: r)
                text = text.replacingOccurrences(of: "\u{2028}", with: " ")
                    .replacingOccurrences(of: "\u{000B}", with: " ")
                    .replacingOccurrences(of: "\u{FFFC}", with: "")
                if text.isEmpty { return }
                var run = TRun(text: text)
                if let f = attrs[.font] as? NSFont {
                    let t = f.fontDescriptor.symbolicTraits
                    run.bold = t.contains(.bold)
                    run.italic = t.contains(.italic)
                    run.code = t.contains(.monoSpace)
                }
                if let u = attrs[.link] as? URL { run.link = u.absoluteString }
                else if let s = attrs[.link] as? String { run.link = s }
                runs.append(run)
            }
            if runs.isEmpty { return }

            // пункт списка: убираем маркер
            var level = 0
            let joined = runs.map { $0.text }.joined()
            if let m = joined.range(of: #"^[\s]*[•◦▪‣∙·\-–—\*][ \t]+"#, options: .regularExpression) {
                var drop = joined.distance(from: joined.startIndex, to: m.upperBound)
                level = -1
                var i = 0
                while drop > 0 && i < runs.count {
                    let c = runs[i].text.count
                    if c <= drop { drop -= c; runs[i].text = "" }
                    else { runs[i].text = String(runs[i].text.dropFirst(drop)); drop = 0 }
                    i += 1
                }
                runs.removeAll { $0.text.isEmpty }
            } else if let first = runs.first {
                var t = first.text
                while let c = t.first, c == "\t" || c == " " { t.removeFirst() }
                runs[0].text = t
                runs.removeAll { $0.text.isEmpty }
            }
            if runs.isEmpty { return }
            if runs.map({ $0.text }).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

            if level == 0, let f = a.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont, base > 0 {
                let ratio = f.pointSize / base
                if ratio >= 1.6 { level = 1 } else if ratio >= 1.3 { level = 2 } else if ratio >= 1.12 { level = 3 }
                if level > 0 { for i in 0..<runs.count { runs[i].bold = false } }
            }
            result.append(TBlock(level: level, runs: runs))
        }
        return result
    }

    private static func mdWrap(_ t: String, _ mark: String) -> String {
        let lead = t.prefix { $0 == " " }
        let trail = t.reversed().prefix { $0 == " " }
        let core = t.trimmingCharacters(in: .whitespaces)
        if core.isEmpty { return t }
        return String(lead) + mark + core + mark + String(trail)
    }

    static func markdown(_ blocks: [TBlock]) -> String {
        var out = ""
        var prevList = false
        for b in blocks {
            var line = ""
            for r in b.runs {
                var t = r.text
                if r.code { t = mdWrap(t, "`") }
                else if r.bold && r.italic { t = mdWrap(t, "***") }
                else if r.bold { t = mdWrap(t, "**") }
                else if r.italic { t = mdWrap(t, "*") }
                if let l = r.link, !l.isEmpty { t = "[" + r.text.trimmingCharacters(in: .whitespaces) + "](" + l + ")" }
                line += t
            }
            let isList = b.level == -1
            var text: String
            switch b.level {
            case 1...3: text = String(repeating: "#", count: b.level) + " " + line.trimmingCharacters(in: .whitespaces)
            case -1: text = "- " + line.trimmingCharacters(in: .whitespaces)
            default: text = line.trimmingCharacters(in: .whitespaces)
            }
            if !out.isEmpty { out += (isList && prevList) ? "\n" : "\n\n" }
            out += text
            prevList = isList
        }
        return out + "\n"
    }

    // MARK: Markdown → HTML

    private static func groups(_ pattern: String, in s: String, caseInsensitive: Bool = false) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    private static func allMatches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// То же для XML: ещё убирает символы, которых в XML быть не может
    static func escapeXML(_ s: String) -> String {
        let clean = String(String.UnicodeScalarView(s.unicodeScalars.filter {
            $0.value >= 0x20 || $0.value == 0x09 || $0.value == 0x0A || $0.value == 0x0D
        }))
        return escapeHTML(clean)
    }

    private static func mdInline(_ s: String) -> String {
        var r = escapeHTML(s)
        func sub(_ p: String, _ t: String) { r = r.replacingOccurrences(of: p, with: t, options: .regularExpression) }
        sub(#"`([^`]+)`"#, "<code>$1</code>")
        sub(#"\*\*(.+?)\*\*"#, "<b>$1</b>")
        sub(#"__(.+?)__"#, "<b>$1</b>")
        sub(#"\*(.+?)\*"#, "<i>$1</i>")
        sub(#"(?<![\w])_(.+?)_(?![\w])"#, "<i>$1</i>")
        sub(#"!\[([^\]]*)\]\([^)]*\)"#, "$1")
        sub(#"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>")
        return r
    }

    static func markdownToHTML(_ md: String) -> String {
        var out = ""
        var para: [String] = []
        var list: String? = nil
        var inCode = false
        var code: [String] = []

        func flushPara() {
            if !para.isEmpty { out += "<p>" + mdInline(para.joined(separator: " ")) + "</p>\n"; para = [] }
        }
        func closeList() {
            if let k = list { out += "</\(k)>\n"; list = nil }
        }
        func item(_ kind: String, _ text: String) {
            flushPara()
            if list != kind { closeList(); out += "<\(kind)>\n"; list = kind }
            out += "<li>" + mdInline(text) + "</li>\n"
        }

        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("```") {
                if inCode {
                    out += "<pre>" + escapeHTML(code.joined(separator: "\n")) + "</pre>\n"
                    code = []; inCode = false
                } else { flushPara(); closeList(); inCode = true }
                continue
            }
            if inCode { code.append(line); continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { flushPara(); closeList(); continue }
            if let g = groups(#"^(#{1,6})\s+(.*)$"#, in: t) {
                flushPara(); closeList()
                let n = g[1].count
                out += "<h\(n)>" + mdInline(g[2]) + "</h\(n)>\n"
                continue
            }
            if t.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil {
                flushPara(); closeList(); out += "<hr/>\n"; continue
            }
            if let g = groups(#"^[-*+]\s+(.*)$"#, in: t) { item("ul", g[1]); continue }
            if let g = groups(#"^\d+[.)]\s+(.*)$"#, in: t) { item("ol", g[1]); continue }
            if t.hasPrefix(">") {
                flushPara(); closeList()
                out += "<blockquote>" + mdInline(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)) + "</blockquote>\n"
                continue
            }
            closeList()
            para.append(t)
        }
        if inCode { out += "<pre>" + escapeHTML(code.joined(separator: "\n")) + "</pre>\n" }
        flushPara(); closeList()
        return "<html><head><meta charset=\"utf-8\"></head><body>" + out + "</body></html>"
    }

    // MARK: чтение текста в разных кодировках

    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return s }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1251) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: распознавание текста (Vision, встроено в macOS)

    static func recognize(_ image: CGImage) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let supported = (try? req.supportedRecognitionLanguages()) ?? []
        let want = ["ru-RU", "en-US"].filter { supported.contains($0) }
        if !want.isEmpty { req.recognitionLanguages = want }
        if #available(macOS 13.0, *) { req.automaticallyDetectsLanguage = true }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([req])
        let obs: [VNRecognizedTextObservation] = req.results ?? []
        return obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func renderPage(_ page: PDFPage) -> CGImage? {
        let r = page.bounds(for: .mediaBox)
        let scale: CGFloat = 300.0 / 72.0
        let w = Int(r.width * scale), h = Int(r.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    // MARK: PDF

    static func writePDF(_ a: NSAttributedString, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw TextError(L("txt.pdfWriteFail")) }
        let setter = CTFramesetterCreateWithAttributedString(a as CFAttributedString)
        let textRect = box.insetBy(dx: 56, dy: 56)
        var loc = 0
        let len = a.length
        repeat {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: loc, length: 0), CGPath(rect: textRect, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            let vis = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if vis.length == 0 { break }
            loc += vis.length
        } while loc < len
        ctx.closePDF()
    }

    // MARK: FB2

    final class FB2Reader: NSObject, XMLParserDelegate {
        private var html = ""
        private var inBody = false
        private var titleDepth = 0

        func parse(_ data: Data) -> String {
            let p = XMLParser(data: data)
            p.delegate = self
            p.parse()
            return html
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let n = name.lowercased()
            if n == "body" { inBody = true; return }
            guard inBody else { return }
            switch n {
            case "title": titleDepth += 1; html += "<h2>"
            case "subtitle": html += "<h3>"
            case "p": if titleDepth == 0 { html += "<p>" }
            case "strong": html += "<b>"
            case "emphasis": html += "<i>"
            case "code": html += "<code>"
            case "empty-line": html += "<br/>"
            case "epigraph", "cite": html += "<blockquote>"
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            let n = name.lowercased()
            if n == "body" { inBody = false; return }
            guard inBody else { return }
            switch n {
            case "title": titleDepth -= 1; html += "</h2>\n"
            case "subtitle": html += "</h3>\n"
            case "p": html += titleDepth == 0 ? "</p>\n" : "<br/>"
            case "strong": html += "</b>"
            case "emphasis": html += "</i>"
            case "code": html += "</code>"
            case "epigraph", "cite": html += "</blockquote>\n"
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inBody { html += TextEngine.escapeHTML(string) }
        }
    }

    private static func inlineXML(_ runs: [TRun]) -> String {
        var s = ""
        for r in runs {
            var t = escapeXML(r.text)
            if r.code { t = "<code>" + t + "</code>" }
            if r.bold { t = "<strong>" + t + "</strong>" }
            if r.italic { t = "<emphasis>" + t + "</emphasis>" }
            s += t
        }
        return s
    }

    static func fb2(_ blocks: [TBlock], title: String) -> String {
        var body = ""
        for b in blocks {
            switch b.level {
            case 1...3: body += "<subtitle>" + escapeXML(b.plain.trimmingCharacters(in: .whitespaces)) + "</subtitle>\n"
            case -1: body += "<p>• " + inlineXML(b.runs) + "</p>\n"
            default: body += "<p>" + inlineXML(b.runs) + "</p>\n"
            }
        }
        let t = escapeXML(title)
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
        <description><title-info><genre>prose</genre><author><nickname>-</nickname></author><book-title>\(t)</book-title><lang>ru</lang></title-info></description>
        <body><title><p>\(t)</p></title><section>
        \(body)</section></body>
        </FictionBook>
        """
    }

    // MARK: EPUB

    @discardableResult
    static func runTool(_ path: String, _ args: [String], cwd: URL? = nil) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let c = cwd { p.currentDirectoryURL = c }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func epubToHTML(_ url: URL) throws -> String {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("txtconv-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        guard runTool("/usr/bin/unzip", ["-qq", "-o", url.path, "-d", work.path]) == 0 else { throw TextError(L("txt.badEpub")) }
        guard let cdata = try? Data(contentsOf: work.appendingPathComponent("META-INF/container.xml")),
              let opfPath = groups(#"full-path="([^"]+)""#, in: decode(cdata))?[1] else { throw TextError(L("txt.badEpub")) }
        let opfURL = work.appendingPathComponent(opfPath)
        guard let odata = try? Data(contentsOf: opfURL) else { throw TextError(L("txt.badEpub")) }
        let opf = decode(odata)
        var hrefs: [String: String] = [:]
        for tag in allMatches(#"<item\b[^>]*>"#, in: opf) {
            if let id = groups(#"\sid="([^"]+)""#, in: tag)?[1], let href = groups(#"\shref="([^"]+)""#, in: tag)?[1] {
                hrefs[id] = href
            }
        }
        var body = ""
        for tag in allMatches(#"<itemref\b[^>]*>"#, in: opf) {
            guard let idref = groups(#"\sidref="([^"]+)""#, in: tag)?[1], let href = hrefs[idref] else { continue }
            let file = opfURL.deletingLastPathComponent().appendingPathComponent(href.removingPercentEncoding ?? href)
            guard let data = try? Data(contentsOf: file) else { continue }
            let s = decode(data)
            if let g = groups(#"<body[^>]*>([\s\S]*)</body>"#, in: s, caseInsensitive: true) { body += g[1] + "\n" }
        }
        body = body.replacingOccurrences(of: #"<svg[\s\S]*?</svg>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<img\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw TextError(L("txt.noText")) }
        return "<html><head><meta charset=\"utf-8\"></head><body>" + body + "</body></html>"
    }

    private static func inlineXHTML(_ runs: [TRun]) -> String {
        var s = ""
        for r in runs {
            var t = escapeXML(r.text)
            if r.code { t = "<code>" + t + "</code>" }
            if r.bold { t = "<b>" + t + "</b>" }
            if r.italic { t = "<i>" + t + "</i>" }
            if let l = r.link, !l.isEmpty { t = "<a href=\"" + escapeXML(l).replacingOccurrences(of: "\"", with: "&quot;") + "\">" + t + "</a>" }
            s += t
        }
        return s
    }

    static func writeEPUB(_ blocks: [TBlock], title: String, to out: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("txtconv-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: work.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let t = escapeXML(title)

        try "application/epub+zip".write(to: work.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)
        try """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """.write(to: work.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
        let stamp = ISO8601DateFormatter().string(from: Date())
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">urn:uuid:\(UUID().uuidString)</dc:identifier><dc:title>\(t)</dc:title><dc:language>ru</dc:language><meta property="dcterms:modified">\(stamp)</meta></metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="c1"/></spine>
        </package>
        """.write(to: work.appendingPathComponent("OEBPS/content.opf"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>\(t)</title></head><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">\(t)</a></li></ol></nav></body></html>
        """.write(to: work.appendingPathComponent("OEBPS/nav.xhtml"), atomically: true, encoding: .utf8)

        var body = ""
        for b in blocks {
            switch b.level {
            case 1...3: body += "<h\(b.level)>" + inlineXHTML(b.runs) + "</h\(b.level)>\n"
            case -1: body += "<p>• " + inlineXHTML(b.runs) + "</p>\n"
            default: body += "<p>" + inlineXHTML(b.runs) + "</p>\n"
            }
        }
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(t)</title></head><body>
        \(body)</body></html>
        """.write(to: work.appendingPathComponent("OEBPS/chapter.xhtml"), atomically: true, encoding: .utf8)

        try? fm.removeItem(at: out)
        guard runTool("/usr/bin/zip", ["-X", "-0", out.path, "mimetype"], cwd: work) == 0,
              runTool("/usr/bin/zip", ["-X", "-9", "-r", out.path, "META-INF", "OEBPS"], cwd: work) == 0 else {
            throw TextError(L("txt.zipFail"))
        }
    }
}

// MARK: - Очередь

struct TextJob: Identifiable {
    let id = UUID()
    let input: URL
    let inputSize: Int64
    var state: JobState = .waiting
}

final class TextConverter: ObservableObject {
    static let shared = TextConverter()

    @Published var jobs: [TextJob] = []
    @Published private(set) var isRunning = false
    @Published var format: TextFormat { didSet { UserDefaults.standard.set(format.rawValue, forKey: "txt.format") } }
    @Published var ocr: Bool { didSet { UserDefaults.standard.set(ocr, forKey: "txt.ocr") } }
    @Published var outputDir: URL? {
        didSet {
            if let p = outputDir?.path { UserDefaults.standard.set(p, forKey: "txt.outDir") }
            else { UserDefaults.standard.removeObject(forKey: "txt.outDir") }
        }
    }

    private let lock = NSLock()
    private var stopRequested = false
    private var currentTemp: URL?
    private var convertedInRun = 0

    init() {
        let d = UserDefaults.standard
        format = TextFormat(rawValue: d.string(forKey: "txt.format") ?? "") ?? .docx
        ocr = d.object(forKey: "txt.ocr") as? Bool ?? true
        outputDir = d.string(forKey: "txt.outDir").map { URL(fileURLWithPath: $0) }
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopRequested }
    private func setStopped(_ v: Bool) { lock.lock(); stopRequested = v; lock.unlock() }

    var hasWaiting: Bool { jobs.contains { $0.state == .waiting } }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }
    var totalsText: String { queueTotals(jobs.map { ($0.inputSize, $0.state) }) }

    func add(_ urls: [URL]) {
        let files = collectFiles(urls, accept: isTextJobFile).filter(isTextJobFile)
        for f in files {
            let same = f.standardizedFileURL
            if jobs.contains(where: { $0.input.standardizedFileURL == same && !$0.state.isFinished }) { continue }
            jobs.append(TextJob(input: f, inputSize: fileSize(f)))
        }
    }

    func remove(_ id: UUID) { jobs.removeAll { $0.id == id && !$0.state.isRunning } }
    func retry(_ id: UUID) { if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state.canRetry { jobs[i].state = .waiting } }
    func clearFinished() { jobs.removeAll { $0.state.isFinished } }
    /// Очищает окно: убирает всё, кроме файла, который конвертируется прямо сейчас
    func clearAll() { jobs.removeAll { !$0.state.isRunning } }

    func start() {
        guard !isRunning else { return }
        setStopped(false)
        convertedInRun = 0
        isRunning = true
        next()
    }

    func stop() { setStopped(true) }

    func abortForQuit() {
        setStopped(true)
        if let t = currentTemp { try? FileManager.default.removeItem(at: t) }
    }

    private func setProgress(_ id: UUID, _ v: Double) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state.isRunning else { return }
        jobs[i].state = .running(v)
    }

    private func finish(_ id: UUID, _ state: JobState) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].state = state }
        next()
    }

    private func next() {
        guard !isStopped, let i = jobs.firstIndex(where: { $0.state == .waiting }) else {
            let finishedNormally = !isStopped && convertedInRun > 0
            isRunning = false
            currentTemp = nil
            if finishedNormally {
                NSSound(named: NSSound.Name("Glass"))?.play()
                NSApp.requestUserAttention(.informationalRequest)
            }
            return
        }
        jobs[i].state = .running(-1)
        let job = jobs[i]
        let fmt = format
        let useOCR = ocr
        let dir = outputDir ?? defaultOutputDir(for: job.input)
        let id = job.id

        if TextFormat.from(job.input) == fmt {
            finish(id, .failed(L("txt.sameFormat")))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<TextSource, Error> = Result {
                try TextEngine.prepare(job.input, ocr: useOCR,
                                       progress: { p in DispatchQueue.main.async { self.setProgress(id, p) } },
                                       cancelled: { self.isStopped })
            }
            DispatchQueue.main.async { self.build(job, result, fmt, dir) }
        }
    }

    /// Сборка и запись результата — в главном потоке (импорт HTML в оформленный текст требует его)
    private func build(_ job: TextJob, _ result: Result<TextSource, Error>, _ fmt: TextFormat, _ dir: URL) {
        if isStopped { finish(job.id, .cancelled); return }
        let state: JobState
        switch result {
        case .failure(let e):
            state = .failed(e.localizedDescription)
        case .success(let src):
            let base = job.input.deletingPathExtension().lastPathComponent
            let output = Self.uniqueURL(dir: dir, base: base, ext: fmt.ext)
            let temp = dir.appendingPathComponent("." + output.deletingPathExtension().lastPathComponent + ".partial." + fmt.ext)
            try? FileManager.default.removeItem(at: temp)
            currentTemp = temp
            do {
                let a = try TextEngine.attributed(from: src)
                try TextEngine.export(a, as: fmt, to: temp, title: base)
                try FileManager.default.moveItem(at: temp, to: output)
                state = .done(output: output, size: fileSize(output))
                convertedInRun += 1
            } catch {
                try? FileManager.default.removeItem(at: temp)
                state = .failed(error.localizedDescription)
            }
            currentTemp = nil
        }
        finish(job.id, state)
    }

    private static func uniqueURL(dir: URL, base: String, ext: String) -> URL {
        var url = dir.appendingPathComponent(base + "." + ext)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}

// MARK: - Интерфейс

struct TextView: View {
    @ObservedObject var c = TextConverter.shared
    @State private var targeted = false

    var body: some View {
        SectionPage {
            VStack(alignment: .leading, spacing: 9) {
                OptionRow(L("common.format")) {
                    Picker("", selection: $c.format) {
                        ForEach(TextFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                }
                OptionRow("") { HintText(L("txt.hint")) }
                OptionRow("OCR") {
                    Toggle(L("txt.ocr"), isOn: $c.ocr)
                }
                OptionRow("") { HintText(L("txt.ocrHint")) }
                OptionRow(L("common.saveTo")) {
                    FolderRow(path: outputFolderLabel(explicit: c.outputDir, inputs: c.jobs.map { $0.input }),
                              placeholder: L(c.jobs.isEmpty ? "common.nextToOriginal" : "common.nextToEach"),
                              onChoose: { if let u = chooseFolder() { c.outputDir = u } },
                              onReset: c.outputDir == nil ? nil : { c.outputDir = nil })
                }
            }
            .disabled(c.isRunning)
        } content: {
            if c.jobs.isEmpty {
                DropZone(icon: "doc.text", title: L("txt.dropTitle"), subtitle: L("txt.dropSub"),
                         targeted: targeted) { c.add(chooseMediaFiles(prompt: L("common.add"))) }
            } else {
                List {
                    ForEach(c.jobs) { job in
                        JobRow(input: job.input, inputSize: job.inputSize, duration: nil, state: job.state,
                               onRetry: { c.retry(job.id) }, onRemove: { c.remove(job.id) })
                    }
                }
            }
        } bottom: {
            HStack {
                Button(L("common.add")) { c.add(chooseMediaFiles(prompt: L("common.add"))) }
                Button(L("common.clearFinished")) { c.clearFinished() }.disabled(!c.hasFinished)
                Button(L("common.clearAll")) { c.clearAll() }.disabled(!c.jobs.contains { !$0.state.isRunning })
                Spacer()
                Text(c.totalsText).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if c.isRunning {
                    Button(L("common.stop")) { c.stop() }
                } else {
                    Button(L("common.convert")) { c.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!c.hasWaiting)
                }
            }
        }
        .fileDrop(targeted: $targeted) { c.add($0) }
    }
}

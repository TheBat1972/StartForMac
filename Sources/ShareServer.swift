import Foundation
import Darwin
import UniformTypeIdentifiers

// MARK: - Обмен файлами по сети: веб-сервер и FTP-сервер на одной папке
//
// Выбирается папка, включается сервер — по адресу из окна (или по QR-коду) её открывают с телефона и любого компьютера
// в той же сети: взять файл, положить файл. Сервер работает, пока работает «Пуск», и сам поднимается после его запуска,
// если его не выключили вручную. Серверы написаны на обычных сокетах, без сторонних библиотек.

enum ShareNet {
    static func setup(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var off = 0
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return true }
            while off < data.count {
                let n = send(fd, base + off, data.count - off, 0)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    /// Слушающий сокет на всех адресах Mac; nil, если порт занят
    static func listen(port: Int) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = UInt16(port).bigEndian
        a.sin_addr.s_addr = 0
        let ok = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0, Darwin.listen(fd, 64) == 0 else { close(fd); return nil }
        return fd
    }

    /// Ждёт подключение не дольше timeoutMs; nil — время вышло
    static func acceptWait(_ fd: Int32, timeoutMs: Int32) -> Int32? {
        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&p, 1, timeoutMs) > 0 else { return nil }
        let c = accept(fd, nil, nil)
        return c >= 0 ? c : nil
    }
}

/// Папка, которую отдаём: все пути проверяются, выйти за её пределы (.., ссылки) нельзя, скрытые файлы не видны
struct ShareRoot {
    let root: String

    init?(_ path: String) {
        let r = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: r, isDirectory: &isDir), isDir.boolValue else { return nil }
        root = r
    }

    /// Нормализованный виртуальный путь («/a/b») или nil
    func normalize(_ vpath: String, from base: String = "/") -> String? {
        var comps: [String] = vpath.hasPrefix("/") ? [] : base.split(separator: "/").map(String.init)
        for c in vpath.split(separator: "/") {
            let s = String(c)
            if s == "." { continue }
            if s == ".." { if comps.isEmpty { return nil }; comps.removeLast(); continue }
            if s.hasPrefix(".") { return nil }
            comps.append(s)
        }
        return "/" + comps.joined(separator: "/")
    }

    func real(_ vpath: String) -> String? {
        guard let v = normalize(vpath) else { return nil }
        let full = v == "/" ? root : (root == "/" ? v : root + v)
        let resolved = URL(fileURLWithPath: full).resolvingSymlinksInPath().path
        let prefix = root == "/" ? "/" : root + "/"
        guard resolved == root || resolved.hasPrefix(prefix) else { return nil }
        return full
    }
}

// MARK: - Веб-сервер

final class ShareHTTP {
    private let fd: Int32
    private let root: ShareRoot
    private let password: String
    private let readOnly: Bool
    private var stopped = false
    private let done = DispatchSemaphore(value: 0)
    private let token = UUID().uuidString          // значение cookie после входа по паролю

    init(fd: Int32, root: ShareRoot, password: String, readOnly: Bool) {
        self.fd = fd
        self.root = root
        self.password = password
        self.readOnly = readOnly
    }

    func start() {
        DispatchQueue.global(qos: .utility).async {
            while !self.stopped {
                guard let c = ShareNet.acceptWait(self.fd, timeoutMs: 400) else { continue }
                ShareNet.setup(c)
                DispatchQueue.global(qos: .utility).async { self.handle(c) }
            }
            close(self.fd)
            self.done.signal()
        }
    }

    func stop() {
        stopped = true
        _ = done.wait(timeout: .now() + 2)
    }

    // MARK: запрос

    private struct Request {
        var method = ""
        var path = ""
        var query = ""
        var headers: [String: String] = [:]
        var rest = Data()          // начало тела, которое пришло вместе с заголовками
    }

    private func readRequest(_ c: Int32) -> Request? {
        var data = Data()
        var tmp = [UInt8](repeating: 0, count: 16384)
        let marker = Data("\r\n\r\n".utf8)
        var end: Range<Data.Index>?
        while end == nil {
            let n = recv(c, &tmp, tmp.count, 0)
            if n <= 0 { return nil }
            data.append(contentsOf: tmp[0..<n])
            end = data.range(of: marker)
            if data.count > 65536 && end == nil { return nil }
        }
        guard let e = end else { return nil }
        let head = String(decoding: data[data.startIndex..<e.lowerBound], as: UTF8.self)
        var req = Request()
        req.rest = Data(data[e.upperBound...])
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let first = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard first.count >= 2 else { return nil }
        req.method = first[0].uppercased()
        let target = first[1]
        if let q = target.firstIndex(of: "?") {
            req.path = String(target[..<q])
            req.query = String(target[target.index(after: q)...])
        } else { req.path = target }
        req.path = req.path.removingPercentEncoding ?? req.path
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            req.headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        return req
    }

    private func respond(_ c: Int32, _ status: Int, _ text: String, _ headers: [String: String] = [:], body: Data = Data(), head: Bool = false, length: Int64? = nil) {
        var s = "HTTP/1.1 \(status) \(text)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (k, v) in headers { s += "\(k): \(v)\r\n" }
        s += "Content-Length: \(length ?? Int64(body.count))\r\n\r\n"
        var out = Data(s.utf8)
        if !head { out.append(body) }
        ShareNet.writeAll(c, out)
    }

    private func respondHTML(_ c: Int32, _ status: Int, _ text: String, _ html: String, head: Bool) {
        respond(c, status, text, ["Content-Type": "text/html; charset=utf-8"], body: Data(html.utf8), head: head)
    }

    private func authorized(_ req: Request) -> Bool {
        if password.isEmpty { return true }
        if let ck = req.headers["cookie"], ck.components(separatedBy: ";").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "sfm=" + token }) { return true }
        guard let h = req.headers["authorization"], h.lowercased().hasPrefix("basic "),
              let d = Data(base64Encoded: String(h.dropFirst(6)).trimmingCharacters(in: .whitespaces)),
              let s = String(data: d, encoding: .utf8), let i = s.firstIndex(of: ":") else { return false }
        return String(s[s.index(after: i)...]) == password
    }

    private func handle(_ c: Int32) {
        defer { close(c) }
        guard let req = readRequest(c) else { return }
        if req.method == "POST" && req.path == "/__login" && !password.isEmpty { login(c, req); return }
        guard authorized(req) else {
            if (req.method == "GET" || req.method == "HEAD"), (req.headers["accept"] ?? "").contains("text/html") {
                respondHTML(c, 401, "Unauthorized", loginPage(wrong: false), head: req.method == "HEAD")      // браузеру — форма с одним паролем
            } else {
                respond(c, 401, "Unauthorized", ["WWW-Authenticate": "Basic realm=\"Start - any user name, password only\"", "Content-Type": "text/plain; charset=utf-8"],
                        body: Data(T("Нужен пароль").utf8))      // curl, FTP-клиент «Пуска» и скрипты — обычная авторизация
            }
            return
        }
        switch req.method {
        case "GET", "HEAD": serve(c, req, head: req.method == "HEAD")
        case "PUT": put(c, req)
        case "DELETE": remove(c, req)
        case "MKCOL": makeDir(c, req)
        case "MOVE": move(c, req)
        default: respond(c, 405, "Method Not Allowed", ["Allow": "GET, HEAD, PUT, DELETE, MKCOL, MOVE"])
        }
    }

    // MARK: отдача

    private func serve(_ c: Int32, _ req: Request, head: Bool) {
        guard let real = root.real(req.path) else {
            respondHTML(c, 404, "Not Found", page(T("Не найдено"), "<p>" + esc(T("Такого файла или папки нет")) + "</p>", writable: false), head: head)
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real, isDirectory: &isDir) else {
            respondHTML(c, 404, "Not Found", page(T("Не найдено"), "<p>" + esc(T("Такого файла или папки нет")) + "</p>", writable: false), head: head)
            return
        }
        if isDir.boolValue {
            if !req.path.hasSuffix("/") {
                respond(c, 301, "Moved Permanently", ["Location": (req.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? req.path) + "/"])
                return
            }
            respondHTML(c, 200, "OK", listing(real: real, vpath: root.normalize(req.path) ?? "/"), head: head)
            return
        }
        sendFile(c, req, real, head: head)
    }

    private func sendFile(_ c: Int32, _ req: Request, _ path: String, head: Bool) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let total = (attrs[.size] as? NSNumber)?.int64Value,
              let fh = FileHandle(forReadingAtPath: path) else {
            respond(c, 403, "Forbidden", ["Content-Type": "text/plain; charset=utf-8"], body: Data(T("Нет доступа").utf8))
            return
        }
        defer { try? fh.close() }
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        var headers: [String: String] = ["Content-Type": mime, "Accept-Ranges": "bytes"]
        if req.query.contains("dl=1") {
            let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            headers["Content-Disposition"] = "attachment; filename*=UTF-8''" + enc
        }
        var start: Int64 = 0
        var end = total - 1
        var status = 200
        var text = "OK"
        if let r = req.headers["range"], r.lowercased().hasPrefix("bytes="), !r.contains(",") {
            let parts = r.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 {
                if let a = Int64(parts[0]) {
                    start = a
                    if let b = Int64(parts[1]) { end = min(b, total - 1) }
                } else if let n = Int64(parts[1]) {          // «последние n байт»
                    start = max(0, total - n)
                }
                if start > end || start >= total {
                    respond(c, 416, "Range Not Satisfiable", ["Content-Range": "bytes */\(total)"])
                    return
                }
                status = 206
                text = "Partial Content"
                headers["Content-Range"] = "bytes \(start)-\(end)/\(total)"
            }
        }
        let length = total == 0 ? 0 : end - start + 1
        var s = "HTTP/1.1 \(status) \(text)\r\nConnection: close\r\nContent-Length: \(length)\r\n"
        for (k, v) in headers { s += "\(k): \(v)\r\n" }
        s += "\r\n"
        guard ShareNet.writeAll(c, Data(s.utf8)), !head, length > 0 else { return }
        try? fh.seek(toOffset: UInt64(start))
        var left = length
        while left > 0 {
            guard let chunk = try? fh.read(upToCount: Int(min(262_144, left))), !chunk.isEmpty else { break }
            if !ShareNet.writeAll(c, chunk) { break }
            left -= Int64(chunk.count)
        }
    }

    // MARK: вход по паролю (форма для браузера)

    private func login(_ c: Int32, _ req: Request) {
        guard let len = req.headers["content-length"].flatMap({ Int($0) }), len >= 0, len <= 4096 else { respond(c, 400, "Bad Request"); return }
        var body = req.rest
        var tmp = [UInt8](repeating: 0, count: 4096)
        while body.count < len {
            let n = recv(c, &tmp, min(tmp.count, len - body.count), 0)
            if n <= 0 { return }
            body.append(contentsOf: tmp[0..<n])
        }
        var given = ""
        for pair in String(decoding: body, as: UTF8.self).components(separatedBy: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if kv.count == 2, kv[0] == "password" {
                let v = kv[1].replacingOccurrences(of: "+", with: " ")
                given = v.removingPercentEncoding ?? v
            }
        }
        if given == password {
            respond(c, 303, "See Other", ["Location": "/", "Set-Cookie": "sfm=\(token); Path=/; HttpOnly; SameSite=Lax"])
        } else {
            sleep(1)
            respondHTML(c, 401, "Unauthorized", loginPage(wrong: true), head: false)
        }
    }

    private func loginPage(wrong: Bool) -> String {
        let err = wrong ? "<p class=\"e\">" + esc(T("Неверный пароль")) + "</p>" : ""
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(esc(T("Нужен пароль")))</title>
        <style>body{font:16px -apple-system,Helvetica,Arial,sans-serif;background:#f4f4f6;color:#1d1d1f;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}
        form{background:#fff;padding:28px;border-radius:14px;box-shadow:0 2px 12px #0002;width:min(320px,86vw)}
        input{width:100%;box-sizing:border-box;padding:10px;font-size:16px;margin:12px 0;border:1px solid #bbb;border-radius:8px}
        button{width:100%;padding:10px;font-size:16px;border:0;border-radius:8px;background:#0a84ff;color:#fff}
        .e{color:#d00;margin:0}
        @media(prefers-color-scheme:dark){body{background:#1c1c1e;color:#eee}form{background:#2c2c2e}input{background:#1c1c1e;color:#eee;border-color:#555}}</style></head>
        <body><form method="post" action="/__login"><b>\(esc(T("Введите пароль")))</b>
        \(err)
        <input type="password" name="password" autofocus autocomplete="current-password">
        <button type="submit">\(esc(T("Войти")))</button></form></body></html>
        """
    }

    // MARK: удаление, новая папка, переименование (DELETE, MKCOL, MOVE)

    private func writeAllowed(_ c: Int32) -> Bool {
        if readOnly { respond(c, 403, "Forbidden", ["Content-Type": "text/plain; charset=utf-8"], body: Data(T("Загрузка отключена").utf8)); return false }
        return true
    }

    private func remove(_ c: Int32, _ req: Request) {
        guard writeAllowed(c) else { return }
        guard let v = root.normalize(req.path), v != "/", let r = root.real(v) else { respond(c, 404, "Not Found"); return }
        if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: r), resultingItemURL: nil)) != nil { respond(c, 204, "No Content") }
        else { respond(c, 500, "Internal Server Error") }
    }

    private func makeDir(_ c: Int32, _ req: Request) {
        guard writeAllowed(c) else { return }
        guard let v = root.normalize(req.path), v != "/" else { respond(c, 400, "Bad Request"); return }
        let parentV = (v as NSString).deletingLastPathComponent
        guard let dir = root.real(parentV.isEmpty ? "/" : parentV) else { respond(c, 409, "Conflict"); return }
        let dest = dir + "/" + (v as NSString).lastPathComponent
        if FileManager.default.fileExists(atPath: dest) { respond(c, 405, "Method Not Allowed"); return }
        if (try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: false)) != nil { respond(c, 201, "Created") }
        else { respond(c, 409, "Conflict") }
    }

    private func move(_ c: Int32, _ req: Request) {
        guard writeAllowed(c) else { return }
        guard let v = root.normalize(req.path), v != "/", let from = root.real(v) else { respond(c, 404, "Not Found"); return }
        guard var dst = req.headers["destination"] else { respond(c, 400, "Bad Request"); return }
        if let r = dst.range(of: "://") {
            let rest = dst[r.upperBound...]
            dst = rest.firstIndex(of: "/").map { String(rest[$0...]) } ?? "/"
        }
        if let q = dst.firstIndex(of: "?") { dst = String(dst[..<q]) }
        dst = dst.removingPercentEncoding ?? dst
        guard let dv = root.normalize(dst), dv != "/" else { respond(c, 400, "Bad Request"); return }
        let parentV = (dv as NSString).deletingLastPathComponent
        guard let dir = root.real(parentV.isEmpty ? "/" : parentV) else { respond(c, 409, "Conflict"); return }
        let dest = dir + "/" + (dv as NSString).lastPathComponent
        if FileManager.default.fileExists(atPath: dest) { respond(c, 412, "Precondition Failed"); return }
        if (try? FileManager.default.moveItem(atPath: from, toPath: dest)) != nil { respond(c, 201, "Created") }
        else { respond(c, 500, "Internal Server Error") }
    }

    // MARK: загрузка (PUT)

    private func put(_ c: Int32, _ req: Request) {
        if readOnly { respond(c, 403, "Forbidden", ["Content-Type": "text/plain; charset=utf-8"], body: Data(T("Загрузка отключена").utf8)); return }
        guard let len = req.headers["content-length"].flatMap({ Int64($0) }), len >= 0 else {
            respond(c, 411, "Length Required"); return
        }
        guard !req.path.hasSuffix("/"), let v = root.normalize(req.path), v != "/" else { respond(c, 400, "Bad Request"); return }
        let name = (v as NSString).lastPathComponent
        let parentV = (v as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        guard let dir = root.real(parentV.isEmpty ? "/" : parentV),
              FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { respond(c, 404, "Not Found"); return }
        // имя не затирает существующий файл: «имя (1).ext»
        var dest = dir + "/" + name
        if FileManager.default.fileExists(atPath: dest) {
            let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            var n = 1
            repeat {
                dest = dir + "/" + base + " (\(n))" + (ext.isEmpty ? "" : "." + ext)
                n += 1
            } while FileManager.default.fileExists(atPath: dest)
        }
        let tmp = dir + "/.upload-" + UUID().uuidString
        guard FileManager.default.createFile(atPath: tmp, contents: nil), let fh = FileHandle(forWritingAtPath: tmp) else {
            respond(c, 500, "Internal Server Error"); return
        }
        var got: Int64 = 0
        var ok = true
        if !req.rest.isEmpty {
            let part = req.rest.prefix(Int(min(Int64(req.rest.count), len)))
            fh.write(Data(part))
            got += Int64(part.count)
        }
        var tmpBuf = [UInt8](repeating: 0, count: 262_144)
        while got < len {
            let n = recv(c, &tmpBuf, Int(min(Int64(tmpBuf.count), len - got)), 0)
            if n <= 0 { ok = false; break }
            fh.write(Data(tmpBuf[0..<n]))
            got += Int64(n)
        }
        try? fh.close()
        if ok, rename(tmp, dest) == 0 {
            respond(c, 201, "Created", ["Content-Type": "text/plain; charset=utf-8"], body: Data("OK".utf8))
        } else {
            try? FileManager.default.removeItem(atPath: tmp)
            if ok { respond(c, 500, "Internal Server Error") }
        }
    }

    // MARK: страница

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func listing(real: String, vpath: String) -> String {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: real)) ?? []).filter { !$0.hasPrefix(".") }
        struct Row { let name: String; let isDir: Bool; let size: Int64; let date: Date? }
        var rows: [Row] = names.map { n in
            let p = real + "/" + n
            var d: ObjCBool = false
            fm.fileExists(atPath: p, isDirectory: &d)
            let a = try? fm.attributesOfItem(atPath: p)
            return Row(name: n, isDir: d.boolValue, size: (a?[.size] as? NSNumber)?.int64Value ?? 0, date: a?[.modificationDate] as? Date)
        }
        rows.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var html = ""
        if vpath != "/" { html += "<tr><td colspan=\"3\"><a href=\"../\">⬆︎ " + esc(T("Вверх")) + "</a></td></tr>" }
        for r in rows {
            let href = (r.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? r.name) + (r.isDir ? "/" : "")
            let link = r.isDir ? "<a href=\"\(href)\">📁 \(esc(r.name))</a>"
                               : "<a href=\"\(href)?dl=1\">📄 \(esc(r.name))</a>"
            let size = r.isDir ? "" : ByteCountFormatter.string(fromByteCount: r.size, countStyle: .file)
            html += "<tr><td>\(link)</td><td class=\"s\">\(size)</td><td class=\"d\">\(r.date.map { df.string(from: $0) } ?? "")</td></tr>"
        }
        if rows.isEmpty { html += "<tr><td colspan=\"3\" style=\"color:#888\">" + esc(T("Папка пуста")) + "</td></tr>" }
        return page(vpath, "<table>" + html + "</table>", writable: !readOnly)
    }

    private func page(_ title: String, _ body: String, writable: Bool) -> String {
        let upload = writable ? """
        <div id="drop"><div>\(esc(T("Перетащите файлы сюда или выберите")))</div>
        <input type="file" id="f" multiple style="margin-top:10px"><div id="st" style="margin-top:8px"></div>
        <progress id="pr" value="0" max="1" hidden></progress></div>
        """ : ""
        let script = writable ? #"""
        (function(){var f=document.getElementById('f'),d=document.getElementById('drop');if(!f)return;
        var st=document.getElementById('st'),pr=document.getElementById('pr');
        function send(list,i){if(i>=list.length){location.reload();return;}
        var file=list[i],x=new XMLHttpRequest();
        st.textContent=file.name+' ('+(i+1)+'/'+list.length+')';pr.hidden=false;pr.value=0;
        x.open('PUT',location.pathname+encodeURIComponent(file.name));
        x.upload.onprogress=function(e){if(e.lengthComputable)pr.value=e.loaded/e.total};
        x.onload=function(){if(x.status>=200&&x.status<300)send(list,i+1);else st.textContent='ERR: '+file.name+' ('+x.status+')'};
        x.onerror=function(){st.textContent='ERR: '+file.name};
        x.send(file);}
        f.onchange=function(){if(f.files.length)send(Array.from(f.files),0)};
        d.ondragover=function(e){e.preventDefault();d.classList.add('over')};
        d.ondragleave=function(){d.classList.remove('over')};
        d.ondrop=function(e){e.preventDefault();d.classList.remove('over');if(e.dataTransfer.files.length)send(Array.from(e.dataTransfer.files),0)};
        })();
        """# : ""
        return #"""
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>
        """# + esc(title) + #"""
        </title><style>
        :root{color-scheme:light dark}
        body{font:16px -apple-system,"Segoe UI",Roboto,sans-serif;margin:0 auto;padding:16px;max-width:900px}
        h1{font-size:20px;word-break:break-all}
        table{width:100%;border-collapse:collapse}
        td{padding:11px 6px;border-bottom:1px solid #8884;word-break:break-all}
        td.s,td.d{color:#888;white-space:nowrap;text-align:right;font-size:14px}
        a{text-decoration:none;color:#0a7aff}
        #drop{border:2px dashed #8886;border-radius:12px;padding:18px;text-align:center;margin:14px 0}
        #drop.over{background:#0a7aff22}
        progress{width:100%;margin-top:8px}
        @media(max-width:600px){td.d{display:none}}
        </style></head><body><h1>
        """# + esc(title) + "</h1>" + upload + body + "<script>" + script + "</script></body></html>"
    }
}

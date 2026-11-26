import Foundation
import Security

// MARK: - Удалённые файловые системы для «Файл менеджера»: FTP, FTPS, SFTP и HTTP
//
// Работу с сетью делает системная программа /usr/bin/curl (она умеет FTP, FTPS, SFTP и HTTP(S)): в «Пуске» нет своего
// сетевого кода, а пароль передаётся curl через стандартный ввод, поэтому не виден в списке процессов.
// Серверы хранятся в настройках приложения, пароли — в связке ключей.

enum RemoteProto: String, Codable, CaseIterable, Identifiable {
    case ftp, ftps, sftp, http, https
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ftp: return "FTP"
        case .ftps: return "FTPS"
        case .sftp: return "SFTP"
        case .http: return "HTTP"
        case .https: return "HTTPS"
        }
    }
    var defaultPort: Int {
        switch self {
        case .ftp, .ftps: return 21
        case .sftp: return 22
        case .http: return 80
        case .https: return 443
        }
    }
    var isHTTP: Bool { self == .http || self == .https }
    /// Запись есть у всех; по HTTP она работает, если сервер принимает PUT, DELETE, MKCOL и MOVE (WebDAV, сервер «Пуска»)
    var writable: Bool { true }
}

struct RemoteServer: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = ""
    var proto: RemoteProto = .ftp
    var host: String = ""
    var port: Int = 21
    var user: String = ""
    var path: String = "/"
    var keyPath: String = ""
    var insecure: Bool = false      // доверять неизвестному ключу или сертификату сервера
}

enum RemoteStore {
    private static let key = "tp.servers"
    static func load() -> [RemoteServer] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let l = try? JSONDecoder().decode([RemoteServer].self, from: d) else { return [] }
        return l
    }
    static func save(_ l: [RemoteServer]) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: key) }
    }
}

enum RemoteKeychain {
    private static let service = "StartForMac.remote"

    private static func base(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
    }
    static func get(_ id: String) -> String? {
        var q = base(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ id: String, _ password: String) {
        SecItemDelete(base(id) as CFDictionary)
        guard !password.isEmpty else { return }
        var q = base(id)
        q[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ id: String) { SecItemDelete(base(id) as CFDictionary) }
}

struct RemoteEntry {
    let name: String
    let isDir: Bool
    let isLink: Bool
    let size: Int64
    let modified: Date?
}

struct RemoteError: LocalizedError {
    let code: Int32
    let stderr: String
    let proto: RemoteProto

    var needsTrust: Bool { code == 60 || code == 51 }

    var errorDescription: String? {
        var s: String
        switch code {
        case 6: s = T("Не удалось найти адрес сервера")
        case 7: s = T("Не удалось подключиться к серверу (проверьте адрес и порт)")
        case 28: s = T("Время ожидания истекло")
        case 67: s = T("Сервер отклонил логин или пароль")
        case 9, 19, 78, 22: s = T("Нет доступа или файл не найден")
        case 60, 51: s = T("Не удалось проверить подлинность сервера")
        case 35, 52, 55, 56: s = T("Соединение прервано")
        case 21, 25: s = T("Сервер не выполнил команду (нет прав или имя занято)")
        default: s = Tf("Ошибка (код %@)", "\(code)")
        }
        let last = stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last(where: { !$0.isEmpty }) ?? ""
        if !last.isEmpty && ![6, 7, 28, 67].contains(code) { s += ": " + String(last.prefix(160)) }
        return s
    }
}

final class RemoteClient {
    let server: RemoteServer
    let password: String

    init(_ s: RemoteServer, password: String) {
        server = s
        self.password = password
    }

    // MARK: адреса

    private var scheme: String {
        switch server.proto {
        case .ftp: return "ftp"
        case .ftps: return server.port == 990 ? "ftps" : "ftp"      // явный TLS идёт через ftp:// и --ssl-reqd
        case .sftp: return "sftp"
        case .http: return "http"
        case .https: return "https"
        }
    }

    static func dirPath(_ p: String) -> String {
        var s = p.hasPrefix("/") ? p : "/" + p
        if !s.hasSuffix("/") { s += "/" }
        return s
    }

    static func parentPath(_ p: String) -> String {
        var comps = p.split(separator: "/").map(String.init)
        if !comps.isEmpty { comps.removeLast() }
        return comps.isEmpty ? "/" : "/" + comps.joined(separator: "/") + "/"
    }

    func url(_ path: String) -> String {
        var host = server.host
        if host.contains(":") && !host.hasPrefix("[") { host = "[" + host + "]" }
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "\(scheme)://\(host):\(server.port)\(enc)"
    }

    // MARK: curl

    private func baseArgs() -> [String] {
        var a = ["-sS", "--globoff", "--connect-timeout", "15", "--speed-limit", "1", "--speed-time", "40"]
        switch server.proto {
        case .ftp, .ftps:
            a.append("--ftp-skip-pasv-ip")
            if server.proto == .ftps && server.port != 990 { a.append("--ssl-reqd") }
        case .sftp:
            if !server.keyPath.isEmpty {
                a += ["--key", server.keyPath]
                if FileManager.default.fileExists(atPath: server.keyPath + ".pub") { a += ["--pubkey", server.keyPath + ".pub"] }
            }
        case .http, .https:
            a += ["-L", "--max-redirs", "5", "-A", NetSpeed.userAgent]
            if !server.user.isEmpty || !password.isEmpty { a.append("--anyauth") }
        }
        if server.insecure { a.append("-k") }
        return a
    }

    private func config() -> Data {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        var user = server.user
        var pw = password
        if user.isEmpty && (server.proto == .ftp || server.proto == .ftps) {
            // без имени — анонимный вход; пароль, если он введён, всё равно отправляем (серверу «Пуска» имя не важно)
            user = "anonymous"
            if pw.isEmpty { pw = "anonymous@" }
        }
        // веб-серверу может быть нужен только пароль (например, «Обмен файлами» «Пуска»): имя тогда пустое
        guard !user.isEmpty || (server.proto.isHTTP && !pw.isEmpty) else { return Data() }
        return Data(("user = \"" + esc(user) + ":" + esc(pw) + "\"\n").utf8)
    }

    @discardableResult
    private func run(_ extra: [String], url: String, output: URL? = nil, input: URL? = nil) -> (Int32, Data, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = ["-K", "-"] + baseArgs() + extra
        if let o = output { args += ["-o", o.path] }
        if let i = input { args += ["-T", i.path] }
        args += ["--url", url]
        p.arguments = args
        let inP = Pipe(), outP = Pipe(), errP = Pipe()
        p.standardInput = inP
        p.standardOutput = outP
        p.standardError = errP
        do { try p.run() } catch { return (-1, Data(), error.localizedDescription) }
        inP.fileHandleForWriting.write(config())
        try? inP.fileHandleForWriting.close()
        var errData = Data()
        let g = DispatchGroup()
        g.enter()
        DispatchQueue.global().async {
            errData = errP.fileHandleForReading.readDataToEndOfFile()
            g.leave()
        }
        let data = outP.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        g.wait()
        return (p.terminationStatus, data, String(decoding: errData, as: UTF8.self))
    }

    private func fail(_ r: (Int32, Data, String)) -> RemoteError {
        RemoteError(code: r.0, stderr: r.2, proto: server.proto)
    }

    // MARK: список

    func list(_ path: String) throws -> [RemoteEntry] {
        let dir = RemoteClient.dirPath(path)
        let r = run([], url: url(dir))
        guard r.0 == 0 else { throw fail(r) }
        let text = String(data: r.1, encoding: .utf8) ?? String(data: r.1, encoding: .isoLatin1) ?? ""
        if server.proto.isHTTP { return RemoteClient.parseHTML(text, dir: dir) }
        var out = RemoteClient.parseLong(text)
        if out.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // сервер отдал не «ls -l», а только имена
            let r2 = run(["--list-only"], url: url(dir))
            if r2.0 == 0 {
                let t2 = String(data: r2.1, encoding: .utf8) ?? ""
                for l in t2.components(separatedBy: .newlines) {
                    let n = l.trimmingCharacters(in: .whitespaces)
                    if n.isEmpty || n == "." || n == ".." { continue }
                    out.append(RemoteEntry(name: n.hasSuffix("/") ? String(n.dropLast()) : n, isDir: n.hasSuffix("/"),
                                           isLink: false, size: 0, modified: nil))
                }
            }
        }
        return out
    }

    // разбор «ls -l» (FTP, SFTP) и «dir» Windows-серверов

    private static let unixRe = try! NSRegularExpression(
        pattern: #"^([\-dlbcps])[rwxsStT\-]{9}[+@.]?\s+\d+\s+\S+(?:\s+\S+)?\s+(\d+)\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4}|\d{1,2}:\d{2})\s+(.+)$"#)
    private static let dosRe = try! NSRegularExpression(
        pattern: #"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})\s*([AaPp][Mm])?\s+(<DIR>|\d+)\s+(.+)$"#)
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func groups(_ re: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func unixDate(_ mon: String, _ day: String, _ yt: String) -> Date? {
        guard let mi = months.firstIndex(of: mon.lowercased()), let d = Int(day) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.month = mi + 1
        c.day = d
        let now = Date()
        if yt.contains(":") {
            let hm = yt.split(separator: ":").compactMap { Int($0) }
            guard hm.count == 2 else { return nil }
            c.hour = hm[0]; c.minute = hm[1]
            c.year = cal.component(.year, from: now)
            if let dt = cal.date(from: c), dt > now.addingTimeInterval(86400) { c.year = (c.year ?? 0) - 1 }
        } else {
            c.year = Int(yt)
        }
        return cal.date(from: c)
    }

    static func parseLong(_ text: String) -> [RemoteEntry] {
        var out: [RemoteEntry] = []
        for line in text.components(separatedBy: .newlines) {
            if let g = groups(unixRe, line), g.count == 6 {
                var name = g[5]
                let type = g[0]
                if type == "l", let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
                if name == "." || name == ".." { continue }
                // ссылка: куда она ведёт, по списку не видно; считаем папкой, если у имени нет расширения
                let isDir = type == "d" || (type == "l" && !name.contains("."))
                out.append(RemoteEntry(name: name, isDir: isDir, isLink: type == "l", size: Int64(g[1]) ?? 0,
                                       modified: unixDate(g[2], g[3], g[4])))
            } else if let g = groups(dosRe, line), g.count == 8 {
                var year = Int(g[2]) ?? 0
                if g[2].count == 2 { year += year >= 70 ? 1900 : 2000 }
                var hour = Int(g[3]) ?? 0
                let ap = g[5].lowercased()
                if ap == "pm" && hour < 12 { hour += 12 }
                if ap == "am" && hour == 12 { hour = 0 }
                var c = DateComponents()
                c.year = year; c.month = Int(g[0]); c.day = Int(g[1]); c.hour = hour; c.minute = Int(g[4])
                let isDir = g[6] == "<DIR>"
                out.append(RemoteEntry(name: g[7], isDir: isDir, isLink: false, size: isDir ? 0 : (Int64(g[6]) ?? 0),
                                       modified: Calendar(identifier: .gregorian).date(from: c)))
            }
        }
        return out
    }

    // разбор HTML-страницы «Index of…» (Apache, nginx и подобные): ссылки, дата и размер рядом

    private static let linkRe = try! NSRegularExpression(
        pattern: #"<a\s+[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let tagRe = try! NSRegularExpression(pattern: #"<[^>]*>"#)
    private static let dateRes: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}"#), "yyyy-MM-dd HH:mm"),
        (try! NSRegularExpression(pattern: #"\d{2}-[A-Za-z]{3}-\d{4}\s+\d{2}:\d{2}"#), "dd-MMM-yyyy HH:mm"),
    ]
    private static let sizeRe = try! NSRegularExpression(pattern: #"(?<![\w.:\-])(\d+(?:\.\d+)?)([KMGT]?)(?![\w.:\-])"#)

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    static func parseHTML(_ html: String, dir: String) -> [RemoteEntry] {
        let ns = html as NSString
        let matches = linkRe.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var out: [RemoteEntry] = []
        var seen = Set<String>()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for m in matches {
            var href = decodeEntities(ns.substring(with: m.range(at: 1)))
            if href.isEmpty || href.hasPrefix("?") || href.hasPrefix("#") || href.hasPrefix("mailto:") || href.hasPrefix("javascript:") { continue }
            if href.contains("://") { continue }
            if let q = href.firstIndex(where: { $0 == "?" || $0 == "#" }) { href = String(href[..<q]) }
            if href.isEmpty { continue }
            href = href.removingPercentEncoding ?? href
            if href.hasPrefix("/") {
                guard href.hasPrefix(dir), href.count > dir.count else { continue }
                href = String(href.dropFirst(dir.count))
            }
            if href.hasPrefix("./") { href = String(href.dropFirst(2)) }
            let isDir = href.hasSuffix("/")
            let name = isDir ? String(href.dropLast()) : href
            if name.isEmpty || name.contains("/") || name == ".." || name == "." { continue }
            if seen.contains(name) { continue }
            seen.insert(name)
            // что написано после ссылки до следующей ссылки или конца строки
            let after = NSRange(location: m.range.location + m.range.length, length: min(240, ns.length - m.range.location - m.range.length))
            var tail = after.length > 0 ? ns.substring(with: after) : ""
            if let r = tail.range(of: "<a ", options: .caseInsensitive) { tail = String(tail[..<r.lowerBound]) }
            if let r = tail.range(of: "\n") { tail = String(tail[..<r.lowerBound]) }
            tail = tagRe.stringByReplacingMatches(in: tail, range: NSRange(location: 0, length: (tail as NSString).length), withTemplate: " ")
            tail = decodeEntities(tail)
            var modified: Date?
            for (re, f) in dateRes {
                let tn = tail as NSString
                if let dm = re.firstMatch(in: tail, range: NSRange(location: 0, length: tn.length)) {
                    fmt.dateFormat = f
                    modified = fmt.date(from: tn.substring(with: dm.range))
                    tail = tn.replacingCharacters(in: dm.range, with: " ")
                    break
                }
            }
            var size: Int64 = 0
            let tn = tail as NSString
            if !isDir, let sm = sizeRe.matches(in: tail, range: NSRange(location: 0, length: tn.length)).last {
                let v = Double(tn.substring(with: sm.range(at: 1))) ?? 0
                let unit = tn.substring(with: sm.range(at: 2))
                let mul: Double = unit == "K" ? 1024 : unit == "M" ? 1_048_576 : unit == "G" ? 1_073_741_824 : unit == "T" ? 1_099_511_627_776 : 1
                size = Int64(v * mul)
            }
            out.append(RemoteEntry(name: name, isDir: isDir, isLink: false, size: size, modified: modified))
        }
        return out
    }

    // MARK: операции

    /// Путь для команд FTP/SFTP, которые идут мимо адреса (-Q)
    private func quotePath(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        if server.proto == .sftp {
            if p == "/~" { p = "." } else if p.hasPrefix("/~/") { p = String(p.dropFirst(3)) }
            let esc = p.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"" + esc + "\""
        }
        if p.hasPrefix("/") { p.removeFirst() }
        return p.isEmpty ? "." : p
    }

    private func quote(_ cmds: [String]) throws {
        guard server.proto.writable else { throw RemoteError(code: 21, stderr: T("HTTP-серверы доступны только для чтения"), proto: server.proto) }
        var extra: [String] = []
        for c in cmds { extra += ["-Q", c] }
        let u: String
        if server.proto == .sftp { extra += ["-o", "/dev/null"]; u = url("/~/") } else { extra.append("-I"); u = url("/") }
        let r = run(extra, url: u)
        guard r.0 == 0 else { throw fail(r) }
    }

    func download(_ path: String, to dest: URL) throws {
        let part = dest.deletingLastPathComponent().appendingPathComponent(dest.lastPathComponent + ".part")
        try? FileManager.default.removeItem(at: part)
        let r = run(["-f"], url: url(path), output: part)
        guard r.0 == 0 else {
            try? FileManager.default.removeItem(at: part)
            throw fail(r)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: part, to: dest)
    }

    func upload(_ file: URL, toDir dir: String, name: String) throws {
        guard server.proto.writable else { throw RemoteError(code: 25, stderr: T("HTTP-серверы доступны только для чтения"), proto: server.proto) }
        let r = run(server.proto.isHTTP ? ["-f"] : [], url: url(RemoteClient.dirPath(dir) + name), input: file)
        guard r.0 == 0 else { throw fail(r) }
    }

    /// Запись по HTTP: PUT/DELETE/MKCOL/MOVE
    private func httpOp(_ method: String, _ path: String, headers: [String] = []) throws {
        var extra = ["-f", "-X", method, "-o", "/dev/null"]
        for h in headers { extra += ["-H", h] }
        let r = run(extra, url: url(path))
        guard r.0 == 0 else { throw fail(r) }
    }

    func mkdir(_ path: String) throws {
        if server.proto.isHTTP { try httpOp("MKCOL", RemoteClient.dirPath(path)); return }
        let q = quotePath(path)
        try quote([server.proto == .sftp ? "mkdir " + q : "MKD " + q])
    }

    func removeFile(_ path: String) throws {
        if server.proto.isHTTP { try httpOp("DELETE", path); return }
        let q = quotePath(path)
        try quote([server.proto == .sftp ? "rm " + q : "DELE " + q])
    }

    func removeDir(_ path: String) throws {
        if server.proto.isHTTP { try httpOp("DELETE", RemoteClient.dirPath(path)); return }
        let q = quotePath(path)
        try quote([server.proto == .sftp ? "rmdir " + q : "RMD " + q])
    }

    /// Папка со всем содержимым; ссылки удаляются как файлы и по ним внутрь не заходим
    func removeTree(_ dirPath: String) throws {
        let d = RemoteClient.dirPath(dirPath)
        if server.proto.isHTTP { try httpOp("DELETE", d); return }
        for e in try list(d) {
            if e.isDir && !e.isLink { try removeTree(d + e.name + "/") } else { try removeFile(d + e.name) }
        }
        try removeDir(d)
    }

    func rename(_ from: String, to: String) throws {
        if server.proto.isHTTP { try httpOp("MOVE", from, headers: ["Destination: " + url(to)]); return }
        let a = quotePath(from), b = quotePath(to)
        if server.proto == .sftp { try quote(["rename " + a + " " + b]) }
        else { try quote(["RNFR " + a, "RNTO " + b]) }
    }
}

import Foundation
import Darwin

// MARK: - FTP-сервер для той же папки (пассивный режим, без шифрования)

final class ShareFTP {
    private let fd: Int32
    let root: ShareRoot
    let password: String
    let readOnly: Bool
    private var stopped = false
    private let done = DispatchSemaphore(value: 0)

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
                DispatchQueue.global(qos: .utility).async { FTPSession(c, self).run() }
            }
            close(self.fd)
            self.done.signal()
        }
    }

    func stop() {
        stopped = true
        _ = done.wait(timeout: .now() + 2)
    }
}

private final class FTPSession {
    let c: Int32
    let srv: ShareFTP
    var cwd = "/"
    var authed = false
    var pasv: Int32 = -1
    var rnfr: String?
    var rest: Int64 = 0
    var buf = Data()

    init(_ c: Int32, _ srv: ShareFTP) {
        self.c = c
        self.srv = srv
    }

    func reply(_ s: String) { ShareNet.writeAll(c, Data((s + "\r\n").utf8)) }

    func readLine() -> String? {
        while true {
            if let i = buf.firstIndex(of: 10) {
                let line = buf[buf.startIndex..<i]
                buf.removeSubrange(buf.startIndex...i)
                return String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var tmp = [UInt8](repeating: 0, count: 4096)
            let n = recv(c, &tmp, tmp.count, 0)
            if n <= 0 { return nil }
            buf.append(contentsOf: tmp[0..<n])
            if buf.count > 65536 { return nil }
        }
    }

    func run() {
        reply("220 " + T("Сервер файлов «Пуска» готов"))
        while let line = readLine() {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let cmd = parts.first else { continue }
            let arg = parts.count > 1 ? String(parts[1]) : ""
            if !handle(String(cmd).uppercased(), arg) { break }
        }
        closePasv()
        close(c)
    }

    // MARK: пассивный режим

    func closePasv() {
        if pasv >= 0 { close(pasv); pasv = -1 }
    }

    func openPasv() -> (port: Int, ip: [UInt8])? {
        closePasv()
        guard let l = ShareNet.listen(port: 0) else { return nil }
        var a = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(l, $0, &len) } }
        guard ok == 0 else { close(l); return nil }
        let port = Int(UInt16(bigEndian: a.sin_port))
        var la = sockaddr_in()
        var llen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &la) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(c, $0, &llen) } }
        let ip = UInt32(bigEndian: la.sin_addr.s_addr)
        pasv = l
        return (port, [UInt8(ip >> 24 & 255), UInt8(ip >> 16 & 255), UInt8(ip >> 8 & 255), UInt8(ip & 255)])
    }

    func acceptData() -> Int32? {
        guard pasv >= 0 else { return nil }
        let d = ShareNet.acceptWait(pasv, timeoutMs: 15000)
        closePasv()
        if let d = d { ShareNet.setup(d) }
        return d
    }

    // MARK: пути

    func vpath(_ arg: String) -> String? { srv.root.normalize(arg, from: cwd) }

    func real(_ arg: String) -> String? {
        guard let v = vpath(arg) else { return nil }
        return srv.root.real(v)
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func lsLine(_ name: String, _ path: String) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        let isDir = (a?[.type] as? FileAttributeType) == .typeDirectory
        let size = (a?[.size] as? NSNumber)?.int64Value ?? 0
        let date = (a?[.modificationDate] as? Date) ?? Date()
        let recent = abs(date.timeIntervalSinceNow) < 180 * 86400
        FTPSession.dateFmt.dateFormat = recent ? "MMM dd HH:mm" : "MMM dd  yyyy"
        return (isDir ? "drwxr-xr-x" : "-rw-r--r--") + " 1 ftp ftp \(isDir ? 4096 : size) " + FTPSession.dateFmt.string(from: date) + " " + name
    }

    private func mlsdLine(_ name: String, _ path: String) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        let isDir = (a?[.type] as? FileAttributeType) == .typeDirectory
        let size = (a?[.size] as? NSNumber)?.int64Value ?? 0
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        let m = f.string(from: (a?[.modificationDate] as? Date) ?? Date())
        return "type=\(isDir ? "dir" : "file");size=\(size);modify=\(m); " + name
    }

    // MARK: команды

    func handle(_ cmd: String, _ arg: String) -> Bool {
        switch cmd {
        case "USER": reply("331 " + T("Введите пароль")); return true
        case "PASS":
            if srv.password.isEmpty || arg == srv.password { authed = true; reply("230 " + T("Вход выполнен")) }
            else { sleep(1); reply("530 " + T("Неверный пароль")) }
            return true
        case "QUIT": reply("221 Bye"); return false
        case "SYST": reply("215 UNIX Type: L8"); return true
        case "FEAT": reply("211-Features:\r\n PASV\r\n EPSV\r\n SIZE\r\n MDTM\r\n MLSD\r\n REST STREAM\r\n UTF8\r\n211 End"); return true
        case "OPTS", "TYPE", "MODE", "STRU", "NOOP": reply("200 OK"); return true
        case "AUTH", "PBSZ", "PROT": reply("502 " + T("Шифрование не поддерживается")); return true
        default: break
        }
        guard authed else { reply("530 " + T("Сначала войдите")); return true }
        switch cmd {
        case "PWD", "XPWD": reply("257 \"\(cwd)\" is current directory")
        case "CWD", "XCWD", "CDUP", "XCUP":
            let target = (cmd == "CDUP" || cmd == "XCUP") ? ".." : arg
            if let v = vpath(target), let r = srv.root.real(v) {
                var d: ObjCBool = false
                if FileManager.default.fileExists(atPath: r, isDirectory: &d), d.boolValue { cwd = v; reply("250 OK"); break }
            }
            reply("550 " + T("Папка не найдена"))
        case "PASV":
            if let p = openPasv() {
                reply("227 Entering Passive Mode (\(p.ip.map { String($0) }.joined(separator: ",")),\(p.port >> 8),\(p.port & 255))")
            } else { reply("425 " + T("Не удалось открыть порт")) }
        case "EPSV":
            if let p = openPasv() { reply("229 Entering Extended Passive Mode (|||\(p.port)|)") }
            else { reply("425 " + T("Не удалось открыть порт")) }
        case "PORT", "EPRT": reply("502 " + T("Используйте пассивный режим"))
        case "LIST", "NLST", "MLSD": list(cmd, arg)
        case "RETR": retr(arg)
        case "STOR", "APPE": stor(arg, append: cmd == "APPE")
        case "REST": rest = Int64(arg) ?? 0; reply("350 OK")
        case "SIZE":
            if let r = real(arg), let a = try? FileManager.default.attributesOfItem(atPath: r), let n = (a[.size] as? NSNumber)?.int64Value {
                reply("213 \(n)")
            } else { reply("550 " + T("Файл не найден")) }
        case "MDTM":
            if let r = real(arg), let a = try? FileManager.default.attributesOfItem(atPath: r), let d = a[.modificationDate] as? Date {
                let f = DateFormatter()
                f.dateFormat = "yyyyMMddHHmmss"
                f.timeZone = TimeZone(identifier: "UTC")
                reply("213 " + f.string(from: d))
            } else { reply("550 " + T("Файл не найден")) }
        case "DELE", "RMD", "XRMD":
            guard !srv.readOnly else { reply("550 " + T("Загрузка отключена")); break }
            if let r = real(arg), r != srv.root.root, (try? FileManager.default.trashItem(at: URL(fileURLWithPath: r), resultingItemURL: nil)) != nil {
                reply("250 OK")
            } else { reply("550 " + T("Не удалось удалить")) }
        case "MKD", "XMKD":
            guard !srv.readOnly else { reply("550 " + T("Загрузка отключена")); break }
            if let v = vpath(arg), let r = srv.root.real(v),
               (try? FileManager.default.createDirectory(atPath: r, withIntermediateDirectories: false)) != nil {
                reply("257 \"\(v)\" created")
            } else { reply("550 " + T("Не удалось создать папку")) }
        case "RNFR":
            if let r = real(arg), FileManager.default.fileExists(atPath: r), !srv.readOnly { rnfr = r; reply("350 OK") }
            else { reply("550 " + T("Файл не найден")) }
        case "RNTO":
            if let from = rnfr, let to = real(arg), !FileManager.default.fileExists(atPath: to),
               (try? FileManager.default.moveItem(atPath: from, toPath: to)) != nil { reply("250 OK") }
            else { reply("550 " + T("Не удалось переименовать")) }
            rnfr = nil
        default: reply("502 " + T("Команда не поддерживается"))
        }
        return true
    }

    private func list(_ cmd: String, _ argIn: String) {
        var arg = argIn
        while arg.hasPrefix("-") {                       // ключи вроде «-la» игнорируем
            if let sp = arg.firstIndex(of: " ") { arg = String(arg[arg.index(after: sp)...]).trimmingCharacters(in: .whitespaces) } else { arg = "" }
        }
        guard let r = real(arg.isEmpty ? "." : arg) else { reply("550 " + T("Папка не найдена")); return }
        var d: ObjCBool = false
        guard FileManager.default.fileExists(atPath: r, isDirectory: &d) else { reply("550 " + T("Папка не найдена")); return }
        reply("150 " + T("Список папки"))
        guard let dc = acceptData() else { reply("425 " + T("Не удалось открыть соединение для данных")); return }
        var names: [(String, String)] = []
        if d.boolValue {
            let items = ((try? FileManager.default.contentsOfDirectory(atPath: r)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            names = items.map { ($0, r + "/" + $0) }
        } else { names = [((r as NSString).lastPathComponent, r)] }
        var out = ""
        for (n, p) in names {
            switch cmd {
            case "NLST": out += n + "\r\n"
            case "MLSD": out += mlsdLine(n, p) + "\r\n"
            default: out += lsLine(n, p) + "\r\n"
            }
        }
        ShareNet.writeAll(dc, Data(out.utf8))
        close(dc)
        reply("226 OK")
    }

    private func retr(_ arg: String) {
        defer { rest = 0 }
        guard let r = real(arg), let fh = FileHandle(forReadingAtPath: r) else { reply("550 " + T("Файл не найден")); return }
        defer { try? fh.close() }
        reply("150 " + T("Отправляю файл"))
        guard let dc = acceptData() else { reply("425 " + T("Не удалось открыть соединение для данных")); return }
        try? fh.seek(toOffset: UInt64(max(0, rest)))
        var ok = true
        while true {
            guard let chunk = try? fh.read(upToCount: 262_144), !chunk.isEmpty else { break }
            if !ShareNet.writeAll(dc, chunk) { ok = false; break }
        }
        close(dc)
        reply(ok ? "226 OK" : "426 " + T("Передача прервана"))
    }

    private func stor(_ arg: String, append: Bool) {
        guard !srv.readOnly else { reply("550 " + T("Загрузка отключена")); return }
        guard let v = vpath(arg), v != "/", let target = srv.root.real(v) else { reply("550 " + T("Недопустимое имя")); return }
        let dir = (target as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { reply("550 " + T("Папка не найдена")); return }
        let tmp = append ? target : dir + "/.upload-" + UUID().uuidString
        if append { if !FileManager.default.fileExists(atPath: tmp) { FileManager.default.createFile(atPath: tmp, contents: nil) } }
        else { FileManager.default.createFile(atPath: tmp, contents: nil) }
        guard let fh = FileHandle(forWritingAtPath: tmp) else { reply("550 " + T("Не удалось создать файл")); return }
        if append { fh.seekToEndOfFile() }
        reply("150 " + T("Принимаю файл"))
        guard let dc = acceptData() else {
            try? fh.close()
            if !append { try? FileManager.default.removeItem(atPath: tmp) }
            reply("425 " + T("Не удалось открыть соединение для данных"))
            return
        }
        var ok = true
        var tmpBuf = [UInt8](repeating: 0, count: 262_144)
        while true {
            let n = recv(dc, &tmpBuf, tmpBuf.count, 0)
            if n < 0 { ok = false; break }
            if n == 0 { break }
            fh.write(Data(tmpBuf[0..<n]))
        }
        try? fh.close()
        close(dc)
        if ok && !append { ok = rename(tmp, target) == 0 }
        if !ok && !append { try? FileManager.default.removeItem(atPath: tmp) }
        reply(ok ? "226 OK" : "426 " + T("Передача прервана"))
    }
}

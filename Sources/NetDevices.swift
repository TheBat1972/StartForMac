import Foundation
import Darwin

// MARK: - Подробности об устройстве в локальной сети
//
// По IP и MAC выясняется всё, что устройство выдаёт само: имя (обратный DNS / Bonjour и NetBIOS), производитель по MAC
// (таблица Wireshark, скачивается один раз и хранится в Application Support), отклик и TTL (по нему примерно видна система),
// открытые порты, заголовок SSH, сервер и заголовок веб-страницы. Ничего не отправляется наружу, кроме скачивания таблицы.

enum NetDevice {
    // MARK: производитель по MAC

    private static var manuf: [String: String]?
    private static let manufLock = NSLock()
    private static let manufURL = "https://www.wireshark.org/download/automated/data/manuf"

    private static var manufFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StartForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("manuf.txt")
    }

    private static func loadManuf() -> [String: String] {
        manufLock.lock(); defer { manufLock.unlock() }
        if let m = manuf { return m }
        let f = manufFile
        var text = try? String(contentsOf: f, encoding: .utf8)
        let age = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map { -$0.timeIntervalSinceNow } ?? .infinity
        if text == nil || age > 90 * 86400 {
            if let fresh = NetSpeed.get(manufURL, timeout: 25), fresh.count > 100_000 {
                try? fresh.write(to: f, atomically: true, encoding: .utf8)
                text = fresh
            }
        }
        var m: [String: String] = [:]
        for line in (text ?? "").split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let c = line.components(separatedBy: "\t")
            guard c.count >= 2 else { continue }
            var key = c[0].trimmingCharacters(in: .whitespaces).uppercased()
            var bits = 24
            if let slash = key.firstIndex(of: "/") {
                bits = Int(key[key.index(after: slash)...]) ?? 24
                key = String(key[..<slash])
            }
            let hex = key.replacingOccurrences(of: ":", with: "")
            let k = bits == 24 ? String(hex.prefix(6)) : String(hex.prefix(bits / 4)) + "/\(bits)"
            let name = (c.count >= 3 && !c[2].trimmingCharacters(in: .whitespaces).isEmpty) ? c[2] : c[1]
            m[k] = name.trimmingCharacters(in: .whitespaces)
        }
        manuf = m
        return m
    }

    static func vendor(_ mac: String) -> String? {
        let hex = mac.replacingOccurrences(of: ":", with: "").uppercased()
        guard hex.count == 12 else { return nil }
        let m = loadManuf()
        for bits in [36, 28, 24] {
            let k = bits == 24 ? String(hex.prefix(6)) : String(hex.prefix(bits / 4)) + "/\(bits)"
            if let v = m[k] { return v }
        }
        return nil
    }

    /// Второй бит первого байта: адрес «локальный», то есть случайный (частный) — производителя по нему не узнать
    static func isRandomMAC(_ mac: String) -> Bool {
        guard let b = UInt8(mac.prefix(2), radix: 16) else { return false }
        return b & 0x02 != 0
    }

    // MARK: имена

    /// NetBIOS: запрос состояния узла (UDP 137); возвращает (имя компьютера, рабочая группа)
    static func netbios(_ ip: String) -> (String?, String?) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return (nil, nil) }
        defer { close(fd) }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var q: [UInt8] = [0x13, 0x37, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0x20, 0x43, 0x4B]
        q += [UInt8](repeating: 0x41, count: 30)
        q += [0, 0, 0x21, 0, 1]
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET)
        a.sin_port = UInt16(137).bigEndian
        guard inet_pton(AF_INET, ip, &a.sin_addr) == 1 else { return (nil, nil) }
        let sent = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            sendto(fd, q, q.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard sent == q.count else { return (nil, nil) }
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = recv(fd, &buf, buf.count, 0)
        guard n > 57 else { return (nil, nil) }
        let count = Int(buf[56])
        var name: String?, group: String?
        for i in 0..<count {
            let o = 57 + i * 18
            guard o + 18 <= n else { break }
            let raw = String(decoding: buf[o..<(o + 15)], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
            let suffix = buf[o + 15]
            let isGroup = buf[o + 16] & 0x80 != 0
            if suffix == 0 && !raw.isEmpty {
                if isGroup { if group == nil { group = raw } } else if name == nil { name = raw }
            }
        }
        return (name, group)
    }

    // MARK: сеть

    static func gateway() -> String {
        for l in NetSpeed.capture("/sbin/route", ["-n", "get", "default"]).split(separator: "\n") {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("gateway:") { return t.dropFirst(8).trimmingCharacters(in: .whitespaces) }
        }
        return ""
    }

    /// (минимальный отклик в мс, TTL)
    static func ping(_ ip: String) -> (Double?, Int?) {
        let out = NetSpeed.capture("/sbin/ping", ["-c", "2", "-W", "800", ip])
        var best: Double?
        var ttl: Int?
        for l in out.split(separator: "\n") {
            guard l.contains("ttl=") else { continue }
            if let r = l.range(of: "ttl="), let v = Int(l[r.upperBound...].prefix(while: { $0.isNumber })) { ttl = v }
            if let r = l.range(of: "time="), let v = Double(l[r.upperBound...].prefix(while: { $0.isNumber || $0 == "." })) {
                best = min(best ?? v, v)
            }
        }
        return (best, ttl)
    }

    static func systemByTTL(_ ttl: Int) -> String {
        if ttl <= 64 { return T("Linux / macOS / iOS / Android или сетевое устройство") }
        if ttl <= 128 { return T("Windows") }
        return T("сетевое оборудование (роутер, коммутатор)")
    }

    static let portNames: [(UInt16, String)] = [
        (21, "FTP"), (22, "SSH"), (23, "Telnet"), (25, "SMTP"), (53, "DNS"), (80, "HTTP"), (111, "RPC"), (139, "NetBIOS"),
        (443, "HTTPS"), (445, "SMB"), (515, "LPD"), (548, "AFP"), (554, "RTSP"), (631, "IPP"), (1883, "MQTT"),
        (3389, "RDP"), (5000, "UPnP/AirPlay"), (5357, "WSDAPI"), (5900, "VNC"), (7000, "AirPlay"), (8000, "HTTP-alt"),
        (8008, "Cast"), (8009, "Cast"), (8080, "HTTP-proxy"), (8291, "MikroTik"), (8443, "HTTPS-alt"), (9100, "Printer"),
        (32400, "Plex"), (34567, "DVR"), (37777, "Dahua"), (62078, "iPhone sync")
    ]

    static func openPorts(_ ip: String) -> [UInt16] {
        let lock = NSLock()
        var open: [UInt16] = []
        let g = DispatchGroup()
        for (p, _) in portNames {
            g.enter()
            DispatchQueue.global(qos: .utility).async {
                if NetProbe.tcp(host: ip, port: p, timeout: 0.9).0 == T("открыт") {
                    lock.lock(); open.append(p); lock.unlock()
                }
                g.leave()
            }
        }
        g.wait()
        return open.sorted()
    }

    /// Первая строка, которую сервер присылает сам (у SSH — версия и ОС)
    static func banner(_ ip: String, _ port: UInt16) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &a.sin_addr) == 1 else { return nil }
        let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        if r != 0 {
            guard errno == EINPROGRESS else { return nil }
            var w = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&w, 1, 1000) > 0 else { return nil }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            guard err == 0 else { return nil }
        }
        var rd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&rd, 1, 1200) > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: 256)
        let n = read(fd, &buf, 255)
        guard n > 0 else { return nil }
        let s = String(decoding: buf[0..<n], as: UTF8.self)
        return s.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).first.map(String.init)
    }

    /// Веб-страница устройства: сервер, область авторизации и заголовок
    static func web(_ ip: String, _ port: UInt16, tls: Bool) -> String? {
        let out = NetSpeed.capture("/usr/bin/curl", ["-s", "-i", "-k", "-m", "3", "--max-filesize", "300000",
                                                     "\(tls ? "https" : "http")://\(ip):\(port)/"])
        guard !out.isEmpty else { return nil }
        var server = "", realm = "", title = ""
        let parts = out.components(separatedBy: "\r\n\r\n")
        for l in (parts.first ?? "").components(separatedBy: "\r\n") {
            let low = l.lowercased()
            if low.hasPrefix("server:") { server = l.dropFirst(7).trimmingCharacters(in: .whitespaces) }
            if low.hasPrefix("www-authenticate:"), let r = l.range(of: "realm=") {
                realm = l[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
        }
        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
        if let re = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let m = re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)), let r = Range(m.range(at: 1), in: body) {
            title = body[r].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        }
        var bits: [String] = []
        if !server.isEmpty { bits.append(T("сервер") + " " + server) }
        if !realm.isEmpty { bits.append(T("авторизация") + " «" + realm + "»") }
        if !title.isEmpty { bits.append(T("заголовок") + " «" + String(title.prefix(80)) + "»") }
        return bits.isEmpty ? nil : bits.joined(separator: ", ")
    }

    // MARK: итог по устройству

    static func details(ip: String, mac: String, isSelf: Bool, gateway: String) -> String {
        var rows: [(String, String)] = []
        func add(_ k: String, _ v: String?) { if let v = v, !v.isEmpty { rows.append((k, v)) } }

        var names: [String] = []
        if isSelf, let n = Host.current().localizedName { names.append(n) }
        if let h = NetProbe.reverse(ip), !h.isEmpty, h != ip { names.append(h) }
        let (nb, group) = netbios(ip)
        if let nb = nb, !names.contains(where: { $0.lowercased().hasPrefix(nb.lowercased()) }) { names.append(nb + " (NetBIOS)") }
        add(T("Имя"), names.joined(separator: " · "))
        add(T("Рабочая группа"), group)

        if isRandomMAC(mac) {
            add(T("Производитель"), T("не определить: адрес случайный (частный), так делают iPhone, Android и Windows"))
        } else {
            add(T("Производитель"), vendor(mac) ?? T("нет в таблице"))
        }

        var ms: Double?
        var ttl: Int?
        if !isSelf { (ms, ttl) = ping(ip) }
        if !isSelf {
            if let ms = ms {
                add(T("Отклик"), String(format: "%.1f", ms).replacingOccurrences(of: ".", with: ",") + " " + T("мс")
                    + (ttl.map { ", TTL \($0)" } ?? ""))
            } else {
                add(T("Отклик"), T("на ping не отвечает (устройство спит или закрыто файрволом)"))
            }
            if let t = ttl { add(T("Система по TTL"), systemByTTL(t)) }
        }

        let open = openPorts(ip)
        if !open.isEmpty {
            add(T("Открытые порты"), open.map { p in
                "\(p) " + (portNames.first(where: { $0.0 == p })?.1 ?? "")
            }.joined(separator: ", "))
        } else if !isSelf {
            add(T("Открытые порты"), T("из частых не найдено"))
        }
        if open.contains(22), let b = banner(ip, 22) { add(T("SSH"), String(b.prefix(100))) }
        for (p, tls) in [(UInt16(80), false), (443, true), (8080, false)] where open.contains(p) {
            if let w = web(ip, p, tls: tls) { add(T("Веб-страница") + " :\(p)", w) }
        }

        var guess: [String] = []
        if ip == gateway { guess.append(T("роутер (шлюз сети)")) }
        if open.contains(62078) { guess.append(T("iPhone / iPad")) }
        if open.contains(9100) || open.contains(631) || open.contains(515) { guess.append(T("принтер")) }
        if open.contains(554) || open.contains(37777) || open.contains(34567) { guess.append(T("камера или видеорегистратор")) }
        if open.contains(8009) || open.contains(8008) { guess.append(T("Chromecast / Google TV")) }
        if open.contains(8291) { guess.append("MikroTik") }
        if open.contains(3389) { guess.append(T("Windows (удалённый рабочий стол)")) }
        if open.contains(548) || open.contains(7000) { guess.append(T("устройство Apple или NAS")) }
        if (open.contains(445) || open.contains(139)) && !open.contains(3389) { guess.append(T("компьютер или NAS с общими папками")) }
        if open.contains(32400) { guess.append("Plex") }
        if open.contains(1883) { guess.append(T("умный дом (MQTT)")) }
        if isSelf { guess.append(T("этот Mac")) }
        add(T("Похоже на"), guess.joined(separator: ", "))

        return rows.map { "    " + $0.0 + ": " + $0.1 }.joined(separator: "\n") + "\n"
    }
}

import SwiftUI
import AppKit
import Darwin

// MARK: - Сетевые инструменты
//
// Окно из меню «Инструменты»: свои адреса и внешний IP, ping, трассировка, проверка портов, DNS, открытые порты.
// Ping и трассировку выполняют системные программы /sbin/ping и /usr/sbin/traceroute, порты проверяются обычным
// подключением (TCP), список портов берётся у /usr/sbin/lsof. Внешний IP узнаётся только по кнопке: запрос к api.ipify.org.

final class NetRunner: ObservableObject {
    @Published var output = ""
    @Published var running = false
    private var process: Process?
    private var cancelled = false

    func clear() { output = "" }

    func append(_ s: String) {
        output += s
        if output.count > 200_000 { output = String(output.suffix(150_000)) }
    }

    /// Запускает программу и показывает её вывод по мере появления
    func run(_ path: String, _ args: [String], header: String? = nil) {
        guard !running else { return }
        if let h = header { append("$ \(h)\n") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        cancelled = false
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            let s = String(decoding: d, as: UTF8.self)
            DispatchQueue.main.async { self?.append(s) }
        }
        p.terminationHandler = { [weak self] pr in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !rest.isEmpty { self.append(String(decoding: rest, as: UTF8.self)) }
                if self.cancelled { self.append("\n" + T("Остановлено") + "\n") }
                else if pr.terminationStatus != 0 { self.append("\n" + T("Код завершения") + ": \(pr.terminationStatus)\n") }
                self.running = false
                self.process = nil
            }
        }
        do { try p.run(); process = p; running = true }
        catch { append(T("Не удалось запустить") + ": \(error.localizedDescription)\n") }
    }

    func stop() {
        cancelled = true
        stopWork = true
        if let p = process, p.isRunning { p.terminate() }
    }

    // MARK: собственная работа в фоне (проверка портов, DNS)
    var stopWork = false

    func work(_ job: @escaping (_ emit: @escaping (String) -> Void, _ stopped: @escaping () -> Bool) -> Void) {
        guard !running else { return }
        running = true
        stopWork = false
        DispatchQueue.global(qos: .userInitiated).async {
            job({ s in DispatchQueue.main.async { self.append(s) } }, { self.stopWork })
            DispatchQueue.main.async { self.running = false }
        }
    }
}

enum NetProbe {
    /// Пробует подключиться по TCP; возвращает (результат, миллисекунды)
    static func tcp(host: String, port: UInt16, timeout: Double = 3) -> (String, Int) {
        var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let first = res else {
            return (T("адрес не найден"), 0)
        }
        defer { freeaddrinfo(res) }
        var ai: UnsafeMutablePointer<addrinfo>? = first
        var result = T("нет ответа")
        let t0 = Date()
        while let a = ai {
            let fd = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
            if fd >= 0 {
                let fl = fcntl(fd, F_GETFL)
                _ = fcntl(fd, F_SETFL, fl | O_NONBLOCK)
                var r = connect(fd, a.pointee.ai_addr, a.pointee.ai_addrlen)
                if r != 0 && errno == EINPROGRESS {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let pr = poll(&pfd, 1, Int32(timeout * 1000))
                    if pr > 0 {
                        var err: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
                        if err == 0 { r = 0 } else { errno = err }
                    }
                }
                let e = errno
                close(fd)
                if r == 0 { return (T("открыт"), Int(Date().timeIntervalSince(t0) * 1000)) }
                if e == ECONNREFUSED { result = T("закрыт") }
            }
            ai = a.pointee.ai_next
        }
        return (result, Int(Date().timeIntervalSince(t0) * 1000))
    }

    /// «80, 443, 8000-8010» → [80, 443, 8000…8010]
    static func ports(_ text: String) -> [UInt16] {
        var out: [UInt16] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) {
            let b = part.split(separator: "-").compactMap { UInt16($0) }
            if b.count == 1 { out.append(b[0]) }
            else if b.count == 2, b[0] <= b[1] { out += Array(b[0]...b[1]) }
            if out.count >= 500 { break }
        }
        return Array(out.prefix(500))
    }

    static func localAddresses() -> String {
        var list = ""
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0, let first = ifa else { return "" }
        defer { freeifaddrs(ifa) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            let f = i.pointee
            if let sa = f.ifa_addr, (f.ifa_flags & UInt32(IFF_UP)) != 0, (f.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               sa.pointee.sa_family == UInt8(AF_INET) || sa.pointee.sa_family == UInt8(AF_INET6) {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let addr = String(cString: buf)
                    if !addr.hasPrefix("fe80") {
                        list += String(cString: f.ifa_name).padding(toLength: 8, withPad: " ", startingAt: 0) + addr + "\n"
                    }
                }
            }
            p = f.ifa_next
        }
        return list
    }

    static func lookup(_ name: String) -> [String] {
        var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &res) == 0, let first = res else { return [] }
        defer { freeaddrinfo(res) }
        var out: [String] = []
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let a = p {
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(a.pointee.ai_addr, a.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let s = String(cString: buf)
                if !out.contains(s) { out.append(s) }
            }
            p = a.pointee.ai_next
        }
        return out
    }

    static func dotted(_ v: UInt32) -> String { "\(v >> 24 & 255).\(v >> 16 & 255).\(v >> 8 & 255).\(v & 255)" }

    /// Адрес и маска основной сети (en0, а если её нет — первой подходящей), числами в порядке «как пишется»
    static func primaryIPv4() -> (UInt32, UInt32)? {
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0, let first = ifa else { return nil }
        defer { freeifaddrs(ifa) }
        var best: (String, UInt32, UInt32)?
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            let f = i.pointee
            if let sa = f.ifa_addr, let nm = f.ifa_netmask, sa.pointee.sa_family == UInt8(AF_INET),
               (f.ifa_flags & UInt32(IFF_UP)) != 0, (f.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                let name = String(cString: f.ifa_name)
                let a = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let m = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let private10 = a >> 24 == 10 || a >> 20 == 0xAC1 || a >> 16 == 0xC0A8
                if name == "en0" && private10 { return (a, m) }
                if best == nil && private10 && name.hasPrefix("en") { best = (name, a, m) }
            }
            p = f.ifa_next
        }
        return best.map { ($0.1, $0.2) }
    }

    /// Отправляет по одному пустому UDP-пакету каждому адресу: ядро спрашивает «кто это?» (ARP), и живые устройства попадают в таблицу
    static func poke(base: UInt32, count: Int, stopped: () -> Bool) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var byte: UInt8 = 0
        for k in 1...max(count, 1) {
            if stopped() { return }
            var a = sockaddr_in()
            a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET)
            a.sin_port = UInt16(9).bigEndian
            a.sin_addr.s_addr = (base &+ UInt32(k)).bigEndian
            _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, &byte, 1, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            if k % 32 == 0 { usleep(20_000) }
        }
    }

    struct ArpRow { let ip: UInt32; let mac: String }

    static func arpTable() -> [ArpRow] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        p.arguments = ["-an"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var rows: [ArpRow] = []
        for line in String(decoding: d, as: UTF8.self).split(separator: "\n") {
            guard let a = line.firstIndex(of: "("), let b = line.firstIndex(of: ")"), a < b,
                  let at = line.range(of: " at ") else { continue }
            let ipStr = String(line[line.index(after: a)..<b])
            let rest = line[at.upperBound...]
            let macStr = String(rest.prefix(while: { $0 != " " }))
            guard macStr.contains(":"), !line.contains("incomplete") else { continue }
            var addr = in_addr()
            guard inet_pton(AF_INET, ipStr, &addr) == 1 else { continue }
            // у arp байты MAC печатаются без ведущих нулей: «a:b:c» → «0A:0B:0C»
            let mac = macStr.split(separator: ":").map { $0.count == 1 ? "0" + $0.uppercased() : $0.uppercased() }.joined(separator: ":")
            rows.append(ArpRow(ip: UInt32(bigEndian: addr.s_addr), mac: mac))
        }
        return rows
    }

    /// Магический пакет Wake-on-LAN: 6 байт 0xFF и 16 раз MAC; уходит всем в сети на порты 9 и 7
    static func wake(_ mac: [UInt8]) -> Bool {
        guard mac.count == 6 else { return false }
        var pkt = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { pkt += mac }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var ok = false
        var targets: [UInt32] = [0xFFFFFFFF]
        if let (ip, mask) = primaryIPv4() { targets.append((ip & mask) | ~mask) }
        for t in targets {
            for port in [9, 7] as [UInt16] {
                var a = sockaddr_in()
                a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); a.sin_family = sa_family_t(AF_INET)
                a.sin_port = port.bigEndian; a.sin_addr.s_addr = t.bigEndian
                let n = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, pkt, pkt.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
                if n == pkt.count { ok = true }
            }
        }
        return ok
    }

    static func reverse(_ ip: String) -> String? {
        var a4 = sockaddr_in(); var a6 = sockaddr_in6()
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if inet_pton(AF_INET, ip, &a4.sin_addr) == 1 {
            a4.sin_family = sa_family_t(AF_INET); a4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            let r = withUnsafePointer(to: &a4) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD) } }
            return r == 0 ? String(cString: buf) : nil
        }
        if inet_pton(AF_INET6, ip, &a6.sin6_addr) == 1 {
            a6.sin6_family = sa_family_t(AF_INET6); a6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            let r = withUnsafePointer(to: &a6) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in6>.size), &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD) } }
            return r == 0 ? String(cString: buf) : nil
        }
        return nil
    }
}

/// Вспомогательные запросы: внешний IP, страна и провайдер, маршрут по умолчанию
enum NetSpeed {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func get(_ url: String, timeout: Int = 6) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        p.arguments = ["-s", "-L", "-A", userAgent, "--connect-timeout", String(timeout), "--max-time", String(timeout + 2), url]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let t = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !t.isEmpty ? t : nil
    }

    /// Запускает программу и возвращает её вывод (пустая строка, если не вышло)
    static func capture(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }

    static func isLoopback(_ ip: String) -> Bool { ip.hasPrefix("127.") || ip == "0.0.0.0" || ip == "::1" || ip == "::" }

    static func isIP(_ s: String) -> Bool {
        var a4 = in_addr(), a6 = in6_addr()
        return inet_pton(AF_INET, s, &a4) == 1 || inet_pton(AF_INET6, s, &a6) == 1
    }

    /// Сервисы, которые отвечают «ваш адрес такой-то»: с разных сторон, чтобы увидеть, где трафик идёт через туннель
    static let ipServices: [(name: String, url: String)] = [
        ("ipify.org", "https://api.ipify.org"),
        ("icanhazip.com", "https://icanhazip.com"),
        ("ifconfig.me", "https://ifconfig.me/ip"),
        ("ident.me", "https://ident.me"),
        ("Яндекс", "https://ipv4-internet.yandex.net/api/v0/ip"),
        ("Amazon", "https://checkip.amazonaws.com"),
        ("ipinfo.io", "https://ipinfo.io/ip"),
        ("ip.sb", "https://api.ip.sb/ip"),
    ]

    /// Страна и провайдер по адресу (ipwho.is), одной строкой; пусто, если не удалось
    static func whois(_ ip: String) -> String {
        guard let t = get("https://ipwho.is/" + ip, timeout: 5), let d = t.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["success"] as? Bool) != false else { return "" }
        let country = j["country"] as? String ?? ""
        let isp = (j["connection"] as? [String: Any])?["isp"] as? String ?? ""
        return [country, isp].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Интерфейс и шлюз маршрута по умолчанию («en0 → 192.168.1.1»); utun… в начале значит, что всё идёт через туннель
    static func defaultRoute() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/route")
        p.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var iface = "", gw = ""
        for line in String(decoding: d, as: UTF8.self).split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("interface:") { iface = t.dropFirst(10).trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("gateway:") { gw = t.dropFirst(8).trimmingCharacters(in: .whitespaces) }
        }
        return iface.isEmpty ? "" : iface + (gw.isEmpty ? "" : " → " + gw)
    }
}

/// Вывод с цветом по строкам: зелёный — хорошо, красный — плохо, оранжевый — обратите внимание, серый — команда
struct NetOutputText: View {
    let text: String

    static func color(_ line: String) -> Color? {
        let l = line.lowercased()
        if line.hasPrefix("$ ") { return .secondary }
        if line.hasPrefix(T("Открыто")) {
            // «Открыто: N из M»: зелёный, если хоть один порт открыт, иначе красный
            let n = Int(line.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })) ?? 0
            return n > 0 ? .green : .red
        }
        let bad = [T("Блокирует"), T("закрыт"), T("нет ответа"), T("не удалось"), T("Не удалось"), T("Код завершения"), T("адрес не найден"),
                   T("Не найдено"), T("Нет активной сети"), "http 4", "http 5", "curl ", "timeout", "100.0% packet loss", "unknown host", "cannot resolve"]
        if bad.contains(where: { l.contains($0.lowercased()) }) { return .red }
        let warn = [T("Адреса разные"), T("Остановлено"), "% packet loss"]
        if l.contains("0.0% packet loss") { return .green }
        if warn.contains(where: { l.contains($0.lowercased()) }) { return .orange }
        let good = [T("Всё чисто"), T("открыт"), T("Пакет отправлен"), T("Адрес один"), T("Быстрее всего"), T("Найдено устройств"), T("Мбит/с"), "bytes from", "mbps"]
        if good.contains(where: { l.contains($0.lowercased()) }) { return .green }
        return nil
    }

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        if text.isEmpty || lines.count > 1500 {
            Text(text.isEmpty ? " " : text)
        } else {
            lines.enumerated().reduce(Text("")) { acc, item in
                let (i, line) = item
                let piece = Text(line + (i < lines.count - 1 ? "\n" : ""))
                if let c = Self.color(line) { return acc + piece.foregroundColor(c) }
                return acc + piece
            }
        }
    }
}

enum NetTab: Int, CaseIterable, Identifiable {
    case ip, ping, trace, ports, dns, hosts, whois, conns, lan, wol, wifi
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .ip: return T("Мой IP")
        case .ping: return "Ping"
        case .trace: return T("Трассировка")
        case .ports: return T("Порты")
        case .dns: return "DNS"
        case .hosts: return T("Файл hosts")
        case .whois: return "Whois"
        case .conns: return T("Соединения")
        case .lan: return T("Устройства в сети")
        case .wol: return "Wake-on-LAN"
        case .wifi: return T("Wi-Fi: каналы")
        }
    }
    var icon: String {
        switch self {
        case .ip: return "globe"
        case .ping: return "dot.radiowaves.left.and.right"
        case .trace: return "point.topleft.down.curvedto.point.bottomright.up"
        case .ports: return "door.left.hand.open"
        case .dns: return "magnifyingglass"
        case .hosts: return "doc.text"
        case .whois: return "person.text.rectangle"
        case .conns: return "arrow.left.arrow.right"
        case .lan: return "desktopcomputer"
        case .wol: return "power"
        case .wifi: return "wifi"
        }
    }
}

struct NetToolsView: View {
    @StateObject private var r = NetRunner()
    @AppStorage("net.tab2") private var tabRaw = 0
    @AppStorage("net.host") private var host = "8.8.8.8"
    @AppStorage("net.ports") private var ports = "80, 443, 554"
    @AppStorage("net.count") private var count = 4
    @AppStorage("net.lsof") private var lsofMode = 0
    @AppStorage("net.mac") private var mac = ""

    private var tab: NetTab { NetTab(rawValue: tabRaw) ?? .ip }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(NetTab.allCases) { t in
                    DCSidebarItem(icon: t.icon, title: t.title, selected: t == tab) { tabRaw = t.rawValue; r.clear() }
                }
                Spacer()
            }
            .padding(10).frame(width: 200)
            Divider()
            if tab == .wifi {
                WiFiView().padding(14)
            } else if tab == .hosts {
                HostsView().padding(14)
            } else {
                VStack(spacing: 10) {
                    controls
                    ScrollViewReader { sp in
                        ScrollView {
                            NetOutputText(text: r.output)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                        .onChange(of: r.output) { _ in sp.scrollTo("end") }
                    }
                    HStack {
                        Text(hint).font(.caption).foregroundColor(.secondary).lineLimit(3)
                        Spacer()
                        Button(T("Копировать")) { copyToPasteboard(r.output) }.disabled(r.output.isEmpty)
                        Button(T("Очистить")) { r.clear() }.disabled(r.output.isEmpty || r.running)
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 860, minHeight: 520)
    }

    private var hint: String {
        switch tab {
        case .ip: return T("Внешний IP спрашивается у нескольких сервисов (ipify, icanhazip, ifconfig.me, ident.me, Яндекс), страна и провайдер — у ipwho.is, только когда вы нажмёте кнопку. Если адреса разные, у вас работает туннель или VPN для части трафика.")
        case .ports: return T("Порты: через запятую или диапазоном, например 80, 443, 8000-8010. 554 — RTSP камер, 80 и 8080 — веб-интерфейс.")
        case .conns: return T("Показаны соединения программ вашей учётной записи.")
        case .lan: return T("Ищет устройства в вашей подсети по таблице ARP: включённые устройства отвечают, выключенные и спящие могут не показаться. macOS может спросить доступ к локальной сети.")
        case .wol: return T("Отправляет «магический пакет» всей локальной сети. Устройство должно быть подключено проводом, а в его настройках включён Wake-on-LAN.")
        case .whois: return T("Сведения о владельце домена или адреса.")
        default: return ""
        }
    }

    private var hostField: some View {
        TextField(T("Адрес или имя"), text: $host)
            .textFieldStyle(.roundedBorder).frame(minWidth: 220)
            .onSubmit { go() }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 8) {
            switch tab {
            case .ip:
                Button(T("Мои адреса")) { showLocal() }
                Button(T("Узнать внешние IP")) { external() }.disabled(r.running)
            case .ping:
                hostField
                Picker("", selection: $count) {
                    ForEach([4, 10, 30, 100], id: \.self) { Text("\($0)").tag($0) }
                }.labelsHidden().fixedSize().help(T("Сколько запросов отправить"))
            case .ports:
                hostField
                TextField(T("Порты"), text: $ports).textFieldStyle(.roundedBorder).frame(width: 190).onSubmit { go() }
            case .conns:
                Picker("", selection: $lsofMode) {
                    Text(T("Ждут подключений")).tag(0)
                    Text(T("Установленные")).tag(1)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            case .wol:
                TextField("AA:BB:CC:DD:EE:FF", text: $mac).textFieldStyle(.roundedBorder).frame(width: 220).onSubmit { go() }
            case .lan:
                EmptyView()
            case .dns:
                hostField
                if !r.running { Button(T("Кто отвечает")) { dnsWho(cleanHost()) } }
            default:
                hostField
            }
            if r.running { Button(T("Стоп")) { r.stop() } }
            else if tab != .ip {
                Button(goTitle) { go() }.keyboardShortcut(.defaultAction)
            }
            Spacer(minLength: 0)
        }
    }

    private var goTitle: String {
        switch tab {
        case .conns: return T("Показать")
        case .lan: return T("Найти устройства")
        case .wol: return T("Разбудить")
        default: return T("Запустить")
        }
    }

    private func cleanHost() -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["https://", "http://", "rtsp://"] where h.lowercased().hasPrefix(p) { h = String(h.dropFirst(p.count)) }
        if let i = h.firstIndex(where: { $0 == "/" || $0 == "?" }) { h = String(h[..<i]) }
        if let at = h.lastIndex(of: "@") { h = String(h[h.index(after: at)...]) }
        // «адрес:порт» → адрес (порт можно вписать в поле портов); IPv6 в скобках не трогаем
        if h.filter({ $0 == ":" }).count == 1, let c = h.firstIndex(of: ":") { h = String(h[..<c]) }
        return h
    }

    private func go() {
        guard !r.running else { return }
        let h = cleanHost()
        switch tab {
        case .ping:
            guard !h.isEmpty else { return }
            r.run("/sbin/ping", ["-c", String(count), h], header: "ping -c \(count) \(h)")
        case .trace:
            guard !h.isEmpty else { return }
            r.run("/usr/sbin/traceroute", ["-m", "24", "-w", "2", "-q", "1", h], header: "traceroute \(h)")
        case .ports: checkPorts(h)
        case .dns: dns(h)
        case .whois:
            guard !h.isEmpty else { return }
            r.run("/usr/bin/whois", [h], header: "whois \(h)")
        case .conns:
            let st = lsofMode == 0 ? "LISTEN" : "ESTABLISHED"
            r.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:" + st], header: "lsof -nP -iTCP -sTCP:\(st)")
        case .lan: scanLAN()
        case .wol: wake()
        default: break
        }
    }

    private func showLocal() {
        let l = NetProbe.localAddresses()
        r.append(T("Адреса этого Mac") + ":\n" + (l.isEmpty ? T("нет активных сетей") + "\n" : l))
    }

    private func external() {
        r.append("$ " + T("Внешний IP по разным сервисам") + "\n")
        r.work { emit, _ in
            let route = NetSpeed.defaultRoute()
            if !route.isEmpty { emit(T("Маршрут по умолчанию") + ": \(route)\n\n") }
            // все сервисы спрашиваем одновременно
            var answers = [String?](repeating: nil, count: NetSpeed.ipServices.count)
            let lock = NSLock()
            let g = DispatchGroup()
            for (i, sv) in NetSpeed.ipServices.enumerated() {
                g.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    var t = NetSpeed.get(sv.url) ?? ""
                    t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \n\r"))
                    lock.lock(); answers[i] = NetSpeed.isIP(t) ? t : nil; lock.unlock()
                    // 127.0.0.1 и подобное — не ваш внешний адрес: так отвечает DNS-фильтр, который «гасит» домен сервиса
                    g.leave()
                }
            }
            g.wait()
            // страна и провайдер — по одному запросу на каждый разный адрес
            var info: [String: String] = [:]
            for ip in Set(answers.compactMap { $0 }) { info[ip] = NetSpeed.whois(ip) }
            for (i, sv) in NetSpeed.ipServices.enumerated() {
                if let ip = answers[i] {
                    emit(sv.name.padding(toLength: 16, withPad: " ", startingAt: 0) + ip.padding(toLength: 18, withPad: " ", startingAt: 0) + (info[ip] ?? "") + "\n")
                } else {
                    emit(sv.name.padding(toLength: 16, withPad: " ", startingAt: 0) + T("нет ответа") + "\n")
                }
            }
            let uniq = Set(answers.compactMap { $0 }.filter { !NetSpeed.isLoopback($0) })
            if answers.contains(where: { $0.map(NetSpeed.isLoopback) == true }) {
                emit("\n" + T("Один из сервисов ответил 127.0.0.1 — внешний адрес он не определил. Это не блокировка: если DNS-вкладка («Кто отвечает») показывает «Всё чисто», сервис сам так ответил (например, из-за прокси или туннеля). В сравнении этот ответ не учитывается.") + "\n")
            }
            emit("\n")
            if uniq.isEmpty { emit(T("Не удалось узнать: нет доступа в интернет или сервисы недоступны.") + "\n") }
            else if uniq.count == 1 { emit(T("Адрес один: весь трафик выходит через одно место.") + "\n") }
            else { emit(T("Адреса разные: часть трафика идёт через туннель или VPN, часть напрямую. Обычно российские сайты видят один адрес, зарубежные — другой.") + "\n") }
        }
    }

    private func checkPorts(_ h: String) {
        let list = NetProbe.ports(ports)
        guard !h.isEmpty, !list.isEmpty else { r.append(T("Укажите адрес и хотя бы один порт") + "\n"); return }
        r.append("$ \(h) \(list.count > 12 ? "\(list.count) " + T("портов") : list.map(String.init).joined(separator: ", "))\n")
        r.work { emit, stopped in
            var open = 0
            let openWord = T("открыт")
            for p in list {
                if stopped() { emit(T("Остановлено") + "\n"); return }
                let (st, ms) = NetProbe.tcp(host: h, port: p)
                if st == openWord { open += 1 }
                // закрытые порты в длинных диапазонах не печатаем: важны только открытые
                if list.count <= 20 || st == openWord {
                    emit(String(p).padding(toLength: 7, withPad: " ", startingAt: 0) + st + (ms > 0 && st == openWord ? "  \(ms) " + T("мс") : "") + "\n")
                }
            }
            emit(T("Открыто") + ": \(open) " + T("из") + " \(list.count)\n")
        }
    }

    private func dns(_ h: String) {
        guard !h.isEmpty else { return }
        r.append("$ \(h)\n")
        r.work { emit, _ in
            if let name = NetProbe.reverse(h) { emit(T("Имя") + ": \(name)\n"); return }
            let a = NetProbe.lookup(h)
            if a.isEmpty { emit(T("Не найдено") + "\n") } else { a.forEach { emit($0 + "\n") } }
        }
    }

    /// Разбор «кто подменил ответ»: система, /etc/hosts, DNS-серверы Mac и публичные DNS отвечают на один и тот же вопрос
    private func dnsWho(_ h: String) {
        guard !h.isEmpty, !r.running else { return }
        r.append("$ " + T("Кто отвечает на запрос") + " \(h)\n")
        r.work { emit, _ in
            let sys = NetProbe.lookup(h)
            emit(T("Так видят программы Mac") + ": " + (sys.isEmpty ? T("Не найдено") : sys.joined(separator: ", ")) + "\n")
            let sysBlocked = sys.contains(where: NetSpeed.isLoopback)
            // 1. файл hosts
            let hosts = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
            let hostsLines = hosts.split(separator: "\n").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && $0.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).contains(Substring(h.lowercased())) }
            for l in hostsLines { emit(T("В файле /etc/hosts есть запись") + ": \(l)\n") }
            // 2. DNS-серверы, которые использует Mac
            var seen = Set<String>()
            var sysServers: [String] = []
            for line in NetSpeed.capture("/usr/sbin/scutil", ["--dns"]).split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("nameserver["), let ip = t.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces),
                   NetSpeed.isIP(ip), seen.insert(ip).inserted { sysServers.append(ip) }
            }
            let pub = [("Google", "8.8.8.8"), ("Cloudflare", "1.1.1.1"), ("Яндекс", "77.88.8.8")]
            var sysAnswers: [(String, [String])] = []
            var pubAnswers: [(String, [String])] = []
            emit("\n")
            for ip in sysServers {
                let a = NetSpeed.capture("/usr/bin/dig", ["+short", "+time=2", "+tries=1", "@" + ip, h, "A"]).split(separator: "\n").map(String.init).filter(NetSpeed.isIP)
                sysAnswers.append((ip, a))
                emit(T("DNS вашего Mac").padding(toLength: 16, withPad: " ", startingAt: 0) + ip.padding(toLength: 18, withPad: " ", startingAt: 0) + (a.isEmpty ? T("нет ответа") : a.joined(separator: ", ")) + "\n")
            }
            for (name, ip) in pub {
                let a = NetSpeed.capture("/usr/bin/dig", ["+short", "+time=2", "+tries=1", "@" + ip, h, "A"]).split(separator: "\n").map(String.init).filter(NetSpeed.isIP)
                pubAnswers.append((name, a))
                emit(name.padding(toLength: 16, withPad: " ", startingAt: 0) + ip.padding(toLength: 18, withPad: " ", startingAt: 0) + (a.isEmpty ? T("нет ответа") : a.joined(separator: ", ")) + "\n")
            }
            emit("\n")
            // вывод
            let pubGood = pubAnswers.contains { $0.1.contains { !NetSpeed.isLoopback($0) } }
            let pubAllBlocked = !pubAnswers.isEmpty && pubAnswers.allSatisfy { !$0.1.isEmpty && $0.1.allSatisfy(NetSpeed.isLoopback) }
            let blockers = sysAnswers.filter { !$0.1.isEmpty && $0.1.allSatisfy(NetSpeed.isLoopback) }.map { $0.0 }
            if !hostsLines.isEmpty {
                emit(T("Блокирует файл /etc/hosts: уберите из него строку с этим адресом (sudo nano /etc/hosts).") + "\n")
            } else if !sysBlocked {
                emit(T("Всё чисто: система получает настоящий адрес.") + "\n")
            } else if !blockers.isEmpty && pubGood {
                emit(T("Блокирует DNS-сервер") + " " + blockers.joined(separator: ", ") + ": " + T("он отвечает 127.0.0.1, а публичные DNS отдают настоящий адрес. Это ваш роутер, провайдер или DNS-фильтр (AdGuard, Pi-hole, NextDNS). Откройте его настройки и уберите домен из списка блокировки.") + "\n")
            } else if pubGood {
                emit(T("Блокирует программа на самом Mac: DNS-серверы отвечают правильно, а система получает 127.0.0.1. Так делают локальные блокировщики и фильтры (AdGuard, Little Snitch, Lulu, клиент VPN со своим DNS).") + "\n")
            } else if pubAllBlocked {
                emit(T("Блокирует сеть: даже публичные DNS отвечают 127.0.0.1, подмена идёт на пути, у провайдера или в вашем фильтре, который перехватывает весь DNS.") + "\n")
            } else {
                emit(T("Определить не удалось: публичные DNS не ответили (нет интернета или порт 53 закрыт).") + "\n")
            }
        }
    }

    private func scanLAN() {
        r.append("$ arp\n")
        r.work { emit, stopped in
            guard let (ip, mask) = NetProbe.primaryIPv4() else { emit(T("Нет активной сети") + "\n"); return }
            emit(T("Ваш адрес") + ": \(NetProbe.dotted(ip)), " + T("маска") + " \(NetProbe.dotted(mask))\n")
            let net = ip & mask
            var count = Int(~mask)
            if count > 1022 { count = 254 }   // слишком большая сеть: проверяем только соседей в /24
            let base = count == 254 ? (ip & 0xFFFFFF00) : net
            NetProbe.poke(base: base, count: count, stopped: stopped)
            if stopped() { emit(T("Остановлено") + "\n"); return }
            Thread.sleep(forTimeInterval: 1.5)
            let rows = NetProbe.arpTable().filter { $0.ip & (count == 254 ? 0xFFFFFF00 : mask) == base }
            emit(T("Найдено устройств") + ": \(rows.count)\n\n")
            for x in rows.sorted(by: { $0.ip < $1.ip }) {
                let me = x.ip == ip ? "  (" + T("этот Mac") + ")" : ""
                emit(NetProbe.dotted(x.ip).padding(toLength: 17, withPad: " ", startingAt: 0) + x.mac + me + "\n")
            }
        }
    }

    private func wake() {
        let digits = mac.filter { $0.isHexDigit }
        guard digits.count == 12 else { r.append(T("MAC-адрес — 12 шестнадцатеричных цифр, например AA:BB:CC:DD:EE:FF") + "\n"); return }
        let bytes = stride(from: 0, to: 12, by: 2).compactMap { i -> UInt8? in
            let a = digits.index(digits.startIndex, offsetBy: i)
            return UInt8(digits[a..<digits.index(a, offsetBy: 2)], radix: 16)
        }
        r.append(NetProbe.wake(bytes) ? T("Пакет отправлен") + ": \(digits.uppercased())\n" : T("Не удалось отправить пакет") + "\n")
    }
}

final class NetToolsController: NSObject, NSWindowDelegate {
    static let shared = NetToolsController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 860, height: 520)
            w.contentView = NSHostingView(rootView: LangRefresh { NetToolsView() })
            w.delegate = self
            if !w.setFrameUsingName("NetToolsWindow") { w.center() }
            w.setFrameAutosaveName("NetToolsWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Сетевые инструменты")
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() { window?.title = T("Сетевые инструменты") }
}

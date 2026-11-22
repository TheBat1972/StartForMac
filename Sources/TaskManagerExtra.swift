import SwiftUI
import AppKit
import Combine

// MARK: - Защита от случайного завершения

enum TMGuardKind { case none, system, selfApp }

enum TMGuard {
    static let critical: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow", "Finder", "Dock", "SystemUIServer",
        "coreservicesd", "securityd", "opendirectoryd", "mds", "mds_stores", "notifyd", "configd",
        "powerd", "distnoted", "cfprefsd", "UserEventAgent", "fseventsd", "diskarbitrationd",
        "hidd", "bluetoothd", "coreaudiod", "logd", "syslogd", "trustd", "tccd", "airportd"
    ]

    static func kind(path: String, name: String, user: String, pids: [Int32]) -> TMGuardKind {
        if pids.contains(getpid()) { return .selfApp }
        if critical.contains(name) || user == "root" { return .system }
        if path.hasPrefix("/usr/local/") { return .none }
        for p in ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"] where path.hasPrefix(p) { return .system }
        return .none
    }

    /// Предупреждение перед опасным действием; `verb` — «Завершить» / «Приостановить»
    static func confirm(_ name: String, _ kind: TMGuardKind, verb: String) -> Bool {
        if kind == .none { return true }
        let a = NSAlert()
        a.alertStyle = .warning
        if kind == .selfApp {
            a.messageText = T("Это сам «Пуск»")
            a.informativeText = T("Программа закроется, горячие клавиши и значки в строке меню перестанут работать.")
        } else {
            a.messageText = Tf("Системный процесс «%@»", name)
            a.informativeText = T("Остановка системных процессов может привести к потере данных, сбою программ или перезагрузке Мака.")
        }
        a.addButton(withTitle: verb)
        a.addButton(withTitle: T("Отмена"))
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }
}

struct TMPriority: Identifiable {
    let id: Int32
    var title: String { return T(name) }
    let name: String
    var value: Int32 { return id }
    static let all: [TMPriority] = [
        TMPriority(id: -10, name: "Высокий"),
        TMPriority(id: -5, name: "Выше обычного"),
        TMPriority(id: 0, name: "Обычный"),
        TMPriority(id: 5, name: "Ниже обычного"),
        TMPriority(id: 15, name: "Низкий"),
    ]
}

/// Команда с правами администратора через системное окно пароля (работает из любого окна)
enum TMAdmin {
    static func run(_ tool: String, _ args: [String]) -> (ok: Bool, out: String) {
        func q(_ s: String) -> String { return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let cmd = ([tool] + args).map(q).joined(separator: " ")
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script \"\(esc)\" with administrator privileges"]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (false, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - Автоматические правила

final class TMRules: ObservableObject {
    static let shared = TMRules()
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "tm.rule.on"); TMExtras.refreshBackground() } }
    @Published var limit: Double { didSet { d.set(limit, forKey: "tm.rule.limit") } }
    @Published var seconds: Int { didSet { d.set(seconds, forKey: "tm.rule.sec") } }
    @Published var endIt: Bool { didSet { d.set(endIt, forKey: "tm.rule.end") } }

    private var over: [Int32: Double] = [:]
    private var done = Set<Int32>()

    private init() {
        enabled = d.bool(forKey: "tm.rule.on")
        let l = d.double(forKey: "tm.rule.limit")
        limit = l > 0 ? l : 50
        let s = d.integer(forKey: "tm.rule.sec")
        seconds = s > 0 ? s : 60
        endIt = d.bool(forKey: "tm.rule.end")
    }

    func evaluate(_ procs: [Int32: TMProc], dt: Double) {
        guard enabled else { over = [:]; done = []; return }
        var now: [Int32: Double] = [:]
        for (pid, p) in procs where p.cpu > limit && pid > 1 && p.status != 4 {
            let t = (over[pid] ?? 0) + dt
            now[pid] = t
            if t >= Double(seconds) && !done.contains(pid) {
                done.insert(pid)
                let k = TMGuard.kind(path: p.path, name: p.name, user: p.user, pids: [pid])
                let title = Tf("«%@» нагружает процессор", p.name)
                if endIt && k == .none {
                    kill(pid, SIGTERM)
                    TMExtras.notify(title, Tf("Больше %@ % ЦП дольше %@ с: процесс завершён.", "\(Int(limit))", "\(seconds)"))
                } else {
                    TMExtras.notify(title, Tf("Больше %@ % ЦП дольше %@ с.", "\(Int(limit))", "\(seconds)"))
                }
            }
        }
        over = now
        done = done.filter { now[$0] != nil }
    }
}

struct TMRulesView: View {
    @ObservedObject private var r = TMRules.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Автоматические действия")).font(.headline)
            Toggle(T("Следить за нагрузкой процессов"), isOn: $r.enabled)
            HStack(spacing: 6) {
                Text(T("Если процесс держит больше"))
                TextField("", value: $r.limit, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                Text(T("% ЦП"))
            }
            HStack(spacing: 6) {
                Text(T("дольше"))
                TextField("", value: $r.seconds, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                Text(T("секунд"))
            }
            Picker("", selection: $r.endIt) {
                Text(T("Только предупредить")).tag(false)
                Text(T("Предупредить и снять задачу")).tag(true)
            }
            .pickerStyle(.radioGroup).labelsHidden()
            Text(T("Значение ЦП — как в столбце «ЦП» (доля всего процессора). Системные процессы и сам «Пуск» не снимаются, о них только предупреждение. Слежение работает, пока «Пуск» запущен."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(width: 340)
    }
}

// MARK: - Фон: слежение, значок в строке меню, уведомления

enum TMExtras {
    private static var lastT = Date()

    static func notify(_ title: String, _ text: String) {
        DispatchQueue.global(qos: .utility).async {
            func esc(_ s: String) -> String {
                return s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "display notification \"\(esc(text))\" with title \"\(esc(title))\" sound name \"Glass\""]
            try? p.run()
        }
    }

    /// Вызывается из сэмплера после каждого замера (в главном потоке)
    static func afterSample(_ s: TMSampler) {
        let now = Date()
        let dt = min(10, max(0.2, now.timeIntervalSince(lastT)))
        lastT = now
        TMRules.shared.evaluate(s.procs, dt: dt)
        TMJournal.shared.add(rows: s.apps + s.background, dt: dt)
    }

    static var keepRunning: Bool {
        return TMRules.shared.enabled || UserDefaults.standard.bool(forKey: "tm.menubar")
    }

    /// Запуск при старте программы: если включены слежение или значок, сэмплер работает без окна
    static func bootstrap() {
        if UserDefaults.standard.bool(forKey: "tm.menubar") { TMMenuBar.shared.setEnabled(true) }
        refreshBackground()
    }

    static func refreshBackground() {
        if keepRunning { TMSampler.shared.start() }
        else if !TMSampler.shared.windowVisible { TMSampler.shared.stop() }
    }
}

final class TMMenuBar: NSObject {
    static let shared = TMMenuBar()
    private var item: NSStatusItem?
    private var sub: AnyCancellable?
    private let cpuLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let memLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "tm.menubar")
        if on {
            if item == nil {
                let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let menu = NSMenu()
                cpuLine.isEnabled = false
                memLine.isEnabled = false
                menu.addItem(cpuLine)
                menu.addItem(memLine)
                menu.addItem(.separator())
                let open = NSMenuItem(title: T("Открыть диспетчер задач"), action: #selector(openManager), keyEquivalent: "")
                open.target = self
                menu.addItem(open)
                let off = NSMenuItem(title: T("Убрать значок из строки меню"), action: #selector(removeIcon), keyEquivalent: "")
                off.target = self
                menu.addItem(off)
                it.menu = menu
                item = it
            }
            TMSampler.shared.start()
            sub = TMSampler.shared.$cpuHistory.receive(on: DispatchQueue.main).sink { [weak self] h in self?.update(h) }
        } else {
            sub = nil
            if let it = item { NSStatusBar.system.removeStatusItem(it) }
            item = nil
            TMExtras.refreshBackground()
        }
    }

    @objc private func openManager() { TMWindowController.shared.show() }
    @objc private func removeIcon() { setEnabled(false) }

    private func update(_ h: [Double]) {
        guard let button = item?.button else { return }
        let now = h.last ?? 0
        button.image = Self.spark(h)
        button.imagePosition = .imageLeft
        button.attributedTitle = NSAttributedString(
            string: " " + String(format: "%.0f%%", now),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)])
        let s = TMSampler.shared
        cpuLine.title = T("ЦП") + ": " + String(format: "%.0f%%", now)
        memLine.title = T("Память") + ": " + tmBytes(Double(s.memUsed)) + " / " + tmBytes(Double(s.memTotal))
    }

    private static func spark(_ h: [Double]) -> NSImage {
        let size = NSSize(width: 38, height: 16)
        let img = NSImage(size: size, flipped: false) { r in
            let n = TMSampler.historyLength
            guard !h.isEmpty else { return true }
            let step = r.width / CGFloat(max(1, n - 1))
            let off = n - h.count
            func pt(_ i: Int) -> NSPoint {
                let v = CGFloat(min(100, max(0, h[i])) / 100)
                return NSPoint(x: CGFloat(i + off) * step, y: 1 + v * (r.height - 2))
            }
            let line = NSBezierPath()
            line.move(to: pt(0))
            for i in 1..<max(1, h.count) { line.line(to: pt(i)) }
            let fill = line.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: pt(h.count - 1).x, y: 0))
            fill.line(to: NSPoint(x: pt(0).x, y: 0))
            fill.close()
            NSColor.black.withAlphaComponent(0.3).setFill()
            fill.fill()
            NSColor.black.setStroke()
            line.lineWidth = 1
            line.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - Журнал приложений

struct TMHistEntry: Codable {
    var name: String
    var isApp: Bool
    var cpu = 0.0          // секунд процессорного времени
    var netIn = 0.0        // байт
    var netOut = 0.0
    var disk = 0.0         // байт чтения + записи
}

final class TMJournal: ObservableObject {
    static let shared = TMJournal()
    @Published var entries: [String: TMHistEntry] = [:]
    @Published var since = Date()
    private var lastSave = Date()
    private let ncpu = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))

    private struct File: Codable { var since: Date; var entries: [String: TMHistEntry] }

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StartMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tm-history.json")
    }

    private init() {
        if let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: d) {
            since = f.since
            entries = f.entries
        }
    }

    func add(rows: [TMRow], dt: Double) {
        for r in rows where !r.path.isEmpty {
            var e = entries[r.id] ?? TMHistEntry(name: r.name, isApp: r.isApp)
            e.name = r.name
            e.isApp = e.isApp || r.isApp
            e.cpu += r.cpu / 100 * ncpu * dt
            e.netIn += r.netIn * dt
            e.netOut += r.netOut * dt
            e.disk += (r.diskR + r.diskW) * dt
            entries[r.id] = e
        }
        if entries.count > 800 {
            let keep = entries.sorted { $0.value.cpu > $1.value.cpu }.prefix(600)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if Date().timeIntervalSince(lastSave) > 30 { save() }
    }

    func save() {
        lastSave = Date()
        if let d = try? JSONEncoder().encode(File(since: since, entries: entries)) { try? d.write(to: url) }
    }

    func reset() {
        entries = [:]
        since = Date()
        save()
    }
}

func tmDuration(_ sec: Double) -> String {
    let s = Int(sec)
    if s >= 3600 { return "\(s / 3600):" + String(format: "%02d:%02d", (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

struct TMJournalView: View {
    @ObservedObject private var j = TMJournal.shared
    @State private var sortKey = "cpu"
    @State private var asc = false
    @State private var showBackground = false
    @State private var query = ""

    private func icon(_ id: String) -> NSImage {
        let i = NSWorkspace.shared.icon(forFile: id)
        i.size = NSSize(width: 16, height: 16)
        return i
    }

    private func total(_ e: TMHistEntry, _ k: String) -> Double {
        switch k {
        case "cpu": return e.cpu
        case "net": return e.netIn + e.netOut
        case "disk": return e.disk
        default: return 0
        }
    }

    private func list() -> [(String, TMHistEntry)] {
        var a = j.entries.map { ($0.key, $0.value) }
        if !showBackground { a = a.filter { $0.1.isApp } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { a = a.filter { $0.1.name.lowercased().contains(q) } }
        a.sort { x, y in
            if sortKey == "name" {
                let c = x.1.name.localizedCaseInsensitiveCompare(y.1.name)
                return asc ? c == .orderedAscending : c == .orderedDescending
            }
            let u = total(x.1, sortKey), v = total(y.1, sortKey)
            return asc ? u < v : u > v
        }
        return a
    }

    private func header(_ title: String, _ key: String, width: CGFloat?, trailing: Bool = true) -> some View {
        Button {
            if sortKey == key { asc.toggle() } else { sortKey = key; asc = key == "name" }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortKey == key { Image(systemName: asc ? "chevron.up" : "chevron.down").font(.system(size: 8)) }
            }
            .font(.caption).foregroundColor(.secondary)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: trailing ? .trailing : .leading)
        }
        .buttonStyle(.plain)
        .frame(width: width)
    }

    var body: some View {
        let rows = list()
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                header(T("Имя"), "name", width: nil, trailing: false)
                header(T("Время ЦП"), "cpu", width: 100)
                header(T("Сеть"), "net", width: 110)
                header(T("Диск"), "disk", width: 110)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.0) { id, e in
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Image(nsImage: icon(id)).resizable().frame(width: 16, height: 16)
                                Text(e.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            Text(tmDuration(e.cpu)).monospacedDigit().frame(width: 100, alignment: .trailing)
                            Text(tmBytes(e.netIn + e.netOut)).monospacedDigit().frame(width: 110, alignment: .trailing)
                                .help(Tf("Получено %@, отправлено %@", tmBytes(e.netIn), tmBytes(e.netOut)))
                            Text(tmBytes(e.disk)).monospacedDigit().frame(width: 110, alignment: .trailing)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                TextField(T("Поиск процессов"), text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
                Toggle(T("Показывать фоновые"), isOn: $showBackground)
                Spacer()
                Text(Tf("Накоплено с %@", DateFormatter.localizedString(from: j.since, dateStyle: .medium, timeStyle: .short)))
                    .font(.caption).foregroundColor(.secondary)
                Button(T("Сбросить")) { j.reset() }
            }
            .padding(10)
            Text(T("Данные копятся, пока диспетчер открыт или включено слежение / значок в строке меню."))
                .font(.caption2).foregroundColor(.secondary).padding(.bottom, 6)
        }
    }
}

// MARK: - Пользователи

enum TMUsers {
    static func isHuman(_ u: String) -> Bool {
        return !u.hasPrefix("_") && u != "root" && u != "nobody" && u != "daemon" && !u.isEmpty
    }
    static func count(_ procs: [Int32: TMProc]) -> Int {
        return Set(procs.values.map { $0.user }.filter(isHuman)).count
    }
}

struct TMUsersView: View {
    @ObservedObject var s: TMSampler
    @State private var open = Set<String>()

    private struct U { var name: String; var procs: [TMProc]; var cpu: Double; var mem: UInt64 }

    private func users() -> [U] {
        var d: [String: [TMProc]] = [:]
        for p in s.procs.values { d[p.user, default: []].append(p) }
        var a = d.map { U(name: $0.key, procs: $0.value.sorted { $0.cpu > $1.cpu },
                          cpu: $0.value.reduce(0) { $0 + $1.cpu }, mem: $0.value.reduce(0) { $0 + $1.mem }) }
        a.sort { x, y in
            let hx = TMUsers.isHuman(x.name), hy = TMUsers.isHuman(y.name)
            if hx != hy { return hx }
            return x.cpu > y.cpu
        }
        return a
    }

    var body: some View {
        let list = users()
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(T("Пользователь")).frame(maxWidth: .infinity, alignment: .leading)
                Text(T("Процессы")).frame(width: 90, alignment: .trailing)
                Text(T("ЦП")).frame(width: 80, alignment: .trailing)
                Text(T("Память")).frame(width: 100, alignment: .trailing)
            }
            .font(.caption).foregroundColor(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(list, id: \.name) { u in
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Image(systemName: open.contains(u.name) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9)).frame(width: 12)
                                Image(systemName: TMUsers.isHuman(u.name) ? "person.fill" : "gearshape.fill")
                                    .foregroundColor(.secondary)
                                Text(u.name + (u.name == NSUserName() ? " " + T("(вы)") : "")).fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(u.procs.count)").monospacedDigit().frame(width: 90, alignment: .trailing)
                            Text(String(format: "%.1f%%", u.cpu)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Text(tmBytes(Double(u.mem))).monospacedDigit().frame(width: 100, alignment: .trailing)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if open.contains(u.name) { open.remove(u.name) } else { open.insert(u.name) }
                        }
                        if open.contains(u.name) {
                            ForEach(u.procs.prefix(20)) { p in
                                HStack(spacing: 0) {
                                    Text(p.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 46)
                                    Text("\(p.id)").monospacedDigit().frame(width: 90, alignment: .trailing)
                                    Text(String(format: "%.1f%%", p.cpu)).monospacedDigit().frame(width: 80, alignment: .trailing)
                                    Text(tmBytes(Double(p.mem))).monospacedDigit().frame(width: 100, alignment: .trailing)
                                }
                                .font(.system(size: 11)).foregroundColor(.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 2)
                            }
                        }
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - Службы (launchd)

struct TMService: Identifiable {
    var id: String { return path }
    var label: String
    var path: String
    var exec: String
    var kind: Int              // 0 демон (system), 1 агент
    var apple: Bool
    var running = false
    var pid: Int32 = 0
}

final class TMServiceStore: ObservableObject {
    @Published var items: [TMService] = []
    @Published var busy = false
    private var defs: [TMService] = []
    private let uid = getuid()

    private func parse() -> [TMService] {
        let home = NSHomeDirectory()
        let dirs: [(String, Int, Bool)] = [
            ("/System/Library/LaunchDaemons", 0, true), ("/Library/LaunchDaemons", 0, false),
            ("/System/Library/LaunchAgents", 1, true), ("/Library/LaunchAgents", 1, false),
            (home + "/Library/LaunchAgents", 1, false),
        ]
        var out: [TMService] = []
        for (dir, kind, apple) in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".plist") {
                let path = dir + "/" + f
                guard let d = NSDictionary(contentsOfFile: path), let label = d["Label"] as? String else { continue }
                var exec = d["Program"] as? String ?? ""
                if exec.isEmpty, let a = d["ProgramArguments"] as? [String], let f0 = a.first { exec = f0 }
                out.append(TMService(label: label, path: path, exec: exec, kind: kind,
                                     apple: apple || label.hasPrefix("com.apple.")))
            }
        }
        return out
    }

    private func launchctlList() -> [String: Int32] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var r: [String: Int32] = [:]
        for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").dropFirst() {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false)
            if c.count >= 3, let pid = Int32(c[0]) { r[String(c[2])] = pid }
        }
        return r
    }

    /// reload — заново читать plist-файлы; иначе обновляем только состояние
    func refresh(procs: [Int32: TMProc], reload: Bool = false) {
        let paths = Set(procs.values.map { $0.path })
        let pidByPath = Dictionary(procs.values.map { ($0.path, $0.id) }, uniquingKeysWith: { a, _ in a })
        DispatchQueue.global(qos: .utility).async {
            if reload || self.defs.isEmpty { self.defs = self.parse() }
            let lc = self.launchctlList()
            var a = self.defs
            for i in a.indices {
                if let pid = lc[a[i].label] {
                    a[i].running = true; a[i].pid = pid
                } else if !a[i].exec.isEmpty, paths.contains(a[i].exec) {
                    a[i].running = true; a[i].pid = pidByPath[a[i].exec] ?? 0
                }
            }
            a.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            DispatchQueue.main.async { self.items = a }
        }
    }

    private func local(_ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// action: start / stop / restart
    func act(_ svc: TMService, _ action: String, procs: [Int32: TMProc]) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = true
            var detail = ""
            let target = (svc.kind == 0 ? "system/" : "gui/\(self.uid)/") + svc.label
            let domain = svc.kind == 0 ? "system" : "gui/\(self.uid)"
            func run(_ args: [String]) -> (Bool, String) {
                if svc.kind == 0 {
                    let r = TMAdmin.run("/bin/launchctl", args)
                    return (r.ok, r.out)
                }
                let (c, o) = self.local(args)
                return (c == 0, o)
            }
            switch action {
            case "stop":
                (ok, detail) = run(["bootout", target])
            case "restart":
                (ok, detail) = run(["kickstart", "-k", target])
                if !ok { (ok, detail) = run(["bootstrap", domain, svc.path]) }
            default:
                (ok, detail) = run(["kickstart", target])
                if !ok { (ok, detail) = run(["bootstrap", domain, svc.path]) }
            }
            DispatchQueue.main.async {
                self.busy = false
                if !ok {
                    let a = NSAlert()
                    a.alertStyle = .warning
                    a.messageText = Tf("Не удалось выполнить действие со службой «%@»", svc.label)
                    a.informativeText = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    NSApp.activate(ignoringOtherApps: true)
                    a.runModal()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.refresh(procs: TMSampler.shared.procs) }
        }
    }
}

struct TMServicesView: View {
    @ObservedObject var s: TMSampler
    @StateObject private var store = TMServiceStore()
    @State private var selected: String? = nil
    @State private var query = ""
    @State private var hideApple = true
    @State private var filter = 0          // 0 все, 1 работают, 2 остановлены
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private func list() -> [TMService] {
        var a = store.items
        if hideApple { a = a.filter { !$0.apple } }
        if filter == 1 { a = a.filter { $0.running } } else if filter == 2 { a = a.filter { !$0.running } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { a = a.filter { $0.label.lowercased().contains(q) } }
        return a
    }

    private func kindText(_ k: Int) -> String { return k == 0 ? T("Демон") : T("Агент") }

    private func confirmApple(_ svc: TMService, _ verb: String) -> Bool {
        guard svc.apple else { return true }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = Tf("Системная служба «%@»", svc.label)
        a.informativeText = T("Остановка системных служб может нарушить работу macOS. macOS может не дать изменить защищённые службы.")
        a.addButton(withTitle: verb)
        a.addButton(withTitle: T("Отмена"))
        return a.runModal() == .alertFirstButtonReturn
    }

    private func do_(_ svc: TMService, _ action: String, _ verb: String) {
        if confirmApple(svc, verb) { store.act(svc, action, procs: s.procs) }
    }

    @ViewBuilder private func menu(_ svc: TMService) -> some View {
        Button(T("Запустить")) { do_(svc, "start", T("Запустить")) }
        Button(T("Остановить")) { do_(svc, "stop", T("Остановить")) }
        Button(T("Перезапустить")) { do_(svc, "restart", T("Перезапустить")) }
        Divider()
        Button(T("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: svc.path)]) }
        Button(T("Скопировать путь")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(svc.path, forType: .string)
        }
    }

    var body: some View {
        let rows = list()
        let cur = rows.first { $0.id == selected }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(T("Служба")).frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 64, alignment: .trailing)
                Text(T("Состояние")).frame(width: 110, alignment: .leading).padding(.leading, 12)
                Text(T("Тип")).frame(width: 80, alignment: .leading)
            }
            .font(.caption).foregroundColor(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { svc in
                        HStack(spacing: 0) {
                            Text(svc.label).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                            Text(svc.running && svc.pid > 0 ? "\(svc.pid)" : "").monospacedDigit().frame(width: 64, alignment: .trailing)
                            HStack(spacing: 5) {
                                Circle().fill(svc.running ? Color.green : Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                                Text(svc.running ? T("Работает") : T("Остановлена"))
                            }
                            .frame(width: 110, alignment: .leading).padding(.leading, 12)
                            Text(kindText(svc.kind)).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(selected == svc.id ? Color.accentColor.opacity(0.28) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = svc.id }
                        .contextMenu { menu(svc) }
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                TextField(T("Поиск служб"), text: $query).textFieldStyle(.roundedBorder).frame(width: 190)
                Picker("", selection: $filter) {
                    Text(T("Все")).tag(0)
                    Text(T("Работают")).tag(1)
                    Text(T("Остановлены")).tag(2)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 220)
                Toggle(T("Скрыть службы Apple"), isOn: $hideApple)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button(T("Запустить")) { if let c = cur { do_(c, "start", T("Запустить")) } }.disabled(cur == nil)
                Button(T("Остановить")) { if let c = cur { do_(c, "stop", T("Остановить")) } }.disabled(cur == nil)
                Button(T("Обновить")) { store.refresh(procs: s.procs, reload: true) }
            }
            .padding(10)
        }
        .onAppear { store.refresh(procs: s.procs, reload: true) }
        .onReceive(timer) { _ in store.refresh(procs: s.procs) }
    }
}

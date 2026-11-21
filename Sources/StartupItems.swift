import Cocoa
import SwiftUI
import Darwin
import UniformTypeIdentifiers

// MARK: - Автозагрузка: элементы входа и агенты запуска

struct TMStartItem: Identifiable {
    enum Kind { case login, agent }
    let id: String              // для элемента входа — путь, для агента — путь к plist
    var name: String
    var kind: Kind
    var enabled: Bool
    var path: String            // что запускается (программа или исполняемый файл)
    var label: String           // Label агента
    var plist: String           // путь к plist агента
    var system: Bool            // агент из /Library (удалять нельзя)
}

final class TMStartupStore: ObservableObject {
    static let shared = TMStartupStore()
    @Published var items: [TMStartItem] = []
    @Published var loading = false
    @Published var error: String? = nil

    private let disabledKey = "tm.disabledLoginItems"       // [[имя, путь]]: отключённые элементы входа, которые мы убрали из системного списка
    private let uid = getuid()

    // MARK: Элементы входа (список «Открывать при входе»)

    private func readLogin() -> [TMStartItem] {
        var out: [TMStartItem] = []
        for (n, url) in LSL.items() {
            var name = n
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
            if name.isEmpty { name = url.lastPathComponent }
            out.append(TMStartItem(id: url.path, name: name, kind: .login, enabled: true,
                                   path: url.path, label: "", plist: "", system: false))
        }
        let have = Set(out.map { $0.path })
        for d in (UserDefaults.standard.array(forKey: disabledKey) as? [[String]]) ?? [] where d.count == 2 && !have.contains(d[1]) {
            out.append(TMStartItem(id: d[1], name: d[0], kind: .login, enabled: false, path: d[1], label: "", plist: "", system: false))
        }
        return out
    }

    private func rememberDisabled(_ name: String, _ path: String, add: Bool) {
        var a = (UserDefaults.standard.array(forKey: disabledKey) as? [[String]]) ?? []
        a.removeAll { $0.count == 2 && $0[1] == path }
        if add { a.append([name, path]) }
        UserDefaults.standard.set(a, forKey: disabledKey)
    }

    private func insertLogin(_ url: URL) { LSL.insert(url) }

    private func removeLogin(path: String) { LSL.remove(path: path) }

    // MARK: Агенты запуска

    private func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func disabledLabels() -> Set<String> {
        var s = Set<String>()
        let text = run(["print-disabled", "gui/\(uid)"])
        guard let re = try? NSRegularExpression(pattern: "\"([^\"]+)\"\\s*=>\\s*(true|false|enabled|disabled)") else { return s }
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges == 3 {
            let v = ns.substring(with: m.range(at: 2))
            if v == "true" || v == "disabled" { s.insert(ns.substring(with: m.range(at: 1))) }
        }
        return s
    }

    private func readAgents() -> [TMStartItem] {
        let dirs: [(String, Bool)] = [(NSHomeDirectory() + "/Library/LaunchAgents", false), ("/Library/LaunchAgents", true)]
        let off = disabledLabels()
        var out: [TMStartItem] = []
        let fm = FileManager.default
        for (dir, system) in dirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".plist") {
                let plist = dir + "/" + f
                guard let d = NSDictionary(contentsOfFile: plist) as? [String: Any] else { continue }
                let label = (d["Label"] as? String) ?? (f as NSString).deletingPathExtension
                if label.hasPrefix("com.apple.") { continue }
                let runAtLoad = (d["RunAtLoad"] as? Bool) ?? false
                let keepAlive: Bool = {
                    if let b = d["KeepAlive"] as? Bool { return b }
                    return d["KeepAlive"] is [String: Any]
                }()
                if !runAtLoad && !keepAlive { continue }                 // запускается не при входе
                var exe = (d["Program"] as? String) ?? ((d["ProgramArguments"] as? [String])?.first ?? "")
                if exe.isEmpty { exe = plist }
                var shown = exe
                if let r = exe.range(of: ".app/") { shown = String(exe[exe.startIndex..<r.lowerBound]) + ".app" }
                var name = (shown as NSString).lastPathComponent
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                if name.isEmpty { name = label }
                out.append(TMStartItem(id: plist, name: name, kind: .agent, enabled: !off.contains(label),
                                       path: shown, label: label, plist: plist, system: system))
            }
        }
        return out
    }

    // MARK: Операции

    func reload() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let all = (self.readLogin() + self.readAgents())
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self.items = all; self.loading = false }
        }
    }

    func setEnabled(_ it: TMStartItem, _ on: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            switch it.kind {
            case .login:
                if on {
                    self.rememberDisabled(it.name, it.path, add: false)
                    self.insertLogin(URL(fileURLWithPath: it.path))
                } else {
                    self.rememberDisabled(it.name, it.path, add: true)
                    self.removeLogin(path: it.path)
                }
            case .agent:
                // включённый агент подхватывается при следующем входе; сразу его не запускаем
                _ = self.run([on ? "enable" : "disable", "gui/\(self.uid)/\(it.label)"])
            }
            DispatchQueue.main.async { self.reload() }
        }
    }

    func remove(_ it: TMStartItem) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            switch it.kind {
            case .login:
                self.rememberDisabled(it.name, it.path, add: false)
                self.removeLogin(path: it.path)
            case .agent:
                if !it.system {
                    _ = self.run(["bootout", "gui/\(self.uid)/\(it.label)"])
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: it.plist), resultingItemURL: nil)
                }
            }
            DispatchQueue.main.async { self.reload() }
        }
    }

    func add(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.rememberDisabled("", url.path, add: false)
            self.insertLogin(url)
            DispatchQueue.main.async { self.reload() }
        }
    }

    func reveal(_ it: TMStartItem) {
        let p = FileManager.default.fileExists(atPath: it.path) ? it.path : it.plist
        guard !p.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    }
}

struct TMStartupView: View {
    @ObservedObject private var st = TMStartupStore.shared
    @State private var selected: String? = nil
    @State private var confirmRemove: TMStartItem? = nil

    private var selectedItem: TMStartItem? { st.items.first { $0.id == selected } }

    private func kindTitle(_ it: TMStartItem) -> String {
        switch it.kind {
        case .login: return T("Элемент входа")
        case .agent: return it.system ? T("Агент (все пользователи)") : T("Агент пользователя")
        }
    }

    private func canRemove(_ it: TMStartItem) -> Bool { it.kind == .login || !it.system }

    private func row(_ it: TMStartItem) -> some View {
        let sel = selected == it.id
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: it.path)).resizable().frame(width: 16, height: 16)
                Text(it.name).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(kindTitle(it)).foregroundColor(.secondary).lineLimit(1)
                .frame(width: 190, alignment: .leading)
            Text(it.enabled ? T("Включено") : T("Отключено"))
                .foregroundColor(it.enabled ? .primary : .secondary)
                .frame(width: 100, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .opacity(it.enabled ? 1 : 0.7)
        .background(sel ? Color.accentColor.opacity(0.28) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = it.id }
        .contextMenu {
            Button(it.enabled ? T("Отключить") : T("Включить")) { st.setEnabled(it, !it.enabled) }
            Button(T("Показать в Finder")) { st.reveal(it) }
            if canRemove(it) { Button(T("Удалить из автозагрузки…")) { confirmRemove = it } }
        }
    }

    private func pickApp() {
        Store.suppressAutoHide = true
        let panel = NSOpenPanel()
        panel.title = T("Выберите программу")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url { st.add(u) }
        Store.suppressAutoHide = false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(T("Имя")).frame(maxWidth: .infinity, alignment: .leading)
                Text(T("Тип")).frame(width: 190, alignment: .leading)
                Text(T("Состояние")).frame(width: 100, alignment: .leading)
            }
            .font(.caption).foregroundColor(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(st.items) { row($0) }
                    if st.items.isEmpty {
                        Text(st.loading ? T("Загрузка…") : T("Нет программ в автозагрузке"))
                            .foregroundColor(.secondary).padding(30)
                    }
                }
            }
            Divider()
            Text(T("Здесь программы, которые запускаются при входе в систему: элементы входа и агенты запуска. Отключённый элемент входа убирается из системного списка и возвращается при включении, отключённый агент не запустится при следующем входе. Часть фоновых программ (Системные настройки → Основные → Объекты входа) система программам не показывает."))
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.top, 8)
            HStack(spacing: 10) {
                Button(T("Добавить…")) { pickApp() }
                Spacer()
                Button(T("Удалить…")) { confirmRemove = selectedItem }
                    .disabled(selectedItem == nil || !(selectedItem.map(canRemove) ?? false))
                Button((selectedItem?.enabled ?? true) ? T("Отключить") : T("Включить")) {
                    if let it = selectedItem { st.setEnabled(it, !it.enabled) }
                }
                .disabled(selectedItem == nil)
            }
            .padding(10)
        }
        .onAppear { st.reload() }
        .alert(item: Binding(get: { confirmRemove.map { RemoveAsk(id: $0.id, item: $0) } }, set: { _ in confirmRemove = nil })) { ask in
            Alert(title: Text(T("Удалить из автозагрузки?")),
                  message: Text(ask.item.name + (ask.item.kind == .agent ? "\n" + T("Файл агента будет перемещён в Корзину.") : "")),
                  primaryButton: .destructive(Text(T("Удалить"))) { st.remove(ask.item) },
                  secondaryButton: .cancel(Text(T("Отмена"))))
        }
    }
}

private struct RemoveAsk: Identifiable {
    let id: String
    let item: TMStartItem
}


// Старый интерфейс LSSharedFileList помечен устаревшим, но это единственный способ
// читать и менять «Открывать при входе» без Apple Events. Вызываем через dlsym.
private enum LSL {
    typealias RP = UnsafeRawPointer
    typealias MP = UnsafeMutableRawPointer
    typealias CreateF = @convention(c) (RP?, RP?, RP?) -> MP?
    typealias SnapF = @convention(c) (RP, UnsafeMutablePointer<UInt32>?) -> MP?
    typealias UrlF = @convention(c) (RP, UInt32, UnsafeMutablePointer<MP?>?) -> MP?
    typealias NameF = @convention(c) (RP) -> MP?
    typealias InsF = @convention(c) (RP, RP?, RP?, RP?, RP, RP?, RP?) -> MP?
    typealias RemF = @convention(c) (RP, RP) -> Int32

    private static let h = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY)

    private static func fn<T>(_ name: String, _ t: T.Type) -> T? {
        guard let h = h, let s = dlsym(h, name) else { return nil }
        return unsafeBitCast(s, to: t)
    }
    private static func const(_ name: String) -> RP? {
        guard let h = h, let s = dlsym(h, name) else { return nil }
        return s.assumingMemoryBound(to: RP?.self).pointee
    }
    private static func list() -> MP? {
        guard let c = fn("LSSharedFileListCreate", CreateF.self),
              let kind = const("kLSSharedFileListSessionLoginItems") else { return nil }
        return c(nil, kind, nil)
    }
    private static func release(_ p: MP) { Unmanaged<AnyObject>.fromOpaque(p).release() }

    private static func each(_ body: (RP, RP) -> Void) {
        guard let l = list() else { return }
        defer { release(l) }
        guard let snap = fn("LSSharedFileListCopySnapshot", SnapF.self), let arrP = snap(RP(l), nil) else { return }
        let arr = Unmanaged<CFArray>.fromOpaque(arrP).takeRetainedValue()
        for i in 0..<CFArrayGetCount(arr) {
            if let it = CFArrayGetValueAtIndex(arr, i) { body(RP(l), it) }
        }
    }
    private static func resolve(_ it: RP) -> URL? {
        guard let f = fn("LSSharedFileListItemCopyResolvedURL", UrlF.self), let p = f(it, 0, nil) else { return nil }
        return (Unmanaged<CFURL>.fromOpaque(p).takeRetainedValue() as URL)
    }

    static func items() -> [(String, URL)] {
        var out: [(String, URL)] = []
        let nameF = fn("LSSharedFileListItemCopyDisplayName", NameF.self)
        each { _, it in
            guard let url = resolve(it) else { return }
            var name = ""
            if let nf = nameF, let np = nf(it) { name = Unmanaged<CFString>.fromOpaque(np).takeRetainedValue() as String }
            out.append((name, url))
        }
        return out
    }

    static func insert(_ url: URL) {
        guard let l = list(), let f = fn("LSSharedFileListInsertItemURL", InsF.self),
              let last = const("kLSSharedFileListItemLast") else { return }
        defer { release(l) }
        let u = url as CFURL
        let r = f(RP(l), last, nil, nil, RP(Unmanaged.passUnretained(u).toOpaque()), nil, nil)
        if let r = r { release(r) }
    }

    static func remove(path: String) {
        guard let rf = fn("LSSharedFileListItemRemove", RemF.self) else { return }
        each { l, it in
            if let url = resolve(it), url.path == path { _ = rf(l, it) }
        }
    }
}

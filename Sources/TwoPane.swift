import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

// MARK: - Общий провайдер перетаскивания файла (результаты поиска и файловый менеджер)

/// Что отдаётся при перетаскивании файла из «Пуска»: копия для других программ, ссылка и настоящий путь для окон самого «Пуска»
func makeFileDragProvider(_ url: URL) -> NSItemProvider {
    let p = NSItemProvider()
    // имя без расширения: систему добавляет его сама (с полным именем выходило «файл.pdf.pdf»)
    p.suggestedName = url.deletingPathExtension().lastPathComponent
    let rv = try? url.resourceValues(forKeys: [.typeIdentifierKey, .isDirectoryKey])
    if rv?.isDirectory != true {
        let type = rv?.typeIdentifier ?? UTType.data.identifier
        p.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
    }
    p.registerObject(url as NSURL, visibility: .all)
    let path = url.path
    p.registerDataRepresentation(forTypeIdentifier: startMenuFilePathType, visibility: .ownProcess) { completion in
        completion(path.data(using: .utf8), nil)
        return nil
    }
    return p
}

// MARK: - Модели

struct TPItem: Identifiable {
    let url: URL
    let name: String
    let isDir: Bool
    let isPackage: Bool
    let size: Int64
    let modified: Date?
    var isParent = false
    var mtpHandle: UInt32 = 0       // объект на телефоне (MTP)
    var mtpStorage: UInt32 = 0
    var isStorage = false           // хранилище телефона («Внутренняя память», карта)
    var remotePath = ""             // полный путь на сервере (FTP, SFTP, HTTP)
    var remoteLink = false          // ссылка на сервере: внутрь неё при удалении не заходим
    var id: String { isParent ? ".." : url.path }
}

enum TPDecision { case replace, skip, cancel }

final class TPMenuTarget: NSObject {
    let block: () -> Void
    init(_ b: @escaping () -> Void) { block = b }
    @objc func fire() { block() }
}

/// Общее состояние одной операции копирования с телефоном/на телефон
final class TPXferCtx {
    var all: TPDecision?
    var cancelled = false
    var failed: [String] = []
    var done = 0
    private var cache: [UInt32: [MTPEntry]] = [:]

    func children(_ s: MTPSession, _ storage: UInt32, _ parent: UInt32) throws -> [MTPEntry] {
        if let c = cache[parent] { return c }
        let l = try s.list(storage: storage, parent: parent)
        cache[parent] = l
        return l
    }
}

/// Где сейчас панель, если в ней открыт телефон
struct MTPLoc {
    var session: MTPSession
    var storage: UInt32          // 0 — список хранилищ телефона
    var storageName: String
    var folder: UInt32           // 0xFFFFFFFF — корень хранилища
    var trail: [(handle: UInt32, name: String)]
}

final class TPPane: ObservableObject {
    enum SortKey: String { case name, size, date }

    let key: String
    @Published var dir: URL
    @Published var items: [TPItem] = []
    @Published var cursor = 0
    @Published var marked: Set<String> = []
    @Published var sortKey: SortKey
    @Published var ascending: Bool
    @Published var showHidden: Bool
    @Published var free: Int64 = 0
    @Published var error: String?
    @Published var mtp: MTPLoc?
    @Published var remote: RemoteLoc?
    let search = FileSearch()      // поиск, как в «Пуске»
    var searchActive = false       // поверх списка показаны результаты поиска
    var hitURL: URL?               // выбранная строка результатов поиска
    @Published var displayPath = ""

    // выделение диапазоном (Shift)
    var anchor: Int?
    var rangeBase: Set<String> = []
    var rangeUnmark = false
    var gen = 0

    init(key: String, fallback: URL) {
        self.key = key
        let d = UserDefaults.standard
        var u = fallback
        if let s = d.string(forKey: "tp.\(key).dir") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: s, isDirectory: &isDir), isDir.boolValue {
                u = URL(fileURLWithPath: s, isDirectory: true)
            }
        }
        dir = u
        sortKey = SortKey(rawValue: d.string(forKey: "tp.\(key).sort") ?? "") ?? .name
        ascending = d.object(forKey: "tp.\(key).asc") as? Bool ?? true
        showHidden = d.bool(forKey: "tp.\(key).hidden")
        displayPath = u.path
    }

    var current: TPItem? { items.indices.contains(cursor) ? items[cursor] : nil }

    /// Над чем работают команды: отмеченные, а если ничего не отмечено — файл под курсором
    func targets() -> [TPItem] {
        if searchActive {                     // в режиме поиска работаем с выбранным результатом, а не со списком под ним
            guard let u = hitURL else { return [] }
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey])
            return [TPItem(url: u, name: u.lastPathComponent, isDir: v?.isDirectory ?? false, isPackage: v?.isPackage ?? false,
                           size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate)]
        }
        let m = items.filter { !$0.isParent && !$0.isStorage && marked.contains($0.id) }
        if !m.isEmpty { return m }
        if let c = current, !c.isParent, !c.isStorage { return [c] }
        return []
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(sortKey.rawValue, forKey: "tp.\(key).sort")
        d.set(ascending, forKey: "tp.\(key).asc")
        d.set(showHidden, forKey: "tp.\(key).hidden")
    }

    @discardableResult
    func navigate(to url: URL, select name: String? = nil) -> Bool {
        let u = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue,
              FileManager.default.isReadableFile(atPath: u.path) else { return false }
        mtp = nil
        remote = nil
        dir = u
        displayPath = u.path
        marked = []
        anchor = nil
        cursor = 0
        UserDefaults.standard.set(u.path, forKey: "tp.\(key).dir")
        reload(select: name, keepCurrent: false)
        return true
    }

    func goUp() {
        if remote != nil { goUpRemote(); return }
        if var l = mtp {
            if !l.trail.isEmpty {
                let left = l.trail.removeLast()
                l.folder = l.trail.last?.handle ?? 0xFFFF_FFFF
                mtp = l
                afterMTPMove(select: left.name)
            } else if l.storage != 0 {
                let left = l.storageName
                l.storage = 0
                l.storageName = ""
                l.folder = 0xFFFF_FFFF
                mtp = l
                afterMTPMove(select: left)
            } else {
                let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser
                navigate(to: dl)
            }
            return
        }
        guard dir.path != "/" else { return }
        navigate(to: dir.deletingLastPathComponent(), select: dir.lastPathComponent)
    }

    func reload(select name: String? = nil, keepCurrent: Bool = true) {
        if remote != nil { reloadRemote(select: name, keepCurrent: keepCurrent); return }
        if mtp != nil { reloadMTP(select: name, keepCurrent: keepCurrent); return }
        let d = dir, hidden = showHidden, sk = sortKey, asc = ascending
        var keep = name
        if keep == nil, keepCurrent, let c = current { keep = c.name }
        gen += 1
        let g = gen
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
            var opts: FileManager.DirectoryEnumerationOptions = []
            if !hidden { opts.insert(.skipsHiddenFiles) }
            var urls: [URL] = []
            var err: String?
            do { urls = try fm.contentsOfDirectory(at: d, includingPropertiesForKeys: keys, options: opts) }
            catch { err = error.localizedDescription }
            var arr: [TPItem] = urls.map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                let pkg = v?.isPackage ?? false
                let isDir = (v?.isDirectory ?? false) && !pkg
                return TPItem(url: u, name: u.lastPathComponent, isDir: isDir, isPackage: pkg,
                              size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate)
            }
            func cmp(_ a: TPItem, _ b: TPItem) -> Int {
                switch sk {
                case .name:
                    switch a.name.localizedStandardCompare(b.name) {
                    case .orderedAscending: return -1
                    case .orderedDescending: return 1
                    default: return 0
                    }
                case .size:
                    return a.size == b.size ? 0 : (a.size < b.size ? -1 : 1)
                case .date:
                    let x = a.modified ?? .distantPast, y = b.modified ?? .distantPast
                    return x == y ? 0 : (x < y ? -1 : 1)
                }
            }
            arr.sort { a, b in
                if a.isDir != b.isDir { return a.isDir }
                let c = cmp(a, b)
                if c == 0 { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
                return asc ? c < 0 : c > 0
            }
            if d.path != "/" {
                arr.insert(TPItem(url: d.deletingLastPathComponent(), name: "..", isDir: true, isPackage: false,
                                  size: 0, modified: nil, isParent: true), at: 0)
            }
            let free = (try? d.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage ?? 0
            DispatchQueue.main.async {
                guard let self = self, g == self.gen else { return }
                if err != nil, !FileManager.default.fileExists(atPath: d.path) {
                    let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                        ?? FileManager.default.homeDirectoryForCurrentUser
                    if d.standardizedFileURL.path != dl.standardizedFileURL.path, self.navigate(to: dl) { return }
                }
                self.items = arr
                self.free = free
                self.error = err
                let ids = Set(arr.map { $0.id })
                self.marked = self.marked.intersection(ids)
                if let k = keep, let i = arr.firstIndex(where: { $0.name == k }) {
                    self.cursor = i
                } else {
                    self.cursor = keepCurrent ? max(0, min(self.cursor, arr.count - 1)) : 0
                }
            }
        }
    }

    // MARK: телефон (MTP)

    func updatePath() {
        if let l = remote {
            displayPath = remoteDisplay(l)
        } else if let l = mtp {
            var parts = [l.session.name]
            if l.storage != 0 { parts.append(l.storageName) }
            parts += l.trail.map { $0.name }
            displayPath = "📱 " + parts.joined(separator: " / ")
        } else {
            displayPath = dir.path
        }
    }

    private func afterMTPMove(select name: String?) {
        marked = []
        anchor = nil
        updatePath()
        reload(select: name, keepCurrent: false)
    }

    func enterDevice(_ s: MTPSession) {
        mtp = MTPLoc(session: s, storage: 0, storageName: "", folder: 0xFFFF_FFFF, trail: [])
        cursor = 0
        afterMTPMove(select: nil)
    }

    func enterMTP(_ it: TPItem) {
        guard var l = mtp else { return }
        if it.isStorage {
            l.storage = it.mtpStorage
            l.storageName = it.name
            l.folder = 0xFFFF_FFFF
            l.trail = []
        } else {
            l.trail.append((it.mtpHandle, it.name))
            l.folder = it.mtpHandle
        }
        mtp = l
        cursor = 0
        afterMTPMove(select: nil)
    }

    static func sortItems(_ arr: inout [TPItem], _ sk: SortKey, _ asc: Bool) {
        func cmp(_ a: TPItem, _ b: TPItem) -> Int {
            switch sk {
            case .name:
                switch a.name.localizedStandardCompare(b.name) {
                case .orderedAscending: return -1
                case .orderedDescending: return 1
                default: return 0
                }
            case .size: return a.size == b.size ? 0 : (a.size < b.size ? -1 : 1)
            case .date:
                let x = a.modified ?? .distantPast, y = b.modified ?? .distantPast
                return x == y ? 0 : (x < y ? -1 : 1)
            }
        }
        arr.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            let c = cmp(a, b)
            if c == 0 { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return asc ? c < 0 : c > 0
        }
    }

    private func reloadMTP(select name: String?, keepCurrent: Bool) {
        guard let loc = mtp else { return }
        var keep = name
        if keep == nil, keepCurrent, let c = current { keep = c.name }
        gen += 1
        let g = gen
        let sk = sortKey, asc = ascending
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var arr: [TPItem] = []
            var err: String?
            var free: Int64 = 0
            do {
                if loc.storage == 0 {
                    for st in try loc.session.storages() {
                        arr.append(TPItem(url: URL(fileURLWithPath: "/mtp/s\(st.id)"), name: st.name, isDir: true, isPackage: false,
                                          size: 0, modified: nil, isParent: false, mtpHandle: 0xFFFF_FFFF, mtpStorage: st.id, isStorage: true))
                    }
                } else {
                    for e in try loc.session.list(storage: loc.storage, parent: loc.folder) {
                        arr.append(TPItem(url: URL(fileURLWithPath: "/mtp/\(e.storage)/\(e.handle)"), name: e.name, isDir: e.isDir,
                                          isPackage: false, size: e.size, modified: e.modified, isParent: false,
                                          mtpHandle: e.handle, mtpStorage: e.storage, isStorage: false))
                    }
                    free = (try? loc.session.storageInfo(loc.storage).free) ?? 0
                }
            } catch { err = error.localizedDescription }
            TPPane.sortItems(&arr, sk, asc)
            arr.insert(TPItem(url: URL(fileURLWithPath: "/mtp/up"), name: "..", isDir: true, isPackage: false,
                              size: 0, modified: nil, isParent: true), at: 0)
            DispatchQueue.main.async {
                guard let self = self, g == self.gen else { return }
                self.items = arr
                self.free = free
                self.error = err
                self.marked = self.marked.intersection(Set(arr.map { $0.id }))
                if let k = keep, let i = arr.firstIndex(where: { $0.name == k }) { self.cursor = i }
                else { self.cursor = keepCurrent ? max(0, min(self.cursor, arr.count - 1)) : 0 }
            }
        }
    }

    func beginRange() {
        guard anchor == nil else { return }
        anchor = cursor
        rangeBase = marked
        rangeUnmark = current.map { marked.contains($0.id) } ?? false
    }

    func applyRange(to idx: Int) {
        guard let a = anchor, items.indices.contains(a), items.indices.contains(idx) else { return }
        let lo = min(a, idx), hi = max(a, idx)
        let ids = Set(items[lo...hi].filter { !$0.isParent }.map { $0.id })
        marked = rangeUnmark ? rangeBase.subtracting(ids) : rangeBase.union(ids)
    }
}

// MARK: - Пакетное переименование

final class TPRenameModel: ObservableObject {
    let items: [TPItem]
    let dir: URL
    @Published var mask = "[N]"
    @Published var extMask = "[E]"
    @Published var find = ""
    @Published var replace = ""
    @Published var caseMode = 0
    @Published var start = 1
    @Published var step = 1
    @Published var digits = 1
    private let others: Set<String>
    let mtp: MTPLoc?

    init(items: [TPItem], dir: URL, existing: [String]? = nil, mtp: MTPLoc? = nil) {
        self.items = items
        self.dir = dir
        self.mtp = mtp
        let mine = Set(items.map { $0.name.lowercased() })
        let all = existing ?? ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        others = Set(all.map { $0.lowercased() }).subtracting(mine)
    }

    private static func fmt(_ f: String, _ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = f
        return df.string(from: d)
    }

    private func parts(_ i: Int) -> (name: String, ext: String) {
        let it = items[i]
        let ns = it.name as NSString
        let base = it.isDir ? it.name : ns.deletingPathExtension
        let ext = it.isDir ? "" : ns.pathExtension
        let counter = String(format: "%0\(max(1, digits))d", start + i * step)
        let date = it.modified ?? Date()

        func token(_ c: Character) -> String? {
            switch c {
            case "N": return base
            case "E": return ext
            case "C": return counter
            case "Y": return TPRenameModel.fmt("yyyy", date)
            case "M": return TPRenameModel.fmt("MM", date)
            case "D": return TPRenameModel.fmt("dd", date)
            default: return nil
            }
        }
        func sub(_ m: String) -> String {
            var out = ""
            let chars = Array(m)
            var k = 0
            while k < chars.count {
                if chars[k] == "[", k + 2 < chars.count, chars[k + 2] == "]", let t = token(chars[k + 1]) {
                    out += t
                    k += 3
                } else {
                    out.append(chars[k])
                    k += 1
                }
            }
            return out
        }

        var name = sub(mask)
        let e = it.isDir ? "" : sub(extMask)
        if !find.isEmpty { name = name.replacingOccurrences(of: find, with: replace) }
        switch caseMode {
        case 1: name = name.lowercased()
        case 2: name = name.uppercased()
        case 3: name = name.prefix(1).uppercased() + name.dropFirst().lowercased()
        default: break
        }
        return (name, e)
    }

    private func join(_ n: String, _ e: String) -> String { e.isEmpty ? n : n + "." + e }

    /// Новые имена. Если в масках нет [C], а имена получились одинаковыми, к каждому имени добавляется номер
    /// по настройкам счётчика (начало, шаг, цифр).
    func allNames() -> [String] {
        let ps = (0..<items.count).map { parts($0) }
        let hasC = mask.contains("[C]") || extMask.contains("[C]")
        var seen = Set<String>()
        var dup = false
        for p in ps where !seen.insert(join(p.name, p.ext).lowercased()).inserted { dup = true; break }
        guard dup, !hasC else { return ps.map { join($0.name, $0.ext) } }
        return ps.enumerated().map { i, p in
            let counter = String(format: "%0\(max(1, digits))d", start + i * step)
            return join(p.name.trimmingCharacters(in: .whitespaces) + " " + counter, p.ext)
        }
    }

    /// Новые имена и ошибки по каждой строке
    func previews() -> [(old: String, new: String, err: String?)] {
        let names = allNames()
        var count: [String: Int] = [:]
        for n in names { count[n.lowercased(), default: 0] += 1 }
        return items.enumerated().map { i, it in
            let n = names[i]
            var err: String?
            if n.isEmpty || n == "." || n == ".." { err = T("Имя не может быть пустым") }
            else if n.contains("/") || n.contains(":") { err = T("Недопустимое имя") }
            else if (count[n.lowercased()] ?? 0) > 1 { err = T("Повторяющееся имя") }
            else if others.contains(n.lowercased()) { err = T("Уже существует") }
            return (it.name, n, err)
        }
    }

    func apply() -> (done: Int, errors: [String], first: String?) {
        let fm = FileManager.default
        var errors: [String] = []
        var done = 0
        var first: String?
        let names = allNames()
        if let m = mtp {                       // телефон: переименование на месте
            for (i, it) in items.enumerated() {
                let nn = names[i]
                if nn == it.name { continue }
                do {
                    try m.session.rename(handle: it.mtpHandle, to: nn)
                    done += 1
                    if first == nil { first = nn }
                } catch { errors.append(it.name + ": " + error.localizedDescription) }
            }
            return (done, errors, first)
        }
        var temps: [(tmp: URL, final: URL, orig: URL)] = []
        // сначала во временные имена: так можно переименовать «по кругу» без конфликтов
        for (i, it) in items.enumerated() {
            let nn = names[i]
            if nn == it.name { continue }
            let tmp = dir.appendingPathComponent(".tprn-" + UUID().uuidString)
            do {
                try fm.moveItem(at: it.url, to: tmp)
                temps.append((tmp, dir.appendingPathComponent(nn), it.url))
            } catch { errors.append(it.name + ": " + error.localizedDescription) }
        }
        for t in temps {
            do {
                try fm.moveItem(at: t.tmp, to: t.final)
                done += 1
                if first == nil { first = t.final.lastPathComponent }
            } catch {
                errors.append(t.orig.lastPathComponent + ": " + error.localizedDescription)
                try? fm.moveItem(at: t.tmp, to: t.orig)
            }
        }
        return (done, errors, first)
    }
}

struct TPRenameView: View {
    @ObservedObject var model: TPRenameModel
    let onCancel: () -> Void
    let onApply: () -> Void

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 140, alignment: .trailing)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    var body: some View {
        let pv = model.previews()
        let changed = pv.contains { $0.old != $0.new }
        let bad = pv.contains { $0.err != nil }
        VStack(alignment: .leading, spacing: 10) {
            Text(T("Пакетное переименование")).font(.headline)
            Text(Tf("Объектов: %@", "\(model.items.count)")).foregroundColor(.secondary)
            field(T("Маска имени"), $model.mask)
            field(T("Маска расширения"), $model.extMask)
            field(T("Найти"), $model.find)
            field(T("Заменить на"), $model.replace)
            HStack {
                Text(T("Регистр")).frame(width: 140, alignment: .trailing)
                Picker("", selection: $model.caseMode) {
                    Text(T("Как есть")).tag(0)
                    Text(T("строчные")).tag(1)
                    Text(T("ПРОПИСНЫЕ")).tag(2)
                    Text(T("С заглавной")).tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(spacing: 16) {
                Stepper(value: $model.start, in: 0...999999) { Text(T("Счётчик: начало") + " \(model.start)") }
                Stepper(value: $model.step, in: 1...1000) { Text(T("шаг") + " \(model.step)") }
                Stepper(value: $model.digits, in: 1...8) { Text(T("цифр") + " \(model.digits)") }
            }
            Text(T("Метки: [N] имя, [E] расширение, [C] счётчик, [Y][M][D] дата"))
                .font(.caption).foregroundColor(.secondary)
            Text(T("Если в маске нет [C], а имена совпадают, номер добавляется автоматически."))
                .font(.caption).foregroundColor(.secondary)
            Divider()
            HStack {
                Text(T("Было")).frame(maxWidth: .infinity, alignment: .leading)
                Text(T("Стало")).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption).foregroundColor(.secondary)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(pv.enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .top) {
                            Text(r.old).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r.new).lineLimit(1).truncationMode(.middle)
                                    .foregroundColor(r.err != nil ? .red : (r.old != r.new ? .accentColor : .primary))
                                if let e = r.err { Text(e).font(.caption2).foregroundColor(.red) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            .frame(height: 170)
            HStack {
                Spacer()
                Button(T("Отмена"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(T("Переименовать"), action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!changed || bad)
            }
        }
        .padding(18)
        .frame(width: 640)
    }
}

// MARK: - Состояние и команды

final class TPState: ObservableObject {
    static let shared = TPState()

    let panes: [TPPane]
    @Published var active = 0
    @Published var status = ""
    @Published var busy = false
    weak var window: NSWindow?
    var qlProc: Process?
    @Published var mtpDevices: [MTPDeviceInfo] = []
    private var missing = 0
    private var bag = Set<AnyCancellable>()

    init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dl = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home
        panes = [TPPane(key: "left", fallback: home), TPPane(key: "right", fallback: dl)]
        for p in panes { p.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag) }
        // флешку или диск отключили, пока панель на нём: переходим в «Загрузки»
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didUnmountNotification, NSWorkspace.willUnmountNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                guard let self = self, let vol = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                let vp = vol.standardizedFileURL.path
                for p in self.panes where p.dir.path == vp || p.dir.path.hasPrefix(vp + "/") {
                    p.navigate(to: dl)
                }
            }
        }
    }

    var src: TPPane { panes[active] }
    var dst: TPPane { panes[1 - active] }

    func reloadAll() { panes.forEach { $0.reload() } }

    func clearKeyFocus() { window?.makeFirstResponder(nil) }

    // MARK: мышь

    func click(pane: TPPane, index: Int, row: Int) {
        active = index
        clearKeyFocus()
        guard pane.items.indices.contains(row) else { return }
        let mods = NSEvent.modifierFlags
        if mods.contains(.shift) {
            pane.beginRange()
            pane.cursor = row
            pane.applyRange(to: row)
        } else if mods.contains(.command) {
            let it = pane.items[row]
            if !it.isParent {
                if pane.marked.contains(it.id) { pane.marked.remove(it.id) } else { pane.marked.insert(it.id) }
            }
            pane.cursor = row
            pane.anchor = nil
        } else {
            pane.cursor = row
            pane.anchor = nil
            pane.marked = []
        }
    }

    func open(_ pane: TPPane, _ it: TPItem) {
        if it.isParent { pane.goUp(); return }
        if pane.remote != nil {
            if it.isDir { pane.enterRemoteDir(it) }
            else if let loc = pane.remote { remoteFetchTemp(loc, it) { NSWorkspace.shared.open($0) } }
            return
        }
        if pane.mtp != nil { if it.isDir { pane.enterMTP(it) }; return }     // файлы на телефоне не открываем
        if it.isDir { pane.navigate(to: it.url) } else { NSWorkspace.shared.open(it.url) }
    }

    // MARK: клавиатура

    /// Поля ввода панели сверху вниз: первое — путь, второе — поиск (у панели с телефоном поиска нет)
    private func paneFields(_ idx: Int, _ root: NSView) -> [NSTextField] {
        func frameInWindow(_ v: NSView) -> NSRect { v.convert(v.bounds, to: nil) }
        func editableFields(_ v: NSView) -> [NSTextField] {
            var r: [NSTextField] = []
            for s in v.subviews {
                if let t = s as? NSTextField, t.isEditable, !t.isHidden { r.append(t) }
                r += editableFields(s)
            }
            return r
        }
        let half = root.bounds.width / 2
        return editableFields(root)
            .filter { (frameInWindow($0).midX < half ? 0 : 1) == idx }
            .sorted { frameInWindow($0).midY > frameInWindow($1).midY }
    }

    /// Стрелки вверх и вниз между полем пути, полем поиска и списком файлов; влево и вправо в полях работают как обычно.
    func handleFieldKey(_ e: NSEvent, _ tv: NSTextView, _ w: NSWindow) -> Bool {
        guard e.keyCode == 125 || e.keyCode == 126,
              e.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
              !tv.hasMarkedText(),
              let field = tv.delegate as? NSTextField, field.isEditable,
              let root = w.contentView else { return false }
        let idx = field.convert(field.bounds, to: nil).midX < root.bounds.width / 2 ? 0 : 1
        let fields = paneFields(idx, root)
        guard let pos = fields.firstIndex(where: { $0 === field }) else { return false }
        active = idx
        if e.keyCode == 125 {
            if pos + 1 < fields.count { w.makeFirstResponder(fields[pos + 1]) } else { clearKeyFocus() }
        } else {
            guard pos > 0 else { return false }        // выше поля пути идти некуда: курсор ведёт себя как в обычном поле
            w.makeFirstResponder(fields[pos - 1])
        }
        return true
    }

    /// Со списка файлов вверх: из первой строки — в поле поиска (а если его нет — в поле пути)
    private func focusFieldsAbove(_ idx: Int) -> Bool {
        guard let w = window, let root = w.contentView else { return false }
        let fields = paneFields(idx, root)
        guard let target = fields.last else { return false }
        w.makeFirstResponder(target)
        return true
    }

    func handleKey(_ e: NSEvent) -> Bool {
        let f = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let cmd = f.contains(.command), shift = f.contains(.shift), opt = f.contains(.option)
        let p = src
        if cmd {
            switch e.keyCode {
            case 0: markAll(p); return true                       // ⌘A
            case 15: reloadAll(); return true                      // ⌘R
            case 47: if shift { p.showHidden.toggle(); p.saveSettings(); p.reload(); return true }   // ⌘⇧.
            case 51: deleteSelected(); return true                 // ⌘⌫
            default: break
            }
            return false
        }
        switch e.keyCode {
        case 48: active = 1 - active; return true                  // Tab
        case 123: active = 0; return true
        case 124: active = 1; return true
        case 126:
            if opt { moveCursor(p, to: p.cursor - 15, extend: shift); return true }      // ⌥↑ — страница вверх, как PgUp
            if !shift, p.cursor <= 0, focusFieldsAbove(active) { return true }
            moveCursor(p, to: p.cursor - 1, extend: shift); return true
        case 125: moveCursor(p, to: p.cursor + (opt ? 15 : 1), extend: shift); return true      // ⌥↓ — страница вниз, как PgDn
        case 116: moveCursor(p, to: p.cursor - 15, extend: shift); return true
        case 121: moveCursor(p, to: p.cursor + 15, extend: shift); return true
        case 115: moveCursor(p, to: 0, extend: shift); return true
        case 119: moveCursor(p, to: p.items.count - 1, extend: shift); return true
        case 36, 76: if let c = p.current { open(p, c) }; return true
        case 51: p.goUp(); return true
        case 117, 100: deleteSelected(); return true               // Delete, F8
        case 49, 114: toggleMarkAndDown(p); return true            // Space, Insert
        case 53: p.marked = []; p.anchor = nil; return true        // Esc
        case 120: renameSelected(); return true                    // F2
        case 99: quickLook(); return true                          // F3
        case 118: editFile(); return true                          // F4
        case 96: copyMove(move: false); return true               // F5
        case 97: if shift { renameSelected() } else { copyMove(move: true) }; return true   // F6
        case 98: newFolder(); return true                          // F7
        case 69: markAll(p); return true                           // Num +
        case 78: p.marked = []; return true                        // Num -
        case 67:                                                    // Num *
            let ids = Set(p.items.filter { !$0.isParent }.map { $0.id })
            p.marked = ids.subtracting(p.marked)
            return true
        default: return false
        }
    }

    func markAll(_ p: TPPane) {
        p.marked = Set(p.items.filter { !$0.isParent }.map { $0.id })
        p.anchor = nil
    }

    func moveCursor(_ p: TPPane, to new: Int, extend: Bool) {
        guard !p.items.isEmpty else { return }
        let n = max(0, min(p.items.count - 1, new))
        if extend {
            p.beginRange()
            p.cursor = n
            p.applyRange(to: n)
        } else {
            p.anchor = nil
            p.cursor = n
        }
    }

    func toggleMarkAndDown(_ p: TPPane) {
        if let c = p.current, !c.isParent {
            if p.marked.contains(c.id) { p.marked.remove(c.id) } else { p.marked.insert(c.id) }
        }
        p.anchor = nil
        if p.cursor + 1 < p.items.count { p.cursor += 1 }
    }

    // MARK: диалоги

    static func prompt(title: String, info: String?, value: String, ok: String, selectBase: Bool = false) -> String? {
        let a = NSAlert()
        a.messageText = title
        if let i = info { a.informativeText = i }
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        f.stringValue = value
        a.accessoryView = f
        a.addButton(withTitle: ok)
        a.addButton(withTitle: T("Отмена"))
        a.window.initialFirstResponder = f
        DispatchQueue.main.async {
            a.window.makeFirstResponder(f)
            if selectBase, let ed = f.currentEditor() {
                let n = (value as NSString).deletingPathExtension.count
                ed.selectedRange = NSRange(location: 0, length: n)
            }
        }
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
    }

    static func askConflict(_ name: String, multiple: Bool, device: Bool = false, remote: Bool = false) -> (TPDecision, Bool) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = Tf("«%@» уже существует", name)
        a.informativeText = remote ? T("Заменить файл? Старый будет удалён с сервера.")
            : (device ? T("Заменить файл? Старый будет удалён с телефона.") : T("Заменить файл? Старый уйдёт в Корзину."))
        a.addButton(withTitle: T("Заменить"))
        a.addButton(withTitle: T("Пропустить"))
        a.addButton(withTitle: T("Отмена"))
        if multiple {
            a.showsSuppressionButton = true
            a.suppressionButton?.title = T("Применить ко всем")
        }
        let r = a.runModal()
        let all = a.suppressionButton?.state == .on
        switch r {
        case .alertFirstButtonReturn: return (.replace, all)
        case .alertSecondButtonReturn: return (.skip, all)
        default: return (.cancel, false)
        }
    }

    static func showErrors(_ list: [String]) {
        guard !list.isEmpty else { return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = T("Ошибка")
        a.informativeText = list.prefix(10).joined(separator: "\n") + (list.count > 10 ? "\n…" : "")
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    func summary(_ t: [TPItem]) -> String {
        t.count == 1 ? t[0].name : Tf("Объектов: %@", "\(t.count)")
    }

    // MARK: копирование и перемещение

    func copyMove(move: Bool) {
        let p = src
        let t = p.targets()
        guard !t.isEmpty else { return }
        if p.remote != nil || dst.remote != nil {
            if move { remoteNote(); return }                 // с сервером — без переноса: только копирование
            remoteCopy(p, t)
            return
        }
        if p.mtp != nil || dst.mtp != nil {
            if move { phoneRestricted(); return }          // с телефоном — только копирование
            mtpCopy(p, t)
            return
        }
        let title = Tf(move ? "Переместить: %@" : "Копировать: %@", summary(t))
        guard let dest = TPState.prompt(title: title, info: T("Куда:"), value: dst.dir.path,
                                        ok: move ? T("Переместить") : T("Копировать")) else { return }
        let path = (dest.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard !path.isEmpty else { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            if !isDir.boolValue { TPState.showErrors([path + ": " + T("Не папка")]); return }
        } else {
            do { try fm.createDirectory(atPath: path, withIntermediateDirectories: true) }
            catch { TPState.showErrors([error.localizedDescription]); return }
        }
        p.marked = []
        transfer(t.map { $0.url }, to: URL(fileURLWithPath: path, isDirectory: true), move: move)
    }

    func transfer(_ urls: [URL], to dir: URL, move: Bool, cleanTemp: Bool = false) {
        guard !urls.isEmpty else { return }
        busy = true
        let total = urls.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            var done = 0
            var failed: [String] = []
            var all: TPDecision?
            let destPath = dir.standardizedFileURL.path
            for (n, u) in urls.enumerated() {
                let src = u.standardizedFileURL
                defer {
                    if cleanTemp {
                        let par = src.deletingLastPathComponent()
                        if par.lastPathComponent.hasPrefix("dc-drop-") { try? fm.removeItem(at: par) }
                    }
                }
                let name = u.lastPathComponent
                DispatchQueue.main.async { self.status = Tf("Обработано %@ из %@", "\(n)", "\(total)") + " — " + name }
                let target = dir.appendingPathComponent(name)
                if src.path == target.standardizedFileURL.path { continue }
                if (destPath + "/").hasPrefix(src.path + "/") {
                    failed.append(name + ": " + T("нельзя поместить папку в саму себя"))
                    continue
                }
                if fm.fileExists(atPath: target.path) {
                    var d: TPDecision
                    if let a = all { d = a } else {
                        var res: (TPDecision, Bool) = (.cancel, false)
                        DispatchQueue.main.sync { res = TPState.askConflict(name, multiple: total - n > 1) }
                        d = res.0
                        if res.1 { all = d }
                    }
                    if d == .cancel { break }
                    if d == .skip { continue }
                    do { try fm.trashItem(at: target, resultingItemURL: nil) }
                    catch { failed.append(name + ": " + error.localizedDescription); continue }
                }
                do {
                    if move { try fm.moveItem(at: src, to: target) } else { try fm.copyItem(at: src, to: target) }
                    done += 1
                } catch { failed.append(name + ": " + error.localizedDescription) }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.status = Tf(move ? "Перемещено: %@" : "Скопировано: %@", "\(done)")
                self.reloadAll()
                TPState.showErrors(failed)
            }
        }
    }

    /// Файлы, брошенные на панель из результатов поиска «Пуска», Finder или другой программы: копия в текущую папку панели
    func handleDrop(_ providers: [NSItemProvider], into pane: TPPane) -> Bool {
        let lock = NSLock()
        var urls: [URL] = []
        let g = DispatchGroup()
        for p in providers {
            g.enter()
            loadDroppedFile(p) { u in
                lock.lock(); urls.append(u); lock.unlock()
                g.leave()
            }
        }
        g.notify(queue: .main) { [weak self] in
            if let loc = pane.remote { self?.remoteUpload(urls, to: loc, cleanTemp: true) }
            else if let loc = pane.mtp { self?.mtpUpload(urls, to: loc, cleanTemp: true) }
            else { self?.transfer(urls, to: pane.dir, move: false, cleanTemp: true) }
        }
        return true
    }

    /// Меню «диски и устройства»: список строится в момент нажатия, поэтому всегда свежий
    func showPlacesMenu(pane: TPPane, index: Int) {
        active = index
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let t = TPMenuTarget(action)
            let it = NSMenuItem(title: title, action: #selector(TPMenuTarget.fire), keyEquivalent: "")
            it.target = t
            it.representedObject = t          // target слабая ссылка: держим объект в пункте меню
            menu.addItem(it)
        }
        add(T("Домой")) { pane.navigate(to: home) }
        add(T("Рабочий стол")) { pane.navigate(to: home.appendingPathComponent("Desktop")) }
        add(T("Документы")) { pane.navigate(to: home.appendingPathComponent("Documents")) }
        add(T("Загрузки")) { pane.navigate(to: home.appendingPathComponent("Downloads")) }
        add(T("Программы")) { pane.navigate(to: URL(fileURLWithPath: "/Applications")) }
        add(T("Корень диска")) { pane.navigate(to: URL(fileURLWithPath: "/")) }
        // папки из «Избранного» Finder (кроме тех, что уже есть выше)
        let standard: Set<String> = [home.path, home.appendingPathComponent("Desktop").path, home.appendingPathComponent("Documents").path,
                                     home.appendingPathComponent("Downloads").path, "/Applications", "/"]
        let fav = FinderFavorites.load()
        let favs = fav.folders.filter { !standard.contains($0.path) }
        if !favs.isEmpty || fav.note != nil {
            menu.addItem(.separator())
            for u in favs {
                add(fm.displayName(atPath: u.path)) { pane.navigate(to: u) }
                let icon = NSWorkspace.shared.icon(forFile: u.path)
                icon.size = NSSize(width: 16, height: 16)
                menu.items.last?.image = icon
            }
            if let n = fav.note { menu.addItem(NSMenuItem(title: n, action: nil, keyEquivalent: "")) }
        }
        menu.addItem(.separator())
        add(T("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([pane.dir]) }
        menu.addItem(.separator())
        let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        for v in vols {
            let name = (try? v.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? v.lastPathComponent
            add(name.isEmpty ? "/" : name) { pane.navigate(to: v) }
        }
        menu.addItem(.separator())
        for s in RemoteStore.load() { add("🌐 " + s.name) { [weak self] in self?.connectRemote(pane, s, index: index) } }
        add(T("Серверы FTP, SFTP, HTTP…")) { [weak self] in self?.showRemoteManager(pane: pane, index: index) }
        menu.addItem(.separator())
        let devs = MTPScanner.scan()          // свежий опрос USB в момент нажатия
        if devs.map({ $0.id }) != mtpDevices.map({ $0.id }) { mtpDevices = devs }
        if devs.isEmpty {
            menu.addItem(NSMenuItem(title: T("Android: не найден (на телефоне выберите «Передача файлов»)"), action: nil, keyEquivalent: ""))
        }
        for d in devs { add("📱 " + d.name) { [weak self] in self?.connectMTP(pane, d, index: index) } }
        if let w = window, let ev = NSApp.currentEvent, let v = w.contentView {
            NSMenu.popUpContextMenu(menu, with: ev, for: v)
        }
    }

    // MARK: телефон (MTP): только копирование, переименование и удаление

    func phoneRestricted() {
        status = T("С телефоном доступны только копирование, переименование и удаление")
    }

    func refreshDevices() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = MTPScanner.scan()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if list.map({ $0.id }) != self.mtpDevices.map({ $0.id }) { self.mtpDevices = list }
                let gone = self.panes.filter { p in
                    p.mtp.map { l in !list.contains(where: { $0.id == l.session.id }) } ?? false
                }
                if gone.isEmpty { self.missing = 0; return }
                self.missing += 1
                if self.missing >= 2 {            // телефон пропал два опроса подряд: возвращаем панель в «Загрузки»
                    let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                        ?? FileManager.default.homeDirectoryForCurrentUser
                    for p in gone { p.navigate(to: dl) }
                    self.status = T("Телефон отключён")
                    self.missing = 0
                }
            }
        }
    }

    func connectMTP(_ pane: TPPane, _ info: MTPDeviceInfo, index: Int) {
        active = index
        busy = true
        status = T("Подключение к устройству…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let s = try MTPSession.session(for: info)
                _ = try s.storages()               // телефон разблокирован и отдаёт хранилища
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.status = ""
                    pane.enterDevice(s)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.busy = false
                    self?.status = ""
                    TPState.showErrors([error.localizedDescription])
                }
            }
        }
    }

    func mtpAsync(_ work: @escaping () throws -> Void, done: @escaping () -> Void) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var err: Error?
            do { try work() } catch { err = error }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                done()
                if let e = err { TPState.showErrors([e.localizedDescription]) }
            }
        }
    }

    func mtpCopy(_ sp: TPPane, _ t: [TPItem]) {
        let dp = dst
        if sp.mtp != nil && dp.mtp != nil {
            TPState.showErrors([T("Копирование между двумя телефонами не поддерживается")])
            return
        }
        if let d = dp.mtp, d.storage == 0 {
            TPState.showErrors([T("Откройте хранилище телефона (например, «Внутренняя память») в панели назначения")])
            return
        }
        let a = NSAlert()
        a.messageText = Tf("Копировать: %@", summary(t))
        a.informativeText = T("Куда:") + " " + dp.displayPath
        a.addButton(withTitle: T("Копировать"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        sp.marked = []
        if let d = dp.mtp { mtpUpload(t.map { $0.url }, to: d, cleanTemp: false) }
        else if let s = sp.mtp { mtpDownload(t, from: s, to: dp.dir) }
    }

    private func mtpDecide(_ name: String, _ ctx: TPXferCtx, device: Bool) -> TPDecision {
        if let a = ctx.all { return a }
        var res: (TPDecision, Bool) = (.cancel, false)
        DispatchQueue.main.sync { res = TPState.askConflict(name, multiple: true, device: device) }
        if res.1 { ctx.all = res.0 }
        if res.0 == .cancel { ctx.cancelled = true }
        return res.0
    }

    func mtpUpload(_ urls: [URL], to loc: MTPLoc, cleanTemp: Bool) {
        guard loc.storage != 0 else {
            TPState.showErrors([T("Откройте хранилище телефона (например, «Внутренняя память») в панели назначения")])
            return
        }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ctx = TPXferCtx()
            for (n, u) in urls.enumerated() {
                if ctx.cancelled { break }
                DispatchQueue.main.async { self.status = Tf("Обработано %@ из %@", "\(n)", "\(urls.count)") + " — " + u.lastPathComponent }
                _ = self.mtpUploadItem(loc.session, u, storage: loc.storage, parent: loc.folder, ctx: ctx)
                if cleanTemp {
                    let par = u.deletingLastPathComponent()
                    if par.lastPathComponent.hasPrefix("dc-drop-") { try? FileManager.default.removeItem(at: par) }
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.status = Tf("Скопировано: %@", "\(ctx.done)")
                self.reloadAll()
                TPState.showErrors(ctx.failed)
            }
        }
    }

    private func mtpUploadItem(_ s: MTPSession, _ url: URL, storage: UInt32, parent: UInt32, ctx: TPXferCtx) -> Bool {
        let fm = FileManager.default
        let name = url.lastPathComponent
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        do {
            let existing = try ctx.children(s, storage, parent).first { $0.name == name }
            if isDir.boolValue {
                var folder: UInt32
                if let e = existing, e.isDir {
                    folder = e.handle
                } else {
                    if let e = existing {
                        guard mtpDecide(name, ctx, device: true) == .replace else { return false }
                        try s.deleteRecursive(e)
                    }
                    folder = try s.makeFolder(name: name, storage: storage, parent: parent)
                }
                var ok = true
                let kids = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for k in kids {
                    if ctx.cancelled { return false }
                    if !mtpUploadItem(s, k, storage: storage, parent: folder, ctx: ctx) { ok = false }
                }
                return ok
            } else {
                if let e = existing {
                    guard mtpDecide(name, ctx, device: true) == .replace else { return false }
                    try s.deleteRecursive(e)
                }
                try s.upload(file: url, storage: storage, parent: parent)
                ctx.done += 1
                return true
            }
        } catch {
            ctx.failed.append(name + ": " + error.localizedDescription)
            return false
        }
    }

    func mtpDownload(_ items: [TPItem], from loc: MTPLoc, to dir: URL) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ctx = TPXferCtx()
            for (n, it) in items.enumerated() {
                if ctx.cancelled { break }
                DispatchQueue.main.async { self.status = Tf("Обработано %@ из %@", "\(n)", "\(items.count)") + " — " + it.name }
                let e = MTPEntry(handle: it.mtpHandle, storage: it.mtpStorage, name: it.name, isDir: it.isDir, size: it.size, modified: it.modified)
                _ = self.mtpDownloadItem(loc.session, e, to: dir, ctx: ctx)
            }
            DispatchQueue.main.async {
                self.busy = false
                self.status = Tf("Скопировано: %@", "\(ctx.done)")
                self.reloadAll()
                TPState.showErrors(ctx.failed)
            }
        }
    }

    private func mtpDownloadItem(_ s: MTPSession, _ e: MTPEntry, to dir: URL, ctx: TPXferCtx) -> Bool {
        let fm = FileManager.default
        let safe = e.name.replacingOccurrences(of: "/", with: "_")
        let target = dir.appendingPathComponent(safe)
        do {
            if e.isDir {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
                    guard mtpDecide(safe, ctx, device: false) == .replace else { return false }
                    try fm.trashItem(at: target, resultingItemURL: nil)
                }
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                var ok = true
                for c in try s.list(storage: e.storage, parent: e.handle) {
                    if ctx.cancelled { return false }
                    if !mtpDownloadItem(s, c, to: target, ctx: ctx) { ok = false }
                }
                return ok
            } else {
                if fm.fileExists(atPath: target.path) {
                    guard mtpDecide(safe, ctx, device: false) == .replace else { return false }
                    try fm.trashItem(at: target, resultingItemURL: nil)
                }
                try s.download(handle: e.handle, to: target)
                ctx.done += 1
                return true
            }
        } catch {
            ctx.failed.append(safe + ": " + error.localizedDescription)
            return false
        }
    }

    func mtpDelete(_ p: TPPane, _ t: [TPItem]) {
        guard let loc = p.mtp else { return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = Tf("Удалить с телефона навсегда: %@?", summary(t))
        a.informativeText = T("Файлы не попадут в Корзину.")
        a.addButton(withTitle: T("Удалить"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        p.marked = []
        let entries = t.map { MTPEntry(handle: $0.mtpHandle, storage: $0.mtpStorage, name: $0.name, isDir: $0.isDir, size: $0.size, modified: $0.modified) }
        mtpAsync({ for e in entries { try loc.session.deleteRecursive(e) } }) {
            self.status = Tf("Удалено: %@", "\(t.count)")
            self.reloadAll()
        }
    }

    // MARK: удаление

    func deleteSelected() {
        let p = src
        let t = p.targets()
        guard !t.isEmpty else { return }
        if p.remote != nil { remoteDelete(p, t); return }
        if p.mtp != nil { mtpDelete(p, t); return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = Tf("Удалить в Корзину: %@?", summary(t))
        if t.count > 1 {
            a.informativeText = t.prefix(10).map { $0.name }.joined(separator: "\n") + (t.count > 10 ? "\n…" : "")
        }
        a.addButton(withTitle: T("В Корзину"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        p.marked = []
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var done = 0
            var failed: [String] = []
            for it in t {
                do { try FileManager.default.trashItem(at: it.url, resultingItemURL: nil); done += 1 }
                catch { failed.append(it.name + ": " + error.localizedDescription) }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                self.status = Tf("Удалено: %@", "\(done)")
                self.reloadAll()
                TPState.showErrors(failed)
            }
        }
    }

    // MARK: переименование, новая папка

    func renameSelected() {
        let p = src
        let t = p.targets()
        guard !t.isEmpty else { return }
        if p.remote != nil { remoteRename(p, t); return }
        if t.count > 1 { batchRename(t, in: p); return }
        let it = t[0]
        guard let nn = TPState.prompt(title: T("Переименовать"), info: T("Новое имя:"), value: it.name,
                                      ok: T("Переименовать"), selectBase: !it.isDir) else { return }
        let name = nn.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != it.name else { return }
        if name.contains("/") { TPState.showErrors([T("Недопустимое имя")]); return }
        if let loc = p.mtp {
            mtpAsync({ try loc.session.rename(handle: it.mtpHandle, to: name) }) {
                self.status = Tf("Переименовано: %@", "1")
                p.reload(select: name)
            }
            return
        }
        do {
            try FileManager.default.moveItem(at: it.url, to: it.url.deletingLastPathComponent().appendingPathComponent(name))
            status = Tf("Переименовано: %@", "1")
            reloadAll()
            p.reload(select: name)
        } catch { TPState.showErrors([error.localizedDescription]) }
    }

    func batchRename(_ items: [TPItem], in pane: TPPane) {
        guard let parent = window else { return }
        let model = TPRenameModel(items: items, dir: pane.dir,
                                  existing: pane.mtp != nil ? pane.items.map { $0.name } : nil, mtp: pane.mtp)
        var sheet: NSWindow!
        let view = TPRenameView(model: model, onCancel: { parent.endSheet(sheet) }, onApply: { [weak self] in
            let r = model.apply()
            parent.endSheet(sheet)
            pane.marked = []
            self?.status = Tf("Переименовано: %@", "\(r.done)")
            self?.reloadAll()
            if let f = r.first { pane.reload(select: f) }
            TPState.showErrors(r.errors)
        })
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                         styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentView = NSHostingView(rootView: view)
        parent.beginSheet(sheet, completionHandler: nil)
    }

    func newFolder() {
        let p = src
        if p.remote != nil { remoteNewFolder(p); return }
        if p.mtp != nil { phoneRestricted(); return }
        guard let n = TPState.prompt(title: T("Новая папка"), info: T("Имя папки:"), value: T("Новая папка"),
                                     ok: T("Создать")) else { return }
        let name = n.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }
        do {
            try FileManager.default.createDirectory(at: p.dir.appendingPathComponent(name), withIntermediateDirectories: false)
            reloadAll()
            p.reload(select: name)
        } catch { TPState.showErrors([error.localizedDescription]) }
    }

    // MARK: просмотр и правка

    func quickLook() {
        if src.mtp != nil { phoneRestricted(); return }
        guard let it = src.current, !it.isParent else { return }
        if it.isDir { open(src, it); return }
        if let loc = src.remote {
            remoteFetchTemp(loc, it) { [weak self] u in
                self?.qlProc?.terminate()
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
                p.arguments = ["-p", u.path]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try? p.run()
                self?.qlProc = p
            }
            return
        }
        qlProc?.terminate()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", it.url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        qlProc = p
    }

    func editFile() {
        if src.remote != nil { remoteNote(); return }
        if src.mtp != nil { phoneRestricted(); return }
        guard let it = src.current, !it.isParent, !it.isDir else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", it.url.path]
        try? p.run()
    }
}

// MARK: - Интерфейс

enum TPIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for it: TPItem) -> NSImage {
        let key: String
        if it.isParent || it.isDir { key = "·dir" }
        else if it.isPackage { key = it.url.path }
        else { key = it.url.pathExtension.lowercased() }
        if let i = cache[key] { return i }
        let img: NSImage
        if it.isParent || it.isDir { img = NSWorkspace.shared.icon(for: .folder) }
        else if it.isPackage { img = NSWorkspace.shared.icon(forFile: it.url.path) }
        else if key.isEmpty { img = NSWorkspace.shared.icon(for: .data) }
        else { img = NSWorkspace.shared.icon(for: UTType(filenameExtension: key) ?? .data) }
        img.size = NSSize(width: 16, height: 16)
        cache[key] = img
        return img
    }
}

private let tpDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    return f
}()

private func tpBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

struct TPRow: View {
    let item: TPItem
    let isCursor: Bool
    let isMarked: Bool
    let isActive: Bool

    var body: some View {
        let hi = isCursor && isActive
        HStack(spacing: 6) {
            Image(nsImage: TPIcons.icon(for: item)).resizable().frame(width: 16, height: 16)
            Text(item.name)
                .font(.system(size: 13, weight: isMarked ? .bold : .regular))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(item.isParent ? "" : (item.isDir ? T("<папка>") : tpBytes(item.size)))
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 78, alignment: .trailing)
            Text(item.modified.map { tpDateFormatter.string(from: $0) } ?? "")
                .font(.system(size: 12))
                .frame(width: 112, alignment: .trailing)
        }
        .foregroundColor(hi ? .white : (isMarked ? .accentColor : .primary))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(hi ? Color.accentColor : (isCursor ? Color.gray.opacity(0.3) : (isMarked ? Color.accentColor.opacity(0.12) : Color.clear)))
        .contentShape(Rectangle())
    }
}

struct TPPaneView: View {
    @ObservedObject var st: TPState
    @ObservedObject var pane: TPPane
    @ObservedObject var search: FileSearch
    let index: Int
    @State private var query = ""
    @State private var hitSel: String?
    @State private var pathText = ""
    @State private var dropTargeted = false

    private var isActive: Bool { st.active == index }

    private var volumes: [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
    }

    private func go(_ u: URL) {
        st.active = index
        pane.navigate(to: u)
    }

    private func sortButton(_ key: TPPane.SortKey, _ title: String, width: CGFloat? = nil) -> some View {
        Button {
            if pane.sortKey == key { pane.ascending.toggle() } else { pane.sortKey = key; pane.ascending = true }
            pane.saveSettings()
            pane.reload()
        } label: {
            Text(title + (pane.sortKey == key ? (pane.ascending ? " ▲" : " ▼") : ""))
                .font(.caption).foregroundColor(.secondary)
                .frame(width: width, alignment: width == nil ? .leading : .trailing)
        }
        .buttonStyle(.plain)
    }

    private var searching: Bool { !pane.offDisk && query.trimmingCharacters(in: .whitespaces).count >= 2 }

    @ViewBuilder
    private var hitsOverlay: some View {
        if searching {
            ZStack(alignment: .top) {
                Color(NSColor.textBackgroundColor)
                if search.hits.isEmpty {
                    Text(T("Ничего не найдено")).foregroundColor(.secondary).padding(.top, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(search.hits) { h in hitRow(h) }
                        }
                    }
                }
            }
        }
    }

    /// Передаёт панели, что выбрано в результатах поиска: F5/F6/F8 работают именно с этим
    private func syncHit() {
        pane.searchActive = searching
        if searching, let id = hitSel, search.hits.contains(where: { $0.id == id }) {
            pane.hitURL = URL(fileURLWithPath: id)
        } else {
            pane.hitURL = nil
        }
    }

    private func reveal(_ h: FileHit) {
        let u = URL(fileURLWithPath: h.id)
        query = ""
        st.active = index
        pane.navigate(to: u.deletingLastPathComponent(), select: u.lastPathComponent)
    }

    private func hitRow(_ h: FileHit) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: h.icon).resizable().frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(h.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                Text(h.dir).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 4)
            if h.byContent { Text(T("в тексте")).font(.caption2).foregroundColor(.secondary) }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(hitSel == h.id ? Color.accentColor.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { reveal(h) }
        .onTapGesture { st.active = index; hitSel = h.id }
        .onDrag { makeFileDragProvider(URL(fileURLWithPath: h.id)) }
        .contextMenu {
            Button(T("Перейти к папке")) { reveal(h) }
            Button(T("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: h.id)]) }
            Button(T("Копировать путь")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(h.id, forType: .string)
            }
        }
    }

    private var footer: String {
        let files = pane.items.filter { !$0.isParent }
        let sel = files.filter { pane.marked.contains($0.id) }
        var s = Tf("Выбрано: %@ из %@", "\(sel.count)", "\(files.count)")
        if !sel.isEmpty { s += " · " + tpBytes(sel.reduce(0) { $0 + $1.size }) }
        if pane.remote == nil { s += " · " + T("Свободно") + ": " + tpBytes(pane.free) }
        return s
    }

    /// Контекстное меню строки: все функции F-клавиш
    @ViewBuilder
    private func rowMenu(row: Int, item it: TPItem) -> some View {
        // правый клик по неотмеченной строке работает с ней одной; по отмеченной — со всем выделением
        let prep = {
            st.active = index
            if !pane.marked.contains(it.id) { pane.marked = [] }
            pane.cursor = row
            pane.anchor = nil
        }
        Button(T("Открыть")) { prep(); st.open(pane, it) }.disabled(pane.mtp != nil && !it.isDir)
        Divider()
        Button(T("Переименовать") + "\t F2") { prep(); st.renameSelected() }
        Button(T("Просмотр") + "\t F3") { prep(); st.quickLook() }.disabled(pane.mtp != nil)
        if !it.isDir { Button(T("Правка") + "\t F4") { prep(); st.editFile() }.disabled(pane.offDisk) }
        Button(T("Копировать") + "\t F5") { prep(); st.copyMove(move: false) }
        Button(T("Переместить") + "\t F6") { prep(); st.copyMove(move: true) }.disabled(pane.offDisk || st.panes[1 - index].offDisk)
        Button(T("Новая папка") + "\t F7") { prep(); st.newFolder() }.disabled(pane.mtp != nil)
        Button(T("Удалить") + "\t F8") { prep(); st.deleteSelected() }
        Divider()
        Button(T("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([it.url]) }.disabled(pane.offDisk)
        Button(T("Копировать путь")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pane.remote != nil ? it.remotePath : it.url.path, forType: .string)
        }.disabled(pane.mtp != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { st.showPlacesMenu(pane: pane, index: index) } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "externaldrive")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                }
                .buttonStyle(.borderless)
                .help(T("Диски и устройства"))
                .frame(width: 34)

                Button { st.active = index; pane.goUp() } label: { Image(systemName: "arrow.up") }
                    .help(T("Вверх"))

                TextField("", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if pane.mtp != nil { pathText = pane.displayPath; st.clearKeyFocus(); return }
                        if st.handleAddress(pathText, pane: pane, index: index) { st.clearKeyFocus(); return }
                        let p = (pathText as NSString).expandingTildeInPath
                        if !pane.navigate(to: URL(fileURLWithPath: p)) { pathText = pane.dir.path }
                        st.clearKeyFocus()
                    }

                Button {
                    pane.showHidden.toggle()
                    pane.saveSettings()
                    pane.reload()
                } label: { Image(systemName: pane.showHidden ? "eye" : "eye.slash") }
                .help(T("Скрытые файлы"))
            }
            .padding(6)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)

            if !pane.offDisk {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(T("Поиск"), text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { st.clearKeyFocus() }
                        .onExitCommand { query = ""; st.clearKeyFocus() }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 4)
            }

            HStack(spacing: 6) {
                Color.clear.frame(width: 16, height: 1)
                sortButton(.name, T("Имя"))
                Spacer(minLength: 4)
                sortButton(.size, T("Размер"), width: 78)
                sortButton(.date, T("Изменён"), width: 112)
            }
            .padding(.horizontal, 8).frame(height: 20)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(pane.items.enumerated()), id: \.element.id) { i, it in
                            TPRow(item: it, isCursor: pane.cursor == i, isMarked: pane.marked.contains(it.id), isActive: isActive)
                                .id(it.id)
                                .onTapGesture(count: 2) { st.active = index; st.open(pane, it) }
                                .onTapGesture { st.click(pane: pane, index: index, row: i) }
                                .onDrag { (it.isParent || pane.offDisk) ? NSItemProvider() : makeFileDragProvider(it.url) }
                                .contextMenu { if !it.isParent { rowMenu(row: i, item: it) } }
                        }
                    }
                }
                .onChange(of: pane.cursor) { c in
                    if pane.items.indices.contains(c) { proxy.scrollTo(pane.items[c].id) }
                }
            }
            .overlay(Group {
                if let e = pane.error { Text(e).foregroundColor(.secondary).padding() }
            })
            .overlay(hitsOverlay)

            Divider()
            Text(footer).font(.caption).foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).frame(height: 22)
        }
        .overlay(RoundedRectangle(cornerRadius: 2)
            .stroke(Color.accentColor, lineWidth: dropTargeted ? 3 : 0))
        .onDrop(of: [UTType.fileURL, UTType.item], isTargeted: $dropTargeted) { providers in
            st.handleDrop(providers, into: pane)
        }
        .contextMenu {
            Button(T("Новая папка") + "\t F7") { st.active = index; st.newFolder() }.disabled(pane.mtp != nil)
            Button(T("Обновить")) { pane.reload() }
        }
        .onAppear { pathText = pane.displayPath }
        .onChange(of: query) { search.update($0); syncHit() }
        .onChange(of: hitSel) { _ in syncHit() }
        .onChange(of: search.hits.count) { _ in syncHit() }
        .onChange(of: pane.displayPath) { pathText = $0 }
        .simultaneousGesture(TapGesture().onEnded { st.active = index })
    }
}

struct TPRootView: View {
    @ObservedObject var st: TPState

    private func button(_ key: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key + " " + title).lineLimit(1).frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TPPaneView(st: st, pane: st.panes[0], search: st.panes[0].search, index: 0)
                Divider()
                TPPaneView(st: st, pane: st.panes[1], search: st.panes[1].search, index: 1)
            }
            Divider()
            HStack(spacing: 6) {
                if st.busy { ProgressView().scaleEffect(0.5).frame(width: 16, height: 16) }
                Text(st.status).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 22)
            Divider()
            HStack(spacing: 6) {
                button("F2", T("Переименовать")) { st.renameSelected() }
                button("F3", T("Просмотр")) { st.quickLook() }.disabled(st.src.mtp != nil)
                button("F4", T("Правка")) { st.editFile() }.disabled(st.src.offDisk)
                button("F5", T("Копировать")) { st.copyMove(move: false) }
                button("F6", T("Переместить")) { st.copyMove(move: true) }.disabled(st.src.offDisk || st.dst.offDisk)
                button("F7", T("Новая папка")) { st.newFolder() }.disabled(st.src.mtp != nil)
                button("F8", T("Удалить")) { st.deleteSelected() }
            }
            .padding(8)
        }
    }
}

// MARK: - Окно

final class TPWindowController: NSObject, NSWindowDelegate {
    static let shared = TPWindowController()
    private var window: NSWindow?
    private var monitor: Any?
    private var devTimer: Timer?

    func show() {
        let st = TPState.shared
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 820, height: 480)
            w.contentView = NSHostingView(rootView: LangRefresh { TPRootView(st: st) })
            w.delegate = self
            if !w.setFrameUsingName("TPWindow") { w.center() }
            w.setFrameAutosaveName("TPWindow")
            window = w
            st.window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Файл менеджер")
        installMonitor()
        st.reloadAll()
        st.refreshDevices()
        if devTimer == nil {
            devTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in TPState.shared.refreshDevices() }
        }
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() {
        window?.title = T("Файл менеджер")
    }

    func windowWillClose(_ notification: Notification) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        devTimer?.invalidate()
        devTimer = nil
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard let w = self.window, NSApp.keyWindow === w, NSApp.modalWindow == nil,
                  w.attachedSheet == nil else { return e }
            if let tv = w.firstResponder as? NSTextView {
                return TPState.shared.handleFieldKey(e, tv, w) ? nil : e
            }
            return TPState.shared.handleKey(e) ? nil : e
        }
    }
}

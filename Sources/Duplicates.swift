import SwiftUI
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Дубликаты и похожие фото
//
// Дубликаты: файлы с одинаковым размером сравниваются по хешу SHA-256 (сначала первый мегабайт, потом весь файл).
// Похожие фото: уменьшенная копия 9×8 в градациях серого → 64-битный «отпечаток» (dHash); близкие отпечатки
// и близкие пропорции дают группу. В Корзину уходит только отмеченное; «Выбрать лишние» оставляет по одной копии, но при желании можно отметить и все.

struct DupFile: Identifiable {
    let url: URL
    let size: Int64
    let date: Date
    var width = 0
    var height = 0
    var id: String { url.path }
    var pixels: Int { width * height }
}

struct DupGroup: Identifiable {
    let id = UUID()
    var files: [DupFile]
    /// Сколько места освободится, если оставить одну (самую большую) копию
    var wasted: Int64 {
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        return total - (files.map { $0.size }.max() ?? 0)
    }
}

final class DupState {
    let lock = NSLock()
    private var cancelledFlag = false
    private(set) var phase = ""
    private(set) var done = 0
    private(set) var total = 0

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledFlag }
    func cancel() { lock.lock(); cancelledFlag = true; lock.unlock() }
    func set(_ p: String, total t: Int = 0) { lock.lock(); phase = p; done = 0; total = t; lock.unlock() }
    func tick(_ n: Int = 1) { lock.lock(); done += n; lock.unlock() }
    func snapshot() -> (String, Int, Int) { lock.lock(); defer { lock.unlock() }; return (phase, done, total) }
}

enum DupScanner {
    static let minSize: Int64 = 4096
    static let minPhotoSize: Int64 = 20 * 1024
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    // MARK: Список файлов

    static func collect(root: URL, state: DupState) -> [DupFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let home = NSHomeDirectory()
        var out: [DupFile] = []
        var n = 0
        for case let u as URL in en {
            if state.isCancelled { break }
            let path = u.path
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isDirectory == true {
                let name = u.lastPathComponent
                if path == home + "/Library" || path.hasSuffix("/Library/Mobile Documents") || path.hasSuffix("/Library/CloudStorage")
                    || name == "node_modules" || name == ".Trash" {
                    en.skipDescendants()
                }
                continue
            }
            guard v.isRegularFile == true, let sz = v.fileSize, Int64(sz) >= minSize else { continue }
            out.append(DupFile(url: u, size: Int64(sz), date: v.contentModificationDate ?? .distantPast))
            n += 1
            if n % 400 == 0 { state.set(T("Поиск файлов…") + " \(n)") }
        }
        return out
    }

    // MARK: Точные дубликаты

    private static func hash(_ url: URL, limit: Int?) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        var read = 0
        while true {
            var finished = false
            autoreleasepool {
                if let data = try? h.read(upToCount: 1 << 20), !data.isEmpty {
                    sha.update(data: data)
                    read += data.count
                    if let l = limit, read >= l { finished = true }
                } else {
                    finished = true
                }
            }
            if finished { break }
        }
        return Data(sha.finalize()).base64EncodedString()
    }

    private static func inodeKey(_ url: URL) -> String? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return "\(st.st_dev):\(st.st_ino)"
    }

    private static func withoutHardLinks(_ g: [DupFile]) -> [DupFile] {
        var seen = Set<String>()
        return g.filter { f in
            guard let k = inodeKey(f.url) else { return true }
            return seen.insert(k).inserted
        }
    }

    static func duplicates(_ files: [DupFile], state: DupState) -> [DupGroup] {
        var bySize: [Int64: [DupFile]] = [:]
        for f in files { bySize[f.size, default: []].append(f) }
        let list = bySize.values.filter { $0.count > 1 }
        state.set(T("Сравнение файлов"), total: list.reduce(0) { $0 + $1.count })
        var groups: [DupGroup] = []
        let lock = NSLock()
        let quickLimit = 1 << 20
        DispatchQueue.concurrentPerform(iterations: list.count) { i in
            if state.isCancelled { return }
            let same = list[i]
            let whole = same[0].size <= Int64(quickLimit)
            var byQuick: [String: [DupFile]] = [:]
            for f in same {
                if state.isCancelled { return }
                if let h = hash(f.url, limit: quickLimit) { byQuick[h, default: []].append(f) }
                state.tick()
            }
            for (_, q) in byQuick where q.count > 1 {
                var byFull: [String: [DupFile]] = [:]
                if whole {
                    byFull["same"] = q
                } else {
                    for f in q {
                        if state.isCancelled { return }
                        if let h = hash(f.url, limit: nil) { byFull[h, default: []].append(f) }
                    }
                }
                for (_, g) in byFull where g.count > 1 {
                    let g2 = withoutHardLinks(g).sorted { ($0.date, $0.url.path.count) < ($1.date, $1.url.path.count) }
                    if g2.count > 1 {
                        lock.lock(); groups.append(DupGroup(files: g2)); lock.unlock()
                    }
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    // MARK: Похожие фото

    private struct Print {
        var file: DupFile
        var hash: UInt64
        var aspect: Double
    }

    /// 64-битный отпечаток разностей яркости соседних пикселей уменьшенной копии 9×8
    private static func dHash(_ url: URL) -> (UInt64, Double, Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 64]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary), img.height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 9, height: 8))
            return true
        }
        guard ok else { return nil }
        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                hash <<= 1
                if pixels[y * 9 + x] > pixels[y * 9 + x + 1] { hash |= 1 }
            }
        }
        if hash == 0 || hash == UInt64.max { return nil }          // однотонные кадры не сравниваем: у них у всех один отпечаток
        return (hash, Double(img.width) / Double(img.height), w, h)
    }

    static func similar(_ files: [DupFile], state: DupState) -> [DupGroup] {
        let photos = files.filter { imageExts.contains($0.url.pathExtension.lowercased()) && $0.size >= minPhotoSize }
        state.set(T("Просмотр фотографий"), total: photos.count)
        var prints = [Print?](repeating: nil, count: photos.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: photos.count) { i in
            if state.isCancelled { return }
            autoreleasepool {
                if let (h, asp, w, hh) = dHash(photos[i].url) {
                    var f = photos[i]
                    f.width = w
                    f.height = hh
                    lock.lock(); prints[i] = Print(file: f, hash: h, aspect: asp); lock.unlock()
                }
            }
            state.tick()
        }
        if state.isCancelled { return [] }
        let ps = prints.compactMap { $0 }
        state.set(T("Сравнение фотографий"), total: ps.count)
        let n = ps.count
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != r { let nx = parent[c]; parent[c] = r; c = nx }
            return r
        }
        let hashes = ps.map { $0.hash }
        let aspects = ps.map { $0.aspect }
        for i in 0..<n {
            if i % 256 == 0 {
                if state.isCancelled { return [] }
                state.tick(256)
            }
            let hi = hashes[i], ai = aspects[i]
            var j = i + 1
            while j < n {
                if (hi ^ hashes[j]).nonzeroBitCount <= 6, abs(ai - aspects[j]) / max(ai, 0.0001) < 0.08 {
                    let a = find(i), b = find(j)
                    if a != b { parent[a] = b }
                }
                j += 1
            }
        }
        var comps: [Int: [DupFile]] = [:]
        for i in 0..<n { comps[find(i), default: []].append(ps[i].file) }
        return comps.values.filter { $0.count > 1 }
            .map { DupGroup(files: $0.sorted { ($0.pixels, $0.size) > ($1.pixels, $1.size) }) }
            .sorted { $0.wasted > $1.wasted }
    }
}

// MARK: - Модель

/// Строка дерева папок для окна исключений
struct DupFolderRow: Identifiable {
    let id: String          // полный путь
    let name: String
    let depth: Int
    let count: Int          // сколько файлов из результатов лежит в папке и глубже
    let hasChildren: Bool
}

final class DupModel: ObservableObject {
    static let shared = DupModel()

    init() { excluded = Set(UserDefaults.standard.stringArray(forKey: "dup.excluded") ?? []) }

    enum Stage { case choose, scanning, result }
    enum Tab { case dups, similar }

    @Published var stage: Stage = .choose
    @Published var tab: Tab = .dups
    @Published var dupGroups: [DupGroup] = []
    @Published var similarGroups: [DupGroup] = []
    @Published var selected = Set<String>()
    @Published var phase = ""
    @Published var progress = 0.0
    @Published var message: String?
    @Published var confirm = false
    @Published var includeSimilar = true
    /// Папки, исключённые из результатов (с подпапками); запоминаются между поисками
    @Published var excluded = Set<String>() {
        didSet {
            UserDefaults.standard.set(excluded.sorted(), forKey: "dup.excluded")
            applyExclusions()
        }
    }
    private var rawDup: [DupGroup] = []
    private var rawSim: [DupGroup] = []
    private var scanRoot = URL(fileURLWithPath: "/")
    private var all: [String: DupFile] = [:]
    private var state: DupState?
    private var timer: Timer?
    private var generation = 0

    var selectedSize: Int64 { selected.reduce(Int64(0)) { $0 + (all[$1]?.size ?? 0) } }

    func scan(folder: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) else { return }
        let root = isDir.boolValue ? folder : folder.deletingLastPathComponent()
        if stage == .scanning { cancel() }
        generation += 1
        let gen = generation
        stage = .scanning
        message = nil
        selected = []
        dupGroups = []
        similarGroups = []
        rawDup = []
        rawSim = []
        scanRoot = root.standardizedFileURL
        phase = T("Поиск файлов…")
        progress = 0
        let st = DupState()
        state = st
        let wantSimilar = includeSimilar
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            let (p, d, t) = st.snapshot()
            self?.phase = t > 0 ? "\(p): \(d) / \(t)" : p
            self?.progress = t > 0 ? min(1, Double(d) / Double(t)) : 0
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            st.set(T("Поиск файлов…"))
            let files = DupScanner.collect(root: root, state: st)
            if st.isCancelled { return }
            let dups = DupScanner.duplicates(files, state: st)
            if st.isCancelled { return }
            let sim = wantSimilar ? DupScanner.similar(files, state: st) : []
            if st.isCancelled { return }
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                self.timer?.invalidate()
                self.rawDup = dups
                self.rawSim = sim
                self.applyExclusions()
                var map: [String: DupFile] = [:]
                for g in dups + sim { for f in g.files { map[f.id] = f } }
                self.all = map
                self.tab = self.dupGroups.isEmpty && !self.similarGroups.isEmpty ? .similar : .dups
                self.stage = .result
            }
        }
    }

    // MARK: Исключение папок

    func isExcluded(_ path: String) -> Bool {
        excluded.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Файлы исключённых папок не участвуют в результатах; группы, где осталась одна копия, пропадают
    private func applyExclusions() {
        func filtered(_ gs: [DupGroup]) -> [DupGroup] {
            gs.compactMap { g in
                var x = g
                x.files.removeAll { isExcluded($0.url.path) }
                return x.files.count > 1 ? x : nil
            }
        }
        dupGroups = filtered(rawDup)
        similarGroups = filtered(rawSim)
        selected = selected.filter { !isExcluded($0) }
        message = nil
    }

    func excludeFolder(_ path: String) { excluded.insert(path) }
    func includeFolder(_ path: String) { excluded.remove(path) }
    func resetExclusions() { excluded = [] }

    /// Дерево папок, в которых есть файлы из результатов (до корня поиска), развёрнутое по `expanded`
    func folderRows(expanded: Set<String>) -> [DupFolderRow] {
        let root = scanRoot.path
        var counts: [String: Int] = [:]
        var children: [String: Set<String>] = [:]
        var seen = Set<String>()
        for g in rawDup + rawSim {
            for f in g.files where seen.insert(f.id).inserted {
                var dir = f.url.deletingLastPathComponent().standardizedFileURL.path
                while true {
                    counts[dir, default: 0] += 1
                    if dir == root || dir == "/" || dir.isEmpty { break }
                    let parent = (dir as NSString).deletingLastPathComponent
                    if parent == dir { break }
                    children[parent, default: []].insert(dir)
                    dir = parent
                }
            }
        }
        var rows: [DupFolderRow] = []
        func walk(_ path: String, _ depth: Int) {
            let kids = (children[path] ?? []).sorted { ($0 as NSString).lastPathComponent.localizedCaseInsensitiveCompare(($1 as NSString).lastPathComponent) == .orderedAscending }
            let name = path == root ? (path == NSHomeDirectory() ? "~" : (path as NSString).lastPathComponent) : (path as NSString).lastPathComponent
            rows.append(DupFolderRow(id: path, name: name.isEmpty ? "/" : name, depth: depth, count: counts[path] ?? 0, hasChildren: !kids.isEmpty))
            if expanded.contains(path) { for k in kids { walk(k, depth + 1) } }
        }
        if counts[root] != nil { walk(root, 0) }
        return rows
    }

    func cancel() {
        generation += 1
        state?.cancel()
        timer?.invalidate()
        stage = .choose
    }

    // MARK: Выбор

    /// Отметить можно любой файл, в том числе все копии группы (перед удалением будет предупреждение)
    func canSelect(_ f: DupFile) -> Bool { true }

    func toggle(_ f: DupFile) {
        if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
        message = nil
    }

    /// В скольких группах отмечены все копии: после удаления не останется ни одной
    var fullyMarkedGroups: Int {
        (dupGroups + similarGroups).filter { g in g.files.allSatisfy { selected.contains($0.id) } }.count
    }

    /// В каждой группе оставляем одну копию: у дубликатов — самую старую, у фото — с наибольшим разрешением
    func selectExtras() {
        let groups = tab == .dups ? dupGroups : similarGroups
        for g in groups {
            guard let keep = g.files.first else { continue }       // группы уже отсортированы: нужная копия первая
            for f in g.files where f.id != keep.id && canSelect(f) { selected.insert(f.id) }
        }
        message = nil
    }

    func clearSelection() { selected = []; message = nil }

    func trashSelected() {
        let urls = selected.compactMap { all[$0]?.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { _, _ in
            DispatchQueue.main.async {
                let gone = { (f: DupFile) in !FileManager.default.fileExists(atPath: f.url.path) }
                func clean(_ groups: [DupGroup]) -> [DupGroup] {
                    groups.compactMap { g in
                        var x = g
                        x.files.removeAll(where: gone)
                        return x.files.count > 1 ? x : nil
                    }
                }
                self.rawDup = clean(self.rawDup)
                self.rawSim = clean(self.rawSim)
                self.applyExclusions()
                let failed = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                self.selected = Set(failed.map { $0.path })
                self.message = failed.isEmpty ? nil : Tf("Не удалось переместить в Корзину: %@", "\(failed.count)")
            }
        }
    }
}

// MARK: - Интерфейс

struct DupThumb: View {
    let url: URL
    @State private var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let i = image {
                Image(nsImage: i).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 52, height: 52)
        .clipped()
        .cornerRadius(6)
        .onAppear { load() }
    }

    private func load() {
        let key = url.path as NSString
        if let c = DupThumb.cache.object(forKey: key) { image = c; return }
        let u = url
        DispatchQueue.global(qos: .utility).async {
            var img: NSImage?
            if DupScanner.imageExts.contains(u.pathExtension.lowercased()), let src = CGImageSourceCreateWithURL(u as CFURL, nil) {
                let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceCreateThumbnailWithTransform: true,
                                             kCGImageSourceThumbnailMaxPixelSize: 120]
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
            }
            if img == nil { img = NSWorkspace.shared.icon(forFile: u.path) }
            DispatchQueue.main.async {
                if let i = img { DupThumb.cache.setObject(i, forKey: key); image = i }
            }
        }
    }
}

struct DupPanel: View {
    @ObservedObject var model: DupModel
    @State private var dropTargeted = false
    @State private var showFolders = false

    private func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.on.square").font(.system(size: 26)).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Дубликаты и похожие фото")).font(.headline)
                    Text(T("Найдите лишние копии файлов и похожие снимки; в Корзину уйдёт только то, что вы отметите"))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            Divider()
            content
        }
        .frame(minWidth: 660, minHeight: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in dropFolder(providers) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .overlay { if model.confirm { confirmView } }
        .sheet(isPresented: $showFolders) { DupFoldersSheet(model: model) { showFolders = false } }
    }

    private func dropFolder(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            guard let u = url else { return }
            DispatchQueue.main.async { model.scan(folder: u) }
        }
        return true
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = T("Анализировать")
        panel.message = T("Выберите папку или диск")
        panel.begin { r in
            if r == .OK, let u = panel.url { model.scan(folder: u) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .choose:
            VStack(spacing: 14) {
                Spacer()
                HStack(spacing: 16) {
                    Button { model.scan(folder: URL(fileURLWithPath: NSHomeDirectory())) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "house").font(.system(size: 26))
                            Text(T("Домашняя папка"))
                        }.frame(width: 150, height: 90)
                    }
                    Button { chooseFolder() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus").font(.system(size: 26))
                            Text(T("Выбрать папку…"))
                        }.frame(width: 150, height: 90)
                    }
                }
                Toggle(T("Искать похожие фото"), isOn: $model.includeSimilar)
                Text(T("Или перетащите папку в окно")).font(.caption).foregroundColor(.secondary)
                Spacer()
                HStack { Spacer(); Button(T("Закрыть")) { DupWindowController.shared.close() } }.padding(12)
            }
        case .scanning:
            VStack(spacing: 10) {
                Spacer()
                ProgressView(value: model.progress).frame(width: 320)
                Text(model.phase).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle).padding(.horizontal, 30)
                Spacer()
                HStack { Spacer(); Button(T("Отмена")) { model.cancel() } }.padding(12)
            }
        case .result:
            VStack(spacing: 0) {
                Picker("", selection: $model.tab) {
                    Text(Tf("Дубликаты (%@)", "\(model.dupGroups.count)")).tag(DupModel.Tab.dups)
                    Text(Tf("Похожие фото (%@)", "\(model.similarGroups.count)")).tag(DupModel.Tab.similar)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14).padding(.vertical, 8)
                Divider()
                groupList(model.tab == .dups ? model.dupGroups : model.similarGroups)
                Divider()
                footer
            }
        }
    }

    private func groupList(_ groups: [DupGroup]) -> some View {
        Group {
            if groups.isEmpty {
                VStack { Spacer(); Text(T("Ничего не найдено")).foregroundColor(.secondary); Spacer() }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups.prefix(500)) { g in groupView(g) }
                        if groups.count > 500 {
                            Text(Tf("Показаны первые %@ групп", "500")).font(.caption).foregroundColor(.secondary).padding(8)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func groupView(_ g: DupGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tf("Копий: %@ · освободится до %@", "\(g.files.count)", "\(fmt(g.wasted))"))
                .font(.caption).foregroundColor(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
            Divider()
            ForEach(g.files) { f in row(f) }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
    }

    private func row(_ f: DupFile) -> some View {
        let on = model.selected.contains(f.id)
        return HStack(spacing: 10) {
            Button { model.toggle(f) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17)).foregroundColor(on ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            DupThumb(url: f.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(f.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmt(f.size)).font(.callout)
                Text((f.width > 0 ? "\(f.width)×\(f.height) · " : "") + DupPanel.dateFmt.string(from: f.date))
                    .font(.caption).foregroundColor(.secondary)
            }
            Button { model.excludeFolder(f.url.deletingLastPathComponent().path) } label: {
                Image(systemName: "folder.badge.minus").foregroundColor(.secondary)
            }
            .buttonStyle(.plain).help(T("Исключить эту папку из поиска"))
            Button { DiskPreview.show(f.url) } label: { Image(systemName: "eye").foregroundColor(.secondary) }
                .buttonStyle(.plain).help(T("Предпросмотр"))
            Button { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } label: {
                Image(systemName: "magnifyingglass.circle").foregroundColor(.secondary)
            }
            .buttonStyle(.plain).help(T("Показать в Finder"))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(on ? Color.accentColor.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(f) }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Tf("Выбрано: %@ (%@)", "\(model.selected.count)", "\(fmt(model.selectedSize))")).font(.callout)
                if let m = model.message { Text(m).font(.caption).foregroundColor(.orange) }
            }
            Spacer()
            Button(T("Выбрать лишние")) { model.selectExtras() }
            Button(T("Снять выбор")) { model.clearSelection() }.disabled(model.selected.isEmpty)
            Button(model.excluded.isEmpty ? T("Исключить папки…") : Tf("Исключить папки: %@", "\(model.excluded.count)")) { showFolders = true }
            Button(T("Новый поиск")) { model.stage = .choose }
            Button(T("В Корзину…")) { model.confirm = true }.disabled(model.selected.isEmpty)
            Button(T("Закрыть")) { DupWindowController.shared.close() }
        }
        .padding(12)
    }

    private var confirmView: some View {
        ZStack {
            Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { }
            VStack(spacing: 12) {
                Image(systemName: "trash.circle.fill").font(.system(size: 34)).foregroundColor(.orange)
                Text(Tf("Переместить в Корзину файлов: %@?", "\(model.selected.count)")).font(.title3.bold())
                Text(Tf("Освободится: %@", "\(fmt(model.selectedSize))")).font(.callout)
                if model.fullyMarkedGroups > 0 {
                    Text(Tf("Внимание: в группах, где отмечены все копии, не останется ни одной: %@", "\(model.fullyMarkedGroups)"))
                        .font(.callout).foregroundColor(.red).multilineTextAlignment(.center)
                }
                Text(T("Вернуть можно из Корзины, пока вы её не очистили.")).font(.caption).foregroundColor(.secondary)
                HStack {
                    Button(T("Нет, вернуться")) { model.confirm = false }
                    Button(T("Да, в Корзину")) { model.confirm = false; model.trashSelected() }.foregroundColor(.red)
                }
            }
            .padding(20)
            .frame(width: 340)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 20)
        }
    }
}

/// Дерево папок с галочками: снятая галочка исключает папку (и всё внутри) из результатов
struct DupFoldersSheet: View {
    @ObservedObject var model: DupModel
    let close: () -> Void
    @State private var expanded = Set<String>()
    @State private var started = false

    var body: some View {
        let rows = model.folderRows(expanded: expanded)
        return VStack(alignment: .leading, spacing: 10) {
            Text(T("Исключить папки")).font(.headline)
            Text(T("Снимите галочку с папки: её файлы исчезнут из результатов, а группы, где не осталось повторов, пропадут. Выбор запоминается для следующих поисков."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { r in rowView(r) }
                }
                .padding(4)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
            HStack {
                Button(T("Включить все")) { model.resetExclusions() }.disabled(model.excluded.isEmpty)
                Spacer()
                Button(T("Готово"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 460)
        .onAppear {
            if !started, let first = model.folderRows(expanded: []).first { expanded = [first.id]; started = true }
        }
    }

    private func rowView(_ r: DupFolderRow) -> some View {
        let byParent = model.isExcluded(r.id) && !model.excluded.contains(r.id)   // исключена родительская папка
        let off = model.isExcluded(r.id)
        return HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(r.depth) * 16, height: 1)
            Button {
                if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) }
            } label: {
                Image(systemName: expanded.contains(r.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).frame(width: 14)
                    .opacity(r.hasChildren ? 1 : 0)
            }
            .buttonStyle(.plain).disabled(!r.hasChildren)
            Button {
                if model.excluded.contains(r.id) { model.includeFolder(r.id) } else if !byParent { model.excludeFolder(r.id) }
            } label: {
                Image(systemName: off ? "square" : "checkmark.square.fill")
                    .font(.system(size: 16)).foregroundColor(off ? .secondary : .accentColor)
            }
            .buttonStyle(.plain).disabled(byParent)
            Image(systemName: "folder").foregroundColor(off ? .secondary : .accentColor)
            Text(r.name).lineLimit(1).truncationMode(.middle).foregroundColor(off ? .secondary : .primary)
            Spacer(minLength: 8)
            Text(Tf("Файлов: %@", "\(r.count)")).font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

struct DupWindowRoot: View {
    @ObservedObject var store: Store
    @ObservedObject var model: DupModel
    var body: some View { DupPanel(model: model).id(store.language) }
}

final class DupWindowController: NSObject, NSWindowDelegate {
    static let shared = DupWindowController()
    private var window: NSWindow?

    func show(store: Store) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = T("Дубликаты и похожие фото")
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 660, height: 460)
            w.contentView = NSHostingView(rootView: DupWindowRoot(store: store, model: DupModel.shared))
            w.delegate = self
            if !w.setFrameUsingName("DuplicatesWindow") { w.center() }
            w.setFrameAutosaveName("DuplicatesWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    @objc private func languageChanged() { window?.title = T("Дубликаты и похожие фото") }
}

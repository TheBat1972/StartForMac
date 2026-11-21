import SwiftUI
import AppKit

// MARK: - UnRar (распаковка архивов)
//
// Движок — консольный 7-Zip (7zz): RAR/RAR5, 7z, ZIP (в т. ч. AES), TAR, GZ, BZ2, XZ, ISO, DMG, CAB и др.
// Пароль и многотомные архивы (.part1.rar, .r00, .7z.001, .zip.001) поддерживаются самим 7-Zip.
// Если 7zz нет в системе, при первом открытии он скачивается в ~/Library/Application Support/StartMenu.

enum UnState { case waiting, running, done, needPassword, failed }

final class UnJob: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var state: UnState = .waiting
    @Published var progress: Double = 0
    @Published var message = ""
    @Published var password = ""
    var destination: URL?
    var process: Process?
    var cancelled = false
    init(url: URL) { self.url = url }
    var title: String { url.lastPathComponent }
}

// MARK: Тома

enum UnVolumes {
    private static func rx(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : String(s[Range(r, in: s)!])
        }
    }

    /// Если выбран не первый том, возвращает первый (если он существует рядом)
    static func first(_ url: URL) -> URL {
        let name = url.lastPathComponent
        let dir = url.deletingLastPathComponent()
        var candidate: String?
        if let g = rx("^(.*)\\.part(\\d+)\\.rar$", name) {
            let n = g[2]
            candidate = g[1] + ".part" + String(repeating: "0", count: max(0, n.count - 1)) + "1.rar"
        } else if let g = rx("^(.*)\\.r\\d{2,}$", name) {
            candidate = g[1] + ".rar"
        } else if let g = rx("^(.*)\\.z\\d{2}$", name) {
            candidate = g[1] + ".zip"
        } else if let g = rx("^(.*)\\.\\d{3}$", name) {
            candidate = g[1] + ".001"
        }
        if let c = candidate {
            let u = dir.appendingPathComponent(c)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return url
    }

    /// Имя без расширений и номеров томов — для папки назначения
    static func baseName(_ url: URL) -> String {
        var name = url.lastPathComponent
        let patterns = ["\\.part\\d+\\.rar$", "\\.(7z|zip|rar|tar)\\.\\d{3}$", "\\.\\d{3}$"]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
                name = String(name[..<Range(m.range, in: name)!.lowerBound])
                return name.isEmpty ? "archive" : name
            }
        }
        name = (name as NSString).deletingPathExtension
        if name.lowercased().hasSuffix(".tar") { name = (name as NSString).deletingPathExtension }
        return name.isEmpty ? "archive" : name
    }
}

// MARK: Движок

enum UnEngine {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StartMenu", isDirectory: true)
    }
    static var local: URL { supportDir.appendingPathComponent("7zz") }

    static func find() -> URL? {
        var paths = [local.path, "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz", "/opt/homebrew/bin/7zzs", "/usr/local/bin/7zzs"]
        for d in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            paths.append(String(d) + "/7zz")
        }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: d, as: UTF8.self))
    }

    /// Скачивает и устанавливает 7zz (синхронно, вызывать не из главного потока)
    static func install() -> String? {
        let fm = FileManager.default
        var lastErr = "нет связи"
        var archive: URL?
        for v in ["2600", "2501", "2409", "2408", "2407"] {
            guard let u = URL(string: "https://www.7-zip.org/a/7z\(v)-mac.tar.xz") else { continue }
            let sem = DispatchSemaphore(value: 0)
            var result: URL?
            URLSession.shared.downloadTask(with: u) { loc, resp, err in
                if let loc = loc, (resp as? HTTPURLResponse)?.statusCode == 200 {
                    let keep = fm.temporaryDirectory.appendingPathComponent("7z\(v)-\(UUID().uuidString).tar.xz")
                    try? fm.moveItem(at: loc, to: keep)
                    result = keep
                } else {
                    lastErr = err?.localizedDescription ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
                }
                sem.signal()
            }.resume()
            sem.wait()
            if let r = result { archive = r; break }
        }
        guard let arch = archive else { return lastErr }
        defer { try? fm.removeItem(at: arch) }

        let tmp = fm.temporaryDirectory.appendingPathComponent("7zz-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let (code, out) = run("/usr/bin/tar", ["-xf", arch.path, "-C", tmp.path])
        guard code == 0 else { return out.isEmpty ? "tar: \(code)" : out }
        let bin = tmp.appendingPathComponent("7zz")
        guard fm.fileExists(atPath: bin.path) else { return "7zz не найден в архиве" }
        do {
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try? fm.removeItem(at: local)
            try fm.copyItem(at: bin, to: local)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: local.path)
        } catch { return error.localizedDescription }
        run("/usr/bin/xattr", ["-cr", local.path])
        run("/usr/bin/codesign", ["--force", "--sign", "-", local.path])
        return find() == nil ? "не удалось запустить 7zz" : nil
    }
}

// MARK: Модель

final class UnRarModel: ObservableObject {
    static let shared = UnRarModel()

    @Published var jobs: [UnJob] = []
    @Published var engine: URL?
    @Published var installing = false
    @Published var engineError = ""

    @Published var customDir: URL? {
        didSet { UserDefaults.standard.set(customDir?.path, forKey: "unrar.customPath") }
    }
    @Published var useCustom: Bool {
        didSet { UserDefaults.standard.set(useCustom, forKey: "unrar.useCustom") }
    }
    @Published var subfolder: Bool {
        didSet { UserDefaults.standard.set(subfolder, forKey: "unrar.subfolder") }
    }
    @Published var reveal: Bool {
        didSet { UserDefaults.standard.set(reveal, forKey: "unrar.reveal") }
    }

    private var running: UnJob?

    init() {
        let d = UserDefaults.standard
        useCustom = d.bool(forKey: "unrar.useCustom")
        subfolder = d.object(forKey: "unrar.subfolder") as? Bool ?? true
        reveal = d.object(forKey: "unrar.reveal") as? Bool ?? true
        if let p = d.string(forKey: "unrar.customPath") { customDir = URL(fileURLWithPath: p) }
        engine = UnEngine.find()
    }

    // MARK: добавление

    func add(_ urls: [URL]) {
        for u in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let first = UnVolumes.first(u)
            if jobs.contains(where: { $0.url.path == first.path }) { continue }
            jobs.append(UnJob(url: first))
        }
        pump()
    }

    func choose() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.message = T("Выберите архивы (для многотомного — любой том)")
        if p.runModal() == .OK { add(p.urls) }
    }

    func chooseDestination() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = T("Выбрать")
        if p.runModal() == .OK, let u = p.url { customDir = u; useCustom = true }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var any = false
        for p in providers where p.hasItemConformingToTypeIdentifier("public.file-url") {
            any = true
            p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let u = url { DispatchQueue.main.async { self.add([u]) } }
            }
        }
        return any
    }

    func remove(_ job: UnJob) {
        job.cancelled = true
        job.process?.terminate()
        jobs.removeAll { $0.id == job.id }
        if running?.id == job.id { running = nil }
        pump()
    }

    func clearFinished() {
        jobs.removeAll { $0.state == .done || $0.state == .failed }
    }

    func retry(_ job: UnJob) {
        job.state = .waiting
        job.progress = 0
        job.message = ""
        pump()
    }

    // MARK: движок

    func ensureEngine() {
        if engine != nil || installing { return }
        installing = true
        engineError = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let err = UnEngine.install()
            DispatchQueue.main.async {
                self.installing = false
                if let e = err { self.engineError = e } else { self.engine = UnEngine.find() }
                self.pump()
            }
        }
    }

    // MARK: очередь

    private func pump() {
        guard running == nil, let job = jobs.first(where: { $0.state == .waiting }) else { return }
        guard let exe = engine else { ensureEngine(); return }
        start(job, exe: exe)
    }

    private func destination(for job: UnJob) -> URL {
        let base = useCustom ? (customDir ?? job.url.deletingLastPathComponent()) : job.url.deletingLastPathComponent()
        return subfolder ? base.appendingPathComponent(UnVolumes.baseName(job.url), isDirectory: true) : base
    }

    private func start(_ job: UnJob, exe: URL) {
        let dest = destination(for: job)
        job.destination = dest
        job.state = .running
        job.progress = 0
        job.message = ""
        running = job
        let src = job.url
        let pw = job.password

        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = exe
            var args = ["x", src.path, "-o" + dest.path, "-y", "-aou", "-bsp1", "-bso1", "-bse1"]
            if !pw.isEmpty { args.append("-p" + pw) }
            p.arguments = args
            p.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            DispatchQueue.main.sync { job.process = p }
            do { try p.run() } catch {
                DispatchQueue.main.async { self.finish(job, code: -1, log: error.localizedDescription) }
                return
            }
            var log = ""
            let pct = try? NSRegularExpression(pattern: "(\\d{1,3})%")
            let fh = pipe.fileHandleForReading
            while true {
                let d = fh.availableData
                if d.isEmpty { break }
                let s = String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\u{8}", with: "")
                if let re = pct {
                    let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
                    if let m = ms.last, let r = Range(m.range(at: 1), in: s), let v = Double(s[r]) {
                        DispatchQueue.main.async { if v / 100 >= job.progress { job.progress = min(1, v / 100) } }
                    }
                }
                log += s
                if log.count > 30000 { log = String(log.suffix(20000)) }
            }
            p.waitUntilExit()
            let code = p.terminationStatus
            DispatchQueue.main.async { self.finish(job, code: code, log: log) }
        }
    }

    private func finish(_ job: UnJob, code: Int32, log: String) {
        job.process = nil
        if running?.id == job.id { running = nil }
        if job.cancelled { pump(); return }

        let lower = log.lowercased()
        let lines = log.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if code == 0 || code == 1 {                 // 1 — предупреждения (например, нельзя прочитать часть файлов)
            job.state = .done
            job.progress = 1
            job.message = code == 1 ? T("Распаковано с предупреждениями") : ""
            if reveal, let d = job.destination, FileManager.default.fileExists(atPath: d.path) {
                NSWorkspace.shared.activateFileViewerSelecting([d])
            }
        } else if lower.contains("wrong password") || lower.contains("enter password")
                    || lower.contains("cannot open encrypted archive") || lower.contains("encrypted") {
            job.state = .needPassword
            job.message = job.password.isEmpty ? T("Архив защищён паролем") : T("Неверный пароль")
        } else {
            job.state = .failed
            var msg = lines.filter { $0.hasPrefix("ERROR") || $0.lowercased().contains("missing volume")
                                     || $0.lowercased().contains("unsupported") || $0.lowercased().contains("can not open")
                                     || $0.lowercased().contains("cannot open") }
                .prefix(2).joined(separator: "\n")
            if msg.isEmpty { msg = lines.last ?? "7-Zip: код \(code)" }
            if lower.contains("missing volume") || lower.contains("unexpected end of archive") {
                msg = T("Не хватает тома архива — положите все части в одну папку") + "\n" + msg
            }
            job.message = msg
        }
        pump()
    }
}

// MARK: Интерфейс

struct UnRarPanel: View {
    @ObservedObject var model: UnRarModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                if model.jobs.isEmpty { dropHint } else { list }
                if targeted {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .padding(8).allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: ["public.file-url"], isTargeted: $targeted) { model.handleDrop($0) }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 380)
        .onAppear { model.ensureEngine() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(T("Добавить архивы…")) { model.choose() }
                Spacer()
                if model.jobs.contains(where: { $0.state == .done || $0.state == .failed }) {
                    Button(T("Убрать завершённые")) { model.clearFinished() }
                }
            }
            HStack(spacing: 10) {
                Picker("", selection: $model.useCustom) {
                    Text(T("Рядом с архивом")).tag(false)
                    Text(T("В выбранную папку")).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                if model.useCustom {
                    Button(model.customDir?.lastPathComponent ?? T("Выбрать папку…")) { model.chooseDestination() }
                        .lineLimit(1)
                }
                Spacer()
            }
            HStack(spacing: 18) {
                Toggle(T("В папку с именем архива"), isOn: $model.subfolder)
                Toggle(T("Показать результат в Finder"), isOn: $model.reveal)
            }
            .toggleStyle(.checkbox)
        }
        .padding(12)
    }

    private var dropHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "archivebox").font(.system(size: 44)).foregroundColor(.secondary)
            Text(T("Перетащите архивы сюда")).font(.title3)
            Text(T("RAR, RAR5, 7z, ZIP (в т. ч. с шифрованием), TAR, GZ, BZ2, XZ, ISO, DMG, CAB, ARJ, LZH, WIM, CPIO, RPM, DEB и другие. Поддерживаются пароль и многотомные архивы (.part1.rar, .r00, .7z.001, .zip.001)."))
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .padding()
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.jobs) { job in
                    UnJobRow(job: job, model: model)
                    Divider()
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.installing {
                ProgressView().controlSize(.small)
                Text(T("Загрузка движка 7-Zip…")).font(.caption).foregroundColor(.secondary)
            } else if let e = model.engine {
                Text(Tf("Движок: 7-Zip (%@)", e.path)).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                Text(Tf("Не удалось получить движок 7-Zip: %@", model.engineError)).font(.caption).foregroundColor(.red)
                    .lineLimit(2)
                Button(T("Повторить")) { model.ensureEngine() }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct UnJobRow: View {
    @ObservedObject var job: UnJob
    let model: UnRarModel

    private var icon: String {
        switch job.state {
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .needPassword: return "lock.fill"
        default: return "archivebox"
        }
    }
    private var iconColor: Color {
        switch job.state {
        case .done: return .green
        case .failed: return .red
        case .needPassword: return .orange
        default: return .secondary
        }
    }
    private var subtitle: String {
        switch job.state {
        case .waiting: return T("Ожидание")
        case .running: return T("Распаковка…") + " \(Int(job.progress * 100))%"
        case .done: return job.message.isEmpty ? T("Готово") : job.message
        case .needPassword: return job.message
        case .failed: return job.message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20)).foregroundColor(iconColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).lineLimit(1).truncationMode(.middle)
                    Text(subtitle).font(.caption)
                        .foregroundColor(job.state == .failed ? .red : .secondary)
                        .lineLimit(3)
                }
                Spacer()
                if job.state == .done, let d = job.destination {
                    Button(T("Показать")) { NSWorkspace.shared.activateFileViewerSelecting([d]) }
                }
                if job.state == .failed {
                    Button(T("Повторить")) { model.retry(job) }
                }
                Button { model.remove(job) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(job.state == .running ? T("Остановить") : T("Убрать из списка"))
            }
            if job.state == .running {
                ProgressView(value: job.progress)
            }
            if job.state == .needPassword {
                HStack {
                    SecureField(T("Пароль"), text: $job.password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.retry(job) }
                    Button(T("Распаковать")) { model.retry(job) }
                        .disabled(job.password.isEmpty)
                }
                .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct UnRarWindowRoot: View {
    @ObservedObject var store: Store
    @ObservedObject var model: UnRarModel
    var body: some View { UnRarPanel(model: model).id(store.language) }
}

final class UnRarWindowController: NSObject, NSWindowDelegate {
    static let shared = UnRarWindowController()
    private var window: NSWindow?

    func show(store: Store) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = T("UnRar")
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 560, height: 380)
            w.contentView = NSHostingView(rootView: UnRarWindowRoot(store: store, model: UnRarModel.shared))
            w.delegate = self
            if !w.setFrameUsingName("UnRarWindow") { w.center() }
            w.setFrameAutosaveName("UnRarWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Открыть окно сразу с готовыми файлами (например, перетащенными на значок)
    func show(store: Store, urls: [URL]) {
        show(store: store)
        UnRarModel.shared.add(urls)
    }

    @objc private func languageChanged() { window?.title = T("UnRar") }
}

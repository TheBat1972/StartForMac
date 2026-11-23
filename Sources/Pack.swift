import SwiftUI
import AppKit

// MARK: - Упаковка архивов
//
// Тот же движок 7-Zip (7zz), что и для распаковки. Форматы: 7z и ZIP (пароль, разбивка на тома),
// TAR.GZ / TAR.BZ2 / TAR.XZ (без пароля и томов — этих возможностей в формате нет).
// ZIP шифруется AES-256, у 7z можно скрыть и имена файлов. Тома: имя.7z.001, имя.7z.002…

enum PackFormat: String, CaseIterable, Identifiable {
    case sevenZ = "7z", zip, tgz, tbz, txz
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "ZIP"
        case .tgz: return "TAR.GZ"
        case .tbz: return "TAR.BZ2"
        case .txz: return "TAR.XZ"
        }
    }
    var ext: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tgz: return "tar.gz"
        case .tbz: return "tar.bz2"
        case .txz: return "tar.xz"
        }
    }
    /// Пароль и тома есть только у 7z и ZIP
    var rich: Bool { self == .sevenZ || self == .zip }
    var outer: String {      // тип внешнего сжатия 7-Zip для TAR.*
        switch self {
        case .tgz: return "gzip"
        case .tbz: return "bzip2"
        case .txz: return "xz"
        default: return rawValue
        }
    }
}

enum PackLevel: Int, CaseIterable, Identifiable {
    case fast = 1, normal = 5, maximum = 9
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .fast: return T("Быстро")
        case .normal: return T("Обычное")
        case .maximum: return T("Максимум")
        }
    }
}

enum PackState { case idle, running, done, failed }

final class PackModel: ObservableObject {
    static let shared = PackModel()

    /// Готовые размеры тома, МБ (0 — свой)
    static let volumePresets = [10, 25, 100, 700, 1000, 4000, 0]
    static func volumeTitle(_ mb: Int) -> String {
        switch mb {
        case 0: return T("Свой размер")
        case 1000: return T("1 ГБ")
        case 4000: return T("4 ГБ (для FAT32)")
        default: return "\(mb) " + T("МБ")
        }
    }

    @Published var items: [URL] = []
    @Published var format: PackFormat { didSet { UserDefaults.standard.set(format.rawValue, forKey: "pack.format") } }
    @Published var level: PackLevel { didSet { UserDefaults.standard.set(level.rawValue, forKey: "pack.level") } }
    @Published var password = ""
    @Published var encryptNames = true
    @Published var volumes = false
    @Published var volumeMB = 100
    @Published var customMB = "100"
    @Published var name = ""
    @Published var useCustom = false
    @Published var customDir: URL?
    @Published var state: PackState = .idle
    @Published var progress: Double = 0
    @Published var message = ""
    @Published var result: URL?

    private var process: Process?
    private var cancelled = false

    init() {
        let d = UserDefaults.standard
        format = PackFormat(rawValue: d.string(forKey: "pack.format") ?? "") ?? .sevenZ
        level = PackLevel(rawValue: d.integer(forKey: "pack.level")) ?? .normal
    }

    var autoName: String {
        guard let f = items.first else { return T("Архив") }
        if items.count > 1 { return T("Архив") }
        let n = f.deletingPathExtension().lastPathComponent
        return n.isEmpty ? f.lastPathComponent : n
    }

    /// Размер тома в МБ или nil, если введено не число больше нуля
    var volumeValue: Int? {
        if volumeMB != 0 { return volumeMB }
        guard let v = Int(customMB.trimmingCharacters(in: .whitespaces)), v > 0, v <= 1_000_000 else { return nil }
        return v
    }

    // MARK: список

    func add(_ urls: [URL]) {
        for u in urls where FileManager.default.fileExists(atPath: u.path) {
            let s = u.standardizedFileURL
            if !items.contains(where: { $0.standardizedFileURL == s }) { items.append(s) }
        }
        if state != .running { state = .idle; message = "" }
    }

    func choose() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.message = T("Выберите, что упаковать")
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

    // MARK: запуск

    private func destDir() -> URL {
        if useCustom, let d = customDir { return d }
        return items.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Имя, которое не затрёт уже существующий архив (и его тома)
    private func uniqueOutput(dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        func taken(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) || fm.fileExists(atPath: u.path + ".001") }
        var u = dir.appendingPathComponent(base + "." + ext)
        var n = 2
        while taken(u) { u = dir.appendingPathComponent("\(base) \(n)." + ext); n += 1 }
        return u
    }

    func stop() {
        cancelled = true
        process?.terminate()
    }

    func start(exe: URL) {
        guard state != .running, !items.isEmpty else { return }
        var volMB: Int?
        if volumes && format.rich {
            guard let v = volumeValue else { state = .failed; message = T("Размер тома — целое число больше нуля"); return }
            volMB = v
        }
        let fmt = format, lvl = level, pw = format.rich ? password : ""
        let hide = encryptNames
        var nm = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        if nm.isEmpty { nm = autoName }
        let dir = destDir()
        let out = uniqueOutput(dir: dir, base: nm, ext: fmt.ext)
        let srcs = items
        cancelled = false
        state = .running
        progress = 0
        message = T("Упаковка…")
        result = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            // Общая папка исходников: имена в архиве будут без полных путей
            let parents = Set(srcs.map { $0.deletingLastPathComponent().path })
            let cwd = parents.count == 1 ? URL(fileURLWithPath: parents.first!, isDirectory: true) : URL(fileURLWithPath: "/")
            let names = parents.count == 1 ? srcs.map { $0.lastPathComponent } : srcs.map { String($0.path.dropFirst()) }

            var tmpTar: URL?
            var inputs = names
            var inputCwd = cwd
            if !fmt.rich {
                // TAR.* : сначала tar во временную папку, затем сжатие
                let tmp = fm.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString)", isDirectory: true)
                try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                let tar = tmp.appendingPathComponent(nm + ".tar")
                let r = Self.run("/usr/bin/tar", ["-cf", tar.path, "-C", cwd.path] + names, env: ["COPYFILE_DISABLE": "1"],
                                 onStart: { p in DispatchQueue.main.async { self.process = p } }, onOutput: { _ in })
                if self.cancelled || r.0 != 0 {
                    try? fm.removeItem(at: tmp)
                    DispatchQueue.main.async { self.finish(out: out, code: self.cancelled ? -2 : r.0, log: r.1, volumes: false) }
                    return
                }
                tmpTar = tar
                inputs = [tar.lastPathComponent]
                inputCwd = tmp
            }
            defer { if let t = tmpTar { try? fm.removeItem(at: t.deletingLastPathComponent()) } }

            var args = ["a", "-t" + fmt.outer, "-mx=\(lvl.rawValue)", "-y", "-bsp1", "-bso1", "-bse1", out.path]
            if fmt.rich {
                if !pw.isEmpty {
                    args.append("-p" + pw)
                    if fmt == .zip { args.append("-mem=AES256") }
                    if fmt == .sevenZ && hide { args.append("-mhe=on") }
                }
                if let v = volMB { args.append("-v\(v)m") }
            }
            args += inputs
            let pct = try? NSRegularExpression(pattern: "(\\d{1,3})%")
            let r = Self.run(exe.path, args, cwd: inputCwd, onStart: { p in DispatchQueue.main.async { self.process = p } }) { s in
                if let re = pct, let m = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).last,
                   let rg = Range(m.range(at: 1), in: s), let v = Double(s[rg]) {
                    DispatchQueue.main.async { if v / 100 >= self.progress { self.progress = min(1, v / 100) } }
                }
            }
            DispatchQueue.main.async { self.finish(out: out, code: self.cancelled ? -2 : r.0, log: r.1, volumes: volMB != nil) }
        }
    }

    private static func run(_ exe: String, _ args: [String], cwd: URL? = nil, env: [String: String] = [:],
                            onStart: (Process) -> Void, onOutput: @escaping (String) -> Void) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let c = cwd { p.currentDirectoryURL = c }
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        onStart(p)
        var log = ""
        let fh = pipe.fileHandleForReading
        while true {
            let d = fh.availableData
            if d.isEmpty { break }
            let s = String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\u{8}", with: "")
            onOutput(s)
            log += s
            if log.count > 30000 { log = String(log.suffix(20000)) }
        }
        p.waitUntilExit()
        return (p.terminationStatus, log)
    }

    private func removePartial(_ out: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: out)
        var i = 1
        while true {
            let v = URL(fileURLWithPath: out.path + String(format: ".%03d", i))
            if fm.fileExists(atPath: v.path) { try? fm.removeItem(at: v); i += 1 } else { break }
        }
    }

    private func finish(out: URL, code: Int32, log: String, volumes: Bool) {
        process = nil
        let fm = FileManager.default
        if code == -2 {                                  // остановлено пользователем
            removePartial(out)
            state = .idle; message = ""; progress = 0
            return
        }
        if code == 0 || code == 1 {
            state = .done
            progress = 1
            result = volumes ? URL(fileURLWithPath: out.path + ".001") : out
            if let r = result, !fm.fileExists(atPath: r.path) { result = out }
            message = code == 1 ? T("Упаковано с предупреждениями") : T("Упаковано")
            if let r = result, fm.fileExists(atPath: r.path) { NSWorkspace.shared.activateFileViewerSelecting([r]) }
        } else {
            removePartial(out)
            state = .failed
            let lines = log.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let errs = lines.filter { $0.hasPrefix("ERROR") || $0.lowercased().contains("cannot") || $0.lowercased().contains("can not") }
            message = errs.prefix(2).joined(separator: "\n")
            if message.isEmpty { message = lines.last ?? Tf("Не удалось (код %@)", "\(code)") }
        }
    }
}

// MARK: Интерфейс

struct PackView: View {
    @ObservedObject var engine: UnRarModel
    @ObservedObject var pack: PackModel
    let footer: AnyView          // строка состояния движка 7-Zip из окна
    @State private var targeted = false
    @FocusState private var pwFocus: Bool

    /// ZIP принимает пароль только из ASCII (так устроен формат): 7-Zip иначе отвечает E_INVALIDARG
    private var zipBadPassword: Bool { pack.format == .zip && pack.password.contains { !$0.isASCII } }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if pack.items.isEmpty { hint } else { list }
                if targeted {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .padding(8).allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity)
            .onDrop(of: ["public.file-url"], isTargeted: $targeted) { pack.handleDrop($0) }
            Divider()
            options
            Divider()
            bottom
            Divider()
            footer
        }
    }

    private var hint: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox").font(.system(size: 40)).foregroundColor(.secondary)
            Text(T("Перетащите сюда файлы и папки")).font(.title3)
            Text(T("Получится архив 7z, ZIP, TAR.GZ, TAR.BZ2 или TAR.XZ. Для 7z и ZIP доступны пароль и разбивка на тома."))
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .padding()
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pack.items, id: \.self) { u in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(u.deletingLastPathComponent().path).font(.caption).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Button { pack.items.removeAll { $0 == u } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).disabled(pack.state == .running)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    Divider()
                }
            }
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).frame(width: 110, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(T("Формат")) {
                Picker("", selection: $pack.format) {
                    ForEach(PackFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("", selection: $pack.level) {
                    ForEach(PackLevel.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            if pack.format.rich {
                row(T("Пароль")) {
                    SecureField(T("Необязательно"), text: $pack.password).textFieldStyle(.roundedBorder).frame(width: 200)
                        .focused($pwFocus)
                        .onChange(of: pwFocus) { f in if f { InputSourceSwitcher.switchToASCII() } else { InputSourceSwitcher.restore() } }
                        .onDisappear { InputSourceSwitcher.restore() }
                    if pack.format == .sevenZ {
                        Toggle(T("Скрыть и имена файлов"), isOn: $pack.encryptNames)
                            .toggleStyle(.checkbox).disabled(pack.password.isEmpty)
                    } else {
                        Text(T("шифрование AES-256")).font(.caption).foregroundColor(.secondary)
                    }
                }
                row(T("Тома")) {
                    Toggle(T("Разбить на тома"), isOn: $pack.volumes).toggleStyle(.checkbox)
                    if pack.volumes {
                        Picker("", selection: $pack.volumeMB) {
                            ForEach(PackModel.volumePresets, id: \.self) { Text(PackModel.volumeTitle($0)).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        if pack.volumeMB == 0 {
                            TextField("100", text: $pack.customMB).textFieldStyle(.roundedBorder).frame(width: 70)
                            Text(T("МБ"))
                        }
                    }
                }
                if zipBadPassword {
                    row("") {
                        Text(T("ZIP принимает пароль только из латинских букв, цифр и знаков. Сотрите русские буквы или выберите 7z."))
                            .font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if pack.volumes && pack.volumeValue == nil {
                    row("") { Text(T("Размер тома — целое число больше нуля")).font(.caption).foregroundColor(.red) }
                }
            } else {
                row("") {
                    Text(T("Для TAR.GZ, TAR.BZ2 и TAR.XZ пароль и тома недоступны — выберите 7z или ZIP."))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            row(T("Имя архива")) {
                TextField(pack.autoName, text: $pack.name).textFieldStyle(.roundedBorder).frame(width: 220)
                Text("." + pack.format.ext).foregroundColor(.secondary)
            }
            row(T("Куда")) {
                Picker("", selection: $pack.useCustom) {
                    Text(T("Рядом с исходными файлами")).tag(false)
                    Text(T("В выбранную папку")).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 330)
                if pack.useCustom {
                    Button(pack.customDir?.lastPathComponent ?? T("Выбрать папку…")) { pack.chooseDestination() }.lineLimit(1)
                }
            }
        }
        .padding(12)
        .disabled(pack.state == .running)
    }

    private var bottom: some View {
        VStack(spacing: 6) {
            if pack.state == .running { ProgressView(value: pack.progress) }
            HStack {
                Button(T("Добавить файлы и папки…")) { pack.choose() }.disabled(pack.state == .running)
                if !pack.items.isEmpty {
                    Button(T("Очистить список")) { pack.items = []; pack.state = .idle; pack.message = "" }
                        .disabled(pack.state == .running)
                }
                Text(pack.message).font(.caption)
                    .foregroundColor(pack.state == .failed ? .red : (pack.state == .done ? .green : .secondary))
                    .lineLimit(2)
                Spacer()
                if pack.state == .done, let r = pack.result {
                    Button(T("Показать")) { NSWorkspace.shared.activateFileViewerSelecting([r]) }
                }
                if pack.state == .running {
                    Button(T("Остановить")) { pack.stop() }
                } else {
                    Button(T("Упаковать")) { if let e = engine.engine { pack.start(exe: e) } else { engine.ensureEngine() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(pack.items.isEmpty || engine.engine == nil
                                  || (pack.volumes && pack.format.rich && pack.volumeValue == nil) || zipBadPassword)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

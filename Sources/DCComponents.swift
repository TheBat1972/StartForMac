// Инструмент «Загрузка и конвертация» (раньше — отдельное приложение Download and Convert).
// Общие элементы интерфейса: одинаковый каркас и компоненты для всех трёх разделов.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Состояние задач (общее для MP3 и MP4)

enum JobState: Equatable {
    case waiting
    case running(Double)            // 0…1; отрицательное — пока неизвестно
    case done(output: URL, size: Int64)
    case failed(String)
    case cancelled
}

extension JobState {
    var isRunning: Bool { if case .running = self { return true }; return false }
    var isFinished: Bool {
        switch self {
        case .done, .failed, .cancelled: return true
        default: return false
        }
    }
    var canRetry: Bool {
        switch self {
        case .failed, .cancelled: return true
        default: return false
        }
    }
    var output: URL? { if case .done(let o, _) = self { return o }; return nil }
}

func queueTotals(_ items: [(size: Int64, state: JobState)]) -> String {
    let done = items.compactMap { i -> (Int64, Int64)? in
        if case .done(_, let s) = i.state { return (i.size, s) }
        return nil
    }
    let waiting = items.filter { $0.state == .waiting }.count
    var parts: [String] = []
    if !done.isEmpty {
        let a = done.reduce(Int64(0)) { $0 + $1.0 }, b = done.reduce(Int64(0)) { $0 + $1.1 }
        parts.append(LF("queue.done", String(done.count), formatBytes(a), formatBytes(b)))
    }
    if waiting > 0 { parts.append(LF("queue.waiting", String(waiting))) }
    return parts.joined(separator: " · ")
}

// MARK: - Файлы

let extraVideoExtensions: Set<String> = [
    "mp4", "m4v", "mov", "qt", "mkv", "webm", "avi", "wmv", "asf", "flv", "f4v", "mpg", "mpeg", "m2v",
    "vob", "ts", "mts", "m2ts", "3gp", "3g2", "ogv", "mxf", "divx", "rm", "rmvb", "gif", "dv", "hevc", "h264"]

func isVideoFile(_ u: URL) -> Bool {
    let ext = u.pathExtension.lowercased()
    if extraVideoExtensions.contains(ext) { return true }
    if let t = UTType(filenameExtension: ext) { return t.conforms(to: .movie) }
    return false
}

func isAudioOnlyFile(_ u: URL) -> Bool {
    let ext = u.pathExtension.lowercased()
    if extraVideoExtensions.contains(ext) { return false }
    if let t = UTType(filenameExtension: ext) { return t.conforms(to: .audio) && !t.conforms(to: .movie) }
    return false
}

func isMediaFile(_ u: URL) -> Bool {
    if isVideoFile(u) { return true }
    if let t = UTType(filenameExtension: u.pathExtension.lowercased()) {
        return t.conforms(to: .audio) || t.conforms(to: .audiovisualContent)
    }
    return false
}

/// Файлы из списка путей; папки обходятся целиком (берутся только подходящие файлы),
/// файл, выбранный явно, принимается всегда.
func collectFiles(_ urls: [URL], accept: (URL) -> Bool) -> [URL] {
    let fm = FileManager.default
    var files: [URL] = []
    for u in urls {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
        if isDir.boolValue {
            if let e = fm.enumerator(at: u, includingPropertiesForKeys: nil,
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let f as URL in e where accept(f) { files.append(f) }
            }
        } else {
            files.append(u)
        }
    }
    return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

func fileSize(_ u: URL) -> Int64 {
    Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
}

func chooseFolder() -> URL? {
    let p = NSOpenPanel()
    p.canChooseFiles = false
    p.canChooseDirectories = true
    p.canCreateDirectories = true
    p.prompt = L("common.choose")
    return p.runModal() == .OK ? p.url : nil
}

func chooseMediaFiles(prompt: String) -> [URL] {
    let p = NSOpenPanel()
    p.allowsMultipleSelection = true
    p.canChooseDirectories = true
    p.canChooseFiles = true
    p.message = L("common.chooseFilesMessage")
    p.prompt = prompt
    return p.runModal() == .OK ? p.urls : []
}

/// Папка для результата, когда выбрано «рядом с оригиналом». Если файл — временная копия
/// (перетащен из программы, которая отдала только копию), результат кладётся в «Загрузки», а не во временную папку.
func defaultOutputDir(for input: URL) -> URL {
    if input.path.contains("/dc-drop-"),
       let d = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { return d }
    return input.deletingLastPathComponent()
}

/// Что показать за кнопкой «Папка…»: выбранная папка, а если не выбрана — реальная целевая папка очереди
/// (для перетащенных из других программ файлов это «Загрузки»). nil — очередь пуста или папки разные.
func outputFolderLabel(explicit: URL?, inputs: [URL]) -> String? {
    if let e = explicit { return e.path }
    let dirs = Set(inputs.map { defaultOutputDir(for: $0).path })
    return dirs.count == 1 ? dirs.first : nil
}

/// Удаляет временные копии перетащенных файлов (dc-drop-…), оставшиеся с прошлых запусков
func cleanDropTemp() {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory
    guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
    for u in items where u.lastPathComponent.hasPrefix("dc-drop-") { try? fm.removeItem(at: u) }
}

/// Тип, в котором «Пуск» отдаёт путь к настоящему файлу при перетаскивании из поиска (виден только самой программе)
let startMenuFilePathType = "ru.local.startmenu.file-path"

/// Достаёт файл из перетащенного элемента: из Finder, из результатов поиска «Пуска», из других программ.
/// Сначала ссылка на файл (в любом из видов, в каком её отдают), запасной путь — копия файла во временную папку.
func loadDroppedFile(_ p: NSItemProvider, _ done: @escaping (URL) -> Void) {
    func fallback() {
        let types = p.registeredTypeIdentifiers.filter { id in
            guard let t = UTType(id) else { return false }
            return t.conforms(to: .data) || t.conforms(to: .item)
        }
        guard let type = types.first else { return }
        p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            guard let url = url else { return }
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("dc-drop-" + UUID().uuidString, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var name = url.lastPathComponent
            if let s = p.suggestedName, !s.isEmpty {
                let ext = url.pathExtension
                name = (ext.isEmpty || s.lowercased().hasSuffix("." + ext.lowercased())) ? s : s + "." + ext
            }
            let dest = dir.appendingPathComponent(name)
            if (try? fm.copyItem(at: url, to: dest)) != nil { done(dest) }
        }
    }
    // перетащено из результатов поиска «Пуска»: путь к настоящему файлу, без копий
    if p.hasItemConformingToTypeIdentifier(startMenuFilePathType) {
        p.loadDataRepresentation(forTypeIdentifier: startMenuFilePathType) { data, _ in
            if let d = data, let s = String(data: d, encoding: .utf8), FileManager.default.fileExists(atPath: s) {
                done(URL(fileURLWithPath: s))
            } else {
                loadDroppedFileURL(p, fallback: fallback, done: done)
            }
        }
        return
    }
    loadDroppedFileURL(p, fallback: fallback, done: done)
}

private func loadDroppedFileURL(_ p: NSItemProvider, fallback: @escaping () -> Void, done: @escaping (URL) -> Void) {
    /// Настоящий путь: ссылки вида file:///.file/id=… превращаем в обычные
    func real(_ u: URL) -> URL? {
        guard u.isFileURL else { return nil }
        let r = (u as NSURL).filePathURL ?? u
        return FileManager.default.fileExists(atPath: r.path) ? r : nil
    }
    // запасной путь: объект-ссылка (Finder отдаёт её и там, где fileURL недоступен) — тогда копия не нужна
    func viaObject() {
        if p.canLoadObject(ofClass: NSURL.self) {
            _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                if let u = obj as? NSURL, let r = real(u as URL) { done(r) } else { fallback() }
            }
        } else { fallback() }
    }
    guard p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { viaObject(); return }
    p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        var url: URL?
        if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
        else if let u = item as? URL { url = u }
        else if let u = item as? NSURL { url = u as URL }
        if let u = url, let r = real(u) { done(r) } else { viaObject() }
    }
}

extension View {
    func fileDrop(targeted: Binding<Bool>, _ handler: @escaping ([URL]) -> Void) -> some View {
        onDrop(of: [UTType.fileURL, UTType.item], isTargeted: targeted) { providers in
            // Сначала настоящие пути прямо из буфера перетаскивания: так Finder отдаёт сами файлы, а не их копии
            let real = (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self],
                        options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
                .map { ($0 as NSURL).filePathURL ?? $0 }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            // Буфер .drag может хранить путь от прошлого перетаскивания (так бывает при дропе из стопки Dock):
            // берём его, только если имя файла совпадает с тем, что отдают providers этого дропа
            let names = Set(providers.compactMap { $0.suggestedName }.map { ($0 as NSString).deletingPathExtension })
            let current = real.filter { names.contains($0.deletingPathExtension().lastPathComponent) }
            let useBoard = !names.isEmpty && current.count == real.count && current.count >= providers.count
            if !real.isEmpty && useBoard {
                DispatchQueue.main.async { handler(real) }
                return true
            }
            for p in providers {
                loadDroppedFile(p) { url in DispatchQueue.main.async { handler([url]) } }
            }
            return true
        }
    }
}

// MARK: - Каркас раздела: опции → содержимое → нижняя панель

struct SectionPage<Options: View, Content: View, Bottom: View>: View {
    let options: Options
    let content: Content
    let bottom: Bottom

    init(@ViewBuilder options: () -> Options,
         @ViewBuilder content: () -> Content,
         @ViewBuilder bottom: () -> Bottom) {
        self.options = options()
        self.content = content()
        self.bottom = bottom()
    }

    var body: some View {
        VStack(spacing: 0) {
            options
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            bottom
                .padding(12)
        }
    }
}

/// Строка опции: подпись справа в колонке одинаковой ширины, дальше элементы управления
struct OptionRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).frame(width: 96, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
    }
}

struct HintText: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.caption).foregroundColor(.secondary) }
}

/// «Сохранять: путь [Сбросить] [Папка…]»
struct FolderRow: View {
    let path: String?
    let placeholder: String
    let onChoose: () -> Void
    var onReset: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(path ?? placeholder)
                .lineLimit(1).truncationMode(.middle)
                .foregroundColor(path == nil ? .secondary : .primary)
            if let reset = onReset { Button(L("common.reset"), action: reset) }
            Button(L("common.folder"), action: onChoose)
        }
    }
}

struct DropZone: View {
    let icon: String
    let title: String
    let subtitle: String
    let targeted: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 46, weight: .light))
            Text(title).font(.title3)
            Text(subtitle).font(.caption).foregroundColor(.secondary)
            Button(L("common.chooseFiles"), action: action)
        }
        .foregroundColor(targeted ? .accentColor : .primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundColor(targeted ? Color.accentColor : Color.secondary.opacity(0.5))
        )
        .padding(16)
    }
}

/// Строка файла в очереди (MP3 и MP4 выглядят одинаково)
struct JobRow: View {
    let input: URL
    let inputSize: Int64
    let duration: Double?
    let state: JobState
    var edited = false
    var trimmedTo: Double? = nil
    var canEdit = true
    var onEdit: (() -> Void)? = nil
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: input.path))
                .resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(input.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    if edited {
                        Image(systemName: "scissors").foregroundColor(.accentColor).help(L("job.willTrim"))
                    }
                }
                status
            }
            Spacer(minLength: 8)
            HStack(spacing: 12) {
                if let out = state.output {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help(L("common.showInFinder"))
                }
                if state.canRetry {
                    Button(action: onRetry) { Image(systemName: "arrow.clockwise") }
                        .help(L("common.retry"))
                }
                if !state.isRunning {
                    if let edit = onEdit {
                        Button(action: edit) { Image(systemName: "scissors") }
                            .help(L("job.trimHelp"))
                            .disabled(!canEdit)
                    }
                    Button(action: onRemove) { Image(systemName: "xmark") }
                        .help(L("job.remove"))
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(L("job.showOriginal")) { NSWorkspace.shared.activateFileViewerSelecting([input]) }
            if let out = state.output {
                Button(L("job.showResult")) { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                Button(L("job.openResult")) { NSWorkspace.shared.open(out) }
            }
        }
    }

    private var info: String {
        var s = formatBytes(inputSize)
        if let d = duration {
            s += " · " + formatTime(d)
            if edited, let k = trimmedTo { s += " → " + formatTime(k) + " " + L("job.afterTrim") }
        }
        return s
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .waiting:
            Text(info).font(.caption).foregroundColor(.secondary)
        case .running(let p):
            HStack(spacing: 8) {
                if p < 0 {
                    ProgressView().progressViewStyle(.linear).frame(maxWidth: 280)
                    Text(L("job.preparing")).font(.caption).foregroundColor(.secondary)
                } else {
                    ProgressView(value: p).frame(maxWidth: 280)
                    Text("\(Int(p * 100))%").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }
            }
        case .done(_, let size):
            Text(doneText(size)).font(.caption).foregroundColor(.green)
        case .failed(let msg):
            Text(msg).font(.caption).foregroundColor(.red).lineLimit(3)
        case .cancelled:
            Text(L("job.stopped")).font(.caption).foregroundColor(.secondary)
        }
    }

    private func doneText(_ size: Int64) -> String {
        var s = LF("job.done", formatBytes(inputSize), formatBytes(size))
        if inputSize > 0 {
            let pct = Int((Double(size) / Double(inputSize) - 1) * 100)
            s += pct <= 0 ? " (−\(-pct)%)" : " (+\(pct)%)"
        }
        return s
    }
}

/// Баннер загрузки ffmpeg — над любым разделом
struct ToolsBanner: View {
    @ObservedObject var tm = ToolsManager.shared
    var body: some View {
        switch tm.state {
        case .checking:
            EmptyView()
        case .ready:
            if tm.ffmpegOutdated {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(LF("ff.outdated", tm.ffmpegVersion ?? "—")).font(.callout).foregroundColor(.orange)
                        Spacer()
                        Button(L("ff.update")) { tm.prepare(forceDownload: true) }.disabled(tm.isInUse)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08))
                    Divider()
                }
            }
        case .downloading(let p, let label):
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle").foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("banner.first")).font(.callout)
                        ProgressView(value: p)
                        Text(label).font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08))
                Divider()
            }
        case .failed(let msg):
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("banner.failTitle")).bold()
                        Text(msg).font(.caption).foregroundColor(.secondary).lineLimit(3)
                    }
                    Spacer()
                    Button(L("common.retry")) { tm.prepare(forceDownload: true) }
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
                Divider()
            }
        }
    }
}

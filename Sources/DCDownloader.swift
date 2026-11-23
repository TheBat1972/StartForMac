// Инструмент «Загрузка и конвертация» (раньше — отдельное приложение Download and Convert).
// Загрузка видео по ссылке через yt-dlp.
import SwiftUI
import AppKit

enum YTQuality: String, CaseIterable, Identifiable {
    case best, p1080, p720, audio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .best: return L("yt.q.best")
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .audio: return L("yt.q.audio")
        }
    }
}

// Откуда брать cookies (YouTube просит подтвердить, что вы не бот)
enum CookieSource: String, CaseIterable, Identifiable {
    case none = ""
    case safari, chrome, firefox, brave, edge, opera, vivaldi
    var id: String { rawValue }

    var bundleID: String? {
        switch self {
        case .none: return nil
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .firefox: return "org.mozilla.firefox"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .opera: return "com.operasoftware.Opera"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        }
    }

    /// Установлен ли браузер. Проверка идёт через системный реестр приложений и разрешений не требует.
    var isInstalled: Bool {
        guard let b = bundleID else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) != nil
    }

    /// «Без cookies» и только установленные браузеры.
    static var available: [CookieSource] { allCases.filter { $0.isInstalled } }
    var title: String {
        switch self {
        case .none: return L("yt.cookies.none")
        case .chrome: return "Chrome"
        case .safari: return "Safari"
        case .firefox: return "Firefox"
        case .brave: return "Brave"
        case .edge: return "Edge"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        }
    }
}

/// Cookies Safari лежат в защищённой папке: нужен «Полный доступ к диску».
/// Программно выдать это право нельзя — можно только объяснить и открыть нужный раздел настроек.
enum FullDiskAccess {
    static var isGranted: Bool {
        let path = NSHomeDirectory() + "/Library/Safari"
        guard FileManager.default.fileExists(atPath: path) else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func warn() {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = L("fda.title")
        a.informativeText = L("fda.text")
        a.addButton(withTitle: L("fda.open"))
        a.addButton(withTitle: L("fda.later"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { openSettings() }
    }
}

final class Downloader: ObservableObject {
    static let shared = Downloader()

    @Published var urlText = ""
    @Published var quality: YTQuality { didSet { UserDefaults.standard.set(quality.rawValue, forKey: "yt.quality") } }
    @Published var cookies: CookieSource {
        didSet {
            UserDefaults.standard.set(cookies.rawValue, forKey: "yt.cookies")
            if cookies == .safari && !FullDiskAccess.isGranted {
                DispatchQueue.main.async { FullDiskAccess.warn() }
            }
        }
    }
    @Published var folder: String { didSet { UserDefaults.standard.set(folder, forKey: "yt.folder") } }

    @Published var log = ""
    @Published var progress: Double?
    @Published var running = false
    @Published var status = ""
    @Published var lastFile: String?

    private var process: Process?
    private var cancelled = false

    init() {
        let d = UserDefaults.standard
        quality = YTQuality(rawValue: d.string(forKey: "yt.quality") ?? "") ?? .best
        let saved = CookieSource(rawValue: d.string(forKey: "yt.cookies") ?? "safari") ?? .safari
        cookies = saved.isInstalled ? saved : .safari
        folder = d.string(forKey: "yt.folder") ?? (NSHomeDirectory() + "/Downloads")
    }

    var trimmedURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    func pasteFromClipboard() {
        if let s = NSPasteboard.general.string(forType: .string) {
            urlText = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func start() {
        guard let tool = ToolsManager.shared.ytDlpPath else {
            status = L("yt.noYtDlp")
            return
        }
        if cookies == .safari && !FullDiskAccess.isGranted {
            status = L("fda.status")
            FullDiskAccess.warn()
            return
        }
        let ffmpeg = ToolsManager.shared.tools?.ffmpeg
        var args = ["--print", "after_move:filepath", "--no-quiet", "--no-playlist", "--newline",
                    "-o", folder + "/%(title)s.%(ext)s"]
        // папка, а не файл: так yt-dlp найдёт рядом и ffprobe
        if let ffmpeg = ffmpeg {
            args += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }
        if cookies != .none { args += ["--cookies-from-browser", cookies.rawValue] }

        switch (quality, ffmpeg != nil) {
        case (.best, true):
            args += ["-f", "bv*+ba/b", "-S", "res,vcodec:h264,acodec:m4a", "--merge-output-format", "mp4"]
        case (.p1080, true):
            args += ["-f", "bv*[height<=1080]+ba/b[height<=1080]/b", "-S", "vcodec:h264,acodec:m4a", "--merge-output-format", "mp4"]
        case (.p720, true):
            args += ["-f", "bv*[height<=720]+ba/b[height<=720]/b", "-S", "vcodec:h264,acodec:m4a", "--merge-output-format", "mp4"]
        case (.best, false):
            args += ["-f", "b[ext=mp4]/b"]
        case (.p1080, false):
            args += ["-f", "b[height<=1080][ext=mp4]/b[height<=1080]/b"]
        case (.p720, false):
            args += ["-f", "b[height<=720][ext=mp4]/b[height<=720]/b"]
        case (.audio, true):
            args += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
        case (.audio, false):
            args += ["-f", "ba[ext=m4a]/ba"]
        }
        args += ["--", trimmedURL]

        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.deno/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.handle(text) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                if let text = String(data: rest, encoding: .utf8), !text.isEmpty { self?.handle(text) }
                self?.finished(proc.terminationStatus)
            }
        }

        log = ""
        lastFile = nil
        progress = nil
        cancelled = false
        status = L("yt.starting")
        do {
            try p.run()
            process = p
            running = true
        } catch {
            status = LF("yt.launchFail", error.localizedDescription)
        }
    }

    /// Очищает окно: ссылку, журнал и статус (во время загрузки не работает)
    func clearWindow() {
        guard !running else { return }
        urlText = ""; log = ""; status = ""; progress = nil; lastFile = nil
    }

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    private func handle(_ text: String) {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let r = line.range(of: #"^\[download\]\s+[0-9.]+%"#, options: .regularExpression) {
                let digits = line[r].filter { "0123456789.".contains($0) }
                if let v = Double(digits) { progress = v / 100 }
                status = line.replacingOccurrences(of: "[download] ", with: "")
                continue
            }
            if line.hasPrefix("/"), FileManager.default.fileExists(atPath: line) {
                lastFile = line
            }
            log += line + "\n"
            if log.count > 20000 { log = String(log.suffix(15000)) }
        }
    }

    private func finished(_ code: Int32) {
        running = false
        process = nil
        if cancelled {
            status = L("yt.cancelled")
            progress = nil
        } else if code == 0 {
            status = L("yt.done")
            progress = 1
        } else {
            status = LF("yt.error", String(code))
            progress = nil
        }
    }
}

// MARK: - Интерфейс

struct DownloadView: View {
    @ObservedObject var d = Downloader.shared
    @ObservedObject var tm = ToolsManager.shared

    var body: some View {
        SectionPage {
            VStack(alignment: .leading, spacing: 9) {
                OptionRow(L("yt.link")) {
                    TextField(L("yt.linkPlaceholder"), text: $d.urlText)
                        .textFieldStyle(.roundedBorder)
                    Button(L("yt.paste")) { d.pasteFromClipboard() }
                }
                OptionRow(L("common.quality")) {
                    Picker("", selection: $d.quality) {
                        ForEach(YTQuality.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                OptionRow(L("common.saveTo")) {
                    FolderRow(path: d.folder, placeholder: "") {
                        if let u = chooseFolder() { d.folder = u.path }
                    }
                }
                OptionRow(L("yt.cookies")) {
                    Picker("", selection: $d.cookies) {
                        ForEach(CookieSource.available) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 160)
                }
                OptionRow("") { HintText(L("yt.cookiesHint")) }
            }
            .disabled(d.running)
        } content: {
            VStack(spacing: 0) {
                if tm.ytDlpOutdated {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(LF("yt.outdated", tm.ytDlpVersion ?? "", tm.ytDlpLatest ?? ""))
                            .font(.callout).foregroundColor(.orange)
                        Spacer()
                        Button(L("yt.update")) { tm.installYtDlp() }.disabled(tm.ytDlpBusy || d.running)
                    }
                    .padding(12)
                    Divider()
                }
                if d.running || d.progress != nil || !d.status.isEmpty || tm.ytDlpPath == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        if d.running || d.progress != nil {
                            if let p = d.progress { ProgressView(value: p) }
                            else { ProgressView().progressViewStyle(.linear) }
                        }
                        if tm.ytDlpPath == nil && !d.running {
                            Text(L("yt.noYtDlp")).font(.callout).foregroundColor(.orange)
                        } else {
                            Text(d.status).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(d.log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Color.clear.frame(height: 1).id("end")
                            }
                            .padding(8)
                        }
                        .onChange(of: d.log) { _ in proxy.scrollTo("end") }
                    }
                    if d.log.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle").font(.system(size: 46, weight: .light))
                            Text(L("yt.placeholderTitle")).font(.title3)
                            HintText(L("yt.placeholderSub"))
                        }
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        } bottom: {
            HStack {
                if let f = d.lastFile {
                    Button(L("common.showInFinder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)])
                    }
                }
                Button(L("common.clearAll")) { d.clearWindow() }
                    .disabled(d.running || (d.urlText.isEmpty && d.log.isEmpty && d.lastFile == nil))
                if tm.ytDlpPath == nil {
                    Button(L("yt.install")) { tm.installYtDlp() }.disabled(tm.ytDlpBusy)
                }
                if tm.ytDlpBusy { ProgressView().controlSize(.small) }
                if let m = tm.ytDlpMessage {
                    Text(m).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if d.running {
                    Button(L("common.cancel")) { d.cancel() }
                } else {
                    Button(L("yt.download")) { d.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(d.trimmedURL.isEmpty || tm.ytDlpPath == nil)
                }
            }
        }
        .onAppear {
            tm.checkYtDlp()
            if d.urlText.isEmpty, let s = NSPasteboard.general.string(forType: .string), s.hasPrefix("http") {
                d.urlText = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

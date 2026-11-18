// Инструмент «Загрузка и конвертация» (раньше — отдельное приложение Download and Convert).
// Общие инструменты: ffmpeg/ffprobe (скачиваются сами), yt-dlp, запуск процессов.
import Foundation
import AppKit

func formatBytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

func formatTime(_ t: Double, precise: Bool = false) -> String {
    let t = max(0, t)
    let whole = Int(t)
    let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
    var str = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    if precise { str += String(format: ",%d", min(9, Int((t - Double(whole)) * 10))) }
    return str
}

struct Failure: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

@discardableResult
func capture(_ exe: URL, _ args: [String]) -> (status: Int32, text: String) {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

final class Buffer {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    func lastLines(_ n: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.split(separator: "\n").suffix(n).joined(separator: "\n")
    }
}

final class LineSplitter {
    private var buffer = Data()
    private let onLine: (String) -> Void
    init(_ onLine: @escaping (String) -> Void) { self.onLine = onLine }
    func feed(_ d: Data) {
        buffer.append(d)
        while let i = buffer.firstIndex(of: 10) {
            let line = buffer[buffer.startIndex..<i]
            onLine(String(decoding: line, as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...i)
        }
    }
}

// MARK: - ffmpeg

struct FFTools {
    let ffmpeg: URL
    let ffprobe: URL
    let encoders: String
    let filters: String

    func has(encoder: String) -> Bool { encoders.contains(" \(encoder) ") }
    var hasToneMapping: Bool { filters.contains(" zscale ") && filters.contains(" tonemap ") }

    static func load(from dir: URL) -> FFTools? {
        let f = dir.appendingPathComponent("ffmpeg"), p = dir.appendingPathComponent("ffprobe")
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: f.path), fm.isExecutableFile(atPath: p.path) else { return nil }
        let enc = capture(f, ["-hide_banner", "-encoders"])
        guard enc.status == 0, capture(p, ["-version"]).status == 0 else { return nil }
        return FFTools(ffmpeg: f, ffprobe: p, encoders: enc.text,
                       filters: capture(f, ["-hide_banner", "-filters"]).text)
    }
}

struct MediaInfo {
    var duration: Double?
    var hasAudio = false
    var transfer: String?
    var primaries: String?
    var colorSpace: String?
    var isHDR: Bool { transfer == "smpte2084" || transfer == "arib-std-b67" }

    static func probe(_ t: FFTools, _ url: URL) -> MediaInfo {
        var info = MediaInfo()
        let v = capture(t.ffprobe, ["-v", "error", "-select_streams", "v:0",
                                    "-show_entries", "stream=color_transfer,color_primaries,color_space:format=duration",
                                    "-of", "default=nw=1", url.path]).text
        for line in v.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[1].isEmpty, kv[1] != "unknown", kv[1] != "N/A" else { continue }
            switch kv[0] {
            case "duration": info.duration = Double(kv[1])
            case "color_transfer": info.transfer = kv[1]
            case "color_primaries": info.primaries = kv[1]
            case "color_space": info.colorSpace = kv[1]
            default: break
            }
        }
        if info.duration == nil {
            // у аудиофайлов без видеопотока длительность берём из формата
            let d = capture(t.ffprobe, ["-v", "error", "-show_entries", "format=duration",
                                        "-of", "default=nw=1:nk=1", url.path]).text
            info.duration = Double(d.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let a = capture(t.ffprobe, ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_type",
                                    "-of", "default=nw=1:nk=1", url.path]).text
        info.hasAudio = a.contains("audio")
        return info
    }
}

/// Запуск ffmpeg с разбором прогресса. Блокирует вызывающий поток — вызывать не из главного.
enum FFmpegRunner {
    static func run(_ ffmpeg: URL, args: [String], duration: Double?,
                    register: (Process?) -> Void,
                    progress: @escaping (Double) -> Void) -> (status: Int32, error: String?) {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice

        let errors = Buffer()
        let total = duration ?? 0
        let lines = LineSplitter { line in
            guard total > 0, line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms="),
                  let eq = line.firstIndex(of: "="), let v = Double(line[line.index(after: eq)...]) else { return }
            progress(min(max(v / 1_000_000 / total, 0), 1))
        }
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { lines.feed(d) }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { errors.append(d) }
        }
        do { try p.run() } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            return (-1, error.localizedDescription)
        }
        register(p)
        p.waitUntilExit()
        register(nil)
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        errors.append(err.fileHandleForReading.readDataToEndOfFile())
        return (p.terminationStatus, errors.lastLines(4))
    }
}

extension Notification.Name {
    static let toolsReady = Notification.Name("DownloadAndConvert.toolsReady")
}

/// Скачивает статические сборки ffmpeg/ffprobe (Martin Riedl, подписаны) в ~/Library/Application Support/DownloadAndConvert/bin
final class FFmpegInstaller {
    static var binDir: URL { ToolsManager.supportDir.appendingPathComponent("bin", isDirectory: true) }
    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }
    static func url(_ name: String) -> URL {
        URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arch)/release/\(name).zip")!
    }

    private var observations: [NSKeyValueObservation] = []

    func install(progress: @escaping (Double, String) -> Void, done: @escaping (Result<FFTools, Error>) -> Void) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("DownloadAndConvert-" + UUID().uuidString, isDirectory: true)
        do { try fm.createDirectory(at: work, withIntermediateDirectories: true) } catch { done(.failure(error)); return }
        observations.removeAll()

        fetch("ffmpeg", into: work, from: 0, to: 0.8, progress: progress) { r1 in
            if case .failure(let e) = r1 { try? fm.removeItem(at: work); done(.failure(e)); return }
            DispatchQueue.main.async {
            self.fetch("ffprobe", into: work, from: 0.8, to: 1, progress: progress) { r2 in
                if case .failure(let e) = r2 { try? fm.removeItem(at: work); done(.failure(e)); return }
                progress(1, L("tools.installing"))
                do {
                    let bin = Self.binDir
                    try fm.createDirectory(at: bin, withIntermediateDirectories: true)
                    for name in ["ffmpeg", "ffprobe"] {
                        guard let src = Self.findFile(named: name, in: work) else { throw Failure(LF("tools.notInArchive", name)) }
                        let dst = bin.appendingPathComponent(name)
                        try? fm.removeItem(at: dst)
                        try fm.moveItem(at: src, to: dst)
                        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
                        capture(URL(fileURLWithPath: "/usr/bin/xattr"), ["-c", dst.path])
                        if capture(dst, ["-version"]).status != 0 {
                            // на всякий случай — локальная подпись, если система не приняла исходную
                            capture(URL(fileURLWithPath: "/usr/bin/codesign"), ["--force", "--sign", "-", dst.path])
                        }
                    }
                    try? fm.removeItem(at: work)
                    guard let t = FFTools.load(from: bin) else { throw Failure(L("tools.notRunnable")) }
                    done(.success(t))
                } catch {
                    try? fm.removeItem(at: work)
                    done(.failure(error))
                }
            }
            }
        }
    }

    /// Отдельная сессия: длинные таймауты, ждёт возвращения сети
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 3600
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    private static let maxTries = 8

    private func fetch(_ name: String, into dir: URL, from: Double, to: Double,
                       progress: @escaping (Double, String) -> Void,
                       done: @escaping (Result<Void, Error>) -> Void) {
        attempt(name, into: dir, from: from, to: to, resumeData: nil, tries: Self.maxTries, progress: progress, done: done)
    }

    /// Одна попытка; при обрыве — повтор с места остановки (resume data), до maxTries раз
    private func attempt(_ name: String, into dir: URL, from: Double, to: Double, resumeData: Data?, tries: Int,
                         progress: @escaping (Double, String) -> Void,
                         done: @escaping (Result<Void, Error>) -> Void) {
        let n = Self.maxTries - tries + 1
        let label = n == 1 ? LF("tools.downloading", name)
                           : LF("tools.retry", name, String(n), String(Self.maxTries))
        let handler: (URL?, URLResponse?, Error?) -> Void = { tmp, resp, err in
            if let err = err as NSError? {
                guard tries > 1, err.code != NSURLErrorCancelled else { done(.failure(err)); return }
                let rd = err.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.attempt(name, into: dir, from: from, to: to, resumeData: rd, tries: tries - 1,
                                 progress: progress, done: done)
                }
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let tmp = tmp, (200..<300).contains(code) else {
                done(.failure(Failure(LF("tools.serverError", String(code))))); return
            }
            let zip = dir.appendingPathComponent(name + ".zip")
            do {
                try FileManager.default.moveItem(at: tmp, to: zip)
                let out = dir.appendingPathComponent(name + "-unpacked", isDirectory: true)
                let r = capture(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, out.path])
                guard r.status == 0 else { throw Failure(LF("tools.unpackFail", name)) }
                done(.success(()))
            } catch {
                done(.failure(error))
            }
        }
        let task: URLSessionDownloadTask
        if let rd = resumeData {
            task = session.downloadTask(withResumeData: rd, completionHandler: handler)
        } else {
            task = session.downloadTask(with: Self.url(name), completionHandler: handler)
        }
        observations.append(task.progress.observe(\.fractionCompleted) { p, _ in
            progress(from + (to - from) * p.fractionCompleted, label)
        })
        progress(from, label)
        task.resume()
    }

    static func findFile(named name: String, in dir: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        for case let u as URL in e where u.lastPathComponent == name && !u.path.contains("__MACOSX") {
            if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return u }
        }
        return nil
    }
}

enum ToolsState: Equatable {
    case checking
    case downloading(Double, String)
    case ready
    case failed(String)
}

// MARK: - Менеджер утилит

final class ToolsManager: ObservableObject {
    static let shared = ToolsManager()

    static var supportDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DownloadAndConvert", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var localYtDlp: String { supportDir.appendingPathComponent("yt-dlp").path }

    @Published private(set) var tools: FFTools?
    @Published private(set) var state: ToolsState = .checking
    @Published private(set) var ytDlpPath: String?
    @Published private(set) var ytDlpBusy = false
    @Published var ytDlpMessage: String?
    @Published private(set) var ytDlpVersion: String?
    @Published private(set) var ytDlpLatest: String?
    /// Проверка обновлений — не чаще раза в 12 часов
    private static let checkInterval: TimeInterval = 12 * 3600
    private var ytDlpCheckedAt = Date.distantPast

    // ffmpeg: сравнение с последней сборкой на ffmpeg.martin-riedl.de
    @Published private(set) var ffmpegVersion: String?
    @Published private(set) var ffmpegLatest: String?
    private var ffmpegCheckedAt = Date.distantPast
    private static let ffmpegSourceKey = "dc.ffmpegSource"

    /// Есть сборка новее установленной
    var ffmpegOutdated: Bool {
        guard tools != nil, let latest = ffmpegLatest else { return false }
        if let stored = UserDefaults.standard.string(forKey: Self.ffmpegSourceKey) { return stored != latest }
        if let v = ffmpegVersion, let lv = Self.versionToken(in: latest) { return Self.isOlder(v, than: lv) }
        return false
    }

    static func versionToken(in s: String) -> String? {
        guard let r = s.range(of: #"\d+\.\d+(?:\.\d+)*"#, options: .regularExpression) else { return nil }
        return String(s[r])
    }

    /// Адрес, на который ведёт ссылка «последняя сборка» (первый редирект, без скачивания)
    static func resolveLatestFFmpeg(_ done: @escaping (String?) -> Void) {
        final class Catcher: NSObject, URLSessionTaskDelegate {
            var location: URL?
            func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
                location = request.url
                completionHandler(nil)
            }
        }
        let c = Catcher()
        let session = URLSession(configuration: .ephemeral, delegate: c, delegateQueue: nil)
        var req = URLRequest(url: FFmpegInstaller.url("ffmpeg"))
        req.httpMethod = "HEAD"
        req.timeoutInterval = 10
        session.dataTask(with: req) { _, _, _ in
            session.finishTasksAndInvalidate()
            done(c.location?.absoluteString)
        }.resume()
    }

    func checkFFmpeg(force: Bool = false) {
        guard let t = tools else { return }
        if !force && Date().timeIntervalSince(ffmpegCheckedAt) < Self.checkInterval { return }
        ffmpegCheckedAt = Date()
        DispatchQueue.global(qos: .utility).async {
            var version: String?
            let out = capture(t.ffmpeg, ["-version"]).text
            if let r = out.range(of: #"version (\d+(?:\.\d+)*)"#, options: .regularExpression) {
                version = String(out[r]).replacingOccurrences(of: "version ", with: "")
            }
            DispatchQueue.main.async { self.ffmpegVersion = version }
            Self.resolveLatestFFmpeg { id in
                DispatchQueue.main.async { if let id = id { self.ffmpegLatest = id } }
            }
        }
    }

    /// После скачивания запоминаем, какая именно сборка установлена
    private func recordFFmpegSource() {
        Self.resolveLatestFFmpeg { id in
            DispatchQueue.main.async {
                if let id = id { UserDefaults.standard.set(id, forKey: Self.ffmpegSourceKey) }
                self.checkFFmpeg(force: true)
            }
        }
    }

    /// Установленная версия старше последнего релиза
    var ytDlpOutdated: Bool {
        guard let v = ytDlpVersion, let l = ytDlpLatest else { return false }
        return Self.isOlder(v, than: l)
    }

    /// Сравнение версий вида 2025.11.12 (и 2025.11.12.1) по числам
    static func isOlder(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q }
        }
        return false
    }

    /// Проверяет, не устарел ли yt-dlp: версия установленной копии против последнего релиза на GitHub.
    /// Без сети тихо ничего не делает. Не чаще раза в 12 часов, если не force.
    func checkYtDlp(force: Bool = false) {
        guard let path = ytDlpPath else { return }
        if !force && Date().timeIntervalSince(ytDlpCheckedAt) < Self.checkInterval { return }
        ytDlpCheckedAt = Date()
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["--version"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            var version: String?
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let s = s, !s.isEmpty { version = s }
            }
            DispatchQueue.main.async { self.ytDlpVersion = version }

            var req = URLRequest(url: URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!)
            req.timeoutInterval = 10
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                guard (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = obj["tag_name"] as? String else { return }
                DispatchQueue.main.async { self.ytDlpLatest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")) }
            }.resume()
        }
    }

    private let installer = FFmpegInstaller()

    init() {
        migrateYtDlp()
        ytDlpPath = Self.findYtDlp()
        prepare()
        checkYtDlp()
    }

    /// Проверка обновлений всех компонентов (при открытии окна)
    func checkUpdates() {
        checkYtDlp()
        checkFFmpeg()
    }

    /// Нельзя перекачивать ffmpeg, пока он используется
    var isInUse: Bool {
        VideoConverter.shared.isRunning || AudioConverter.shared.isRunning || Downloader.shared.running
    }

    // MARK: ffmpeg

    func prepare(forceDownload: Bool = false) {
        if case .downloading = state { return }
        if forceDownload && isInUse { return }
        state = .checking
        if forceDownload { tools = nil }
        DispatchQueue.global(qos: .userInitiated).async {
            var existing: FFTools? = forceDownload ? nil : FFTools.load(from: FFmpegInstaller.binDir)
            if existing == nil && !forceDownload { existing = Self.migrateFFmpeg() }
            DispatchQueue.main.async {
                if let t = existing { self.ready(t) } else { self.download() }
            }
        }
    }

    private func download() {
        state = .downloading(0, LF("tools.downloading", "ffmpeg"))
        installer.install(progress: { p, label in
            DispatchQueue.main.async {
                if case .downloading = self.state { self.state = .downloading(p, label) }
            }
        }, done: { r in
            DispatchQueue.main.async {
                switch r {
                case .success(let t): self.ready(t); self.recordFFmpegSource()
                case .failure(let e): self.state = .failed(e.localizedDescription)
                }
            }
        })
    }

    private func ready(_ t: FFTools) {
        tools = t
        state = .ready
        checkFFmpeg()
        NotificationCenter.default.post(name: .toolsReady, object: nil)
    }

    /// Если ffmpeg уже скачан старыми программами («Конвертер», YT Загрузчик) — берём их копию, а не качаем заново
    private static func migrateFFmpeg() -> FFTools? {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = [base.appendingPathComponent("VideoToMP4/bin"), base.appendingPathComponent("YTLoader")]
        for dir in legacy {
            guard FFTools.load(from: dir) != nil else { continue }
            let bin = FFmpegInstaller.binDir
            try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
            var ok = true
            for name in ["ffmpeg", "ffprobe"] {
                let dst = bin.appendingPathComponent(name)
                try? fm.removeItem(at: dst)
                do { try fm.copyItem(at: dir.appendingPathComponent(name), to: dst) } catch { ok = false }
            }
            if ok, let t = FFTools.load(from: bin) { return t }
        }
        return nil
    }

    // MARK: yt-dlp

    static func findYtDlp() -> String? {
        [localYtDlp, "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func migrateYtDlp() {
        let fm = FileManager.default
        guard !fm.isExecutableFile(atPath: Self.localYtDlp) else { return }
        let old = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YTLoader/yt-dlp")
        if fm.isExecutableFile(atPath: old.path) {
            try? fm.copyItem(at: old, to: URL(fileURLWithPath: Self.localYtDlp))
        }
    }

    /// Скачать (или обновить) собственную копию yt-dlp
    func installYtDlp() {
        guard !ytDlpBusy else { return }
        ytDlpBusy = true
        ytDlpMessage = LF("tools.downloading", "yt-dlp")
        let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        URLSession.shared.downloadTask(with: url) { tmp, resp, err in
            var message: String
            if let tmp = tmp, err == nil, (resp as? HTTPURLResponse)?.statusCode == 200 {
                let dest = URL(fileURLWithPath: Self.localYtDlp)
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
                    message = L("tools.ytInstalled")
                } catch {
                    message = LF("tools.ytSaveFail", error.localizedDescription)
                }
            } else {
                message = LF("tools.ytDownloadFail", err?.localizedDescription ?? L("tools.networkError"))
            }
            DispatchQueue.main.async {
                self.ytDlpBusy = false
                self.ytDlpMessage = message
                self.ytDlpPath = Self.findYtDlp()
                self.checkYtDlp(force: true)
            }
        }.resume()
    }
}

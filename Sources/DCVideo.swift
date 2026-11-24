// Инструмент «Загрузка и конвертация» (раньше — отдельное приложение Download and Convert).
// Конвертация видео любого формата в MP4 (HEVC/H.264) с обрезкой.
import Foundation
import AppKit

// MARK: - Настройки

enum Codec: String, CaseIterable, Identifiable {
    case hevc, h264
    var id: String { rawValue }
    var title: String { self == .hevc ? "HEVC (H.265)" : "H.264" }
    var hint: String { self == .hevc ? L("vid.hint.hevc") : L("vid.hint.h264") }
}

/// Что делать со звуком: взаимоисключающие режимы
enum SoundMode: String, CaseIterable, Identifiable {
    case both, muted, only
    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: return L("vid.sound.both")
        case .muted: return L("vid.sound.muted")
        case .only: return L("vid.sound.only")
        }
    }
}

/// Во что конвертируем видео
enum VideoFormat: String, CaseIterable, Identifiable {
    case mp4, mov, mkv, webm, avi, gif
    var id: String { rawValue }
    var ext: String { rawValue }
    var title: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .mkv: return "MKV"
        case .webm: return "WebM"
        case .avi: return "AVI"
        case .gif: return "GIF"
        }
    }
    var muxer: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .mkv: return "matroska"
        case .webm: return "webm"
        case .avi: return "avi"
        case .gif: return "gif"
        }
    }
    /// В MP4, MOV и MKV можно выбрать кодек (HEVC или H.264); WebM и GIF имеют свой
    var usesCodecChoice: Bool { self == .mp4 || self == .mov || self == .mkv }
    var hasAudio: Bool { self != .gif }
    var hint: String { L("vid.fmt." + rawValue) }
}

/// Размер кадра: готовые варианты по короткой стороне («720p») и свой размер в рамке
enum VideoSize: String, CaseIterable, Identifiable {
    case original, p2160, p1080, p720, p480, p360, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return L("vid.size.original")
        case .p2160: return "4K (2160p)"
        case .p1080: return "Full HD (1080p)"
        case .p720: return "HD (720p)"
        case .p480: return "480p"
        case .p360: return "360p"
        case .custom: return L("vid.size.custom")
        }
    }
    var side: Int? {
        switch self {
        case .p2160: return 2160
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        case .p360: return 360
        default: return nil
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case best, transparent, small
    var id: String { rawValue }
    var title: String {
        switch self {
        case .best: return L("vid.q.best")
        case .transparent: return L("vid.q.transparent")
        case .small: return L("vid.q.small")
        }
    }
    /// CRF: чем меньше, тем выше качество и больше файл
    func crf(_ c: Codec) -> Int {
        switch (self, c) {
        case (.best, .hevc): return 18
        case (.best, .h264): return 16
        case (.transparent, .hevc): return 22
        case (.transparent, .h264): return 19
        case (.small, .hevc): return 26
        case (.small, .h264): return 23
        }
    }
    var audioBitrate: String { self == .small ? "128k" : "160k" }
    /// VP9 (WebM): шкала CRF 0–63
    var vp9CRF: Int {
        switch self {
        case .best: return 24
        case .transparent: return 31
        case .small: return 36
        }
    }
    /// AVI (кодек MPEG-4): шкала качества 2–31, меньше — лучше
    var mpeg4Q: Int {
        switch self {
        case .best: return 2
        case .transparent: return 4
        case .small: return 7
        }
    }
    /// GIF: ширина и частота кадров
    var gifWidth: Int {
        switch self {
        case .best: return 720
        case .transparent: return 480
        case .small: return 320
        }
    }
    var gifFPS: Int { self == .small ? 10 : 15 }
}

// MARK: - Обрезка

struct Segment { var a: Double; var b: Double; var length: Double { b - a } }

struct Cut: Identifiable, Equatable {
    var id = UUID()
    var from: Double
    var to: Double
}

struct Edit: Equatable {
    var start: Double = 0          // обрезать начало до этого места
    var end: Double? = nil         // обрезать всё после этого места
    var cuts: [Cut] = []           // вырезаемые куски

    var isActive: Bool { start > 0.01 || end != nil || !cuts.isEmpty }

    /// Куски, которые останутся в итоговом видео
    func keep(_ duration: Double) -> [Segment] {
        let a = max(0, min(start, duration)), b = min(end ?? duration, duration)
        guard b > a else { return [] }
        var segs = [Segment(a: a, b: b)]
        for c in cuts.sorted(by: { min($0.from, $0.to) < min($1.from, $1.to) }) {
            let lo = min(c.from, c.to), hi = max(c.from, c.to)
            var next: [Segment] = []
            for s in segs {
                if hi <= s.a || lo >= s.b { next.append(s); continue }
                if lo > s.a { next.append(Segment(a: s.a, b: lo)) }
                if hi < s.b { next.append(Segment(a: hi, b: s.b)) }
            }
            segs = next
        }
        return segs.filter { $0.length > 0.04 }
    }

    func keptDuration(_ duration: Double) -> Double { keep(duration).reduce(0) { $0 + $1.length } }
}

// MARK: - Очередь

struct VideoJob: Identifiable {
    let id = UUID()
    let input: URL
    let inputSize: Int64
    var duration: Double? = nil
    var probed = false
    var edit = Edit()
    var state: JobState = .waiting
}

// MARK: - Конвертер

final class VideoConverter: ObservableObject {
    static let shared = VideoConverter()

    @Published var jobs: [VideoJob] = []
    @Published private(set) var isRunning = false

    @Published var format: VideoFormat {
        didSet {
            UserDefaults.standard.set(format.rawValue, forKey: "vid.format")
            if !format.hasAudio { sound = .both }   // у GIF звука нет — режимы звука не применяются
        }
    }
    @Published var codec: Codec { didSet { UserDefaults.standard.set(codec.rawValue, forKey: "vid.codec") } }
    @Published var quality: VideoQuality { didSet { UserDefaults.standard.set(quality.rawValue, forKey: "vid.quality") } }
    /// Размер кадра: по умолчанию не меняем; если включено — вписываем в рамку «ширина × высота»
    @Published var size: VideoSize { didSet { UserDefaults.standard.set(size.rawValue, forKey: "vid.size") } }
    @Published var resizeW: String { didSet { UserDefaults.standard.set(resizeW, forKey: "vid.resizeW") } }
    @Published var resizeH: String { didSet { UserDefaults.standard.set(resizeH, forKey: "vid.resizeH") } }
    /// Введённый размер: оба числа целые и больше нуля
    var resizeBox: (w: Int, h: Int)? {
        guard let w = Int(resizeW.trimmingCharacters(in: .whitespaces)), let h = Int(resizeH.trimmingCharacters(in: .whitespaces)),
              w > 0, h > 0, w <= 16384, h <= 16384 else { return nil }
        return (w, h)
    }
    @Published var limit1080: Bool { didSet { UserDefaults.standard.set(limit1080, forKey: "vid.limit1080") } }
    /// Настройки режима «Только звук»: звуковой формат и битрейт
    @Published var audioFormat: AudioFormat { didSet { UserDefaults.standard.set(audioFormat.rawValue, forKey: "vid.audioFormat") } }
    @Published var audioKbps: Int { didSet { UserDefaults.standard.set(audioKbps, forKey: "vid.audioKbps") } }
    @Published var sound: SoundMode { didSet { UserDefaults.standard.set(sound.rawValue, forKey: "vid.sound") } }
    @Published var outputDir: URL? {
        didSet {
            if let p = outputDir?.path { UserDefaults.standard.set(p, forKey: "vid.outDir") }
            else { UserDefaults.standard.removeObject(forKey: "vid.outDir") }
        }
    }

    private let lock = NSLock()
    private var process: Process?
    private var currentTemp: URL?
    private var stopRequested = false
    private var convertedInRun = 0

    init() {
        let d = UserDefaults.standard
        format = VideoFormat(rawValue: d.string(forKey: "vid.format") ?? "") ?? .mp4
        codec = Codec(rawValue: d.string(forKey: "vid.codec") ?? "") ?? .hevc
        quality = VideoQuality(rawValue: d.string(forKey: "vid.quality") ?? "") ?? .transparent
        limit1080 = d.bool(forKey: "vid.limit1080")
        // прежний чекбокс «Не больше Full HD» стал пунктом «1080p»
        size = VideoSize(rawValue: d.string(forKey: "vid.size") ?? "") ?? (d.bool(forKey: "vid.limit1080") ? .p1080 : .original)
        resizeW = d.string(forKey: "vid.resizeW") ?? "1920"
        resizeH = d.string(forKey: "vid.resizeH") ?? "1080"
        audioFormat = AudioFormat(rawValue: d.string(forKey: "vid.audioFormat") ?? "") ?? .mp3
        let kb = d.integer(forKey: "vid.audioKbps")
        audioKbps = [128, 192, 256, 320].contains(kb) ? kb : 192
        if let raw = d.string(forKey: "vid.sound"), let m = SoundMode(rawValue: raw) { sound = m }
        else { sound = d.bool(forKey: "vid.removeAudio") ? .muted : .both }
        outputDir = nil; d.removeObject(forKey: "vid.outDir")
        NotificationCenter.default.addObserver(forName: .toolsReady, object: nil, queue: .main) { [weak self] _ in
            self?.probeMissing()
        }
    }

    private func probeMissing() {
        guard let t = ToolsManager.shared.tools else { return }
        let targets = jobs.filter { !$0.probed }.map { ($0.id, $0.input) }
        guard !targets.isEmpty else { return }
        for (id, _) in targets { if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].probed = true } }
        DispatchQueue.global(qos: .utility).async {
            for (id, url) in targets {
                let d = MediaInfo.probe(t, url).duration
                DispatchQueue.main.async {
                    if let i = self.jobs.firstIndex(where: { $0.id == id }) { self.jobs[i].duration = d }
                }
            }
        }
    }

    // MARK: очередь

    func add(_ urls: [URL]) {
        for f in collectFiles(urls, accept: isVideoFile).filter(isVideoFile) {
            let same = f.standardizedFileURL
            if jobs.contains(where: { $0.input.standardizedFileURL == same && !$0.state.isFinished }) { continue }
            jobs.append(VideoJob(input: f, inputSize: fileSize(f)))
        }
        probeMissing()
    }

    func remove(_ id: UUID) { jobs.removeAll { $0.id == id && !$0.state.isRunning } }
    func retry(_ id: UUID) { if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state.canRetry { jobs[i].state = .waiting } }
    func clearFinished() { jobs.removeAll { $0.state.isFinished } }
    /// Очищает окно: убирает всё, кроме файла, который конвертируется прямо сейчас
    func clearAll() { jobs.removeAll { !$0.state.isRunning } }

    func setEdit(_ id: UUID, _ e: Edit) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), !jobs[i].state.isRunning else { return }
        if jobs[i].edit != e {
            jobs[i].edit = e
            if jobs[i].state.isFinished { jobs[i].state = .waiting }
        }
    }

    var hasWaiting: Bool { jobs.contains { $0.state == .waiting } }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }
    var totalsText: String { queueTotals(jobs.map { ($0.inputSize, $0.state) }) }

    // MARK: запуск

    func start() {
        guard !isRunning, ToolsManager.shared.tools != nil else { return }
        stopRequested = false
        convertedInRun = 0
        isRunning = true
        next()
    }

    func stop() {
        stopRequested = true
        lock.lock(); let p = process; lock.unlock()
        if let p = p, p.isRunning { p.terminate() }
    }

    /// При выходе из программы: прервать и убрать недописанный файл
    func abortForQuit() {
        stopRequested = true
        lock.lock(); let p = process; lock.unlock()
        if let p = p, p.isRunning { p.terminate(); p.waitUntilExit() }
        if let t = currentTemp { try? FileManager.default.removeItem(at: t) }
    }

    private func setProcess(_ p: Process?) { lock.lock(); process = p; lock.unlock() }

    private struct Settings { let format: VideoFormat; let codec: Codec; let quality: VideoQuality; let size: VideoSize; let box: (w: Int, h: Int)?; let resizeInvalid: Bool; let sound: SoundMode
                          let audioFormat: AudioFormat; let audioKbps: Int }
    private struct Plan { let args: [String]; let duration: Double? }

    private func next() {
        guard !stopRequested, let t = ToolsManager.shared.tools,
              let i = jobs.firstIndex(where: { $0.state == .waiting }) else {
            let finishedNormally = !stopRequested && convertedInRun > 0
            isRunning = false
            currentTemp = nil
            if finishedNormally {
                NSSound(named: NSSound.Name("Glass"))?.play()
                NSApp.requestUserAttention(.informationalRequest)
            }
            return
        }
        jobs[i].state = .running(-1)
        let job = jobs[i]
        let fmt = format
        let ext = (fmt.hasAudio && sound == .only) ? audioFormat.ext : fmt.ext
        let output = Self.outputURL(for: job.input, in: outputDir ?? defaultOutputDir(for: job.input), ext: ext)
        let temp = output.deletingLastPathComponent()
            .appendingPathComponent("." + output.deletingPathExtension().lastPathComponent + ".partial." + ext)
        try? FileManager.default.removeItem(at: temp)
        currentTemp = temp
        let s = Settings(format: fmt, codec: codec, quality: quality, size: size, box: size == .custom ? resizeBox : nil,
                     resizeInvalid: size == .custom && resizeBox == nil, sound: sound,
                     audioFormat: audioFormat, audioKbps: audioKbps)
        let id = job.id

        DispatchQueue.global(qos: .userInitiated).async {
            let info = MediaInfo.probe(t, job.input)
            let plan: Plan
            do {
                plan = try Self.makePlan(t, input: job.input, output: temp, info: info, edit: job.edit, s: s)
            } catch {
                let msg = error.localizedDescription
                DispatchQueue.main.async { self.complete(id, temp: temp, output: output, status: -1, error: msg) }
                return
            }
            if self.stopRequested {
                DispatchQueue.main.async { self.complete(id, temp: temp, output: output, status: 0, error: nil) }
                return
            }
            let r = FFmpegRunner.run(t.ffmpeg, args: plan.args, duration: plan.duration,
                                     register: { self.setProcess($0) },
                                     progress: { v in DispatchQueue.main.async { self.setProgress(id, v) } })
            DispatchQueue.main.async { self.complete(id, temp: temp, output: output, status: r.status, error: r.error) }
        }
    }

    private func setProgress(_ id: UUID, _ v: Double) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state.isRunning else { return }
        jobs[i].state = .running(v)
    }

    private func complete(_ id: UUID, temp: URL, output: URL, status: Int32, error: String?) {
        setProcess(nil)
        currentTemp = nil
        let fm = FileManager.default
        let state: JobState
        if stopRequested {
            try? fm.removeItem(at: temp)
            state = .cancelled
        } else if status != 0 {
            try? fm.removeItem(at: temp)
            state = .failed(error ?? LF("vid.ffmpegError", String(status)))
        } else {
            do {
                try fm.moveItem(at: temp, to: output)
                state = .done(output: output, size: fileSize(output))
                convertedInRun += 1
            } catch {
                try? fm.removeItem(at: temp)
                state = .failed(error.localizedDescription)
            }
        }
        if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].state = state }
        next()
    }

    /// Результат кладётся в выбранную папку (по умолчанию рядом с оригиналом): «имя.mp4», а если занято — «имя (сконвертировано).mp4»
    static func outputURL(for input: URL, in dir: URL, ext: String) -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        let suffix = L("vid.suffix")
        var candidate = dir.appendingPathComponent(base + "." + ext)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(n == 1 ? "\(base) (\(suffix)).\(ext)" : "\(base) (\(suffix) \(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    private static func num(_ v: Double) -> String { String(format: "%.3f", v) }

    /// «Только звук»: из видео берётся звуковая дорожка и кодируется в выбранный звуковой формат
    /// (обрезка и вырезание кусков работают так же)
    private static func makeAudioOnlyPlan(_ t: FFTools, input: URL, output: URL, info: MediaInfo, edit: Edit, s: Settings) throws -> Plan {
        let af = s.audioFormat
        guard t.has(encoder: af.encoder) else { throw Failure(LF("common.noEncoder", af.encoder)) }
        guard info.hasAudio else { throw Failure(L("aud.noAudio")) }

        var args = ["-hide_banner", "-nostdin", "-y"]
        var duration = info.duration
        let map: [String]
        if edit.isActive {
            guard let total = info.duration, total > 0 else { throw Failure(L("vid.noDuration")) }
            let segs = edit.keep(total)
            guard !segs.isEmpty else { throw Failure(L("vid.nothingLeft")) }
            duration = segs.reduce(0) { $0 + $1.length }
            if segs.count == 1 {
                args += ["-ss", num(segs[0].a), "-t", num(segs[0].length), "-i", input.path]
                map = ["-map", "0:a:0"]
            } else {
                var parts: [String] = []
                var pads = ""
                for (i, g) in segs.enumerated() {
                    parts.append("[0:a:0]atrim=start=\(num(g.a)):end=\(num(g.b)),asetpts=PTS-STARTPTS[a\(i)]")
                    pads += "[a\(i)]"
                }
                parts.append("\(pads)concat=n=\(segs.count):v=0:a=1[ac]")
                args += ["-i", input.path, "-filter_complex", parts.joined(separator: ";")]
                map = ["-map", "[ac]"]
            }
        } else {
            args += ["-i", input.path]
            map = ["-map", "0:a:0"]
        }
        args += ["-vn"] + map + ["-map_metadata", "0"]
        args += af.encodeArgs(kbps: s.audioKbps)
        args += ["-progress", "pipe:1", "-nostats", "-loglevel", "error", "-f", af.muxer, output.path]
        return Plan(args: args, duration: duration)
    }

    private static func makePlan(_ t: FFTools, input: URL, output: URL, info: MediaInfo, edit: Edit, s: Settings) throws -> Plan {
        let f = s.format
        if f.hasAudio && s.sound == .only {
            return try makeAudioOnlyPlan(t, input: input, output: output, info: info, edit: edit, s: s)
        }
        let videoEncoder: String
        switch f {
        case .webm: videoEncoder = "libvpx-vp9"
        case .gif: videoEncoder = "gif"
        case .avi: videoEncoder = "mpeg4"
        default: videoEncoder = s.codec == .hevc ? "libx265" : "libx264"
        }
        guard t.has(encoder: videoEncoder) else { throw Failure(LF("common.noEncoder", videoEncoder)) }
        let audio = f.hasAudio && info.hasAudio && s.sound == .both
        if audio && f == .webm {
            guard t.has(encoder: "libopus") else { throw Failure(LF("common.noEncoder", "libopus")) }
        }
        if audio && f == .avi {
            guard t.has(encoder: "libmp3lame") else { throw Failure(LF("common.noEncoder", "libmp3lame")) }
        }
        if s.resizeInvalid { throw Failure(L("vid.resize.bad")) }
        let hevc = f.usesCodecChoice && s.codec == .hevc
        // перевод HDR в обычный цвет без «блёклости»
        let toneMap = "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"

        // Видеофильтры: размер, чётные стороны, цвет
        var vf: [String] = []
        var color: [String] = []
        if f == .gif {
            if info.isHDR && t.hasToneMapping { vf.append(toneMap) }
            vf.append("fps=\(s.quality.gifFPS)")
            vf.append("scale=w=min(\(s.quality.gifWidth)\\,iw):h=-2:flags=lanczos")
            vf.append("split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5")
        } else {
            if let b = s.box {
                // вписываем в рамку, пропорции сохраняются, увеличения нет
                vf.append("scale=w=min(\(b.w)\\,iw):h=min(\(b.h)\\,ih):force_original_aspect_ratio=decrease:flags=lanczos")
            } else if let n = s.size.side {
                // «720p» — по короткой стороне, поэтому подходит и вертикальному видео; меньший кадр не увеличиваем
                vf.append("scale=w=if(gte(iw\\,ih)\\,-2\\,min(\(n)\\,iw)):h=if(gte(iw\\,ih)\\,min(\(n)\\,ih)\\,-2):flags=lanczos")
            }
            vf.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")
            if info.isHDR && hevc {
                // HDR с iPhone: сохраняем 10 бит и цветовые метки — Keynote и QuickTime покажут правильно
                vf.append("format=yuv420p10le")
                if let v = info.primaries { color += ["-color_primaries", v] }
                if let v = info.transfer { color += ["-color_trc", v] }
                if let v = info.colorSpace { color += ["-colorspace", v] }
            } else if info.isHDR && t.hasToneMapping {
                // H.264 и VP9 здесь работают в обычном цвете
                vf.append(toneMap)
                color += ["-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709"]
            } else {
                vf.append("format=yuv420p")
            }
        }
        let chain = vf.joined(separator: ",")

        var args = ["-hide_banner", "-nostdin", "-y"]
        var duration = info.duration
        let maps: [String]

        if edit.isActive {
            guard let total = info.duration, total > 0 else { throw Failure(L("vid.noDuration")) }
            let segs = edit.keep(total)
            guard !segs.isEmpty else { throw Failure(L("vid.nothingLeft")) }
            duration = segs.reduce(0) { $0 + $1.length }
            if segs.count == 1 {
                // один кусок — быстрый точный переход
                args += ["-ss", num(segs[0].a), "-t", num(segs[0].length), "-i", input.path, "-vf", chain]
                maps = ["-map", "0:v:0"] + (audio ? ["-map", "0:a:0"] : [])
            } else {
                // несколько кусков — склейка
                var parts: [String] = []
                var pads = ""
                for (i, g) in segs.enumerated() {
                    parts.append("[0:v:0]trim=start=\(num(g.a)):end=\(num(g.b)),setpts=PTS-STARTPTS[v\(i)]")
                    pads += "[v\(i)]"
                    if audio {
                        parts.append("[0:a:0]atrim=start=\(num(g.a)):end=\(num(g.b)),asetpts=PTS-STARTPTS[a\(i)]")
                        pads += "[a\(i)]"
                    }
                }
                parts.append("\(pads)concat=n=\(segs.count):v=1:a=\(audio ? 1 : 0)[vc]\(audio ? "[ac]" : "")")
                parts.append("[vc]\(chain)[vout]")
                args += ["-i", input.path, "-filter_complex", parts.joined(separator: ";")]
                maps = ["-map", "[vout]"] + (audio ? ["-map", "[ac]"] : [])
            }
        } else {
            args += ["-i", input.path, "-vf", chain]
            maps = ["-map", "0:v:0"] + (audio ? ["-map", "0:a:0"] : [])
        }

        args += maps
        switch f {
        case .gif:
            args += ["-loop", "0"]
        case .avi:
            args += ["-c:v", "mpeg4", "-q:v", "\(s.quality.mpeg4Q)", "-vtag", "xvid"]
        case .webm:
            args += ["-c:v", "libvpx-vp9", "-crf", "\(s.quality.vp9CRF)", "-b:v", "0",
                     "-row-mt", "1", "-deadline", "good", "-cpu-used", "2"]
        default:
            if s.codec == .hevc {
                args += ["-c:v", "libx265", "-preset", "slow", "-crf", "\(s.quality.crf(.hevc))"]
                // hvc1 — метка, без которой Apple не воспроизводит HEVC в MP4 и MOV
                if f != .mkv { args += ["-tag:v", "hvc1"] }
                args += ["-x265-params", "log-level=error"]
            } else {
                args += ["-c:v", "libx264", "-preset", "slow", "-crf", "\(s.quality.crf(.h264))", "-profile:v", "high"]
            }
        }
        args += color
        if audio {
            switch f {
            case .webm: args += ["-c:a", "libopus", "-b:a", "128k"]
            case .avi: args += ["-c:a", "libmp3lame", "-b:a", s.quality.audioBitrate]
            default: args += ["-c:a", "aac", "-b:a", s.quality.audioBitrate]
            }
        } else {
            args += ["-an"]
        }
        args += ["-map_metadata", "0", "-map_chapters", "-1"]
        if f == .mp4 || f == .mov { args += ["-movflags", "+faststart"] }
        args += ["-progress", "pipe:1", "-nostats", "-loglevel", "error", "-f", f.muxer, output.path]
        return Plan(args: args, duration: duration)
    }
}

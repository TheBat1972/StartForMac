// Инструмент «Загрузка и конвертация» (раньше — отдельное приложение Download and Convert).
// Конвертация любого аудио/видео в выбранный аудиоформат.
import SwiftUI
import AppKit

enum AudioFormat: String, CaseIterable, Identifiable {
    case mp3, m4a, flac, wav, aiff, ogg, opus
    var id: String { rawValue }
    var ext: String { rawValue }
    var title: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .flac: return "FLAC"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .ogg: return "OGG"
        case .opus: return "Opus"
        }
    }
    var encoder: String {
        switch self {
        case .mp3: return "libmp3lame"
        case .m4a: return "aac"
        case .flac: return "flac"
        case .wav: return "pcm_s16le"
        case .aiff: return "pcm_s16be"
        case .ogg: return "libvorbis"
        case .opus: return "libopus"
        }
    }
    var muxer: String {
        switch self {
        case .mp3: return "mp3"
        case .m4a: return "ipod"
        case .flac: return "flac"
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .ogg: return "ogg"
        case .opus: return "opus"
        }
    }
    /// У форматов со сжатием с потерями выбирается битрейт, у остальных — нет
    var isLossy: Bool { self == .mp3 || self == .m4a || self == .ogg || self == .opus }
    /// Аргументы ffmpeg для звука этого формата
    func encodeArgs(kbps: Int) -> [String] {
        var a = ["-codec:a", encoder]
        if isLossy { a += ["-b:a", "\(kbps)k"] }
        if self == .mp3 { a += ["-id3v2_version", "3"] }
        return a
    }
    var hint: String { L("aud.hint." + rawValue) }
}

struct AudioJob: Identifiable {
    let id = UUID()
    let input: URL
    let inputSize: Int64
    var duration: Double? = nil
    var probed = false
    var state: JobState = .waiting
}

final class AudioConverter: ObservableObject {
    static let shared = AudioConverter()

    @Published var jobs: [AudioJob] = []
    @Published private(set) var isRunning = false
    @Published var format: AudioFormat { didSet { UserDefaults.standard.set(format.rawValue, forKey: "aud.format") } }
    @Published var bitrate: Int { didSet { UserDefaults.standard.set(bitrate, forKey: "mp3.bitrate") } }
    @Published var outputDir: URL? {
        didSet {
            if let p = outputDir?.path { UserDefaults.standard.set(p, forKey: "mp3.outDir") }
            else { UserDefaults.standard.removeObject(forKey: "mp3.outDir") }
        }
    }

    private let lock = NSLock()
    private var process: Process?
    private var currentTemp: URL?
    private var stopRequested = false
    private var convertedInRun = 0

    init() {
        let d = UserDefaults.standard
        let b = d.integer(forKey: "mp3.bitrate")
        bitrate = [128, 192, 256, 320].contains(b) ? b : 192
        format = AudioFormat(rawValue: d.string(forKey: "aud.format") ?? "") ?? .mp3
        outputDir = d.string(forKey: "mp3.outDir").map { URL(fileURLWithPath: $0) }
        NotificationCenter.default.addObserver(forName: .toolsReady, object: nil, queue: .main) { [weak self] _ in
            self?.probeMissing()
        }
    }

    var hasWaiting: Bool { jobs.contains { $0.state == .waiting } }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }
    var totalsText: String { queueTotals(jobs.map { ($0.inputSize, $0.state) }) }

    func add(_ urls: [URL]) {
        let files = collectFiles(urls, accept: isMediaFile)
        for f in files {
            let same = f.standardizedFileURL
            if jobs.contains(where: { $0.input.standardizedFileURL == same && !$0.state.isFinished }) { continue }
            jobs.append(AudioJob(input: f, inputSize: fileSize(f)))
        }
        probeMissing()
    }

    func remove(_ id: UUID) { jobs.removeAll { $0.id == id && !$0.state.isRunning } }
    func retry(_ id: UUID) { if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state.canRetry { jobs[i].state = .waiting } }
    func clearFinished() { jobs.removeAll { $0.state.isFinished } }

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
        let kbps = bitrate
        let fmt = format
        let dir = outputDir ?? defaultOutputDir(for: job.input)
        let output = Self.uniqueURL(dir: dir, base: job.input.deletingPathExtension().lastPathComponent, ext: fmt.ext)
        let temp = dir.appendingPathComponent("." + output.deletingPathExtension().lastPathComponent + ".partial." + fmt.ext)
        try? FileManager.default.removeItem(at: temp)
        currentTemp = temp
        let id = job.id

        DispatchQueue.global(qos: .userInitiated).async {
            guard t.has(encoder: fmt.encoder) else {
                DispatchQueue.main.async {
                    self.complete(id, temp: temp, output: output, status: -1, error: LF("common.noEncoder", fmt.encoder))
                }
                return
            }
            let duration = job.duration ?? MediaInfo.probe(t, job.input).duration
            var args = ["-hide_banner", "-nostdin", "-y",
                        "-i", job.input.path,
                        "-vn", "-map", "0:a:0", "-map_metadata", "0"]
            args += fmt.encodeArgs(kbps: kbps)
            args += ["-progress", "pipe:1", "-nostats", "-loglevel", "error", "-f", fmt.muxer, temp.path]
            let r = FFmpegRunner.run(t.ffmpeg, args: args, duration: duration,
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
            var msg = error ?? LF("aud.ffmpegError", String(status))
            if msg.contains("matches no streams") || msg.contains("does not contain any stream") {
                msg = L("aud.noAudio")
            } else if msg.contains("Unknown encoder") {
                msg = LF("common.noEncoder", format.encoder)
            }
            state = .failed(msg)
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

    private static func uniqueURL(dir: URL, base: String, ext: String) -> URL {
        var url = dir.appendingPathComponent(base + "." + ext)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}

// MARK: - Интерфейс

struct AudioView: View {
    @ObservedObject var c = AudioConverter.shared
    @ObservedObject var tm = ToolsManager.shared
    @State private var targeted = false

    var body: some View {
        SectionPage {
            VStack(alignment: .leading, spacing: 9) {
                OptionRow(L("common.format")) {
                    Picker("", selection: $c.format) {
                        ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                OptionRow("") { HintText(c.format.hint) }
                OptionRow(L("common.quality")) {
                    if c.format.isLossy {
                        Picker("", selection: $c.bitrate) {
                            ForEach([128, 192, 256, 320], id: \.self) { Text(LF("aud.kbps", String($0))).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    } else {
                        Text(L("aud.lossless")).foregroundColor(.secondary)
                    }
                }
                OptionRow(L("common.saveTo")) {
                    FolderRow(path: c.outputDir?.path, placeholder: L("common.nextToOriginal"),
                              onChoose: { if let u = chooseFolder() { c.outputDir = u } },
                              onReset: c.outputDir == nil ? nil : { c.outputDir = nil })
                }
            }
            .disabled(c.isRunning)
        } content: {
            if c.jobs.isEmpty {
                DropZone(icon: "waveform", title: L("aud.dropTitle"), subtitle: L("aud.dropSub"),
                         targeted: targeted) { c.add(chooseMediaFiles(prompt: L("common.add"))) }
            } else {
                List {
                    ForEach(c.jobs) { job in
                        JobRow(input: job.input, inputSize: job.inputSize, duration: job.duration, state: job.state,
                               onRetry: { c.retry(job.id) }, onRemove: { c.remove(job.id) })
                    }
                }
            }
        } bottom: {
            HStack {
                Button(L("common.add")) { c.add(chooseMediaFiles(prompt: L("common.add"))) }
                Button(L("common.clearFinished")) { c.clearFinished() }.disabled(!c.hasFinished)
                Spacer()
                Text(c.totalsText).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if c.isRunning {
                    Button(L("common.stop")) { c.stop() }
                } else {
                    Button(L("common.convert")) { c.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!c.hasWaiting || tm.tools == nil)
                }
            }
        }
        .fileDrop(targeted: $targeted) { c.add($0) }
    }
}

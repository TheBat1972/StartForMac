// Раздел «Картинки» в «Загрузке и конвертации»: уменьшить размер картинок и сжать их.
// Работает встроенными средствами macOS (ImageIO), без ffmpeg и без интернета.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImgFormat: String, CaseIterable, Identifiable {
    case keep, jpeg, png, heic, tiff
    var id: String { rawValue }
    var title: String {
        switch self {
        case .keep: return L("img.keep")
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }
    /// У JPEG и HEIC качество задаётся ползунком
    var isLossy: Bool { self == .jpeg || self == .heic }
}

struct ImageJob: Identifiable {
    let id = UUID()
    let input: URL
    let inputSize: Int64
    var state: JobState = .waiting
}

final class ImageConverter: ObservableObject {
    static let shared = ImageConverter()

    @Published var jobs: [ImageJob] = []
    @Published private(set) var isRunning = false
    @Published var format: ImgFormat { didSet { UserDefaults.standard.set(format.rawValue, forKey: "img.format") } }
    @Published var quality: Int { didSet { UserDefaults.standard.set(quality, forKey: "img.quality") } }
    /// Длинная сторона в пикселях; 0 — как в оригинале, -1 — своё значение из customSide
    @Published var sizeChoice: Int { didSet { UserDefaults.standard.set(sizeChoice, forKey: "img.size") } }
    @Published var customSide: String { didSet { UserDefaults.standard.set(customSide, forKey: "img.customSide") } }
    /// Убирать из файла геопозицию, модель камеры и прочие метаданные (по умолчанию — да)
    @Published var stripMeta: Bool { didSet { UserDefaults.standard.set(stripMeta, forKey: "img.strip") } }

    static let sizes = [0, 3840, 2560, 1920, 1600, 1280, 1024, 800, 640]
    private var stopRequested = false

    init() {
        let d = UserDefaults.standard
        format = ImgFormat(rawValue: d.string(forKey: "img.format") ?? "") ?? .keep
        let q = d.integer(forKey: "img.quality")
        quality = (30...100).contains(q) ? q : 80
        let s = d.object(forKey: "img.size") as? Int ?? 0
        sizeChoice = (ImageConverter.sizes + [-1]).contains(s) ? s : 0
        customSide = d.string(forKey: "img.customSide") ?? "1500"
        stripMeta = d.object(forKey: "img.strip") as? Bool ?? true
    }

    var hasWaiting: Bool { jobs.contains { $0.state == .waiting } }
    var hasFinished: Bool { jobs.contains { $0.state.isFinished } }
    var totalsText: String { queueTotals(jobs.map { ($0.inputSize, $0.state) }) }

    /// Нужная длинная сторона: 0 — не менять
    var maxSide: Int {
        if sizeChoice == -1 { return max(0, Int(customSide.trimmingCharacters(in: .whitespaces)) ?? 0) }
        return sizeChoice
    }

    static func isImage(_ u: URL) -> Bool {
        guard let t = UTType(filenameExtension: u.pathExtension.lowercased()) else { return false }
        return t.conforms(to: .image) && !t.conforms(to: .pdf) && !t.conforms(to: .svg)
    }

    func add(_ urls: [URL]) {
        let files = collectFiles(urls, accept: Self.isImage).filter(Self.isImage)
        for f in files {
            let same = f.standardizedFileURL
            if jobs.contains(where: { $0.input.standardizedFileURL == same && !$0.state.isFinished }) { continue }
            jobs.append(ImageJob(input: f, inputSize: fileSize(f)))
        }
    }

    func remove(_ id: UUID) { jobs.removeAll { $0.id == id && !$0.state.isRunning } }
    func retry(_ id: UUID) { if let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state.canRetry { jobs[i].state = .waiting } }
    func clearFinished() { jobs.removeAll { $0.state.isFinished } }
    func clearAll() { jobs.removeAll { !$0.state.isRunning } }

    func start() {
        guard !isRunning else { return }
        stopRequested = false
        isRunning = true
        next(done: 0)
    }

    func stop() { stopRequested = true }
    func abortForQuit() { stopRequested = true }

    private func next(done: Int) {
        guard !stopRequested, let i = jobs.firstIndex(where: { $0.state == .waiting }) else {
            isRunning = false
            if !stopRequested && done > 0 {
                NSSound(named: NSSound.Name("Glass"))?.play()
                NSApp.requestUserAttention(.informationalRequest)
            }
            return
        }
        jobs[i].state = .running(-1)
        let job = jobs[i]
        let fmt = format, q = quality, side = maxSide, strip = stripMeta
        let dir = defaultOutputDir(for: job.input)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Self.convert(job.input, format: fmt, quality: q, maxSide: side, strip: strip, dir: dir)
            DispatchQueue.main.async {
                if let k = self.jobs.firstIndex(where: { $0.id == job.id }) {
                    switch r {
                    case .success(let url): self.jobs[k].state = .done(output: url, size: fileSize(url))
                    case .failure(let e): self.jobs[k].state = .failed(e.message)
                    }
                }
                if case .success = r { self.next(done: done + 1) } else { self.next(done: done) }
            }
        }
    }

    struct ImgError: Error { let message: String }

    /// Читает картинку, при необходимости уменьшает (с учётом поворота из EXIF) и записывает в выбранном формате
    static func convert(_ input: URL, format: ImgFormat, quality: Int, maxSide: Int, strip: Bool, dir: URL) -> Result<URL, ImgError> {
        guard let src = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return .failure(ImgError(message: L("img.errOpen")))
        }
        let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let longest = max(w, h)
        // не увеличиваем: если нужная сторона больше исходной, размер остаётся прежним
        let target = (maxSide > 0 && maxSide < longest) ? maxSide : longest
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target, 1)]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return .failure(ImgError(message: L("img.errOpen")))
        }
        // формат результата: «Как есть» оставляет JPEG, PNG, HEIC и TIFF, остальное (WebP, GIF, BMP…) станет PNG
        var out = format
        if out == .keep {
            let t = UTType(filenameExtension: input.pathExtension.lowercased())
            if t?.conforms(to: .jpeg) == true { out = .jpeg }
            else if t?.conforms(to: .heic) == true { out = .heic }
            else if t?.conforms(to: .tiff) == true { out = .tiff }
            else { out = .png }
        }
        let uti: UTType, ext: String
        switch out {
        case .jpeg: uti = .jpeg; ext = "jpg"
        case .heic: uti = .heic; ext = "heic"
        case .tiff: uti = .tiff; ext = "tiff"
        default: uti = .png; ext = "png"
        }
        let base = input.deletingPathExtension().lastPathComponent + "-min"
        var url = dir.appendingPathComponent(base + "." + ext)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        let temp = dir.appendingPathComponent("." + url.lastPathComponent + ".partial")
        try? FileManager.default.removeItem(at: temp)
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, uti.identifier as CFString, 1, nil) else {
            return .failure(ImgError(message: L("img.errWrite")))
        }
        var p: [CFString: Any] = [:]
        if !strip {
            // метаданные оригинала, кроме поворота (он уже применён к пикселям)
            p = props
            p.removeValue(forKey: kCGImagePropertyOrientation)
            p.removeValue(forKey: kCGImagePropertyPixelWidth)
            p.removeValue(forKey: kCGImagePropertyPixelHeight)
            if var tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
                p[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        if out.isLossy { p[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100 }
        CGImageDestinationAddImage(dest, cg, p as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: temp)
            return .failure(ImgError(message: L("img.errWrite")))
        }
        do { try FileManager.default.moveItem(at: temp, to: url) }
        catch { try? FileManager.default.removeItem(at: temp); return .failure(ImgError(message: error.localizedDescription)) }
        return .success(url)
    }
}

func chooseImageFiles() -> [URL] {
    let p = NSOpenPanel()
    p.allowsMultipleSelection = true
    p.canChooseDirectories = true
    p.canChooseFiles = true
    p.allowedContentTypes = [.image, .folder]
    p.prompt = L("common.add")
    return p.runModal() == .OK ? p.urls : []
}

struct ImagesView: View {
    @ObservedObject var c = ImageConverter.shared
    @State private var targeted = false

    var body: some View {
        SectionPage {
            VStack(alignment: .leading, spacing: 9) {
                OptionRow(L("common.format")) {
                    Picker("", selection: $c.format) {
                        ForEach(ImgFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                OptionRow(L("img.size")) {
                    HStack(spacing: 8) {
                        Picker("", selection: $c.sizeChoice) {
                            Text(L("img.original")).tag(0)
                            ForEach(ImageConverter.sizes.filter { $0 > 0 }, id: \.self) { Text("\($0) px").tag($0) }
                            Text(L("img.custom")).tag(-1)
                        }
                        .labelsHidden().fixedSize()
                        if c.sizeChoice == -1 {
                            TextField("", text: $c.customSide).frame(width: 70)
                            Text("px").foregroundColor(.secondary)
                        }
                    }
                }
                OptionRow("") { HintText(L("img.sizeHint")) }
                OptionRow(L("common.quality")) {
                    if c.format == .png || c.format == .tiff {
                        Text(L("img.lossless")).foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Slider(value: Binding(get: { Double(c.quality) }, set: { c.quality = Int($0) }), in: 30...100, step: 5)
                                .frame(width: 200)
                            Text("\(c.quality)%").monospacedDigit().frame(width: 44, alignment: .leading)
                        }
                    }
                }
                OptionRow(L("img.meta")) {
                    Toggle(L("img.metaStrip"), isOn: $c.stripMeta).toggleStyle(.checkbox)
                }
                OptionRow(L("common.saveTo")) { Text(L("common.toDownloads")) }
            }
            .disabled(c.isRunning)
        } content: {
            if c.jobs.isEmpty {
                DropZone(icon: "photo", title: L("img.dropTitle"), subtitle: L("img.dropSub"),
                         targeted: targeted) { c.add(chooseImageFiles()) }
            } else {
                List {
                    ForEach(c.jobs) { job in
                        JobRow(input: job.input, inputSize: job.inputSize, duration: nil, state: job.state,
                               onRetry: { c.retry(job.id) }, onRemove: { c.remove(job.id) })
                    }
                }
            }
        } bottom: {
            HStack {
                Button(L("common.add")) { c.add(chooseImageFiles()) }
                Button(L("common.clearFinished")) { c.clearFinished() }.disabled(!c.hasFinished)
                Button(L("common.clearAll")) { c.clearAll() }.disabled(!c.jobs.contains { !$0.state.isRunning })
                Spacer()
                Text(c.totalsText).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if c.isRunning {
                    Button(L("common.stop")) { c.stop() }
                } else {
                    Button(L("common.convert")) { c.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!c.hasWaiting)
                }
            }
        }
        .fileDrop(targeted: $targeted) { c.add($0) }
    }
}

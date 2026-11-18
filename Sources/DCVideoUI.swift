// Инструмент «Загрузка и конвертация» (раньше — отдельное приложение Download and Convert).
// Раздел «Видео → MP4»: окно, редактор обрезки, полоса времени.
import SwiftUI
import AppKit

struct EditTarget: Identifiable { let id: UUID }

struct VideoView: View {
    @ObservedObject var c = VideoConverter.shared
    @ObservedObject var tm = ToolsManager.shared
    @State private var targeted = false
    @State private var editing: EditTarget?

    var body: some View {
        SectionPage {
            VStack(alignment: .leading, spacing: 9) {
                OptionRow(L("vid.sound")) {
                    Picker("", selection: $c.sound) {
                        ForEach(SoundMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .disabled(!c.format.hasAudio)
                }
                if c.format.hasAudio && c.sound == .only {
                    // режим «Только звук»: форматы и качество — звуковые
                    OptionRow(L("common.format")) {
                        Picker("", selection: $c.audioFormat) {
                            ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    OptionRow("") { HintText(c.audioFormat.hint) }
                    OptionRow(L("common.quality")) {
                        if c.audioFormat.isLossy {
                            Picker("", selection: $c.audioKbps) {
                                ForEach([128, 192, 256, 320], id: \.self) { Text(LF("aud.kbps", String($0))).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        } else {
                            Text(L("aud.lossless")).foregroundColor(.secondary)
                        }
                    }
                } else {
                    OptionRow(L("common.format")) {
                        Picker("", selection: $c.format) {
                            ForEach(VideoFormat.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    OptionRow("") { HintText(c.format.hint) }
                    if c.format.usesCodecChoice {
                        OptionRow(L("vid.codec")) {
                            Picker("", selection: $c.codec) {
                                ForEach(Codec.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        }
                        OptionRow("") { HintText(c.codec.hint) }
                    }
                    OptionRow(L("common.quality")) {
                        Picker("", selection: $c.quality) {
                            ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    OptionRow("") {
                        Toggle(L("vid.limit1080"), isOn: $c.limit1080).disabled(c.format == .gif)
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
                DropZone(icon: "film", title: L("vid.dropTitle"), subtitle: L("vid.dropSub"),
                         targeted: targeted) { c.add(chooseMediaFiles(prompt: L("common.add"))) }
            } else {
                List {
                    ForEach(c.jobs) { job in
                        JobRow(input: job.input, inputSize: job.inputSize, duration: job.duration, state: job.state,
                               edited: job.edit.isActive,
                               trimmedTo: job.duration.map { job.edit.keptDuration($0) },
                               canEdit: tm.tools != nil && !job.state.isRunning,
                               onEdit: { editing = EditTarget(id: job.id) },
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
        .sheet(item: $editing) { target in
            EditorView(jobID: target.id)
        }
    }
}

// MARK: - Обрезка

/// Показывает кадр в выбранный момент (через ffmpeg — работает для любого формата)
final class FrameLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var duration: Double
    private let ffmpeg: URL?
    private let input: URL?
    private var busy = false
    private var queued: Double?

    init(input: URL?, duration: Double?) {
        let tools = ToolsManager.shared.tools
        self.ffmpeg = tools?.ffmpeg
        self.input = input
        self.duration = duration ?? 0
        if (duration ?? 0) <= 0, let t = tools, let input = input {
            DispatchQueue.global(qos: .userInitiated).async {
                let d = MediaInfo.probe(t, input).duration ?? 0
                DispatchQueue.main.async { self.duration = d }
            }
        }
    }

    func request(_ time: Double) {
        if busy { queued = time; return }
        guard let ffmpeg = ffmpeg, let input = input else { return }
        busy = true
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin",
                       "-ss", String(format: "%.3f", max(0, time)), "-i", input.path,
                       "-frames:v", "1", "-vf", "scale=960:-2", "-f", "image2pipe", "-c:v", "png", "-"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        DispatchQueue.global(qos: .userInitiated).async {
            var img: NSImage?
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 0 { img = NSImage(data: data) }
            }
            DispatchQueue.main.async {
                if let img = img { self.image = img }
                self.busy = false
                if let q = self.queued { self.queued = nil; self.request(q) }
            }
        }
    }
}

struct EditorView: View {
    let jobID: UUID
    @Environment(\.dismiss) private var dismiss
    @StateObject private var frames: FrameLoader
    @State private var edit: Edit
    @State private var t: Double = 0
    @State private var cutMark: Double?
    private let title: String

    init(jobID: UUID) {
        self.jobID = jobID
        let job = VideoConverter.shared.jobs.first { $0.id == jobID }
        title = job?.input.lastPathComponent ?? ""
        _edit = State(initialValue: job?.edit ?? Edit())
        _frames = StateObject(wrappedValue: FrameLoader(input: job?.input, duration: job?.duration))
    }

    private var dur: Double { frames.duration }
    private var maxT: Double { max(0, dur - 0.05) }

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline).lineLimit(1).truncationMode(.middle)

            ZStack {
                Color.black
                if let img = frames.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                }
            }
            .frame(minHeight: 280)
            .cornerRadius(8)

            HStack {
                Text(formatTime(t, precise: true)).font(.system(.title3, design: .monospaced))
                Spacer()
                if dur > 0 {
                    Text(LF("ed.remains", formatTime(edit.keptDuration(dur), precise: true), formatTime(dur, precise: true)))
                        .foregroundColor(.secondary)
                } else {
                    Text(L("ed.detecting")).foregroundColor(.secondary)
                }
            }

            Timeline(duration: dur, edit: edit, cutMark: cutMark, t: $t)
                .frame(height: 34)

            HStack(spacing: 8) {
                Button(L("ed.minus1")) { step(-1) }.keyboardShortcut(.leftArrow, modifiers: .shift)
                Button(L("ed.minus01")) { step(-0.1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button(L("ed.plus01")) { step(0.1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button(L("ed.plus1")) { step(1) }.keyboardShortcut(.rightArrow, modifiers: .shift)
                Spacer()
                HintText(L("ed.stepHint"))
            }

            HStack(spacing: 8) {
                Button { setStart() } label: { Label(L("ed.startHere"), systemImage: "arrow.right.to.line") }
                    .keyboardShortcut("i", modifiers: [])
                    .help(L("ed.startHelp"))
                Button { setEnd() } label: { Label(L("ed.endHere"), systemImage: "arrow.left.to.line") }
                    .keyboardShortcut("o", modifiers: [])
                    .help(L("ed.endHelp"))
                Divider().frame(height: 18)
                Button { markCut() } label: {
                    Label(cutMark == nil ? L("ed.cutMarkStart") : L("ed.cutMarkEnd"), systemImage: "scissors")
                }
                .keyboardShortcut("x", modifiers: [])
                .help(L("ed.cutHelp"))
                if cutMark != nil {
                    Button(L("ed.cancelMark")) { cutMark = nil }
                }
                Spacer()
            }
            .disabled(dur <= 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(LF("ed.start", formatTime(edit.start, precise: true)))
                    if edit.start > 0.01 {
                        Button(L("ed.reset")) { edit.start = 0 }.buttonStyle(.link)
                    }
                    Text("·").foregroundColor(.secondary)
                    Text(LF("ed.end", edit.end.map { formatTime($0, precise: true) } ?? L("ed.toEnd")))
                    if edit.end != nil {
                        Button(L("ed.reset")) { edit.end = nil }.buttonStyle(.link)
                    }
                }
                .font(.callout)
                if !edit.cuts.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(edit.cuts) { cut in
                                HStack(spacing: 6) {
                                    Image(systemName: "scissors").foregroundColor(.red)
                                    Button("\(formatTime(cut.from, precise: true)) – \(formatTime(cut.to, precise: true))") {
                                        t = cut.from
                                    }
                                    .buttonStyle(.link)
                                    Button { edit.cuts.removeAll { $0.id == cut.id } } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(L("ed.dontCut"))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 80)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(L("ed.resetAll")) { edit = Edit(); cutMark = nil }
                    .disabled(!edit.isActive && cutMark == nil)
                Spacer()
                Button(L("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("common.done")) {
                    VideoConverter.shared.setEdit(jobID, edit)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 800, height: 700)
        .onChange(of: t) { frames.request($0) }
        .onAppear { frames.request(0) }
    }

    private func step(_ d: Double) { t = min(max(0, t + d), maxT) }

    private func setStart() {
        edit.start = t
        if let e = edit.end, e <= t + 0.1 { edit.end = nil }
    }

    private func setEnd() {
        guard t > edit.start + 0.1 else { NSSound.beep(); return }
        edit.end = t
    }

    private func markCut() {
        if let m = cutMark {
            if abs(t - m) > 0.05 { edit.cuts.append(Cut(from: min(m, t), to: max(m, t))) } else { NSSound.beep() }
            cutMark = nil
        } else {
            cutMark = t
        }
    }
}

/// Полоса времени: синее — останется, красноватое — будет убрано. Тяните мышью.
struct Timeline: View {
    let duration: Double
    let edit: Edit
    let cutMark: Double?
    @Binding var t: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x: (Double) -> CGFloat = { v in duration > 0 ? CGFloat(v / duration) * w : 0 }
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.red.opacity(0.22))
                ForEach(Array(edit.keep(duration).enumerated()), id: \.offset) { _, s in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: max(1, x(s.b) - x(s.a)))
                        .offset(x: x(s.a))
                }
                if let m = cutMark {
                    Rectangle().fill(Color.orange).frame(width: 3).offset(x: x(m) - 1.5)
                }
                Rectangle().fill(Color.primary).frame(width: 2).offset(x: x(t) - 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                guard duration > 0, w > 0 else { return }
                t = min(max(0, Double(v.location.x / w) * duration), max(0, duration - 0.05))
            })
        }
    }
}

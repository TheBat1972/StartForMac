// Окно инструмента «Загрузка и конвертация»: слева разделы, справа содержимое.
// Открывается из меню инструментов «Пуска» и живёт как отдельное окно.
import SwiftUI
import AppKit

enum DCSection: String, CaseIterable, Identifiable {
    case download, audio, video, text, components
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .download: return "arrow.down.circle"
        case .audio: return "waveform"
        case .video: return "film"
        case .text: return "doc.text"
        case .components: return "gearshape"
        }
    }
    var title: String {
        switch self {
        case .download: return L("nav.download")
        case .audio: return L("nav.mp3")
        case .video: return L("nav.video")
        case .text: return L("nav.text")
        case .components: return L("nav.components")
        }
    }
}

struct DCRootView: View {
    @ObservedObject var store: Store
    @AppStorage("dc.section") private var sectionRaw = DCSection.download.rawValue

    private var section: DCSection { DCSection(rawValue: sectionRaw) ?? .download }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(DCSection.allCases.filter { $0 != .components }) { s in
                    DCSidebarItem(icon: s.icon, title: s.title, selected: s == section) { sectionRaw = s.rawValue }
                }
                Spacer()
                DCSidebarItem(icon: DCSection.components.icon, title: DCSection.components.title,
                              selected: section == .components) { sectionRaw = DCSection.components.rawValue }
            }
            .padding(10)
            .frame(width: 210)
            .background(Color(NSColor.windowBackgroundColor))
            Divider()
            VStack(spacing: 0) {
                ToolsBanner()
                Group {
                    switch section {
                    case .download: DownloadView()
                    case .audio: AudioView()
                    case .video: VideoView()
                    case .text: TextView()
                    case .components: DCComponentsView()
                    }
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 660)
        .id(store.language)
    }
}

struct DCSidebarItem: View {
    let icon: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Состояние ffmpeg и yt-dlp: скачать заново или обновить
struct DCComponentsView: View {
    @ObservedObject var tm = ToolsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OptionRow("ffmpeg") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ffmpegStatus).foregroundColor(.secondary).lineLimit(2)
                    if tm.ffmpegOutdated {
                        Text(LF("ff.outdated", tm.ffmpegVersion ?? "—")).font(.caption).foregroundColor(.orange)
                    } else if tm.tools != nil && tm.ffmpegLatest != nil {
                        HintText(L("ff.upToDate"))
                    }
                    // кнопка есть всегда, подпись зависит от того, что нужно сделать
                    Button(tm.tools == nil ? L("ff.download") : (tm.ffmpegOutdated ? L("ff.update") : L("set.redownload"))) {
                        tm.prepare(forceDownload: true)
                    }
                    .disabled(isDownloading || tm.isInUse)
                }
            }
            OptionRow("yt-dlp") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tm.ytDlpPath ?? L("set.notInstalled")).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let v = tm.ytDlpVersion {
                        if tm.ytDlpOutdated {
                            Text(LF("yt.outdated", v, tm.ytDlpLatest ?? "")).font(.caption).foregroundColor(.orange)
                        } else if tm.ytDlpLatest != nil {
                            HintText(LF("yt.upToDate", v))
                        } else {
                            HintText(LF("yt.version", v))
                        }
                    }
                    HStack {
                        Button(tm.ytDlpPath == nil ? L("yt.install") : (tm.ytDlpOutdated ? L("yt.update") : L("yt.redownload"))) {
                            tm.installYtDlp()
                        }
                        .disabled(tm.ytDlpBusy)
                        if let m = tm.ytDlpMessage { HintText(m) }
                    }
                }
            }
            Spacer()
            HintText(L("set.toolsHint"))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var isDownloading: Bool {
        if case .downloading = tm.state { return true }
        return false
    }

    private var ffmpegStatus: String {
        switch tm.state {
        case .ready: return tm.tools?.ffmpeg.deletingLastPathComponent().path ?? ""
        case .checking: return L("set.checking")
        case .downloading(_, let label): return label
        case .failed(let m): return m
        }
    }
}

final class DCWindowController: NSObject, NSWindowDelegate {
    static let shared = DCWindowController()
    private var window: NSWindow?

    func show(store: Store) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 1000, height: 660)
            w.contentView = NSHostingView(rootView: LangRefresh { DCRootView(store: store) })
            w.delegate = self
            if !w.setFrameUsingName("DCWindow") { w.center() }
            w.setFrameAutosaveName("DCWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Загрузка и конвертация")
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        ToolsManager.shared.checkUpdates()
    }

    @objc private func languageChanged() { window?.title = T("Загрузка и конвертация") }

    var isBusy: Bool {
        VideoConverter.shared.isRunning || AudioConverter.shared.isRunning || TextConverter.shared.isRunning || Downloader.shared.running
    }

    /// При выходе из «Пуска» спрашивает, если ещё идёт загрузка или конвертация
    func confirmQuit() -> Bool {
        guard isBusy else { return true }
        let a = NSAlert()
        a.messageText = L("quit.title")
        a.informativeText = L("quit.text")
        a.addButton(withTitle: L("quit.abort"))
        a.addButton(withTitle: L("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        VideoConverter.shared.abortForQuit()
        AudioConverter.shared.abortForQuit()
        TextConverter.shared.abortForQuit()
        Downloader.shared.cancel()
        return true
    }
}

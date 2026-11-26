import SwiftUI
import AppKit
import CoreImage

// MARK: - Состояние общего доступа к папке (веб + FTP)

final class ShareManager: ObservableObject {
    static let shared = ShareManager()

    @Published var folder: String { didSet { save() } }
    @Published var httpPort: Int { didSet { save() } }
    @Published var ftpOn: Bool { didSet { save() } }
    @Published var ftpPort: Int { didSet { save() } }
    @Published var allowUpload: Bool { didSet { save() } }
    @Published var password: String { didSet { if loaded { RemoteKeychain.set("share-server", password) } } }
    @Published private(set) var running = false
    @Published private(set) var error = ""
    @Published private(set) var ip = ""

    private var statusItem: NSStatusItem?
    private let menuHandler = ShareMenuHandler()
    private var http: ShareHTTP?
    private var ftp: ShareFTP?
    private var loaded = false
    private let d = UserDefaults.standard

    private init() {
        folder = d.string(forKey: "share.folder") ?? ""
        let hp = d.integer(forKey: "share.http")
        httpPort = hp > 0 ? hp : 8080
        ftpOn = d.object(forKey: "share.ftpOn") as? Bool ?? false
        let fp = d.integer(forKey: "share.ftp")
        ftpPort = fp > 0 ? fp : 2121
        allowUpload = d.object(forKey: "share.upload") as? Bool ?? true
        password = RemoteKeychain.get("share-server") ?? ""
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        d.set(folder, forKey: "share.folder")
        d.set(httpPort, forKey: "share.http")
        d.set(ftpOn, forKey: "share.ftpOn")
        d.set(ftpPort, forKey: "share.ftp")
        d.set(allowUpload, forKey: "share.upload")
    }

    var httpURL: String { "http://\(hostText):\(httpPort)/" }
    var ftpURL: String { "ftp://\(hostText):\(ftpPort)/" }
    private var hostText: String { ip.isEmpty ? "localhost" : ip }

    /// Включает сервер; ошибку кладёт в `error`
    func start() {
        stopServers()
        error = ""
        guard let root = ShareRoot(folder) else { error = T("Выберите папку"); return }
        guard (1024...65535).contains(httpPort), (1024...65535).contains(ftpPort) else {
            error = T("Порт должен быть от 1024 до 65535"); return
        }
        if ftpOn && ftpPort == httpPort { error = T("Порты веб и FTP должны отличаться"); return }
        guard let hfd = ShareNet.listen(port: httpPort) else { error = Tf("Порт %@ занят", String(httpPort)); return }
        let h = ShareHTTP(fd: hfd, root: root, password: password, readOnly: !allowUpload)
        var f: ShareFTP?
        if ftpOn {
            guard let ffd = ShareNet.listen(port: ftpPort) else {
                close(hfd); error = Tf("Порт %@ занят", String(ftpPort)); return
            }
            f = ShareFTP(fd: ffd, root: root, password: password, readOnly: !allowUpload)
        }
        h.start()
        f?.start()
        http = h
        ftp = f
        if let (a, _) = NetProbe.primaryIPv4() { ip = NetProbe.dotted(a) } else { ip = "" }
        running = true
        d.set(true, forKey: "share.enabled")
        showIcon()
    }

    /// Выключает вручную — после перезапуска «Пуска» сервер остаётся выключенным
    func stop() {
        stopServers()
        d.set(false, forKey: "share.enabled")
    }

    private func stopServers() {
        hideIcon()
        let h = http, f = ftp
        http = nil
        ftp = nil
        running = false
        DispatchQueue.global().async { h?.stop(); f?.stop() }
    }

    // MARK: зелёный значок в строке меню, пока сервер работает

    private func showIcon() {
        if !Thread.isMainThread { DispatchQueue.main.async { self.showIcon() }; return }
        hideIcon()
        guard running else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                it.autosaveName = "StartShareIcon"      // система запоминает место значка в строке меню
        it.isVisible = true
        let name = T("Обмен файлами по сети")
        if let img = StatusIcon.colored("network", .systemGreen, name) ?? StatusIcon.colored("globe", .systemGreen, name) {
            it.button?.image = img
        } else {
            // без значка кнопка была бы пустой и невидимой
            it.button?.attributedTitle = NSAttributedString(string: "●", attributes: [.foregroundColor: NSColor.systemGreen])
        }
        it.button?.toolTip = T("Обмен файлами по сети") + ": " + httpURL
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, _ obj: String? = nil) {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            mi.target = menuHandler
            mi.representedObject = obj
            m.addItem(mi)
        }
        add(httpURL, #selector(ShareMenuHandler.copyText(_:)), httpURL)
        if ftpOn { add(ftpURL, #selector(ShareMenuHandler.copyText(_:)), ftpURL) }
        m.addItem(.separator())
        add(T("Обмен файлами по сети") + "…", #selector(ShareMenuHandler.openWindow))
        add(T("Выключить"), #selector(ShareMenuHandler.turnOff))
        it.menu = m
        statusItem = it
    }

    private func hideIcon() {
        if !Thread.isMainThread { DispatchQueue.main.async { self.hideIcon() }; return }
        if let it = statusItem { NSStatusBar.system.removeStatusItem(it) }
        statusItem = nil
    }

    /// При запуске «Пуска» поднимает сервер, если он был включён
    func restoreOnLaunch() {
        if d.bool(forKey: "share.enabled"), ShareRoot(folder) != nil { start() }
    }
}

/// Цветной значок для строки меню. Шаблонный значок с contentTintColor в строке меню может стать невидимым,
/// поэтому цвет вшивается в само изображение (не шаблон).
enum StatusIcon {
    static func colored(_ symbol: String, _ color: NSColor, _ desc: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: desc) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let img = base.withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img
    }
}

final class ShareMenuHandler: NSObject {
    @objc func copyText(_ sender: NSMenuItem) {
        guard let t = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
    }
    @objc func openWindow() { ShareController.shared.show() }
    @objc func turnOff() { ShareManager.shared.stop() }
}

// MARK: - QR-код

enum QRCode {
    static func image(_ text: String, side: CGFloat) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage else { return nil }
        let k = max(1, floor(side / out.extent.width))
        let big = out.samplingNearest().transformed(by: CGAffineTransform(scaleX: k, y: k))
        let rep = NSCIImageRep(ciImage: big)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - Окно

final class ShareController: NSObject, NSWindowDelegate {
    static let shared = ShareController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 480, height: 560)
            w.contentView = NSHostingView(rootView: LangRefresh { ShareView() })
            w.delegate = self
            if !w.setFrameUsingName("ShareWindow") { w.center() }
            w.setFrameAutosaveName("ShareWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = T("Обмен файлами по сети")
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() { window?.title = T("Обмен файлами по сети") }
}

struct ShareView: View {
    @ObservedObject private var m = ShareManager.shared
    @State private var showPassword = false

    private func portBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<String> {
        Binding(get: { String(get()) }, set: { set(Int($0.filter { $0.isNumber }) ?? 0) })
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = T("Выбрать")
        if p.runModal() == .OK, let u = p.url { m.folder = u.path }
    }

    private func addressRow(_ title: String, _ url: String) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundColor(.secondary).frame(width: 40, alignment: .leading)
            Text(url).font(.system(.body, design: .monospaced)).textSelection(.enabled).lineLimit(1)
            Spacer()
            Button(T("Скопировать")) { copy(url) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Папка по сети: заходите с телефона или другого компьютера через браузер или FTP-клиент"))
                .font(.callout).foregroundColor(.secondary)

            HStack {
                Text(m.folder.isEmpty ? T("Папка не выбрана") : m.folder)
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundColor(m.folder.isEmpty ? .secondary : .primary)
                Spacer()
                Button(T("Выбрать папку…")) { chooseFolder() }.disabled(m.running)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(T("Разрешить загрузку, переименование и удаление файлов"), isOn: $m.allowUpload).disabled(m.running)
                    HStack {
                        Text(T("Пароль (необязательно)"))
                        Group {
                            if showPassword { TextField("", text: $m.password) } else { SecureField("", text: $m.password) }
                        }
                        .frame(maxWidth: 200).disabled(m.running)
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(showPassword ? T("Скрыть пароль") : T("Показать пароль"))
                    }
                    HStack {
                        Text(T("Порт веб"))
                        TextField("", text: portBinding({ m.httpPort }, { m.httpPort = $0 })).frame(width: 70).disabled(m.running)
                        Toggle(T("FTP-сервер"), isOn: $m.ftpOn).disabled(m.running).padding(.leading, 12)
                        TextField("", text: portBinding({ m.ftpPort }, { m.ftpPort = $0 })).frame(width: 70).disabled(m.running || !m.ftpOn)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(m.running ? T("Выключить") : T("Включить")) {
                    if m.running { m.stop() } else { m.start() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!m.running && m.folder.isEmpty)
                if m.running {
                    Label(T("Работает"), systemImage: "checkmark.circle.fill").foregroundColor(.green)
                }
            }

            if !m.error.isEmpty {
                Text(m.error).foregroundColor(.red).font(.callout)
            }

            if m.running {
                HStack(alignment: .top, spacing: 16) {
                    if let q = QRCode.image(m.httpURL, side: 180) {
                        Image(nsImage: q).interpolation(.none).resizable().frame(width: 180, height: 180)
                            .padding(8).background(Color.white).cornerRadius(8)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("Наведите камеру телефона на QR-код или введите адрес")).font(.callout).foregroundColor(.secondary)
                        addressRow("Web", m.httpURL)
                        if m.ftpOn { addressRow("FTP", m.ftpURL) }
                    }
                }
                Text(m.password.isEmpty
                     ? T("Пароля нет: любой в вашей сети откроет эту папку. Не включайте без пароля в чужих сетях.")
                     : T("Пароль: любое имя пользователя и ваш пароль. Внимание: соединение не шифруется."))
                    .font(.footnote).foregroundColor(.secondary)
                Text(T("Сервер работает, пока запущен «Пуск», и сам включается после его перезапуска. Выключенный вручную остаётся выключенным."))
                    .font(.footnote).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

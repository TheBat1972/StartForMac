import SwiftUI
import AppKit

// MARK: - «Файл менеджер»: панель с FTP, FTPS, SFTP или HTTP-сервером

struct RemoteLoc {
    var server: RemoteServer
    var password: String
    var path: String            // папка на сервере, всегда с «/» в конце
}

final class RemoteXfer {
    var all: TPDecision?
    var cancelled = false
    var failed: [String] = []
    var done = 0
    private var cache: [String: [RemoteEntry]] = [:]

    func children(_ c: RemoteClient, _ dir: String) throws -> [RemoteEntry] {
        if let l = cache[dir] { return l }
        let l = try c.list(dir)
        cache[dir] = l
        return l
    }
    func setEmpty(_ dir: String) { cache[dir] = [] }
}

extension TPPane {
    var offDisk: Bool { mtp != nil || remote != nil }

    func remoteDisplay(_ l: RemoteLoc) -> String {
        let s = l.server
        let port = s.port == s.proto.defaultPort ? "" : ":\(s.port)"
        return s.proto.rawValue + "://" + s.host + port + l.path
    }

    func enterRemote(_ s: RemoteServer, password: String) {
        var p = s.path.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { p = s.proto == .sftp ? "/~/" : "/" }
        mtp = nil
        remote = RemoteLoc(server: s, password: password, path: RemoteClient.dirPath(p))
        cursor = 0
        marked = []
        anchor = nil
        updatePath()
        reload(select: nil, keepCurrent: false)
    }

    func enterRemoteDir(_ it: TPItem) {
        guard var l = remote, it.isDir else { return }
        l.path = l.path + it.name + "/"
        remote = l
        cursor = 0
        marked = []
        anchor = nil
        updatePath()
        reload(select: nil, keepCurrent: false)
    }

    func goUpRemote() {
        guard var l = remote else { return }
        if l.path == "/" {
            let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            navigate(to: dl)
            return
        }
        let left = l.path.split(separator: "/").last.map(String.init)
        l.path = RemoteClient.parentPath(l.path)
        remote = l
        marked = []
        anchor = nil
        updatePath()
        reload(select: left, keepCurrent: false)
    }

    func reloadRemote(select name: String?, keepCurrent: Bool) {
        guard let loc = remote else { return }
        var keep = name
        if keep == nil, keepCurrent, let c = current { keep = c.name }
        gen += 1
        let g = gen
        let sk = sortKey, asc = ascending, showH = showHidden
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var arr: [TPItem] = []
            var err: String?
            var trust: RemoteError?
            do {
                for e in try RemoteClient(loc.server, password: loc.password).list(loc.path) where showH || !e.name.hasPrefix(".") {
                    arr.append(TPItem(url: URL(fileURLWithPath: loc.path + e.name), name: e.name, isDir: e.isDir, isPackage: false,
                                      size: e.size, modified: e.modified, remotePath: loc.path + e.name, remoteLink: e.isLink))
                }
            } catch let e as RemoteError {
                if e.needsTrust { trust = e }
                err = e.localizedDescription
            } catch { err = error.localizedDescription }
            TPPane.sortItems(&arr, sk, asc)
            arr.insert(TPItem(url: URL(fileURLWithPath: "/remote/up"), name: "..", isDir: true, isPackage: false,
                              size: 0, modified: nil, isParent: true), at: 0)
            DispatchQueue.main.async {
                guard let self = self, g == self.gen else { return }
                self.items = arr
                self.free = 0
                self.error = err
                self.marked = self.marked.intersection(Set(arr.map { $0.id }))
                if let k = keep, let i = arr.firstIndex(where: { $0.name == k }) { self.cursor = i }
                else { self.cursor = keepCurrent ? max(0, min(self.cursor, arr.count - 1)) : 0 }
                if let t = trust { TPState.shared.askTrust(self, t) }
            }
        }
    }
}

extension TPState {
    // MARK: подключение

    static func askPassword(_ title: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: T("Подключиться"))
        a.addButton(withTitle: T("Отмена"))
        a.window.initialFirstResponder = f
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
    }

    func connectRemote(_ pane: TPPane, _ s: RemoteServer, password: String? = nil, index: Int) {
        active = index
        var pw = password ?? RemoteKeychain.get(s.id) ?? ""
        if pw.isEmpty && !s.user.isEmpty && s.keyPath.isEmpty {
            guard let asked = TPState.askPassword(Tf("Пароль для %@", s.user + "@" + s.host)) else { return }
            pw = asked
        }
        pane.enterRemote(s, password: pw)
    }

    func askTrust(_ pane: TPPane, _ e: RemoteError) {
        guard var l = pane.remote, !l.server.insecure else { return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = T("Не удалось проверить подлинность сервера")
        a.informativeText = (e.proto == .sftp ? T("Ключ этого сервера ещё не известен вашему Mac.")
                                              : T("Сертификат сервера не прошёл проверку (самоподписанный или просрочен)."))
            + " " + T("Подключайтесь только к серверу, которому доверяете.")
        a.addButton(withTitle: T("Доверять и подключиться"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        l.server.insecure = true
        pane.remote = l
        var all = RemoteStore.load()
        if let i = all.firstIndex(where: { $0.id == l.server.id }) { all[i].insecure = true; RemoteStore.save(all) }
        pane.reload(select: nil, keepCurrent: false)
    }

    /// Строка в поле пути: адрес сервера (ftp://, ftps://, sftp://, http://, https://) или путь на уже открытом сервере
    func handleAddress(_ text: String, pane: TPPane, index: Int) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: "://") {
            let scheme = t[..<r.lowerBound].lowercased()
            guard let proto = RemoteProto(rawValue: scheme), let c = URLComponents(string: t),
                  let host = c.host, !host.isEmpty else { return false }
            let port = c.port ?? proto.defaultPort
            let path = RemoteClient.dirPath(c.path.isEmpty ? "/" : c.path)
            if var l = pane.remote, l.server.proto == proto, l.server.host == host, l.server.port == port {
                l.path = path                      // тот же сервер: только меняем папку
                pane.remote = l
                pane.updatePath()
                pane.reload(select: nil, keepCurrent: false)
                return true
            }
            var s = RemoteServer()
            s.proto = proto
            s.host = host
            s.port = port
            s.user = c.user ?? ""
            s.path = path
            s.name = host
            let pw = c.password ?? ""
            connectRemote(pane, s, password: pw.isEmpty ? nil : pw, index: index)
            return true
        }
        if var l = pane.remote {
            l.path = RemoteClient.dirPath(t.isEmpty ? "/" : t)
            pane.remote = l
            pane.updatePath()
            pane.reload(select: nil, keepCurrent: false)
            return true
        }
        return false
    }

    func showRemoteManager(pane: TPPane, index: Int) {
        guard let parent = window else { return }
        let model = RemoteManagerModel()
        var sheet: NSWindow!
        let view = RemoteManagerView(model: model, onClose: { parent.endSheet(sheet) }, onConnect: { [weak self] s, pw in
            parent.endSheet(sheet)
            self?.connectRemote(pane, s, password: pw, index: index)
        })
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentView = NSHostingView(rootView: view)
        parent.beginSheet(sheet, completionHandler: nil)
    }

    func remoteNote() {
        status = T("С сервером доступны просмотр, копирование, переименование, удаление и новая папка")
    }

    private func needWritable(_ loc: RemoteLoc) -> Bool {
        if loc.server.proto.writable { return true }
        TPState.showErrors([T("HTTP-серверы доступны только для чтения")])
        return false
    }

    // MARK: копирование

    func remoteCopy(_ sp: TPPane, _ t: [TPItem]) {
        let dp = dst
        if (sp.remote != nil && dp.remote != nil) || sp.mtp != nil || dp.mtp != nil {
            TPState.showErrors([T("Между сервером и телефоном или между двумя серверами копировать нельзя — копируйте через папку на этом Mac")])
            return
        }
        if let d = dp.remote, !needWritable(d) { return }
        let a = NSAlert()
        a.messageText = Tf("Копировать: %@", summary(t))
        a.informativeText = T("Куда:") + " " + dp.displayPath
        a.addButton(withTitle: T("Копировать"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        sp.marked = []
        if let d = dp.remote { remoteUpload(t.map { $0.url }, to: d, cleanTemp: false) }
        else if let s = sp.remote { remoteDownload(t, from: s, to: dp.dir) }
    }

    private func remoteDecide(_ name: String, _ ctx: RemoteXfer, toServer: Bool) -> TPDecision {
        if let a = ctx.all { return a }
        var res: (TPDecision, Bool) = (.cancel, false)
        DispatchQueue.main.sync { res = TPState.askConflict(name, multiple: true, remote: toServer) }
        if res.1 { ctx.all = res.0 }
        if res.0 == .cancel { ctx.cancelled = true }
        return res.0
    }

    func remoteUpload(_ urls: [URL], to loc: RemoteLoc, cleanTemp: Bool) {
        guard needWritable(loc) else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let client = RemoteClient(loc.server, password: loc.password)
            let ctx = RemoteXfer()
            for (n, u) in urls.enumerated() {
                if ctx.cancelled { break }
                DispatchQueue.main.async { self.status = Tf("Обработано %@ из %@", "\(n)", "\(urls.count)") + " — " + u.lastPathComponent }
                _ = self.remoteUploadItem(client, u, dir: loc.path, ctx: ctx)
                if cleanTemp {
                    let par = u.deletingLastPathComponent()
                    if par.lastPathComponent.hasPrefix("dc-drop-") { try? FileManager.default.removeItem(at: par) }
                }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.status = Tf("Скопировано: %@", "\(ctx.done)")
                self.reloadAll()
                TPState.showErrors(ctx.failed)
            }
        }
    }

    private func remoteUploadItem(_ c: RemoteClient, _ url: URL, dir: String, ctx: RemoteXfer) -> Bool {
        let fm = FileManager.default
        let name = url.lastPathComponent
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        do {
            let existing = try ctx.children(c, dir).first { $0.name == name }
            if isDir.boolValue {
                let sub = dir + name + "/"
                if let e = existing, !e.isDir {
                    guard remoteDecide(name, ctx, toServer: true) == .replace else { return false }
                    try c.removeFile(dir + name)
                    try c.mkdir(sub)
                    ctx.setEmpty(sub)
                } else if existing == nil {
                    try c.mkdir(sub)
                    ctx.setEmpty(sub)
                }
                var ok = true
                let kids = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for k in kids {
                    if ctx.cancelled { return false }
                    if !remoteUploadItem(c, k, dir: sub, ctx: ctx) { ok = false }
                }
                return ok
            } else {
                if let e = existing {
                    guard remoteDecide(name, ctx, toServer: true) == .replace else { return false }
                    if e.isDir && !e.isLink { try c.removeTree(dir + name + "/") }
                }
                try c.upload(url, toDir: dir, name: name)
                ctx.done += 1
                return true
            }
        } catch {
            ctx.failed.append(name + ": " + error.localizedDescription)
            return false
        }
    }

    func remoteDownload(_ items: [TPItem], from loc: RemoteLoc, to dir: URL) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let client = RemoteClient(loc.server, password: loc.password)
            let ctx = RemoteXfer()
            for (n, it) in items.enumerated() {
                if ctx.cancelled { break }
                DispatchQueue.main.async { self.status = Tf("Обработано %@ из %@", "\(n)", "\(items.count)") + " — " + it.name }
                let e = RemoteEntry(name: it.name, isDir: it.isDir, isLink: it.remoteLink, size: it.size, modified: it.modified)
                _ = self.remoteDownloadItem(client, e, remoteDir: loc.path, to: dir, ctx: ctx)
            }
            DispatchQueue.main.async {
                self.busy = false
                self.status = Tf("Скопировано: %@", "\(ctx.done)")
                self.reloadAll()
                TPState.showErrors(ctx.failed)
            }
        }
    }

    private func remoteDownloadItem(_ c: RemoteClient, _ e: RemoteEntry, remoteDir: String, to dir: URL, ctx: RemoteXfer) -> Bool {
        let fm = FileManager.default
        let safe = e.name.replacingOccurrences(of: "/", with: "_")
        let target = dir.appendingPathComponent(safe)
        do {
            if e.isDir {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
                    guard remoteDecide(safe, ctx, toServer: false) == .replace else { return false }
                    try fm.trashItem(at: target, resultingItemURL: nil)
                }
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                let sub = remoteDir + e.name + "/"
                var ok = true
                for k in try c.list(sub) {
                    if ctx.cancelled { return false }
                    if !remoteDownloadItem(c, k, remoteDir: sub, to: target, ctx: ctx) { ok = false }
                }
                return ok
            } else {
                if fm.fileExists(atPath: target.path) {
                    guard remoteDecide(safe, ctx, toServer: false) == .replace else { return false }
                    try fm.trashItem(at: target, resultingItemURL: nil)
                }
                try c.download(remoteDir + e.name, to: target)
                ctx.done += 1
                return true
            }
        } catch {
            ctx.failed.append(safe + ": " + error.localizedDescription)
            return false
        }
    }

    // MARK: удаление, переименование, новая папка

    func remoteDelete(_ p: TPPane, _ t: [TPItem]) {
        guard let loc = p.remote, needWritable(loc) else { return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = Tf("Удалить с сервера навсегда: %@?", summary(t))
        a.informativeText = T("Файлы не попадут в Корзину.")
        a.addButton(withTitle: T("Удалить"))
        a.addButton(withTitle: T("Отмена"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        p.marked = []
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let client = RemoteClient(loc.server, password: loc.password)
            var done = 0
            var failed: [String] = []
            for it in t {
                do {
                    if it.isDir && !it.remoteLink { try client.removeTree(loc.path + it.name + "/") }
                    else { try client.removeFile(loc.path + it.name) }
                    done += 1
                } catch { failed.append(it.name + ": " + error.localizedDescription) }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                self.status = Tf("Удалено: %@", "\(done)")
                self.reloadAll()
                TPState.showErrors(failed)
            }
        }
    }

    func remoteRename(_ p: TPPane, _ t: [TPItem]) {
        guard let loc = p.remote, needWritable(loc) else { return }
        guard t.count == 1 else { TPState.showErrors([T("На сервере переименовывать можно по одному файлу")]); return }
        let it = t[0]
        guard let nn = TPState.prompt(title: T("Переименовать"), info: T("Новое имя:"), value: it.name,
                                      ok: T("Переименовать"), selectBase: !it.isDir) else { return }
        let name = nn.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != it.name else { return }
        if name.contains("/") { TPState.showErrors([T("Недопустимое имя")]); return }
        let client = RemoteClient(loc.server, password: loc.password)
        mtpAsync({ try client.rename(loc.path + it.name, to: loc.path + name) }) {
            self.status = Tf("Переименовано: %@", "1")
            p.reload(select: name)
        }
    }

    func remoteNewFolder(_ p: TPPane) {
        guard let loc = p.remote, needWritable(loc) else { return }
        guard let n = TPState.prompt(title: T("Новая папка"), info: T("Имя папки:"), value: T("Новая папка"),
                                     ok: T("Создать")) else { return }
        let name = n.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }
        let client = RemoteClient(loc.server, password: loc.password)
        mtpAsync({ try client.mkdir(loc.path + name + "/") }) {
            p.reload(select: name)
        }
    }

    // MARK: открыть и посмотреть файл с сервера (скачивается во временную папку)

    func remoteFetchTemp(_ loc: RemoteLoc, _ it: TPItem, done: @escaping (URL) -> Void) {
        busy = true
        status = Tf("Скачиваю: %@", it.name)
        let client = RemoteClient(loc.server, password: loc.password)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("start-remote-" + UUID().uuidString, isDirectory: true)
            var err: Error?
            var out: URL?
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let f = dir.appendingPathComponent(it.name.replacingOccurrences(of: "/", with: "_"))
                try client.download(loc.path + it.name, to: f)
                out = f
            } catch { err = error }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                self.status = ""
                if let e = err { TPState.showErrors([e.localizedDescription]) } else if let o = out { done(o) }
            }
        }
    }
}

// MARK: - Окно «Серверы»

final class RemoteManagerModel: ObservableObject {
    @Published var servers: [RemoteServer] = RemoteStore.load()
    @Published var selected: String?
    @Published var draft = RemoteServer()
    @Published var password = ""
    @Published var message = ""

    init() {
        if let f = servers.first { select(f) } else { startNew() }
    }

    func select(_ s: RemoteServer) {
        selected = s.id
        draft = s
        password = RemoteKeychain.get(s.id) ?? ""
        message = ""
    }

    func startNew() {
        selected = nil
        draft = RemoteServer()
        password = ""
        message = ""
    }

    /// Сохраняет черновик в список; возвращает готовый сервер или nil, если адрес не заполнен
    @discardableResult
    func save() -> RemoteServer? {
        var s = draft
        s.host = s.host.trimmingCharacters(in: .whitespaces)
        guard !s.host.isEmpty else { message = T("Укажите адрес сервера"); return nil }
        if s.name.trimmingCharacters(in: .whitespaces).isEmpty { s.name = s.host }
        if s.port <= 0 || s.port > 65535 { s.port = s.proto.defaultPort }
        if let i = servers.firstIndex(where: { $0.id == s.id }) { servers[i] = s } else { servers.append(s) }
        RemoteStore.save(servers)
        RemoteKeychain.set(s.id, password)
        draft = s
        selected = s.id
        message = T("Сохранено")
        return s
    }

    func remove() {
        guard let id = selected else { return }
        servers.removeAll { $0.id == id }
        RemoteStore.save(servers)
        RemoteKeychain.delete(id)
        if let f = servers.first { select(f) } else { startNew() }
    }

    func chooseKey() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.showsHiddenFiles = true
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if p.runModal() == .OK, let u = p.url { draft.keyPath = u.path }
    }
}

struct RemoteManagerView: View {
    @ObservedObject var model: RemoteManagerModel
    @State private var showPassword = false
    let onClose: () -> Void
    let onConnect: (RemoteServer, String) -> Void

    private var protoBinding: Binding<RemoteProto> {
        Binding(get: { model.draft.proto }, set: { n in
            let old = model.draft.proto
            if model.draft.port == old.defaultPort { model.draft.port = n.defaultPort }
            model.draft.proto = n
        })
    }

    private func row(_ title: String, _ content: some View) -> some View {
        HStack(alignment: .center) {
            Text(title).frame(width: 130, alignment: .trailing).foregroundColor(.secondary)
            content
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.servers) { s in
                                HStack {
                                    Image(systemName: "network").foregroundColor(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.name).lineLimit(1)
                                        Text(s.proto.title + " · " + s.host).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .background(model.selected == s.id ? Color.accentColor.opacity(0.2) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { model.select(s) }
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Button(T("Новый")) { model.startNew() }
                        Spacer()
                        Button(T("Удалить")) { model.remove() }.disabled(model.selected == nil)
                    }
                    .padding(8)
                }
                .frame(width: 210)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    row(T("Название"), TextField("", text: $model.draft.name).textFieldStyle(.roundedBorder))
                    row(T("Протокол"), Picker("", selection: protoBinding) {
                        ForEach(RemoteProto.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden())
                    row(T("Адрес"), TextField("example.com", text: $model.draft.host).textFieldStyle(.roundedBorder))
                    row(T("Порт"), TextField("", value: $model.draft.port, formatter: NumberFormatter()).textFieldStyle(.roundedBorder).frame(width: 90))
                    row(T("Пользователь"), TextField(model.draft.proto.isHTTP ? "" : T("пусто — анонимно"), text: $model.draft.user).textFieldStyle(.roundedBorder))
                    row(T("Пароль"), HStack(spacing: 6) {
                        Group {
                            if showPassword { TextField("", text: $model.password) } else { SecureField("", text: $model.password) }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                            .buttonStyle(.borderless)
                            .help(showPassword ? T("Скрыть пароль") : T("Показать пароль"))
                    })
                    row(T("Папка"), TextField("/", text: $model.draft.path).textFieldStyle(.roundedBorder))
                    if model.draft.proto == .sftp {
                        row(T("Файл ключа"), HStack {
                            TextField(T("не нужен, если вход по паролю"), text: $model.draft.keyPath).textFieldStyle(.roundedBorder)
                            Button(T("Выбрать…")) { model.chooseKey() }
                        })
                    }
                    if model.draft.insecure {
                        Toggle(T("Доверять ключу или сертификату этого сервера"), isOn: $model.draft.insecure)
                            .padding(.leading, 138)
                    }
                    Text(model.draft.proto.isHTTP
                         ? T("HTTP-серверы открываются как папки. Загрузка, удаление и новая папка работают, если сервер принимает PUT, DELETE и MKCOL (WebDAV или «Обмен файлами» «Пуска»).")
                         : T("Пароль хранится в связке ключей. Для SFTP можно войти и по ключу."))
                        .font(.caption).foregroundColor(.secondary).padding(.leading, 138)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
            Divider()
            HStack {
                Text(model.message).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(T("Закрыть")) { onClose() }
                Button(T("Сохранить")) { model.save() }
                Button(T("Подключиться")) {
                    if let s = model.save() { onConnect(s, model.password) }
                }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 700, height: 440)
    }
}

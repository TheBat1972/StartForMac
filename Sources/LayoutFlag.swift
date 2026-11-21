import Cocoa
import Carbon

// MARK: - Флаг раскладки на экране (встроенный LangFlag)
//
// Маленькая плавающая плашка с флагом текущей раскладки поверх всех окон. Клик — следующая раскладка,
// перетаскивание — двигает плашку, правая кнопка — размер и возврат в угол экрана. Разрешений не требует.
// Включается в настройках (по умолчанию выключено).

extension Notification.Name {
    static let layoutFlagChanged = Notification.Name("ru.local.StartMenu.layoutFlagChanged")
}

/// Описание раскладки клавиатуры
struct KbLayout {
    let id: String      // com.apple.keylayout.Russian
    let name: String
    let lang: String    // ru
}

enum Kb {
    static func string(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let p = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }

    static func lang(_ src: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return "" }
        let arr = Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as? [String]
        return arr?.first ?? ""
    }

    static func layout(of src: TISInputSource) -> KbLayout {
        let id = string(src, kTISPropertyInputSourceID) ?? ""
        return KbLayout(id: id, name: string(src, kTISPropertyLocalizedName) ?? id, lang: lang(src))
    }

    static func current() -> KbLayout {
        layout(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    /// Раскладки, которые можно выбрать в системе
    static func selectable() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    static func selectNext() {
        let list = selectable()
        guard list.count > 1 else { return }
        let cur = current().id
        let idx = list.firstIndex { string($0, kTISPropertyInputSourceID) == cur } ?? -1
        select(list[(idx + 1) % list.count])
    }

    /// Выбирает раскладку и проверяет, что система её приняла: macOS иногда «теряет» переключение,
    /// особенно сразу после перехода в поле ввода. Если текущая раскладка не сменилась — повторяем (до 3 раз).
    static func select(_ target: TISInputSource, attempt: Int = 0) {
        TISSelectInputSource(target)
        guard attempt < 3 else { return }
        let want = string(target, kTISPropertyInputSourceID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if current().id != want { select(target, attempt: attempt + 1) }
            LayoutFlag.shared.syncNow()                 // флаги обновляются сразу после проверки
        }
    }

    /// Флаг по ID раскладки (точнее) или по коду языка
    static func flag(for l: KbLayout) -> String {
        let id = l.id.lowercased()
        if id.contains("british") { return "🇬🇧" }
        if id.contains("australian") { return "🇦🇺" }
        if id.contains("canadian") { return "🇨🇦" }
        if id.contains("irish") { return "🇮🇪" }
        if id.contains("austrian") { return "🇦🇹" }
        if id.contains("swiss") { return "🇨🇭" }
        if id.contains("brazil") || (id.contains("portuguese") && l.lang == "pt") { return "🇧🇷" }
        let map: [String: String] = [
            "en": "🇺🇸", "ru": "🇷🇺", "uk": "🇺🇦", "be": "🇧🇾", "kk": "🇰🇿",
            "de": "🇩🇪", "fr": "🇫🇷", "es": "🇪🇸", "it": "🇮🇹", "pt": "🇵🇹",
            "pl": "🇵🇱", "cs": "🇨🇿", "sk": "🇸🇰", "tr": "🇹🇷", "nl": "🇳🇱",
            "sv": "🇸🇪", "no": "🇳🇴", "nb": "🇳🇴", "da": "🇩🇰", "fi": "🇫🇮",
            "el": "🇬🇷", "he": "🇮🇱", "ar": "🇸🇦", "hy": "🇦🇲", "ka": "🇬🇪",
            "az": "🇦🇿", "uz": "🇺🇿", "ja": "🇯🇵", "ko": "🇰🇷", "zh": "🇨🇳",
            "hi": "🇮🇳", "th": "🇹🇭", "vi": "🇻🇳", "hu": "🇭🇺", "ro": "🇷🇴",
            "bg": "🇧🇬", "sr": "🇷🇸", "hr": "🇭🇷", "lt": "🇱🇹", "lv": "🇱🇻",
            "et": "🇪🇪", "fa": "🇮🇷"
        ]
        let code = String(l.lang.split(separator: "-").first ?? "").lowercased()
        return map[code] ?? "⌨️"
    }
}

final class LFFlagView: NSView {
    var text: String = "🇺🇸" { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    private var cache: [String: NSImage] = [:]
    private var downPoint = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragged = false

    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        downPoint = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - downPoint.x, dy = p.y - downPoint.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let m = menuProvider?() else { return }
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }

    /// Рендерит эмодзи крупно и обрезает прозрачные поля, чтобы флаг занимал весь кадр
    func flagImage(_ s: String) -> NSImage {
        if let c = cache[s] { return c }
        let attr = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 256)])
        let sz = attr.size()
        let w = Int(ceil(sz.width)) + 16, h = Int(ceil(sz.height)) + 16
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        attr.draw(at: NSPoint(x: 8, y: 8))
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        var minX = w, minY = h, maxX = -1, maxY = -1
        if let data = rep.bitmapData {
            let bpr = rep.bytesPerRow
            for y in 0..<h {
                for x in 0..<w where data[y * bpr + x * 4 + 3] > 12 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        var image = NSImage(size: NSSize(width: w, height: h))
        image.addRepresentation(rep)
        if maxX >= minX, maxY >= minY, let cg = rep.cgImage,
           let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) {
            image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        }
        cache[s] = image
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        flagImage(text).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0,
                             respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}

final class LayoutFlag: NSObject {
    static let shared = LayoutFlag()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "layoutFlag.enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "layoutFlag.enabled") }
    }
    /// Флажок в строке меню macOS (рядом с часами), по умолчанию выключен
    static var statusEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "layoutFlag.status") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "layoutFlag.status") }
    }
    static var scale: CGFloat {
        get { let v = UserDefaults.standard.double(forKey: "layoutFlag.scale"); return v == 0 ? 1.5 : CGFloat(v) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "layoutFlag.scale") }
    }

    private let baseWidth: CGFloat = 38, baseHeight: CGFloat = 24.7
    private var panel: NSPanel?
    private let view = LFFlagView()
    private var observer: NSObjectProtocol?
    private var statusItem: NSStatusItem?

    func setEnabled(_ on: Bool) { on ? show() : hide() }

    // MARK: флажок в строке меню

    func setStatusEnabled(_ on: Bool) {
        if on {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(statusClicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                statusItem = item
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        updateObserver()
        refresh()
    }

    private func updateStatusImage() {
        guard let button = statusItem?.button else { return }
        let src = view.flagImage(view.text)
        let h: CGFloat = 13
        let ratio = src.size.height > 0 ? src.size.width / src.size.height : 1.4
        let img = (src.copy() as? NSImage) ?? src
        img.size = NSSize(width: h * ratio, height: h)
        img.isTemplate = false
        button.image = img
    }

    /// Левый клик — следующая раскладка, правый (или ⌃-клик) — меню
    @objc private func statusClicked(_ sender: Any?) {
        let e = NSApp.currentEvent
        let wantsMenu = e?.type == .rightMouseUp || (e?.modifierFlags.contains(.control) ?? false)
        if wantsMenu && LayoutSwitcher.enabled { return }       // пока включён переключатель раскладки, флажок убрать нельзя
        guard wantsMenu, let item = statusItem else { Kb.selectNext(); return }
        let m = NSMenu()
        let off = NSMenuItem(title: T("Убрать флажок из строки меню"), action: #selector(menuHideStatus), keyEquivalent: "")
        off.target = self
        m.addItem(off)
        item.menu = m
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func menuHideStatus() {
        LayoutFlag.statusEnabled = false
        setStatusEnabled(false)
        NotificationCenter.default.post(name: .layoutFlagChanged, object: nil)
    }

    /// Слушаем смену раскладки, пока включён хотя бы один из флажков
    private func updateObserver() {
        if LayoutFlag.enabled || LayoutFlag.statusEnabled {
            if observer == nil {
                observer = DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                    object: nil, queue: .main) { [weak self] _ in
                    // система обновляет «текущую» раскладку чуть позже уведомления
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.refresh() }
                }
            }
        } else if let o = observer {
            DistributedNotificationCenter.default().removeObserver(o)
            observer = nil
        }
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: baseWidth, height: baseHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .screenSaver
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = false
            p.contentView = view
            view.onClick = { Kb.selectNext() }
            view.menuProvider = { [weak self] in self?.buildMenu() ?? NSMenu() }
            panel = p
            applyScale()
            restorePosition()
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                self?.savePosition()
            }
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil, queue: .main) { [weak self] _ in self?.ensureOnScreen() }
        }
        updateObserver()
        refresh()
        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        updateObserver()
    }

    /// Сразу сверить флаги с системой (после проверки переключения), не дожидаясь уведомления macOS
    func syncNow() {
        if view.text != Kb.flag(for: Kb.current()) || statusItem != nil { refresh() }
    }

    private func refresh() {
        view.text = Kb.flag(for: Kb.current())
        updateStatusImage()
    }

    // MARK: размер и позиция

    func setScale(_ s: CGFloat) {
        LayoutFlag.scale = s
        applyScale()
        savePosition()
    }

    private func applyScale() {
        guard let p = panel else { return }
        let sc = LayoutFlag.scale
        var f = p.frame
        let old = f
        f.size = NSSize(width: baseWidth * sc, height: baseHeight * sc)
        f.origin.y = old.maxY - f.size.height
        p.setFrame(f, display: true)
    }

    private func savePosition() {
        guard let p = panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "layoutFlag.origin")
    }

    private func restorePosition() {
        if let s = UserDefaults.standard.string(forKey: "layoutFlag.origin") {
            panel?.setFrameOrigin(NSPointFromString(s))
            ensureOnScreen()
        } else {
            resetPosition()
        }
    }

    func resetPosition() {
        guard let p = panel, let vf = NSScreen.main?.visibleFrame else { return }
        p.setFrameOrigin(NSPoint(x: vf.maxX - p.frame.width - 20, y: vf.minY + 20))
        savePosition()
    }

    private func ensureOnScreen() {
        guard let p = panel else { return }
        if !NSScreen.screens.contains(where: { $0.frame.intersects(p.frame) }) { resetPosition() }
    }

    // MARK: меню

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        let sizeItem = NSMenuItem(title: T("Размер флага"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let sizes: [(String, Double)] = [(T("Крошечный"), 0.75), (T("Маленький"), 1.0), (T("Обычный"), 1.5),
                                         (T("Большой"), 2.0), (T("Очень большой"), 3.0)]
        for (title, value) in sizes {
            let it = NSMenuItem(title: title, action: #selector(menuSize(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = value
            it.state = abs(CGFloat(value) - LayoutFlag.scale) < 0.01 ? .on : .off
            sub.addItem(it)
        }
        sizeItem.submenu = sub
        m.addItem(sizeItem)
        let reset = NSMenuItem(title: T("Вернуть в угол экрана"), action: #selector(menuReset), keyEquivalent: "")
        reset.target = self
        m.addItem(reset)
        m.addItem(.separator())
        let off = NSMenuItem(title: T("Скрыть флаг"), action: #selector(menuHide), keyEquivalent: "")
        off.target = self
        m.addItem(off)
        return m
    }

    @objc private func menuSize(_ s: NSMenuItem) {
        if let v = s.representedObject as? Double { setScale(CGFloat(v)) }
    }
    @objc private func menuReset() { resetPosition() }
    @objc private func menuHide() {
        LayoutFlag.enabled = false
        hide()
        NotificationCenter.default.post(name: .layoutFlagChanged, object: nil)
    }
}

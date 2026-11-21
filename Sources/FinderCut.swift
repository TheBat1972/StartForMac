import Cocoa

// MARK: - ⌘X в Finder («вырезать» файлы)
//
// В Finder нет «вырезать»: ⌘X ничего не делает. Здесь ⌘X работает как «копировать» и запоминает, что файлы вырезаны;
// следующая вставка ⌘V в Finder превращается в «Переместить объект сюда» (⌘⌥V). Любой другой ⌘C после этого
// отменяет вырезание. В полях ввода (переименование, поиск) ⌘X и ⌘V остаются обычными.
// Для перехвата клавиш нужен доступ «Управление устройством и доступ к данным» (в ранних версиях macOS: «Универсальный доступ»).

final class FinderCut {
    static let shared = FinderCut()
    private static let marker: Int64 = 0x53464D43          // метка своих событий, чтобы не перехватывать их же

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "finder.cut") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "finder.cut") }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending = false
    private var cutCount = 0

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in FinderCut.shared.handle(type, event) },
                                        userInfo: nil) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        pending = false
    }

    private func finderIsActive() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Курсор в текстовом поле (переименование, поиск): тогда ⌘X / ⌘V обычные
    private func editingText() -> Bool {
        let sys = AXUIElementCreateSystemWide()
        guard let el = WindowFinder.attr(sys, kAXFocusedUIElementAttribute) else { return false }
        let role = WindowFinder.attr(el as! AXUIElement, kAXRoleAttribute) as? String
        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole || role == "AXSearchField"
    }

    private func post(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: FinderCut.marker)
            e.post(tap: .cghidEventTap)
        }
    }

    // MARK: Подсказка «Вырезано»

    private var toast: NSPanel?

    /// Файлы вырезаны и ещё не вставлены (используется и окном нового рабочего стола)
    var cutPending: Bool { pending && (cutCount == 0 || NSPasteboard.general.changeCount == cutCount) }
    /// Пометить текущее содержимое буфера обмена как вырезанное
    func markCut() { pending = true; cutCount = NSPasteboard.general.changeCount }
    func cancelCut() { pending = false }

    func showToast() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                    options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        let title = urls.count == 1 ? Tf("Вырезано: «%@»", urls[0].lastPathComponent)
                                    : Tf("Вырезано файлов: %@", "\(urls.count)")
        let view = CutToastView(title: title, subtitle: T("Вставьте ⌘V, чтобы переместить"))
        let size = view.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let shown = NSPoint(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.minY + 16)
        let hidden = NSPoint(x: shown.x, y: screen.frame.minY - size.height - 8)      // за нижним краем экрана

        toast?.orderOut(nil)
        let p = NSPanel(contentRect: NSRect(origin: hidden, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = view
        p.orderFrontRegardless()
        toast = p
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.25
            c.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(NSRect(origin: shown, size: size), display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self, weak p] in
            guard let p = p, self?.toast === p else { return }
            NSAnimationContext.runAnimationGroup({ c in
                c.duration = 0.25
                c.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().setFrame(NSRect(origin: hidden, size: size), display: true)
            }, completionHandler: { p.orderOut(nil); if self?.toast === p { self?.toast = nil } })
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != FinderCut.marker else { return pass }
        let mods = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard mods == .maskCommand, finderIsActive() else { return pass }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        switch key {
        case 7:                                            // ⌘X
            if editingText() { return pass }
            let before = NSPasteboard.general.changeCount
            post(8, .maskCommand)                          // копировать
            pending = true
            cutCount = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                let now = NSPasteboard.general.changeCount
                if now == before {
                    self.pending = false                   // ничего не выделено — отмена
                } else {
                    self.cutCount = now
                    self.showToast()
                }
            }
            return nil
        case 9:                                            // ⌘V
            if pending && !editingText() && (cutCount == 0 || NSPasteboard.general.changeCount == cutCount) {
                pending = false
                post(9, [.maskCommand, .maskAlternate])    // «Переместить объект сюда»
                return nil
            }
            pending = false
            return pass
        case 8:                                            // ⌘C отменяет вырезание
            pending = false
            return pass
        default:
            return pass
        }
    }
}

/// Небольшая плашка справа внизу; цвета системные, поэтому подчиняется светлой и тёмной теме
final class CutToastView: NSView {
    private let title: String, subtitle: String

    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        if let img = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            let icon = img.withSymbolConfiguration(cfg) ?? img
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                NSColor.controlAccentColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: 16, y: (bounds.height - tinted.size.height) / 2,
                                   width: tinted.size.width, height: tinted.size.height))
        }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingMiddle
        let x: CGFloat = 50, w = bounds.width - x - 14
        (title as NSString).draw(in: NSRect(x: x, y: 30, width: w, height: 18),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                  .foregroundColor: NSColor.labelColor, .paragraphStyle: para])
        (subtitle as NSString).draw(in: NSRect(x: x, y: 11, width: w, height: 16),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                                     .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para])
    }
}

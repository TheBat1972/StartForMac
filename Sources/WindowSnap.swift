import Cocoa
import Carbon.HIToolbox

// MARK: - Окна по сочетаниям ⌃⌥ + стрелка
//
// ← / → — окно встаёт в левую / правую половину экрана (если размер окна меняется); если не меняется — просто
// сдвигается до края в эту сторону. ↑ — окно на весь экран (по размеру рабочей области), ↓ — свернуть в Dock.
// Работает с активным окном любого приложения через Accessibility API.

enum WindowSnap {
    enum Action { case left, right, fill, minimize }

    static let keyCodes: [(id: UInt32, code: UInt32, title: String, action: Action)] = [
        (11, 123, "←", .left), (12, 124, "→", .right), (13, 126, "↑", .fill), (14, 125, "↓", .minimize)
    ]

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "snap.enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "snap.enabled") }
    }

    static func registerAll(_ on: Bool) {
        for k in keyCodes {
            if on {
                let c = Combo(keyCode: k.code, mods: UInt32(controlKey | optionKey), keyTitle: k.title)
                HotKeyCenter.shared.register(c, id: k.id) { perform(k.action) }
            } else {
                HotKeyCenter.shared.unregister(id: k.id)
            }
        }
    }

    private static func point(_ e: AXUIElement) -> CGPoint? {
        guard let v = WindowFinder.attr(e, kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(_ e: AXUIElement) -> CGSize? {
        guard let v = WindowFinder.attr(e, kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    private static func setPoint(_ e: AXUIElement, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v) }
    }

    private static func setSize(_ e: AXUIElement, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v) }
    }

    /// Рабочая область (без меню и Dock) экрана, где лежит окно, в координатах Accessibility (начало слева сверху)
    private static func workArea(for window: CGRect) -> CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        func toAX(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height) }
        let c = CGPoint(x: window.midX, y: window.midY)
        var best: NSScreen?
        var bestArea: CGFloat = -1
        for s in NSScreen.screens {
            let f = toAX(s.frame)
            if f.contains(c) { return toAX(s.visibleFrame) }
            let i = f.intersection(window)
            let a = i.isNull ? 0 : i.width * i.height
            if a > bestArea { bestArea = a; best = s }
        }
        return toAX((best ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame)
    }

    static func perform(_ action: Action) {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let wv = WindowFinder.attr(ax, kAXFocusedWindowAttribute) ?? WindowFinder.attr(ax, kAXMainWindowAttribute) else { return }
        let w = wv as! AXUIElement
        guard WindowFinder.isWindow(w) else { return }
        if (WindowFinder.attr(w, "AXFullScreen") as? Bool) == true { return }

        if action == .minimize {
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            return
        }
        guard let p = point(w), let s = size(w) else { return }
        let area = workArea(for: CGRect(origin: p, size: s))
        var resizable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(w, kAXSizeAttribute as CFString, &resizable)

        switch action {
        case .fill:
            guard resizable.boolValue else { return }
            apply(w, CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height))
        case .left, .right:
            let half = (area.width / 2).rounded(.down)
            if resizable.boolValue {
                let x = action == .left ? area.minX : area.maxX - half
                apply(w, CGRect(x: x, y: area.minY, width: half, height: area.height))
            } else {
                let x = action == .left ? area.minX : area.maxX - s.width
                setPoint(w, CGPoint(x: x, y: p.y))
            }
        case .minimize:
            break
        }
    }

    /// Размер, позиция и ещё раз размер: так окно надёжно встаёт и при переходе между экранами
    private static func apply(_ w: AXUIElement, _ r: CGRect) {
        setSize(w, r.size)
        setPoint(w, r.origin)
        setSize(w, r.size)
        // окно со своим минимальным размером могло не сузиться: прижать к нужному краю
        if let s = size(w), let p = point(w), p.x + s.width > r.maxX + 1 {
            setPoint(w, CGPoint(x: r.maxX - s.width, y: r.minY))
        }
    }
}

import SwiftUI
import AppKit

// MARK: - Пипетка и линейка
//
// Инструмент из меню «Инструменты». «Пипетка» берёт цвет любой точки экрана системной пипеткой macOS (NSColorSampler)
// и показывает его как HEX, RGB и HSL; последние цвета запоминаются. «Линейка» затемняет экран и измеряет
// рамку, которую вы протянули мышью: размер в точках и в пикселях (Esc — выйти, C — скопировать размер).
// Доступа к записи экрана не нужно: цвет и рамку показывает сама система.

final class ScreenToolsModel: ObservableObject {
    static let shared = ScreenToolsModel()
    @Published var tab = 0
    @Published var current: String = UserDefaults.standard.stringArray(forKey: "screen.colors")?.first ?? "#3B82F6"
    @Published var history: [String] = UserDefaults.standard.stringArray(forKey: "screen.colors") ?? []
    @Published var lastMeasure = ""

    func add(_ c: NSColor) {
        guard let s = c.usingColorSpace(.sRGB) else { return }
        let hex = String(format: "#%02X%02X%02X", Int(round(s.redComponent * 255)), Int(round(s.greenComponent * 255)),
                         Int(round(s.blueComponent * 255)))
        current = hex
        history.removeAll { $0 == hex }
        history.insert(hex, at: 0)
        if history.count > 16 { history.removeLast(history.count - 16) }
        UserDefaults.standard.set(history, forKey: "screen.colors")
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: "screen.colors")
    }

    static func color(_ hex: String) -> NSColor {
        var h = hex; if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt32(h, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                       blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    static func rgb(_ hex: String) -> (Int, Int, Int) {
        let c = color(hex)
        return (Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }

    static func hsl(_ hex: String) -> (Int, Int, Int) {
        let (r8, g8, b8) = rgb(hex)
        let r = Double(r8) / 255, g = Double(g8) / 255, b = Double(b8) / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
        }
        return (Int(round(h)), Int(round(s * 100)), Int(round(l * 100)))
    }

    func pick() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] c in
            guard let c = c else { return }
            DispatchQueue.main.async { self?.add(c) }
        }
    }
}

struct ScreenToolsView: View {
    @ObservedObject var m = ScreenToolsModel.shared

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: $m.tab) {
                Text(T("Пипетка")).tag(0)
                Text(T("Линейка")).tag(1)
                Text(T("Транспортир")).tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 330)
            if m.tab == 0 { pipette } else if m.tab == 1 { ruler } else { protractor }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 400, height: 440)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary).frame(width: 44, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button { copyToPasteboard(value) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help(T("Скопировать"))
        }
    }

    private var pipette: some View {
        let hex = m.current
        let (r, g, b) = ScreenToolsModel.rgb(hex)
        let (h, s, l) = ScreenToolsModel.hsl(hex)
        return VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(ScreenToolsModel.color(hex)))
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.2)))
            valueRow("HEX", hex)
            valueRow("RGB", "\(r), \(g), \(b)")
            valueRow("HSL", "\(h)°, \(s)%, \(l)%")
            Button { m.pick() } label: {
                Label(T("Выбрать цвет на экране"), systemImage: "eyedropper").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            if !m.history.isEmpty {
                HStack {
                    Text(T("Последние цвета")).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button(T("Очистить")) { m.clearHistory() }.buttonStyle(.link).font(.caption)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                    ForEach(m.history, id: \.self) { h in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(ScreenToolsModel.color(h)))
                            .frame(width: 30, height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(h == m.current ? Color.accentColor : Color.primary.opacity(0.2),
                                                                               lineWidth: h == m.current ? 2 : 1))
                            .onTapGesture { m.current = h }
                            .help(h)
                    }
                }
            }
        }
    }

    private var protractor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Щёлкните три раза: вершина угла, конец первой стороны, конец второй. Угол показывается сразу и меняется, пока вы двигаете мышь. Следующий щелчок начинает заново. Esc — выйти, C — скопировать угол."))
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { ScreenToolsController.shared.startRuler(mode: 1) } label: {
                Label(T("Измерить угол на экране"), systemImage: "angle").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            if m.lastMeasure.hasSuffix("°") {
                HStack {
                    Text(T("Последний замер")).foregroundColor(.secondary)
                    Spacer()
                    Text(m.lastMeasure).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Button { copyToPasteboard(m.lastMeasure) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help(T("Скопировать"))
                }
            }
        }
    }

    private var ruler: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Протяните мышью рамку на экране: покажу ширину и высоту в точках и в пикселях. Esc — выйти, C — скопировать размер."))
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { ScreenToolsController.shared.startRuler() } label: {
                Label(T("Измерить на экране"), systemImage: "ruler").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            if !m.lastMeasure.isEmpty && !m.lastMeasure.hasSuffix("°") {
                HStack {
                    Text(T("Последний замер")).foregroundColor(.secondary)
                    Spacer()
                    Text(m.lastMeasure).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Button { copyToPasteboard(m.lastMeasure) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help(T("Скопировать"))
                }
            }
        }
    }
}

final class ScreenToolsController: NSObject, NSWindowDelegate {
    static let shared = ScreenToolsController()
    private var window: NSWindow?
    private var overlays: [RulerWindow] = []

    func show(tab: Int? = nil) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: LangRefresh { ScreenToolsView() })
            w.delegate = self
            if !w.setFrameUsingName("ScreenToolsWindow") { w.center() }
            w.setFrameAutosaveName("ScreenToolsWindow")
            window = w
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        if let t = tab { ScreenToolsModel.shared.tab = t }
        window?.title = T("Пипетка и линейка")
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged() { window?.title = T("Пипетка и линейка") }

    func startRuler(mode: Int = 0) {
        guard overlays.isEmpty else { return }
        window?.orderOut(nil)
        overlays = NSScreen.screens.map { RulerWindow(screen: $0, mode: mode) { [weak self] in self?.endRuler(mode: mode) } }
        NSApp.activate(ignoringOtherApps: true)
        overlays.forEach { $0.makeKeyAndOrderFront(nil) }
        overlays.first?.makeKey()
    }

    private func endRuler(mode: Int) {
        let o = overlays; overlays = []
        o.forEach { $0.orderOut(nil) }
        show(tab: mode == 1 ? 2 : 1)
    }
}

/// Окно-затемнение на одном экране: ловит мышь и клавиши
final class RulerWindow: NSWindow {
    init(screen: NSScreen, mode: Int, onClose: @escaping () -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let v = RulerView(frame: NSRect(origin: .zero, size: screen.frame.size), scale: screen.backingScaleFactor, mode: mode, onClose: onClose)
        contentView = v
        setFrame(screen.frame, display: true)
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class RulerView: NSView {
    private let scale: CGFloat
    private let mode: Int      // 0 — линейка, 1 — транспортир
    private let onClose: () -> Void
    private var pts: [NSPoint] = []
    private var start: NSPoint?
    private var rect: NSRect?
    private var mouse = NSPoint.zero
    private var area: NSTrackingArea?

    init(frame: NSRect, scale: CGFloat, mode: Int, onClose: @escaping () -> Void) {
        self.scale = scale
        self.mode = mode
        self.onClose = onClose
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var text: String {
        guard let r = rect else { return "" }
        let w = Int(round(r.width)), h = Int(round(r.height))
        let pw = Int(round(r.width * scale)), ph = Int(round(r.height * scale))
        return scale > 1 ? "\(w) × \(h) pt  (\(pw) × \(ph) px)" : "\(w) × \(h) px"
    }

    override func mouseMoved(with event: NSEvent) { mouse = convert(event.locationInWindow, from: nil); needsDisplay = true }

    /// Угол между сторонами (градусы): вершина — первая точка, концы сторон — вторая и третья либо указатель
    private var angle: (v: NSPoint, a: NSPoint, b: NSPoint, deg: Double)? {
        guard let v = pts.first else { return nil }
        let a = pts.count >= 2 ? pts[1] : mouse
        guard pts.count >= 2 else { return nil }
        let b = pts.count >= 3 ? pts[2] : mouse
        let ax = Double(a.x - v.x), ay = Double(a.y - v.y), bx = Double(b.x - v.x), by = Double(b.y - v.y)
        let la = hypot(ax, ay), lb = hypot(bx, by)
        guard la > 0.5, lb > 0.5 else { return nil }
        let c = max(-1, min(1, (ax * bx + ay * by) / (la * lb)))
        return (v, a, b, acos(c) * 180 / .pi)
    }

    private var angleText: String { angle.map { String(format: "%.1f°", $0.deg) } ?? "" }

    override func mouseDown(with event: NSEvent) {
        if mode == 1 {
            let p = convert(event.locationInWindow, from: nil)
            if pts.count >= 3 { pts = [] }
            pts.append(p)
            mouse = p
            if pts.count == 3 { ScreenToolsModel.shared.lastMeasure = angleText }
            needsDisplay = true
            return
        }
        start = convert(event.locationInWindow, from: nil)
        rect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        if mode == 1 { needsDisplay = true; return }
        guard let s = start else { return }
        rect = NSRect(x: min(s.x, mouse.x), y: min(s.y, mouse.y), width: abs(mouse.x - s.x), height: abs(mouse.y - s.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if mode == 1 { return }
        start = nil
        if let r = rect, r.width > 1 || r.height > 1 { ScreenToolsModel.shared.lastMeasure = text }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 53 { onClose() }
        else if key == "c", mode == 1, angle != nil {
            copyToPasteboard(angleText)
            ScreenToolsModel.shared.lastMeasure = angleText
            onClose()
        }
        else if key == "c", mode == 0, rect != nil {
            copyToPasteboard(text)
            ScreenToolsModel.shared.lastMeasure = text
            onClose()
        }
    }

    private func drawProtractor(label: (String, NSPoint) -> Void) {
        let acc = NSColor.controlAccentColor
        func line(_ a: NSPoint, _ b: NSPoint) {
            let p = NSBezierPath(); p.move(to: a); p.line(to: b); p.lineWidth = 1.5; p.stroke()
        }
        func dot(_ c: NSPoint) { acc.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)).fill() }
        acc.setStroke()
        if let v = pts.first {
            let a = pts.count >= 2 ? pts[1] : mouse
            line(v, a); dot(v)
            if pts.count >= 2 { dot(a) }
            if let g = angle {
                line(g.v, g.b)
                if pts.count >= 3 { dot(g.b) }
                // дуга между сторонами по кратчайшему пути
                let a1 = atan2(Double(g.a.y - g.v.y), Double(g.a.x - g.v.x))
                let a2 = atan2(Double(g.b.y - g.v.y), Double(g.b.x - g.v.x))
                var d = a2 - a1
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                let r = 38.0
                let arc = NSBezierPath()
                for i in 0...48 {
                    let t = a1 + d * Double(i) / 48
                    let pt = NSPoint(x: Double(g.v.x) + r * cos(t), y: Double(g.v.y) + r * sin(t))
                    if i == 0 { arc.move(to: pt) } else { arc.line(to: pt) }
                }
                arc.lineWidth = 1.5; arc.stroke()
                let mid = a1 + d / 2
                label(angleText, NSPoint(x: Double(g.v.x) + (r + 6) * cos(mid), y: Double(g.v.y) + (r + 6) * sin(mid)))
            } else if pts.count == 1 {
                label(T("Щёлкните конец первой стороны"), mouse)
            }
        } else {
            label(T("Щёлкните вершину угла"), mouse)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        func label(_ s: String, _ p: NSPoint) {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                                                        .foregroundColor: NSColor.white]
            let sz = (s as NSString).size(withAttributes: attrs)
            var o = NSPoint(x: p.x + 12, y: p.y + 14)
            if o.x + sz.width + 16 > bounds.width { o.x = p.x - sz.width - 28 }
            if o.y + sz.height + 8 > bounds.height { o.y = p.y - sz.height - 20 }
            let box = NSRect(x: o.x, y: o.y, width: sz.width + 16, height: sz.height + 8)
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            (s as NSString).draw(at: NSPoint(x: box.minX + 8, y: box.minY + 4), withAttributes: attrs)
        }
        if mode == 1 { drawProtractor(label: label); return }
        if let r = rect {
            NSColor.clear.setFill()
            NSGraphicsContext.current?.compositingOperation = .clear
            r.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            r.fill()
            NSColor.controlAccentColor.setStroke()
            let b = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); b.lineWidth = 1; b.stroke()
            label(text, NSPoint(x: r.maxX, y: r.maxY))
        } else {
            // пока рамки нет: крестик и координаты указателя
            NSColor.white.withAlphaComponent(0.7).setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 0, y: mouse.y)); p.line(to: NSPoint(x: bounds.width, y: mouse.y))
            p.move(to: NSPoint(x: mouse.x, y: 0)); p.line(to: NSPoint(x: mouse.x, y: bounds.height))
            p.lineWidth = 0.5; p.stroke()
            label("\(Int(mouse.x)), \(Int(mouse.y))", mouse)
        }
    }
}

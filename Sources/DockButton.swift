import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - Кнопка «Пуска» у края Dock (альфа)
// «Пуск» рисует свою маленькую плавающую кнопку и ставит её вплотную к Dock: слева от него (Dock внизу)
// или под ним (Dock сбоку). Сам Dock не трогаем: границы списка его значков читаем через Accessibility
// и следуем за ними, поэтому учитываются размер, расположение и автоскрытие Dock.
// Окно Dock в общем списке окон отдельной карточкой не виден (там только прозрачное окно на весь экран), поэтому нужен Accessibility.

final class DockButton {
    static let shared = DockButton()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "dockButton.enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.enabled") }
    }
    /// Журнал найденных окон Dock (~/Library/Logs/Pusk-dockbtn.log): пока альфа, нужен для подбора
    static let debugLog = true

    /// Размер кнопки: 0,6…1,6 (по умолчанию 1 — штатный размер кнопки, 1,35 значка Dock)
    static var sizeScale: Double {
        get { min(max(UserDefaults.standard.object(forKey: "dockButton.size") as? Double ?? 1, 0.6), 1.6) }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.size") }
    }

    /// Фон значка внутри кнопки: белый, чёрный или цвет радуги, прозрачность и насыщенность
    static let iconPalette: [(name: String, hue: CGFloat, sat: CGFloat, bri: CGFloat)] = [
        ("Белый", 0, 0, 1), ("Чёрный", 0, 0, 0), ("Красный", 0, 1, 0.95), ("Оранжевый", 0.07, 1, 1), ("Жёлтый", 0.14, 1, 1),
        ("Зелёный", 0.33, 1, 0.85), ("Голубой", 0.5, 1, 1), ("Синий", 0.62, 1, 1), ("Фиолетовый", 0.78, 1, 0.9)
    ]
    static var iconColorIndex: Int {
        get { min(max(UserDefaults.standard.object(forKey: "dockButton.iconColor") as? Int ?? 0, 0), iconPalette.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.iconColor") }
    }
    /// Непрозрачность фона значка 0…1 (по умолчанию 0,10)
    static var iconAlpha: Double {
        get { min(max(UserDefaults.standard.object(forKey: "dockButton.iconAlpha") as? Double ?? 0.10, 0), 1) }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.iconAlpha") }
    }
    /// Насыщенность цвета фона 0…1 (по умолчанию 1); у белого и чёрного не действует
    static var iconSaturation: Double {
        get { min(max(UserDefaults.standard.object(forKey: "dockButton.iconSat") as? Double ?? 1, 0), 1) }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.iconSat") }
    }
    /// Тонкая серая окантовка значка (по умолчанию включена)
    static var iconOutline: Bool {
        get { UserDefaults.standard.object(forKey: "dockButton.iconOutline") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.iconOutline") }
    }
    static var iconBackground: NSColor {
        let c = iconPalette[iconColorIndex]
        return NSColor(calibratedHue: c.hue, saturation: c.sat * CGFloat(iconSaturation), brightness: c.bri, alpha: CGFloat(iconAlpha))
    }

    /// Положение: 0 — у Dock (следит за ним), 1 — свободно на экране поверх всех окон (можно перетащить)
    static var mode: Int {
        get { min(max(UserDefaults.standard.object(forKey: "dockButton.mode") as? Int ?? 0, 0), 1) }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.mode") }
    }
    /// Расстояние от Dock в режиме «Рядом с Dock»: 0…1 — от 3 pt до двух значков Dock (по умолчанию 8 pt, как было)
    static var gapFraction: Double {
        get {
            if let v = UserDefaults.standard.object(forKey: "dockButton.gap") as? Double { return min(max(v, 0), 1) }
            return (8 - minGap) / max(maxGap - minGap, 1)
        }
        set { UserDefaults.standard.set(newValue, forKey: "dockButton.gap") }
    }
    private static let minGap: Double = 3
    private static var maxGap: Double {
        let tile = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 0
        return 2 * (tile > 0 ? tile : 64)
    }
    static var gapPoints: CGFloat { CGFloat(minGap + gapFraction * (maxGap - minGap)) }

    /// macOS 26 и новее: кнопка делается из «жидкого стекла», прозрачность задаёт система
    static var usesGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Где кнопка стоит в режиме «На экране» (левый нижний угол, координаты экрана)
    static var freeOrigin: NSPoint? {
        get { (UserDefaults.standard.string(forKey: "dockButton.freeOrigin")).map { NSPointFromString($0) } }
        set { UserDefaults.standard.set(newValue.map { NSStringFromPoint($0) }, forKey: "dockButton.freeOrigin") }
    }

    var onClick: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHide: (() -> Void)?
    /// Пункты меню значка «Пуска» в Dock (свернуть окна, не давать уснуть, «Создать»…): показываются и по правому клику на кнопке
    var menuProvider: (() -> NSMenu?)?
    /// Где сейчас кнопка (координаты экрана): от неё открывается окно «Пуска»
    private(set) var buttonFrame: NSRect?

    private enum Side { case bottom, left, right }
    private struct Geo { let rect: NSRect; let side: Side; let screen: NSScreen; var iconMid: CGFloat? = nil }

    private var panel: DockButtonPanel?
    private var overlay: DockSquaresPanel?      // увеличенные квадраты: растут над кнопкой, как значки Dock над Dock
    private let queue = DispatchQueue(label: "dockbutton.poll", qos: .userInteractive)
    private var running = false
    private var generation = 0
    private var lastRect = NSRect.zero
    private var lastChange = Date.distantPast
    private var lastLog = ""
    private var lastLogTime = Date.distantPast

    func setEnabled(_ on: Bool) { on ? start() : stop() }

    func start() {
        guard !running else { return }
        running = true
        generation += 1
        let gen = generation
        queue.async { [weak self] in self?.tick(gen) }
    }

    func stop() {
        running = false
        generation += 1
        DispatchQueue.main.async { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.overlay?.orderOut(nil)
            self?.overlay = nil
        }
    }

    // MARK: опрос окна Dock

    private func tick(_ gen: Int) {
        guard running, gen == generation else { return }
        if Self.mode == 1 {                      // свободная кнопка за Dock не следит: Dock не опрашиваем
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.running, gen == self.generation else { return }
                self.applyFree()
            }
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.tick(gen) }
            return
        }
        let geo = findDock()
        let rect = geo?.rect ?? .zero
        if rect != lastRect { lastRect = rect; lastChange = Date() }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.running, gen == self.generation else { return }
            self.apply(geo)
        }
        // у края экрана или сразу после сдвига Dock — часто (анимация), иначе редко
        var interval = 0.25
        if Date().timeIntervalSince(lastChange) < 2.5 || mouseNearEdge() || magK > 1.01 { interval = 1.0 / 144.0 }   // Dock едет (автоскрытие): опрашиваем как можно чаще, чтобы кнопка успевала
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in self?.tick(gen) }
    }

    private func mouseNearEdge() -> Bool {
        let m = NSEvent.mouseLocation
        for s in NSScreen.screens where s.frame.contains(m) {
            let f = s.frame
            let e: CGFloat = 220      // с увеличением Dock выше
            return m.y < f.minY + e || m.x < f.minX + e || m.x > f.maxX - e
        }
        return false
    }

    /// Границы списка значков Dock (AXList у процесса Dock): нужен доступ «Универсальный доступ»
    private func findDock() -> Geo? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            if Self.debugLog { log(["нет доступа Accessibility или нет процесса Dock"], chosen: nil) }
            return nil
        }
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var ch: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &ch) == .success,
              let kids = ch as? [AXUIElement] else {
            if Self.debugLog { log(["у Dock нет дочерних элементов AX"], chosen: nil) }
            return nil
        }
        var best: NSRect?
        var bestKid: AXUIElement?
        var desc: [String] = []
        for k in kids {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(k, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == kAXListRole as String else { continue }
            var pv: CFTypeRef?, sv: CFTypeRef?
            guard AXUIElementCopyAttributeValue(k, kAXPositionAttribute as CFString, &pv) == .success,
                  AXUIElementCopyAttributeValue(k, kAXSizeAttribute as CFString, &sv) == .success,
                  let pvv = pv, let svv = sv else { continue }
            var pt = CGPoint.zero, sz = CGSize.zero
            guard AXValueGetValue(pvv as! AXValue, .cgPoint, &pt), AXValueGetValue(svv as! AXValue, .cgSize, &sz) else { continue }
            desc.append("AXList x=\(Int(pt.x)) y=\(Int(pt.y)) w=\(Int(sz.width)) h=\(Int(sz.height))")
            guard sz.width >= 20, sz.height >= 20 else { continue }
            let r = NSRect(x: pt.x, y: primary.frame.height - (pt.y + sz.height), width: sz.width, height: sz.height)   // координаты Cocoa
            if best == nil || r.width * r.height > best!.width * best!.height { best = r; bestKid = k }
        }
        if Self.debugLog { log(desc, chosen: best) }
        guard let r = best else { return nil }
        let c = NSPoint(x: r.midX, y: r.midY)
        guard let screen = screens.first(where: { $0.frame.contains(c) }) ?? screens.first(where: { $0.frame.intersects(r) }) else { return nil }
        let side: Side = r.width >= r.height ? .bottom : (r.midX < screen.frame.midX ? .left : .right)
        var geo = Geo(rect: r, side: side, screen: screen)
        // середина ряда значков (а не всего списка): по ней и центруем кнопку
        if let k = bestKid {
            var cv: CFTypeRef?
            if AXUIElementCopyAttributeValue(k, kAXChildrenAttribute as CFString, &cv) == .success, let icons = cv as? [AXUIElement], !icons.isEmpty {
                // берём самый маленький значок: увеличенный под курсором сдвинул бы середину
                var minSize = CGFloat.greatestFiniteMagnitude
                for ic in icons {
                    var pv: CFTypeRef?, sv: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(ic, kAXPositionAttribute as CFString, &pv) == .success,
                          AXUIElementCopyAttributeValue(ic, kAXSizeAttribute as CFString, &sv) == .success,
                          let pvv = pv, let svv = sv else { continue }
                    var pt = CGPoint.zero, sz = CGSize.zero
                    guard AXValueGetValue(pvv as! AXValue, .cgPoint, &pt), AXValueGetValue(svv as! AXValue, .cgSize, &sz), sz.width > 8, sz.height > 8 else { continue }
                    let dim = side == .bottom ? sz.height : sz.width
                    guard dim < minSize else { continue }
                    minSize = dim
                    geo.iconMid = side == .bottom ? primary.frame.height - (pt.y + sz.height / 2) : pt.x + sz.width / 2
                }
            }
        }
        return geo
    }

    private func log(_ desc: [String], chosen: NSRect?) {
        let text = desc.joined(separator: " | ") + " => " + (chosen.map { "\($0)" } ?? "none")
        guard text != lastLog, Date().timeIntervalSince(lastLogTime) > 0.5 else { return }
        lastLog = text
        lastLogTime = Date()
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Pusk-dockbtn.log")
        let line = "\(Date()) \(text)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: кнопка

    private func apply(_ geo: Geo?) {
        guard let geo = geo else { buttonFrame = nil; panel?.orderOut(nil); overlay?.orderOut(nil); return }
        let r = geo.rect
        let s = buttonSize(fallback: min(r.width, r.height) - 16)
        var f: NSRect
        switch geo.side {
        case .bottom: f = NSRect(x: r.minX - s - DockButton.gapPoints, y: (geo.iconMid ?? r.midY) - s / 2, width: s, height: s)      // слева от Dock, по середине ряда значков
        case .left, .right: f = NSRect(x: (geo.iconMid ?? r.midX) - s / 2, y: r.minY - s - DockButton.gapPoints, width: s, height: s) // под Dock
        }
        // Dock спрятан (автоскрытие) или кнопка ушла за экран: не показываем
        let visible = f.intersection(geo.screen.frame)
        if visible.width * visible.height < f.width * f.height * 0.1 { buttonFrame = nil; panel?.orderOut(nil); overlay?.orderOut(nil); return }
        let k = smoothedMagnification(geo, f, current: widened(f, k: magK, side: geo.side), screen: geo.screen.frame)
        f = widened(f, k: k, side: geo.side)       // при увеличении Dock кнопка раздвигается по горизонтали
        buttonFrame = f
        let p = panel ?? makePanel()
        let m = DockButtonPanel.margin
        let pf = f.insetBy(dx: -m, dy: -m)
        p.setFree(false)
        if p.buttonSize != s {
            p.rebuild(size: s)
        }
        if p.frame != pf {
            // при движении Dock меняется только положение: двигаем окно без перерисовки, это быстрее
            if p.frame.size == pf.size { p.setFrameOrigin(pf.origin) } else { p.setFrame(pf, display: true) }
        }
        let icon = iconSize(button: s)
        p.setIconSize(icon)
        p.setIconInOverlay(true)           // в режиме у Dock значок рисует только окно над кнопкой: без передачи между двумя окнами он не мигает
        updateOverlay(k: k, buttonFrame: f, size: s, icon: icon, side: geo.side)
        if !p.isVisible { p.orderFrontRegardless() }
    }

    /// Текущее увеличение значков Dock возле кнопки: 1 — обычное; растёт, когда курсор над Dock и в системе включено «Увеличение».
    /// Нужно только для синих квадратов, сама кнопка не меняется.
    /// Коэффициент к увеличению Dock (large/tilesize): значок растёт на 10% меньше, чем значки Dock
    private static let magnifyCoef: CGFloat = 0.9
    private static let maxMagnify: CGFloat = 2.0      // значок растёт не больше чем в 2 раза
    private var magK: CGFloat = 1
    /// Кнопка раздвигается вдоль Dock, но вдвое слабее квадратов (отступы до краёв не меняются): у нижнего Dock по горизонтали
    /// от стороны Dock, у бокового — вверх и вниз поровну
    private func widened(_ f: NSRect, k: CGFloat, side: Side) -> NSRect {
        guard k > 1.001 else { return f }
        var w = f
        let s = min(f.width, f.height)
        let grown = (s * (1 + (k - 1) / 2)).rounded()
        if side == .bottom {
            w.size.width = grown
            w.origin.x = f.maxX - grown          // растёт влево, от Dock
        } else {
            w.size.height = grown
            w.origin.y = f.midY - grown / 2      // растёт вверх и вниз поровну
        }
        return w
    }

    private func smoothedMagnification(_ geo: Geo, _ f: NSRect, current: NSRect, screen: NSRect) -> CGFloat {
        var target: CGFloat = 1
        if let d = UserDefaults(suiteName: "com.apple.dock"), d.bool(forKey: "magnification") {
            let tile = CGFloat(d.double(forKey: "tilesize")), large = CGFloat(d.double(forKey: "largesize"))
            let m = NSEvent.mouseLocation
            // у горизонтального Dock курсор на кнопке или ниже неё (до края экрана) считается наведённым на кнопку
            let hot = geo.side == .bottom ? NSRect(x: current.minX, y: screen.minY, width: current.width, height: current.maxY - screen.minY) : current
            if tile > 0, large > tile, hot.contains(m) {
                target = min(large / tile * Self.magnifyCoef, Self.maxMagnify)              // курсор на самой кнопке: квадраты максимальные
            } else if tile > 0, large > tile, geo.rect.insetBy(dx: -8, dy: -8).contains(m) {
                let dist = geo.side == .bottom ? abs(m.x - f.midX) : abs(m.y - f.midY)
                let t = min(dist / (3 * tile), 1)
                let w = cos(t * .pi / 2)
                target = 1 + (min(large / tile * Self.magnifyCoef, Self.maxMagnify) - 1) * w * w
            }
        }
        magK += (target - magK) * 0.4          // плавно, как у самого Dock
        if abs(target - magK) < 0.02 { magK = target }
        return magK
    }

    /// Окно с увеличенными квадратами: прозрачное, пропускает мышь, больше кнопки на 0,5 её размера с каждой стороны
    private func updateOverlay(k: CGFloat, buttonFrame f: NSRect, size s: CGFloat, icon: CGFloat, side: Side) {
        let o = overlay ?? DockSquaresPanel()
        overlay = o
        let pad = max(s * 0.5, icon * 1.3).rounded()
        let of = f.insetBy(dx: -pad, dy: -pad)
        if o.frame != of { o.setFrame(of, display: false) }
        o.squares.pad = pad
        o.squares.k = k
        o.squares.iconSize = icon
        o.squares.edge = side == .bottom ? 0 : 1
        if !o.isVisible { o.orderFrontRegardless() }
    }

    /// Значок внутри кнопки пропорционален ей: при размере 100% он на 10% меньше значка Finder в Dock (0,81 tilesize при кнопке 1,35 tilesize),
    /// ползунок размера меняет кнопку и значок вместе, увеличение Dock умножает уже этот размер
    private func iconSize(button s: CGFloat) -> CGFloat { (s * 0.81 / 1.35).rounded() }

    /// Размер — как у значка Dock (tilesize), с поправкой на выбранный размер кнопки
    private func buttonSize(fallback: CGFloat) -> CGFloat {
        let tile = CGFloat(UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 0)
        let base = tile > 0 ? tile : max(fallback, 48)
        return min(max((base * 1.35 * CGFloat(Self.sizeScale)).rounded(), 28), 300)
    }

    /// Режим «На экране»: кнопка стоит там, где её оставили, поверх всех окон
    private func applyFree() {
        let s = buttonSize(fallback: 64)
        magK = 1
        overlay?.orderOut(nil)
        let p = panel ?? makePanel()
        let m = DockButtonPanel.margin
        if p.userDragging { buttonFrame = p.frame.insetBy(dx: m, dy: m); return }
        var origin = Self.freeOrigin ?? .zero
        let screens = NSScreen.screens
        let valid = Self.freeOrigin != nil && screens.contains { $0.frame.intersects(NSRect(origin: origin, size: NSSize(width: s, height: s))) }
        if !valid {
            let vf = (NSScreen.main ?? screens[0]).visibleFrame
            origin = NSPoint(x: vf.minX + 24, y: vf.minY + 24)
        }
        let f = NSRect(origin: origin, size: NSSize(width: s, height: s))
        buttonFrame = f
        let pf = f.insetBy(dx: -m, dy: -m)
        p.setFree(true)
        if p.buttonSize != s { p.rebuild(size: s) }
        p.setIconSize(iconSize(button: s))
        p.setIconInOverlay(false)          // на экране значок рисует сама кнопка
        if p.frame != pf { p.setFrame(pf, display: true) }
        if !p.isVisible { p.orderFrontRegardless() }
    }

    /// Перерисовать кнопку после смены прозрачности
    func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let p = self?.panel, p.buttonSize > 0 else { self?.overlay?.squares.needsDisplay = true; return }
            p.rebuild(size: p.buttonSize)
            self?.overlay?.squares.needsDisplay = true
        }
    }

    /// Запомнить, где кнопку оставили (режим «На экране»)
    fileprivate func saveFreeOrigin(from panel: DockButtonPanel) {
        let m = DockButtonPanel.margin
        Self.freeOrigin = NSPoint(x: panel.frame.minX + m, y: panel.frame.minY + m)
    }

    private func makePanel() -> DockButtonPanel {
        let p = DockButtonPanel()
        p.onClick = { [weak self] in self?.onClick?() }
        p.onSettings = { [weak self] in self?.onSettings?() }
        p.onHide = { [weak self] in self?.onHide?() }
        p.menuProvider = { [weak self] in self?.menuProvider?() }
        p.onMoved = { [weak self, weak p] in if let p = p { self?.saveFreeOrigin(from: p) } }
        panel = p
        return p
    }
}

/// Невидимое окно над кнопкой: рисует увеличенные синие квадраты. Они растут от стороны, обращённой к Dock (вверх над нижним Dock,
/// вбок у бокового), как значки Dock, и могут выходить за пределы кнопки. Мышь пропускает.
final class DockSquaresPanel: NSPanel {
    let squares = DockSquaresView()
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        squares.autoresizingMask = [.width, .height]
        contentView = squares
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class DockSquaresView: NSView {
    static weak var shared: DockSquaresView?
    var pressed = false { didSet { needsDisplay = true } }
    var hover = false { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); DockSquaresView.shared = self }
    required init?(coder: NSCoder) { fatalError() }
    var pad: CGFloat = 0 { didSet { needsDisplay = true } }
    var k: CGFloat = 1 { didSet { needsDisplay = true } }
    var iconSize: CGFloat = 0 { didSet { needsDisplay = true } }
    var edge = 0 { didSet { needsDisplay = true } }      // 0 — Dock снизу (растём вверх), иначе от центра
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let btn = bounds.insetBy(dx: pad, dy: pad)
        let base = iconSize > 0 ? iconSize : min(btn.width, btn.height) * 0.62
        let size = base * (k > 1.001 ? k : (hover ? 1.12 : 1))      // увеличение Dock или, без него, небольшой рост при наведении
        var x0 = btn.midX - size / 2, y0 = btn.midY - size / 2
        if edge == 0 { y0 = btn.midY - base / 2 }          // у нижнего Dock низ значка стоит на месте, верх поднимается; у бокового растёт от центра
        drawStartIcon(in: NSRect(x: x0, y: y0, width: size, height: size), dim: pressed ? 0.3 : 0)
    }
}

final class DockButtonPanel: NSPanel {
    static let margin: CGFloat = 6          // запас вокруг кнопки: под тень и небольшое увеличение при наведении
    var onClick: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHide: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onMoved: (() -> Void)?
    var userDragging = false
    private(set) var buttonSize: CGFloat = 0
    private weak var buttonView: DockButtonView?
    func setIconInOverlay(_ on: Bool) { buttonView?.setIconInOverlay(on) }
    func setIconSize(_ v: CGFloat) { buttonView?.setIconSize(v) }
    /// Кнопка выше окна «Пуска» (оно на уровне .floating, ниже Dock) в обоих режимах
    func setFree(_ free: Bool) {
        let lvl = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        if level != lvl { level = lvl }
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    // «Жидкое стекло» (NSGlassEffectView) рисуется настоящим, с преломлением, только в окне с активным видом, то есть в ключевом окне
    // активной программы. Наша панель ключевой не бывает (иначе она отнимала бы фокус у программы, в которой работает пользователь),
    // и стекло рисовалось бы матовым и серым. Поэтому панель отвечает «да» на закрытые вопросы AppKit об активном виде.
    // Это недокументированные селекторы AppKit: если в будущей macOS они пропадут, стекло просто станет матовым, ничего не сломается.
    @objc(_hasActiveAppearance) func glassHasActiveAppearance() -> Bool { true }
    @objc(_hasActiveAppearanceIgnoringKeyFocus) func glassHasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

    func rebuild(size s: CGFloat) {
        buttonSize = s
        let m = Self.margin
        let box = NSView(frame: NSRect(x: 0, y: 0, width: s + 2 * m, height: s + 2 * m))
        let v = DockButtonView(frame: NSRect(x: m, y: m, width: s, height: s))
        v.onClick = { [weak self] in self?.onClick?() }
        v.onSettings = { [weak self] in self?.onSettings?() }
        v.onHide = { [weak self] in self?.onHide?() }
        v.menuProvider = { [weak self] in self?.menuProvider?() }
        v.onMoved = { [weak self] in self?.onMoved?() }
        v.autoresizingMask = [.width, .height]
        box.addSubview(v)
        buttonView = v
        contentView = box
    }
}

/// Значок «Пуска»: белый (10%) скруглённый квадрат с тончайшей серой окантовкой и четырьмя синими окнами (как в Windows).
private func drawStartIcon(in r: NSRect, dim: CGFloat = 0) {
    let w = r.width
    let radius = w * 0.225
    let shape = NSBezierPath(roundedRect: r.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
    DockButton.iconBackground.setFill()      // фон значка: цвет, прозрачность и насыщенность из настроек
    shape.fill()
    if DockButton.iconOutline {
        NSColor(calibratedWhite: 0.72, alpha: 1).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
    let block = w * 0.46 / 0.9, gap = block * 0.1      // окна остались прежнего размера, хотя значок стал на 10% меньше
    let p = (block - gap) / 2
    let x0 = r.midX - block / 2, y0 = r.midY - block / 2
    let colors = [NSColor(calibratedRed: 0.20, green: 0.64, blue: 1.00, alpha: 1),
                  NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.96, alpha: 1),
                  NSColor(calibratedRed: 0.08, green: 0.50, blue: 0.92, alpha: 1),
                  NSColor(calibratedRed: 0.04, green: 0.44, blue: 0.86, alpha: 1)]
    for row in 0..<2 {
        for col in 0..<2 {
            let q = NSRect(x: x0 + CGFloat(col) * (p + gap), y: y0 + CGFloat(1 - row) * (p + gap), width: p, height: p)
            (colors[row * 2 + col].blended(withFraction: dim, of: .black) ?? colors[row * 2 + col]).setFill()      // при нажатии темнеют синие окна
            NSBezierPath(roundedRect: q, xRadius: w * 0.022, yRadius: w * 0.022).fill()
        }
    }
}

/// Четыре синих квадрата (как «Пуск» в Windows) с подсветкой при наведении и затемнением при нажатии.
/// Рисуется отдельным видом поверх подложки: сама подложка (NSVisualEffectView) свой draw не вызывает.
private final class DockGlyphView: NSView {
    var hover = false { didSet { needsDisplay = true; DockSquaresView.shared?.hover = hover } }
    var pressed = false { didSet { needsDisplay = true; DockSquaresView.shared?.pressed = pressed } }
    var iconInOverlay = false { didSet { if iconInOverlay != oldValue { needsDisplay = true } } }
    var iconSize: CGFloat = 0 { didSet { if iconSize != oldValue { needsDisplay = true } } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }      // мышь достаётся кнопке под ним

    override func draw(_ dirtyRect: NSRect) {
        let s = min(bounds.width, bounds.height)
        // значок «Пуска» по центру: белый (10%) скруглённый квадрат с тонкой серой окантовкой и четырьмя синими окнами
        if iconInOverlay { return }          // у Dock значок рисует отдельное окно над кнопкой (оно же показывает увеличение)
        let base = iconSize > 0 ? iconSize : s * 0.62
        let size = base * (hover ? 1.12 : 1)    // при наведении чуть крупнее только значок, сама кнопка не меняется
        drawStartIcon(in: NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size), dim: pressed ? 0.3 : 0)
    }
}

/// Кнопка в духе «Пуск» из Windows на подложке в стиле Dock.
/// При наведении чуть увеличивается, при нажатии темнеет; правый клик — меню значка «Пуска» из Dock плюс «Настройки…» и «Скрыть кнопку».
private final class DockButtonView: NSView {
    var onClick: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHide: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onMoved: (() -> Void)?
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var dragged = false
    private let glyph = DockGlyphView()
    private var tracking: NSTrackingArea?
    private var restFrame: NSRect?

    private var backdrop: NSView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        if DockButton.usesGlass, #available(macOS 26.0, *) {
            // macOS 26: настоящее «жидкое стекло», как у Dock и системных контролов
            let g = NSGlassEffectView()
            // стиль стекла: .clear (по умолчанию: прозрачное стекло с затемнением, как у Dock) или .regular: defaults write ru.local.StartMenu dockButton.glassStyle regular
            g.style = UserDefaults.standard.string(forKey: "dockButton.glassStyle") == "regular" ? .regular : .clear
            backdrop = g
        } else {
            let v = NSVisualEffectView()
            v.material = .hudWindow   // системный материал: сам светлеет/темнеет по теме и фону, без своей подложки
            v.blendingMode = .behindWindow
            v.state = .active
            backdrop = v
            layer?.masksToBounds = true
        }
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop)
        if DockButton.debugLog {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            let line = "\(Date()) подложка: \(type(of: backdrop!)), стекло=\(DockButton.usesGlass), macOS \(v.majorVersion).\(v.minorVersion)\n"
            let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Pusk-dockbtn.log")
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
        restFrame = frameRect
        glyph.frame = bounds
        glyph.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let g = backdrop as? NSGlassEffectView {
            g.contentView = glyph             // по правилам AppKit содержимое кладут внутрь стекла: так оно рисуется как следует
            applyTint()
        } else {
            addSubview(glyph)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Лёгкое затемнение стекла по теме системы: системное стекло получается светлее Dock и на тёмном, и на светлом фоне.
    /// Фон за кнопкой не измеряем (это требовало записи экрана), поэтому только по теме: в тёмной теме сильнее, в светлой слабее.
    private func applyTint() {
        guard #available(macOS 26.0, *), let g = backdrop as? NSGlassEffectView else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        g.tintColor = NSColor.black.withAlphaComponent(dark ? 0.21 : 0.16)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    override func layout() {
        super.layout()
        let radius = min(bounds.width, bounds.height) * 0.3
        layer?.cornerRadius = radius
        if #available(macOS 26.0, *), let g = backdrop as? NSGlassEffectView { g.cornerRadius = radius }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    /// При наведении только подсвечиваем: размер кнопки не меняем (при смене размера значок внутри «уезжал»)
    private func setHover(_ on: Bool) { glyph.hover = on }
    func setIconInOverlay(_ on: Bool) { glyph.iconInOverlay = on }
    func setIconSize(_ v: CGFloat) { glyph.iconSize = v }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) {
        glyph.pressed = false
        setHover(false)
    }
    override func mouseDown(with event: NSEvent) {
        glyph.pressed = true
        dragged = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
    }

    /// В режиме «На экране» кнопку можно перетащить; короткий клик без сдвига — обычный клик
    override func mouseDragged(with event: NSEvent) {
        guard DockButton.mode == 1, let panel = window as? DockButtonPanel else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - dragStartMouse.x, dy = m.y - dragStartMouse.y
        if !dragged && hypot(dx, dy) < 4 { return }
        dragged = true
        panel.userDragging = true
        glyph.pressed = false
        panel.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        glyph.pressed = false
        if dragged {
            dragged = false
            (window as? DockButtonPanel)?.userDragging = false
            onMoved?()
            return
        }
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = menuProvider?() ?? NSMenu()
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let a = NSMenuItem(title: T("Настройки…"), action: #selector(menuSettings), keyEquivalent: "")
        a.target = self
        let b = NSMenuItem(title: T("Скрыть кнопку"), action: #selector(menuHide), keyEquivalent: "")
        b.target = self
        menu.addItem(a)
        menu.addItem(b)
        menu.addItem(.separator())
        let q = NSMenuItem(title: T("Закрыть «Пуск»"), action: #selector(menuQuit), keyEquivalent: "")
        q.target = self
        menu.addItem(q)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func menuSettings() { onSettings?() }
    @objc private func menuHide() { onHide?() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}

// «Передохни»: Diam — игра с кристаллами, переписанная с iOS (SpriteKit) на Swift/AppKit.
// Поле 6×16: кристалл перетаскивается на соседнюю клетку (меняется местами с соседом или съезжает в пустоту),
// после каждого хода сверху добавляется новая линия. Три в ряд (по строке или столбцу) исчезают вместе со всеми связанными с ними
// по сторонам кристаллами того же цвета — по диагонали связи нет; цепочки считаются. Столбик дорос до верха — конец игры. Режимы «5 цветов» и
// «4 цвета» с отдельными таблицами рекордов. Картинки и звуки — в папке DiamRes внутри приложения.
import AppKit

// MARK: - Ресурсы и звуки

private enum DiamRes {
    private static let dir: URL? = Bundle.main.resourceURL?.appendingPathComponent("DiamRes")
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let i = images[name] { return i }
        guard let u = dir?.appendingPathComponent(name), let i = NSImage(contentsOf: u) else { return nil }
        images[name] = i
        return i
    }

    static func url(_ name: String) -> URL? { return dir?.appendingPathComponent(name) }
}

private enum DiamSound {
    private static var cache: [String: NSSound] = [:]
    private static let files = ["1.wav", "2.wav", "3.wav", "4.wav"]

    private static func sound(_ name: String) -> NSSound? {
        if let s = cache[name] { return s }
        guard let u = DiamRes.url(name), let s = NSSound(contentsOf: u, byReference: false) else { return nil }
        cache[name] = s
        return s
    }

    /// Один из четырёх звуков наугад, как в оригинале
    static func play() {
        guard let s = sound(files.randomElement()!) else { return }
        s.stop()
        s.volume = 1
        s.play()
    }

    static func warmUp() {
        for f in files {
            guard let s = sound(f) else { continue }
            s.volume = 0
            s.play()
            s.stop()
        }
    }
}

// MARK: - Модель

private final class DiamGem {
    let color: String
    var col: Int, row: Int          // клетка, в которую кристалл едет
    var x: Double, y: Double        // где он сейчас нарисован (в клетках)
    var dying = 0.0                 // секунд до исчезновения; 0 — не исчезает
    init(color: String, col: Int, row: Int) {
        self.color = color; self.col = col; self.row = row
        x = Double(col); y = Double(row)
    }
    var atRest: Bool { return dying == 0 && abs(x - Double(col)) < 0.001 && abs(y - Double(row)) < 0.001 }
}

private struct DiamSpark {
    var p: CGPoint
    var v: CGVector
    var life: Double
    var color: NSColor
}

private struct DiamCell: Hashable {
    var row: Int
    var col: Int
}

final class DiamView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let cols = 6, rows = 16
    private let gw: CGFloat = 48, gh: CGFloat = 36          // размер кристалла
    private let px: CGFloat = 49, py: CGFloat = 37          // шаг клеток
    private let origin = CGPoint(x: 20, y: 56)
    private let dieTime = 0.25

    private var grid: [[DiamGem?]] = []
    private var score = 0
    private var over = false
    private var needMatch = false
    private var matchDelay = 0.0
    private var five: Bool = UserDefaults.standard.object(forKey: "diam.five") as? Bool ?? true
    private var bgName = "t0.jpg"
    private var sparks: [DiamSpark] = []
    private var banner: (text: String, life: Double)? = nil

    private var dragGem: DiamGem?
    private var dragStart = CGPoint.zero
    private var dragOff = CGVector(dx: 0, dy: 0)

    private var timer: Timer?
    private var lastT: CFTimeInterval = 0

    private var recs5: GameRecordsPanel?
    private var recs4: GameRecordsPanel?
    private var recs: GameRecordsPanel? { return five ? recs5 : recs4 }
    private let recsRect = NSRect(x: 344, y: 56, width: 190, height: 480)
    private let newBtn = NSRect(x: 130, y: 12, width: 120, height: 30)
    private let modeBtn = NSRect(x: 260, y: 12, width: 110, height: 30)

    private var colors: [String] { return five ? ["r", "g", "f", "b", "y"] : ["r", "g", "y", "b"] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        recs5 = GameRecordsPanel(key: "diam.records5", host: self)
        recs4 = GameRecordsPanel(key: "diam.records4", host: self)
        recs5?.onFinish = { [weak self] in self?.newGame() }
        recs4?.onFinish = { [weak self] in self?.newGame() }
        newGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate() }

    // MARK: Игра

    private func newGame() {
        recs5?.cancel(); recs4?.cancel()
        grid = Array(repeating: Array(repeating: nil, count: cols), count: rows)
        // 7 стартовых линий без готовых троек
        for r in 0..<7 {
            for c in 0..<cols {
                var ok = colors
                if c >= 2, let a = grid[r][c - 1], let b = grid[r][c - 2], a.color == b.color { ok.removeAll { $0 == a.color } }
                if r >= 2, let a = grid[r - 1][c], let b = grid[r - 2][c], a.color == b.color { ok.removeAll { $0 == a.color } }
                grid[r][c] = DiamGem(color: ok.randomElement()!, col: c, row: r)
            }
        }
        score = 0; over = false; needMatch = false; sparks = []; banner = nil
        dragGem = nil; dragOff = CGVector(dx: 0, dy: 0)
        bgName = "t\(Int.random(in: 0...6)).jpg"
        startTimer()
        needsDisplay = true
    }

    private var allGems: [DiamGem] { return grid.flatMap { $0 }.compactMap { $0 } }

    private var busy: Bool { return allGems.contains { !$0.atRest } }

    /// Кристаллы падают вниз, пока не упрутся
    private func applyGravity() {
        for c in 0..<cols {
            var stack: [DiamGem] = []
            for r in 0..<rows { if let g = grid[r][c] { stack.append(g); grid[r][c] = nil } }
            for (r, g) in stack.enumerated() { grid[r][c] = g; g.row = r; g.col = c }
        }
    }

    /// Новая линия сверху; если она легла в самую верхнюю строку — игра окончена
    private func insertLine() {
        for c in 0..<cols where grid[rows - 1][c] == nil {
            grid[rows - 1][c] = DiamGem(color: colors.randomElement()!, col: c, row: rows - 1)
        }
        applyGravity()
        if grid[rows - 1].contains(where: { $0 != nil }) {
            over = true
            DiamSound.play()
            if score > 0 { recs?.beginEntry(score: score, in: recsRect) }
        }
    }

    /// Ищет тройки и длиннее по строкам и столбцам, добавляет соседей того же цвета, убирает всё найденное
    private func runMatch() {
        var found = Set<DiamCell>()
        func color(_ r: Int, _ c: Int) -> String? {
            guard r >= 0, r < rows, c >= 0, c < cols, let g = grid[r][c], g.dying == 0 else { return nil }
            return g.color
        }
        for r in 0..<rows {
            var c = 0
            while c < cols {
                guard let col = color(r, c) else { c += 1; continue }
                var e = c
                while e + 1 < cols && color(r, e + 1) == col { e += 1 }
                if e - c >= 2 { for k in c...e { found.insert(DiamCell(row: r, col: k)) } }
                c = e + 1
            }
        }
        for c in 0..<cols {
            var r = 0
            while r < rows {
                guard let col = color(r, c) else { r += 1; continue }
                var e = r
                while e + 1 < rows && color(e + 1, c) == col { e += 1 }
                if e - r >= 2 { for k in r...e { found.insert(DiamCell(row: k, col: c)) } }
                r = e + 1
            }
        }
        if found.isEmpty { return }
        // убираются все кристаллы того же цвета, связанные с тройкой по сторонам (по диагонали связи нет);
        // квадрат 2×2 без тройки в ряд не считается
        var stack = Array(found)
        while let cur = stack.popLast() {
            guard let col = color(cur.row, cur.col) else { continue }
            for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                let n = DiamCell(row: cur.row + dr, col: cur.col + dc)
                if !found.contains(n), color(n.row, n.col) == col {
                    found.insert(n); stack.append(n)
                }
            }
        }

        for cell in found {
            guard let g = grid[cell.row][cell.col] else { continue }
            g.dying = dieTime
            burst(at: cell, color: g.color)
        }
        score += found.count
        if found.count > 5 {
            score += found.count
            banner = ("Bonus + \(found.count)", 1.6)
        }
        DiamSound.play()
    }

    private func sparkColor(_ name: String) -> NSColor {
        switch name {
        case "r": return NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.25, alpha: 1)
        case "g": return NSColor(calibratedRed: 0.3, green: 0.9, blue: 0.35, alpha: 1)
        case "b": return NSColor(calibratedRed: 0.3, green: 0.65, blue: 1.0, alpha: 1)
        case "f": return NSColor(calibratedRed: 0.75, green: 0.5, blue: 1.0, alpha: 1)
        default:  return NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.3, alpha: 1)
        }
    }

    private func burst(at c: DiamCell, color: String) {
        let center = CGPoint(x: CGFloat(c.col) * px + gw / 2, y: CGFloat(rows - 1 - c.row) * py + gh / 2)
        for _ in 0..<10 {
            let a = Double.random(in: 0..<(2 * Double.pi)), s = Double.random(in: 40...140)
            sparks.append(DiamSpark(p: center, v: CGVector(dx: CGFloat(cos(a) * s), dy: CGFloat(sin(a) * s)),
                                    life: Double.random(in: 0.3...0.6), color: sparkColor(color)))
        }
        sparks.append(DiamSpark(p: center, v: CGVector(dx: 0, dy: 0), life: 0.3, color: .white))
    }

    // MARK: Таймер

    private func startTimer() {
        if timer != nil { return }
        lastT = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastT)
        lastT = now

        var removed = false
        for g in allGems {
            let dy = Double(g.row) - g.y
            if abs(dy) > 0.0005 { g.y += max(-16 * dt, min(16 * dt, dy)) } else { g.y = Double(g.row) }
            let dx = Double(g.col) - g.x
            if abs(dx) > 0.0005 { g.x += max(-14 * dt, min(14 * dt, dx)) } else { g.x = Double(g.col) }
            if g.dying > 0 {
                g.dying -= dt
                if g.dying <= 0 { grid[g.row][g.col] = nil; removed = true }
            }
        }
        if removed && !allGems.contains(where: { $0.dying > 0 }) {
            applyGravity()
            needMatch = true; matchDelay = 0.08
        }
        if needMatch && !over && !busy {
            matchDelay -= dt
            if matchDelay <= 0 { needMatch = false; runMatch() }
        }
        for i in sparks.indices {
            sparks[i].life -= dt
            sparks[i].p.x += sparks[i].v.dx * CGFloat(dt)
            sparks[i].p.y += sparks[i].v.dy * CGFloat(dt)
        }
        sparks.removeAll { $0.life <= 0 }
        if var b = banner { b.life -= dt; banner = b.life > 0 ? b : nil }
        needsDisplay = true
    }

    // MARK: Мышь

    private func cell(at p: CGPoint) -> DiamCell? {
        let bx = p.x - origin.x, by = p.y - origin.y
        guard bx >= 0, by >= 0 else { return nil }
        let c = Int(bx / px), r = rows - 1 - Int(by / py)
        guard c < cols, r >= 0, r < rows else { return nil }
        return DiamCell(row: r, col: c)
    }

    private var canPlay: Bool { return !over && !busy && !needMatch }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if newBtn.contains(p) { newGame(); return }
        if modeBtn.contains(p) {
            five.toggle()
            UserDefaults.standard.set(five, forKey: "diam.five")
            newGame()
            return
        }
        if over {
            if recs?.entering != true { newGame() }
            return
        }
        guard canPlay, let c = cell(at: p), let g = grid[c.row][c.col] else { return }
        dragGem = g
        dragStart = p
        dragOff = CGVector(dx: 0, dy: 0)
    }

    override func mouseDragged(with e: NSEvent) {
        guard let g = dragGem else { return }
        let p = convert(e.locationInWindow, from: nil)
        let dxc = Double(p.x - dragStart.x) / Double(px)
        let dyc = -Double(p.y - dragStart.y) / Double(py)      // вверх — положительное
        // можно тащить и по диагонали: каждая ось ограничена одной клеткой и краями поля
        var off = CGVector(dx: 0, dy: 0)
        let tx = max(-1, min(1, dxc)), ty = max(-1, min(1, dyc))
        let nc = g.col + Int(tx.rounded(.awayFromZero)), nr = g.row + Int(ty.rounded(.awayFromZero))
        if nc >= 0 && nc < cols { off.dx = CGFloat(tx) }
        if nr >= 0 && nr < rows - 1 { off.dy = CGFloat(ty) }
        dragOff = off
    }

    override func mouseUp(with e: NSEvent) {
        guard let g = dragGem else { return }
        dragGem = nil
        let off = dragOff
        dragOff = CGVector(dx: 0, dy: 0)
        // кристалл остаётся там, где его отпустили, и плавно доедет до своей клетки
        g.x += Double(off.dx)
        g.y += Double(off.dy)
        let moved = abs(off.dx) >= 0.5 || abs(off.dy) >= 0.5
        guard moved else { return }
        let tc = g.col + (abs(off.dx) >= 0.5 ? (off.dx > 0 ? 1 : -1) : 0)
        let tr = g.row + (abs(off.dy) >= 0.5 ? (off.dy > 0 ? 1 : -1) : 0)
        let before = grid.map { $0.map { $0?.color } }
        let other = grid[tr][tc]
        grid[tr][tc] = g
        grid[g.row][g.col] = other
        other?.col = g.col; other?.row = g.row
        g.col = tc; g.row = tr
        applyGravity()
        // кристалл вернулся на то же место (или поменялся с таким же цветом) — поле не изменилось, новой линии нет
        if grid.map({ $0.map { $0?.color } }) == before { return }
        insertLine()
        if !over { needMatch = true; matchDelay = 0.1 } else { applyGravity() }
    }

    // MARK: Рисование

    private let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor(white: 0, alpha: 0.9)
        s.shadowOffset = NSSize(width: 0, height: -1)
        s.shadowBlurRadius = 3
        return s
    }()

    private func plate(_ r: NSRect, alpha: CGFloat = 0.62) {
        NSColor(white: 0, alpha: alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
    }

    private func drawString(_ s: String, _ r: NSRect, size: CGFloat, color: NSColor = .white,
                            align: NSTextAlignment = .left, bold: Bool = false) {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
            .foregroundColor: color, .paragraphStyle: p, .shadow: textShadow]
        (s as NSString).draw(in: r, withAttributes: attrs)
    }

    private func button(_ r: NSRect, _ title: String) {
        NSColor(white: 1, alpha: 0.2).setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        drawString(title, NSRect(x: r.minX, y: r.minY + 7, width: r.width, height: 18), size: 13, align: .center)
    }

    private func gemRect(x: Double, y: Double) -> NSRect {
        return NSRect(x: origin.x + CGFloat(x) * px, y: origin.y + (CGFloat(rows - 1) - CGFloat(y)) * py, width: gw, height: gh)
    }

    private func drawGem(_ g: DiamGem, offset: CGVector = CGVector(dx: 0, dy: 0)) {
        var r = gemRect(x: g.x + Double(offset.dx), y: g.y + Double(offset.dy))
        var alpha: CGFloat = 1
        if g.dying > 0 {
            let k = CGFloat(max(0, g.dying / dieTime))
            r = r.insetBy(dx: r.width * (1 - k) / 2, dy: r.height * (1 - k) / 2)
            alpha = k
        }
        if let img = DiamRes.image(g.color + ".png") {
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        } else {
            sparkColor(g.color).withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // фон-текстура
        if let bg = DiamRes.image(bgName) {
            let s = max(bounds.width / bg.size.width, bounds.height / bg.size.height)
            let w = bg.size.width * s, h = bg.size.height * s
            bg.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.15, alpha: 1).setFill()
            bounds.fill()
        }

        // шапка и подложки: фон меняется, текст должен читаться на любом
        plate(NSRect(x: 10, y: 6, width: bounds.width - 20, height: 42))
        drawString(T("Очки") + ": \(score)", NSRect(x: 20, y: 14, width: 105, height: 26), size: 18, bold: true)
        button(newBtn, T("Новая игра"))
        button(modeBtn, five ? T("5 цветов") : T("4 цвета"))

        let field = NSRect(x: origin.x - 4, y: origin.y - 4, width: CGFloat(cols) * px + 7, height: CGFloat(rows) * py + 7)
        plate(field, alpha: 0.55)
        plate(recsRect.insetBy(dx: -10, dy: -8))
        recs?.draw(in: recsRect)

        // кристаллы (перетаскиваемый — сверху)
        for g in allGems where g !== dragGem { drawGem(g) }
        if let g = dragGem { drawGem(g, offset: dragOff) }

        // искры
        for s in sparks {
            let a = CGFloat(min(1, s.life * 3))
            s.color.withAlphaComponent(a).setFill()
            let r: CGFloat = s.color == .white ? 14 : 3
            NSBezierPath(ovalIn: NSRect(x: origin.x + s.p.x - r, y: origin.y + s.p.y - r, width: r * 2, height: r * 2)).fill()
        }

        // подвал
        plate(NSRect(x: 10, y: field.maxY + 6, width: 530, height: 30))
        drawString(T("Тяните кристалл на соседнюю клетку · три в ряд и связанные с ними исчезают"),
                   NSRect(x: 20, y: field.maxY + 13, width: 510, height: 18), size: 12,
                   color: NSColor(white: 1, alpha: 0.9))

        // надписи
        if let b = banner {
            let k = CGFloat(1.6 - b.life)
            let size = 24 + 26 * min(1, k)
            drawString(b.text, NSRect(x: field.minX, y: field.midY - 60, width: field.width, height: 70), size: size,
                       color: NSColor(calibratedRed: 1, green: 0.9, blue: 0.3, alpha: CGFloat(min(1, b.life * 2))),
                       align: .center, bold: true)
        }
        if over {
            NSColor(white: 0, alpha: 0.6).setFill()
            NSBezierPath(roundedRect: field, xRadius: 8, yRadius: 8).fill()
            drawString(T("Игра окончена"), NSRect(x: field.minX, y: field.midY - 36, width: field.width, height: 40), size: 28,
                       align: .center, bold: true)
            drawString(T("Очки") + ": \(score)   ·   " + T("Нажмите, чтобы начать заново"),
                       NSRect(x: field.minX, y: field.midY + 10, width: field.width, height: 22), size: 14,
                       color: NSColor(white: 1, alpha: 0.9), align: .center)
        }
    }
}

final class DiamWindowController: NSObject, NSWindowDelegate {
    static let shared = DiamWindowController()
    private var window: NSWindow?
    private var game: DiamView?

    func show() {
        if window == nil {
            let size = NSSize(width: 560, height: 700)
            DiamSound.warmUp()
            let v = DiamView(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = v
            w.delegate = self
            if !w.setFrameUsingName("DiamWindow") { w.center() }
            w.setFrameAutosaveName("DiamWindow")
            window = w
            game = v
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = "Diam"
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let g = game { window?.makeFirstResponder(g) }
    }

    @objc private func languageChanged() {
        game?.needsDisplay = true
    }
}

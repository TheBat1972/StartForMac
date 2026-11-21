import Cocoa

// MARK: - JezzBall («Передохни»)
//
// Классика: по полю летают шарики. Щелчок строит стену — она растёт одновременно в обе стороны. Если шарик
// заденет растущую половину стены, половина разрушается и теряется жизнь. Когда стена дошла до краёв,
// участки поля без шариков закрашиваются. Нужно закрыть 75% поля.

/// Простые синтезированные звуки (без файлов): WAV собирается в памяти
private enum JezzSound: Int, CaseIterable {
    case start, close, hit, done, over
    private static var cache: [Int: NSSound] = [:]

    /// ноты подряд: частота Гц (плавно меняется к `to`), длительность с, доля шума 0…1
    private var notes: [(f: Double, to: Double, d: Double, noise: Double)] {
        switch self {
        case .start: return [(500, 900, 0.10, 0)]
        case .close: return [(330, 330, 0.07, 0), (440, 440, 0.07, 0), (660, 660, 0.12, 0)]
        case .hit:   return [(220, 70, 0.28, 0.5)]
        case .done:  return [(523, 523, 0.12, 0), (659, 659, 0.12, 0), (784, 784, 0.12, 0), (1047, 1047, 0.30, 0)]
        case .over:  return [(392, 392, 0.18, 0), (330, 330, 0.18, 0), (262, 262, 0.18, 0), (196, 196, 0.40, 0)]
        }
    }

    private func wav() -> Data {
        let rate = 22050.0
        var samples = [Int16]()
        var phase = 0.0
        for n in notes {
            let count = Int(n.d * rate)
            for i in 0..<count {
                let u = Double(i) / Double(count)
                phase += 2 * Double.pi * (n.f + (n.to - n.f) * u) / rate
                let tone = sin(phase) > 0 ? 1.0 : -1.0
                let v = (tone * (1 - n.noise) + Double.random(in: -1...1) * n.noise) * 0.22 * min(1, (1 - u) * 6)
                samples.append(Int16(max(-1, min(1, v)) * 32767))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + samples.count * 2))
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(samples.count * 2))
        for v in samples { u16(UInt16(bitPattern: v)) }
        return d
    }

    func play() {
        if JezzSound.cache[rawValue] == nil { JezzSound.cache[rawValue] = NSSound(data: wav()) }
        guard let snd = JezzSound.cache[rawValue] else { return }
        JezzSound.warming.remove(rawValue)
        snd.stop()
        snd.volume = 1
        snd.play()
    }

    private static var warming = Set<Int>()

    /// Заранее собирает все звуки и «прогревает» аудиосистему беззвучным запуском, чтобы первый настоящий звук не подвешивал игру
    static func warmUp() {
        for k in JezzSound.allCases {
            if cache[k.rawValue] == nil { cache[k.rawValue] = NSSound(data: k.wav()) }
            guard let snd = cache[k.rawValue] else { continue }
            warming.insert(k.rawValue)
            snd.volume = 0
            snd.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if warming.contains(k.rawValue) { warming.remove(k.rawValue); snd.stop(); snd.volume = 1 }
            }
        }
    }
}


final class JezzView: NSView {
    override var isFlipped: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }

    // MARK: Параметры
    private let cell: CGFloat = 16
    private let cols = 50, rows = 30
    private let fx: CGFloat = 30, fy: CGFloat = 64
    private let ballR: CGFloat = 7
    private let goal = 75
    private let armSpeed: CGFloat = 15      // клеток в секунду

    private enum State { case playing, paused, levelDone, over }
    private struct Ball { var x: CGFloat; var y: CGFloat; var vx: CGFloat; var vy: CGFloat }
    private struct Arm {
        var cells: [(Int, Int)] = []
        var dx = 0, dy = 0
        var startX = 0, startY = 0
        var seed = false                // первая половина несёт ещё и стартовую клетку
        var len: CGFloat = 0
        var done = false
    }

    // MARK: Состояние
    private var filled: [Bool] = []
    private var balls: [Ball] = []
    private var arms: [Arm] = []
    private var horizontal = true
    private var level = 1
    private var score = 0
    private var lives = 2
    private var lifeBonus = 0
    private var state: State = .playing
    private var autoPaused = false
    private var hover: (Int, Int)? = nil
    private var timer: Timer?
    private var lastT: CFTimeInterval = 0
    private var solidPaths: (NSBezierPath, NSBezierPath, NSBezierPath)? = nil
    private var recs: GameRecordsPanel?
    private let recsRect = NSRect(x: 860, y: 64, width: 190, height: 480)

    // MARK: Кнопки
    private let newBtn = NSRect(x: 30, y: 14, width: 130, height: 34)
    private let pauseBtn = NSRect(x: 170, y: 14, width: 110, height: 34)
    private let wallBtn = NSRect(x: 290, y: 14, width: 130, height: 34)

    override init(frame: NSRect) {
        super.init(frame: frame)
        recs = GameRecordsPanel(key: "jezz.records", host: self)
        recs?.onFinish = { [weak self] in self?.newGame() }
        newGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Игра

    private func idx(_ x: Int, _ y: Int) -> Int { return y * cols + x }

    private var fieldRect: NSRect {
        return NSRect(x: fx, y: fy, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
    }

    private func newGame() {
        recs?.cancel()
        level = 1
        score = 0
        setupLevel()
    }

    private func setupLevel() {
        filled = Array(repeating: false, count: cols * rows)
        arms = []
        lives = level + 1
        lifeBonus = 0
        solidPaths = nil
        let speed = min(300, 170 + 12 * CGFloat(level - 1))
        let angles: [CGFloat] = [35, 55, 125, 145, 215, 235, 305, 325]
        balls = []
        for _ in 0..<(level + 1) {
            let a = angles.randomElement()! * .pi / 180
            balls.append(Ball(x: CGFloat.random(in: 3...(CGFloat(cols) - 3)) * cell,
                              y: CGFloat.random(in: 3...(CGFloat(rows) - 3)) * cell,
                              vx: speed * cos(a), vy: speed * sin(a)))
        }
        state = .playing
        autoPaused = false
        startTimer()
        needsDisplay = true
    }

    private func startTimer() {
        if timer != nil { return }
        lastT = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Окно потеряло фокус или закрыто: игра встаёт на паузу сама
    func autoPause() {
        if state == .playing {
            state = .paused
            autoPaused = true
            stopTimer()
            needsDisplay = true
        }
    }

    /// Окно снова показано: продолжаем, если пауза была автоматической
    func resume() {
        if state == .paused && autoPaused {
            state = .playing
            autoPaused = false
            startTimer()
            needsDisplay = true
        }
    }

    private func togglePause() {
        if state == .playing {
            state = .paused
            autoPaused = false
            stopTimer()
        } else if state == .paused {
            state = .playing
            autoPaused = false
            startTimer()
        }
        needsDisplay = true
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.05, now - lastT))
        lastT = now
        guard state == .playing else { return }
        update(dt)
        needsDisplay = true
    }

    // MARK: Физика

    private func isSolid(_ px: CGFloat, _ py: CGFloat) -> Bool {
        let cx = Int(floor(px / cell)), cy = Int(floor(py / cell))
        if cx < 0 || cy < 0 || cx >= cols || cy >= rows { return true }
        return filled[idx(cx, cy)]
    }

    private func moveBalls(_ dt: CGFloat) {
        let r = ballR
        for i in balls.indices {
            var b = balls[i]
            let ox = b.x, oy = b.y
            let nx = b.x + b.vx * dt
            let sx: CGFloat = b.vx > 0 ? 1 : -1
            if isSolid(nx + sx * r, b.y) || isSolid(nx + sx * r, b.y - r * 0.6) || isSolid(nx + sx * r, b.y + r * 0.6) {
                b.vx = -b.vx
            } else {
                b.x = nx
            }
            let ny = b.y + b.vy * dt
            let sy: CGFloat = b.vy > 0 ? 1 : -1
            if isSolid(b.x, ny + sy * r) || isSolid(b.x - r * 0.6, ny + sy * r) || isSolid(b.x + r * 0.6, ny + sy * r) {
                b.vy = -b.vy
            } else {
                b.y = ny
            }
            // угол: шарик попал точно в выступ стены по диагонали
            let dx: CGFloat = b.vx > 0 ? 1 : -1
            let dy: CGFloat = b.vy > 0 ? 1 : -1
            if isSolid(b.x + dx * r * 0.72, b.y + dy * r * 0.72) {
                b.x = ox; b.y = oy
                b.vx = -b.vx; b.vy = -b.vy
            }
            balls[i] = b
        }
    }

    private func ballTouches(_ b: Ball, cellX: Int, cellY: Int) -> Bool {
        let minX = CGFloat(cellX) * cell, minY = CGFloat(cellY) * cell
        let dx = max(minX - b.x, 0, b.x - (minX + cell))
        let dy = max(minY - b.y, 0, b.y - (minY + cell))
        let r = ballR * 0.92
        return dx * dx + dy * dy < r * r
    }

    private func growArms(_ dt: CGFloat) {
        for i in arms.indices where !arms[i].done {
            arms[i].len += armSpeed * dt
            let target = Int(arms[i].len) + (arms[i].seed ? 1 : 0)
            while arms[i].cells.count < target {
                let k = arms[i].cells.count + (arms[i].seed ? 0 : 1)
                let x = arms[i].startX + arms[i].dx * k
                let y = arms[i].startY + arms[i].dy * k
                if x < 0 || y < 0 || x >= cols || y >= rows || filled[idx(x, y)] {
                    arms[i].done = true
                    break
                }
                arms[i].cells.append((x, y))
            }
        }
    }

    private func update(_ dt: CGFloat) {
        moveBalls(dt)
        growArms(dt)

        // шарик задел растущую стену: половина разрушена, минус жизнь
        var i = 0
        while i < arms.count {
            var hit = false
            if !arms[i].done {
                outer: for c in arms[i].cells {
                    for b in balls where ballTouches(b, cellX: c.0, cellY: c.1) { hit = true; break outer }
                }
            }
            if hit {
                arms.remove(at: i)
                lives -= 1
                JezzSound.hit.play()
                if lives <= 0 {
                    lives = 0
                    JezzSound.over.play()
                    state = .over
                    stopTimer()
                    if score > 0 { recs?.beginEntry(score: score, in: recsRect) }
                    return
                }
            } else {
                i += 1
            }
        }

        // дошедшие до края половины становятся твёрдыми
        var added = 0
        var j = 0
        var changed = false
        while j < arms.count {
            if arms[j].done {
                for c in arms[j].cells where !filled[idx(c.0, c.1)] {
                    filled[idx(c.0, c.1)] = true
                    added += 1
                }
                arms.remove(at: j)
                changed = true
            } else {
                j += 1
            }
        }
        if changed {
            JezzSound.close.play()
            added += capture()
            score += added * level
            solidPaths = nil
            if filledPercent >= goal {
                lifeBonus = lives * 50 * level
                score += lifeBonus
                JezzSound.done.play()
                state = .levelDone
                stopTimer()
            }
        }
    }

    /// Закрашивает участки поля, в которых нет шариков; возвращает число закрашенных клеток
    private func capture() -> Int {
        var seen = Array(repeating: false, count: cols * rows)
        var stack: [(Int, Int)] = []
        for b in balls {
            let cx = min(cols - 1, max(0, Int(b.x / cell)))
            let cy = min(rows - 1, max(0, Int(b.y / cell)))
            if !filled[idx(cx, cy)] && !seen[idx(cx, cy)] {
                seen[idx(cx, cy)] = true
                stack.append((cx, cy))
            }
        }
        while let (x, y) = stack.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                if nx < 0 || ny < 0 || nx >= cols || ny >= rows { continue }
                let k = idx(nx, ny)
                if !filled[k] && !seen[k] {
                    seen[k] = true
                    stack.append((nx, ny))
                }
            }
        }
        var n = 0
        for k in 0..<(cols * rows) where !filled[k] && !seen[k] {
            filled[k] = true
            n += 1
        }
        return n
    }

    private var filledPercent: Int {
        let n = filled.reduce(0) { $0 + ($1 ? 1 : 0) }
        return n * 100 / (cols * rows)
    }

    private func startWall(_ cx: Int, _ cy: Int) {
        guard state == .playing, arms.isEmpty, !filled[idx(cx, cy)] else { return }
        var a = Arm(), b = Arm()
        if horizontal { a.dx = -1; b.dx = 1 } else { a.dy = -1; b.dy = 1 }
        a.startX = cx; a.startY = cy; a.seed = true
        b.startX = cx; b.startY = cy
        arms = [a, b]
        JezzSound.start.play()
        growArms(0)
        needsDisplay = true
    }

    // MARK: Мышь и клавиатура

    private func cellAt(_ e: NSEvent) -> (Int, Int)? {
        let p = convert(e.locationInWindow, from: nil)
        let fr = fieldRect
        if !fr.contains(p) { return nil }
        let cx = min(cols - 1, Int((p.x - fx) / cell))
        let cy = min(rows - 1, Int((p.y - fy) / cell))
        return (cx, cy)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(fieldRect, cursor: .crosshair)
    }

    override func mouseMoved(with e: NSEvent) {
        hover = cellAt(e)
        if state != .playing { needsDisplay = true }
    }

    override func mouseExited(with e: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if newBtn.contains(p) { newGame(); return }
        if pauseBtn.contains(p) { togglePause(); return }
        if wallBtn.contains(p) { horizontal.toggle(); needsDisplay = true; return }
        switch state {
        case .over:
            if recs?.entering != true { newGame() }
        case .levelDone:
            level += 1
            setupLevel()
        case .paused:
            togglePause()
        case .playing:
            if let c = cellAt(e) { startWall(c.0, c.1) }
        }
    }

    override func rightMouseDown(with e: NSEvent) {
        horizontal.toggle()
        needsDisplay = true
    }

    override func keyDown(with e: NSEvent) {
        // по кодам клавиш, чтобы работало и в русской раскладке
        switch e.keyCode {
        case 49:            // пробел
            horizontal.toggle()
            needsDisplay = true
        case 35:            // P
            togglePause()
        default:
            super.keyDown(with: e)
        }
    }

    // MARK: Рисование

    private func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    private func drawString(_ s: String, _ rect: NSRect, size: CGFloat, color: NSColor,
                            align: NSTextAlignment = .left, bold: Bool = false) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (s as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps])
    }

    private func drawButton(_ r: NSRect, _ title: String) {
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        NSColor(white: 1, alpha: 0.12).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawString(title, NSRect(x: r.minX, y: r.minY + 8, width: r.width, height: 18), size: 13,
                   color: .white, align: .center)
    }

    /// Контуры твёрдых клеток (в координатах поля): заливка, светлые и тёмные грани
    private func buildSolidPaths() -> (NSBezierPath, NSBezierPath, NSBezierPath) {
        let base = NSBezierPath(), light = NSBezierPath(), dark = NSBezierPath()
        func solid(_ x: Int, _ y: Int) -> Bool {
            if x < 0 || y < 0 || x >= cols || y >= rows { return false }
            return filled[idx(x, y)]
        }
        for y in 0..<rows {
            for x in 0..<cols where filled[idx(x, y)] {
                let px = CGFloat(x) * cell, py = CGFloat(y) * cell
                base.appendRect(NSRect(x: px, y: py, width: cell, height: cell))
                if !solid(x, y - 1) { light.appendRect(NSRect(x: px, y: py, width: cell, height: 2)) }
                if !solid(x - 1, y) { light.appendRect(NSRect(x: px, y: py, width: 2, height: cell)) }
                if !solid(x, y + 1) { dark.appendRect(NSRect(x: px, y: py + cell - 2, width: cell, height: 2)) }
                if !solid(x + 1, y) { dark.appendRect(NSRect(x: px + cell - 2, y: py, width: 2, height: cell)) }
            }
        }
        return (base, light, dark)
    }

    override func draw(_ dirtyRect: NSRect) {
        // фон
        col(0.09, 0.11, 0.17).setFill()
        bounds.fill()

        // шапка
        drawButton(newBtn, T("Новая игра"))
        drawButton(pauseBtn, state == .paused ? T("Продолжить") : T("Пауза"))
        drawButton(wallBtn, horizontal ? T("Стена") + " ↔" : T("Стена") + " ↕")
        drawString(String(repeating: "♥", count: max(0, lives)), NSRect(x: 440, y: 17, width: 110, height: 28),
                   size: 20, color: col(1, 0.35, 0.40))
        drawString(T("Уровень") + ": \(level)   " + T("Очки") + ": \(score)",
                   NSRect(x: 560, y: 22, width: 270, height: 20), size: 13, color: .white, align: .right)

        // поле
        let fr = fieldRect
        col(0.03, 0.05, 0.10).setFill()
        fr.fill()

        NSGraphicsContext.saveGraphicsState()
        let tr = NSAffineTransform()
        tr.translateX(by: fx, yBy: fy)
        tr.concat()

        if solidPaths == nil { solidPaths = buildSolidPaths() }
        if let (base, light, dark) = solidPaths {
            col(0.36, 0.52, 0.78).setFill()
            base.fill()
            col(0.66, 0.80, 0.98).setFill()
            light.fill()
            col(0.17, 0.27, 0.48).setFill()
            dark.fill()
        }

        // растущие стены
        for a in arms {
            for (k, c) in a.cells.enumerated() {
                let r = NSRect(x: CGFloat(c.0) * cell, y: CGFloat(c.1) * cell, width: cell, height: cell)
                let tip = (k == a.cells.count - 1 && !a.done)
                (tip ? col(0.85, 1, 1) : col(0.35, 0.92, 1)).setFill()
                r.fill()
                col(1, 1, 1, 0.55).setStroke()
                NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
        }

        // шарики
        for b in balls {
            let r = NSRect(x: b.x - ballR, y: b.y - ballR, width: ballR * 2, height: ballR * 2)
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: r.offsetBy(dx: 2, dy: 3)).fill()
            let g = NSGradient(colors: [col(1, 0.92, 0.92), col(0.95, 0.22, 0.25), col(0.45, 0.04, 0.10)])
            g?.draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: NSPoint(x: -0.35, y: -0.35))
        }

        // подсказка: куда пойдёт стена
        if state == .playing, arms.isEmpty, let h = hover, !filled[idx(h.0, h.1)] {
            let cx = CGFloat(h.0) * cell + cell / 2, cy = CGFloat(h.1) * cell + cell / 2
            col(1, 1, 1, 0.22).setFill()
            if horizontal {
                NSRect(x: 0, y: cy - 1, width: CGFloat(cols) * cell, height: 2).fill()
            } else {
                NSRect(x: cx - 1, y: 0, width: 2, height: CGFloat(rows) * cell).fill()
            }
            col(1, 1, 1, 0.9).setFill()
            let tri = NSBezierPath()
            if horizontal {
                tri.move(to: NSPoint(x: cx - 6, y: cy)); tri.line(to: NSPoint(x: cx - 14, y: cy - 5)); tri.line(to: NSPoint(x: cx - 14, y: cy + 5)); tri.close()
                tri.move(to: NSPoint(x: cx + 6, y: cy)); tri.line(to: NSPoint(x: cx + 14, y: cy - 5)); tri.line(to: NSPoint(x: cx + 14, y: cy + 5)); tri.close()
            } else {
                tri.move(to: NSPoint(x: cx, y: cy - 6)); tri.line(to: NSPoint(x: cx - 5, y: cy - 14)); tri.line(to: NSPoint(x: cx + 5, y: cy - 14)); tri.close()
                tri.move(to: NSPoint(x: cx, y: cy + 6)); tri.line(to: NSPoint(x: cx - 5, y: cy + 14)); tri.line(to: NSPoint(x: cx + 5, y: cy + 14)); tri.close()
            }
            tri.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        // рамка поля
        col(0.55, 0.70, 0.95, 0.5).setStroke()
        let fb = NSBezierPath(rect: fr.insetBy(dx: -1, dy: -1))
        fb.lineWidth = 2
        fb.stroke()

        recs?.draw(in: recsRect)

        // подвал
        drawString(T("Клик — построить стену · правый клик или пробел — повернуть стену"),
                   NSRect(x: 30, y: fr.maxY + 12, width: 560, height: 18), size: 12, color: NSColor(white: 1, alpha: 0.65))
        drawString(T("Заполнено") + ": \(filledPercent)% " + T("из") + " \(goal)%",
                   NSRect(x: 560, y: fr.maxY + 12, width: 270, height: 18), size: 12, color: .white, align: .right)

        // завеса и надписи
        var title = "", sub = ""
        switch state {
        case .paused:
            title = T("Пауза"); sub = T("Нажмите, чтобы продолжить")
        case .levelDone:
            title = T("Уровень") + " \(level) " + T("пройден!")
            sub = T("Бонус за жизни") + ": +\(lifeBonus)   ·   " + T("Нажмите, чтобы продолжить")
        case .over:
            title = T("Игра окончена")
            sub = T("Очки") + ": \(score)   ·   " + T("Нажмите, чтобы начать заново")
        case .playing:
            break
        }
        if !title.isEmpty {
            NSColor(white: 0, alpha: 0.58).setFill()
            fr.fill()
            drawString(title, NSRect(x: fr.minX, y: fr.midY - 36, width: fr.width, height: 40), size: 30,
                       color: .white, align: .center, bold: true)
            drawString(sub, NSRect(x: fr.minX, y: fr.midY + 10, width: fr.width, height: 22), size: 15,
                       color: NSColor(white: 1, alpha: 0.85), align: .center)
        }
    }
}

final class JezzWindowController: NSObject, NSWindowDelegate {
    static let shared = JezzWindowController()
    private var window: NSWindow?
    private var game: JezzView?

    private var title: String { return "JezzBall" }

    func show() {
        if window == nil {
            let size = NSSize(width: 1070, height: 600)
            JezzSound.warmUp()
            let v = JezzView(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = v
            w.delegate = self
            if !w.setFrameUsingName("JezzBallWindow") { w.center() }
            w.setFrameAutosaveName("JezzBallWindow")
            window = w
            game = v
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = title
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let g = game {
            window?.makeFirstResponder(g)
            g.resume()
        }
    }

    @objc private func languageChanged() {
        game?.needsDisplay = true
    }

    func windowDidResignKey(_ notification: Notification) { game?.autoPause() }
    func windowWillClose(_ notification: Notification) { game?.autoPause() }
}

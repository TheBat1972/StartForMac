// «Передохни»: Arcan — классический арканоид, перенесённый с Qt/C++ («SnakeLive/Arkan») на Swift.
// Кирпичи с бонусами оригинала: неубиваемая стенка снизу, пробивной шар с широкой битой, ускорение, замедление,
// ещё один шар и сброс эффектов. Уровни, три жизни, рекорды. Картинки и звуки — в папке ArcanRes внутри приложения.
import AppKit

// MARK: - Ресурсы и звуки

private enum ArcanRes {
    private static let dir: URL? = Bundle.main.resourceURL?.appendingPathComponent("ArcanRes")
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let i = images[name] { return i }
        guard let u = dir?.appendingPathComponent(name), let i = NSImage(contentsOf: u) else { return nil }
        images[name] = i
        return i
    }

    static func url(_ name: String) -> URL? { return dir?.appendingPathComponent(name) }
}

private enum ArcanSound: Int {
    case ping, bat, life, win, over
    private static var cache: [Int: NSSound] = [:]

    /// (частота Гц, длительность с) — ноты подряд, прямоугольная волна как в старых играх
    private func notes() -> [(Double, Double)] {
        switch self {
        case .ping: return []
        case .bat:  return [(330, 0.05)]
        case .life: return [(440, 0.12), (330, 0.12), (220, 0.25)]
        case .win:  return [(523, 0.1), (659, 0.1), (784, 0.1), (1047, 0.25)]
        case .over: return [(392, 0.15), (330, 0.15), (262, 0.15), (196, 0.4)]
        }
    }

    private func wav() -> Data {
        let rate = 22050.0
        var samples = [Int16]()
        var phase = 0.0
        for (f, d) in notes() {
            let count = Int(d * rate)
            for i in 0..<count {
                let u = Double(i) / Double(count)
                phase += 2 * Double.pi * f / rate
                let v = (sin(phase) > 0 ? 1.0 : -1.0) * 0.2 * min(1, (1 - u) * 5)
                samples.append(Int16(max(-1, min(1, v)) * 32767))
            }
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + samples.count * 2))
        data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        data.append("data".data(using: .ascii)!); u32(UInt32(samples.count * 2))
        for v in samples { u16(UInt16(bitPattern: v)) }
        return data
    }

    private func sound() -> NSSound? {
        if let s = ArcanSound.cache[rawValue] { return s }
        let s: NSSound?
        if self == .ping {
            s = ArcanRes.url("ping.wav").flatMap { NSSound(contentsOf: $0, byReference: false) }
        } else {
            s = NSSound(data: wav())
        }
        if let s = s { ArcanSound.cache[rawValue] = s }
        return s
    }

    func play() {
        guard let s = sound() else { return }
        s.stop()
        s.volume = 1
        s.play()
    }

    /// Собирает звуки заранее и беззвучно запускает — первый настоящий звук не подвешивает игру
    static func warmUp() {
        for k in [ArcanSound.ping, .bat, .life, .win, .over] {
            guard let s = k.sound() else { continue }
            s.volume = 0
            s.play()
            s.stop()
        }
    }
}

// MARK: - Игра

private struct ArcanBrick {
    var rect: CGRect
    var tip: Int            // 1, 2 — обычные; 3 — два удара; 4 — три удара; 5…10 — бонусы
    var hits: Int           // сколько ударов ещё нужно
    var bump = 0.0          // «подпрыгивание» после удара
    var points: Int { return tip <= 2 ? 10 : (tip == 3 ? 20 : (tip == 4 ? 30 : 15)) }
}

private struct ArcanBall {
    var p: CGPoint          // центр
    var d: CGVector         // единичное направление
}

private struct ArcanFloat {
    var text: String
    var p: CGPoint
    var life: Double
}

final class ArcanView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private enum State { case ready, playing, paused, levelDone, over }

    // поле 400×600, как в оригинале
    private let W: CGFloat = 400, H: CGFloat = 600
    private let origin = CGPoint(x: 20, y: 56)
    private let batY: CGFloat = 548
    private let wallY: CGFloat = 585

    private var bricks: [ArcanBrick] = []
    private var balls: [ArcanBall] = []
    private var batX: CGFloat = 170
    private var level = 1, score = 0, lives = 3
    private var state: State = .ready
    private var autoPaused = false
    private var floats: [ArcanFloat] = []
    private var bgName = "scr1.jpg"

    // эффекты бонусов: оставшееся время, секунды
    private var wallT = 0.0, bigT = 0.0, speedT = 0.0
    private var speedMul = 1.0
    private var leftDown = false, rightDown = false

    private var timer: Timer?
    private var lastT: CFTimeInterval = 0

    private var recs: GameRecordsPanel?
    private let recsRect = NSRect(x: 470, y: 56, width: 190, height: 480)
    private let newBtn = NSRect(x: 150, y: 12, width: 120, height: 30)
    private let pauseBtn = NSRect(x: 280, y: 12, width: 110, height: 30)

    private var big: Bool { return bigT > 0 }
    private var ballR: CGFloat { return big ? 15 : 10 }
    private var batW: CGFloat { return big ? 100 : 70 }
    private var baseSpeed: Double { return 260 * min(1.6, 1 + 0.06 * Double(level - 1)) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        recs = GameRecordsPanel(key: "arcan.records", host: self)
        recs?.onFinish = { [weak self] in self?.newGame() }
        newGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    // MARK: Уровни

    private func newGame() {
        recs?.cancel()
        level = 1; score = 0; lives = 3
        setupLevel()
    }

    private func setupLevel() {
        buildBricks()
        resetBall()
        bgName = "scr\(Int.random(in: 1...14)).jpg"
        floats = []
        autoPaused = false
        startTimer()
        needsDisplay = true
    }

    /// Сетка 10 столбцов, левая половина случайная, правая — зеркальная (как в оригинале); с уровнем строк больше
    private func buildBricks() {
        bricks = []
        let rows = min(9, 3 + level)
        for r in 0..<rows {
            for c in 0..<5 {
                if Double.random(in: 0...1) > 0.78 { continue }
                let roll = Double.random(in: 0...1)
                let heavy = min(0.35, 0.05 * Double(level))
                var tip: Int
                if roll < 0.10 { tip = Int.random(in: 5...10) }
                else if roll < 0.10 + heavy / 2 { tip = 4 }
                else if roll < 0.10 + heavy { tip = 3 }
                else { tip = Int.random(in: 1...2) }
                let y = 44 + CGFloat(r) * 32
                for x in [CGFloat(c) * 40, W - 40 - CGFloat(c) * 40] {
                    bricks.append(ArcanBrick(rect: CGRect(x: x, y: y, width: 40, height: 30), tip: tip,
                                             hits: tip == 3 ? 2 : (tip == 4 ? 3 : 1)))
                }
            }
        }
        if bricks.isEmpty { bricks.append(ArcanBrick(rect: CGRect(x: 180, y: 44, width: 40, height: 30), tip: 1, hits: 1)) }
    }

    /// Шар на бите, эффекты сброшены; ждёт запуска
    private func resetBall() {
        wallT = 0; bigT = 0; speedT = 0; speedMul = 1
        balls = [ArcanBall(p: CGPoint(x: batX + batW / 2, y: batY - ballR - 1), d: CGVector(dx: 0, dy: -1))]
        state = .ready
    }

    private func launch() {
        guard state == .ready, !balls.isEmpty else { return }
        let a = Double.random(in: -0.45...0.45)
        balls[0].d = CGVector(dx: CGFloat(sin(a)), dy: -CGFloat(cos(a)))
        state = .playing
        ArcanSound.ping.play()
        needsDisplay = true
    }

    // MARK: Таймер и физика

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

    private func clampBat() { batX = max(0, min(W - batW, batX)) }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastT)
        lastT = now

        if state == .playing || state == .ready {
            // бита с клавиатуры
            if leftDown { batX -= CGFloat(420 * dt) }
            if rightDown { batX += CGFloat(420 * dt) }
            clampBat()
        }
        if state == .ready, !balls.isEmpty { balls[0].p = CGPoint(x: batX + batW / 2, y: batY - ballR - 1) }

        if state == .playing {
            wallT = max(0, wallT - dt)
            if bigT > 0 { bigT -= dt; if bigT <= 0 { bigT = 0; clampBat() } }
            if speedT > 0 { speedT -= dt; if speedT <= 0 { speedT = 0; speedMul = 1 } }
            let steps = 2
            for _ in 0..<steps { moveBalls(dt / Double(steps)) }
        }
        for i in bricks.indices where bricks[i].bump > 0 { bricks[i].bump = max(0, bricks[i].bump - dt * 5) }
        for i in floats.indices { floats[i].life -= dt; floats[i].p.y -= CGFloat(30 * dt) }
        floats.removeAll { $0.life <= 0 }
        needsDisplay = true
    }

    private func moveBalls(_ dt: Double) {
        let speed = CGFloat(baseSpeed * speedMul * dt)
        var lost: [Int] = []
        var newBalls: [ArcanBall] = []
        for i in balls.indices {
            var b = balls[i]
            b.p.x += b.d.dx * speed
            b.p.y += b.d.dy * speed
            let r = ballR

            // стены
            if b.p.x - r < 0 { b.p.x = r; b.d.dx = abs(b.d.dx) }
            if b.p.x + r > W { b.p.x = W - r; b.d.dx = -abs(b.d.dx) }
            if b.p.y - r < 0 { b.p.y = r; b.d.dy = abs(b.d.dy) }

            // временная стенка снизу
            if wallT > 0 && b.p.y + r >= wallY && b.d.dy > 0 {
                b.p.y = wallY - r
                b.d.dy = -abs(b.d.dy)
                ArcanSound.ping.play()
            }

            // бита
            if b.d.dy > 0 && b.p.y + r >= batY && b.p.y - r <= batY + 14
                && b.p.x + r > batX && b.p.x - r < batX + batW {
                let rel = max(-1, min(1, (b.p.x - (batX + batW / 2)) / (batW / 2 + r)))
                let a = Double(rel) * 1.05            // до ≈60° от вертикали
                b.d = CGVector(dx: CGFloat(sin(a)), dy: -CGFloat(cos(a)))
                b.p.y = batY - r
                ArcanSound.ping.play()
            }

            // кирпичи
            var hitOne = false
            var k = 0
            while k < bricks.count {
                let br = bricks[k].rect
                let cx = max(br.minX, min(b.p.x, br.maxX)), cy = max(br.minY, min(b.p.y, br.maxY))
                let dx = b.p.x - cx, dy = b.p.y - cy
                if dx * dx + dy * dy < r * r {
                    ArcanSound.ping.play()
                    let tip = bricks[k].tip
                    if !big && !hitOne {
                        // отскок по оси с меньшим проникновением
                        let ox = (r + br.width / 2) - abs(b.p.x - br.midX)
                        let oy = (r + br.height / 2) - abs(b.p.y - br.midY)
                        if ox < oy { b.d.dx = b.p.x < br.midX ? -abs(b.d.dx) : abs(b.d.dx); b.p.x += b.p.x < br.midX ? -ox : ox }
                        else { b.d.dy = b.p.y < br.midY ? -abs(b.d.dy) : abs(b.d.dy); b.p.y += b.p.y < br.midY ? -oy : oy }
                        hitOne = true
                    }
                    bricks[k].hits -= 1
                    bricks[k].bump = 1
                    if bricks[k].hits <= 0 || big {
                        score += bricks[k].points
                        floats.append(ArcanFloat(text: "+\(bricks[k].points)", p: CGPoint(x: br.midX, y: br.midY), life: 0.9))
                        bricks.remove(at: k)
                        applyBonus(tip, newBalls: &newBalls)
                    } else {
                        k += 1
                    }
                    if !big { break }
                } else {
                    k += 1
                }
            }

            // шар ушёл вниз
            if b.p.y - r > H - 10 { lost.append(i) }
            balls[i] = b
        }
        for i in lost.reversed() { balls.remove(at: i) }
        balls.append(contentsOf: newBalls)

        if bricks.isEmpty {
            state = .levelDone
            ArcanSound.win.play()
            needsDisplay = true
            return
        }
        if balls.isEmpty { loseLife() }
    }

    private func applyBonus(_ tip: Int, newBalls: inout [ArcanBall]) {
        switch tip {
        case 5: wallT = 20
        case 6: wallT = 0; bigT = 0; speedT = 0; speedMul = 1; clampBat()
        case 7: bigT = 20
        case 8: speedMul = 1.6; speedT = 12
        case 9: speedMul = 0.55; speedT = 20
        case 10:
            if let b = balls.first {
                let a = Double.random(in: 0..<(2 * Double.pi))
                newBalls.append(ArcanBall(p: b.p, d: CGVector(dx: CGFloat(cos(a)), dy: -abs(CGFloat(sin(a))) - 0.3)))
            }
        default: break
        }
    }

    private func loseLife() {
        lives -= 1
        if lives <= 0 {
            state = .over
            stopTimer()
            ArcanSound.over.play()
            needsDisplay = true
            if score > 0 { recs?.beginEntry(score: score, in: recsRect) }
        } else {
            ArcanSound.life.play()
            resetBall()
        }
    }

    private func setPaused(_ on: Bool) {
        if on {
            guard state == .playing else { return }
            state = .paused
            leftDown = false; rightDown = false
        } else {
            guard state == .paused else { return }
            state = .playing
            lastT = CACurrentMediaTime()
        }
        autoPaused = false
        needsDisplay = true
    }

    /// Окно потеряло фокус или закрыто: игра встаёт на паузу сама
    func autoPause() {
        if state == .playing { setPaused(true); autoPaused = true }
        leftDown = false; rightDown = false
    }

    /// Окно снова показано: продолжаем, если пауза была автоматической
    func resume() {
        if state == .paused && autoPaused { setPaused(false) }
    }

    // MARK: Управление

    private func action() {
        switch state {
        case .ready: launch()
        case .playing: setPaused(true)
        case .paused: setPaused(false)
        case .levelDone: level += 1; setupLevel()
        case .over: if recs?.entering != true { newGame() }
        }
    }

    override func keyDown(with e: NSEvent) {
        // по кодам клавиш, чтобы работало и в русской раскладке
        switch e.keyCode {
        case 123, 0: leftDown = true
        case 124, 2: rightDown = true
        case 49: if !e.isARepeat { action() }
        case 35: if !e.isARepeat { if state == .playing { setPaused(true) } else if state == .paused { setPaused(false) } }
        default: super.keyDown(with: e)
        }
    }

    override func keyUp(with e: NSEvent) {
        switch e.keyCode {
        case 123, 0: leftDown = false
        case 124, 2: rightDown = false
        default: super.keyUp(with: e)
        }
    }

    private func moveBat(_ e: NSEvent) {
        guard state == .playing || state == .ready else { return }
        let p = convert(e.locationInWindow, from: nil)
        batX = p.x - origin.x - batW / 2
        clampBat()
    }

    override func mouseMoved(with e: NSEvent) { moveBat(e) }
    override func mouseDragged(with e: NSEvent) { moveBat(e) }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if newBtn.contains(p) { newGame(); return }
        if pauseBtn.contains(p) {
            if state == .playing { setPaused(true) } else if state == .paused { setPaused(false) }
            return
        }
        moveBat(e)
        action()
    }

    // MARK: Рисование

    /// Тень под текстом — читается на любом из фонов
    private let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor(white: 0, alpha: 0.9)
        s.shadowOffset = NSSize(width: 0, height: -1)
        s.shadowBlurRadius = 3
        return s
    }()

    private func plate(_ r: NSRect) {
        NSColor(white: 0, alpha: 0.62).setFill()
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

    @discardableResult
    private func drawImage(_ name: String, in r: NSRect, alpha: CGFloat = 1) -> Bool {
        guard let img = ArcanRes.image(name) else { return false }
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        return true
    }

    private func R(_ r: CGRect) -> NSRect { return NSRect(x: origin.x + r.minX, y: origin.y + r.minY, width: r.width, height: r.height) }

    private func button(_ r: NSRect, _ title: String, enabled: Bool = true) {
        NSColor(white: 1, alpha: enabled ? 0.2 : 0.08).setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        drawString(title, NSRect(x: r.minX, y: r.minY + 7, width: r.width, height: 18), size: 13,
                   color: NSColor(white: 1, alpha: enabled ? 1 : 0.5), align: .center)
    }

    override func draw(_ dirtyRect: NSRect) {
        // фон
        if let bg = ArcanRes.image(bgName) {
            let s = max(bounds.width / bg.size.width, bounds.height / bg.size.height)
            let w = bg.size.width * s, h = bg.size.height * s
            bg.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedRed: 0.08, green: 0.1, blue: 0.2, alpha: 1).setFill()
            bounds.fill()
        }

        // тёмные подложки под надписями: фоны разные, белый текст должен читаться на всех
        plate(NSRect(x: 10, y: 6, width: bounds.width - 20, height: 42))
        plate(NSRect(x: 10, y: origin.y + H + 6, width: 530, height: 30))

        // шапка
        drawString(T("Очки") + ": \(score)", NSRect(x: 20, y: 14, width: 125, height: 26), size: 18, bold: true)
        button(newBtn, T("Новая игра"))
        button(pauseBtn, state == .paused ? T("Продолжить") : T("Пауза"), enabled: state == .playing || state == .paused)
        drawString(T("Уровень") + " \(level)   " + T("Жизни") + ": \(lives)",
                   NSRect(x: 400, y: 16, width: 260, height: 22), size: 14, align: .right)

        // поле
        let field = NSRect(x: origin.x, y: origin.y, width: W, height: H)
        NSColor(white: 0, alpha: 0.6).setFill()
        field.fill()
        NSColor(white: 1, alpha: 0.5).setStroke()
        NSBezierPath(rect: field.insetBy(dx: -1, dy: -1)).stroke()

        // кирпичи
        for b in bricks {
            let lift = CGFloat(sin(b.bump * Double.pi)) * 6
            let r = R(b.rect).insetBy(dx: 1, dy: 3).offsetBy(dx: 0, dy: -lift)
            let name = b.tip == 8 ? "rb.png" : "\(b.tip).png"
            let alpha: CGFloat = (b.tip == 3 && b.hits == 1) || (b.tip == 4 && b.hits < 3) ? (b.hits == 1 ? 0.55 : 0.8) : 1
            if !drawImage(name, in: r, alpha: alpha) {
                NSColor(calibratedHue: CGFloat(b.tip) / 11, saturation: 0.6, brightness: 0.9, alpha: alpha).setFill()
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            }
        }

        // стенка
        if wallT > 0 {
            let blink = wallT < 3 && Int(wallT * 4) % 2 == 0
            if !blink && !drawImage("8.png", in: R(CGRect(x: 0, y: wallY, width: W, height: 10))) {
                NSColor.cyan.setFill()
                R(CGRect(x: 0, y: wallY, width: W, height: 6)).fill()
            }
        }

        // бита
        let batRect = R(CGRect(x: batX, y: batY - 8, width: batW, height: batW * 0.5))
        if !drawImage("k.png", in: batRect) {
            NSColor.lightGray.setFill()
            NSBezierPath(roundedRect: R(CGRect(x: batX, y: batY, width: batW, height: 14)), xRadius: 6, yRadius: 6).fill()
        }

        // шары
        let ballName = speedMul > 1 ? "r.png" : (speedMul < 1 ? "s.png" : "b.png")
        for b in balls {
            let r = NSRect(x: origin.x + b.p.x - ballR, y: origin.y + b.p.y - ballR, width: ballR * 2, height: ballR * 2)
            if !drawImage(ballName, in: r) {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: r).fill()
            }
        }

        // всплывающие очки
        for f in floats {
            drawString(f.text, NSRect(x: origin.x + f.p.x - 25, y: origin.y + f.p.y - 8, width: 50, height: 16), size: 13,
                       color: NSColor(calibratedRed: 1, green: 0.9, blue: 0.4, alpha: CGFloat(min(1, f.life * 2))),
                       align: .center, bold: true)
        }

        // подвал
        drawString(T("Мышь или стрелки/A·D — бита · пробел или клик — запуск и пауза"),
                   NSRect(x: 20, y: origin.y + H + 13, width: 520, height: 18), size: 12,
                   color: NSColor(white: 1, alpha: 0.9))

        // рекорды
        plate(recsRect.insetBy(dx: -10, dy: -8))
        recs?.draw(in: recsRect)

        // завеса и надписи
        var title = "", sub = ""
        switch state {
        case .ready:
            if level == 1 && score == 0 { title = "Arcan" }
            sub = T("Нажмите пробел или клик, чтобы запустить шар")
        case .paused:
            title = T("Пауза"); sub = T("Нажмите, чтобы продолжить")
        case .levelDone:
            title = T("Уровень") + " \(level) " + T("пройден!"); sub = T("Нажмите, чтобы продолжить")
        case .over:
            title = T("Игра окончена")
            sub = T("Очки") + ": \(score)   ·   " + T("Нажмите, чтобы начать заново")
        case .playing:
            break
        }
        if !sub.isEmpty {
            if state != .ready {
                NSColor(white: 0, alpha: 0.58).setFill()
                field.fill()
            }
            let y = state == .ready ? field.midY + 60 : field.midY
            if !title.isEmpty {
                drawString(title, NSRect(x: field.minX, y: y - 36, width: field.width, height: 40), size: 30, align: .center, bold: true)
            }
            drawString(sub, NSRect(x: field.minX, y: y + 10, width: field.width, height: 22), size: 15,
                       color: NSColor(white: 1, alpha: 0.85), align: .center)
        }
    }
}

final class ArcanWindowController: NSObject, NSWindowDelegate {
    static let shared = ArcanWindowController()
    private var window: NSWindow?
    private var game: ArcanView?

    func show() {
        if window == nil {
            let size = NSSize(width: 690, height: 690)
            ArcanSound.warmUp()
            let v = ArcanView(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = v
            w.delegate = self
            w.acceptsMouseMovedEvents = true
            if !w.setFrameUsingName("ArcanWindow") { w.center() }
            w.setFrameAutosaveName("ArcanWindow")
            window = w
            game = v
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = "Arcan"
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

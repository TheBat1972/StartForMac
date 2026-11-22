// «Передохни»: Snake — змейка с мультяшной графикой и звуками из iOS-игры «Удафф» (проект Snake).
// Поле 24×20 с бордюром, 12 кустов репейника (препятствия), фрукты каждые 3,7 с: еда ускоряет змею, подарок даёт бонус. Змея ползёт плавно и анимирует поедание: открывает рот, когда еда рядом, фрукт уменьшается
// и исчезает во рту, по телу бежит «комок», а когда он доходит до хвоста — змея вырастает. Девять скинов (кнопка «Скин»).
// Картинки и звуки — в папке SnakeRes внутри приложения; рекорды — как в других играх.
import AppKit

// MARK: - Ресурсы

private enum SnakeRes {
    private static let dir: URL? = Bundle.main.resourceURL?.appendingPathComponent("SnakeRes")
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let i = images[name] { return i }
        guard let u = dir?.appendingPathComponent(name + ".png"), let i = NSImage(contentsOf: u) else { return nil }
        images[name] = i
        return i
    }

    static func url(_ name: String) -> URL? { return dir?.appendingPathComponent(name) }
}

private enum SnakeSound: String {
    case eat = "hrum.wav", die = "end.wav", box = "priz.wav"
    private static var cache: [String: NSSound] = [:]

    private func sound() -> NSSound? {
        if let s = SnakeSound.cache[rawValue] { return s }
        guard let u = SnakeRes.url(rawValue), let s = NSSound(contentsOf: u, byReference: false) else { return nil }
        SnakeSound.cache[rawValue] = s
        return s
    }

    func play() {
        guard let s = sound() else { return }
        s.stop()
        s.volume = 1
        s.play()
    }

    /// Загружает звуки заранее и беззвучно запускает их — первый настоящий звук не подвешивает игру
    static func warmUp() {
        for k in [SnakeSound.eat, .die, .box] {
            guard let s = k.sound() else { continue }
            s.volume = 0
            s.play()
            s.stop()
        }
    }
}

// MARK: - Игра

private struct SnakeCell: Equatable {
    var x: Int
    var y: Int
    static prefix func - (c: SnakeCell) -> SnakeCell { return SnakeCell(x: -c.x, y: -c.y) }
}

private enum SnakeThingKind {
    case food, obstacle, box
}

private struct SnakeThing {
    var cell: SnakeCell
    var kind: SnakeThingKind
    var variant = 1               // фрукт 1…9; у репейника 0 или 2 (цвет цветка)
    var points = 0
    var seed = Double.random(in: 0...6)
}

/// Съеденный предмет: уменьшается и исчезает во рту, пока голова к нему подъезжает
private struct SnakeEaten {
    var thing: SnakeThing
    var age = 0.0
    var duration: Double
}

private struct SnakeFloat {
    var text: String
    var p: CGPoint
    var life: Double
}

final class SnakeView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private enum State { case ready, playing, paused, over }

    // поле: клетки 1…24 по x и 1…20 по y, нулевая и последняя строка/столбец — бордюр
    private let maxX = 24, maxY = 20
    private let cell: CGFloat = 28
    private let origin = CGPoint(x: 20, y: 56)

    private var snake: [SnakeCell] = []
    private var prevSnake: [SnakeCell] = []   // положение до последнего шага — для плавного движения
    private var dir = SnakeCell(x: 1, y: 0)
    private var queue: [SnakeCell] = []
    private var things: [SnakeThing] = []
    private var eaten: [SnakeEaten] = []
    private var floats: [SnakeFloat] = []
    private var waves: [Double] = []          // «комки» еды, бегущие по телу: номер сегмента
    private var pendingGrow = 0               // сколько комков дошло до хвоста — на столько вырастем
    private var chomp = 0.0                   // сколько ещё секунд голова «жуёт»
    private var score = 0
    private var stepMs = 700.0                // длительность шага; еда уменьшает, подарок увеличивает
    private var state: State = .ready
    private var autoPaused = false
    private var stepAcc = 0.0, mealAcc = 0.0
    private var lastT: CFTimeInterval = 0
    private var timer: Timer?
    private var skin: Int = max(1, min(9, UserDefaults.standard.integer(forKey: "snake.skin")))
    private var texture = 0

    private var recs: GameRecordsPanel?
    private let recsRect = NSRect(x: 778, y: 56, width: 190, height: 480)
    private let newBtn = NSRect(x: 150, y: 12, width: 120, height: 30)
    private let skinBtn = NSRect(x: 280, y: 12, width: 110, height: 30)
    private let pauseBtn = NSRect(x: 400, y: 12, width: 110, height: 30)

    override init(frame: NSRect) {
        super.init(frame: frame)
        recs = GameRecordsPanel(key: "snake.records", host: self)
        recs?.onFinish = { [weak self] in self?.newGame() }
        newGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate() }

    // MARK: Правила

    private func newGame() {
        recs?.cancel()
        snake = [SnakeCell(x: 4, y: 4), SnakeCell(x: 3, y: 4), SnakeCell(x: 2, y: 4)]
        prevSnake = snake
        dir = SnakeCell(x: 1, y: 0)
        queue = []
        things = []
        eaten = []; floats = []; waves = []
        pendingGrow = 0; chomp = 0
        score = 0
        stepMs = 700
        stepAcc = 0; mealAcc = 0
        texture = Int.random(in: 0...5)
        // 12 кустов репейника — не на строке, где стоит змея
        var tries = 0
        while things.filter({ $0.kind == .obstacle }).count < 12 && tries < 400 {
            tries += 1
            let c = SnakeCell(x: Int.random(in: 1...maxX), y: Int.random(in: 1...maxY))
            if c.y != 4 && !occupied(c) {
                things.append(SnakeThing(cell: c, kind: .obstacle, variant: Bool.random() ? 0 : 2))
            }
        }
        for _ in 0..<6 { addMeal() }
        state = .ready
        autoPaused = false
        startTimer()
        needsDisplay = true
    }

    private func occupied(_ c: SnakeCell) -> Bool {
        return snake.contains(c) || things.contains { $0.cell == c }
    }

    /// Новый предмет на свободной клетке: чаще фрукт, изредка подарок
    private func addMeal() {
        for _ in 0..<40 {
            let c = SnakeCell(x: Int.random(in: 1...maxX), y: Int.random(in: 1...maxY))
            if occupied(c) { continue }
            if Int.random(in: 0...7) != 3 {
                things.append(SnakeThing(cell: c, kind: .food, variant: Int.random(in: 1...9), points: Int.random(in: 2...3)))
            } else {
                things.append(SnakeThing(cell: c, kind: .box, points: Int.random(in: 3...7)))
            }
            return
        }
    }

    private func turn(_ d: SnakeCell) {
        if state == .over { return }
        let last = queue.last ?? dir
        if d == last || d == -last { return }
        if state == .paused { setPaused(false) }
        if queue.count < 2 { queue.append(d) }
        if state == .ready { state = .playing; needsDisplay = true }
    }

    private func step() {
        prevSnake = snake
        if let q = queue.first {
            queue.removeFirst()
            if q != -dir { dir = q }
        }
        // комки еды ползут по телу; дошёл до хвоста — змея вырастает
        for i in waves.indices { waves[i] += 1 }
        let arrived = waves.filter { $0 >= Double(snake.count) }.count
        waves.removeAll { $0 >= Double(snake.count) }
        pendingGrow += arrived

        let head = SnakeCell(x: snake[0].x + dir.x, y: snake[0].y + dir.y)
        if head.x < 1 || head.x > maxX || head.y < 1 || head.y > maxY || snake.dropLast().contains(head) {
            die(); return
        }
        var shorten = false
        if let i = things.firstIndex(where: { $0.cell == head }) {
            let th = things[i]
            switch th.kind {
            case .obstacle:
                die(); return
            case .food:
                score += th.points
                stepMs = max(70, stepMs - 10)
                waves.append(1)
                chomp = 0.35
                SnakeSound.eat.play()
            case .box:
                score += th.points
                stepMs = min(900, stepMs + 25)      // подарок немного замедляет змею — игра дольше
                shorten = true                       // и укорачивает хвост на 10%
                chomp = 0.35
                SnakeSound.box.play()
            }
            eaten.append(SnakeEaten(thing: th, duration: stepMs / 1000))
            floats.append(SnakeFloat(text: "+\(th.points)",
                                     p: CGPoint(x: CGFloat(head.x) * cell + cell / 2, y: CGFloat(head.y) * cell), life: 0.9))
            things.remove(at: i)
        }
        var grow = false
        if pendingGrow > 0 { pendingGrow -= 1; grow = true }
        snake.insert(head, at: 0)
        if !grow { snake.removeLast() }
        if shorten {
            // хвост короче на 10% (округляя, но хотя бы на один шарик), не меньше трёх шариков
            let cut = max(1, Int((Double(snake.count) * 0.1).rounded()))
            let target = max(3, snake.count - cut)
            if snake.count > target { snake.removeLast(snake.count - target) }
            waves.removeAll { $0 >= Double(snake.count) }
        }
        needsDisplay = true
    }

    private func die() {
        state = .over
        stopTimer()
        SnakeSound.die.play()
        needsDisplay = true
        if score > 0 { recs?.beginEntry(score: score, in: recsRect) }
    }

    // MARK: Таймер

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

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.2, now - lastT)
        lastT = now
        if state == .playing {
            stepAcc += dt
            mealAcc += dt
            while stepAcc >= stepMs / 1000 && state == .playing {
                stepAcc -= stepMs / 1000
                step()
            }
            if mealAcc >= 3.7 { mealAcc = 0; addMeal() }
            chomp = max(0, chomp - dt)
            for i in eaten.indices { eaten[i].age += dt }
            eaten.removeAll { $0.age >= $0.duration }
        }
        for i in floats.indices { floats[i].life -= dt; floats[i].p.y -= CGFloat(34 * dt) }
        floats.removeAll { $0.life <= 0 }
        needsDisplay = true
    }

    private func setPaused(_ on: Bool) {
        if on {
            guard state == .playing else { return }
            state = .paused
            stopTimer()
        } else {
            guard state == .paused else { return }
            state = .playing
            startTimer()
        }
        autoPaused = false
        needsDisplay = true
    }

    /// Окно потеряло фокус или закрыто: игра встаёт на паузу сама
    func autoPause() {
        if state == .playing {
            setPaused(true)
            autoPaused = true
        }
    }

    /// Окно снова показано: продолжаем, если пауза была автоматической
    func resume() {
        if state == .paused && autoPaused { setPaused(false) }
    }

    // MARK: Управление

    override func keyDown(with e: NSEvent) {
        // по кодам клавиш, чтобы работало и в русской раскладке
        switch e.keyCode {
        case 123, 0:  turn(SnakeCell(x: -1, y: 0))   // ←, A
        case 124, 2:  turn(SnakeCell(x: 1, y: 0))    // →, D
        case 126, 13: turn(SnakeCell(x: 0, y: -1))   // ↑, W
        case 125, 1:  turn(SnakeCell(x: 0, y: 1))    // ↓, S
        case 49, 35:                                  // пробел, P
            switch state {
            case .ready: state = .playing; needsDisplay = true
            case .playing: setPaused(true)
            case .paused: setPaused(false)
            case .over: if recs?.entering != true { newGame() }
            }
        default:
            super.keyDown(with: e)
        }
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if newBtn.contains(p) { newGame(); return }
        if skinBtn.contains(p) {
            skin = skin % 9 + 1
            UserDefaults.standard.set(skin, forKey: "snake.skin")
            needsDisplay = true
            return
        }
        if pauseBtn.contains(p) {
            if state == .playing { setPaused(true) } else if state == .paused { setPaused(false) }
            return
        }
        switch state {
        case .over:
            if recs?.entering != true { newGame() }
        case .ready:
            state = .playing
            needsDisplay = true
        case .paused:
            setPaused(false)
        case .playing:
            // как в оригинале: клик выше/ниже или левее/правее головы поворачивает змею в ту сторону
            let h = snake[0]
            let hx = origin.x + (CGFloat(h.x) + 0.5) * cell, hy = origin.y + (CGFloat(h.y) + 0.5) * cell
            if dir.x != 0 {
                if p.y > hy + 1 { turn(SnakeCell(x: 0, y: 1)) } else if p.y < hy - 1 { turn(SnakeCell(x: 0, y: -1)) }
            } else {
                if p.x < hx - 1 { turn(SnakeCell(x: -1, y: 0)) } else if p.x > hx + 1 { turn(SnakeCell(x: 1, y: 0)) }
            }
        }
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

    @discardableResult
    private func drawImage(_ name: String, in r: NSRect, alpha: CGFloat = 1) -> Bool {
        guard let img = SnakeRes.image(name) else { return false }
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        return true
    }

    private func rect(_ c: SnakeCell, lift: CGFloat = 0) -> NSRect {
        return NSRect(x: origin.x + CGFloat(c.x) * cell, y: origin.y + CGFloat(c.y) * cell - lift, width: cell, height: cell)
    }

    private func button(_ r: NSRect, _ title: String, enabled: Bool = true) {
        NSColor(white: 1, alpha: enabled ? 0.2 : 0.08).setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        drawString(title, NSRect(x: r.minX, y: r.minY + 7, width: r.width, height: 18), size: 13,
                   color: NSColor(white: 1, alpha: enabled ? 1 : 0.5), align: .center)
    }

    /// Картинка по центру клетки, увеличенная в k раз
    private func drawScaled(_ name: String, _ r: NSRect, scale k: CGFloat, alpha: CGFloat = 1, fallback: NSColor) {
        let rr = r.insetBy(dx: -r.width * (k - 1) / 2, dy: -r.height * (k - 1) / 2)
        if !drawImage(name, in: rr, alpha: alpha) {
            fallback.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: rr.insetBy(dx: 3, dy: 3)).fill()
        }
    }

    private func thingSprite(_ t: SnakeThing, time: Double) -> (String, CGFloat) {
        switch t.kind {
        case .food: return ("food\(t.variant)", 1.05)
        case .obstacle:
            let period = 1.0 + t.seed.truncatingRemainder(dividingBy: 1)
            return ("thorn\(t.variant + Int((time + t.seed) / period) % 2)", 1.25)
        case .box: return ("priz\(Int(time * 4 + t.seed * 4) % 4)", 1.15)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.1, green: 0.17, blue: 0.13, alpha: 1).setFill()
        bounds.fill()

        // шапка
        plate(NSRect(x: 10, y: 6, width: bounds.width - 20, height: 42))
        drawString(T("Очки") + ": \(score)", NSRect(x: 20, y: 14, width: 120, height: 26), size: 18, bold: true)
        button(newBtn, T("Новая игра"))
        button(skinBtn, T("Скин") + " \(skin)")
        button(pauseBtn, state == .paused ? T("Продолжить") : T("Пауза"), enabled: state == .playing || state == .paused)

        // поле: бордюр и «трава» (клетки шахматкой)
        let all = NSRect(x: origin.x, y: origin.y, width: CGFloat(maxX + 2) * cell, height: CGFloat(maxY + 2) * cell)
        NSColor(calibratedRed: 0.36, green: 0.24, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: all, xRadius: 6, yRadius: 6).fill()
        let inner = NSRect(x: origin.x + cell, y: origin.y + cell, width: CGFloat(maxX) * cell, height: CGFloat(maxY) * cell)
        let tile = "tex\(texture)"
        for y in 1...maxY {
            for x in 1...maxX {
                let r = rect(SnakeCell(x: x, y: y))
                if !drawImage(tile, in: r) {
                    NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.3, alpha: 1).setFill()
                    r.fill()
                }
                if (x + y) % 2 == 0 {
                    NSColor(white: 1, alpha: 0.07).setFill()
                    r.fill()
                }
            }
        }
        NSColor(white: 0, alpha: 0.35).setStroke()
        NSBezierPath(rect: inner).stroke()

        let time = CACurrentMediaTime()

        // предметы: фрукты и подарки подпрыгивают, репейник и подарки анимируются
        for th in things {
            let hop: CGFloat = (th.kind == .food || th.kind == .box) ? CGFloat(abs(sin(time * 2.2 + th.seed))) * 4 : 0
            let (name, k) = thingSprite(th, time: time)
            drawScaled(name, rect(th.cell, lift: hop), scale: k, fallback: NSColor(calibratedRed: 0.9, green: 0.7, blue: 0.2, alpha: 1))
        }

        // змея: плавное движение, комки еды бегут по телу
        let progress: CGFloat = (state == .playing || state == .paused) ? CGFloat(min(1, stepAcc / (stepMs / 1000))) : 1
        func bulge(_ i: Int) -> CGFloat {
            var k = 0.0
            for w in waves { k += max(0, 1 - abs(Double(i) - (w - 1 + Double(progress)))) }
            return CGFloat(min(1, k))
        }
        let pre = "s\(skin)_"
        for (i, c) in snake.enumerated().reversed() {
            let from = prevSnake.isEmpty ? c : prevSnake[min(i, prevSnake.count - 1)]
            var r = rect(c)
            let fr = rect(from)
            r.origin.x = fr.origin.x + (r.origin.x - fr.origin.x) * progress
            r.origin.y = fr.origin.y + (r.origin.y - fr.origin.y) * progress
            if i > 0 {
                drawScaled(pre + "body", r, scale: 0.95 + 0.45 * bulge(i), fallback: NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.2, alpha: 1))
            } else {
                // голова: рот открыт, если еда в двух клетках впереди или идёт поедание; изредка моргает
                let a1 = SnakeCell(x: c.x + dir.x, y: c.y + dir.y), a2 = SnakeCell(x: c.x + 2 * dir.x, y: c.y + 2 * dir.y)
                let foodAhead = things.contains { $0.kind == .food && ($0.cell == a1 || $0.cell == a2) }
                let open = state != .over && (foodAhead || chomp > 0 || !eaten.isEmpty)
                let blink = !open && (state == .over || Int(time * 1000) % 3500 < 180)
                let d = dir.x > 0 ? "r" : (dir.x < 0 ? "l" : (dir.y < 0 ? "u" : "d"))
                let pulse = 1 + 0.3 * CGFloat(min(1, chomp / 0.35))
                drawScaled(pre + "head" + d + (open ? "o" : (blink ? "c" : "")), r, scale: 1.3 * pulse,
                           fallback: NSColor(calibratedRed: 0.4, green: 0.9, blue: 0.3, alpha: 1))
            }
        }

        // съедаемый предмет уменьшается и «втягивается» в рот
        for e in eaten {
            let k = CGFloat(max(0, 1 - e.age / e.duration))
            let (name, sk) = thingSprite(e.thing, time: time)
            drawScaled(name, rect(e.thing.cell), scale: sk * k, alpha: k, fallback: .orange)
        }

        // очки над съеденным
        for f in floats {
            drawString(f.text, NSRect(x: origin.x + f.p.x - 25, y: origin.y + f.p.y - 8, width: 50, height: 16), size: 14,
                       color: NSColor(calibratedRed: 1, green: 0.9, blue: 0.4, alpha: CGFloat(min(1, f.life * 2))),
                       align: .center, bold: true)
        }

        // подвал
        plate(NSRect(x: 10, y: all.maxY + 6, width: 750, height: 30))
        drawString(T("Стрелки или WASD — поворот · пробел — пауза · клик — повернуть к месту клика"),
                   NSRect(x: 20, y: all.maxY + 13, width: 730, height: 18), size: 12,
                   color: NSColor(white: 1, alpha: 0.9))

        // рекорды
        plate(recsRect.insetBy(dx: -10, dy: -8))
        recs?.draw(in: recsRect)

        // завеса и надписи
        var title = "", sub = ""
        switch state {
        case .ready:
            title = "Snake"; sub = T("Нажмите пробел или стрелку, чтобы начать")
        case .paused:
            title = T("Пауза"); sub = T("Нажмите, чтобы продолжить")
        case .over:
            title = T("Игра окончена")
            sub = T("Очки") + ": \(score)   ·   " + T("Нажмите, чтобы начать заново")
        case .playing:
            break
        }
        if !title.isEmpty {
            NSColor(white: 0, alpha: 0.58).setFill()
            inner.fill()
            drawString(title, NSRect(x: inner.minX, y: inner.midY - 36, width: inner.width, height: 40), size: 30,
                       align: .center, bold: true)
            drawString(sub, NSRect(x: inner.minX, y: inner.midY + 10, width: inner.width, height: 22), size: 15,
                       color: NSColor(white: 1, alpha: 0.9), align: .center)
        }
    }
}

final class SnakeWindowController: NSObject, NSWindowDelegate {
    static let shared = SnakeWindowController()
    private var window: NSWindow?
    private var game: SnakeView?

    func show() {
        if window == nil {
            let size = NSSize(width: 1000, height: 720)
            SnakeSound.warmUp()
            let v = SnakeView(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = v
            w.delegate = self
            if !w.setFrameUsingName("SnakeWindow") { w.center() }
            w.setFrameAutosaveName("SnakeWindow")
            window = w
            game = v
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = "Snake"
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

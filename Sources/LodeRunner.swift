import Cocoa

// MARK: - Lode Runner («Передохни»)
//
// Классика: собрать всё золото, убегая от охранников, потом подняться по появившейся лестнице на самый верх.
// Бегун умеет копать ямы в кирпичной кладке слева и справа от себя (пробел); охранник, упавший в яму, на время
// выбывает; яма через несколько секунд зарастает. Уровни составлены для этой игры.
//   '#' кирпич (копается)  '@' бетон  'X' ловушка (выглядит как кирпич, но проваливается)
//   'H' лестница  'S' скрытая лестница  '-' канат  '$' золото  '&' бегун  '0' охранник

private let lodeLevels: [[String]] = [
    [
        "                S           ",
        "                S           ",
        "                S      $    ",
        "###H#####@#H#@##############",
        "   H       H                ",
        "   H       H                ",
        "   H       H$0              ",
        "#######H###########@H#####H#",
        "       H            H     H ",
        "       H            H     H ",
        "     0 H        $  $H     H0",
        "##H######@##H######@##H#@###",
        "  H         H         H     ",
        "  H         H         H     ",
        "  H $       H$      & H  $ $",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "         S                  ",
        "         S                  ",
        "         S                  ",
        "         S                  ",
        "##H############H############",
        "  H            H            ",
        "  H            H            ",
        "  H     0      H        0   ",
        "##H###########H#######@##@##",
        "  H           H             ",
        "  H           H             ",
        "0 H$  $       H$    $     $ ",
        "#######H########H#####H#@###",
        "       H        H     H     ",
        " $     H    & $ H     H     ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "                  S         ",
        "                  S         ",
        "              $0  S         ",
        "##@H#####H#####X#H#####@####",
        "   H     H       H          ",
        " $ H   0 H $     H  $       ",
        "##@#X#H@####@####H####X###H#",
        "      H          H        H ",
        "      H      $   H        H ",
        "#########H########@H####@#@#",
        "         H         H        ",
        " $       H   $     H0 $    $",
        "#######H######X#########H###",
        "       H                H   ",
        "       H       &        H   ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "        S                   ",
        "        S                   ",
        "        S $            0 $  ",
        "#H#########@#######@#H##@#@#",
        " H                   H      ",
        " H      0     $      H      ",
        "##@##H#######H##@######@#X##",
        "     H       H              ",
        "   $ H       H              ",
        "####H######@##@X@X####H#####",
        "    H                 H     ",
        "    H0             $  H     ",
        "#H##########@####H@#####@###",
        " H               H          ",
        " H$ $          $&H$         ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "                         S  ",
        "                         S  ",
        "  $             $       $S  ",
        "###@##@######H##@###H#####@#",
        "             H      H       ",
        "          $  H      H       ",
        "##H#@#X#@@##H###@####H###@#@",
        "  H         H        H      ",
        "0$H$        H        H  0   ",
        "##########H#######H#########",
        "          H       H         ",
        "          H       H     0   ",
        "##@#######H######@#####H####",
        "          H            H    ",
        "  $ $  &  H$     $     H   $",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "   S                        ",
        "   S                        ",
        "   S                        ",
        "###@##@####H#X#########X#H##",
        "           H             H  ",
        "0    $     H $     $     H $",
        "###@######H#########@H##@##@",
        "          H          H      ",
        "      $$  H  0     $ H      ",
        "#####H##@##XH##@######H#@###",
        "     H      H         H     ",
        "     H      H  0$     H $   ",
        "#@###@####X###H##@###@H@@###",
        "              H       H     ",
        "  $    $      H$     &H $   ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "       S                    ",
        "       S                    ",
        "    $  S      $         $   ",
        "###H#####HX##@###@#@####@H##",
        "   H     H               H  ",
        "   H   0 H   $           H  ",
        "##H@###@@#@@@#@#H#####@#@###",
        "  H             H           ",
        "0 H$    0    $  H           ",
        "##########H@##@#XH####H#####",
        "          H      H    H     ",
        "  $  $    H  $   H    H     ",
        "#H#########H@######@#H#@###@",
        " H         H         H      ",
        "$H    $ $ $H  &      H    $ ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "           S                ",
        "           S                ",
        "  $        S  $    $        ",
        "##########H##X############H#",
        "       $ 0H  $       $    H ",
        "@##H####H############@#@####",
        "   H    H                   ",
        " $ H $  H                   ",
        "#######H######@X#####H######",
        "       H             H      ",
        "       H    $0       H$     ",
        "##H#######@@#####X#@#H######",
        "  H                  H      ",
        "  H                  H      ",
        "  H        $ $0   $  H   &  ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "            S               ",
        "            S               ",
        "     $      S      $        ",
        "#@#####@H######H@###########",
        "        H      H            ",
        "   $    H      H  $         ",
        "##@#######H###@#@H####H#####",
        "          H      H    H     ",
        "    $$    H$ $   H    H   0$",
        "@H###@X#####@#######@@###H##",
        " H                       H  ",
        " H            $ $       0H0 ",
        "###@###H#@###H#######H@#####",
        "       H     H       H      ",
        "   &   H     H     $$H    $ ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "                S           ",
        "                S           ",
        "       $  $     S   $$   $  ",
        "@###H###################HX##",
        " $0 H     0 $           H $ ",
        "##@#X##@#@@#@#H#@#@#####H###",
        "              H         H   ",
        "          $   H $       H$  ",
        "##@##@H###X##@H#@#####@@#@##",
        "      H       H             ",
        " $    H       H             ",
        "###H####@#########H####@##@#",
        "   H              H         ",
        "   H              H         ",
        "$ $H          & $ H    0 $  ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "                S           ",
        "                S           ",
        "                S$  $  0   $",
        "#@####H#X##H####@####@#@#H##",
        "      H    H             H  ",
        "      H    H             H  ",
        " $ 0 $H    H      $    $ H$ ",
        "##H@#@########H###@##@##H###",
        "  H           H         H   ",
        "  H           H         H   ",
        "  H$   $    $ H  $   $$ H   ",
        "#@#######H##########@####H##",
        "         H               H  ",
        "         H               H  ",
        "    &    H$            0 H $",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "     S                      ",
        "     S                      ",
        " $   S$$    $  $   $   $  $ ",
        "##@H@#@#@H######H###########",
        "   H  $  H      H           ",
        "#####H######X####H@##@@#X@##",
        "     H           H          ",
        "    $H           H $        ",
        "########X####HX#####H#####@#",
        "             H      H       ",
        "    0 $$     H0     H     0$",
        "#####H###X########H#@#######",
        "     H            H         ",
        "     H            H         ",
        "$ &  H$       $   H     $   ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "                 S          ",
        "                 S          ",
        "  $    0         S   $      ",
        "#@@#@#######HX##X#########H@",
        " $    $     H0 $   $      H ",
        "#@#####H#####@@##H####@##@##",
        "       H         H          ",
        "    $ $H$        H    $  $$ ",
        "###H####@X#########@H#@@###@",
        "   H                H       ",
        " $ H                H$$     ",
        "####H#####@H####X#######@@##",
        "    H      H                ",
        "    H      H                ",
        "  $ H $ 0$ H            &   ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "           S                ",
        "           S                ",
        "$  $    0  S             $  ",
        "#H######@#@@H@############H#",
        " H          H             H ",
        " H  $   $   H     $ $  $ $H$",
        "##XH#@######H@######X####@##",
        "   H        H               ",
        "   H        H         $   0 ",
        "########@####@#H#######@#H##",
        "               H         H  ",
        "$ $$           H   $   $ H  ",
        "@#@####H#######@HX######H@@#",
        "       H        H       H   ",
        "       H   &$   H $   0$H  $",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ],
    [
        "   S                        ",
        "   S                        ",
        " 0 S$   $ $       $      $  ",
        "###@###@@H###@H########@H###",
        "         H    H         H   ",
        "         H    H         H   ",
        "    $$$$ H$$ 0H  $$    $H$  ",
        "@H############@##@#@#H###@##",
        " H                   H      ",
        " H                   H      ",
        " H       $$          H 0    ",
        "##########@#H@@##H##@#@@###@",
        "            H    H          ",
        "            H    H          ",
        "   $ & $    H    H      $$  ",
        "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    ]
]

/// Простые синтезированные звуки (без файлов): WAV собирается в памяти
private enum LodeSound {
    case dig, gold, ladder, done, dead
    private static var cache: [Int: NSSound] = [:]

    /// (частота Гц, длительность с, шум 0…1) — ноты подряд; частота может плавно меняться к `to`
    private static func notes(_ k: LodeSound) -> [(f: Double, to: Double, d: Double, noise: Double)] {
        switch k {
        case .dig:    return [(180, 90, 0.14, 0.6)]
        case .gold:   return [(988, 988, 0.05, 0), (1319, 1319, 0.09, 0)]
        case .ladder: return [(392, 392, 0.09, 0), (523, 523, 0.09, 0), (659, 659, 0.09, 0), (784, 784, 0.09, 0), (1047, 1047, 0.16, 0)]
        case .done:   return [(523, 523, 0.12, 0), (659, 659, 0.12, 0), (784, 784, 0.12, 0), (1047, 1047, 0.30, 0)]
        case .dead:   return [(440, 440, 0.12, 0), (370, 370, 0.12, 0), (294, 294, 0.12, 0), (220, 110, 0.45, 0.15)]
        }
    }

    private static func wav(_ k: LodeSound) -> Data {
        let rate = 22050.0
        var samples = [Int16]()
        var phase = 0.0
        for n in notes(k) {
            let count = Int(n.d * rate)
            for i in 0..<count {
                let u = Double(i) / Double(count)
                let f = n.f + (n.to - n.f) * u
                phase += 2 * Double.pi * f / rate
                let tone = sin(phase) > 0 ? 1.0 : -1.0                 // прямоугольная волна — как в старых играх
                let noise = Double.random(in: -1...1)
                let v = (tone * (1 - n.noise) + noise * n.noise) * 0.22 * min(1, (1 - u) * 6)
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
        let key = LodeSound.index(self)
        if LodeSound.cache[key] == nil { LodeSound.cache[key] = NSSound(data: LodeSound.wav(self)) }
        guard let s = LodeSound.cache[key] else { return }
        LodeSound.warming.remove(key)
        s.stop()
        s.volume = 1
        s.play()
    }

    private static var warming = Set<Int>()

    /// Заранее собирает все звуки и «прогревает» аудиосистему беззвучным запуском, чтобы первый настоящий звук не подвешивал игру
    static func warmUp() {
        for k in [LodeSound.dig, .gold, .ladder, .done, .dead] {
            let key = index(k)
            if cache[key] == nil { cache[key] = NSSound(data: wav(k)) }
            guard let s = cache[key] else { continue }
            warming.insert(key)
            s.volume = 0
            s.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if warming.contains(key) { warming.remove(key); s.stop(); s.volume = 1 }
            }
        }
    }

    private static func index(_ k: LodeSound) -> Int {
        switch k { case .dig: return 0; case .gold: return 1; case .ladder: return 2; case .done: return 3; case .dead: return 4 }
    }
}

final class LodeView: NSView {
    override var isFlipped: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }

    // MARK: Параметры
    private let cols = 28, rows = 16
    private let ts: CGFloat = 28
    private let fx: CGFloat = 24, fy: CGFloat = 64
    private let tickDur: Double = 0.30        // один шаг бегуна — одна клетка (≈ 3 клетки в секунду)
    private let holeLife = 23
    private let escapeTicks = 9

    private enum State { case playing, paused, dying, levelDone, over }

    private struct Actor {
        var x = 0, y = 0
        var px: CGFloat = 0, py: CGFloat = 0     // клетка на прошлом шаге (для плавного движения)
        var face = 1
        var phase = 0
        var gold = false
        var carry = 0
        var trapped = 0
        var wait = 0
        var sx = 0, sy = 0
    }

    // MARK: Состояние
    private var tiles: [[Character]] = []
    private var runner = Actor()
    private var guards: [Actor] = []
    private var holes: [Int: Int] = [:]
    private var digTimer = 0, digX = 0, digY = 0
    private var digReq = 0
    private var held: [UInt16] = []
    private var latched: UInt16?                 // быстрое нажатие: клавиша отпущена до такта, но направление не теряется
    private var revealed = false
    private var tickCount = 0
    private var acc = 0.0
    private var gacc = 0.0                       // время до шага охранников (у них свой, более медленный такт)
    private var guardDur: Double { return levelIdx < 4 ? 0.45 : (levelIdx < 8 ? 0.40 : 0.34) }
    private var dyingLeft = 0.0
    private var levelIdx = 0
    private var lives = 5
    private var score = 0
    private var state: State = .playing
    private var autoPaused = false
    private var timer: Timer?
    private var lastT: CFTimeInterval = 0
    private var recs: GameRecordsPanel?
    private let recsRect = NSRect(x: 830, y: 64, width: 190, height: 480)

    private let newBtn = NSRect(x: 24, y: 14, width: 130, height: 34)
    private let pauseBtn = NSRect(x: 164, y: 14, width: 110, height: 34)

    override init(frame: NSRect) {
        super.init(frame: frame)
        recs = GameRecordsPanel(key: "lode.records", host: self)
        recs?.onFinish = { [weak self] in self?.newGame() }
        resumeOrNewGame()
        state = .paused                // при запуске игра стоит на паузе, пока не нажмут любую клавишу
        autoPaused = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Уровень

    private func makeActor(_ x: Int, _ y: Int) -> Actor {
        var a = Actor()
        a.x = x; a.y = y; a.px = CGFloat(x); a.py = CGFloat(y); a.sx = x; a.sy = y
        return a
    }

    private func loadLevel() {
        saveProgress()
        let lv = lodeLevels[levelIdx % lodeLevels.count]
        tiles = []
        guards = []
        holes = [:]
        for (y, row) in lv.enumerated() {
            var line: [Character] = []
            for (x, ch) in row.enumerated() {
                switch ch {
                case "&":
                    runner = makeActor(x, y)
                    line.append(" ")
                case "0":
                    guards.append(makeActor(x, y))
                    line.append(" ")
                default:
                    line.append(ch)
                }
            }
            while line.count < cols { line.append(" ") }
            tiles.append(line)
        }
        revealed = false
        digTimer = 0
        digReq = 0
        tickCount = 0
        acc = 0
        gacc = 0
        state = .playing
        autoPaused = false
        needsDisplay = true
    }

    // MARK: Сохранение прогресса (уровень, жизни, очки) — переживает закрытие окна и выход из программы

    private func saveProgress() {
        let d = UserDefaults.standard
        d.set(levelIdx, forKey: "lode.level")
        d.set(lives, forKey: "lode.lives")
        d.set(score, forKey: "lode.score")
    }

    private func clearProgress() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "lode.level")
        d.removeObject(forKey: "lode.lives")
        d.removeObject(forKey: "lode.score")
    }

    private func resumeOrNewGame() {
        let d = UserDefaults.standard
        if d.object(forKey: "lode.lives") != nil, d.integer(forKey: "lode.lives") > 0 {
            levelIdx = max(0, d.integer(forKey: "lode.level"))
            lives = d.integer(forKey: "lode.lives")
            score = max(0, d.integer(forKey: "lode.score"))
            loadLevel()
            startTimer()
        } else {
            newGame()
        }
    }

    private func newGame() {
        recs?.cancel()
        levelIdx = 0
        lives = 5
        score = 0
        loadLevel()
        startTimer()
    }

    private func startTimer() {
        if timer != nil { return }
        lastT = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.frame60() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func autoPause() {
        held.removeAll()
        digReq = 0
        if state == .playing {
            state = .paused
            autoPaused = true
            needsDisplay = true
        }
        stopTimer()
    }

    func resume() {
        startTimer()
        if state == .paused && autoPaused {
            state = .playing
            autoPaused = false
            needsDisplay = true
        }
    }

    private func togglePause() {
        if state == .playing {
            state = .paused
            autoPaused = false
        } else if state == .paused {
            state = .playing
            autoPaused = false
        }
        needsDisplay = true
    }

    private func frame60() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastT)
        lastT = now
        switch state {
        case .playing:
            acc += dt
            gacc += dt
            while acc >= tickDur && state == .playing {
                tick()
                acc -= tickDur
            }
            while gacc >= guardDur && state == .playing {
                guardTick()
                gacc -= guardDur
            }
        case .dying:
            dyingLeft -= dt
            if dyingLeft <= 0 {
                if lives <= 0 { gameOver() } else { loadLevel() }
            }
        default:
            break
        }
        needsDisplay = true
    }

    private func gameOver() {
        state = .over
        clearProgress()
        if score > 0 { recs?.beginEntry(score: score, in: recsRect) }
    }

    // MARK: Поле

    private func tile(_ x: Int, _ y: Int) -> Character {
        if x < 0 || x >= cols || y < 0 || y >= rows { return "@" }
        return tiles[y][x]
    }

    private func isSolid(_ c: Character) -> Bool { return c == "#" || c == "@" }

    private func idx(_ x: Int, _ y: Int) -> Int { return y * cols + x }

    private func guardAt(_ x: Int, _ y: Int, except: Int? = nil) -> Int? {
        for i in guards.indices where i != except && guards[i].wait == 0 && guards[i].x == x && guards[i].y == y {
            return i
        }
        return nil
    }

    /// Стоит ли на месте (не падает): лестница, канат, твёрдое снизу или голова охранника снизу
    private func supported(_ x: Int, _ y: Int, ignoring gi: Int? = nil) -> Bool {
        let t = tile(x, y)
        if t == "H" || t == "-" { return true }
        let b = tile(x, y + 1)
        if b == "#" || b == "@" || b == "H" { return true }
        if guardAt(x, y + 1, except: gi) != nil { return true }
        return false
    }

    private var goldOnField: Int {
        var n = 0
        for row in tiles { for c in row where c == "$" { n += 1 } }
        return n + guards.filter { $0.gold }.count
    }

    private func checkReveal() {
        if revealed || goldOnField > 0 { return }
        revealed = true
        LodeSound.ladder.play()
        for y in 0..<rows { for x in 0..<cols where tiles[y][x] == "S" { tiles[y][x] = "H" } }
    }

    // MARK: Шаг игры

    private func currentDir() -> (Int, Int) {
        for k in (held.isEmpty ? (latched.map { [$0] } ?? []) : held).reversed() {
            switch k {
            case 123, 0: return (-1, 0)
            case 124, 2: return (1, 0)
            case 126, 13: return (0, -1)
            case 125, 1: return (0, 1)
            default: break
            }
        }
        return (0, 0)
    }

    private func tick() {
        defer { latched = nil }
        tickCount += 1
        runner.px = CGFloat(runner.x); runner.py = CGFloat(runner.y)
        updateHoles()
        if state != .playing { return }
        stepRunner()
        if state != .playing { return }
        checkTouch()
    }

    /// Шаг охранников: у них свой такт (чуть медленнее бегуна), поэтому бегут без остановок
    private func guardTick() {
        for i in guards.indices { guards[i].px = CGFloat(guards[i].x); guards[i].py = CGFloat(guards[i].y) }
        stepGuards()
        checkTouch()
    }

    private func die() {
        if state == .dying { return }
        state = .dying
        LodeSound.dead.play()
        dyingLeft = 1.2
        lives -= 1
        saveProgress()
    }

    private func updateHoles() {
        for (k, left) in Array(holes) {
            if left <= 1 {
                let x = k % cols, y = k / cols
                holes[k] = nil
                tiles[y][x] = "#"
                if runner.x == x && runner.y == y { die() }
                for i in guards.indices where guards[i].wait == 0 && guards[i].x == x && guards[i].y == y {
                    score += 75
                    respawn(i)
                }
            } else {
                holes[k] = left - 1
            }
        }
    }

    private func respawn(_ i: Int) {
        var cand: [(Int, Int)] = []
        for y in 0..<min(rows, 9) {
            for x in 0..<cols where tiles[y][x] == " " && isSolid(tile(x, y + 1))
                && !(runner.x == x && runner.y == y) && guardAt(x, y, except: i) == nil {
                cand.append((x, y))
            }
        }
        let p = cand.randomElement() ?? (guards[i].sx, guards[i].sy)
        guards[i].x = p.0; guards[i].y = p.1
        guards[i].px = CGFloat(p.0); guards[i].py = CGFloat(p.1)
        guards[i].trapped = 0
        guards[i].gold = false
        guards[i].carry = 0
        guards[i].wait = 6
    }

    private func openHole(_ x: Int, _ y: Int) {
        if tile(x, y) != "#" { return }
        tiles[y][x] = " "
        holes[idx(x, y)] = holeLife
    }

    private func moveRunner(_ x: Int, _ y: Int) {
        runner.x = x; runner.y = y
        runner.phase += 1
        if tile(x, y) == "$" {
            tiles[y][x] = " "
            score += 250
            LodeSound.gold.play()
            saveProgress()
            checkReveal()
        }
        if revealed && y == 0 {
            score += 1500
            LodeSound.done.play()
            state = .levelDone
            UserDefaults.standard.set(levelIdx + 1, forKey: "lode.level")      // при выходе на экране «Уровень пройден» продолжим со следующего
            UserDefaults.standard.set(score, forKey: "lode.score")
        }
    }

    private func stepRunner() {
        if digTimer > 0 {
            digTimer -= 1
            if digTimer == 0 { openHole(digX, digY) }
            return
        }
        let x = runner.x, y = runner.y
        if !supported(x, y) {
            if y + 1 < rows && !isSolid(tile(x, y + 1)) { moveRunner(x, y + 1) }
            return
        }
        if digReq != 0 {
            let d = digReq
            digReq = 0
            let tx = x + d
            runner.face = d
            if tile(tx, y) == " " && tile(tx, y + 1) == "#" && holes[idx(tx, y + 1)] == nil
                && guardAt(tx, y) == nil && tile(x, y) != "-" {
                digTimer = 1
                LodeSound.dig.play()
                digX = tx
                digY = y + 1
                return
            }
        }
        let (dx, dy) = currentDir()
        if dx != 0 {
            runner.face = dx
            let tx = x + dx
            if holes[idx(x, y)] != nil {
                // яма: можно выбраться на край
                if !isSolid(tile(tx, y - 1)) && isSolid(tile(tx, y)) && guardAt(tx, y - 1) == nil {
                    moveRunner(tx, y - 1)
                }
                return
            }
            if tx >= 0 && tx < cols && !isSolid(tile(tx, y)) {
                if let gi = guardAt(tx, y), guards[gi].trapped > 0 { return }
                moveRunner(tx, y)
            }
        } else if dy < 0 {
            if tile(x, y) == "H" && y > 0 && !isSolid(tile(x, y - 1)) { moveRunner(x, y - 1) }
        } else if dy > 0 {
            if y + 1 < rows && !isSolid(tile(x, y + 1)) {
                if let gi = guardAt(x, y + 1), guards[gi].trapped > 0 { return }
                moveRunner(x, y + 1)
            }
        }
    }

    // MARK: Охранники

    private func graphNeighbors(_ x: Int, _ y: Int) -> [(Int, Int)] {
        var r: [(Int, Int)] = []
        let t = tile(x, y)
        let b = tile(x, y + 1)
        let head = guardAt(x, y + 1) != nil                 // внизу стоит охранник (в яме): по его голове можно бежать
        let sup = t == "H" || t == "-" || b == "#" || b == "@" || b == "H" || head
        if !sup {
            if y + 1 < rows && !isSolid(b) { r.append((x, y + 1)) }
            return r
        }
        for dx in [-1, 1] {
            let nx = x + dx
            if nx >= 0 && nx < cols && !isSolid(tile(nx, y)) { r.append((nx, y)) }
        }
        if t == "H" && y > 0 && !isSolid(tile(x, y - 1)) { r.append((x, y - 1)) }
        if y + 1 < rows && !isSolid(b) && !head { r.append((x, y + 1)) }
        return r
    }

    /// Первая клетка кратчайшего пути охранника к бегуну (поиск в ширину по клеткам поля)
    private func nextStep(_ i: Int) -> (Int, Int)? {
        let sx = guards[i].x, sy = guards[i].y
        let tx = runner.x, ty = runner.y
        if sx == tx && sy == ty { return nil }
        let start = idx(sx, sy), goal = idx(tx, ty)
        var prev = [Int](repeating: -1, count: cols * rows)
        prev[start] = start
        var queue = [start]
        var head = 0
        var found = false
        while head < queue.count {
            let cur = queue[head]
            head += 1
            if cur == goal { found = true; break }
            for (nx, ny) in graphNeighbors(cur % cols, cur / cols) {
                let k = idx(nx, ny)
                if prev[k] == -1 {
                    prev[k] = cur
                    queue.append(k)
                }
            }
        }
        if !found { return nil }
        var k = goal
        while prev[k] != start { k = prev[k] }
        return (k % cols, k / cols)
    }

    private func moveGuard(_ i: Int, _ x: Int, _ y: Int) {
        if x != guards[i].x { guards[i].face = x > guards[i].x ? 1 : -1 }
        guards[i].x = x; guards[i].y = y
        guards[i].phase += 1
        if !guards[i].gold && tile(x, y) == "$" {
            tiles[y][x] = " "
            guards[i].gold = true
            guards[i].carry = 0
        }
        // упал в яму: роняет золото на край и застревает
        if holes[idx(x, y)] != nil && tile(x, y) == " " {
            guards[i].trapped = 1
            if guards[i].gold {
                guards[i].gold = false
                if tile(x, y - 1) == " " { tiles[y - 1][x] = "$" }
            }
            return
        }
        if guards[i].gold {
            guards[i].carry += 1
            if guards[i].carry > 12 && tile(x, y) == " " && isSolid(tile(x, y + 1)) {
                tiles[y][x] = "$"
                guards[i].gold = false
                guards[i].carry = 0
            }
        }
    }

    private func climbOut(_ i: Int) {
        let g = guards[i]
        let dir = runner.x >= g.x ? 1 : -1
        for d in [dir, -dir] {
            let tx = g.x + d, ty = g.y - 1
            if tx >= 0 && tx < cols && !isSolid(tile(tx, ty)) && isSolid(tile(tx, g.y)) && guardAt(tx, ty, except: i) == nil {
                guards[i].trapped = 0
                guards[i].x = tx; guards[i].y = ty
                guards[i].face = d
                return
            }
        }
    }

    private func stepGuards() {
        for i in guards.indices {
            if guards[i].wait > 0 { guards[i].wait -= 1; continue }
            if guards[i].trapped > 0 {
                guards[i].trapped += 1
                if guards[i].trapped > escapeTicks { climbOut(i) }
                continue
            }
            let g = guards[i]
            if !supported(g.x, g.y, ignoring: i) {
                if g.y + 1 < rows && !isSolid(tile(g.x, g.y + 1)) { moveGuard(i, g.x, g.y + 1) }
                continue
            }
            var target = nextStep(i)
            if target == nil {
                // пути нет: просто идём в сторону бегуна по горизонтали
                let d = runner.x > g.x ? 1 : (runner.x < g.x ? -1 : 0)
                if d != 0 && !isSolid(tile(g.x + d, g.y)) { target = (g.x + d, g.y) }
            } else if Int.random(in: 0..<10) == 0 {
                let opts = graphNeighbors(g.x, g.y).filter { $0.1 == g.y }
                if let o = opts.randomElement() { target = o }
            }
            if let t = target, guardAt(t.0, t.1, except: i) == nil || (t.0 == runner.x && t.1 == runner.y) {
                moveGuard(i, t.0, t.1)
            }
        }
    }

    private func checkTouch() {
        for g in guards where g.wait == 0 && g.trapped == 0 && g.x == runner.x && g.y == runner.y {
            die()
            return
        }
    }

    // MARK: Ввод

    override func keyDown(with e: NSEvent) {
        if e.isARepeat { return }
        let k = e.keyCode
        if state == .levelDone {
            levelIdx += 1
            loadLevel()
            return
        }
        if state == .paused {                           // любая клавиша снимает паузу (P — только снимает, а не ставит заново)
            togglePause()
            if k == 35 { return }
        }
        switch k {
        case 35:
            togglePause()
            return
        case 49:                      // пробел: копать в ту сторону, куда смотрит бегун
            digReq = runner.face >= 0 ? 1 : -1
            kick()
            return
        case 123, 124, 125, 126, 0, 1, 2, 13:
            held.removeAll { $0 == k }
            held.append(k)
            latched = k
            if state == .paused { togglePause() }
            kick()
            return
        default:
            super.keyDown(with: e)
        }
    }

    /// Отзывчивость: если текущий шаг уже почти завершён, не ждём конца такта, а сразу делаем следующий
    private func kick() {
        guard state == .playing, acc >= tickDur * 0.6 else { return }
        tick()
        acc = 0
    }

    override func keyUp(with e: NSEvent) {
        held.removeAll { $0 == e.keyCode }
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        if newBtn.contains(p) { newGame(); return }
        if pauseBtn.contains(p) { togglePause(); return }
        switch state {
        case .over:
            if recs?.entering != true { newGame() }
        case .levelDone:
            levelIdx += 1
            loadLevel()
        case .paused:
            togglePause()
        default:
            break
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

    private func drawBrick(_ r: NSRect, concrete: Bool, height: CGFloat = 1) {
        let rr = NSRect(x: r.minX, y: r.maxY - r.height * height, width: r.width, height: r.height * height)
        if concrete {
            col(0.52, 0.54, 0.60).setFill()
            rr.fill()
            col(0.75, 0.77, 0.82).setFill()
            NSRect(x: rr.minX, y: rr.minY, width: rr.width, height: 2).fill()
            NSRect(x: rr.minX, y: rr.minY, width: 2, height: rr.height).fill()
            col(0.28, 0.30, 0.36).setFill()
            NSRect(x: rr.minX, y: rr.maxY - 2, width: rr.width, height: 2).fill()
            NSRect(x: rr.maxX - 2, y: rr.minY, width: 2, height: rr.height).fill()
            return
        }
        col(0.80, 0.32, 0.13).setFill()
        rr.fill()
        col(0.36, 0.10, 0.05).setFill()
        let h = r.height / 2
        NSRect(x: r.minX, y: r.minY + h - 1, width: r.width, height: 2).intersection(rr).fill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).intersection(rr).fill()
        NSRect(x: r.minX + r.width / 2 - 1, y: r.minY, width: 2, height: h).intersection(rr).fill()
        NSRect(x: r.minX + r.width / 4 - 1, y: r.minY + h, width: 2, height: h).intersection(rr).fill()
        NSRect(x: r.minX + r.width * 3 / 4 - 1, y: r.minY + h, width: 2, height: h).intersection(rr).fill()
        col(1.0, 0.62, 0.40, 0.7).setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).intersection(rr).fill()
    }

    private func drawLadder(_ r: NSRect) {
        col(0.45, 0.88, 1.0).setFill()
        NSRect(x: r.minX + 6, y: r.minY, width: 3, height: r.height).fill()
        NSRect(x: r.maxX - 9, y: r.minY, width: 3, height: r.height).fill()
        var y = r.minY + 3
        while y < r.maxY {
            NSRect(x: r.minX + 6, y: y, width: r.width - 12, height: 2).fill()
            y += 7
        }
    }

    private func drawGold(_ r: NSRect) {
        col(1.0, 0.82, 0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX + 6, y: r.maxY - 14, width: r.width - 12, height: 8), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: r.minX + 9, y: r.maxY - 20, width: r.width - 18, height: 7), xRadius: 3, yRadius: 3).fill()
        col(1.0, 0.97, 0.7).setFill()
        NSRect(x: r.minX + 9, y: r.maxY - 13, width: 5, height: 2).fill()
        NSRect(x: r.minX + 12, y: r.maxY - 19, width: 4, height: 2).fill()
    }

    /// Человечек с суставами, как в оригинале: бег — шаг ногами и маятник руками, лестница — поочерёдный хват,
    /// канат — перехват руками, падение — руки вверх, копание — руки вниз в сторону ямы
    private func drawActor(_ a: Actor, _ body: NSColor, t: CGFloat, isRunner: Bool) {
        let ax = (a.px + (CGFloat(a.x) - a.px) * t) * ts
        let ay = (a.py + (CGFloat(a.y) - a.py) * t) * ts
        let f = CGFloat(a.face >= 0 ? 1 : -1)
        let cx = ax + ts / 2
        let tl = tile(a.x, a.y)
        let below = tile(a.x, a.y + 1)
        let onLadder = tl == "H", onRope = tl == "-"
        let onGround = below == "#" || below == "@" || below == "H" || guardAt(a.x, a.y + 1) != nil
        let falling = !onLadder && !onRope && !onGround && a.trapped == 0
        let moved = state == .playing && (a.px != CGFloat(a.x) || a.py != CGFloat(a.y))
        let vertical = a.py != CGFloat(a.y)
        let ph = CGFloat(a.phase) + (moved ? t : 0)
        let sw: CGFloat = moved ? sin(ph * .pi) : 0         // качание шага: −1…1
        let lift: CGFloat = moved ? cos(ph * .pi) : 1

        let head = NSPoint(x: cx + f * 1.5, y: ay + 5.5)
        let shoulder = NSPoint(x: cx, y: ay + 10.5)
        let hip = NSPoint(x: cx - f * 0.5, y: ay + 19)
        var legA = (NSPoint(x: hip.x - 3, y: ay + 27), NSPoint(x: hip.x - 3, y: ay + 23))   // (стопа, колено)
        var legB = (NSPoint(x: hip.x + 3, y: ay + 27), NSPoint(x: hip.x + 3, y: ay + 23))
        var handA = (NSPoint(x: cx - 6, y: ay + 18), NSPoint(x: cx - 4, y: ay + 15))       // (кисть, локоть)
        var handB = (NSPoint(x: cx + 6, y: ay + 18), NSPoint(x: cx + 4, y: ay + 15))

        func leg(_ dx: CGFloat, _ up: CGFloat) -> (NSPoint, NSPoint) {
            let foot = NSPoint(x: hip.x + dx, y: ay + 27 - up)
            let knee = NSPoint(x: hip.x + dx * 0.45 + f * 2.5, y: hip.y + (foot.y - hip.y) * 0.5)
            return (foot, knee)
        }
        func arm(_ dx: CGFloat, _ dy: CGFloat) -> (NSPoint, NSPoint) {
            let hand = NSPoint(x: shoulder.x + dx, y: shoulder.y + dy)
            let elbow = NSPoint(x: shoulder.x + dx * 0.35 - f * 1.5, y: shoulder.y + 4.5)
            return (hand, elbow)
        }

        if a.trapped > 0 {
            handA = arm(-7, -8); handB = arm(7, -8)                     // охранник в яме машет руками
            legA = leg(-3, 0); legB = leg(3, 0)
        } else if isRunner && digTimer > 0 {
            handA = arm(f * 9, 9); handB = arm(f * 6, 11)               // копает: руки вниз к яме
            legA = leg(-4, 0); legB = leg(4, 0)
        } else if falling {
            handA = arm(-8, -6); handB = arm(8, -6)
            legA = leg(-5, 1); legB = leg(5, 2)
        } else if onLadder && (vertical || !onGround) {
            let k = moved ? sw : 0                                      // лазание: руки и ноги по очереди
            handA = (NSPoint(x: cx - 5, y: ay + 6 + 5 * k), NSPoint(x: cx - 7, y: ay + 11))
            handB = (NSPoint(x: cx + 5, y: ay + 6 - 5 * k), NSPoint(x: cx + 7, y: ay + 11))
            legA = (NSPoint(x: hip.x - 3, y: ay + 26 - 5 * k), NSPoint(x: hip.x - 5, y: ay + 22 - 3 * k))
            legB = (NSPoint(x: hip.x + 3, y: ay + 26 + 5 * k), NSPoint(x: hip.x + 5, y: ay + 22 + 3 * k))
        } else if onRope {
            let k = moved ? sw : 0                                      // канат: хват двумя руками, ноги болтаются
            handA = (NSPoint(x: cx - 3.5 + 2 * k, y: ay + 5), NSPoint(x: cx - 6, y: ay + 9))
            handB = (NSPoint(x: cx + 3.5 + 2 * k, y: ay + 5), NSPoint(x: cx + 6, y: ay + 9))
            legA = leg(-3 + 4 * k, 1); legB = leg(3 - 4 * k, 1)
        } else if moved {
            legA = leg(8 * sw, 4 * max(0, -lift)); legB = leg(-8 * sw, 4 * max(0, lift))   // бег
            handA = arm(-7 * sw, 8 - 1.5 * abs(sw)); handB = arm(7 * sw, 8 - 1.5 * abs(sw))
        } else if onLadder || onRope {
            handA = arm(-6, -3); handB = arm(6, -3)
        }

        let limb = NSBezierPath()
        limb.lineWidth = 3.4
        limb.lineCapStyle = .round
        limb.lineJoinStyle = .round
        limb.move(to: shoulder); limb.line(to: hip)
        for l in [legA, legB] { limb.move(to: hip); limb.line(to: l.1); limb.line(to: l.0) }
        for h in [handA, handB] { limb.move(to: shoulder); limb.line(to: h.1); limb.line(to: h.0) }
        body.setStroke()
        limb.stroke()
        body.blended(withFraction: 0.4, of: .white)?.setFill()
        NSBezierPath(ovalIn: NSRect(x: head.x - 4.3, y: head.y - 4.3, width: 8.6, height: 8.6)).fill()
        if a.gold {
            col(1.0, 0.82, 0.12).setFill()
            NSRect(x: cx + 2, y: ay + 11, width: 6, height: 4).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        col(0.02, 0.02, 0.05).setFill()
        bounds.fill()

        drawButton(newBtn, T("Новая игра"))
        drawButton(pauseBtn, state == .paused ? T("Продолжить") : T("Пауза"))
        drawString(T("Очки") + ": \(score)   " + T("Жизни") + ": \(lives)   " + T("Уровень") + ": \(levelIdx + 1)   "
                   + T("Золото") + ": \(goldOnField)",
                   NSRect(x: 290, y: 22, width: 518, height: 20), size: 13, color: .white, align: .right)

        NSGraphicsContext.saveGraphicsState()
        let tr = NSAffineTransform()
        tr.translateX(by: fx, yBy: fy)
        tr.concat()
        let fieldW = CGFloat(cols) * ts, fieldH = CGFloat(rows) * ts
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: fieldW, height: fieldH)).addClip()
        col(0, 0, 0).setFill()
        NSRect(x: 0, y: 0, width: fieldW, height: fieldH).fill()

        let t: CGFloat = state == .playing ? CGFloat(min(1, acc / tickDur)) : 1
        let tg: CGFloat = state == .playing ? CGFloat(min(1, gacc / guardDur)) : 1

        for y in 0..<rows {
            for x in 0..<cols {
                let r = NSRect(x: CGFloat(x) * ts, y: CGFloat(y) * ts, width: ts, height: ts)
                switch tiles[y][x] {
                case "#", "X":
                    drawBrick(r, concrete: false)
                case "@":
                    drawBrick(r, concrete: true)
                case "H":
                    drawLadder(r)
                case "-":
                    col(0.95, 0.85, 0.55).setFill()
                    NSRect(x: r.minX, y: r.minY + 5, width: r.width, height: 3).fill()
                case "$":
                    drawGold(r)
                default:
                    break
                }
                if let left = holes[idx(x, y)], tiles[y][x] == " " {
                    // яма зарастает: кирпич растёт снизу
                    if left < 5 { drawBrick(r, concrete: false, height: CGFloat(5 - left) / 5) }
                }
            }
        }
        // копание: трещины на кирпиче
        if digTimer > 0 {
            col(0, 0, 0, 0.7).setStroke()
            let r = NSRect(x: CGFloat(digX) * ts, y: CGFloat(digY) * ts, width: ts, height: ts)
            let p = NSBezierPath()
            p.lineWidth = 2
            let n = CGFloat(3 - digTimer)
            p.move(to: NSPoint(x: r.minX + 4, y: r.minY + 2)); p.line(to: NSPoint(x: r.minX + 4 + 5 * n, y: r.minY + 4 + 4 * n))
            p.move(to: NSPoint(x: r.maxX - 4, y: r.minY + 2)); p.line(to: NSPoint(x: r.maxX - 4 - 5 * n, y: r.minY + 4 + 4 * n))
            p.stroke()
        }

        for g in guards where g.wait == 0 {
            drawActor(g, col(0.98, 0.28, 0.40), t: tg, isRunner: false)
        }
        if state != .dying || Int(dyingLeft * 10) % 2 == 0 {
            drawActor(runner, col(0.35, 0.68, 1.0), t: t, isRunner: true)
        }
        NSGraphicsContext.restoreGraphicsState()

        col(0.55, 0.70, 0.95, 0.5).setStroke()
        let fb = NSBezierPath(rect: NSRect(x: fx, y: fy, width: CGFloat(cols) * ts, height: CGFloat(rows) * ts).insetBy(dx: -1, dy: -1))
        fb.lineWidth = 2
        fb.stroke()

        recs?.draw(in: recsRect)

        let fr = NSRect(x: fx, y: fy, width: CGFloat(cols) * ts, height: CGFloat(rows) * ts)
        drawString(T("← → ↑ ↓ — бег, пробел — копать в сторону взгляда, P — пауза"),
                   NSRect(x: fx, y: fr.maxY + 12, width: 760, height: 18), size: 12, color: NSColor(white: 1, alpha: 0.65))

        var title = "", sub = ""
        switch state {
        case .paused:
            title = T("Пауза"); sub = T("Нажмите, чтобы продолжить")
        case .levelDone:
            title = T("Уровень") + " \(levelIdx + 1) " + T("пройден!")
            sub = "+1500   ·   " + T("Нажмите, чтобы продолжить")
        case .over:
            title = T("Игра окончена")
            sub = T("Очки") + ": \(score)   ·   " + T("Нажмите, чтобы начать заново")
        default:
            break
        }
        if !title.isEmpty {
            NSColor(white: 0, alpha: 0.6).setFill()
            fr.fill()
            drawString(title, NSRect(x: fr.minX, y: fr.midY - 36, width: fr.width, height: 40), size: 30,
                       color: .white, align: .center, bold: true)
            drawString(sub, NSRect(x: fr.minX, y: fr.midY + 10, width: fr.width, height: 22), size: 15,
                       color: NSColor(white: 1, alpha: 0.85), align: .center)
        }
    }
}

final class LodeWindowController: NSObject, NSWindowDelegate {
    static let shared = LodeWindowController()
    private var window: NSWindow?
    private var game: LodeView?

    private var title: String { return "Lode Runner" }

    func show() {
        if window == nil {
            let size = NSSize(width: 1044, height: 590)
            LodeSound.warmUp()
            let v = LodeView(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = v
            w.delegate = self
            if !w.setFrameUsingName("LodeRunnerWindow") { w.center() }
            w.setFrameAutosaveName("LodeRunnerWindow")
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

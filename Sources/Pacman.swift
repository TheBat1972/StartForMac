// «Передохни»: Pacman — классический Пакман, перенесённый с Qt/C++ («SnakeLive/Pacman») на Swift.
// Два лабиринта оригинала (выбираются случайно), пять привидений, таблетки-«пилюли» делают привидений съедобными,
// порталы по краям. Пакман и привидения двигаются плавно (непрерывно между клетками, без прыжков).
// Три жизни, уровни, рекорды. Картинки и звуки — в папке PacmanRes внутри приложения.
import AppKit

// MARK: - Ресурсы и звуки

private enum PacmanRes {
    private static let dir: URL? = Bundle.main.resourceURL?.appendingPathComponent("PacmanRes")
    private static var images: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let i = images[name] { return i }
        guard let u = dir?.appendingPathComponent(name), let i = NSImage(contentsOf: u) else { return nil }
        images[name] = i
        return i
    }

    static func url(_ name: String) -> URL? { return dir?.appendingPathComponent(name) }
}

private enum PacmanSound: String, CaseIterable {
    case pill = "pill.wav", ghost = "ghost.wav", over = "over.wav"
    private static var cache: [String: NSSound] = [:]

    private func sound() -> NSSound? {
        if let s = PacmanSound.cache[rawValue] { return s }
        guard let u = PacmanRes.url(rawValue), let s = NSSound(contentsOf: u, byReference: false) else { return nil }
        PacmanSound.cache[rawValue] = s
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
        for k in PacmanSound.allCases {
            guard let s = k.sound() else { continue }
            s.volume = 0
            s.play()
            s.stop()
        }
    }
}

// MARK: - Лабиринты оригинала (1 — стена, 2 — точка, 3 — таблетка, 0 — пусто)

private let pacMazes: [[[Int]]] = [
    [
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,3,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2,3,1],
        [1,2,1,1,2,1,1,1,1,2,1,2,1,1,1,1,2,1,1,2,1],
        [1,2,1,1,2,1,1,1,1,2,1,2,1,1,1,1,2,1,1,2,1],
        [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
        [1,2,1,1,2,1,2,1,1,1,1,1,1,1,2,1,2,1,1,2,1],
        [1,2,2,2,2,1,2,2,2,2,1,2,2,2,2,1,2,2,2,2,1],
        [1,1,1,1,2,1,1,1,1,0,1,0,1,1,1,1,2,1,1,1,1],
        [1,0,0,1,2,1,0,0,0,0,0,0,0,0,0,1,2,1,0,0,1],
        [1,1,1,1,2,1,0,1,1,1,0,1,1,1,0,1,2,1,1,1,1],
        [2,2,2,2,2,0,0,1,0,0,0,0,0,1,0,0,2,2,2,2,2],
        [1,1,1,1,2,1,0,1,1,1,0,1,1,1,0,1,2,1,1,1,1],
        [1,0,0,1,2,1,0,0,0,0,0,0,0,0,0,1,2,1,0,0,1],
        [1,1,1,1,2,1,0,1,1,1,1,1,1,1,0,1,2,1,1,1,1],
        [1,2,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2,2,1],
        [1,2,1,1,2,1,1,1,2,3,1,3,2,1,1,1,2,1,1,2,1],
        [1,2,2,1,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,2,1],
        [1,1,2,1,2,1,2,1,1,1,1,1,1,1,2,1,2,1,2,1,1],
        [1,2,2,2,2,1,2,2,2,2,1,2,2,2,2,1,2,2,2,2,1],
        [1,2,1,1,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,2,1],
        [1,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
    ],
    [
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,3,2,2,2,2,0,1,0,0,0,0,0,1,0,2,2,2,2,3,1],
        [1,2,1,2,1,2,2,1,1,0,0,0,1,1,0,2,1,2,1,2,1],
        [1,2,1,2,2,2,2,2,0,1,0,1,0,2,2,2,2,2,1,2,1],
        [1,2,1,2,2,1,1,2,2,1,1,1,2,2,1,1,2,2,1,2,1],
        [1,2,1,2,2,2,1,2,2,2,2,2,2,2,1,2,2,2,1,2,1],
        [1,2,1,2,3,2,1,2,2,1,1,1,2,2,1,2,3,2,1,2,1],
        [1,2,1,1,1,2,2,2,2,2,2,2,2,2,2,2,1,1,1,2,1],
        [1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,2,2,2,2,2,1],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [2,2,2,2,2,2,0,1,0,0,0,0,0,1,0,2,2,2,2,2,2],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [1,0,0,0,1,2,0,0,0,0,0,0,0,0,0,2,1,0,0,0,1],
        [1,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,1],
        [1,1,1,1,1,2,1,1,1,2,2,2,1,1,1,2,1,1,1,1,1],
        [1,2,2,2,2,2,2,1,2,2,0,2,2,1,2,2,2,2,2,2,1],
        [1,2,1,1,2,1,2,2,2,2,0,2,2,2,2,1,2,1,1,2,1],
        [1,2,1,1,2,2,2,2,2,2,0,2,2,2,2,2,2,1,1,2,1],
        [1,2,1,1,2,2,2,1,2,2,1,2,2,1,2,2,2,1,1,2,1],
        [1,2,1,1,2,1,2,2,2,2,2,2,2,2,2,1,2,1,1,2,1],
        [1,3,2,2,2,2,2,2,1,1,1,1,1,2,2,2,2,2,2,3,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
    ],
    [
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,1],
        [1,2,1,1,2,1,2,1,2,1,1,1,2,1,2,1,2,1,1,2,1],
        [1,2,1,1,2,2,2,2,2,1,1,1,2,2,2,2,2,1,1,2,1],
        [1,2,2,2,2,2,1,2,2,2,2,2,2,2,1,2,2,2,2,2,1],
        [1,2,1,1,2,1,2,2,2,1,1,1,2,2,2,1,2,1,1,2,1],
        [1,2,1,1,2,1,2,1,2,1,1,1,2,1,2,1,2,1,1,2,1],
        [1,2,2,2,2,1,2,1,2,2,2,2,2,1,2,1,2,2,2,2,1],
        [1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,2,2,2,2,2,1],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [2,2,2,2,2,2,0,1,0,0,0,0,0,1,0,2,2,2,2,2,2],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,2,2,2,2,2,1],
        [1,2,1,1,2,1,2,1,1,2,2,2,1,1,2,1,2,1,1,2,1],
        [1,2,1,1,2,2,2,2,2,1,2,1,2,2,2,2,2,1,1,2,1],
        [1,2,2,2,2,2,1,2,2,2,2,2,2,2,1,2,2,2,2,2,1],
        [1,2,1,1,2,2,2,1,1,2,0,2,1,1,2,2,2,1,1,2,1],
        [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
        [1,1,2,1,2,1,2,1,2,1,1,1,2,1,2,1,2,1,2,1,1],
        [1,3,2,1,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,3,1],
        [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
    ],
    [
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,1],
        [1,2,1,1,2,1,1,1,1,2,1,2,1,1,1,1,2,1,1,2,1],
        [1,2,1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1,1,2,1],
        [1,2,2,2,2,1,1,2,1,2,1,2,1,2,1,1,2,2,2,2,1],
        [1,1,2,1,2,1,2,2,1,2,2,2,1,2,2,1,2,1,2,1,1],
        [1,2,2,1,2,1,2,1,1,2,1,2,1,1,2,1,2,1,2,2,1],
        [1,2,1,1,2,2,2,1,2,2,2,2,2,1,2,2,2,1,1,2,1],
        [1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,2,2,2,2,2,1],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [2,2,2,2,2,2,0,1,0,0,0,0,0,1,0,2,2,2,2,2,2],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [1,2,2,2,1,2,0,0,0,0,0,0,0,0,0,2,1,2,2,2,1],
        [1,2,1,2,1,2,1,1,2,1,1,1,2,1,1,2,1,2,1,2,1],
        [1,2,1,2,2,2,1,2,2,2,2,2,2,2,1,2,2,2,1,2,1],
        [1,2,1,2,1,2,1,2,1,1,2,1,1,2,1,2,1,2,1,2,1],
        [1,2,2,2,1,2,2,2,1,2,0,2,1,2,2,2,1,2,2,2,1],
        [1,1,1,2,1,2,1,2,1,2,1,2,1,2,1,2,1,2,1,1,1],
        [1,3,2,2,1,2,2,2,1,2,2,2,1,2,2,2,1,2,2,3,1],
        [1,2,1,1,1,1,1,2,1,1,2,1,1,2,1,1,1,1,1,2,1],
        [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
    ],
    [
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
        [1,3,2,2,1,2,2,2,2,2,1,2,2,2,2,2,1,2,2,3,1],
        [1,2,1,2,1,2,1,1,1,2,1,2,1,1,1,2,1,2,1,2,1],
        [1,2,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,1],
        [1,2,1,1,1,1,2,1,1,2,1,2,1,1,2,1,1,1,1,2,1],
        [1,2,2,2,2,2,2,1,2,2,2,2,2,1,2,2,2,2,2,2,1],
        [1,2,1,1,1,1,2,1,2,1,2,1,2,1,2,1,1,1,1,2,1],
        [1,2,1,2,2,2,2,1,2,1,2,1,2,1,2,2,2,2,1,2,1],
        [1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,2,2,2,2,2,1],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [2,2,2,2,2,2,0,1,0,0,0,0,0,1,0,2,2,2,2,2,2],
        [1,1,1,1,1,2,0,1,1,1,0,1,1,1,0,2,1,1,1,1,1],
        [1,2,2,2,2,2,0,0,0,0,0,0,0,0,0,2,2,2,2,2,1],
        [1,2,1,1,2,1,2,1,1,1,1,1,1,1,2,1,2,1,1,2,1],
        [1,2,2,2,2,1,2,2,2,2,2,2,2,2,2,1,2,2,2,2,1],
        [1,2,1,1,2,1,2,1,1,1,2,1,1,1,2,1,2,1,1,2,1],
        [1,2,1,1,2,2,2,2,2,2,0,2,2,2,2,2,2,1,1,2,1],
        [1,3,2,1,2,1,1,2,1,2,2,2,1,2,1,1,2,1,2,3,1],
        [1,1,2,1,2,1,2,2,1,2,1,2,1,2,2,1,2,1,2,1,1],
        [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
        [1,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,1],
        [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
    ]
]

// MARK: - Движущиеся фигуры

/// Фигура, непрерывно идущая по клеткам: (x, y) — клетка, из которой идёт, (dx, dy) — направление, t — доля пути 0…1
private struct PacMover {
    var x: Int, y: Int
    var dx = 0, dy = 0
    var t = 0.0
    var moving: Bool { return dx != 0 || dy != 0 }
    /// Точная позиция для рисования (в клетках, может выйти за край поля при переходе через портал)
    var px: Double { return Double(x) + Double(dx) * t }
    var py: Double { return Double(y) + Double(dy) * t }
}

private struct PacGhost {
    var m: PacMover
    var tip: Int            // 0…4: красный, оранжевый, «F», «S», «T»
    var scared = false
    var wait: Double        // пауза в «домике» перед выходом, секунды
    var faceRight = true
}

private struct PacFloat {
    var text: String
    var p: CGPoint          // в клетках
    var life: Double
}

final class PacmanView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private enum State { case ready, playing, paused, dying, levelDone, over }

    private let Xs = 21, Ys = 22
    private let cs: CGFloat = 28
    private let origin = CGPoint(x: 20, y: 56)
    private var W: CGFloat { return CGFloat(Xs) * cs }
    private var H: CGFloat { return CGFloat(Ys) * cs }
    private let home = (x: 10, y: 10)
    private let start = (x: 10, y: 16)
    private let ghostNames = ["r", "o", "f", "s", "t"]
    private let chaseProb = [0.9, 0.55, 0.75, 0.65, 0.8]

    private var maze: [[Int]] = pacMazes[0]
    private var dotsLeft = 0
    private var pac = PacMover(x: 10, y: 16)
    private var want = (dx: 0, dy: 0)
    private var face = "r"
    private var ghosts: [PacGhost] = []
    private var floats: [PacFloat] = []
    private var level = 1, score = 0, lives = 3
    private var state: State = .ready
    private var autoPaused = false
    private var frightT = 0.0
    private var deathT = 0.0
    private var anim = 0.0
    private var chomp = 0.0      // фаза жевания: один полный «рот открыт-закрыт» на ~1,1 клетки пути

    private var timer: Timer?
    private var lastT: CFTimeInterval = 0

    private var recs: GameRecordsPanel?
    private let recsRect = NSRect(x: 638, y: 56, width: 190, height: 480)
    private let newBtn = NSRect(x: 150, y: 12, width: 120, height: 30)
    private let pauseBtn = NSRect(x: 280, y: 12, width: 110, height: 30)

    /// Сложность (скорость): 0 — лёгкая, 1 — обычная, 2 — трудная; хранится в настройках
    private var difficulty: Int = {
        let d = UserDefaults.standard.object(forKey: "pacman.difficulty") as? Int ?? 1
        return max(0, min(2, d))
    }()
    private let diffMul = [0.7, 1.0, 1.3]
    private let diffNames = ["Легко", "Нормально", "Трудно"]
    /// Привидений всегда четыре, сложность меняет только скорость
    private var ghostCount: Int { return 4 }
    private let diffBtn = NSRect(x: 400, y: 12, width: 150, height: 30)

    private var speedMul: Double { return min(1.5, 1 + 0.05 * Double(level - 1)) * diffMul[difficulty] }
    private var pacSpeed: Double { return 3.6 * speedMul }

    override init(frame: NSRect) {
        super.init(frame: frame)
        recs = GameRecordsPanel(key: "pacman.records", host: self)
        recs?.onFinish = { [weak self] in self?.newGame() }
        newGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate() }

    // MARK: Уровни

    private func newGame() {
        recs?.cancel()
        level = 1; score = 0; lives = 3
        setupLevel()
    }

    private var mazeIndex = -1

    private func setupLevel() {
        // лабиринт каждый раз другой, не тот же самый подряд
        var idx = Int.random(in: 0..<pacMazes.count)
        if idx == mazeIndex { idx = (idx + 1 + Int.random(in: 0..<(pacMazes.count - 1))) % pacMazes.count }
        mazeIndex = idx
        maze = pacMazes[idx]
        dotsLeft = maze.reduce(0) { $0 + $1.filter { $0 == 2 || $0 == 3 }.count }
        resetActors()
        floats = []
        frightT = 0
        autoPaused = false
        state = .ready
        stopTimer()
        needsDisplay = true
    }

    private func resetActors() {
        pac = PacMover(x: start.x, y: start.y)
        if maze[start.y][start.x] != 1 {
            if maze[start.y][start.x] != 0 { dotsLeft -= 1 }
            maze[start.y][start.x] = 0
        }
        want = (0, 0)
        face = "r"
        ghosts = (0..<ghostCount).map { i in
            PacGhost(m: PacMover(x: home.x, y: home.y), tip: i, scared: false, wait: 1.2 + Double(i) * 1.8)
        }
        frightT = 0
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
        let dt = min(0.05, now - lastT)
        lastT = now
        anim += dt
        floats = floats.compactMap { (f0: PacFloat) -> PacFloat? in
            var f = f0
            f.life -= dt
            f.p.y -= CGFloat(dt) * 1.2
            return f.life > 0 ? f : nil
        }

        if state == .dying {
            deathT -= dt
            if deathT <= 0 { finishDeath() }
            needsDisplay = true
            return
        }
        guard state == .playing else { return }

        if pac.moving { chomp += dt * pacSpeed * 0.9 }
        movePac(dt)
        if frightT > 0 {
            frightT -= dt
            if frightT <= 0 { for i in ghosts.indices { ghosts[i].scared = false } }
        }
        for i in ghosts.indices { moveGhost(i, dt) }
        checkCollisions()
        if state == .playing && dotsLeft <= 0 {
            state = .levelDone
            stopTimer()
            score += 100 * level
        }
        needsDisplay = true
    }

    // MARK: Движение

    private func wrapX(_ x: Int) -> Int { return (x + Xs) % Xs }

    private func canGo(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Bool {
        let ny = y + dy
        if ny < 0 || ny >= Ys { return false }
        let nx = x + dx
        if nx < 0 || nx >= Xs {
            return maze[ny][wrapX(nx)] != 1 && maze[ny][x] != 1
        }
        return maze[ny][nx] != 1
    }

    private func movePac(_ dt: Double) {
        var rem = pacSpeed * dt
        var guardN = 0
        while guardN < 8 {
            guardN += 1
            if !pac.moving {
                if (want.dx != 0 || want.dy != 0) && canGo(pac.x, pac.y, want.dx, want.dy) {
                    pac.dx = want.dx; pac.dy = want.dy; pac.t = 0
                } else { return }
            }
            // мгновенный разворот посреди пути
            if want.dx == -pac.dx && want.dy == -pac.dy && pac.t > 0 && pac.x + pac.dx >= 0 && pac.x + pac.dx < Xs {
                pac.x += pac.dx; pac.y += pac.dy
                pac.dx = -pac.dx; pac.dy = -pac.dy
                pac.t = 1 - pac.t
            }
            if pac.dx != 0 { face = pac.dx > 0 ? "r" : "l" } else { face = pac.dy > 0 ? "d" : "u" }
            let need = 1 - pac.t
            if rem < need { pac.t += rem; return }
            rem -= need
            // пришли в центр клетки
            pac.x = wrapX(pac.x + pac.dx)
            pac.y += pac.dy
            pac.t = 0
            eat(pac.x, pac.y)
            if (want.dx != 0 || want.dy != 0) && canGo(pac.x, pac.y, want.dx, want.dy) {
                pac.dx = want.dx; pac.dy = want.dy
            } else if !canGo(pac.x, pac.y, pac.dx, pac.dy) {
                pac.dx = 0; pac.dy = 0
                return
            }
        }
    }

    private func eat(_ x: Int, _ y: Int) {
        let v = maze[y][x]
        if v == 2 {
            maze[y][x] = 0; dotsLeft -= 1; score += 10
        } else if v == 3 {
            maze[y][x] = 0; dotsLeft -= 1; score += 50
            PacmanSound.pill.play()
            frightT = 8
            for i in ghosts.indices where ghosts[i].wait <= 0 { ghosts[i].scared = true }
        }
    }

    private func moveGhost(_ i: Int, _ dt: Double) {
        if ghosts[i].wait > 0 {
            ghosts[i].wait -= dt
            return
        }
        let base = ghosts[i].scared ? 2.1 : 3.0
        var rem = base * speedMul * dt
        var g = ghosts[i]
        var n = 0
        while n < 8 {
            n += 1
            if !g.m.moving { chooseDir(&g) }
            if !g.m.moving { break }
            let need = 1 - g.m.t
            if rem < need { g.m.t += rem; break }
            rem -= need
            g.m.x = wrapX(g.m.x + g.m.dx)
            g.m.y += g.m.dy
            g.m.t = 0
            chooseDir(&g)
        }
        if g.m.dx != 0 { g.faceRight = g.m.dx > 0 }
        ghosts[i] = g
    }

    /// Выбор направления в центре клетки: без разворота (кроме тупика); догоняет или убегает от Пакмана
    private func chooseDir(_ g: inout PacGhost) {
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        var opts = dirs.filter { canGo(g.m.x, g.m.y, $0.0, $0.1) }
        if opts.count > 1 { opts.removeAll { $0.0 == -g.m.dx && $0.1 == -g.m.dy && g.m.moving } }
        guard !opts.isEmpty else { g.m.dx = 0; g.m.dy = 0; return }
        var pick = opts[Int.random(in: 0..<opts.count)]
        if Double.random(in: 0...1) < chaseProb[g.tip] {
            func d2(_ o: (Int, Int)) -> Int {
                let ax = g.m.x + o.0 - pac.x, ay = g.m.y + o.1 - pac.y
                return ax * ax + ay * ay
            }
            pick = g.scared ? opts.max { d2($0) < d2($1) }! : opts.min { d2($0) < d2($1) }!
        }
        g.m.dx = pick.0; g.m.dy = pick.1; g.m.t = 0
    }

    private func checkCollisions() {
        for i in ghosts.indices where ghosts[i].wait <= 0 {
            let dx = ghosts[i].m.px - pac.px, dy = ghosts[i].m.py - pac.py
            if dx * dx + dy * dy < 0.5 * 0.5 {
                if ghosts[i].scared {
                    score += 200
                    PacmanSound.ghost.play()
                    floats.append(PacFloat(text: "+200", p: CGPoint(x: ghosts[i].m.px + 0.5, y: ghosts[i].m.py), life: 1))
                    ghosts[i] = PacGhost(m: PacMover(x: home.x, y: home.y), tip: ghosts[i].tip, scared: false, wait: 3)
                } else {
                    state = .dying
                    deathT = 1.0
                    PacmanSound.over.play()
                    return
                }
            }
        }
    }

    private func finishDeath() {
        lives -= 1
        if lives <= 0 {
            state = .over
            stopTimer()
            needsDisplay = true
            if score > 0 { recs?.beginEntry(score: score, in: recsRect) }
        } else {
            resetActors()
            state = .ready
            stopTimer()
        }
        needsDisplay = true
    }

    // MARK: Пауза

    private func setPaused(_ p: Bool) {
        if p {
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
        if state == .playing { setPaused(true); autoPaused = true }
    }

    /// Окно снова показано: продолжаем, если пауза была автоматической
    func resume() {
        if state == .paused && autoPaused { setPaused(false) }
    }

    // MARK: Управление

    private func begin() {
        guard state == .ready else { return }
        state = .playing
        startTimer()
        needsDisplay = true
    }

    private func action() {
        switch state {
        case .ready: begin()
        case .playing: setPaused(true)
        case .paused: setPaused(false)
        case .levelDone: level += 1; setupLevel()
        case .over: if recs?.entering != true { newGame() }
        case .dying: break
        }
    }

    override func keyDown(with e: NSEvent) {
        var d: (Int, Int)?
        switch e.keyCode {
        case 123, 0: d = (-1, 0)
        case 124, 2: d = (1, 0)
        case 125, 1: d = (0, 1)
        case 126, 13: d = (0, -1)
        case 49, 35: action(); return
        default: super.keyDown(with: e); return
        }
        if let d = d {
            want = (d.0, d.1)
            if state == .ready { begin() }
        }
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if newBtn.contains(p) { recs?.cancel(); newGame(); return }
        if diffBtn.contains(p) {
            difficulty = (difficulty + 1) % 3
            UserDefaults.standard.set(difficulty, forKey: "pacman.difficulty")
            while ghosts.count > ghostCount { ghosts.removeLast() }
            while ghosts.count < ghostCount {
                ghosts.append(PacGhost(m: PacMover(x: home.x, y: home.y), tip: ghosts.count, scared: false, wait: 2))
            }
            needsDisplay = true
            return
        }
        if pauseBtn.contains(p) {
            if state == .playing { setPaused(true) } else if state == .paused { setPaused(false) }
            return
        }
        if recsRect.insetBy(dx: -10, dy: -8).contains(p) { return }
        action()
    }

    // MARK: Рисование

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
        guard let img = PacmanRes.image(name) else { return false }
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        return true
    }

    private func button(_ r: NSRect, _ title: String, enabled: Bool = true) {
        NSColor(white: 1, alpha: enabled ? 0.2 : 0.08).setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        drawString(title, NSRect(x: r.minX, y: r.minY + 7, width: r.width, height: 18), size: 13,
                   color: NSColor(white: 1, alpha: enabled ? 1 : 0.5), align: .center)
    }

    /// Прямоугольник клетки с дробными координатами (для плавного движения)
    private func cell(_ px: Double, _ py: Double, scale: CGFloat = 1) -> NSRect {
        let s = cs * scale
        return NSRect(x: origin.x + CGFloat(px) * cs + (cs - s) / 2, y: origin.y + CGFloat(py) * cs + (cs - s) / 2, width: s, height: s)
    }

    /// Рисует Пакмана с ртом разной ширины: open 0 — закрыт, 1 — широко открыт (дальше — раскрытие при гибели)
    private func drawPac(_ r: NSRect, open: CGFloat, alpha: CGFloat) {
        let rad = r.width / 2 * 0.94
        let half = min(172, 3 + 34 * open)
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: r.midX, yBy: r.midY)
        switch face {
        case "l": t.scaleX(by: -1, yBy: 1)
        case "d": t.rotate(byDegrees: 90)
        case "u": t.rotate(byDegrees: -90)
        default: break
        }
        t.concat()
        let body = NSBezierPath()
        body.move(to: .zero)
        body.appendArc(withCenter: .zero, radius: rad, startAngle: half, endAngle: 360 - half, clockwise: false)
        body.close()
        NSGradient(starting: NSColor(calibratedRed: 1, green: 0.93, blue: 0.45, alpha: alpha),
                   ending: NSColor(calibratedRed: 1, green: 0.76, blue: 0, alpha: alpha))?
            .draw(in: body, relativeCenterPosition: NSPoint(x: -0.2, y: -0.25))
        NSColor(calibratedWhite: 0.1, alpha: alpha).setStroke()
        body.lineWidth = 1.3
        body.stroke()
        // глаз
        let er = rad * 0.15
        let eye = NSRect(x: rad * 0.28 - er, y: -rad * 0.5 - er, width: er * 2, height: er * 2)
        NSColor(calibratedRed: 0.25, green: 0.2, blue: 0.05, alpha: alpha).setFill()
        NSBezierPath(ovalIn: eye).fill()
        NSColor(white: 1, alpha: 0.7 * alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: eye.minX + er * 0.35, y: eye.minY + er * 0.25, width: er * 0.5, height: er * 0.5)).fill()
        ctx.restoreGraphicsState()
    }

    override func draw(_ dirtyRect: NSRect) {
        // фон
        if let bg = PacmanRes.image("pacfon.jpg") {
            let s = max(bounds.width / bg.size.width, bounds.height / bg.size.height)
            let w = bg.size.width * s, h = bg.size.height * s
            bg.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.15, alpha: 1).setFill()
            bounds.fill()
        }

        plate(NSRect(x: 10, y: 6, width: bounds.width - 20, height: 42))
        plate(NSRect(x: 10, y: origin.y + H + 6, width: W + 20, height: 30))

        // шапка
        drawString(T("Очки") + ": \(score)", NSRect(x: 20, y: 14, width: 125, height: 26), size: 18, bold: true)
        button(newBtn, T("Новая игра"))
        button(pauseBtn, state == .paused ? T("Продолжить") : T("Пауза"), enabled: state == .playing || state == .paused)
        button(diffBtn, T("Сложность") + ": " + T(diffNames[difficulty]))
        drawString(T("Уровень") + " \(level)   " + T("Жизни") + ": \(lives)",
                   NSRect(x: 560, y: 16, width: 270, height: 22), size: 14, align: .right)

        // поле
        let field = NSRect(x: origin.x, y: origin.y, width: W, height: H)
        NSColor(white: 0, alpha: 0.72).setFill()
        field.fill()
        NSColor(white: 1, alpha: 0.5).setStroke()
        NSBezierPath(rect: field.insetBy(dx: -1, dy: -1)).stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: field).addClip()

        let pulse = 0.8 + 0.2 * CGFloat(sin(anim * 8))
        for y in 0..<Ys {
            for x in 0..<Xs {
                let v = maze[y][x]
                if v == 0 { continue }
                let r = NSRect(x: origin.x + CGFloat(x) * cs, y: origin.y + CGFloat(y) * cs, width: cs, height: cs)
                switch v {
                case 1:
                    if !drawImage("1.png", in: r) {
                        NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.8, alpha: 1).setFill()
                        NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
                    }
                case 2:
                    if !drawImage("2.png", in: r) {
                        NSColor(calibratedRed: 1, green: 0.9, blue: 0.6, alpha: 1).setFill()
                        NSBezierPath(ovalIn: r.insetBy(dx: cs * 0.4, dy: cs * 0.4)).fill()
                    }
                default:
                    let pr = r.insetBy(dx: cs * (1 - pulse) / 2, dy: cs * (1 - pulse) / 2)
                    if !drawImage("3.png", in: pr) {
                        NSColor.white.setFill()
                        NSBezierPath(ovalIn: pr.insetBy(dx: cs * 0.22, dy: cs * 0.22)).fill()
                    }
                }
            }
        }

        // привидения
        let blink = frightT > 0 && frightT < 2 && Int(frightT * 5) % 2 == 0
        for g in ghosts {
            let side = g.faceRight ? "r" : "l"
            let name: String
            if g.scared && !blink { name = "g" + side } else { name = ghostNames[g.tip] + side }
            let r = cell(g.m.px, g.m.py)
            if !drawImage(name + ".png", in: r) {
                (g.scared ? NSColor.cyan : NSColor.red).setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
            }
        }

        // Пакман: рот открывается и закрывается, пока он идёт; при гибели раскрывается и исчезает
        var open: CGFloat = pac.moving ? CGFloat(0.06 + 0.94 * abs(sin(chomp * Double.pi))) : 0.5
        var alpha: CGFloat = 1
        var scale: CGFloat = 1
        if state == .dying {
            open = 1 + CGFloat(1 - deathT) * 4
            alpha = CGFloat(max(0, min(1, deathT * 1.6)))
            scale = 1 - CGFloat(1 - deathT) * 0.3
        }
        drawPac(cell(pac.px, pac.py, scale: scale), open: open, alpha: alpha)

        // всплывающие очки
        for f in floats {
            drawString(f.text, NSRect(x: origin.x + f.p.x * cs - 25, y: origin.y + f.p.y * cs - 8, width: 50, height: 16), size: 13,
                       color: NSColor(calibratedRed: 1, green: 0.9, blue: 0.4, alpha: CGFloat(min(1, f.life * 2))),
                       align: .center, bold: true)
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // подвал
        drawString(T("Стрелки или WASD — движение · пробел — пауза · съешьте все точки"),
                   NSRect(x: 20, y: origin.y + H + 13, width: W, height: 18), size: 12,
                   color: NSColor(white: 1, alpha: 0.9))

        // рекорды
        plate(recsRect.insetBy(dx: -10, dy: -8))
        recs?.draw(in: recsRect)

        // завеса и надписи
        var title = "", sub = ""
        switch state {
        case .ready:
            if level == 1 && score == 0 { title = "Pacman" }
            sub = T("Нажмите пробел или стрелку, чтобы начать")
        case .paused:
            title = T("Пауза"); sub = T("Нажмите, чтобы продолжить")
        case .levelDone:
            title = T("Уровень") + " \(level) " + T("пройден!"); sub = T("Нажмите, чтобы продолжить")
        case .over:
            title = T("Игра окончена")
            sub = T("Очки") + ": \(score)   ·   " + T("Нажмите, чтобы начать заново")
        case .playing, .dying:
            break
        }
        if !sub.isEmpty {
            let y = state == .ready ? field.midY + 60 : field.midY
            NSColor(white: 0, alpha: state == .ready ? 0.35 : 0.6).setFill()
            NSBezierPath(roundedRect: NSRect(x: field.minX + 20, y: y - 46, width: field.width - 40, height: 84), xRadius: 10, yRadius: 10).fill()
            if !title.isEmpty {
                drawString(title, NSRect(x: field.minX, y: y - 40, width: field.width, height: 40), size: 30,
                           color: NSColor(calibratedRed: 1, green: 0.88, blue: 0.2, alpha: 1), align: .center, bold: true)
            }
            drawString(sub, NSRect(x: field.minX, y: y + 6, width: field.width, height: 22), size: 15,
                       color: NSColor(white: 1, alpha: 0.9), align: .center)
        }
    }
}

final class PacmanWindowController: NSObject, NSWindowDelegate {
    static let shared = PacmanWindowController()
    private var window: NSWindow?
    private var game: PacmanView?

    func show() {
        if window == nil {
            let size = NSSize(width: 850, height: 720)
            PacmanSound.warmUp()
            let v = PacmanView(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = v
            w.delegate = self
            if !w.setFrameUsingName("PacmanWindow") { w.center() }
            w.setFrameAutosaveName("PacmanWindow")
            window = w
            game = v
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = "Pacman"
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

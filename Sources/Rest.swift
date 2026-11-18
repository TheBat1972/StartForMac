// «Передохни»: тетрис, перенесённый с Python (PySide6) на Swift. Открывается из меню инструментов «Пуска».
// Стакан 10×21, фигуры и матрицы поворота — те же, что в исходной игре; рекорды хранятся в настройках приложения.
import AppKit

// MARK: - Рекорды

struct RestRecord: Codable {
    let name: String
    let score: Int
}

/// Таблица лучших результатов: 12 записей в настройках приложения (UserDefaults)
enum RestRecords {
    private static let key = "rest.records.guideline"   // очки по правилам Guideline; прежние таблицы не смешиваются
    static let limit = 12

    static func load() -> [RestRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([RestRecord].self, from: data) else { return [] }
        return list
    }

    /// Добавляет результат, оставляет лучшие и возвращает обновлённую таблицу
    @discardableResult
    static func add(name: String, score: Int) -> [RestRecord] {
        var list = load()
        list.append(RestRecord(name: name, score: score))
        list.sort { $0.score > $1.score }
        list = Array(list.prefix(limit))
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
        return list
    }
}

// MARK: - Фигуры

private struct RestShape {
    let start: [Int]          // x0,y0,x1,y1,… четырёх блоков
    let dx: [[Int]]           // смещения по x при поворотах (4 положения × 4 блока)
    let dy: [[Int]]
}

private let restShapes: [Int: RestShape] = [
    1: RestShape(start: [4,0,5,0,5,1,6,1],
                 dx: [[0,-1,0,-1],[0,1,0,1],[0,-1,0,-1],[0,1,0,1]],
                 dy: [[2,1,0,-1],[-2,-1,0,1],[2,1,0,-1],[-2,-1,0,1]]),
    2: RestShape(start: [4,1,5,1,5,0,6,0],
                 dx: [[1,0,1,0],[-1,0,-1,0],[1,0,1,0],[-1,0,-1,0]],
                 dy: [[-1,0,1,2],[1,0,-1,-2],[-1,0,1,2],[1,0,-1,-2]]),
    3: RestShape(start: [4,0,5,0,6,0,7,0],
                 dx: [[2,1,0,-1],[-2,-1,0,1],[2,1,0,-1],[-2,-1,0,1]],
                 dy: [[2,1,0,-1],[-2,-1,0,1],[2,1,0,-1],[-2,-1,0,1]]),
    4: RestShape(start: [4,0,4,1,5,1,6,1],
                 dx: [[0,1,0,-1],[2,1,0,-1],[0,-1,0,1],[-2,-1,0,1]],
                 dy: [[2,1,0,-1],[0,-1,0,1],[-2,-1,0,1],[0,1,0,-1]]),
    5: RestShape(start: [4,1,5,1,6,1,6,0],
                 dx: [[1,0,-1,-2],[1,0,-1,0],[-1,0,1,2],[-1,0,1,0]],
                 dy: [[1,0,-1,0],[-1,0,1,2],[-1,0,1,0],[1,0,-1,-2]]),
    6: RestShape(start: [4,1,5,1,5,0,6,1],
                 dx: [[1,0,-1,-1],[1,0,1,-1],[-1,0,1,1],[-1,0,-1,1]],
                 dy: [[1,0,1,-1],[-1,0,1,1],[-1,0,-1,1],[1,0,-1,-1]]),
    7: RestShape(start: [4,0,5,0,4,1,5,1],
                 dx: [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]],
                 dy: [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]]),
]

private struct RestPiece {
    let kind: Int
    var xs: [Int]
    var ys: [Int]
    var rot = 0

    init() {
        kind = Int.random(in: 1...7)
        let s = restShapes[kind]!
        xs = (0..<4).map { s.start[$0 * 2] }
        ys = (0..<4).map { s.start[$0 * 2 + 1] }
    }
}

// MARK: - Игра

final class RestGameView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let cols = 12, rows = 22          // со стенками; играть можно в x 1…10, y 0…20
    private let cell: CGFloat = 30, originX: CGFloat = 20, originY: CGFloat = 20

    private var grid: [[Bool]] = []
    private var fig = RestPiece()
    private var next = RestPiece()
    private var playing = true, paused = false, over = false, figureKey = false
    // Правила как в современном «международном» тетрисе (Tetris Guideline):
    // уровень растёт каждые 10 линий, скорость — (0,8 − (L−1)·0,007)^(L−1) секунд на клетку,
    // очки: 100/300/500/800 × уровень, мягкий сброс 1 очко за клетку, жёсткий — 2,
    // подряд два «тетриса» — ×1,5, серия линий (комбо) — 50 × номер × уровень.
    private let tickSeconds = 0.02
    private var gravityAcc = 0.0
    private var lastTick = Date.timeIntervalSinceReferenceDate
    private var fallInterval = 1.0           // текущая длительность шага вниз — для плавной отрисовки
    private var score = 0, level = 1, totalLines = 0
    private var comboCount = -1, backToBack = false
    private var timer: Timer?
    private var records: [RestRecord] = []
    private let nameField = NSTextField(frame: NSRect(x: 400, y: 290, width: 190, height: 25))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameField.font = restFont(15)
        nameField.delegate = self
        nameField.isHidden = true
        addSubview(nameField)
        newGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate() }

    // MARK: управление игрой

    func newGame() {
        timer?.invalidate()
        grid = Array(repeating: Array(repeating: false, count: cols), count: rows)
        fig = RestPiece()
        next = RestPiece()
        playing = true; paused = false; over = false; figureKey = false
        gravityAcc = 0; lastTick = Date.timeIntervalSinceReferenceDate; score = 0; level = 1; totalLines = 0; comboCount = -1; backToBack = false
        nameField.isHidden = true
        nameField.stringValue = ""
        records = RestRecords.load()
        window?.makeFirstResponder(self)
        schedule()
        needsDisplay = true
    }

    /// Когда окно теряет фокус, игра встаёт на паузу
    func autoPause() {
        if playing && !over && !paused { setPaused(true) }
    }

    private func setPaused(_ on: Bool) {
        paused = on
        if on { timer?.invalidate() } else { lastTick = Date.timeIntervalSinceReferenceDate; schedule() }
        needsDisplay = true
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: tickSeconds, repeats: false) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard playing else { endGame(); return }

        if figureKey {
            for i in 0..<4 { grid[fig.ys[i]][fig.xs[i]] = true }
            if !clearLines() { comboCount = -1 }
            fig = next
            next = RestPiece()
            // новая фигура сразу попала на занятые клетки: стакан заполнен
            for i in 0..<4 where grid[fig.ys[i]][fig.xs[i]] { playing = false }
            figureKey = false
        }

        if paused { return }

        // самотёк фигуры вниз по таблице Guideline (на больших уровнях — несколько клеток за такт)
        // реальное время между тактами, а не фиксированные 20 мс: таймер может запаздывать, и фигура дёргалась
        let now = Date.timeIntervalSinceReferenceDate
        let dt = min(0.1, max(0.001, now - lastTick))
        lastTick = now
        gravityAcc += dt
        let interval = max(0.0005, pow(0.8 - Double(level - 1) * 0.007, Double(level - 1)))
        fallInterval = interval
        var steps = 0
        while gravityAcc >= interval && steps < 21 {
            gravityAcc -= interval
            steps += 1
            if checkDown() { move(0, 1) } else { gravityAcc = 0; break }
        }
        needsDisplay = true
        schedule()
    }

    private func move(_ dx: Int, _ dy: Int) {
        for i in 0..<4 { fig.xs[i] += dx; fig.ys[i] += dy }
        needsDisplay = true
    }

    /// Есть ли под фигурой свободное место; если нет, фигура будет вставлена в стакан
    private func checkDown() -> Bool {
        for i in 0..<4 {
            if fig.ys[i] >= 20 || grid[fig.ys[i] + 1][fig.xs[i]] {
                figureKey = true
                return false
            }
        }
        return true
    }

    /// Может ли фигура опуститься ещё на клетку (без побочных эффектов)
    private func canFall() -> Bool {
        for i in 0..<4 where fig.ys[i] >= 20 || grid[fig.ys[i] + 1][fig.xs[i]] { return false }
        return true
    }

    private func stepLeft() {
        for i in 0..<4 where fig.xs[i] - 1 <= 0 || grid[fig.ys[i]][fig.xs[i] - 1] { return }
        move(-1, 0)
    }

    private func stepRight() {
        for i in 0..<4 where fig.xs[i] + 1 >= 11 || grid[fig.ys[i]][fig.xs[i] + 1] { return }
        move(1, 0)
    }

    private func rotate() {
        guard let s = restShapes[fig.kind] else { return }
        var nx = (0..<4).map { fig.xs[$0] + s.dx[fig.rot][$0] }
        let ny = (0..<4).map { fig.ys[$0] + s.dy[fig.rot][$0] }
        // у стенок фигуру после поворота сдвигаем обратно в стакан
        var shift = 0
        for x in nx { if x <= 0 { shift += 1 }; if x >= 11 { shift -= 1 } }
        nx = nx.map { $0 + shift }
        for i in 0..<4 {
            if ny[i] < 0 || ny[i] > 20 || nx[i] < 1 || nx[i] > 10 || grid[ny[i]][nx[i]] { return }
        }
        fig.xs = nx
        fig.ys = ny
        fig.rot = (fig.rot + 1) % 4
        needsDisplay = true
    }

    private func hardDrop() {
        while checkDown() { move(0, 1); score += 2 }   // жёсткий сброс: 2 очка за клетку
    }

    /// Удаляет полные линии, начисляет очки и сдвигает всё, что выше
    private func clearLines() -> Bool {
        var full: [Int] = []
        for y in 0..<21 where (1...10).allSatisfy({ grid[y][$0] }) { full.append(y) }
        if full.isEmpty { return false }
        let n = full.count
        let base = [100, 300, 500, 800][n - 1] * level
        score += (n == 4 && backToBack) ? base * 3 / 2 : base
        backToBack = (n == 4)
        comboCount += 1
        score += 50 * comboCount * level
        totalLines += n
        level = 1 + totalLines / 10
        for y in full {
            grid.remove(at: y)
            grid.insert(Array(repeating: false, count: cols), at: 0)
        }
        return true
    }

    private func endGame() {
        timer?.invalidate()
        over = true
        for y in 0..<21 { for x in 1...10 { grid[y][x] = true } }
        needsDisplay = true
        if score > 0 {
            nameField.isHidden = false
            window?.makeFirstResponder(nameField)
        }
    }

    // MARK: клавиатура

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:                                  // Esc: начать заново
            newGame()
        case 35:                                  // P (и «З»): пауза
            if playing && !over { setPaused(!paused) }
        case 123 where playing && !over && !paused: stepLeft()
        case 124 where playing && !over && !paused: stepRight()
        case 125 where playing && !over && !paused: if checkDown() { move(0, 1); score += 1 }   // мягкий сброс: 1 очко за клетку
        case 126 where playing && !over && !paused: if checkDown() { rotate() }
        case 49 where playing && !over && !paused: hardDrop()
        default: break
        }
    }

    // MARK: ввод имени и рекорды

    func controlTextDidChange(_ obj: Notification) {
        if nameField.stringValue.count > 15 { nameField.stringValue = String(nameField.stringValue.prefix(15)) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            saveScore()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            newGame()
            return true
        }
        return false
    }

    private func saveScore() {
        let raw = nameField.stringValue.replacingOccurrences(of: " ", with: "")
        let name = raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
        RestRecords.add(name: name, score: score)
        newGame()
    }

    // MARK: рисование

    private func restFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "Courier New", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Текст, который уменьшается, пока не поместится в ширину области (большие очки не обрезаются)
    private func drawFit(_ s: String, in rect: NSRect, maxSize: CGFloat, centerVertically: Bool = true) {
        var size = maxSize
        while size > 8 {
            let w = NSAttributedString(string: s, attributes: [.font: restFont(size)]).size().width
            if w <= rect.width { break }
            size -= 0.5
        }
        drawText(s, in: rect, size: size, centerVertically: centerVertically)
    }

    private func drawText(_ s: String, in rect: NSRect, size: CGFloat, centerVertically: Bool = true) {
        let attrs: [NSAttributedString.Key: Any] = [.font: restFont(size), .foregroundColor: NSColor.labelColor]
        let a = NSAttributedString(string: s, attributes: attrs)
        var r = rect
        if centerVertically {
            let h = a.size().height
            r.origin.y += max(0, (rect.height - h) / 2)
            r.size.height = h
        }
        a.draw(in: r)
    }

    /// Блок со скошенной рамкой, как на исходных картинках: синий — фигуры, фиолетовый — стенки.
    /// Все границы лежат на целых пикселях, поэтому края получаются чёткими.
    private func drawTile(_ r: NSRect, purple: Bool) {
        let gray = NSColor(calibratedWhite: 0.58, alpha: 1)
        let bevel = purple ? NSColor(srgbRed: 0.48, green: 0.34, blue: 0.72, alpha: 1)
                           : NSColor(srgbRed: 0.29, green: 0.50, blue: 0.72, alpha: 1)
        let mid = purple ? NSColor(srgbRed: 0.63, green: 0.55, blue: 0.82, alpha: 1)
                         : NSColor(srgbRed: 0.56, green: 0.71, blue: 0.86, alpha: 1)
        let x = r.minX, y = r.minY, w = r.width
        let far = w - 1                       // координата последнего пикселя
        // серая внешняя рамка в 1 пиксель, под ней синяя скошенная кайма
        gray.setFill(); r.fill()
        bevel.setFill(); NSRect(x: x + 1, y: y + 1, width: w - 2, height: w - 2).fill()
        // серая линия вокруг середины и сама середина
        gray.setFill(); NSRect(x: x + 4, y: y + 4, width: w - 8, height: w - 8).fill()
        mid.setFill(); NSRect(x: x + 5, y: y + 5, width: w - 10, height: w - 10).fill()
        // диагонали скоса от внешних углов к внутренним
        gray.setStroke()
        let d = NSBezierPath()
        d.lineWidth = 1
        d.move(to: NSPoint(x: x + 1.5, y: y + 1.5));       d.line(to: NSPoint(x: x + 4.5, y: y + 4.5))
        d.move(to: NSPoint(x: x + far + 0.5, y: y + 1.5));     d.line(to: NSPoint(x: x + far - 2.5, y: y + 4.5))
        d.move(to: NSPoint(x: x + 1.5, y: y + far + 0.5));     d.line(to: NSPoint(x: x + 4.5, y: y + far - 2.5))
        d.move(to: NSPoint(x: x + far + 0.5, y: y + far + 0.5));   d.line(to: NSPoint(x: x + far - 2.5, y: y + far - 2.5))
        d.stroke()
    }

    private func cellRect(_ x: Int, _ y: Int) -> NSRect {
        NSRect(x: originX + CGFloat(x) * cell, y: originY + CGFloat(y) * cell, width: cell, height: cell)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        // стенки и дно
        for y in 0..<rows { for x in 0..<cols where x == 0 || x == cols - 1 || y == rows - 1 {
            drawTile(cellRect(x, y), purple: true)
        } }
        // лежащие блоки
        for y in 0..<21 { for x in 1...10 where grid[y][x] { drawTile(cellRect(x, y), purple: false) } }

        if !over {
            // плавное падение: пока под фигурой свободно, рисуем её сдвинутой на долю клетки
            var dy: CGFloat = 0
            if playing && !paused && !figureKey && canFall() && fallInterval > 0.05 {
                dy = CGFloat(min(0.999, gravityAcc / fallInterval)) * cell
            }
            for i in 0..<4 { drawTile(cellRect(fig.xs[i], fig.ys[i]).offsetBy(dx: 0, dy: dy), purple: false) }
            // следующая фигура справа
            for i in 0..<4 { drawTile(cellRect(next.xs[i] + 10, next.ys[i] + 4), purple: false) }
        }

        drawText("Level:", in: NSRect(x: 430, y: 35, width: 90, height: 20), size: 20)
        drawText(String(level), in: NSRect(x: 510, y: 30, width: 80, height: 30), size: 30)
        drawText("Score:", in: NSRect(x: 430, y: 72, width: 90, height: 20), size: 20)
        drawFit(String(score), in: NSRect(x: 430, y: 96, width: 165, height: 32), maxSize: 30)
        drawText("by AnD", in: NSRect(x: 520, y: 670, width: 70, height: 30), size: 10)

        if over && score > 0 {
            drawText(T("Запишем результат?"), in: NSRect(x: 400, y: 170, width: 200, height: 200), size: 15)
        }
        if paused && !over {
            drawText("PAUSE", in: NSRect(x: 430, y: 220, width: 150, height: 30), size: 20)
        }

        var y: CGFloat = 370
        let shown = records.prefix(RestRecords.limit)
        let numWidth = max(4, shown.map { String($0.score).count }.max() ?? 4)
        for r in shown {
            let num = String(r.score)
            let line = num + String(repeating: " ", count: numWidth - num.count + 1) + r.name
            drawFit(line, in: NSRect(x: 400, y: y, width: 195, height: 20), maxSize: 15, centerVertically: false)
            y += 20
        }
    }
}

// MARK: - Окно

final class RestWindowController: NSObject, NSWindowDelegate {
    static let shared = RestWindowController()
    private var window: NSWindow?
    private var game: RestGameView?

    private var title: String { T("Передохни") + " — " + T("P — пауза, Esc — заново") }

    func show() {
        if window == nil {
            let g = RestGameView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = g
            w.delegate = self
            if !w.setFrameUsingName("RestWindow") { w.center() }
            w.setFrameAutosaveName("RestWindow")
            window = w
            game = g
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = title
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let g = game { window?.makeFirstResponder(g) }
    }

    @objc private func languageChanged() { window?.title = title; game?.needsDisplay = true }

    func windowDidResignKey(_ notification: Notification) { game?.autoPause() }
}

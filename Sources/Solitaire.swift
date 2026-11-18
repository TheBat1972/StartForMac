// «Косынка» для меню «Передохни»: классический пасьянс Klondike.
// Перетаскивание карт мышью, двойной щелчок — отправить в «дом», отмена хода, набор по 1 или по 3 карты.
import AppKit

private struct SolCard {
    var suit: Int          // 0 ♠, 1 ♥, 2 ♦, 3 ♣
    var rank: Int          // 1…13
    var up = false
    var red: Bool { suit == 1 || suit == 2 }
}

private struct SolState {
    var stock: [SolCard] = []
    var waste: [SolCard] = []
    var found: [[SolCard]] = Array(repeating: [], count: 4)
    var tab: [[SolCard]] = Array(repeating: [], count: 7)
}

/// Картинки карт из Resources/Cards (файлы вида 10c.png, tp.png, back.png) и звуки; если их нет — карты рисуются кодом
private enum SolAssets {
    private static var images: [String: NSImage] = [:]
    private static var sounds: [String: NSSound] = [:]
    private static var dir: URL? { Bundle.main.resourceURL?.appendingPathComponent("Cards") }

    static func image(_ name: String) -> NSImage? {
        if let i = images[name] { return i }
        guard let d = dir, let i = NSImage(contentsOf: d.appendingPathComponent(name + ".png")) else { return nil }
        images[name] = i
        return i
    }

    /// Имя файла лица: масти b, c, k, p (бубны, черви, крести, пики); A, J, Q, K — t, v, d, k
    static func faceName(_ c: SolCard) -> String {
        let ranks = ["t", "2", "3", "4", "5", "6", "7", "8", "9", "10", "v", "d", "k"]
        let suits = ["p", "c", "b", "k"]        // у нас масти: 0 ♠, 1 ♥, 2 ♦, 3 ♣
        return ranks[c.rank - 1] + suits[c.suit]
    }

    /// Рубашки: файлы back.png, back2.png … (название — для меню выбора)
    static let backs: [(file: String, title: String)] = [
        ("back", "Синяя клетка"), ("back2", "Красная с орнаментом"), ("back3", "Масти"), ("back4", "Шотландка"),
    ]
    static var backIndex: Int {
        get { min(max(UserDefaults.standard.integer(forKey: "solitaire.back"), 0), backs.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: "solitaire.back") }
    }
    static var backImage: NSImage? { image(backs[backIndex].file) }

    /// Цвет стола: приглушённые тона, чтобы не уставали глаза
    static let tables: [(title: String, color: NSColor)] = [
        ("Зелёный", NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.26, alpha: 1)),
        ("Синий", NSColor(calibratedRed: 0.17, green: 0.28, blue: 0.42, alpha: 1)),
        ("Графит", NSColor(calibratedRed: 0.23, green: 0.24, blue: 0.27, alpha: 1)),
        ("Бордо", NSColor(calibratedRed: 0.39, green: 0.19, blue: 0.23, alpha: 1)),
        ("Коричневый", NSColor(calibratedRed: 0.35, green: 0.27, blue: 0.20, alpha: 1)),
    ]
    static var tableIndex: Int {
        get { min(max(UserDefaults.standard.integer(forKey: "solitaire.table"), 0), tables.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: "solitaire.table") }
    }

    static func play(_ name: String) {
        if sounds[name] == nil, let d = dir {
            sounds[name] = NSSound(contentsOf: d.appendingPathComponent(name + ".wav"), byReference: false)
        }
        guard let snd = sounds[name] else { return }
        snd.stop()
        snd.play()
    }
}

private struct SolRecord: Codable {
    var time: Int
    var moves: Int
    var draw: Int          // по сколько карт тянули из колоды: 1 или 3
}

private enum SolRecords {
    static let key = "solitaire.records"
    static func load() -> [SolRecord] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let r = try? JSONDecoder().decode([SolRecord].self, from: d) else { return [] }
        return r
    }
    static func list(draw: Int) -> [SolRecord] {
        load().filter { $0.draw == draw }.sorted { ($0.time, $0.moves) < ($1.time, $1.moves) }
    }
    /// Добавляет результат (лучшие 10 для каждого режима) и возвращает место среди результатов своего режима, если вошёл в десятку
    static func add(_ r: SolRecord) -> Int? {
        var top: [SolRecord] = []
        let all = load() + [r]
        for d in [1, 3] {
            top += all.filter { $0.draw == d }.sorted { ($0.time, $0.moves) < ($1.time, $1.moves) }.prefix(10)
        }
        if let data = try? JSONEncoder().encode(top) { UserDefaults.standard.set(data, forKey: key) }
        let mine = top.filter { $0.draw == r.draw }.sorted { ($0.time, $0.moves) < ($1.time, $1.moves) }
        return mine.firstIndex { $0.time == r.time && $0.moves == r.moves }.map { $0 + 1 }
    }
}

private struct SolFlyer {
    var card: SolCard
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
}

private enum SolPile: Equatable {
    case waste
    case found(Int)
    case tab(Int)
}

final class SolitaireView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let cw: CGFloat = 80, ch: CGFloat = 112
    private let pileY: CGFloat = 52
    private var tabY: CGFloat { pileY + ch + 24 }

    private var st = SolState()
    private var history: [SolState] = []
    private var drawCount = 1
    private var moves = 0
    private var startTime = Date()
    private var finalTime: TimeInterval?
    private var timer: Timer?

    // автодоигрывание, победа, рекорды
    private var autoTimer: Timer?
    private var winTimer: Timer?
    private var flyers: [SolFlyer] = []
    private var launchQueue: [Int] = []
    private var launchCountdown = 0
    private var trailRep: NSBitmapImageRep?
    private var winRank: Int?
    private var showRecords = false

    // перетаскивание
    private var dragFrom: SolPile?
    private var dragIndex = 0
    private var dragCards: [SolCard] = []
    private var dragOffset = CGPoint.zero
    private var dragPoint = CGPoint.zero
    private var dragging = false
    private var downPoint = CGPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        newGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate(); autoTimer?.invalidate(); winTimer?.invalidate() }

    // MARK: игра

    func newGame() {
        var deck: [SolCard] = []
        for s in 0..<4 { for r in 1...13 { deck.append(SolCard(suit: s, rank: r)) } }
        deck.shuffle()
        var s = SolState()
        for c in 0..<7 {
            for _ in 0...c { s.tab[c].append(deck.removeLast()) }
            s.tab[c][c].up = true
        }
        s.stock = deck
        st = s
        history = []
        moves = 0
        finalTime = nil
        startTime = Date()
        dragFrom = nil; dragging = false; dragCards = []
        stopAuto()
        winTimer?.invalidate(); winTimer = nil
        flyers = []; launchQueue = []; trailRep = nil; winRank = nil; showRecords = false
        needsDisplay = true
    }

    func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.finalTime == nil else { return }
            self.setNeedsDisplay(NSRect(x: 0, y: 0, width: self.bounds.width, height: 48))
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    private var elapsed: TimeInterval { finalTime ?? Date().timeIntervalSince(startTime) }

    private func pushHistory() {
        history.append(st)
        if history.count > 500 { history.removeFirst() }
    }

    private func undo() {
        guard finalTime == nil, autoTimer == nil, let last = history.popLast() else { return }
        st = last
        moves = max(0, moves - 1)
        needsDisplay = true
    }

    private func pileCards(_ p: SolPile) -> [SolCard] {
        switch p {
        case .waste: return st.waste
        case .found(let f): return st.found[f]
        case .tab(let c): return st.tab[c]
        }
    }

    private func canDrop(_ cards: [SolCard], _ to: SolPile) -> Bool {
        guard let first = cards.first else { return false }
        switch to {
        case .waste: return false
        case .found(let f):
            guard cards.count == 1 else { return false }
            if let top = st.found[f].last { return top.suit == first.suit && top.rank + 1 == first.rank }
            return first.rank == 1
        case .tab(let c):
            if let top = st.tab[c].last { return top.up && top.red != first.red && top.rank == first.rank + 1 }
            return first.rank == 13
        }
    }

    private func move(_ from: SolPile, _ idx: Int, _ to: SolPile) {
        let all = pileCards(from)
        guard idx >= 0, idx < all.count else { return }
        let cards = Array(all[idx...])
        pushHistory()
        switch from {
        case .waste: st.waste.removeLast(cards.count)
        case .found(let f): st.found[f].removeLast(cards.count)
        case .tab(let c):
            st.tab[c].removeLast(cards.count)
            if let l = st.tab[c].last, !l.up { st.tab[c][st.tab[c].count - 1].up = true }
        }
        switch to {
        case .waste: break
        case .found(let f): st.found[f].append(contentsOf: cards)
        case .tab(let c): st.tab[c].append(contentsOf: cards)
        }
        moves += 1
        SolAssets.play("kard")
        if st.found.allSatisfy({ $0.count == 13 }) { startWin() } else { checkAuto() }
        needsDisplay = true
    }

    // MARK: автодоигрывание

    /// Все карты открыты, колода и сброс пусты — остаток раскладывается в «дома» сам
    private func checkAuto() {
        guard finalTime == nil, autoTimer == nil, st.stock.isEmpty, st.waste.isEmpty,
              st.tab.allSatisfy({ $0.allSatisfy { $0.up } }) else { return }
        let t = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in self?.autoStep() }
        RunLoop.main.add(t, forMode: .common)
        autoTimer = t
    }

    private func autoStep() {
        guard finalTime == nil else { stopAuto(); return }
        for c in 0..<7 {
            guard let card = st.tab[c].last else { continue }
            for f in 0..<4 where canDrop([card], .found(f)) {
                move(.tab(c), st.tab[c].count - 1, .found(f))
                return
            }
        }
        stopAuto()
    }

    private func stopAuto() { autoTimer?.invalidate(); autoTimer = nil }

    // MARK: победа: рекорд и каскад карт

    private func startWin() {
        stopAuto()
        finalTime = elapsed
        winRank = SolRecords.add(SolRecord(time: Int(elapsed), moves: moves, draw: drawCount))
        // карты вылетают из «домов» по очереди: сначала короли, потом дамы и так до тузов
        launchQueue = []
        for _ in 0..<13 { for f in 0..<4 { launchQueue.append(f) } }
        flyers = []
        launchCountdown = 25
        let scale = 2
        trailRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        trailRep?.size = bounds.size
        winTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.winStep() }
        RunLoop.main.add(t, forMode: .common)
        winTimer = t
    }

    /// Рисует карту в «след» — накопительную картинку поверх стола
    private func stampTrail(_ card: SolCard, _ r: NSRect) {
        guard let rep = trailRep, let g = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let cg = g.cgContext
        cg.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
        cg.scaleBy(x: CGFloat(rep.pixelsWide) / bounds.width, y: -CGFloat(rep.pixelsHigh) / bounds.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        drawCard(r, card)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func winStep() {
        launchCountdown -= 1
        if launchCountdown <= 0, !launchQueue.isEmpty {
            let f = launchQueue.removeFirst()
            if let card = st.found[f].popLast() {
                let o = foundRect(f).origin
                let dir: CGFloat = Bool.random() ? 1 : -1
                flyers.append(SolFlyer(card: card, x: o.x, y: o.y, vx: dir * CGFloat.random(in: 2.5...6),
                                       vy: CGFloat.random(in: -9 ... -3)))
                launchCountdown = 12
            }
        }
        var alive: [SolFlyer] = []
        for var fl in flyers {
            fl.x += fl.vx
            fl.vy += 0.55
            fl.y += fl.vy
            if fl.y + ch > bounds.height { fl.y = bounds.height - ch; fl.vy = -fl.vy * 0.82 }
            stampTrail(fl.card, NSRect(x: fl.x, y: fl.y, width: cw, height: ch))
            if fl.x > -cw && fl.x < bounds.width { alive.append(fl) }
        }
        flyers = alive
        needsDisplay = true
        if launchQueue.isEmpty && flyers.isEmpty { winTimer?.invalidate(); winTimer = nil }
    }

    private func autoToFoundation(_ pile: SolPile) {
        let cards = pileCards(pile)
        guard let c = cards.last else { return }
        for f in 0..<4 where pile != .found(f) && canDrop([c], .found(f)) {
            move(pile, cards.count - 1, .found(f))
            return
        }
    }

    private func drawFromStock() {
        if !st.stock.isEmpty {
            pushHistory()
            for _ in 0..<min(drawCount, st.stock.count) {
                var c = st.stock.removeLast()
                c.up = true
                st.waste.append(c)
            }
            moves += 1
        } else if !st.waste.isEmpty {
            pushHistory()
            st.stock = st.waste.reversed().map { c -> SolCard in var d = c; d.up = false; return d }
            st.waste = []
            moves += 1
        }
        SolAssets.play("kard")
        checkAuto()
        needsDisplay = true
    }

    // MARK: геометрия

    private func colX(_ i: Int) -> CGFloat { 20 + CGFloat(i) * 100 }
    private var stockRect: NSRect { NSRect(x: colX(0), y: pileY, width: cw, height: ch) }
    private var wasteRect: NSRect { NSRect(x: colX(1), y: pileY, width: cw, height: ch) }
    private func foundRect(_ f: Int) -> NSRect { NSRect(x: colX(3 + f), y: pileY, width: cw, height: ch) }
    private func tabSlot(_ c: Int) -> NSRect { NSRect(x: colX(c), y: tabY, width: cw, height: ch) }

    private var newBtn: NSRect { NSRect(x: 20, y: 10, width: 100, height: 28) }
    private var undoBtn: NSRect { NSRect(x: 126, y: 10, width: 118, height: 28) }
    private var drawBtn: NSRect { NSRect(x: 250, y: 10, width: 100, height: 28) }
    private var recBtn: NSRect { NSRect(x: 356, y: 10, width: 88, height: 28) }
    private var backBtn: NSRect { NSRect(x: 450, y: 10, width: 88, height: 28) }

    /// Вертикальные смещения карт в столбце; длинные столбцы сжимаются, чтобы поместиться в окно
    private func tabOffsets(_ c: Int) -> [CGFloat] {
        let cards = st.tab[c]
        let steps: [CGFloat] = cards.dropLast().map { $0.up ? 28 : 14 }
        let avail = bounds.height - tabY - 16 - ch
        let total = steps.reduce(0, +)
        let k: CGFloat = (total > avail && total > 0) ? max(0.35, avail / total) : 1
        var ys: [CGFloat] = []
        var y: CGFloat = 0
        for i in 0..<cards.count {
            ys.append(y)
            if i < steps.count { y += steps[i] * k }
        }
        return ys
    }

    private func tabCardRect(_ c: Int, _ i: Int) -> NSRect {
        let ys = tabOffsets(c)
        return NSRect(x: colX(c), y: tabY + ys[i], width: cw, height: ch)
    }

    private func rect(of pile: SolPile, _ i: Int) -> NSRect {
        switch pile {
        case .waste: return wasteRect
        case .found(let f): return foundRect(f)
        case .tab(let c): return tabCardRect(c, i)
        }
    }

    private func hitCard(_ p: CGPoint) -> (SolPile, Int)? {
        for c in 0..<7 {
            for i in stride(from: st.tab[c].count - 1, through: 0, by: -1) where tabCardRect(c, i).contains(p) {
                return (.tab(c), i)
            }
        }
        if !st.waste.isEmpty && wasteRect.contains(p) { return (.waste, st.waste.count - 1) }
        for f in 0..<4 where !st.found[f].isEmpty && foundRect(f).contains(p) {
            return (.found(f), st.found[f].count - 1)
        }
        return nil
    }

    // MARK: мышь и клавиатура

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        downPoint = p
        if newBtn.contains(p) { newGame(); return }
        if undoBtn.contains(p) { undo(); return }
        if drawBtn.contains(p) { drawCount = (drawCount == 1) ? 3 : 1; showRecords = false; needsDisplay = true; return }
        if backBtn.contains(p) { showViewMenu(); return }
        if recBtn.contains(p) { showRecords.toggle(); needsDisplay = true; return }
        if showRecords { showRecords = false; needsDisplay = true; return }
        if finalTime != nil { newGame(); return }
        if autoTimer != nil { return }
        if stockRect.contains(p) { drawFromStock(); return }
        guard let (pile, i) = hitCard(p) else { return }
        let cards = pileCards(pile)
        guard i >= 0, i < cards.count else { return }
        if !cards[i].up {
            // щелчок по закрытой верхней карте столбца переворачивает её
            if case .tab(let c) = pile, i == cards.count - 1 {
                pushHistory()
                st.tab[c][i].up = true
                moves += 1
                SolAssets.play("kard")
                needsDisplay = true
                checkAuto()
            }
            return
        }
        if event.clickCount == 2 && i == cards.count - 1 { autoToFoundation(pile); return }
        dragFrom = pile
        dragIndex = i
        dragCards = Array(cards[i...])
        let r = rect(of: pile, i)
        dragOffset = CGPoint(x: p.x - r.minX, y: p.y - r.minY)
        dragPoint = p
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragFrom != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !dragging && hypot(p.x - downPoint.x, p.y - downPoint.y) < 4 { return }
        dragging = true
        dragPoint = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragFrom = nil; dragging = false; dragCards = []; needsDisplay = true }
        guard let from = dragFrom, dragging else { return }
        let r = NSRect(x: dragPoint.x - dragOffset.x, y: dragPoint.y - dragOffset.y, width: cw, height: ch)
        var targets: [(SolPile, NSRect)] = []
        for f in 0..<4 { targets.append((.found(f), foundRect(f))) }
        for c in 0..<7 {
            let area = st.tab[c].isEmpty ? tabSlot(c) : tabCardRect(c, st.tab[c].count - 1)
            targets.append((.tab(c), area))
        }
        var best: (SolPile, CGFloat)?
        for (pile, rc) in targets where pile != from {
            let x = r.intersection(rc)
            let a: CGFloat = x.isNull ? 0 : x.width * x.height
            if a > cw * ch * 0.12 && canDrop(dragCards, pile) && a > (best?.1 ?? 0) { best = (pile, a) }
        }
        if let b = best { move(from, dragIndex, b.0) }
    }

    /// Меню «Вид»: рубашка и цвет стола, с маленькими образцами
    private func showViewMenu() {
        let menu = NSMenu()

        let backItem = NSMenuItem(title: T("Рубашка"), action: nil, keyEquivalent: "")
        let backMenu = NSMenu()
        for (i, b) in SolAssets.backs.enumerated() {
            let item = NSMenuItem(title: T(b.title), action: #selector(pickBack(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == SolAssets.backIndex) ? .on : .off
            if let img = SolAssets.image(b.file), let t = img.copy() as? NSImage {
                t.size = NSSize(width: 24, height: 35)
                item.image = t
            }
            backMenu.addItem(item)
        }
        backItem.submenu = backMenu
        menu.addItem(backItem)

        let tableItem = NSMenuItem(title: T("Цвет стола"), action: nil, keyEquivalent: "")
        let tableMenu = NSMenu()
        for (i, t) in SolAssets.tables.enumerated() {
            let item = NSMenuItem(title: T(t.title), action: #selector(pickTable(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == SolAssets.tableIndex) ? .on : .off
            let color = t.color
            item.image = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { r in
                color.setFill()
                NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
                return true
            }
            tableMenu.addItem(item)
        }
        tableItem.submenu = tableMenu
        menu.addItem(tableItem)

        menu.popUp(positioning: nil, at: NSPoint(x: backBtn.minX, y: backBtn.maxY + 2), in: self)
    }

    @objc private func pickBack(_ sender: NSMenuItem) {
        SolAssets.backIndex = sender.tag
        needsDisplay = true
    }

    @objc private func pickTable(_ sender: NSMenuItem) {
        SolAssets.tableIndex = sender.tag
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 6: undo()                                                     // Z (и «Я»): отмена хода
        case 45 where event.modifierFlags.contains(.command): newGame()    // ⌘N
        default: break
        }
    }

    // MARK: рисование

    private func drawString(_ s: String, _ rect: NSRect, size: CGFloat, color: NSColor,
                            align: NSTextAlignment = .left, bold: Bool = false) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (s as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps])
    }

    private func drawButton(_ r: NSRect, _ title: String) {
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        NSColor(white: 1, alpha: 0.18).setFill()
        path.fill()
        drawString(title, NSRect(x: r.minX, y: r.minY + 5, width: r.width, height: r.height - 5),
                   size: 13, color: .white, align: .center)
    }

    private func drawSlot(_ r: NSRect, glyph: String?) {
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        NSColor(white: 1, alpha: 0.35).setStroke()
        path.lineWidth = 2
        path.stroke()
        if let g = glyph {
            drawString(g, NSRect(x: r.minX, y: r.midY - 26, width: r.width, height: 52),
                       size: 40, color: NSColor(white: 1, alpha: 0.4), align: .center)
        }
    }

    private func drawCard(_ r: NSRect, _ c: SolCard) {
        // картинка вписывается в клетку по высоте (поля и размеры раскладки не меняются), ширина по пропорциям
        if let img = (c.up ? SolAssets.image(SolAssets.faceName(c)) : SolAssets.backImage) {
            let w = r.height * img.size.width / img.size.height
            let dst = NSRect(x: r.minX + (r.width - w) / 2, y: r.minY, width: w, height: r.height)
            img.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            return
        }
        let path = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        if c.up {
            NSColor.white.setFill()
            path.fill()
            NSColor(white: 0.55, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
            let col = c.red ? NSColor(calibratedRed: 0.78, green: 0.08, blue: 0.10, alpha: 1) : NSColor(white: 0.10, alpha: 1)
            let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
            let suit = ["♠", "♥", "♦", "♣"][c.suit] + "\u{FE0E}"
            drawString(ranks[c.rank - 1] + suit, NSRect(x: r.minX + 6, y: r.minY + 4, width: 60, height: 22),
                       size: 16, color: col, bold: true)
            drawString(suit, NSRect(x: r.minX, y: r.midY - 20, width: r.width, height: 60),
                       size: 42, color: col, align: .center)
        } else {
            NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.68, alpha: 1).setFill()
            path.fill()
            NSColor(white: 0.9, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
            let inner = NSBezierPath(roundedRect: r.insetBy(dx: 6, dy: 6), xRadius: 4, yRadius: 4)
            NSColor(white: 1, alpha: 0.55).setStroke()
            inner.lineWidth = 1.5
            inner.stroke()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        SolAssets.tables[SolAssets.tableIndex].color.setFill()
        bounds.fill()

        drawButton(newBtn, T("Новая игра"))
        drawButton(undoBtn, T("Отменить ход"))
        drawButton(drawBtn, T("Тянуть по") + " \(drawCount)")
        let t = Int(elapsed)
        let stats = T("Ходы") + ": \(moves)  " + T("Время") + String(format: ": %d:%02d", t / 60, t % 60)
        drawButton(recBtn, T("Рекорды"))
        drawButton(backBtn, T("Вид"))
        drawString(stats, NSRect(x: 546, y: 17, width: 154, height: 22), size: 11, color: .white, align: .right)

        // колода и сброс
        if st.stock.isEmpty { drawSlot(stockRect, glyph: "↺") } else { drawCard(stockRect, SolCard(suit: 0, rank: 1, up: false)) }
        func visibleCount(_ p: SolPile, _ n: Int) -> Int { (dragging && dragFrom == p) ? dragIndex : n }
        let wn = visibleCount(.waste, st.waste.count)
        if wn > 0 { drawCard(wasteRect, st.waste[wn - 1]) } else { drawSlot(wasteRect, glyph: nil) }
        for f in 0..<4 {
            let n = visibleCount(.found(f), st.found[f].count)
            if n > 0 { drawCard(foundRect(f), st.found[f][n - 1]) } else { drawSlot(foundRect(f), glyph: "A") }
        }
        // столбцы
        for c in 0..<7 {
            if st.tab[c].isEmpty { drawSlot(tabSlot(c), glyph: "K"); continue }
            let n = visibleCount(.tab(c), st.tab[c].count)
            if n == 0 { drawSlot(tabSlot(c), glyph: "K") }
            for i in 0..<n { drawCard(tabCardRect(c, i), st.tab[c][i]) }
        }
        // перетаскиваемые карты — поверх всего
        if dragging {
            for (k, c) in dragCards.enumerated() {
                let r = NSRect(x: dragPoint.x - dragOffset.x, y: dragPoint.y - dragOffset.y + CGFloat(k) * 28,
                               width: cw, height: ch)
                drawCard(r, c)
            }
        }
        // каскад карт после победы: след, затем летящие карты
        if finalTime != nil, let rep = trailRep {
            let img = NSImage(size: bounds.size)
            img.addRepresentation(rep)
            img.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            for fl in flyers { drawCard(NSRect(x: fl.x, y: fl.y, width: cw, height: ch), fl.card) }
        }
        if finalTime != nil {
            drawPanel(title: T("Победа!"), subtitle: stats, mode: drawCount, highlight: winRank, lines: 5,
                      footer: T("Нажмите, чтобы начать заново"), big: true)
        } else if showRecords {
            drawPanel(title: T("Рекорды"), subtitle: T("Тянуть по") + " \(drawCount)", mode: drawCount, highlight: nil, lines: 10,
                      footer: T("Нажмите, чтобы закрыть"), big: false)
        }
    }

    private func clock(_ t: Int) -> String { String(format: "%d:%02d", t / 60, t % 60) }

    /// Панель с заголовком и таблицей рекордов поверх стола
    private func drawPanel(title: String, subtitle: String, mode: Int, highlight: Int?, lines: Int, footer: String, big: Bool) {
        let list = SolRecords.list(draw: mode)
        let shown = Array(list.prefix(lines))
        let bw: CGFloat = 380
        let rows = max(shown.count, 1)
        let head: CGFloat = big ? 150 : 90
        let bh = head + CGFloat(rows) * 22 + 50
        let br = NSRect(x: bounds.midX - bw / 2, y: bounds.midY - bh / 2, width: bw, height: bh)
        NSColor(white: 0, alpha: 0.78).setFill()
        NSBezierPath(roundedRect: br, xRadius: 14, yRadius: 14).fill()
        var y = br.minY + 12
        drawString(title, NSRect(x: br.minX, y: y, width: bw, height: big ? 56 : 30), size: big ? 44 : 22, color: .white, align: .center, bold: true)
        y += big ? 62 : 34
        drawString(subtitle, NSRect(x: br.minX, y: y, width: bw, height: 24), size: big ? 16 : 14, color: .white, align: .center)
        y += 28
        if big, let r = highlight {
            let txt = r == 1 ? T("Новый рекорд!") : T("Место в рекордах") + ": \(r)"
            drawString(txt, NSRect(x: br.minX, y: y, width: bw, height: 24), size: 17,
                       color: NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1), align: .center, bold: true)
            y += 30
        }
        y += 4
        if shown.isEmpty {
            drawString(T("Рекордов пока нет"), NSRect(x: br.minX, y: y, width: bw, height: 22), size: 14,
                       color: NSColor(white: 1, alpha: 0.7), align: .center)
            y += 22
        }
        for (k, r) in shown.enumerated() {
            let mine = (highlight == k + 1)
            let col = mine ? NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1) : NSColor.white
            let line = String(format: "%2d.   %@   %@: %d", k + 1, clock(r.time), T("Ходы"), r.moves)
            drawString(line, NSRect(x: br.minX + 70, y: y, width: bw - 90, height: 22), size: 14, color: col, bold: mine)
            y += 22
        }
        drawString(footer, NSRect(x: br.minX, y: br.maxY - 32, width: bw, height: 22), size: 13,
                   color: NSColor(white: 1, alpha: 0.75), align: .center)
    }
}

// MARK: - Окно

final class SolitaireWindowController: NSObject, NSWindowDelegate {
    static let shared = SolitaireWindowController()
    private var window: NSWindow?
    private var game: SolitaireView?

    private var title: String { T("Косынка") }

    func show() {
        if window == nil {
            let g = SolitaireView(frame: NSRect(x: 0, y: 0, width: 720, height: 720))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = g
            w.delegate = self
            if !w.setFrameUsingName("SolitaireWindow") { w.center() }
            w.setFrameAutosaveName("SolitaireWindow")
            window = w
            game = g
            NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        }
        window?.title = title
        NSApp.windows.compactMap { $0 as? PopupWindow }.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let g = game { window?.makeFirstResponder(g); g.startTimer() }
    }

    @objc private func languageChanged() { window?.title = title; game?.needsDisplay = true }

    func windowDidBecomeKey(_ notification: Notification) { game?.startTimer() }
    func windowDidResignKey(_ notification: Notification) { game?.stopTimer() }
    func windowWillClose(_ notification: Notification) { game?.stopTimer() }
}

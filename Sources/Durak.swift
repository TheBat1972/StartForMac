// «Дурак» для меню «Передохни»: подкидной и переводной, 2–4 игрока (вы и компьютер).
// Карты, рубашка и цвет стола — те же, что у «Косынки» (SolAssets).
//
// Как устроен компьютерный игрок (по литературе об играх с неполной информацией):
//  1. Учёт карт. Известны: своя рука, отбой, открытый козырь внизу колоды и карты, которые игрок взял со стола
//     (это видят все). Остальные карты — «неизвестные».
//  2. Эвристика: ходить дешёвыми картами, козыри беречь, у тех, кому нечем бить, подкидывать лишнее,
//     брать, если отбиваться пришлось бы старшим козырем, переводить дешёвой картой.
//  3. В конце партии (колода почти кончилась) — «детерминизация» (PIMC, Perfect Information Monte Carlo):
//     неизвестные карты случайно раздаются противникам много раз, каждый возможный ход проигрывается
//     до конца партии эвристикой, выбирается ход с лучшей долей побед.
import AppKit

// MARK: - Правила (значения, чтобы компьютер мог «проигрывать» партии в уме)

private let dTotal = 36
private func dSuit(_ c: Int) -> Int { return c / 9 }
private func dRank(_ c: Int) -> Int { return c % 9 + 6 }      // 6…14, туз = 14

private enum DMove: Equatable {
    case play(Int)            // ход или подкидывание
    case beat(Int, Int)       // побить картой c карту на столе с индексом i
    case transfer(Int)        // перевод (только в переводном)
    case take                 // взять карты
    case pass                 // «бито» / «хватит»
}

private struct DG {
    var hands: [[Int]] = []
    var known: [Set<Int>] = []        // карты, про которые всем известно, что они у игрока
    var deck: [Int] = []              // deck[0] — верх, последняя — открытый козырь
    var trumpSuit = 0
    var trumpCard = 0
    var discard = Set<Int>()
    var tableAtk: [Int] = []
    var tableDef: [Int] = []          // -1 — ещё не побита
    var attacker = 0
    var defender = 1
    var phase = 0                     // 0 — ход, 1 — защита, 2 — подкидывание
    var tIdx = 0
    var taking = false
    var out: [Bool] = []
    var transfer = false
    var over = false
    var loser: Int? = nil

    var n: Int { return hands.count }

    init(players: Int, transfer: Bool, firstHint: Int?) {
        self.transfer = transfer
        var cards = Array(0..<dTotal)
        cards.shuffle()
        hands = Array(repeating: [], count: players)
        known = Array(repeating: Set<Int>(), count: players)
        out = Array(repeating: false, count: players)
        for _ in 0..<6 {
            for p in 0..<players { hands[p].append(cards.removeLast()) }
        }
        deck = cards
        trumpCard = deck[deck.count - 1]
        trumpSuit = dSuit(trumpCard)
        var first = firstHint
        if first == nil {
            var bestRank = 99
            for p in 0..<players {
                for c in hands[p] where dSuit(c) == trumpSuit && dRank(c) < bestRank {
                    bestRank = dRank(c)
                    first = p
                }
            }
        }
        attacker = first ?? 0
        defender = (attacker + 1) % players
    }

    func isTrump(_ c: Int) -> Bool { return dSuit(c) == trumpSuit }

    func beats(_ a: Int, _ d: Int) -> Bool {
        if dSuit(a) == dSuit(d) { return dRank(d) > dRank(a) }
        return dSuit(d) == trumpSuit
    }

    func nextActive(after p: Int) -> Int? {
        for k in 1..<n {
            let q = (p + k) % n
            if !out[q] { return q }
        }
        return nil
    }

    func attackerOrder() -> [Int] {
        var r: [Int] = []
        for k in 0..<n {
            let q = (attacker + k) % n
            if q != defender && !out[q] { r.append(q) }
        }
        return r
    }

    var actor: Int {
        switch phase {
        case 0: return attacker
        case 1: return defender
        default:
            let o = attackerOrder()
            return tIdx < o.count ? o[tIdx] : attacker
        }
    }

    func undefendedIndices() -> [Int] {
        var r: [Int] = []
        for i in 0..<tableAtk.count where tableDef[i] < 0 { r.append(i) }
        return r
    }

    func legalMoves() -> [DMove] {
        if over { return [] }
        let p = actor
        let hand = hands[p]
        var r: [DMove] = []
        switch phase {
        case 0:
            for c in hand { r.append(.play(c)) }
        case 1:
            let und = undefendedIndices()
            for c in hand {
                for i in und where beats(tableAtk[i], c) { r.append(.beat(c, i)) }
            }
            if transfer && tableAtk.count < 6 && !tableAtk.isEmpty && und.count == tableAtk.count {
                if let nd = nextActive(after: defender), hands[nd].count >= tableAtk.count + 1 {
                    let rk = dRank(tableAtk[0])
                    for c in hand where dRank(c) == rk { r.append(.transfer(c)) }
                }
            }
            r.append(.take)
        default:
            let und = undefendedIndices().count
            if tableAtk.count < 6 && und + 1 <= hands[defender].count {
                var ranks = Set<Int>()
                for c in tableAtk { ranks.insert(dRank(c)) }
                for c in tableDef where c >= 0 { ranks.insert(dRank(c)) }
                for c in hand where ranks.contains(dRank(c)) { r.append(.play(c)) }
            }
            r.append(.pass)
        }
        return r
    }

    /// Если подкинуть нечего — «пас» делается сам
    mutating func normalize() {
        while !over && phase == 2 {
            if legalMoves().count == 1 { apply(.pass) } else { break }
        }
    }

    private mutating func remove(_ c: Int, from p: Int) {
        hands[p].removeAll { $0 == c }
        known[p].remove(c)
    }

    mutating func apply(_ m: DMove) {
        let p = actor
        switch m {
        case .play(let c):
            remove(c, from: p)
            tableAtk.append(c)
            tableDef.append(-1)
            if phase == 0 || !taking { phase = 1 }
        case .beat(let c, let i):
            remove(c, from: p)
            tableDef[i] = c
            if undefendedIndices().isEmpty {
                if hands[p].isEmpty || tableAtk.count >= 6 {
                    endRound(taken: false)
                } else {
                    phase = 2
                    tIdx = 0
                }
            }
        case .transfer(let c):
            remove(c, from: p)
            tableAtk.append(c)
            tableDef.append(-1)
            if let nd = nextActive(after: p) {
                attacker = p
                defender = nd
            }
            phase = 1
        case .take:
            taking = true
            phase = 2
            tIdx = 0
        case .pass:
            tIdx += 1
            if tIdx >= attackerOrder().count { endRound(taken: taking) }
        }
    }

    private mutating func endRound(taken: Bool) {
        let d = defender
        if taken {
            for c in tableAtk { hands[d].append(c); known[d].insert(c) }
            for c in tableDef where c >= 0 { hands[d].append(c); known[d].insert(c) }
        } else {
            for c in tableAtk { discard.insert(c) }
            for c in tableDef where c >= 0 { discard.insert(c) }
        }
        tableAtk = []
        tableDef = []
        taking = false
        // добор: сначала атаковавшие по кругу, защитник последним
        var order: [Int] = []
        for k in 0..<n {
            let q = (attacker + k) % n
            if q != d { order.append(q) }
        }
        order.append(d)
        for q in order {
            while hands[q].count < 6 && !deck.isEmpty {
                let c = deck.removeFirst()
                hands[q].append(c)
                if c == trumpCard { known[q].insert(c) }
            }
        }
        for q in 0..<n where hands[q].isEmpty && deck.isEmpty { out[q] = true }
        var active: [Int] = []
        for q in 0..<n where !out[q] { active.append(q) }
        if active.count <= 1 {
            over = true
            loser = active.first
            return
        }
        if !taken && !out[d] { attacker = d } else { attacker = nextActive(after: d) ?? d }
        defender = nextActive(after: attacker) ?? attacker
        phase = 0
        tIdx = 0
    }

    /// Случайная раздача неизвестных карт так, как это видит игрок p
    func determinized(for p: Int) -> DG? {
        var seen = Set<Int>(hands[p])
        seen.formUnion(discard)
        for c in tableAtk { seen.insert(c) }
        for c in tableDef where c >= 0 { seen.insert(c) }
        for q in 0..<n where q != p { seen.formUnion(known[q]) }
        let trumpInDeck = !deck.isEmpty && deck[deck.count - 1] == trumpCard
        if trumpInDeck { seen.insert(trumpCard) }
        var pool: [Int] = []
        for c in 0..<dTotal where !seen.contains(c) { pool.append(c) }
        pool.shuffle()
        var need = 0
        for q in 0..<n where q != p { need += hands[q].count - known[q].count }
        let deckUnknown = deck.count - (trumpInDeck ? 1 : 0)
        if need + deckUnknown != pool.count || need < 0 || deckUnknown < 0 { return nil }
        var w = self
        var idx = 0
        for q in 0..<n where q != p {
            let k = hands[q].count - known[q].count
            var h = Array(known[q])
            if k > 0 { h.append(contentsOf: pool[idx..<(idx + k)]) }
            idx += k
            w.hands[q] = h
        }
        var nd: [Int] = []
        if idx < pool.count { nd = Array(pool[idx...]) }
        if trumpInDeck { nd.append(trumpCard) }
        w.deck = nd
        return w
    }
}

// MARK: - Компьютерный игрок

private func dCost(_ g: DG, _ c: Int) -> Int { return dRank(c) + (g.isTrump(c) ? 20 : 0) }

/// Быстрая эвристика (используется и как «политика» при проигрывании партий)
private func dHeuristic(_ g: DG) -> DMove {
    let moves = g.legalMoves()
    if moves.count == 1 { return moves[0] }
    let p = g.actor
    let hand = g.hands[p]
    switch g.phase {
    case 0:
        // если вся рука защитника известна — ходим картой, которую он не побьёт
        let dk = g.known[g.defender]
        let defKnown = dk.count == g.hands[g.defender].count
        var best = hand[0]
        var bestScore = Int.max
        for c in hand {
            var same = 0
            for x in hand where dRank(x) == dRank(c) { same += 1 }
            var s = dCost(g, c) * 2 - (same - 1) * 3 + Int.random(in: 0...6)   // небольшой разброс, чтобы партии не ходили по кругу
            if defKnown {
                var beaten = false
                for x in dk where g.beats(c, x) { beaten = true }
                if !beaten { s -= 200 }
            }
            if s < bestScore { bestScore = s; best = c }
        }
        return .play(best)
    case 1:
        let und = g.undefendedIndices().sorted { dCost(g, g.tableAtk[$0]) > dCost(g, g.tableAtk[$1]) }
        var used = Set<Int>()
        var plan: [(Int, Int)] = []
        var failed = false
        var trumpCount = 0
        var bigTrump = false
        for i in und {
            var bestC = -1
            for c in hand where !used.contains(c) && g.beats(g.tableAtk[i], c) {
                if bestC < 0 || dCost(g, c) < dCost(g, bestC) { bestC = c }
            }
            if bestC < 0 { failed = true; break }
            used.insert(bestC)
            plan.append((bestC, i))
            if g.isTrump(bestC) && !g.isTrump(g.tableAtk[i]) {
                trumpCount += 1
                if dRank(bestC) >= 11 { bigTrump = true }
            }
        }
        // перевод некозырной картой, если отбиваться дорого или у следующего меньше карт
        var tcard = -1
        for m in moves {
            if case .transfer(let c) = m, !g.isTrump(c) {
                if tcard < 0 || dCost(g, c) < dCost(g, tcard) { tcard = c }
            }
        }
        if tcard >= 0 {
            let nd = g.nextActive(after: g.defender) ?? g.attacker
            if failed || trumpCount > 0 || g.hands[nd].count < hand.count { return .transfer(tcard) }
        }
        if failed { return .take }
        // в начале партии не тратим старший козырь на мелочь — лучше взять
        if g.deck.count > 6 && und.count <= 2 && (bigTrump || trumpCount >= 2) && hand.count < 9 { return .take }
        let pair = plan[0]
        return .beat(pair.0, pair.1)
    default:
        var best = -1
        for m in moves {
            guard case .play(let c) = m else { continue }
            let ok: Bool
            if g.isTrump(c) {
                ok = hand.count == 1 && g.deck.isEmpty
            } else if g.taking {
                ok = g.deck.isEmpty || dRank(c) <= 13
            } else {
                ok = g.deck.isEmpty || dRank(c) <= 10
            }
            if ok && (best < 0 || dCost(g, c) < dCost(g, best)) { best = c }
        }
        if best >= 0 { return .play(best) }
        return .pass
    }
}

private func dRollout(_ start: DG, for p: Int) -> Double {
    var s = start
    var steps = 0
    while !s.over && steps < 500 {
        s.apply(dHeuristic(s))
        s.normalize()
        steps += 1
    }
    if !s.over { return 0.5 }
    if let l = s.loser { return l == p ? 0 : 1 }
    return 0.5
}

/// Выбор хода компьютера: эвристика, а в конце партии — детерминизация + проигрывание
private func dAIChoose(_ g: DG) -> DMove {
    let moves = g.legalMoves()
    if moves.isEmpty { return .pass }
    if moves.count == 1 { return moves[0] }
    let base = dHeuristic(g)
    if g.deck.count > 10 { return base }
    let p = g.actor
    let samples = g.deck.isEmpty ? 120 : 60
    var score = [Double](repeating: 0, count: moves.count)
    var done = 0
    let start = Date()
    for _ in 0..<samples {
        guard let w = g.determinized(for: p) else { continue }
        for (k, m) in moves.enumerated() {
            var s = w
            s.apply(m)
            s.normalize()
            score[k] += dRollout(s, for: p)
        }
        done += 1
        if Date().timeIntervalSince(start) > 0.6 { break }
    }
    if done == 0 { return base }
    var bestK = 0
    var bestV = -1.0
    for (k, m) in moves.enumerated() {
        let v = score[k] / Double(done) + (m == base ? 0.002 : 0)
        if v > bestV { bestV = v; bestK = k }
    }
    return moves[bestK]
}

// MARK: - Окно игры

/// Летящая карта (card < 0 — невидимое действие по таймеру)
private struct DFlight {
    var card: Int
    var from: NSRect
    var to: NSRect
    var start: Double
    var dur: Double
    var upFrom: Bool
    var upTo: Bool
    var started = false
    var onStart: (() -> Void)? = nil
    var onLand: (() -> Void)? = nil
}

final class DurakView: NSView {
    override var isFlipped: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }

    private let cw: CGFloat = 80, ch: CGFloat = 112
    private let tableY: CGFloat = 300
    private let handY: CGFloat = 598
    private var W: CGFloat { return bounds.width }

    private var g: DG
    private var playersN: Int
    private var transferMode: Bool
    private var selected: Int? = nil
    private var status = ""
    private var generation = 0
    private var lastLoser: Int? = nil
    private var finished = false

    // то, что показано на экране (отстаёт от правил на время анимации)
    private var tAtk: [Int] = []
    private var tDef: [Int] = []
    private var gone = Set<Int>()               // карты стола, которые уже улетели
    private var flyingIn = Set<Int>()             // свои карты, которые ещё летят в руку
    private var waitingIn = Set<Int>()            // свои карты, чей полёт ещё не начался: рука раздвигается под них только в момент раздачи
    private var pendingIn: [Int: Int] = [:]     // сколько карт ещё летит к сопернику
    private var deckHold = 0                    // карты, которые ещё числятся в колоде на экране
    private var discardShown = 0
    private var flights: [DFlight] = []
    private var ticker: Timer?

    private let newBtn = NSRect(x: 20, y: 16, width: 100, height: 32)
    private let playersBtn = NSRect(x: 128, y: 16, width: 130, height: 32)
    private let modeBtn = NSRect(x: 266, y: 16, width: 130, height: 32)
    private let viewBtn = NSRect(x: 404, y: 16, width: 88, height: 32)
    private let nameBtn = NSRect(x: 500, y: 16, width: 80, height: 32)

    override init(frame frameRect: NSRect) {
        let d = UserDefaults.standard
        let n = min(max((d.object(forKey: "durak.players") as? Int) ?? 2, 2), 4)
        let tm = d.bool(forKey: "durak.transfer")
        playersN = n
        transferMode = tm
        g = DG(players: n, transfer: tm, firstHint: nil)
        super.init(frame: frameRect)
        beginGame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Геометрия

    // от центра к краям; крайний левый слот не используем — там колода с козырем
    private let slotOrder = [3, 2, 4, 1, 5, 6, 0]
    private let slotStep: CGFloat = 88

    private var stockRect: NSRect { return NSRect(x: 24, y: tableY, width: cw, height: ch) }
    private var discardRect: NSRect { return NSRect(x: W - 106, y: 432, width: cw, height: ch) }

    /// Карты на столе стоят от центра к краям, поэтому игровая зона всегда по центру
    private func tableRect(_ k: Int) -> NSRect {
        let x0 = (W - (7 * slotStep - 8)) / 2
        return NSRect(x: x0 + CGFloat(slotOrder[min(max(k, 0), 6)]) * slotStep, y: tableY, width: cw, height: ch)
    }

    private func defRect(_ k: Int) -> NSRect { return tableRect(k).offsetBy(dx: 16, dy: 22) }

    private func oppRect(_ j: Int) -> NSRect {
        if j == 0 { return NSRect(x: W / 2 - 28, y: handY + 20, width: 56, height: 78) }
        let cx = W * (CGFloat(j - 1) + 0.5) / CGFloat(max(1, g.n - 1))
        return NSRect(x: cx - 28, y: 94, width: 56, height: 78)
    }

    /// full: true — итоговая раскладка со всеми картами (куда карты прилетят); иначе — как рука выглядит сейчас
    private func handLayout(full: Bool = false) -> [(Int, NSRect)] {
        let hand = full ? g.hands[0] : g.hands[0].filter { !waitingIn.contains($0) }
        let n = hand.count
        if n == 0 { return [] }
        let avail = W - 100
        let step: CGFloat = n > 1 ? min(cw + 8, (avail - cw) / CGFloat(n - 1)) : 0
        let total = cw + step * CGFloat(n - 1)
        let x0 = (W - total) / 2
        var r: [(Int, NSRect)] = []
        for (i, c) in hand.enumerated() {
            let lift: CGFloat = (selected == c) ? -18 : 0
            r.append((c, NSRect(x: x0 + CGFloat(i) * step, y: handY + lift, width: cw, height: ch)))
        }
        return r
    }

    private func handRect(for c: Int) -> NSRect? {
        for (cc, r) in handLayout(full: true) where cc == c { return r }
        return nil
    }

    /// Кнопки действий по центру окна: одна — ровно по центру, две («Взять» и «Перевести») — парой вокруг центра
    private var twoButtons: Bool { return g.phase == 1 && transferMode }
    private var actionA: NSRect { return NSRect(x: twoButtons ? W / 2 - 125 : W / 2 - 55, y: 514, width: 110, height: 30) }
    private var actionB: NSRect { return NSRect(x: W / 2 + 15, y: 514, width: 110, height: 30) }

    // MARK: Анимация

    private func addFlight(_ card: Int, from: NSRect, to: NSRect, at start: Double, dur: Double, upFrom: Bool, upTo: Bool,
                           onStart: (() -> Void)? = nil, onLand: (() -> Void)? = nil) {
        flights.append(DFlight(card: card, from: from, to: to, start: start, dur: dur, upFrom: upFrom, upTo: upTo,
                               started: false, onStart: onStart, onLand: onLand))
        startTicker()
    }

    private func addAction(at t: Double, _ f: @escaping () -> Void) {
        addFlight(-1, from: .zero, to: .zero, at: t, dur: 0.001, upFrom: false, upTo: false, onLand: f)
    }

    private var animEnd: Double {
        var e = CACurrentMediaTime()
        for f in flights { e = max(e, f.start + f.dur) }
        return e
    }

    private func startTicker() {
        if ticker != nil { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        var i = 0
        while i < flights.count {
            if !flights[i].started && now >= flights[i].start {
                flights[i].started = true
                if let cb = flights[i].onStart { cb() }
            }
            if i < flights.count && now >= flights[i].start + flights[i].dur {
                let cb = flights[i].onLand
                flights.remove(at: i)
                if let c = cb { c() }
                continue
            }
            i += 1
        }
        needsDisplay = true
        if flights.isEmpty {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func resetDisplay() {
        flights = []
        ticker?.invalidate()
        ticker = nil
        tAtk = []
        tDef = []
        gone = []
        flyingIn = []
        waitingIn = []
        pendingIn = [:]
        deckHold = 0
        discardShown = 0
    }

    /// Карта летит из колоды в руку игрока q
    private func queueDraw(card c: Int, player q: Int, at t: Double) {
        deckHold += 1
        var to = oppRect(q)
        if q == 0 {
            flyingIn.insert(c)
            waitingIn.insert(c)
            if let r = handRect(for: c) { to = r }
        } else {
            pendingIn[q, default: 0] += 1
        }
        addFlight(c, from: stockRect, to: to, at: t, dur: 0.38, upFrom: false, upTo: q == 0,
                  onStart: { [weak self] in self?.deckHold -= 1; self?.waitingIn.remove(c) },
                  onLand: { [weak self] in
                      guard let self = self else { return }
                      if q == 0 { self.flyingIn.remove(c) } else { self.pendingIn[q, default: 1] -= 1 }
                  })
    }

    private func drawFlights() {
        let now = CACurrentMediaTime()
        for f in flights where f.card >= 0 && now >= f.start {
            var t = CGFloat(min(1.0, max(0.0, (now - f.start) / f.dur)))
            t = t * t * (3 - 2 * t)
            let r = NSRect(x: f.from.minX + (f.to.minX - f.from.minX) * t,
                           y: f.from.minY + (f.to.minY - f.from.minY) * t,
                           width: f.from.width + (f.to.width - f.from.width) * t,
                           height: f.from.height + (f.to.height - f.from.height) * t)
            // лёгкая тень, чтобы летящая карта читалась над остальными
            NSColor(white: 0, alpha: 0.18).setFill()
            NSBezierPath(roundedRect: r.offsetBy(dx: 3, dy: 4), xRadius: 8, yRadius: 8).fill()
            drawCard(r, f.card, up: t < 0.5 ? f.upFrom : f.upTo)
        }
    }

    // MARK: Ход партии

    private var playerName: String {
        return (UserDefaults.standard.string(forKey: "durak.name") ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func lowerFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return String(f).lowercased() + s.dropFirst()
    }

    /// К игроку всегда обращаемся на «вы», а с именем — «Алексей, вы ходите» (подходит любое имя, любого рода)
    private func addressYou(_ second: String) -> String {
        let t = T(second)
        return playerName.isEmpty ? t : playerName + ", " + lowerFirst(t)
    }

    private func name(_ i: Int) -> String {
        if i == 0 { return playerName.isEmpty ? T("Вы") : playerName }
        return T("Компьютер") + " \(i)"
    }

    /// Фраза с правильной формой глагола: «%@ ходит» для имени и компьютера, «Вы ходите» для «Вы»
    private func say(_ p: Int, _ third: String, _ second: String) -> String {
        return p == 0 ? addressYou(second) : Tf(third, name(p))
    }

    /// Спрашивает имя (при первом запуске и по кнопке «Имя»)
    func askName(force: Bool) {
        let d = UserDefaults.standard
        if !force && d.object(forKey: "durak.name") != nil { return }
        guard let win = self.window else { return }
        let alert = NSAlert()
        alert.messageText = T("Как вас зовут?")
        alert.informativeText = T("Имя будет в игре вместо «Вы». Можно оставить пустым.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = playerName
        alert.accessoryView = field
        alert.addButton(withTitle: T("Сохранить"))
        alert.addButton(withTitle: T("Отмена"))
        alert.beginSheetModal(for: win) { [weak self] resp in
            guard let self = self else { return }
            if resp == .alertFirstButtonReturn {
                d.set(field.stringValue.trimmingCharacters(in: .whitespaces), forKey: "durak.name")
            } else if d.object(forKey: "durak.name") == nil {
                d.set("", forKey: "durak.name")
            }
            self.status = self.say(self.g.attacker, "%@ ходит", "Вы ходите")
            self.needsDisplay = true
        }
    }

    private func beginGame() {
        generation += 1
        selected = nil
        finished = false
        resetDisplay()
        var hint: Int? = nil
        if let l = lastLoser, l < playersN { hint = l }
        g = DG(players: playersN, transfer: transferMode, firstHint: hint)
        g.normalize()
        sortHuman()
        status = say(g.attacker, "%@ ходит", "Вы ходите")
        // раздача: карты по одной летят из колоды
        let now = CACurrentMediaTime()
        var k = 0
        for r in 0..<6 {
            for p in 0..<playersN {
                queueDraw(card: g.hands[p][r], player: p, at: now + 0.2 + Double(k) * 0.07)
                k += 1
            }
        }
        needsDisplay = true
        schedule()
    }

    func pause() { generation += 1 }

    func resume() {
        generation += 1
        schedule()
    }

    private func sortHuman() {
        let ts = g.trumpSuit
        g.hands[0].sort { (a: Int, b: Int) -> Bool in
            let ta = dSuit(a) == ts
            let tb = dSuit(b) == ts
            if ta != tb { return !ta }
            if dSuit(a) != dSuit(b) { return dSuit(a) < dSuit(b) }
            return dRank(a) < dRank(b)
        }
    }

    private func schedule() {
        let gen = generation
        let wait = max(0, animEnd - CACurrentMediaTime())
        if g.over {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.25) { [weak self] in
                guard let self = self, gen == self.generation else { return }
                self.finish()
            }
            return
        }
        if g.actor == 0 { needsDisplay = true; return }
        let snapshot = g
        let delay: Double = (g.out[0] ? 0.3 : 0.55) + wait
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, gen == self.generation else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let m = dAIChoose(snapshot)
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.perform(m)
                }
            }
        }
    }

    private func perform(_ m: DMove) {
        let p = g.actor
        let wasPhase = g.phase
        let tookNow = g.taking || m == .take
        let defBefore = g.defender
        let attBefore = g.attacker
        let beforeHands = g.hands
        var msg = ""
        switch m {
        case .play: msg = wasPhase == 0 ? say(p, "%@ ходит", "Вы ходите") : say(p, "%@ подкидывает", "Вы подкидываете")
        case .beat: msg = say(p, "%@ бьёт", "Вы бьёте")
        case .transfer: msg = say(p, "%@ переводит", "Вы переводите")
        case .take: msg = say(p, "%@ берёт карты", "Вы берёте карты")
        case .pass: break
        }

        // откуда и куда полетит сыгранная карта
        var card = -1
        switch m {
        case .play(let c): card = c
        case .beat(let c, _): card = c
        case .transfer(let c): card = c
        default: break
        }
        var from = oppRect(p)
        if p == 0 && card >= 0, let r = handRect(for: card) { from = r }
        if card >= 0 { SolAssets.play("kard") }
        let now = CACurrentMediaTime()
        var preAtk = tAtk
        var preDef = tDef
        var landT = now
        switch m {
        case .play(let c), .transfer(let c):
            let k = preAtk.count
            preAtk.append(c)
            preDef.append(-1)
            addFlight(c, from: from, to: tableRect(k), at: now, dur: 0.35, upFrom: p == 0, upTo: true,
                      onLand: { [weak self] in
                          self?.tAtk.append(c)
                          self?.tDef.append(-1)
                      })
            landT = now + 0.35
        case .beat(let c, let i):
            preDef[i] = c
            addFlight(c, from: from, to: defRect(i), at: now, dur: 0.35, upFrom: p == 0, upTo: true,
                      onLand: { [weak self] in
                          if let s = self, i < s.tDef.count { s.tDef[i] = c }
                      })
            landT = now + 0.35
        default:
            break
        }

        g.apply(m)
        g.normalize()
        sortHuman()
        var animT = landT
        var takenSet = Set<Int>()

        // конец раунда: карты со стола улетают в «бито» или к тому, кто взял
        if g.tableAtk.isEmpty && !preAtk.isEmpty {
            let sweepStart = landT + 0.5
            var entries: [(Int, NSRect)] = []
            for k in 0..<preAtk.count {
                entries.append((preAtk[k], tableRect(k)))
                if preDef[k] >= 0 { entries.append((preDef[k], defRect(k))) }
            }
            var j = 0
            for (c, r) in entries {
                let t = sweepStart + Double(j) * 0.05
                j += 1
                if tookNow {
                    takenSet.insert(c)
                    var to = oppRect(defBefore)
                    if defBefore == 0 {
                        flyingIn.insert(c)
                        waitingIn.insert(c)
                        if let hr = handRect(for: c) { to = hr }
                    } else {
                        pendingIn[defBefore, default: 0] += 1
                    }
                    let d = defBefore
                    addFlight(c, from: r, to: to, at: t, dur: 0.45, upFrom: true, upTo: d == 0,
                              onStart: { [weak self] in self?.gone.insert(c); self?.waitingIn.remove(c) },
                              onLand: { [weak self] in
                                  guard let self = self else { return }
                                  if d == 0 { self.flyingIn.remove(c) } else { self.pendingIn[d, default: 1] -= 1 }
                              })
                } else {
                    addFlight(c, from: r, to: discardRect, at: t, dur: 0.45, upFrom: true, upTo: false,
                              onStart: { [weak self] in self?.gone.insert(c) },
                              onLand: { [weak self] in self?.discardShown += 1 })
                }
            }
            let sweepEnd = sweepStart + Double(max(0, j - 1)) * 0.05 + 0.45
            addAction(at: sweepEnd) { [weak self] in
                self?.tAtk = []
                self?.tDef = []
                self?.gone = []
            }
            animT = sweepEnd
            msg = tookNow ? say(defBefore, "%@ забирает карты", "Вы забираете карты") : T("Бито")
            if !g.over { msg += " · " + say(g.attacker, "%@ ходит", "Вы ходите") }
        }

        // добор: сначала атаковавшие, защитник последним
        var order: [Int] = []
        for k in 0..<g.n {
            let q = (attBefore + k) % g.n
            if q != defBefore { order.append(q) }
        }
        order.append(defBefore)
        var jj = 0
        for q in order {
            let before = Set(beforeHands[q])
            for c in g.hands[q] where !before.contains(c) && !takenSet.contains(c) {
                queueDraw(card: c, player: q, at: animT + 0.1 + Double(jj) * 0.12)
                jj += 1
            }
        }

        if !msg.isEmpty { status = msg }
        selected = nil
        needsDisplay = true
        schedule()
    }

    private func finish() {
        if finished { needsDisplay = true; return }
        finished = true
        lastLoser = g.loser
        needsDisplay = true
    }

    private func humanAct(_ m: DMove) {
        if g.actor != 0 || g.over || !flights.isEmpty { return }
        perform(m)
    }

    private var humanTurn: Bool { return g.actor == 0 && !g.over && flights.isEmpty }

    // MARK: Мышь

    private func canTransfer(_ c: Int?) -> Bool {
        guard let c = c, g.actor == 0, g.phase == 1 else { return false }
        return g.legalMoves().contains(.transfer(c))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if newBtn.contains(p) { beginGame(); return }
        if playersBtn.contains(p) { showPlayersMenu(); return }
        if modeBtn.contains(p) { showModeMenu(); return }
        if viewBtn.contains(p) { showViewMenu(); return }
        if nameBtn.contains(p) { askName(force: true); return }
        if g.over {
            if finished && flights.isEmpty { beginGame() }
            return
        }
        if !humanTurn { return }

        // кнопки действий
        if g.phase == 1 {
            if actionA.contains(p) { humanAct(.take); return }
            if transferMode && actionB.contains(p), let s = selected, canTransfer(s) { humanAct(.transfer(s)); return }
        } else if g.phase == 2 {
            if actionA.contains(p) { humanAct(.pass); return }
        }

        // карта в руке (верхняя — правая)
        for (c, r) in handLayout().reversed() where r.contains(p) && !flyingIn.contains(c) {
            handClick(c)
            return
        }
        // цель на столе
        if g.phase == 1, let s = selected {
            for i in 0..<tAtk.count where i < tDef.count && tDef[i] < 0 && tableRect(i).contains(p) {
                if g.legalMoves().contains(.beat(s, i)) { humanAct(.beat(s, i)); return }
            }
        }
        selected = nil
        needsDisplay = true
    }

    private func handClick(_ c: Int) {
        let moves = g.legalMoves()
        if g.phase != 1 {
            if moves.contains(.play(c)) {
                humanAct(.play(c))
            } else {
                status = T("Этой картой сейчас нельзя ходить")
                needsDisplay = true
            }
            return
        }
        var targets: [Int] = []
        for m in moves {
            if case .beat(let cc, let i) = m, cc == c { targets.append(i) }
        }
        let tr = moves.contains(.transfer(c))
        if selected == c {
            if let first = targets.first { humanAct(.beat(c, first)) }
            else if tr { humanAct(.transfer(c)) }
            return
        }
        if targets.count == 1 && !tr {
            humanAct(.beat(c, targets[0]))
        } else if targets.isEmpty && !tr {
            status = T("Этой картой не отбиться")
            selected = nil
            needsDisplay = true
        } else {
            selected = c
            status = tr ? T("Выберите карту на столе или нажмите «Перевести»") : T("Выберите карту на столе")
            needsDisplay = true
        }
    }

    // MARK: Меню

    private func showPlayersMenu() {
        let menu = NSMenu()
        for n in 2...4 {
            let item = NSMenuItem(title: "\(T("Игроков")): \(n)", action: #selector(pickPlayers(_:)), keyEquivalent: "")
            item.target = self
            item.tag = n
            item.state = n == playersN ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: playersBtn.minX, y: playersBtn.maxY + 2), in: self)
    }

    private func showModeMenu() {
        let menu = NSMenu()
        let a = NSMenuItem(title: T("Подкидной"), action: #selector(pickMode(_:)), keyEquivalent: "")
        a.target = self
        a.tag = 0
        a.state = transferMode ? .off : .on
        menu.addItem(a)
        let b = NSMenuItem(title: T("Переводной"), action: #selector(pickMode(_:)), keyEquivalent: "")
        b.target = self
        b.tag = 1
        b.state = transferMode ? .on : .off
        menu.addItem(b)
        menu.popUp(positioning: nil, at: NSPoint(x: modeBtn.minX, y: modeBtn.maxY + 2), in: self)
    }

    @objc private func pickPlayers(_ sender: NSMenuItem) {
        if sender.tag == playersN { return }
        playersN = sender.tag
        UserDefaults.standard.set(playersN, forKey: "durak.players")
        beginGame()
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        let tm = sender.tag == 1
        if tm == transferMode { return }
        transferMode = tm
        UserDefaults.standard.set(tm, forKey: "durak.transfer")
        beginGame()
    }

    /// Меню «Вид»: рубашка и цвет стола (общие с «Косынкой»)
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

        menu.popUp(positioning: nil, at: NSPoint(x: viewBtn.minX, y: viewBtn.maxY + 2), in: self)
    }

    @objc private func pickBack(_ sender: NSMenuItem) {
        SolAssets.backIndex = sender.tag
        needsDisplay = true
    }

    @objc private func pickTable(_ sender: NSMenuItem) {
        SolAssets.tableIndex = sender.tag
        needsDisplay = true
    }

    // MARK: Рисование

    private func drawString(_ s: String, _ rect: NSRect, size: CGFloat, color: NSColor,
                            align: NSTextAlignment = .left, bold: Bool = false) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (s as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps])
    }

    /// У каждого игрока свой цвет имени — светлые тона, читаются на любом цвете стола
    private func nameColor(_ i: Int) -> NSColor {
        let cols: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.50, green: 0.82, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.74, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.70, blue: 1.0, alpha: 1)]
        return cols[i % cols.count]
    }

    /// Текст, в котором имена игроков покрашены в их цвета (и чуть крупнее); underline — подчеркнуть имя того, чей сейчас ход
    private func drawColored(_ s: String, _ rect: NSRect, size: CGFloat, base: NSColor,
                             align: NSTextAlignment, bold: Bool = false, underline: Int? = nil) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let at = NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: base, .paragraphStyle: ps])
        let ns = s as NSString
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 2
        for i in 0..<g.n {
            let nm = name(i)
            if nm.isEmpty { continue }
            var search = NSRange(location: 0, length: ns.length)
            while search.length > 0 {
                let r = ns.range(of: nm, options: [], range: search)
                if r.location == NSNotFound { break }
                var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: nameColor(i),
                                                            .font: NSFont.boldSystemFont(ofSize: size + 2),
                                                            .shadow: shadow]
                if underline == i { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                at.addAttributes(attrs, range: r)
                let next = r.location + r.length
                search = NSRange(location: next, length: ns.length - next)
            }
        }
        at.draw(in: rect)
    }

    private func drawButton(_ r: NSRect, _ title: String, enabled: Bool = true) {
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        NSColor(white: 1, alpha: enabled ? 0.18 : 0.07).setFill()
        path.fill()
        drawString(title, NSRect(x: r.minX, y: r.minY + 7, width: r.width, height: r.height - 7),
                   size: 13, color: NSColor(white: 1, alpha: enabled ? 1 : 0.4), align: .center)
    }

    private func drawCard(_ r: NSRect, _ c: Int, up: Bool) {
        let rk = dRank(c) == 14 ? 1 : dRank(c)
        let sc = SolCard(suit: dSuit(c), rank: rk, up: up)
        if let img = (up ? SolAssets.image(SolAssets.faceName(sc)) : SolAssets.backImage) {
            let w = r.height * img.size.width / img.size.height
            let dst = NSRect(x: r.minX + (r.width - w) / 2, y: r.minY, width: w, height: r.height)
            img.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                     hints: [.interpolation: NSImageInterpolation.high])
            return
        }
        // запасной вариант без картинок
        let path = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        if up {
            NSColor.white.setFill()
            path.fill()
            NSColor(white: 0.55, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
            let red = dSuit(c) == 1 || dSuit(c) == 2
            let col = red ? NSColor(calibratedRed: 0.78, green: 0.08, blue: 0.10, alpha: 1) : NSColor(white: 0.1, alpha: 1)
            let names = [6: "6", 7: "7", 8: "8", 9: "9", 10: "10", 11: "J", 12: "Q", 13: "K", 14: "A"]
            let suit = ["♠", "♥", "♦", "♣"][dSuit(c)] + "\u{FE0E}"
            drawString((names[dRank(c)] ?? "") + suit, NSRect(x: r.minX + 6, y: r.minY + 4, width: r.width, height: 22),
                       size: 16, color: col, bold: true)
            drawString(suit, NSRect(x: r.minX, y: r.midY - 20, width: r.width, height: 60),
                       size: 42, color: col, align: .center)
        } else {
            NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.68, alpha: 1).setFill()
            path.fill()
            NSColor(white: 0.9, alpha: 1).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// Козырь лежит под колодой боком и выглядывает справа
    private func drawSidewaysTrump() {
        guard let ctx = NSGraphicsContext.current else { return }
        let s = stockRect
        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: s.minX + 28 + 56, yBy: s.minY + 56)
        t.rotate(byDegrees: 90)
        t.concat()
        drawCard(NSRect(x: -cw / 2, y: -ch / 2, width: cw, height: ch), g.trumpCard, up: true)
        ctx.restoreGraphicsState()
    }

    private func roleText(_ i: Int) -> String {
        if g.out[i] { return T("вне игры") }
        if g.over { return "" }
        let you = i == 0
        if i == g.defender {
            if g.taking { return you ? T("берёте") : T("берёт") }
            return you ? T("отбиваетесь") : T("отбивается")
        }
        if i == g.attacker { return you ? T("атакуете") : T("атакует") }
        return ""
    }

    override func draw(_ dirtyRect: NSRect) {
        SolAssets.tables[SolAssets.tableIndex].color.setFill()
        bounds.fill()

        drawButton(newBtn, T("Новая игра"))
        drawButton(playersBtn, "\(T("Игроков")): \(playersN)")
        drawButton(modeBtn, transferMode ? T("Переводной") : T("Подкидной"))
        drawButton(viewBtn, T("Вид"))
        drawButton(nameBtn, T("Имя"))

        // соперники сверху
        for j in 1..<g.n {
            let cx = oppRect(j).midX
            let role = roleText(j)
            let title = name(j) + (role.isEmpty ? "" : " — " + role)
            let active = j == g.actor && !g.over
            drawColored(title, NSRect(x: cx - 170, y: 66, width: 340, height: 24), size: 15, base: .white,
                        align: .center, underline: active ? j : nil)
            let m = max(0, g.hands[j].count - (pendingIn[j] ?? 0))
            if m > 0 {
                let step: CGFloat = m > 1 ? min(18, 190 / CGFloat(m - 1)) : 0
                let total = 56 + step * CGFloat(m - 1)
                let x0 = cx - total / 2
                for i in 0..<m {
                    drawCard(NSRect(x: x0 + CGFloat(i) * step, y: 94, width: 56, height: 78), 0, up: false)
                }
                drawString("\(m)", NSRect(x: cx - 30, y: 176, width: 60, height: 16), size: 12,
                           color: NSColor(white: 1, alpha: 0.7), align: .center)
            }
        }

        // колода стопкой, козырь под ней боком, число карт в кружке
        let shown = g.deck.count + deckHold
        let s = stockRect
        if shown >= 1 { drawSidewaysTrump() }
        if shown > 1 {
            let layers = min(5, max(1, (shown - 1 + 5) / 7))
            for l in stride(from: layers - 1, through: 0, by: -1) {
                drawCard(s.offsetBy(dx: -CGFloat(l) * 2, dy: -CGFloat(l) * 1.5), 0, up: false)
            }
        }
        if shown == 0 {
            // колода кончилась: масть козыря — красная или чёрная, на лёгкой светлой тени
            let glyph = ["♠", "♥", "♦", "♣"][g.trumpSuit] + "\u{FE0E}"
            let red = g.trumpSuit == 1 || g.trumpSuit == 2
            // светлое свечение по форме самой масти — без плашки и рамки
            let ps = NSMutableParagraphStyle(); ps.alignment = .center
            let glow = NSShadow()
            glow.shadowColor = NSColor(white: 1, alpha: 0.85)
            glow.shadowOffset = .zero
            glow.shadowBlurRadius = 9
            let suitCol = red ? NSColor(calibratedRed: 0.85, green: 0.10, blue: 0.12, alpha: 1)
                              : NSColor(calibratedWhite: 0.07, alpha: 1)
            let at = NSAttributedString(string: glyph, attributes: [
                .font: NSFont.systemFont(ofSize: 34), .foregroundColor: suitCol,
                .paragraphStyle: ps, .shadow: glow])
            let box = NSRect(x: s.minX - 10, y: s.midY - 22, width: s.width + 20, height: 44)
            at.draw(in: box)
            at.draw(in: box)   // второй проход усиливает свечение
        }
        let badge = NSRect(x: s.midX - 18, y: s.maxY + 10, width: 36, height: 36)
        NSColor(white: 0, alpha: 0.42).setFill()
        NSBezierPath(ovalIn: badge).fill()
        drawString("\(shown)", NSRect(x: badge.minX, y: badge.minY + 9, width: badge.width, height: 20), size: 15,
                   color: .white, align: .center, bold: true)

        // отбой: в углу, притушен вуалью
        if discardShown > 0 {
            let d = discardRect
            let layers = min(3, (discardShown + 5) / 6)
            for l in 0..<layers {
                let r = d.offsetBy(dx: CGFloat(l) * 3, dy: CGFloat(l) * 2)
                drawCard(r, 0, up: false)
                NSColor(white: 0, alpha: 0.45).setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            }
            drawString(T("Бито") + ": \(discardShown)", NSRect(x: d.minX - 20, y: d.maxY + 3, width: 120, height: 18),
                       size: 12, color: NSColor(white: 1, alpha: 0.7), align: .center)
        }

        // стол
        let canAct = humanTurn
        var playable = Set<Int>()
        var targets = Set<Int>()
        if canAct {
            for m in g.legalMoves() {
                switch m {
                case .play(let c): playable.insert(c)
                case .beat(let c, let i):
                    playable.insert(c)
                    if let sel = selected, sel == c { targets.insert(i) }
                case .transfer(let c): playable.insert(c)
                default: break
                }
            }
        }
        for i in 0..<tAtk.count where !gone.contains(tAtk[i]) {
            let r = tableRect(i)
            drawCard(r, tAtk[i], up: true)
            if i < tDef.count && tDef[i] >= 0 && !gone.contains(tDef[i]) {
                drawCard(defRect(i), tDef[i], up: true)
            }
            if targets.contains(i) {
                let hl = NSBezierPath(roundedRect: r.insetBy(dx: -2, dy: -2), xRadius: 8, yRadius: 8)
                NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1).setStroke()
                hl.lineWidth = 3
                hl.stroke()
            }
        }

        // строка состояния
        drawColored(status, NSRect(x: 160, y: 456, width: W - 320, height: 24), size: 15, base: .white, align: .center, bold: true)
        if canAct {
            var hint = ""
            switch g.phase {
            case 0: hint = T("Ваш ход: выберите карту")
            case 1: hint = T("Отбейте карту или возьмите")
            default: hint = g.taking ? T("Можно подкинуть ещё или нажать «Хватит»") : T("Подкиньте карту или нажмите «Бито»")
            }
            drawString(hint, NSRect(x: 160, y: 482, width: W - 320, height: 20), size: 13,
                       color: NSColor(white: 1, alpha: 0.8), align: .center)
            if g.phase == 1 {
                drawButton(actionA, T("Взять"))
                if transferMode { drawButton(actionB, T("Перевести"), enabled: canTransfer(selected)) }
            } else if g.phase == 2 {
                drawButton(actionA, g.taking ? T("Хватит") : T("Бито"))
            }
        }

        // ваша рука на подсвеченной панели
        let panel = NSRect(x: 20, y: 568, width: W - 40, height: 156)
        let pp = NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14)
        NSColor(white: 1, alpha: canAct ? 0.14 : 0.09).setFill()
        pp.fill()
        NSColor(white: 1, alpha: canAct ? 0.45 : 0.25).setStroke()
        pp.lineWidth = canAct ? 2 : 1.2
        pp.stroke()
        let myRole = roleText(0)
        let myTitle = (playerName.isEmpty ? T("Вы") : playerName + ", " + T("вы")) + (myRole.isEmpty ? "" : " " + myRole)
        drawColored(myTitle, NSRect(x: 38, y: 571, width: 520, height: 24), size: 15, base: .white,
                    align: .left, underline: canAct ? 0 : nil)
        for (c, r) in handLayout() where !flyingIn.contains(c) {
            drawCard(r, c, up: true)
            if canAct && !playable.contains(c) {
                NSColor(white: 0, alpha: 0.28).setFill()
                NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
            }
        }

        drawFlights()
        if g.over && finished && flights.isEmpty { drawResult() }
    }

    private func drawResult() {
        let r = NSRect(x: W / 2 - 220, y: 250, width: 440, height: 150)
        NSColor(white: 0, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
        var title = ""
        var sub = ""
        if let l = g.loser {
            if l == 0 {
                title = addressYou("Вы остались в дураках")
            } else {
                title = T("Победа!")
                sub = Tf("Дурак: %@", name(l))
            }
        } else {
            title = T("Ничья")
        }
        drawColored(title, NSRect(x: r.minX + 10, y: r.minY + 28, width: r.width - 20, height: 36), size: 22,
                    base: .white, align: .center, bold: true)
        if !sub.isEmpty {
            drawColored(sub, NSRect(x: r.minX, y: r.minY + 68, width: r.width, height: 24), size: 16,
                        base: NSColor(white: 1, alpha: 0.85), align: .center)
        }
        drawString(T("Нажмите чтобы начать заново"), NSRect(x: r.minX, y: r.minY + 108, width: r.width, height: 20),
                   size: 12, color: NSColor(white: 1, alpha: 0.6), align: .center)
    }
}

final class DurakWindowController: NSObject, NSWindowDelegate {
    static let shared = DurakWindowController()
    private var window: NSWindow?
    private var game: DurakView?

    private var title: String { return T("Дурак") }

    func show() {
        if window == nil {
            let size = NSSize(width: 900, height: 740)
            let v = DurakView(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = v
            w.delegate = self
            if !w.setFrameUsingName("DurakWindow") { w.center() }
            w.setFrameAutosaveName("DurakWindow")
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
            DispatchQueue.main.async { g.askName(force: false) }
        }
    }

    @objc private func languageChanged() {
        window?.title = title
        game?.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) { game?.pause() }
}

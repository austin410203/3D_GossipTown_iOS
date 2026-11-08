// The rumour engine — a line-by-line port of the web sim.js (who is where, who tells whom, how it mutates, who believes it,
// how feelings change, events, stars). Must stay identical to the web build: `coretest golden` replays Tests/golden.txt.
import Foundation

public let YOU = "you"
let YOU_TRUST = 10.0

public final class KnowEntry: Codable {
  public var c: Claim
  public var from: String
  public var believed: Bool
  public var root, node, gen: Int
  public var tellers: [String]
  public var heard: Int
  public var told: [String]
  init(c: Claim, from: String, believed: Bool, root: Int, node: Int, gen: Int) {
    self.c = c; self.from = from; self.believed = believed; self.root = root; self.node = node; self.gen = gen
    tellers = [from]; heard = 1; told = []
  }
}
/// One resident's rumours in the order they heard them (JS object insertion order).
public struct KnowMap: Codable {
  public private(set) var order: [String] = []
  public private(set) var dict: [String: KnowEntry] = [:]
  public subscript(_ k: String) -> KnowEntry? {
    get { dict[k] }
    set { if dict[k] == nil { order.append(k) }; dict[k] = newValue }
  }
  public var values: [KnowEntry] { order.compactMap { dict[$0] } }
  public var isEmpty: Bool { order.isEmpty }
}
public struct Heard: Codable, Equatable { public var id: String, out: String; public init(id: String, out: String) { self.id = id; self.out = out } }
public final class Node: Codable {
  public let id: Int
  public let parent: Int?
  public let root: Int
  public let c: Claim
  public let teller, listener: String
  public let h: Double
  public let mut: String?
  public let gen: Int
  public var out = ""
  public var heard: [Heard]?
  init(id: Int, parent: Int?, root: Int, c: Claim, teller: String, listener: String, h: Double, mut: String?, gen: Int) {
    self.id = id; self.parent = parent; self.root = root; self.c = c; self.teller = teller; self.listener = listener; self.h = h; self.mut = mut; self.gen = gen
  }
}
public struct WhisperRec: Codable { public var to: String, others: [String], c: Claim, node: Int, phase: Int }
/// One thing that happens while a part of the day plays: a talk (t tells l) or an event (makeup / date / protest).
public struct Item: Codable {
  public var type: String
  public var h: Double
  public var place: String
  public var t: String? = nil, l: String? = nil, c: Claim? = nil, from: Claim? = nil, mut: String? = nil, out: String? = nil, node: Int? = nil
  public var a: String? = nil, b: String? = nil, p: String? = nil, who: [String]? = nil
  public var falsePlan: Bool? = nil
}
public struct DayResult: Codable { public var stars, reach, gen: Int; public var goalMet: Bool }
public struct Spread { public var reach, gen, muts: Int }

// ── things only the app uses, saved with the day ──
public struct Quest: Codable { public var lang, ask, story, via: String
  public init(lang: String, ask: String, story: String, via: String) { self.lang = lang; self.ask = ask; self.story = story; self.via = via } }
public struct ChatRow: Codable {
  public var who: String? = nil, text: String? = nil, note: String? = nil, chip: String? = nil
  public var heard: [Heard]? = nil, eff: [String]? = nil
  public init(who: String? = nil, text: String? = nil, note: String? = nil, chip: String? = nil, heard: [Heard]? = nil, eff: [String]? = nil) {
    self.who = who; self.text = text; self.note = note; self.chip = chip; self.heard = heard; self.eff = eff
  }
}
public struct ChatState: Codable {
  public var phase = 0, said = 0, rumors = 0, bonus = 0
  public var logs: [String: [ChatRow]] = [:]
  public var scened: Set<String> = []
  public init() {}
}

public final class Day: Codable {
  public var day: Int
  public var goal: Goal
  public var phase = 0
  public var whispers: [WhisperRec] = []
  public var nodes: [Node] = []
  public var know: [String: KnowMap]
  public var done = false
  public var protestOrder: [String] = []
  public var protest: [String: [String]] = [:]
  public var truth: [String]
  public var goalMet = false
  public var mood: String
  public var override: [String: String]? = nil
  public var protested: Set<String> = []
  public var result: DayResult? = nil
  // app
  public var quest: Quest? = nil
  public var chat: ChatState? = nil
  public var spots: Set<String> = []
  public var headline: String? = nil
  public var logged = false
  init(day: Int, goal: Goal, ids: [String], truth: [String], mood: String) {
    self.day = day; self.goal = goal; self.truth = truth; self.mood = mood
    know = Dictionary(uniqueKeysWithValues: ids.map { ($0, KnowMap()) })
  }
  func addProtest(_ p: String, _ x: String) {
    if protest[p] == nil { protestOrder.append(p); protest[p] = [] }
    if !protest[p]!.contains(x) { protest[p]!.append(x) }
  }
}

public final class Town: Codable {
  public var v = 1
  public var seed: Double
  public var day = 1
  public var aff: [String: [String: Int]]
  public var feuds: [[String]] = [["baker", "clock"]]
  public var couples: [[String]] = []
  public var fixed: [[String]] = []
  public var cancelled: [String] = []
  public var stars: [String: Int] = [:]
  public var bestReach = 0, bestGen = 0
  public var totalWhispers = 0
  public var today: Day? = nil
  public var runs = 0
  public var lastType: String? = nil
  public var snap: Data? = nil
  init(seed: Double, aff: [String: [String: Int]]) { self.seed = seed; self.aff = aff }
}

/// Everything sim.js exports.
public enum Sim {
  static var G: GameData { GameData.shared }

  public static func newTown(seed: Double = Double(Int.random(in: 0..<1_000_000_000))) -> Town {
    Town(seed: seed, aff: G.initialAffinity(Mulberry(js: seed)))
  }

  public static func goalFor(_ town: Town, day: Int? = nil) -> Goal {
    let day = day ?? town.day, G = G
    if day == 1, let g = G.goals.first(where: { ($0["day"] as? NSNumber)?.intValue == 1 }) {
      return Goal(day: 1, type: g["type"] as! String, a: g["a"] as! String, b: g["b"] as? String, p: g["p"] as? String, who: "granny", free: false)
    }
    let r = Mulberry(js: town.seed + Double(day * 31))
    var pairs: [(String, String, Int)] = []
    for a in G.ids { for b in G.ids where a < b { pairs.append((a, b, town.aff[a]![b]! + town.aff[b]![a]!)) } }
    let places = G.caresOrder.filter { !town.cancelled.contains($0) }
    let has = { (f: [String], a: String, b: String) in f.contains(a) && f.contains(b) }
    let feudPairs = pairs.filter { p in p.0 != "kid" && p.1 != "kid" && !town.feuds.contains { has($0, p.0, p.1) } }.jsSorted { Double($0.2 - $1.2) }
    let datePairs = pairs.filter { p in
      !town.couples.contains { $0.contains(p.0) || $0.contains(p.1) } && p.0 != "kid" && p.1 != "kid"
        && !town.feuds.contains { f in has(f, p.0, p.1) && !town.fixed.contains { has($0, p.0, p.1) } }
    }.jsSorted { Double($1.2 - $0.2) }
    let ok: [(String, Bool)] = [("reconcile", !feudPairs.isEmpty), ("date", !datePairs.isEmpty), ("protest", !places.isEmpty)]
    var kinds = ok.filter { $0.1 && $0.0 != town.lastType }.map(\.0)
    if kinds.isEmpty { kinds = ok.filter(\.1).map(\.0) }
    let ki = jsFloor(r() * Double(kinds.count))
    let kind = ki < kinds.count ? kinds[ki] : "reconcile"
    town.lastType = kind
    var goal: Goal
    if kind == "reconcile" {
      let p = feudPairs.isEmpty ? pairs : feudPairs
      let (a, b, _) = p[jsFloor(r() * Double(min(5, p.count)))]
      town.aff[a]![b] = min(town.aff[a]![b]!, -45); town.aff[b]![a] = min(town.aff[b]![a]!, -50)
      town.feuds.append([a, b])
      goal = Goal(day: day, type: "reconcile", a: a, b: b, p: nil, who: "", free: true)
    } else if kind == "date" {
      let (a, b, _) = datePairs[jsFloor(r() * Double(min(5, datePairs.count)))]
      town.aff[a]![b] = max(town.aff[a]![b]!, 30); town.aff[b]![a] = max(town.aff[b]![a]!, 28)
      goal = Goal(day: day, type: "date", a: a, b: b, p: nil, who: "", free: true)
    } else {
      goal = Goal(day: day, type: "protest", a: "mayor", b: nil, p: places[jsFloor(r() * Double(places.count))], who: "", free: true)
    }
    goal.who = requester(town, goal)
    return goal
  }
  static func requester(_ town: Town, _ g: Goal) -> String {
    let A = town.aff, others = G.ids.filter { $0 != g.a && $0 != g.b && $0 != "mayor" }
    if g.type == "protest" {
      let c = (G.cares[g.p ?? ""] ?? []).filter { others.contains($0) }
      return c.contains("kid") ? "kid" : c.first ?? "granny"
    }
    let score = { (x: String) -> Int in g.type == "reconcile" ? min(A[x]![g.a]!, A[x]![g.b!]!) : max(A[x]![g.a]!, A[x]![g.b!]!) }
    return others.jsSorted { Double(score($1) - score($0)) }[0]
  }

  @discardableResult
  public static func startDay(_ town: Town, keepGoal: Goal? = nil) -> Day {
    let goal = keepGoal ?? goalFor(town)
    town.runs += 1
    let truth = goal.type == "protest" ? [Claim(k: "demolish", a: goal.a, p: goal.p).key] : []
    let mr = Mulberry(js: town.seed + Double(town.day * 389 + town.runs * 31))
    let mood = G.moodIds[jsFloor(mr() * Double(G.moodIds.count))]
    let d = Day(day: town.day, goal: goal, ids: G.ids, truth: truth, mood: mood)
    town.today = d
    return d
  }

  static func beliefP(_ town: Town, _ x: String, _ t: String, _ c: Claim, _ entry: KnowEntry?) -> Double {
    let R = G.res[x]!, aff = town.aff[x]!, K = G.kinds[c.k]!
    var p = 0.15 + 0.5 * R.cred
    p += (t == YOU ? YOU_TRUST : Double(aff[t] ?? 0)) / 100 * 0.35
    if c.a != x {
      let feelA = Double(aff[c.a] ?? 0)
      if K.val < 0 { p -= feelA / 100 * 0.6 } else if K.val > 0 { p += feelA / 100 * 0.08 }
    }
    if c.b == x && K.val > 0 { p += 0.15 }
    if let e = entry { p += 0.15 * Double(min(3, e.tellers.count)) }
    for e in town.today!.know[x]!.values where e.believed && e.c.a == c.a && e.c.b == c.b && G.kinds[e.c.k]!.val * K.val < 0 { p -= 0.25; break }
    if town.today!.truth.contains(c.key) { p += 0.32 }
    return clamp(p, 0.03, 0.95)
  }

  static func applyEffect(_ town: Town, _ x: String, _ t: String, _ c: Claim, _ mult: Double) {
    func add(_ from: String, _ to: String, _ v: Double) {
      guard from != to, let cur = town.aff[from]?[to] else { return }
      town.aff[from]![to] = clampI(jsRound(Double(cur) + v * mult), -100, 100)
    }
    switch c.k {
    case "likes": if x == c.b { add(c.b!, c.a, 22) }
    case "engaged": if x == c.b { add(c.b!, c.a, 10) }
    case "praised": if x == c.b { add(c.b!, c.a, 20) } else { add(x, c.a, 3) }
    case "badmouth": if x == c.b { add(c.b!, c.a, -25) } else { add(x, c.a, -4) }
    case "apology": if x == c.b { add(c.b!, c.a, town.aff[c.b!]![c.a]! < 0 ? 45 : 22) }
    case "gift": if x == c.b { add(c.b!, c.a, 15) }
    case "demolish":
      let cares = (G.cares[c.p ?? ""] ?? []).contains(x)
      add(x, c.a, cares ? -18 : -6)
      if cares { town.today!.addProtest(c.p!, x) }
    default: break
    }
    if t != YOU { add(x, t, 1) }
  }
  static func selfEffect(_ town: Town, _ x: String, _ t: String, _ c: Claim) {
    func add(_ to: String, _ v: Int) { if let cur = town.aff[x]?[to] { town.aff[x]![to] = clampI(cur + v, -100, 100) } }
    if ["apology", "gift", "likes", "engaged", "praised"].contains(c.k), let b = c.b { add(b, c.k == "apology" ? 16 : 8) }
    if c.k == "badmouth" && t != YOU { add(t, -5) }
  }

  struct NodeInfo { var parent: Int?; var root: Int; var h: Double; var mut: String? = nil; var gen = 0; var r: Mulberry }
  static func deliver(_ town: Town, _ x: String, _ t: String, _ c: Claim, _ info: NodeInfo) -> Node {
    let day = town.today!, key = c.key
    let node = Node(id: day.nodes.count, parent: info.parent, root: info.root, c: c, teller: t, listener: x, h: info.h, mut: info.mut, gen: info.gen)
    day.nodes.append(node)
    if x == c.a { selfEffect(town, x, t, c); node.out = "self"; return node }
    if let e = day.know[x]![key] {
      if e.tellers.contains(t) { node.out = "again"; return node }
      let was = e.believed
      if !was { e.believed = info.r() < beliefP(town, x, t, c, e) }
      e.tellers.append(t); e.heard += 1
      let mult = [1, 0.6, 0.35, 0][min(3, e.heard - 1)]
      if e.believed { applyEffect(town, x, t, c, was ? mult : 1) }
      node.out = e.believed ? (was ? "agree" : "believe") : "doubt"
      return node
    }
    let believed = info.r() < beliefP(town, x, t, c, nil)
    day.know[x]![key] = KnowEntry(c: c, from: t, believed: believed, root: node.root, node: node.id, gen: node.gen)
    if believed { applyEffect(town, x, t, c, 1) }
    node.out = believed ? "believe" : "doubt"
    return node
  }

  /// The player says a rumour to `to`; everyone else in `others` (same place) hears it too.
  @discardableResult
  public static func whisper(_ town: Town, to: String, claim: Claim, others: [String] = []) -> Node? {
    guard G.validClaim(claim), G.res[to] != nil, let day = town.today else { return nil }
    let ph = G.phases[day.phase]
    let r = Mulberry(js: town.seed + Double(day.day * 977 + day.whispers.count * 131 + town.runs * 7919 + 7))
    let c = Claim(k: claim.k, a: claim.a, b: claim.b, p: claim.p)
    let root = day.whispers.count
    let node = deliver(town, to, YOU, c, NodeInfo(parent: nil, root: root, h: ph.from, r: r))
    var heard = [Heard(id: to, out: node.out)]
    for o in others where o != to && G.res[o] != nil {
      let n2 = deliver(town, o, YOU, c, NodeInfo(parent: nil, root: root, h: ph.from, r: r))
      heard.append(Heard(id: o, out: n2.out))
    }
    day.whispers.append(WhisperRec(to: to, others: others.filter { $0 != to }, c: c, node: node.id, phase: day.phase))
    town.totalWhispers += 1
    node.heard = heard
    return node
  }

  static func mutate(_ town: Town, _ t: String, _ c: Claim, _ r: Mulberry) -> (Claim, String?) {
    let R = G.res[t]!, chance = min(0.7, R.embel * 0.55 + (1 - R.memory) * 0.3)
    if r() > chance { return (c, nil) }
    var ops: [(String, Double)] = []
    if G.escalate[c.k] != nil { ops.append(("escalate", R.embel * 1.4)) }
    if c.b != nil { ops.append(("swap", (1 - R.memory) * 1.2 + 0.1)) }
    if ["praised", "apology", "gift"].contains(c.k), let v = town.aff[t]?[c.a], v < -15 { ops.append(("sour", 1.5)) }
    if c.k != "secret" && c.b != nil { ops.append(("blur", (1 - R.memory) * 0.6)) }
    if c.b != nil || c.p != nil { ops.append(("shift", (1 - R.memory) * 0.5 + (c.p != nil ? 0.3 : 0))) }
    let sum = ops.reduce(0) { $0 + $1.1 }
    if sum == 0 { return (c, nil) }
    var pick = r() * sum, op = ops[0].0
    for (o, w) in ops { pick -= w; if pick <= 0 { op = o; break } }
    var n = c
    switch op {
    case "escalate": n.k = G.escalate[c.k]!
    case "swap": n.a = c.b!; n.b = c.a
    case "sour": n.k = "badmouth"
    case "blur": n.k = "secret"
    default:
      if let p = c.p {
        let pl = ["square", "school", "bakery", "dock", "park", "cafe"].filter { $0 != p }
        n.p = pl[jsFloor(r() * Double(pl.count))]
      } else {
        let cand = G.ids.filter { $0 != c.a && $0 != c.b && $0 != t }.jsSorted { Double(town.aff[t]![$1]! - town.aff[t]![$0]!) }
        let i = jsFloor(r() * 3)
        n.b = i < cand.count ? cand[i] : nil
      }
    }
    if !G.validClaim(n) { return (c, nil) }
    return (n, op)
  }

  /// Play one part of the day (morning / afternoon / evening) and return what happened.
  public static func runPhase(_ town: Town) -> [Item] {
    let day = town.today!, ph = G.phases[day.phase]
    let r = Mulberry(js: town.seed + Double(day.day * 1013 + day.phase * 71 + day.whispers.count * 17 + town.runs * 104729))
    var out: [Item] = []
    var h = ph.from
    while h < ph.to - 1e-6 {
      var loc: [String: String] = [:]
      for id in G.ids { loc[id] = day.override?[id] ?? G.placeAt(id, h) }
      var gOrder: [String] = [], groups: [String: [String]] = [:]
      for id in G.ids { let p = loc[id]!; if groups[p] == nil { gOrder.append(p); groups[p] = [] }; groups[p]!.append(id) }
      var busy = Set<String>()
      for place in gOrder {
        let ids = groups[place]!
        if ids.count < 2 { continue }
        let order = v8RandomSort(ids, r)
        for t in order {
          if busy.contains(t) || r() > G.res[t]!.talk * 0.6 { continue }
          guard let pick = chooseRumor(town, t, r) else { continue }
          let listeners = ids.filter { $0 != t && !busy.contains($0) && !pick.told.contains($0) }
          if listeners.isEmpty { continue }
          let L = weighted(listeners.map { ($0, listenerWeight(town, t, $0, pick.c)) }, r)!
          let (c2, mut) = mutate(town, t, pick.c, r)
          let node = deliver(town, L, t, c2, NodeInfo(parent: pick.node, root: pick.root, h: h, mut: mut, gen: pick.gen + (mut != nil ? 1 : 0), r: r))
          pick.told.append(L)
          busy.insert(t); busy.insert(L)
          out.append(Item(type: "talk", h: h, place: place, t: t, l: L, c: c2, from: pick.c, mut: mut, out: node.out, node: node.id))
        }
      }
      out += checkEvents(town, loc, h)
      h += G.tickH
    }
    day.phase += 1
    if day.phase >= G.phases.count { finishDay(town) }
    return out
  }

  static func chooseRumor(_ town: Town, _ t: String, _ r: Mulberry) -> KnowEntry? {
    let items = town.today!.know[t]!.values
    if items.isEmpty { return nil }
    return weighted(items.map { e in (e, G.kinds[e.c.k]!.juicy * (e.believed ? 1 : 0.3) / (1 + Double(e.told.count) * 0.6)) }, r)
  }
  static func listenerWeight(_ town: Town, _ t: String, _ x: String, _ c: Claim) -> Double {
    var w = 1 + Double(max(0, town.aff[t]![x]!)) / 25
    let v = G.kinds[c.k]!.val
    if x == c.a && v < 0 { w *= 0.2 }
    if x == c.b && v > 0 { w *= 1.6 }
    return w
  }
  static func weighted<T>(_ pairs: [(T, Double)], _ r: Mulberry) -> T? {
    let sum = pairs.reduce(0) { $0 + $1.1 }
    if sum <= 0 { return nil }
    var x = r() * sum
    for (v, w) in pairs { x -= w; if x <= 0 { return v } }
    return pairs.last!.0
  }

  static func checkEvents(_ town: Town, _ loc: [String: String], _ h: Double) -> [Item] {
    let day = town.today!
    var evs: [Item] = []
    let together = { (a: String, b: String) in loc[a] == loc[b] }
    let has = { (f: [String], a: String, b: String) in f.contains(a) && f.contains(b) }
    for f in town.feuds {
      let a = f[0], b = f[1]
      if town.fixed.contains(where: { has($0, a, b) }) { continue }
      if town.aff[a]![b]! >= 0 && town.aff[b]![a]! >= 0 && together(a, b) {
        town.fixed.append([a, b])
        town.aff[a]![b] = clampI(town.aff[a]![b]! + 20, -100, 100); town.aff[b]![a] = clampI(town.aff[b]![a]! + 20, -100, 100)
        evs.append(Item(type: "makeup", h: h, place: loc[a]!, a: a, b: b))
      }
    }
    for a in G.ids {
      for b in G.ids {
        if a >= b || a == "kid" || b == "kid" || town.couples.contains(where: { has($0, a, b) }) { continue }
        if town.aff[a]![b]! >= 50 && town.aff[b]![a]! >= 50 && together(a, b) && romance(day, a, b) {
          town.couples.append([a, b])
          evs.append(Item(type: "date", h: h, place: loc[a]!, a: a, b: b))
        }
      }
    }
    for p in day.protestOrder {
      let ids = day.protest[p]!
      if day.protested.contains(p) || ids.count < 5 || town.cancelled.contains(p) { continue }
      day.protested.insert(p)
      var ov = day.override ?? [:]
      for id in ids { ov[id] = p }
      let subj = topSubject(day, p)
      ov[subj] = p
      day.override = ov
      evs.append(Item(type: "protest", h: h, place: p, a: subj, p: p, who: ids))
      if day.truth.contains(Claim(k: "demolish", a: subj, p: p).key) { town.cancelled.append(p) }
    }
    return evs
  }
  static func romance(_ day: Day, _ a: String, _ b: String) -> Bool {
    let love = { (k: String) in k == "likes" || k == "engaged" }
    let both = { (c: Claim) in [c.a, c.b].contains(a) && [c.a, c.b].contains(b) }
    for id in [a, b] { for e in day.know[id]!.values where love(e.c.k) && both(e.c) { return true } }
    return day.nodes.contains { love($0.c.k) && $0.out == "self" && both($0.c) }
  }
  static func topSubject(_ day: Day, _ p: String) -> String {
    var order: [String] = [], count: [String: Int] = [:]
    for k in G.ids { for e in day.know[k]!.values where e.believed && e.c.k == "demolish" && e.c.p == p {
      if count[e.c.a] == nil { order.append(e.c.a) }
      count[e.c.a, default: 0] += 1
    } }
    return order.jsSorted { Double(count[$1]! - count[$0]!) }.first ?? "mayor"
  }

  public static func goalMet(_ town: Town) -> Bool {
    let g = town.today!.goal
    switch g.type {
    case "reconcile": return town.fixed.contains { $0.contains(g.a) && $0.contains(g.b!) }
    case "date": return town.couples.contains { $0.contains(g.a) && $0.contains(g.b!) }
    case "protest": return town.today!.protested.contains(g.p!) && town.cancelled.contains(g.p!)
    default: return false
    }
  }
  public static func spreadStats(_ town: Town) -> [Spread] {
    let day = town.today!
    var reach = day.whispers.map { _ in Set<String>() }, per = day.whispers.map { _ in Spread(reach: 0, gen: 0, muts: 0) }
    for n in day.nodes where n.root < per.count {
      if n.out != "again" { reach[n.root].insert(n.listener) }
      per[n.root].gen = max(per[n.root].gen, n.gen)
      if n.mut != nil { per[n.root].muts += 1 }
    }
    for i in per.indices { per[i].reach = reach[i].count }
    return per
  }
  static func finishDay(_ town: Town) {
    let day = town.today!, st = spreadStats(town)
    let reach = max(0, st.map(\.reach).max() ?? 0), gen = max(0, st.map(\.gen).max() ?? 0)
    day.goalMet = goalMet(town)
    let stars = (day.goalMet ? 1 : 0) + (reach >= 10 ? 1 : 0) + (gen >= 3 ? 1 : 0)
    day.result = DayResult(stars: stars, reach: reach, gen: gen, goalMet: day.goalMet)
    town.stars[String(day.day)] = max(town.stars[String(day.day)] ?? 0, stars)
    town.bestReach = max(town.bestReach, reach); town.bestGen = max(town.bestGen, gen)
    day.done = true
  }
  @discardableResult
  public static func nextDay(_ town: Town) -> Day {
    for x in G.ids { for y in G.ids where x != y { town.aff[x]![y] = jsRound(Double(town.aff[x]![y]!) * 0.95) } }
    town.day += 1
    return startDay(town)
  }
}

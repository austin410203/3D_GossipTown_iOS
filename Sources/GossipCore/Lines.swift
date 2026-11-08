// Offline lines and rumour parsing — port of the web lines.js. Used when the AI (Cloudflare Worker → Claude Haiku) is not
// reachable or returns something unusable, so the game always works. Text tables come from data.json (`text`, `parse`).
import Foundation

public struct ParseResult { public var ok: Bool; public var reject: String; public var to: String?; public var claim: Claim? }
public struct Said: Codable, Equatable { public var who: String; public var text: String; public var via = "mock"
  public init(who: String, text: String, via: String = "mock") { self.who = who; self.text = text; self.via = via } }
public struct ChatResult { public var reject: String; public var rumor: Claim?; public var discussion: [Said]
  public init(reject: String, rumor: Claim?, discussion: [Said]) { self.reject = reject; self.rumor = rumor; self.discussion = discussion } }
/// What offline chat lines may use: today's mood, feelings, rumours each person believes, today's two goal people.
public struct MockCtx { public var mood: String?; public var aff: [String: [String: Int]]; public var know: [String: [Claim]]; public var focus: [String]
  public init(mood: String?, aff: [String: [String: Int]], know: [String: [Claim]], focus: [String]) { self.mood = mood; self.aff = aff; self.know = know; self.focus = focus } }

final class JSRegex {
  let re: NSRegularExpression
  init(_ o: Any?) {
    let d = o as! [String: String]
    re = try! NSRegularExpression(pattern: d["src"]!, options: d["flags"]!.contains("i") ? [.caseInsensitive] : [])
  }
  func test(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil }
  /// String.prototype.search — UTF-16 index of the first match, or -1
  func search(_ s: String) -> Int { re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))?.range.location ?? -1 }
  func match(_ s: String) -> NSTextCheckingResult? { re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) }
}

public enum Lines {
  static var G: GameData { GameData.shared }
  static func L(_ lang: String) -> String { (G.node("text", "FRAME") as? [String: Any])?[lang] != nil ? lang : "en" }
  static func pick<T>(_ arr: [T], _ seed: Int) -> T { arr[abs(seed) % arr.count] }
  static func tbl(_ name: String, _ l: String) -> [String] { (G.node("text", name) as? [String: [String]])?[l] ?? [] }
  static func tbl2(_ name: String, _ l: String) -> [String: [String]] { (G.node("text", name, l) as? [String: [String]]) ?? [:] }
  static func one(_ name: String, _ l: String) -> String { (G.node("text", name) as? [String: String])?[l] ?? "" }

  // ── parse rules (compiled once) ──
  static let alias: [String: [String]] = G.node("parse", "alias") as! [String: [String]]
  static let kw: [(String, JSRegex)] = (G.node("parse", "kw") as! [[String: String]]).map { ($0["k"]!, JSRegex(["src": $0["src"]!, "flags": $0["flags"]!])) }
  static let youRe = JSRegex(G.node("parse", "you"))
  static let toRe: [JSRegex] = (G.node("parse", "to") as! [[String: String]]).map { JSRegex($0) }
  static let block = JSRegex(G.node("parse", "block"))
  static let theRe = try! NSRegularExpression(pattern: "^(the|el|la|los|las) ", options: [])
  static let tailPunct = try! NSRegularExpression(pattern: "[。！!.？?～~]+$", options: [])

  /// One talk during playback → what the teller says and what the listener answers.
  public static func talk(_ ex: Item, _ lang: String) -> (say: String, reply: String) {
    talk(t: ex.t!, l: ex.l!, h: ex.h, c: ex.c!, out: ex.out!, mut: ex.mut, lang)
  }
  static func talk(t: String, l lis: String, h: Double, c: Claim, out: String, mut: String?, _ lang: String) -> (say: String, reply: String) {
    let l = L(lang), seed = jsHash("\(t)\(lis)\(jsNum(h))\(c.k)")
    let ct = G.claimText(c, l)
    var say = mut == "blur" || mut == "shift" ? one("UNSURE", l).replacingFirst("{c}", ct) : pick(tbl("FRAME", l), seed).replacingFirst("{c}", ct)
    if seed % 3 == 0 || t == "clock" || t == "mayor" || t == "teacher" {
      let q = ((G.node("text", "QUIRK", l) as? [String: String])?[t]) ?? "{s}"
      let ns = say as NSString
      let head = tailPunct.stringByReplacingMatches(in: say, range: NSRange(location: 0, length: ns.length), withTemplate: "")
      say = q.hasSuffix("{s}") ? q.replacingFirst("{s}", say)
        : q.replacingFirst("{s}", head + (["en", "ko", "es"].contains(l) ? ", " : "，")).replacingOccurrences(of: "  ", with: " ")
    }
    let R = tbl2("REPLY", l), pos = (G.kinds[c.k]?.val ?? 0) >= 0
    let pool: [String]
    if out == "self" { pool = pos ? R["selfPos"]! : R["selfNeg"]! }
    else if lis == c.b && out != "doubt" { pool = pos ? R["aboutMePos"]! : R["aboutMeNeg"]! }
    else { pool = R[out] ?? R["believe"]! }
    return (say, pick(pool, seed >> 3))
  }
  public static func event(_ ev: Item, _ lang: String) -> (say: String, reply: String) {
    let l = L(lang), E = tbl2("EVENT", l)
    let pair = ev.type == "protest" && ev.falsePlan == true ? E["protestFalse"]! : E[ev.type] ?? E["makeup"]!
    let pn = G.placeName(ev.p, l)
    return (pair[0].replacingOccurrences(of: "{p}", with: pn), pair[1].replacingOccurrences(of: "{p}", with: pn))
  }
  public static func headline(_ lang: String, _ whispers: [WhisperRec]) -> String {
    let l = L(lang), w = whispers.last
    return pick(tbl("HEAD", l), jsHash(whispers.map { $0.c.key }.joined(separator: ";")))
      .replacingOccurrences(of: "{n}", with: String(whispers.count)).replacingOccurrences(of: "{c}", with: w.map { G.claimText($0.c, l) } ?? "…")
  }

  // ── parse the player's words into a rumour ──
  static func findHits(_ text: String) -> [(Int, String)] {
    let t = text.lowercased() as NSString
    var hits: [(Int, String)] = []
    for id in G.ids {
      var best = -1
      for w in alias[id] ?? [] { let r = t.range(of: w); if r.location != NSNotFound && (best < 0 || r.location < best) { best = r.location } }
      if best >= 0 { hits.append((best, id)) }
    }
    return hits.jsSorted { Double($0.0 - $1.0) }
  }
  public static func findIds(_ text: String) -> [String] { findHits(text).map(\.1) }

  public static func parse(_ text: String, to toIn: String?, lang: String) -> ParseResult {
    var s = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    var to = toIn
    if s.isEmpty { return ParseResult(ok: false, reject: "unclear", to: to, claim: nil) }
    if block.test(s) { return ParseResult(ok: false, reject: "unsafe", to: to, claim: nil) }
    for re in toRe {
      if let m = re.match(s) {
        let ns = s as NSString
        let ids = findIds(ns.substring(with: m.range(at: 1)))
        if let first = ids.first { to = first; s = ns.substring(from: m.range.location + m.range.length) }
        break
      }
    }
    guard let to else { return ParseResult(ok: false, reject: "noListener", to: nil, claim: nil) }
    guard let kind = kw.first(where: { $0.1.test(s) })?.0 else { return ParseResult(ok: false, reject: "unclear", to: to, claim: nil) }
    let youAt = youRe.search(s)
    var hits = findHits(s).filter { $0.1 != to || youAt < 0 }
    if youAt >= 0 { hits.append((youAt, to)) }
    var ids: [String] = []
    for h in hits.jsSorted({ Double($0.0 - $1.0) }) where !ids.contains(h.1) { ids.append(h.1) }
    let low = s.lowercased() as NSString
    let kwAt = kind == "demolish" ? kw.first { $0.0 == "demolish" }!.1.search(low as String) : -1
    var placeHits: [(Int, String)] = []
    for p in G.places {
      for l in G.langs {
        guard let n = p.name[l] else { continue }
        let nl = n.lowercased()
        let bare = theRe.stringByReplacingMatches(in: nl, range: NSRange(location: 0, length: (nl as NSString).length), withTemplate: "")
        let r = low.range(of: bare)
        if r.location != NSNotFound { placeHits.append((r.location, p.id)) }
      }
    }
    placeHits = placeHits.jsSorted { kwAt >= 0 ? Double(abs($0.0 - kwAt) - abs($1.0 - kwAt)) : Double($0.0 - $1.0) }
    var claim = Claim(k: kind, a: ids.first ?? "", b: ids.count > 1 ? ids[1] : nil, p: placeHits.first?.1)
    if kind == "demolish" && claim.a.isEmpty { claim.a = "mayor" }
    if kind == "demolish" && claim.p == nil { claim.p = "park" }
    if !G.validClaim(claim) { return ParseResult(ok: false, reject: "unclear", to: to, claim: nil) }
    return ParseResult(ok: true, reject: "none", to: to, claim: claim)
  }

  // ── offline chat ──
  static func opinionOf(_ who: String, _ x: String, _ aff: [String: [String: Int]], _ l: String, _ seed: Int) -> String {
    let v = aff[who]?[x] ?? 0
    let pool = tbl2("OPINION", l)[v >= 30 ? "pos" : v <= -10 ? "neg" : "mid"]!
    return pick(pool, seed).replacingOccurrences(of: "{x}", with: G.nameOf(x, l))
  }
  static func topic(_ who: String, _ l: String, _ seed: Int) -> String {
    pick(((G.node("topics", who) as? [String: [String]])?[l]) ?? [""], seed)
  }
  /// A group chatting by themselves (what you overhear when you walk up).
  public static func scene(_ members: [String], _ lang: String, _ ctx: MockCtx, seed: Int) -> [Said] {
    let l = L(lang)
    var out: [Said] = []
    for (i, who) in members.enumerated() {
      let sd = jsHash("\(who)\(seed)\(i)")
      let kn = ctx.know[who]?.first
      let others = ctx.focus.filter { $0 != who }
      let text: String
      if i == 0, let m = ctx.mood, let mt = G.moods[m]?[l] { text = pick(tbl("MOODLINE", l), sd).replacingOccurrences(of: "{m}", with: mt) }
      else if let kn, sd % 2 == 0 { text = pick(tbl("RUMORLINE", l), sd).replacingOccurrences(of: "{c}", with: G.claimText(kn, l)) }
      else if !others.isEmpty && sd % 3 != 0 { text = opinionOf(who, others[abs(sd) % others.count], ctx.aff, l, sd) }
      else { text = topic(who, l, sd) }
      out.append(Said(who: who, text: text))
    }
    return Array(out.prefix(4))
  }
  /// You brought up a topic: a rumour if the words contain one, otherwise everyone gives their take.
  public static func chat(_ text: String, members: [String], lang: String, ctx: MockCtx, seed: Int) -> ChatResult {
    let l = L(lang), s = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)), to = members[0]
    if block.test(s) { return ChatResult(reject: "unsafe", rumor: nil, discussion: [Said(who: to, text: one("DEFLECT", l))]) }
    let p = parse(s, to: to, lang: lang)
    if p.ok { return ChatResult(reject: "none", rumor: p.claim, discussion: []) }
    let sd = jsHash("\(s)\(to)\(seed)"), about = findIds(s)
    var lines: [Said] = []
    for (i, who) in members.prefix(3).enumerated() {
      if let x = about.first(where: { $0 != who }) { lines.append(Said(who: who, text: opinionOf(who, x, ctx.aff, l, sd + i))); continue }
      if i == 0 { lines.append(Said(who: who, text: sd % 2 != 0 ? topic(who, l, sd) : pick(tbl("CHATBACK", l), sd))); continue }
      lines.append(Said(who: who, text: (sd + i) % 3 != 0 ? pick(tbl("AGREE", l), sd + i) : topic(who, l, sd + i)))
    }
    return ChatResult(reject: "none", rumor: nil, discussion: lines)
  }
  /// How each person present took your rumour (believing or not was decided by the rules).
  public static func reactions(_ claim: Claim, _ heard: [Heard], _ lang: String, seed: Int) -> [Said] {
    heard.prefix(4).enumerated().map { i, h in Said(who: h.id, text: talk(t: YOU, l: h.id, h: Double(seed + i), c: claim, out: h.out, mut: nil, lang).reply) }
  }
}

// Game data: residents, places, schedules, rumour kinds, all text. Loaded from GameData/data.json, which
// tools/export_native.mjs in the web repo (Gaming/GossipTown) writes from data.js / lines.js / i18n.js — the web is the source of truth.
import Foundation

public typealias L10 = [String: String]

public struct Resident {
  public let id, home, gender, age: String
  public let face: Int
  public let talk, cred, embel, memory: Double
  public let voice: [Double]
  public let name, role, note: L10
}
public struct Place { public let id: String; public let x, y: Double; public let name: L10 }
public struct Phase { public let id: String; public let from, to: Double; public let name: L10 }
public struct Kind { public let juicy: Double; public let val: Int; public let needB, needP: Bool }
public struct Claim: Codable, Equatable, Hashable {
  public var k: String, a: String, b: String?, p: String?
  public init(k: String, a: String, b: String? = nil, p: String? = nil) { self.k = k; self.a = a; self.b = b; self.p = p }
  public var key: String { "\(k)|\(a)|\(b ?? "")|\(p ?? "")" }
}
public struct Goal: Codable, Equatable {
  public var day: Int, type: String, a: String, b: String?, p: String?, who: String
  public var free: Bool
}

public final class GameData {
  public static var shared: GameData!
  public let raw: [String: Any]
  public let langs: [String]
  public let residents: [Resident]
  public let ids: [String]
  public let res: [String: Resident]
  public let places: [Place]
  public let place: [String: Place]
  public let schedule: [String: [(Double, String)]]
  public let phases: [Phase]
  public let tickH: Double
  public let kinds: [String: Kind]
  public let kindIds: [String]
  public let claimTextT: [String: L10]
  public let mutations: [String: L10]
  public let escalate: [String: String]
  public let cares: [String: [String]]
  public let caresOrder: [String]
  public let moodIds: [String]
  public let moods: [String: L10]
  public let chatLines, chatRumors: Int
  public let goals: [[String: Any]]
  public let ui: [String: L10]

  public static func load(_ url: URL) throws {
    let d = try Data(contentsOf: url)
    shared = GameData(try JSONSerialization.jsonObject(with: d) as! [String: Any])
  }

  init(_ j: [String: Any]) {
    raw = j
    langs = j["langs"] as! [String]
    func l10(_ v: Any?) -> L10 { v as? L10 ?? [:] }
    func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    residents = (j["residents"] as! [[String: Any]]).map { r in
      Resident(id: r["id"] as! String, home: r["home"] as! String, gender: r["gender"] as? String ?? "female", age: r["age"] as? String ?? "middle",
               face: (r["face"] as! NSNumber).intValue, talk: num(r["talk"]), cred: num(r["cred"]), embel: num(r["embel"]), memory: num(r["memory"]),
               voice: (r["voice"] as? [NSNumber] ?? []).map(\.doubleValue), name: l10(r["name"]), role: l10(r["role"]), note: l10(r["note"]))
    }
    ids = residents.map(\.id)
    res = Dictionary(uniqueKeysWithValues: residents.map { ($0.id, $0) })
    places = (j["places"] as! [[String: Any]]).map { Place(id: $0["id"] as! String, x: num($0["x"]), y: num($0["y"]), name: l10($0["name"])) }
    place = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    var sch: [String: [(Double, String)]] = [:]
    for (id, v) in j["schedule"] as! [String: [[Any]]] { sch[id] = v.map { (num($0[0]), $0[1] as! String) } }
    schedule = sch
    phases = (j["phases"] as! [[String: Any]]).map { Phase(id: $0["id"] as! String, from: num($0["from"]), to: num($0["to"]), name: l10($0["name"])) }
    tickH = num(j["tickH"])
    var ks: [String: Kind] = [:]
    for (k, v) in j["kinds"] as! [String: [String: Any]] {
      ks[k] = Kind(juicy: num(v["juicy"]), val: Int(num(v["val"])), needB: v["needB"] as? Bool ?? false, needP: v["needP"] as? Bool ?? false)
    }
    kinds = ks
    kindIds = j["kindIds"] as! [String]
    claimTextT = j["claimText"] as! [String: L10]
    mutations = j["mutations"] as! [String: L10]
    escalate = j["escalate"] as! [String: String]
    cares = j["cares"] as! [String: [String]]
    caresOrder = j["caresOrder"] as! [String]
    moodIds = j["moodIds"] as! [String]
    moods = j["moods"] as! [String: L10]
    chatLines = (j["chatLines"] as! NSNumber).intValue
    chatRumors = (j["chatRumors"] as! NSNumber).intValue
    goals = j["goals"] as! [[String: Any]]
    ui = j["ui"] as! [String: L10]
  }

  // ── helpers (data.js) ──
  public func placeAt(_ id: String, _ hour: Double) -> String {
    let s = schedule[id]!
    var p = s[0].1
    for (h, pl) in s where hour >= h { p = pl }
    return p
  }
  public func nameOf(_ id: String, _ lang: String) -> String { res[id].map { $0.name[lang] ?? $0.name["en"] ?? id } ?? id }
  public func fullName(_ id: String, _ lang: String) -> String {
    guard let r = res[id] else { return id }
    let n = r.name[lang] ?? r.name["en"]!, ro = r.role[lang] ?? r.role["en"]!
    switch lang {
    case "en": return "\(n) the \(ro)"
    case "zh": return "\(ro)\(n)"
    case "ja": return "\(ro)の\(n)"
    case "es": return "\(n) (\(ro))"
    default: return "\(ro) \(n)"
    }
  }
  public func placeName(_ id: String?, _ lang: String) -> String { id.flatMap { place[$0] }.map { $0.name[lang] ?? $0.name["en"] ?? "" } ?? "" }
  public func claimText(_ c: Claim, _ lang: String) -> String {
    let t = (claimTextT[lang] ?? claimTextT["en"]!)[c.k] ?? ""
    return t.replacingFirst("{a}", nameOf(c.a, lang)).replacingFirst("{b}", c.b.map { nameOf($0, lang) } ?? "").replacingFirst("{p}", placeName(c.p, lang))
  }
  public func validClaim(_ c: Claim) -> Bool {
    guard let k = kinds[c.k], res[c.a] != nil else { return false }
    if k.needB, c.b.flatMap({ res[$0] }) == nil || c.b == c.a { return false }
    if k.needP, c.p.flatMap({ place[$0] }) == nil { return false }
    return true
  }
  /// initialAffinity(rand) — aff[x][y] = how much x likes / trusts y
  func initialAffinity(_ r: Mulberry) -> [String: [String: Int]] {
    var aff: [String: [String: Int]] = [:]
    for x in ids {
      var row: [String: Int] = [:]
      for y in ids where x != y { row[y] = jsRound(5 + r() * 25) }
      aff[x] = row
    }
    aff["baker"]!["clock"] = -40; aff["clock"]!["baker"] = -45
    aff["post"]!["florist"] = 35; aff["florist"]!["post"] = 30
    for x in ids where x != "mayor" { aff[x]!["mayor"] = 50 }
    for x in ids where x != "granny" { aff[x]!["granny"] = 45 }
    for x in ids where x != "teacher" { aff[x]!["teacher"] = 40 }
    for x in ids where x != "kid" { aff[x]!["kid"] = 5 }
    aff["cafe"]!["granny"] = 60; aff["granny"]!["cafe"] = 55; aff["fisher"]!["inn"] = 50; aff["inn"]!["fisher"] = 45
    return aff
  }
  /// a text table from data.json by path, e.g. text("quests", "date", "ask", lang)
  public func node(_ path: String...) -> Any? {
    var cur: Any? = raw
    for p in path { cur = (cur as? [String: Any])?[p] }
    return cur
  }
  public func str(_ path: String..., lang: String) -> String {
    var cur: Any? = raw
    for p in path { cur = (cur as? [String: Any])?[p] }
    let m = cur as? L10
    return m?[lang] ?? m?["en"] ?? ""
  }
  public func list(_ path: String..., lang: String) -> [String] {
    var cur: Any? = raw
    for p in path { cur = (cur as? [String: Any])?[p] }
    let m = cur as? [String: [String]]
    return m?[lang] ?? m?["en"] ?? []
  }
  /// UI text with {placeholders}
  public func t(_ key: String, _ lang: String, _ p: [String: String] = [:]) -> String {
    var s = ui[lang]?[key] ?? ui["zh"]?[key] ?? key
    for (k, v) in p { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
    return s
  }
}

extension String {
  /// JS `str.replace('{a}', x)` — first occurrence only
  public func replacingFirst(_ target: String, _ with: String) -> String {
    guard let r = range(of: target) else { return self }
    return replacingCharacters(in: r, with: with)
  }
}

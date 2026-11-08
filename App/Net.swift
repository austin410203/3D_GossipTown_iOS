// The only way to the AI — port of the web llm.js. Calls the game's own Cloudflare Worker (gossip.emptyoffice.app):
// the Anthropic key lives only there (Worker secret), with per-IP and global daily caps. The app sends structured data and the
// player's words (≤120 chars); the Worker builds every prompt. Offline / locked / over the cap / any error → Lines (offline).
// The site is an internal-test build behind the lab password gate: Settings has a field for it; the app posts it to
// /__unlock exactly like the web page does and keeps the returned cookie (HTTPCookieStorage).
import Foundation
import GossipCore

@MainActor
final class Net {
  static let shared = Net()
  static let base = URL(string: "https://gossip.emptyoffice.app/")!
  enum Mode: String { case unknown, live, mock, cap, locked }
  private(set) var mode: Mode = ProcessInfo.processInfo.arguments.contains("-mock") ? .mock : .unknown
  private(set) var model = ""
  private(set) var tts = false
  private(set) var ttsEngine = ""
  var calls = 0, inTok = 0, outTok = 0, cacheRead = 0, cacheWrite = 0, fails = 0
  var onMode: ((Mode) -> Void)?
  private let forcedMock = ProcessInfo.processInfo.arguments.contains("-mock")
  let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.httpCookieStorage = .shared; c.httpShouldSetCookies = true; c.timeoutIntervalForRequest = 25
    return URLSession(configuration: c)
  }()
  private func setMode(_ m: Mode) { if m != mode { mode = m; onMode?(m) } }
  var cost: Double { Double(inTok) * 0.10e-6 + Double(outTok) * 0.50e-6 + Double(cacheRead) * 0.01e-6 + Double(cacheWrite) * 0.125e-6 }

  @discardableResult
  func status() async -> Mode {
    if forcedMock { setMode(.mock); return mode }
    var req = URLRequest(url: Net.base.appendingPathComponent("api/status")); req.cachePolicy = .reloadIgnoringLocalCacheData
    do {
      let (data, resp) = try await session.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      if code == 401 { setMode(.locked); return mode }
      let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      model = j?["model"] as? String ?? ""; tts = j?["tts"] as? Bool ?? false; ttsEngine = j?["ttsEngine"] as? String ?? ""
      setMode((j?["live"] as? Bool ?? false) ? .live : .mock)
    } catch { setMode(.mock) }
    return mode
  }
  /// the internal-test password gate (same form post as the web page); true when the cookie works
  func unlock(_ password: String) async -> Bool {
    var req = URLRequest(url: Net.base.appendingPathComponent("__unlock"))
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let pw = password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    req.httpBody = "pw=\(pw)&next=%2F".data(using: .utf8)
    _ = try? await session.data(for: req)
    return await status() == .live
  }

  private func call(_ body: [String: Any], timeout: TimeInterval = 15) async -> [String: Any]? {
    var req = URLRequest(url: Net.base.appendingPathComponent("api/llm"))
    req.httpMethod = "POST"; req.timeoutInterval = timeout
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(Prefs.shared.clientId, forHTTPHeaderField: "X-Client")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      let (data, resp) = try await session.data(for: req)
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      if code == 429 { setMode(.cap); return nil }
      if code == 503 { setMode(.mock); return nil }
      if code == 401 { setMode(.locked); return nil }
      guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { fails += 1; return nil }
      calls += 1
      if let u = j["usage"] as? [String: Any] {
        inTok += (u["input_tokens"] as? Int) ?? 0; outTok += (u["output_tokens"] as? Int) ?? 0
        cacheRead += (u["cache_read_input_tokens"] as? Int) ?? 0; cacheWrite += (u["cache_creation_input_tokens"] as? Int) ?? 0
      }
      return j
    } catch { fails += 1; return nil }
  }

  static let bad = try! NSRegularExpression(pattern: "https?:|www\\.|</?[a-z]|川普|trump|習近平|hitler|希特勒|nazi|納粹|rape|強暴|自殺|suicide", options: [.caseInsensitive])
  static func clean(_ s: Any?, _ max: Int = 140) -> String? {
    guard let s = (s as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
    if bad.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil { return nil }
    return String(s.prefix(max))
  }
  static func claimJSON(_ c: Claim) -> [String: Any] { ["k": c.k, "a": c.a, "b": c.b ?? "none", "p": c.p ?? "none"] }
  static func toClaim(_ o: Any?) -> Claim? {
    guard let d = o as? [String: Any], let k = d["k"] as? String, let a = d["a"] as? String else { return nil }
    let b = d["b"] as? String, p = d["p"] as? String
    let c = Claim(k: k, a: a, b: b == "none" ? nil : b, p: p == "none" ? nil : p)
    return GameData.shared.validClaim(c) ? c : nil
  }

  struct Member { var id: String; var know: [[String: Any]]; var feel: [[String: Any]] }
  private func membersJSON(_ m: [Member]) -> [[String: Any]] { m.map { ["id": $0.id, "know": $0.know, "feel": $0.feel] } }

  // ── the five tasks (same JSON as the web build) ──
  func quest(goal: Goal, who: String, mood: String) async -> (ask: String, story: String)? {
    guard mode == .live else { return nil }
    let j = await call(["task": "quest", "lang": LANG, "type": goal.type, "a": goal.a, "b": goal.b ?? "none", "p": goal.p ?? "none", "who": who, "mood": mood], timeout: 20)
    guard let r = j?["result"] as? [String: Any], let ask = Net.clean(r["ask"], 280) else { return nil }
    return (ask, Net.clean(r["story"], 120) ?? "")
  }
  func scene(place: String, hour: Double, mood: String, members: [Member], rumor: Claim? = nil, reactions: [Heard]? = nil, ctx: MockCtx, seed: Int) async -> [Said] {
    let ids = members.map(\.id)
    if mode == .live && (members.count >= 2 || rumor != nil) {
      var body: [String: Any] = ["task": "scene", "lang": LANG, "place": place, "hour": hour, "mood": mood, "members": membersJSON(members)]
      if let rumor, let reactions { body["rumor"] = Net.claimJSON(rumor); body["reactions"] = reactions.map { ["id": $0.id, "out": $0.out] } }
      let j = await call(body)
      let out = ((j?["result"] as? [String: Any])?["lines"] as? [[String: Any]] ?? []).compactMap { x -> Said? in
        guard let who = x["who"] as? String, ids.contains(who), let t = Net.clean(x["text"]) else { return nil }
        return Said(who: who, text: t, via: "llm")
      }
      if !out.isEmpty { return out }
    }
    if let rumor, let reactions { return Lines.reactions(rumor, reactions, LANG, seed: seed) }
    return Lines.scene(ids, LANG, ctx, seed: seed)
  }
  func chat(members: [Member], place: String, hour: Double, mood: String, history: [Said], text: String, ctx: MockCtx, seed: Int) async -> ChatResult {
    let ids = members.map(\.id)
    if mode == .live {
      let j = await call(["task": "chat", "lang": LANG, "place": place, "hour": hour, "mood": mood, "members": membersJSON(members),
                          "history": history.map { ["who": $0.who, "text": $0.text] }, "text": String(text.prefix(120))])
      if let r = j?["result"] as? [String: Any] {
        let rumor = Net.toClaim(r["rumor"])
        let disc = (r["discussion"] as? [[String: Any]] ?? []).compactMap { x -> Said? in
          guard let who = x["who"] as? String, ids.contains(who), let t = Net.clean(x["text"]) else { return nil }
          return Said(who: who, text: t, via: "llm")
        }
        if rumor != nil || !disc.isEmpty { return ChatResult(reject: r["reject"] as? String ?? "none", rumor: rumor, discussion: disc) }
      }
    }
    return Lines.chat(text, members: ids, lang: LANG, ctx: ctx, seed: seed)
  }
  struct Group { var place: String; var ids: [String] }
  /// lines for one played part of the day (+ idle groups' small talk, + the evening headline)
  func lines(items: [Item], day: Day, headline: Bool, groups: [Group], ctx: MockCtx) async -> (lines: [(say: String, reply: String)], headline: String?, chatter: [[Said]]) {
    var got: [Int: (say: String, reply: String)] = [:]
    var head: String? = nil
    var chatter: [[Said]]? = nil
    if mode == .live && (!items.isEmpty || !groups.isEmpty) {
      let send: [[String: Any]] = items.prefix(24).enumerated().map { i, e in
        e.type == "talk"
          ? ["i": i, "type": "talk", "t": e.t!, "l": e.l!, "k": e.c!.k, "a": e.c!.a, "b": e.c!.b ?? "none", "p": e.c!.p ?? "none", "mut": e.mut ?? "none", "out": e.out!, "place": e.place]
          : ["i": i, "type": e.type, "t": e.a!, "l": e.b ?? "mayor", "k": "none", "a": e.a!, "b": e.b ?? "none", "p": e.p ?? "none", "mut": "none", "out": e.falsePlan == true ? "false" : "true", "place": e.place]
      }
      var body: [String: Any] = ["task": "lines", "lang": LANG, "day": day.day, "goal": day.goal.type, "mood": day.mood,
                                 "groups": groups.map { ["place": $0.place, "ids": $0.ids] }, "items": send]
      if headline {
        body["headline"] = ["met": day.goalMet, "whispers": day.whispers.map { ["to": $0.to, "k": $0.c.k, "a": $0.c.a, "b": $0.c.b ?? "none", "p": $0.c.p ?? "none"] }]
      } else { body["headline"] = NSNull() }
      let j = await call(body, timeout: 25)
      let r = j?["result"] as? [String: Any]
      for ln in r?["lines"] as? [[String: Any]] ?? [] {
        if let i = ln["i"] as? Int, i < send.count, let s = Net.clean(ln["say"]), let rp = Net.clean(ln["reply"]) { got[i] = (say: s, reply: rp) }
      }
      head = Net.clean(r?["headline"], 80)
      if let ch = r?["chatter"] as? [[String: Any]], !ch.isEmpty {
        var c = groups.map { _ in [Said]() }
        for x in ch { if let g = x["g"] as? Int, g < c.count, let who = x["who"] as? String, let t = Net.clean(x["text"]) { c[g].append(Said(who: who, text: t, via: "llm")) } }
        chatter = c
      }
    }
    let res: [(say: String, reply: String)] = items.enumerated().map { i, e -> (say: String, reply: String) in
      if let g = got[i] { return g }
      return e.type == "talk" ? Lines.talk(e, LANG) : Lines.event(e, LANG)
    }
    let chat = groups.enumerated().map { k, g in
      if let c = chatter?[k], !c.isEmpty { return c }
      var mc = ctx; mc.know = [:]
      return Array(Lines.scene(g.ids, LANG, mc, seed: day.day * 7 + day.phase * 3 + k).prefix(3))
    }
    return (res, headline ? (head ?? Lines.headline(LANG, day.whispers)) : nil, chat)
  }
}

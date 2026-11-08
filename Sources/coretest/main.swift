// coretest golden <data.json> <golden.txt> — replay the web build's rumour engine runs and compare line by line
// coretest smoke <data.json>               — 300 random towns × 6 days, offline lines/parse, no crashes
import Foundation
import GossipCore

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "golden"
let dataPath = args.count > 2 ? args[2] : "GameData/data.json"
try! GameData.load(URL(fileURLWithPath: dataPath))
let G = GameData.shared!

func c(_ x: Claim) -> String { "\(x.k)/\(x.a)/\(x.b ?? "-")/\(x.p ?? "-")" }
func affLine(_ t: Town) -> String { G.ids.map { x in G.ids.filter { $0 != x }.map { String(t.aff[x]![$0]!) }.joined(separator: ",") }.joined(separator: ";") }

/// Same scripted play as tools/golden_native.mjs `play()` in the web repo.
func play(_ seed: Int, days: Int = 4) -> [String] {
  var log: [String] = []
  let town = Sim.newTown(seed: Double(seed))
  Sim.startDay(town)
  log.append("T \(seed) \(affLine(town))")
  for d in 1...days {
    let day = town.today!, g = day.goal
    log.append("D \(day.day) \(g.type) \(g.a) \(g.b ?? "-") \(g.p ?? "-") \(g.who) \(day.mood)")
    while !day.done {
      let ph = G.phases[day.phase]
      for w in 0..<2 {
        let k = (seed + d * 7 + day.phase * 3 + w) % 4
        var to: String, claim: Claim
        if g.type == "protest" { to = ["granny", "teacher", "cafe", "kid"][k]; claim = Claim(k: "demolish", a: g.a, p: g.p) }
        else {
          let ks = g.type == "reconcile" ? ["apology", "praised"] : ["likes", "gift"]
          to = [g.a, g.b!, "cafe", "granny"][k]
          claim = to == g.a ? Claim(k: ks[w % 2], a: g.b!, b: g.a) : Claim(k: ks[w % 2], a: g.a, b: g.b)
        }
        let others = G.ids.filter { $0 != to && G.placeAt($0, ph.from) == G.placeAt(to, ph.from) }
        let node = Sim.whisper(town, to: to, claim: claim, others: others)
        log.append("W \(to) \(c(claim)) \(node.map { $0.heard!.map { "\($0.id):\($0.out)" }.joined(separator: ",") } ?? "null")")
      }
      for e in Sim.runPhase(town) {
        if e.type == "talk" { log.append("t \(jsNum(e.h)) \(e.place) \(e.t!)>\(e.l!) \(c(e.c!)) \(e.mut ?? "-") \(e.out!) \(e.node!)") }
        else { log.append("e \(e.type) \(jsNum(e.h)) \(e.place) \(e.a!) \(e.b ?? "-") \(e.p ?? "-") \((e.who ?? []).joined(separator: ","))") }
      }
      log.append("A \(affLine(town))")
      let prot = day.protestOrder.map { "\($0):\(day.protest[$0]!.joined(separator: ","))" }.joined(separator: " ")
      log.append("P \(prot)|\(town.fixed.map { $0.joined(separator: "+") }.joined(separator: ","))|\(town.couples.map { $0.joined(separator: "+") }.joined(separator: ","))|\(town.cancelled.joined(separator: ","))")
    }
    let r = day.result!
    log.append("R \(r.stars) \(r.reach) \(r.gen) \(r.goalMet) \(day.nodes.count)")
    if d < days { Sim.nextDay(town) }
  }
  return log
}

switch cmd {
case "golden":
  let goldenPath = args.count > 3 ? args[3] : "Tests/golden.txt"
  let want = try! String(contentsOfFile: goldenPath, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  var seeds: [(Int, [String])] = []
  for l in want where l.hasPrefix("# seed ") { seeds.append((Int(l.dropFirst(7))!, [])) }
  var cur = -1
  for l in want where !l.isEmpty { if l.hasPrefix("# seed ") { cur += 1 } else { seeds[cur].1.append(l) } }
  var pass = 0
  for (seed, lines) in seeds {
    let got = play(seed)
    if got == lines { pass += 1; print("seed \(seed): OK (\(got.count) lines)"); continue }
    let i = zip(got, lines).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(got.count, lines.count)
    print("seed \(seed): DIFF at line \(i)")
    print("  want: \(i < lines.count ? String(lines[i].prefix(220)) : "<end>")")
    print("  got:  \(i < got.count ? String(got[i].prefix(220)) : "<end>")")
  }
  print("GOLDEN \(pass)/\(seeds.count) \(pass == seeds.count ? "PASS" : "FAIL")")
  exit(pass == seeds.count ? 0 : 1)
case "smoke":
  var goals = 0, n = 0
  for s in 0..<300 {
    let town = Sim.newTown(seed: Double(s * 7919 + 13))
    Sim.startDay(town)
    for _ in 0..<6 {
      let day = town.today!, g = day.goal
      while !day.done {
        let ph = G.phases[day.phase]
        let to = [g.a, g.b ?? "granny", "cafe", "teacher"][(s + day.phase) % 4]
        let others = G.ids.filter { $0 != to && G.placeAt($0, ph.from) == G.placeAt(to, ph.from) }
        let claim = g.type == "protest" ? Claim(k: "demolish", a: g.a, p: g.p) : Claim(k: g.type == "reconcile" ? "apology" : "likes", a: g.a, b: g.b)
        Sim.whisper(town, to: to, claim: claim, others: others)
        let lang = G.langs[s % G.langs.count]
        for e in Sim.runPhase(town) where e.type == "talk" { _ = Lines.talk(e, lang) }
        _ = Lines.parse(G.claimText(claim, lang), to: to, lang: lang)
      }
      goals += day.goalMet ? 1 : 0; n += 1
      Sim.nextDay(town)
    }
  }
  print("SMOKE OK days=\(n) goalMet=\(goals)")
default:
  print("usage: coretest golden|smoke <data.json> [golden.txt]")
}

// CI autopilot (`-autotest tour|store`, normally with `-mock`): plays one day through the real UI and saves screenshots to
// Documents/shots; writes done.txt at the end (CI polls for it). `-fold` gives the iPhone Duo half-folded layout.
import UIKit
import GossipCore

@MainActor
final class Autopilot {
  unowned let vc: GameVC
  let scenario: String
  private var events: [String: Int] = [:]
  private var n = 0
  init(vc: GameVC, scenario: String) { self.vc = vc; self.scenario = scenario }
  func event(_ e: String) { events[e, default: 0] += 1; NSLog("AUTOPILOT event %@", e) }

  func shot(_ name: String) {
    n += 1
    let fm = FileManager.default
    let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shots")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let w = vc.view.window else { return }
    let img = UIGraphicsImageRenderer(bounds: w.bounds).image { _ in w.drawHierarchy(in: w.bounds, afterScreenUpdates: true) }
    try? img.pngData()?.write(to: dir.appendingPathComponent(String(format: "%02d_%@.png", n, name)))
    NSLog("AUTOPILOT shot %@", name)
  }
  private func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
  /// wait until event `e` happened `count` times (or time out)
  private func until(_ e: String, _ count: Int = 1, timeout: Double = 40) async {
    var t = 0.0
    while (events[e] ?? 0) < count && t < timeout { await sleep(0.2); t += 0.2 }
  }
  private func waitIdle(_ timeout: Double = 30) async {
    var t = 0.0
    while vc.busy && t < timeout { await sleep(0.2); t += 0.2 }
  }

  func begin() {
    Prefs.shared.voice = false
    Saves.shared.delete(Prefs.shared.slot)
    vc.town = nil
    Task { await run() }
  }
  private func run() async {
    await sleep(2.5)
    vc.showTitle()
    await sleep(0.8); shot("title")
    vc.startGame()
    await until("intro"); await sleep(0.8); shot("intro")
    vc.modal.hide(); vc.plan()
    await sleep(1.5); shot("plan")
    // morning: the school group (teacher + kid) — overhear them, then drop the suggested rumour
    vc.onPick("teacher")
    await until("scene"); await waitIdle(); await sleep(1.2); shot("chat")
    if let to = vc.selected, let s = vc.suggestions(to, vc.groupAt(to)).first { await vc.sendChat(s.text, built: s.claim) }
    await waitIdle(); await sleep(1.2); shot("chat_rumor")
    if scenario == "store" { markDone(); return }
    vc.useSpot("board"); await sleep(0.8); shot("board"); vc.modal.hide()
    vc.useSpot("letter"); await sleep(0.8); shot("letter"); vc.modal.hide()
    vc.useSpot("coin"); await sleep(0.5)
    Prefs.shared.speed = 2
    let p1 = Task { await vc.play() }
    await sleep(7); shot("play")
    vc.skipping = true
    await p1.value
    await until("progress"); await sleep(0.8); shot("progress")
    vc.modal.hide(); vc.plan()
    // afternoon: a random group, a typed topic (offline parse)
    await sleep(1)
    vc.onPick("cafe")
    await waitIdle(); await sleep(0.8)
    await vc.sendChat(GameData.shared.claimText(Claim(k: "apology", a: "clock", b: "baker"), LANG))
    await waitIdle(); await sleep(1); shot("chat_typed")
    vc.skipping = true
    await vc.play()
    await until("progress", 2); vc.modal.hide(); vc.plan()
    await sleep(0.5)
    vc.skipping = true
    await vc.play()
    await until("result"); await sleep(1); shot("result")
    vc.modal.scroll.setContentOffset(CGPoint(x: 0, y: max(0, vc.modal.scroll.contentSize.height - vc.modal.scroll.bounds.height)), animated: false)
    await sleep(0.5); shot("result_tree")
    vc.modal.hide(); vc.openSettings(); await sleep(0.8); shot("settings")
    vc.openSaves(); await sleep(0.8); shot("saves")
    vc.modal.hide(); vc.nextDayTap()
    await until("intro", 2); await sleep(1); shot("day2_intro")
    NSLog("AUTOPILOT done")
    markDone()
  }
  func markDone() {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shots")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? "done".write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
  }
}

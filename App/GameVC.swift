// Main flow — port of the web game.js: title → today's request (a resident asks for help) → each part of the day (morning /
// afternoon / evening): walk up to any group, bring up a topic by voice or typing; rumours are heard by everyone present →
// the part plays out (rumours spread and mutate, idle groups chat) → progress card → evening result (stars, headline,
// rumour tree) → next day / retry. Saves automatically to the active slot.
import UIKit
import UniformTypeIdentifiers
import GossipCore

@MainActor
final class GameVC: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate {
  let G = GameData.shared!
  let townView = TownView()
  let hud = UIView()
  let dayPill = PaddedLabel("", C.paper, font: F.b(14))
  let budgetPill = PaddedLabel("", hex("#ffe3ef"), font: F.b(13))
  let menuBtn = UIButton(type: .custom)
  let goalCard = Card(radius: 16)
  let goalStack = vstack([], spacing: 4)
  let panel = Card(radius: 22, top: true)
  let panelScroll = UIScrollView()
  let panelStack = vstack([], spacing: 7)
  let dock = vstack([], spacing: 6)
  let feed = Card(radius: 14)
  let feedStack = vstack([], spacing: 4)
  let feedScroll = UIScrollView()
  let playbar = Card(radius: 22)
  let modal = ModalHost()
  let toastL = PaddedLabel("", C.ink, font: F.b(14))
  let titleHost = UIView()
  var panelBottom: NSLayoutConstraint!
  var scrollH: NSLayoutConstraint!
  var panelMaxH: NSLayoutConstraint!
  var foldH: NSLayoutConstraint!
  var feedMaxH: NSLayoutConstraint!

  var town: Town?
  var state = "title"
  var selected: String?
  var busy = false, skipping = false, playing = false, logOpen = false
  var speaking = false
  var talkToken = 0
  var input: UITextField?
  var mic: MicButton?
  var micHint: UILabel?
  /// iPhone Duo half-folded (or `-fold` on any simulator): top half = the town, bottom half = its own working area
  var fold = ProcessInfo.processInfo.arguments.contains("-fold")
  var autopilot: Autopilot?

  var day: Day { town!.today! }
  var phase: Phase { G.phases[min(day.phase, G.phases.count - 1)] }
  var hourNow: Double { phase.from }

  // ── setup ──
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = C.sky
    townView.onPick = { [weak self] id in self?.onPick(id) }
    for v in [townView, hud, panel, feed, playbar, titleHost, modal, toastL] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
    // HUD: day + time, rumours left, menu; goal card under it
    menuBtn.setImage(Art.ui("diary"), for: .normal); menuBtn.imageView?.contentMode = .scaleAspectFit
    menuBtn.backgroundColor = C.paper; menuBtn.layer.cornerRadius = 22; menuBtn.layer.borderWidth = 2; menuBtn.layer.borderColor = C.ink.cgColor
    menuBtn.imageEdgeInsets = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
    menuBtn.addTarget(self, action: #selector(openSettingsTap), for: .touchUpInside)
    menuBtn.widthAnchor.constraint(equalToConstant: 44).isActive = true; menuBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
    dayPill.layer.borderColor = C.ink.cgColor; dayPill.layer.borderWidth = 2
    let top = hstack([dayPill, budgetPill, UIView(), menuBtn], spacing: 8)
    goalStack.translatesAutoresizingMaskIntoConstraints = false
    goalCard.addSubview(goalStack)
    goalCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(goalTap)))
    let hudStack = vstack([top, goalCard], spacing: 8)
    hudStack.translatesAutoresizingMaskIntoConstraints = false
    hud.addSubview(hudStack)
    // panel (bottom sheet): scrolling content + the dock (input, mic) that always stays visible
    panelScroll.translatesAutoresizingMaskIntoConstraints = false; panelStack.translatesAutoresizingMaskIntoConstraints = false; dock.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(panelScroll); panelScroll.addSubview(panelStack); panel.addSubview(dock)
    // playback feed + speed bar
    feedScroll.translatesAutoresizingMaskIntoConstraints = false; feedStack.translatesAutoresizingMaskIntoConstraints = false
    feed.addSubview(feedScroll); feedScroll.addSubview(feedStack)
    feed.backgroundColor = C.paper.withAlphaComponent(0.94)
    toastL.isHidden = true; toastL.l.textColor = C.paper; toastL.l.textAlignment = .center
    panelBottom = panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    scrollH = panelScroll.heightAnchor.constraint(equalToConstant: 120); scrollH.priority = UILayoutPriority(999)
    panelMaxH = panel.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.5)
    foldH = panel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5)
    feedMaxH = feed.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: fold ? 0.42 : 0.22)
    let sa = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      townView.leadingAnchor.constraint(equalTo: view.leadingAnchor), townView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      townView.topAnchor.constraint(equalTo: view.topAnchor), townView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      hud.leadingAnchor.constraint(equalTo: sa.leadingAnchor, constant: 10), hud.trailingAnchor.constraint(equalTo: sa.trailingAnchor, constant: -10), hud.topAnchor.constraint(equalTo: sa.topAnchor, constant: 4),
      hudStack.leadingAnchor.constraint(equalTo: hud.leadingAnchor), hudStack.trailingAnchor.constraint(equalTo: hud.trailingAnchor),
      hudStack.topAnchor.constraint(equalTo: hud.topAnchor), hudStack.bottomAnchor.constraint(equalTo: hud.bottomAnchor),
      goalStack.leadingAnchor.constraint(equalTo: goalCard.leadingAnchor, constant: 12), goalStack.trailingAnchor.constraint(equalTo: goalCard.trailingAnchor, constant: -12),
      goalStack.topAnchor.constraint(equalTo: goalCard.topAnchor, constant: 8), goalStack.bottomAnchor.constraint(equalTo: goalCard.bottomAnchor, constant: -8),
      panel.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.trailingAnchor.constraint(equalTo: view.trailingAnchor), panelBottom, panelMaxH,
      panelScroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor), panelScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
      panelScroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10), scrollH,
      panelStack.leadingAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.leadingAnchor, constant: 14), panelStack.trailingAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.trailingAnchor, constant: -14),
      panelStack.topAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.topAnchor), panelStack.bottomAnchor.constraint(equalTo: panelScroll.contentLayoutGuide.bottomAnchor),
      panelStack.widthAnchor.constraint(equalTo: panelScroll.frameLayoutGuide.widthAnchor, constant: -28),
      dock.topAnchor.constraint(equalTo: panelScroll.bottomAnchor, constant: 6),
      dock.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14), dock.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
      dock.bottomAnchor.constraint(equalTo: sa.bottomAnchor, constant: -6),
      feed.leadingAnchor.constraint(equalTo: sa.leadingAnchor, constant: 10), feed.trailingAnchor.constraint(equalTo: sa.trailingAnchor, constant: -10),
      feed.bottomAnchor.constraint(equalTo: playbar.topAnchor, constant: -8), feedMaxH,
      feedScroll.leadingAnchor.constraint(equalTo: feed.leadingAnchor, constant: 8), feedScroll.trailingAnchor.constraint(equalTo: feed.trailingAnchor, constant: -8),
      feedScroll.topAnchor.constraint(equalTo: feed.topAnchor, constant: 6), feedScroll.bottomAnchor.constraint(equalTo: feed.bottomAnchor, constant: -6),
      feedStack.leadingAnchor.constraint(equalTo: feedScroll.contentLayoutGuide.leadingAnchor), feedStack.trailingAnchor.constraint(equalTo: feedScroll.contentLayoutGuide.trailingAnchor),
      feedStack.topAnchor.constraint(equalTo: feedScroll.contentLayoutGuide.topAnchor), feedStack.bottomAnchor.constraint(equalTo: feedScroll.contentLayoutGuide.bottomAnchor),
      feedStack.widthAnchor.constraint(equalTo: feedScroll.frameLayoutGuide.widthAnchor),
      playbar.centerXAnchor.constraint(equalTo: view.centerXAnchor), playbar.bottomAnchor.constraint(equalTo: sa.bottomAnchor, constant: -8),
      titleHost.leadingAnchor.constraint(equalTo: view.leadingAnchor), titleHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      titleHost.topAnchor.constraint(equalTo: view.topAnchor), titleHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      modal.leadingAnchor.constraint(equalTo: view.leadingAnchor), modal.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      modal.topAnchor.constraint(equalTo: view.topAnchor), modal.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      toastL.centerXAnchor.constraint(equalTo: view.centerXAnchor), toastL.topAnchor.constraint(equalTo: sa.topAnchor, constant: 70),
      toastL.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
    ])
    let feedH = feed.heightAnchor.constraint(equalToConstant: 60); feedH.priority = .defaultLow; feedH.isActive = true
    if fold { panelMaxH.isActive = false; foldH.isActive = true }
    NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    view.addGestureRecognizer({ let t = UITapGestureRecognizer(target: self, action: #selector(endEdit)); t.cancelsTouchesInView = false; return t }())
    hud.isHidden = true; panel.isHidden = true; feed.isHidden = true; playbar.isHidden = true
    setLabels()
    townView.layout(locAt(8), instant: true)
    town = Saves.shared.load()
    Net.shared.onMode = { [weak self] m in self?.updateMode(); if m == .cap { self?.toast(T("llmCap")) } }
    showTitle()
    Task { await Net.shared.status(); Voice.shared.cloud = Net.shared.tts && Net.shared.mode == .live; self.updateMode() }
    let args = ProcessInfo.processInfo.arguments
    if let i = args.firstIndex(of: "-autotest"), i + 1 < args.count { autopilot = Autopilot(vc: self, scenario: args[i + 1]); autopilot?.begin() }
  }
  override var prefersStatusBarHidden: Bool { false }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    fitMap()
  }
  /// the map sits between the HUD and whatever covers the bottom (panel / feed)
  func fitMap() {
    let top = hud.isHidden ? 0 : hud.frame.maxY + 4
    var bottom: CGFloat = 0
    if !panel.isHidden { bottom = max(bottom, view.bounds.height - panel.frame.minY) }
    if !feed.isHidden { bottom = max(bottom, view.bounds.height - feed.frame.minY) }
    townView.setInsets(top: top, bottom: bottom)
  }
  @objc func endEdit() { view.endEditing(false) }
  @objc func keyboard(_ n: Notification) {
    guard let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
    let overlap = max(0, view.bounds.maxY - view.convert(f, from: nil).minY)
    panelBottom.constant = overlap > 0 ? -(overlap - view.safeAreaInsets.bottom) : 0
    UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
  }

  // ── small helpers ──
  func save() { if let town { Saves.shared.save(town) } }
  func snapshot() {
    guard let t = town else { return }
    t.snap = try? JSONEncoder().encode(Snap(aff: t.aff, couples: t.couples, fixed: t.fixed, cancelled: t.cancelled, feuds: t.feuds, totalWhispers: t.totalWhispers))
  }
  struct Snap: Codable { var aff: [String: [String: Int]]; var couples, fixed: [[String]]; var cancelled: [String]; var feuds: [[String]]; var totalWhispers: Int }
  func locAt(_ h: Double, _ protests: [Item] = []) -> [String: String] {
    var loc: [String: String] = [:]
    for id in G.ids { loc[id] = G.placeAt(id, h) }
    for ev in protests where ev.h <= h { for id in ev.who ?? [] { loc[id] = ev.place }; if let a = ev.a { loc[a] = ev.place } }
    return loc
  }
  func marksNow() -> [String: String] {
    guard let d = town?.today else { return [:] }
    var m: [String: String] = [:]
    for id in G.ids {
      let es = d.know[id]!.values
      if es.contains(where: { $0.believed }) { m[id] = "believe" } else if !es.isEmpty { m[id] = "doubt" }
    }
    for n in d.nodes where n.out == "self" { if m[n.listener] == nil { m[n.listener] = "self" } }
    return m
  }
  func setLabels() { townView.setLabels(Dictionary(uniqueKeysWithValues: G.ids.map { ($0, nameOf($0)) })) }
  func toast(_ s: String, _ ms: Double = 2600) {
    toastL.l.text = s; toastL.isHidden = false; view.bringSubviewToFront(toastL)
    let my = UUID(); toastId = my
    Task { try? await Task.sleep(nanoseconds: UInt64(ms * 1e6)); if self.toastId == my { self.toastL.isHidden = true } }
  }
  var toastId = UUID()
  func sleep(_ ms: Double) async { if ms > 0 { try? await Task.sleep(nanoseconds: UInt64(ms * 1e6)) } }
  func dur(_ text: String, _ mul: Double = 1) -> Double { ((1200 + Double(text.count) * 55) * mul / Double(Prefs.shared.speed)).rounded() }
  func wait(_ ms: Double) async { if !skipping { await sleep(ms / Double(Prefs.shared.speed)) } }
  /// speak a line if voices are on; always leave some reading time
  func talk(_ text: String, _ who: String, _ ms: Double) async {
    if Prefs.shared.voice && !skipping {
      async let v: Void = Voice.shared.speak(text, who)
      await wait(ms * 0.6)
      await v
    } else { await wait(ms) }
  }
  func pre(_ lines: [(String, String)]) { if Prefs.shared.voice { for (t, w) in lines.prefix(8) { Voice.shared.prefetch(t, w) } } }
  func goalText(_ g: Goal) -> String {
    if !g.free, let t = (G.goals.first { ($0["day"] as? NSNumber)?.intValue == g.day }?["title"] as? [String: String]) { return t[LANG] ?? t["en"] ?? "" }
    return T(g.type == "reconcile" ? "goalReconcile" : g.type == "date" ? "goalDate" : "goalProtest", ["a": nameOf(g.a), "b": g.b.map(nameOf) ?? "", "p": placeName(g.p)])
  }
  func goalIcon(_ g: Goal) -> String { g.type == "date" ? "heart" : g.type == "protest" ? "sign" : "shake" }
  func questText(_ g: Goal, _ field: String) -> String {
    let q = (G.node("quests", g.type, field) as? [String: String]) ?? [:]
    return (q[LANG] ?? q["en"] ?? "").replacingOccurrences(of: "{a}", with: nameOf(g.a)).replacingOccurrences(of: "{b}", with: g.b.map(nameOf) ?? "")
      .replacingOccurrences(of: "{p}", with: placeName(g.p))
  }
  func fmtH(_ h: Double) -> String { String(format: "%02d:%@", Int(h), h.truncatingRemainder(dividingBy: 1) != 0 ? "30" : "00") }
  func updateMode() { if state == "title" { showTitle() } }

  // ── title ──
  func showTitle() {
    state = "title"
    hud.isHidden = true; panel.isHidden = true; feed.isHidden = true; playbar.isHidden = true
    for v in titleHost.subviews { v.removeFromSuperview() }
    titleHost.isHidden = false
    let card = Card(radius: 22)
    let logo = label(T("title"), F.round(40), C.roof, align: .center)
    let sub = label(T("sub"), F.b(13), C.ink2, align: .center)
    let tag = label(T("tagline"), F.r(15), C.ink, align: .center)
    let faces = hstack(["cafe", "granny", "baker", "clock", "florist", "post"].map { faceView($0, 44) }, spacing: 4)
    let start = Btn(town != nil ? T("cont", ["d": String(town!.day)]) : T("start"), primary: true)
    start.onTap = { [weak self] in self?.startGame() }
    let how = Btn(T("how")); how.onTap = { [weak self] in self?.howTo() }
    let saves = Btn(N("saves")); saves.setImage(Art.ui("diary").resized(18), for: .normal); saves.onTap = { [weak self] in self?.openSaves() }
    let set = Btn(T("settings")); set.onTap = { [weak self] in self?.openSettings() }
    let m = Net.shared.mode
    let mode = label(m == .live ? T("llmLive") : m == .cap ? T("llmCap") : T("llmMock"), F.b(12), m == .live ? C.ok : C.ink2, align: .center)
    let credit = label(T("credits"), F.r(11), C.ink2, align: .center)
    let st = vstack([logo, sub, tag, faces, start, hstack([how, saves], spacing: 8), set, mode, credit], spacing: 10, align: .center)
    start.widthAnchor.constraint(equalTo: st.widthAnchor).isActive = true
    st.translatesAutoresizingMaskIntoConstraints = false; card.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(st); titleHost.addSubview(card)
    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: titleHost.centerXAnchor), card.centerYAnchor.constraint(equalTo: titleHost.centerYAnchor),
      card.widthAnchor.constraint(equalTo: titleHost.widthAnchor, multiplier: 0.88), card.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
      st.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20), st.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
      st.topAnchor.constraint(equalTo: card.topAnchor, constant: 22), st.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
    ])
    view.bringSubviewToFront(modal); view.bringSubviewToFront(toastL)
  }
  func howTo() {
    let close = Btn(T("close"), primary: true); close.onTap = { [weak self] in self?.modal.hide() }
    var hv: [UIView] = [label(T("how"), F.b(20))]
    for p in T("howText").split(separator: "\n") { hv.append(label(String(p), F.r(15))) }
    hv.append(buttonRow([close]))
    modal.show(hv)
  }

  // ── start / each day ──
  func startGame() {
    Voice.shared.hush()
    if town == nil { town = Sim.newTown(); Sim.startDay(town!); snapshot(); save() }
    else if town!.today == nil { Sim.startDay(town!); snapshot(); save() }
    titleHost.isHidden = true
    hud.isHidden = false
    setLabels()
    if day.done { showResult(); return }
    Task { await dayIntro() }
  }
  func questWho(_ g: Goal) -> String { g.who.isEmpty ? "granny" : g.who }
  func dayIntro() async {
    let d = day, g = d.goal, who = questWho(g)
    hudUpdate()
    if d.quest == nil || d.quest!.lang != LANG {
      modal.show([label(T("day", ["d": String(d.day)]), F.b(13), C.roof), hstack([faceView(who, 56), vstack([label(T("askFrom", ["who": fullName(who)]), F.r(12), C.ink2), label("…", F.r(16))], spacing: 2)], spacing: 10)])
      townView.focus([who])
      let q = await Net.shared.quest(goal: g, who: who, mood: d.mood)
      guard town?.today === d else { return }
      let story = (G.goals.first { ($0["day"] as? NSNumber)?.intValue == g.day && !g.free }?["story"] as? [String: String]).map { $0[LANG] ?? $0["en"] ?? "" } ?? ""
      d.quest = Quest(lang: LANG, ask: q?.ask ?? questText(g, "ask"), story: q?.story ?? story, via: q != nil ? "llm" : "template")
      save()
    }
    let ask = d.quest!.ask
    var views: [UIView] = [label(T("day", ["d": String(d.day)]), F.b(13), C.roof)]
    let say = PaddedLabel(ask, .white, font: F.r(16))
    views.append(hstack([faceView(who, 56), vstack([label(T("askFrom", ["who": fullName(who)]), F.r(12), C.ink2), say], spacing: 3)], spacing: 10, align: .top))
    let title = label("", F.b(19)); title.attributedText = iconText(goalIcon(g), goalText(g), font: F.b(19))
    views.append(title)
    if !d.quest!.story.isEmpty { views.append(label(d.quest!.story, F.r(14), C.ink2)) }
    var pair: [UIView] = [g.a, g.b].compactMap { $0 }.map { id in vstack([faceView(id, 52), label(fullName(id), F.b(12), align: .center)], spacing: 3, align: .center) }
    if let p = g.p { pair.append(PaddedLabel(placeName(p), C.tut, font: F.b(14))) }
    views.append(hstack([UIView()] + pair + [UIView()], spacing: 16))
    let hint = PaddedLabel("", C.tut, font: F.r(14)); hint.l.attributedText = iconText("board", T("hintLabel") + "  " + questText(g, "hint"), font: F.r(14))
    views.append(hint)
    let go = Btn(T("accept"), primary: true)
    go.onTap = { [weak self] in self?.modal.hide(); Voice.shared.hush(); self?.plan() }
    views.append(buttonRow([go]))
    modal.show(views)
    townView.focus([who]); townView.say(who, ask, ms: 6000)
    if Prefs.shared.voice { Task { await Voice.shared.speak(ask, who) } }
    autopilot?.event("intro")
  }

  // ── planning: walk up to a group ──
  func plan() {
    state = "plan"; selected = nil; busy = false
    townView.layout(locAt(phase.from), instant: false)
    townView.setMarks(marksNow()); townView.select(nil)
    feed.isHidden = true; playbar.isHidden = true
    hudUpdate(); panelPick()
  }
  func hudUpdate() {
    guard let d = town?.today else { return }
    let g = d.goal
    dayPill.l.text = T("day", ["d": String(d.day)]) + "  " + (d.done ? T("dayEnd") : "\(G.phases[d.phase].name[LANG] ?? "") \(fmtH(G.phases[d.phase].from))")
    budgetPill.l.attributedText = iconText("gossip", d.done ? "0" : T("budget", ["n": String(linesLeft), "m": String(rumorsLeft)]), font: F.b(13), color: hex("#9b2f5a"))
    for v in goalStack.arrangedSubviews { goalStack.removeArrangedSubview(v); v.removeFromSuperview() }
    let t = label("", F.b(15)); t.attributedText = iconText(goalIcon(g), goalText(g), font: F.b(15))
    goalStack.addArrangedSubview(t); goalStack.addArrangedSubview(goalMeterView(town!))
    view.setNeedsLayout()
  }
  @objc func goalTap() {
    guard state == "plan" || state == "play", town?.today != nil else { return }
    let g = day.goal
    let close = Btn(T("close"), primary: true); close.onTap = { [weak self] in self?.modal.hide() }
    let hint = PaddedLabel(T("hintLabel") + "  " + questText(g, "hint"), C.tut, font: F.r(14))
    let t = label("", F.b(19)); t.attributedText = iconText(goalIcon(g), goalText(g), font: F.b(19))
    modal.show([t, goalMeterView(town!), hint, buttonRow([close])])
  }

  // chat budget for the current part of the day
  func chatState() -> ChatState {
    if day.chat == nil || day.chat!.phase != day.phase { day.chat = ChatState(); day.chat!.phase = day.phase }
    return day.chat!
  }
  func mutateChat(_ f: (inout ChatState) -> Void) { var c = chatState(); f(&c); day.chat = c }
  var linesLeft: Int { max(0, G.chatLines - chatState().said) }
  var rumorsLeft: Int { let c = chatState(); return max(0, G.chatRumors + c.bonus - c.rumors) }
  func groupAt(_ id: String) -> [String] { let loc = locAt(hourNow); return G.ids.filter { loc[$0] == loc[id] } }
  func knowOf(_ id: String, _ n: Int = 5) -> [[String: Any]] {
    day.know[id]!.values.suffix(n).map { ["k": $0.c.k, "a": $0.c.a, "b": $0.c.b ?? "none", "p": $0.c.p ?? "none", "bel": $0.believed] }
  }
  func feelOf(_ id: String) -> [[String: Any]] {
    let g = day.goal, A = town!.aff
    let strong = G.ids.filter { $0 != id }.sorted { abs(A[id]![$0]!) > abs(A[id]![$1]!) }
    var out: [String] = []
    for x in [g.a, g.b].compactMap({ $0 }).filter({ $0 != id }) + strong.prefix(2) where !out.contains(x) { out.append(x) }
    return out.prefix(4).map { ["id": $0, "v": A[id]![$0]!] }
  }
  func mockCtx() -> MockCtx {
    var know: [String: [Claim]] = [:]
    for id in G.ids { know[id] = day.know[id]!.values.filter(\.believed).map(\.c) }
    return MockCtx(mood: day.mood, aff: town!.aff, know: know, focus: [day.goal.a, day.goal.b].compactMap { $0 })
  }
  var chatSeed: Int { day.day * 101 + day.phase * 17 + chatState().said * 7 + town!.runs }
  func members(_ ids: [String]) -> [Net.Member] { ids.map { Net.Member(id: $0, know: knowOf($0, 3), feel: Array(feelOf($0).prefix(3))) } }

  // ── map objects: notice board (where everyone will be), unsigned letter (whom the goal person listens to), fountain coin (+1 rumour) ──
  let spotList: [(String, CGFloat, CGFloat)] = [("board", 0.40, 0.50), ("letter", 0.615, 0.40), ("coin", 0.465, 0.55)]
  func updateSpots() {
    let on = state == "plan" && !(town?.today?.done ?? true)
    townView.setSpots(on ? spotList.map { TownView.Spot(id: $0.0, x: $0.1, y: $0.2, used: day.spots.contains($0.0)) } : [])
  }
  func useSpot(_ id: String) {
    let d = day, g = d.goal
    if d.spots.contains(id) { toast(T("spotUsed")); return }
    let ok = Btn(T("ok"), primary: true); ok.onTap = { [weak self] in self?.modal.hide() }
    if id == "board" {
      guard d.phase + 1 < G.phases.count else { toast(T("boardLast")); return }
      let n = G.phases[d.phase + 1], loc = locAt(n.from)
      var order: [String] = [], by: [String: [String]] = [:]
      for x in G.ids { let p = loc[x]!; if by[p] == nil { order.append(p) }; by[p, default: []].append(x) }
      let rows = order.map { p -> UIView in
        let people = hstack(by[p]!.map { x in hstack([faceView(x, 20), label(nameOf(x), F.r(13))], spacing: 2) }, spacing: 6)
        let sc = UIScrollView(); sc.showsHorizontalScrollIndicator = false; sc.addSubview(people); people.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([people.leadingAnchor.constraint(equalTo: sc.contentLayoutGuide.leadingAnchor), people.trailingAnchor.constraint(equalTo: sc.contentLayoutGuide.trailingAnchor),
                                     people.topAnchor.constraint(equalTo: sc.contentLayoutGuide.topAnchor), people.bottomAnchor.constraint(equalTo: sc.contentLayoutGuide.bottomAnchor),
                                     people.heightAnchor.constraint(equalTo: sc.frameLayoutGuide.heightAnchor), sc.heightAnchor.constraint(equalToConstant: 26)])
        let name = label(placeName(p), F.b(13)); name.widthAnchor.constraint(equalToConstant: 92).isActive = true
        return hstack([name, sc], spacing: 6)
      }
      let t = label("", F.b(17)); t.attributedText = iconText("board", T("boardTitle", ["p": n.name[LANG] ?? ""]), font: F.b(17), size: 30)
      var bv: [UIView] = [t]
      bv += rows; bv.append(buttonRow([ok]))
      modal.show(bv)
    } else if id == "letter" {
      let who = g.type == "protest" ? "mayor" : g.b!
      let best = G.ids.filter { $0 != who && $0 != g.a && $0 != g.b }.sorted { town!.aff[who]![$0]! > town!.aff[who]![$1]! }[0]
      let t = label("", F.b(17)); t.attributedText = iconText("letter", T("letterTitle"), font: F.b(17), size: 30)
      let body = PaddedLabel(T("letterText", ["a": nameOf(who), "b": nameOf(best)]), hex("#fff8e6"), font: F.b(18)); body.l.textAlignment = .center
      modal.show([t, body, label(T("letterHint", ["a": nameOf(who), "b": nameOf(best), "p": placeName(locAt(hourNow)[best])]), F.r(13), C.ink2), buttonRow([ok])])
    } else if id == "coin" {
      mutateChat { $0.bonus += 1 }
      Haptic.rumor()
      toast(T("coinText"), 3200)
    }
    d.spots.insert(id); save(); updateSpots(); hudUpdate()
    if selected != nil { renderChat() }
  }

  func setPanel(_ content: [UIView], dock dockViews: [UIView]) {
    for v in panelStack.arrangedSubviews { panelStack.removeArrangedSubview(v); v.removeFromSuperview() }
    for v in dock.arrangedSubviews { dock.removeArrangedSubview(v); v.removeFromSuperview() }
    for v in content { panelStack.addArrangedSubview(v) }
    for v in dockViews { dock.addArrangedSubview(v) }
    panel.isHidden = false
    view.layoutIfNeeded()
    scrollH.constant = panelStack.systemLayoutSizeFitting(CGSize(width: panelScroll.bounds.width - 28, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    view.layoutIfNeeded()
    fitMap()
  }
  func panelPick() {
    let d = day, ph = G.phases[d.phase], locNow = locAt(ph.from)
    updateSpots()
    var content: [UIView] = [label(T("pickWho"), F.b(16))]
    if d.day == 1 && d.phase == 0 && d.whispers.isEmpty { content.append(PaddedLabel(T("tutorial1") + " " + T("spotHint"), C.tut, font: F.r(13))) }
    let strip = hstack(G.ids.map { id -> UIView in
      let b = UIButton(type: .custom)
      let col = vstack([faceView(id, 50), label(nameOf(id), F.b(13), align: .center), label(placeName(locNow[id]), F.r(11), C.ink2, align: .center)], spacing: 1, align: .center)
      col.isUserInteractionEnabled = false; col.translatesAutoresizingMaskIntoConstraints = false
      b.addSubview(col)
      NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: b.leadingAnchor), col.trailingAnchor.constraint(equalTo: b.trailingAnchor),
                                   col.topAnchor.constraint(equalTo: b.topAnchor), col.bottomAnchor.constraint(equalTo: b.bottomAnchor), b.widthAnchor.constraint(equalToConstant: 66)])
      b.addAction(UIAction { [weak self] _ in self?.onPick(id) }, for: .touchUpInside)
      return b
    }, spacing: 6, align: .top)
    let sc = UIScrollView(); sc.showsHorizontalScrollIndicator = false; sc.addSubview(strip); strip.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([strip.leadingAnchor.constraint(equalTo: sc.contentLayoutGuide.leadingAnchor), strip.trailingAnchor.constraint(equalTo: sc.contentLayoutGuide.trailingAnchor),
                                 strip.topAnchor.constraint(equalTo: sc.contentLayoutGuide.topAnchor), strip.bottomAnchor.constraint(equalTo: sc.contentLayoutGuide.bottomAnchor),
                                 strip.heightAnchor.constraint(equalTo: sc.frameLayoutGuide.heightAnchor), sc.heightAnchor.constraint(equalToConstant: 92)])
    content.append(sc)
    let rnd = Btn(T("randomChat")); rnd.onTap = { [weak self] in self?.randomChat() }
    let run = Btn(T("runPhase", ["p": ph.name[LANG] ?? ""]), primary: linesLeft < G.chatLines); run.onTap = { [weak self] in Task { await self?.play() } }
    setPanel(content, dock: [buttonRow([rnd, run])])
  }
  func randomChat() {
    let loc = locAt(hourNow), cs = chatState()
    var order: [String] = [], groups: [String: [String]] = [:]
    for id in G.ids { let p = loc[id]!; if groups[p] == nil { order.append(p) }; groups[p, default: []].append(id) }
    let list = order.enumerated().sorted { x, y in
      let a = cs.scened.contains(x.element) ? 1 : 0, b = cs.scened.contains(y.element) ? 1 : 0
      if a != b { return a < b }
      let la = groups[x.element]!.count, lb = groups[y.element]!.count
      return la != lb ? la > lb : x.offset < y.offset
    }.map(\.element)
    let top = list.filter { !cs.scened.contains($0) && groups[$0]!.count >= 2 }
    let pool = top.isEmpty ? list : top
    let g = groups[pool[Int.random(in: 0..<min(3, pool.count))]]!
    onPick(g[Int.random(in: 0..<g.count)])
  }
  func onPick(_ id: String) {
    guard state == "plan", !busy else { return }
    if id.hasPrefix("spot:") { useSpot(String(id.dropFirst(5))); return }
    selected = id
    stopTalking()
    townView.select(id, dim: true)
    Task { await openChat() }
  }
  func openChat() async {
    guard let id = selected else { return }
    let grp = groupAt(id), place = locAt(hourNow)[id]!
    if chatState().logs[place] == nil { mutateChat { $0.logs[place] = [] } }
    renderChat()
    if grp.count >= 2 && !chatState().scened.contains(place) {
      mutateChat { $0.scened.insert(place) }
      busy = true; renderChat()
      let lines = await Net.shared.scene(place: place, hour: hourNow, mood: day.mood, members: members(Array(grp.prefix(4))), ctx: mockCtx(), seed: chatSeed)
      mutateChat { c in for ln in lines { c.logs[place, default: []].append(ChatRow(who: ln.who, text: ln.text)) } }
      busy = false; save()
      if selected == id { renderChat() }
      Task { await speakLines(lines, kind: "chat") }
      autopilot?.event("scene")
    }
  }
  func stopTalking() { talkToken += 1; speaking = false; Voice.shared.hush() }
  func speakLines(_ lines: [Said], kind: String, first: String? = nil) async {
    talkToken += 1
    let my = talkToken
    pre(lines.map { ($0.text, $0.who) })
    speaking = Prefs.shared.voice
    if state == "plan" && selected != nil { renderChat() }
    for ln in lines {
      if my != talkToken || state != "plan" { break }
      townView.clearTalk(); townView.focus([ln.who]); townView.say(ln.who, ln.text, ms: dur(ln.text, 1.8), kind: ln.who == first ? "reply" : kind)
      await talk(ln.text, ln.who, dur(ln.text) * 0.8)
    }
    if my == talkToken { speaking = false; if state == "plan" && selected != nil { renderChat() } }
  }

  // ── suggested topics (built by the rules from today's goal; rumours go in the fixed format, no AI parsing) ──
  struct Sugg { var text: String; var claim: Claim?; var preview: String }
  func suggestions(_ to: String, _ grp: [String]) -> [Sugg] {
    let g = day.goal
    var out: [Sugg] = []
    func chip(_ k: String, _ a: String, _ b: String?, _ p: String?) -> Sugg {
      let claim = Claim(k: k, a: a, b: b, p: p)
      let you = (G.node("youText", LANG) as? [String: String])?[k]
      let text = b != nil && b == to && you != nil ? you!.replacingOccurrences(of: "{a}", with: nameOf(a)) : G.claimText(claim, LANG)
      var preview: String
      if k == "demolish" { preview = T("previewProtest", ["p": placeName(p)]) }
      else if let b, grp.contains(b) {
        let e = (G.node("effectPreview", k) as? [NSNumber])?.map(\.intValue) ?? [0, 0]
        let n = town!.aff[b]![a]! < 0 ? e[0] : e[1]
        preview = T("previewIf", ["x": nameOf(b), "y": nameOf(a), "n": (n > 0 ? "+" : "") + String(n)])
      } else { preview = T("previewSpread") }
      return Sugg(text: text, claim: claim, preview: preview)
    }
    if rumorsLeft > 0 {
      if g.type == "protest" { out.append(chip("demolish", g.a, nil, g.p)) }
      else {
        let ks = g.type == "reconcile" ? ["apology", "praised"] : ["likes", "gift"]
        let toB = grp.contains(g.b!), toA = grp.contains(g.a)
        if toA { out.append(chip(ks[0], g.b!, g.a, nil)) }
        if toB { out.append(chip(ks[0], g.a, g.b, nil)) }
        if !toA && !toB { out.append(chip(ks[0], g.a, g.b, nil)); out.append(chip(ks[1], g.b!, g.a, nil)) }
        else if out.count < 2 { out.append(chip(ks[1], toA ? g.b! : g.a, toA ? g.a : g.b, nil)) }
      }
    }
    let x = [g.a, g.b].compactMap { $0 }.first { !grp.contains($0) } ?? g.a
    out.append(Sugg(text: ((G.node("askOpinion") as? [String: String])?[LANG] ?? "").replacingOccurrences(of: "{x}", with: nameOf(x)), claim: nil, preview: ""))
    let heard = { (c: Claim) in grp.contains { self.day.know[$0]![c.key]?.tellers.contains(YOU) ?? false } }
    return Array(out.filter { $0.claim == nil || !heard($0.claim!) }.prefix(3))
  }
  func goalSnap() -> (ab: Int, ba: Int, prot: Int) {
    let g = day.goal
    if g.type == "protest" { return (0, 0, (day.protest[g.p!] ?? []).count) }
    return (town!.aff[g.a]![g.b!]!, town!.aff[g.b!]![g.a]!, 0)
  }
  func goalDiff(_ before: (ab: Int, ba: Int, prot: Int)) -> [String] {
    let g = day.goal, now = goalSnap()
    if g.type == "protest" { return now.prot != before.prot ? [T("believersLine", ["p": placeName(g.p), "x": String(before.prot), "y": String(now.prot)])] : [] }
    var out: [String] = []
    if now.ab != before.ab { out.append(T("effectAfter", ["a": nameOf(g.a), "b": nameOf(g.b!), "x": String(before.ab), "y": String(now.ab)])) }
    if now.ba != before.ba { out.append(T("effectAfter", ["a": nameOf(g.b!), "b": nameOf(g.a), "x": String(before.ba), "y": String(now.ba)])) }
    return out
  }

  // ── the chat panel ──
  func renderChat() {
    guard let id = selected, state == "plan" else { return }
    let d = day, grp = groupAt(id), place = locAt(hourNow)[id]!, cs = chatState()
    let log = cs.logs[place] ?? []
    let can = linesLeft > 0
    // header: faces (tap to switch who answers first), place, close
    let faces = hstack(grp.map { x -> UIView in
      let b = UIButton(type: .custom)
      let col = vstack([faceView(x, x == id ? 38 : 32), label(nameOf(x), F.b(11), align: .center)], spacing: 0, align: .center)
      col.isUserInteractionEnabled = false; col.translatesAutoresizingMaskIntoConstraints = false
      b.addSubview(col)
      NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: b.leadingAnchor), col.trailingAnchor.constraint(equalTo: b.trailingAnchor),
                                   col.topAnchor.constraint(equalTo: b.topAnchor), col.bottomAnchor.constraint(equalTo: b.bottomAnchor)])
      if x == id { b.backgroundColor = hex("#ffe9a8"); b.layer.cornerRadius = 10 }
      b.addAction(UIAction { [weak self] _ in guard let self, !self.busy else { return }; self.selected = x; self.townView.select(x, dim: true); self.renderChat() }, for: .touchUpInside)
      return b
    }, spacing: 4, align: .top)
    let close = UIButton(type: .custom); close.setImage(Art.ui("close"), for: .normal); close.imageView?.contentMode = .scaleAspectFit
    close.widthAnchor.constraint(equalToConstant: 34).isActive = true; close.heightAnchor.constraint(equalToConstant: 34).isActive = true
    close.addAction(UIAction { [weak self] _ in guard let self, !self.busy else { return }; self.selected = nil; self.townView.select(nil); self.panelPick() }, for: .touchUpInside)
    let where_ = vstack([label(placeName(place), F.b(16)), label(T("talkingTo", ["who": nameOf(id)]), F.r(11), C.ink2, lines: 2)], spacing: 1)
    var content: [UIView] = [hstack([faces, where_, close], spacing: 8)]
    // log: last two lines, tap to see all
    var rows: [UIView] = []
    if log.count > 2 {
      let tog = UIButton(type: .system); tog.setTitle(logOpen ? T("logLess") : T("logMore", ["n": String(log.count - 2)]), for: .normal)
      tog.titleLabel?.font = F.b(12); tog.setTitleColor(C.ink2, for: .normal)
      tog.addAction(UIAction { [weak self] _ in self?.logOpen.toggle(); self?.renderChat() }, for: .touchUpInside)
      rows.append(tog)
    }
    let shown = logOpen ? log : Array(log.suffix(2))
    rows += shown.map(chatRowView)
    if shown.isEmpty { rows.append(label(grp.count > 1 ? "…" : T("alone", ["who": nameOf(id)]), F.r(13), C.ink2)) }
    if busy { rows.append(label(T("thinking", ["who": nameOf(id)]), F.r(13), C.ink2)) }
    let logBox = vstack(rows, spacing: 6)
    logBox.isLayoutMarginsRelativeArrangement = true; logBox.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
    logBox.backgroundColor = C.log; logBox.layer.cornerRadius = 12
    content.append(logBox)
    if d.day == 1 && d.phase == 0 && d.whispers.isEmpty { content.append(PaddedLabel(T("tutorial2"), C.tut, font: F.r(13))) }
    if !busy && can {
      let s = suggestions(id, grp)
      let chips = hstack(s.map { x -> UIView in
        let b = UIButton(type: .custom)
        let t = label(x.text, F.b(13), lines: 2); let p = label(x.preview, F.r(11), hex("#2e7d32"))
        let col = vstack(x.preview.isEmpty ? [t] : [t, p], spacing: 1)
        col.isUserInteractionEnabled = false; col.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(col)
        NSLayoutConstraint.activate([col.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 10), col.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -10),
                                     col.topAnchor.constraint(equalTo: b.topAnchor, constant: 6), col.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -6),
                                     b.widthAnchor.constraint(lessThanOrEqualToConstant: 240)])
        b.backgroundColor = x.claim != nil ? hex("#fff0f5") : .white; b.layer.cornerRadius = 12; b.layer.borderWidth = 1.5
        b.layer.borderColor = (x.claim != nil ? hex("#f3a9c4") : hex("#e0d2b6")).cgColor
        b.addAction(UIAction { [weak self] _ in guard let self, !self.busy else { return }; Task { await self.sendChat(x.text, built: x.claim) } }, for: .touchUpInside)
        return b
      }, spacing: 6, align: .top)
      let sc = UIScrollView(); sc.showsHorizontalScrollIndicator = false; sc.addSubview(chips); chips.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([chips.leadingAnchor.constraint(equalTo: sc.contentLayoutGuide.leadingAnchor), chips.trailingAnchor.constraint(equalTo: sc.contentLayoutGuide.trailingAnchor),
                                   chips.topAnchor.constraint(equalTo: sc.contentLayoutGuide.topAnchor), chips.bottomAnchor.constraint(equalTo: sc.contentLayoutGuide.bottomAnchor),
                                   chips.heightAnchor.constraint(equalTo: sc.frameLayoutGuide.heightAnchor), sc.heightAnchor.constraint(equalToConstant: 58)])
      content.append(sc)
    }
    // dock: input + say, then [random] (mic) [start]
    let rnd = Btn(T("randomShort"), small: true); rnd.onTap = { [weak self] in guard let self, !self.busy else { return }; self.randomChat() }
    let run = Btn(T("runPhase", ["p": G.phases[d.phase].name[LANG] ?? ""]), primary: !can, small: true)
    run.onTap = { [weak self] in guard let self, !self.busy else { return }; Task { await self.play() } }
    var dockViews: [UIView] = []
    if can {
      let tf = UITextField()
      tf.placeholder = T("placeholder"); tf.font = F.r(16); tf.borderStyle = .none; tf.backgroundColor = .white
      tf.layer.borderColor = C.ink.cgColor; tf.layer.borderWidth = 2; tf.layer.cornerRadius = 22; tf.returnKeyType = .send; tf.delegate = self
      tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 10)); tf.leftViewMode = .always
      tf.heightAnchor.constraint(equalToConstant: 44).isActive = true
      tf.isEnabled = !busy
      if let old = input?.text, input?.superview != nil, !old.isEmpty { tf.text = old }
      input = tf
      let send = Btn(T("send"), primary: true); send.isEnabled = !busy
      send.onTap = { [weak self] in guard let self else { return }; Task { await self.sendChat(self.input?.text ?? "") } }
      dockViews.append(hstack([tf, send], spacing: 8))
      let m = MicButton(); m.isEnabled = !busy; mic = m
      m.addAction(UIAction { [weak self] _ in self?.micTap() }, for: .touchUpInside)
      let hint: UIView
      if speaking {
        let b = UIButton(type: .system); b.setTitle(T("skipVoice"), for: .normal); b.titleLabel?.font = F.b(12); b.setTitleColor(C.ink2, for: .normal)
        b.addAction(UIAction { [weak self] _ in self?.stopTalking(); self?.renderChat() }, for: .touchUpInside)
        hint = b; micHint = nil
      } else { let l = label(T("listen"), F.b(12), C.ink2, align: .center); micHint = l; hint = l }
      let mcol = vstack([m, hint], spacing: 2, align: .center)
      let bar = UIStackView(arrangedSubviews: [rnd, mcol, run]); bar.axis = .horizontal; bar.distribution = .equalCentering; bar.alignment = .center
      dockViews.append(bar)
    } else {
      content.append(label(T("noLines", ["p": G.phases[d.phase].name[LANG] ?? ""]), F.r(13), C.ink2))
      dockViews.append(buttonRow([rnd, run]))
    }
    setPanel(content, dock: dockViews)
    panelScroll.layoutIfNeeded()
    let bottom = CGPoint(x: 0, y: max(0, panelScroll.contentSize.height - panelScroll.bounds.height))
    panelScroll.setContentOffset(bottom, animated: false)
  }
  func textFieldShouldReturn(_ tf: UITextField) -> Bool { let t = tf.text ?? ""; Task { await sendChat(t) }; return true }
  func micTap() {
    guard let mic else { return }
    if mic.recording { Voice.shared.stop(); return }
    mic.recording = true
    input?.placeholder = T("listening"); micHint?.text = T("listening")
    Voice.shared.listen(
      onText: { [weak self] s in self?.input?.text = s },
      // never sent automatically: the text goes into the box, the player may edit it and taps Say
      onFinal: { [weak self] s in self?.input?.text = s; self?.micHint?.text = T("editThenSend"); self?.toast(T("editThenSend")) },
      onEnd: { [weak self] in self?.mic?.recording = false; self?.input?.placeholder = T("placeholder"); if (self?.input?.text ?? "").isEmpty { self?.micHint?.text = T("listen") } },
      onError: { [weak self] e in self?.mic?.recording = false; self?.toast(e == "not-allowed" ? N("micDenied") : T("micNA")) })
  }

  /// you bring up a topic (typed, spoken, or a suggestion chip)
  func sendChat(_ raw: String, built: Claim? = nil) async {
    let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    guard !text.isEmpty, state == "plan", !busy, let to = selected, linesLeft > 0 else { return }
    view.endEditing(false)
    let d = day, place = locAt(hourNow)[to]!
    let grp = Array(([to] + groupAt(to).filter { $0 != to }).prefix(4))
    let mem = members(grp)
    let history = (chatState().logs[place] ?? []).compactMap { r -> Said? in r.who.map { Said(who: $0, text: r.text ?? "") } }.suffix(6)
    mutateChat { $0.logs[place, default: []].append(ChatRow(who: YOU, text: text)); $0.said += 1 }
    input?.text = ""
    stopTalking()
    busy = true; renderChat()
    townView.say(to, "「\(text)」", ms: 2200, kind: "whisper")
    let res = built != nil ? ChatResult(reject: "none", rumor: built, discussion: [])
      : await Net.shared.chat(members: mem, place: place, hour: hourNow, mood: d.mood, history: Array(history), text: text, ctx: mockCtx(), seed: chatSeed)
    var lines = res.discussion
    if res.reject == "unsafe" { mutateChat { $0.logs[place, default: []].append(ChatRow(note: T("reject_unsafe", ["who": nameOf(to)]))) } }
    else if let rumor = res.rumor {
      if rumorsLeft > 0 {
        let before = goalSnap()
        if let node = Sim.whisper(town!, to: to, claim: rumor, others: grp.filter { $0 != to }) {
          mutateChat { $0.rumors += 1 }
          let heard = node.heard ?? [Heard(id: to, out: node.out)]
          mutateChat { $0.logs[place, default: []].append(ChatRow(chip: G.claimText(rumor, LANG), heard: heard, eff: goalDiff(before))) }
          Haptic.rumor()
          townView.setMarks(marksNow())
          renderChat()
          lines = await Net.shared.scene(place: place, hour: hourNow, mood: d.mood, members: mem, rumor: rumor, reactions: heard, ctx: mockCtx(), seed: chatSeed)
        }
      } else { lines = [Said(who: to, text: T("rumorLimit"))] }
    }
    mutateChat { c in for ln in lines { c.logs[place, default: []].append(ChatRow(who: ln.who, text: ln.text)) } }
    busy = false
    save(); hudUpdate()
    if state == "plan" && selected == to { renderChat() }
    autopilot?.event("chat")
    await speakLines(lines, kind: "chat", first: to)
  }

  // ── play one part of the day ──
  func play() async {
    guard state == "plan" else { return }
    townView.setSpots([])
    stopTalking()
    state = "play"; playing = true; skipping = false; Voice.shared.hush()
    view.endEditing(false)
    panel.isHidden = true
    for v in feedStack.arrangedSubviews { v.removeFromSuperview() }
    feed.isHidden = false; playbar.isHidden = false
    speedButtons()
    let d = day, ph = G.phases[d.phase]
    let before = goalSnap()
    var items = Sim.runPhase(town!)
    for i in items.indices where items[i].type == "protest" { items[i].falsePlan = !d.truth.contains(Claim(k: "demolish", a: items[i].a!, p: items[i].p).key) }
    let isLast = d.done
    let midH = ph.from + ((ph.to - ph.from) / 2).rounded(.down)
    var busyIds = Set<String>()
    for e in items { for x in [e.t, e.l, e.a, e.b] { if let x { busyIds.insert(x) } } }
    let groups = Array(idleGroups(locAt(midH), busyIds).prefix(2))
    let card = PaddedLabel("\(ph.name[LANG] ?? "")   \(fmtH(ph.from)) – \(fmtH(ph.to))", C.paper, font: F.round(22))
    card.translatesAutoresizingMaskIntoConstraints = false; card.layer.borderWidth = 3; card.layer.borderColor = C.ink.cgColor
    view.addSubview(card)
    NSLayoutConstraint.activate([card.centerXAnchor.constraint(equalTo: view.centerXAnchor), card.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60)])
    view.layoutIfNeeded(); fitMap()
    async let resA = Net.shared.lines(items: items, day: d, headline: isLast, groups: groups.map { Net.Group(place: $0.place, ids: $0.ids) }, ctx: mockCtx())
    await sleep(1200)
    let res = await resA
    if isLast { d.headline = res.headline ?? d.headline }
    card.removeFromSuperview()
    autopilot?.event("play")
    let protests = items.filter { $0.type == "protest" }
    var marks = marksBefore(items)
    townView.setMarks(marks)
    func pair(_ e: Item) -> (String, String) { e.type == "talk" ? (e.t!, e.l!) : e.type == "protest" ? (e.who?.first ?? e.a!, e.a!) : (e.a!, e.b!) }
    pre(res.chatter.flatMap { $0.map { ($0.text, $0.who) } } + res.lines.enumerated().flatMap { k, l -> [(String, String)] in let (a, b) = pair(items[k]); return [(l.say, a), (l.reply, b)] })
    var lastH = -1.0, chatted = 0
    func playChatter() async {
      guard chatted < groups.count else { return }
      let g = groups[chatted], lines = res.chatter.count > chatted ? res.chatter[chatted] : []
      chatted += 1
      if lines.isEmpty { return }
      townView.layout(locAt(midH, protests), instant: skipping); townView.focus(g.ids)
      for ln in lines {
        townView.clearTalk(); townView.say(ln.who, ln.text, ms: dur(ln.text, 1.8), kind: "chat")
        feedAdd(ln.who, nil, ln.text, "chat")
        if !skipping { if Prefs.shared.speed > 1 { await wait(dur(ln.text) * 0.9) } else { await talk(ln.text, ln.who, dur(ln.text) * 0.9) } }
      }
    }
    await playChatter()
    for (i, e) in items.enumerated() {
      let ln = res.lines[i]
      if i == items.count / 2 && chatted < groups.count { await playChatter() }
      if i + 3 < items.count { let (a3, b3) = pair(items[i + 3]); pre([(res.lines[i + 3].say, a3), (res.lines[i + 3].reply, b3)]) }
      if e.h != lastH {
        lastH = e.h
        townView.layout(locAt(e.h, protests), instant: skipping)
        dayPill.l.text = T("day", ["d": String(d.day)]) + "  \(ph.name[LANG] ?? "") \(fmtH(e.h))"
        await wait(700)
      }
      if e.type == "talk" {
        let t = e.t!, l = e.l!
        townView.focus([t, l]); townView.clearTalk()
        townView.say(t, ln.say, ms: dur(ln.say, 2), kind: "say")
        feedAdd(t, l, ln.say, "say", e.mut)
        if !skipping { await talk(ln.say, t, dur(ln.say)) }
        townView.arc(t, l, ms: skipping ? 1 : 600)
        await wait(500)
        marks[l] = e.out == "self" ? "self" : e.out == "doubt" ? (marks[l] == "believe" ? "believe" : "doubt") : e.out == "again" ? marks[l] : "believe"
        townView.setMarks(marks)
        townView.clearTalk()
        townView.say(l, ln.reply, ms: dur(ln.reply, 1.6), kind: "reply")
        feedAdd(l, nil, ln.reply, "reply")
        if !skipping { if Prefs.shared.speed > 1 { await wait(dur(ln.reply) * 0.8) } else { await talk(ln.reply, l, dur(ln.reply) * 0.8) } }
      } else {
        let (a, b) = pair(e)
        townView.layout(locAt(e.h, protests), instant: skipping)
        townView.focus([a, b]); townView.clearTalk()
        townView.say(a, ln.say, ms: dur(ln.say, 2.4), kind: "event")
        townView.burst(a, e.type == "protest" ? "sign" : "heart"); townView.burst(b, e.type == "protest" ? "sign" : "heart")
        Haptic.event()
        feedAdd(a, b, ln.say, "event")
        if !skipping { await talk(ln.say, a, dur(ln.say) * 1.2) }
        townView.say(b, ln.reply, ms: dur(ln.reply, 2.4), kind: "event")
        feedAdd(b, nil, ln.reply, "event")
        if !skipping { if Prefs.shared.speed > 1 { await wait(dur(ln.reply) * 1.2) } else { await talk(ln.reply, b, dur(ln.reply) * 1.2) } }
      }
    }
    while chatted < groups.count { await playChatter() }
    townView.layout(locAt(ph.to - 0.5, protests), instant: skipping)
    townView.setMarks(marksNow())
    playing = false
    save()
    if isLast { await sleep(skipping ? 200 : 1200); showResult(); return }
    showProgress(ph, before)
  }
  func idleGroups(_ loc: [String: String], _ busy: Set<String>) -> [(place: String, ids: [String])] {
    var order: [String] = [], g: [String: [String]] = [:]
    for id in G.ids where !busy.contains(id) { let p = loc[id]!; if g[p] == nil { order.append(p) }; g[p, default: []].append(id) }
    return order.filter { g[$0]!.count >= 2 }.map { (place: $0, ids: Array(g[$0]!.prefix(3))) }.enumerated()
      .sorted { $0.element.ids.count != $1.element.ids.count ? $0.element.ids.count > $1.element.ids.count : $0.offset < $1.offset }.map(\.element)
  }
  func marksBefore(_ items: [Item]) -> [String: String] {
    var m = marksNow(), first = Set<String>()
    for e in items where e.type == "talk" && !first.contains(e.l!) {
      first.insert(e.l!)
      if !day.nodes.contains(where: { $0.listener == e.l! && $0.id < e.node! }) { m[e.l!] = nil }
    }
    return m
  }
  func speedButtons() {
    for v in playbar.subviews { v.removeFromSuperview() }
    var items: [UIView] = [label(T("speed"), F.b(13))]
    for s in [1, 2] {
      let b = Btn("\(s)×", primary: Prefs.shared.speed == s, small: true)
      b.onTap = { [weak self] in Prefs.shared.speed = s; self?.speedButtons() }
      items.append(b)
    }
    let skip = UIButton(type: .custom); skip.setImage(Art.ui("skip"), for: .normal); skip.imageView?.contentMode = .scaleAspectFit
    skip.widthAnchor.constraint(equalToConstant: 40).isActive = true; skip.heightAnchor.constraint(equalToConstant: 32).isActive = true
    skip.addAction(UIAction { [weak self] _ in self?.skipping = true; Voice.shared.hush() }, for: .touchUpInside)
    items.append(skip)
    let st = hstack(items, spacing: 8); st.translatesAutoresizingMaskIntoConstraints = false
    playbar.addSubview(st)
    NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo: playbar.leadingAnchor, constant: 14), st.trailingAnchor.constraint(equalTo: playbar.trailingAnchor, constant: -10),
                                 st.topAnchor.constraint(equalTo: playbar.topAnchor, constant: 5), st.bottomAnchor.constraint(equalTo: playbar.bottomAnchor, constant: -5)])
  }
  func feedAdd(_ from: String?, _ to: String?, _ text: String, _ kind: String, _ mut: String? = nil) {
    var head: [UIView] = []
    if let from { head += [faceView(from, 18), label(nameOf(from), F.b(12))] } else { head.append(label(T("you"), F.b(12), C.roof)) }
    if let to { head += [label("→", F.b(12)), faceView(to, 18), label(nameOf(to), F.b(12))] }
    if let mut, let m = G.mutations[mut]?[LANG] { head.append(PaddedLabel(m, hex("#ffe3ef"), font: F.b(10))) }
    head.append(UIView())
    let row = vstack([hstack(head, spacing: 3), label(text, F.r(13), kind == "event" ? hex("#9a5b00") : C.ink)], spacing: 1)
    feedStack.addArrangedSubview(row)
    while feedStack.arrangedSubviews.count > 40 { let v = feedStack.arrangedSubviews[0]; feedStack.removeArrangedSubview(v); v.removeFromSuperview() }
    view.layoutIfNeeded()
    feedScroll.setContentOffset(CGPoint(x: 0, y: max(0, feedScroll.contentSize.height - feedScroll.bounds.height)), animated: true)
    fitMap()
  }

  /// end of a part: how far the gossip got, goal progress, where the two will be next
  func showProgress(_ ph: Phase, _ before: (ab: Int, ba: Int, prot: Int)) {
    state = "progress"
    let d = day, g = d.goal, now = goalSnap(), next = G.phases[d.phase]
    let reach = max(0, Sim.spreadStats(town!).map(\.reach).max() ?? 0), believe = marksNow().values.filter { $0 == "believe" }.count
    var lines: [String], status = ""
    if g.type == "protest" {
      lines = [T("believersLine", ["p": placeName(g.p), "x": String(before.prot), "y": String(now.prot)])]
      status = now.prot >= 5 ? T("goalOK") : now.prot >= 3 ? T("goalNear") : ""
    } else {
      let target = g.type == "reconcile" ? 0 : 50
      lines = [T("effectAfter", ["a": nameOf(g.a), "b": nameOf(g.b!), "x": String(before.ab), "y": String(now.ab)]),
               T("effectAfter", ["a": nameOf(g.b!), "b": nameOf(g.a), "x": String(before.ba), "y": String(now.ba)])]
      let lo = min(now.ab, now.ba)
      status = lo >= target ? T("goalOK") : lo >= target - 15 ? T("goalNear") : ""
    }
    var whereText = ""
    if g.type != "protest" {
      var h = next.from
      while h < next.to {
        if G.placeAt(g.a, h) == G.placeAt(g.b!, h) { whereText = T("meet", ["a": nameOf(g.a), "b": nameOf(g.b!), "place": "\(placeName(G.placeAt(g.a, h))) \(fmtH(h))"]); break }
        h += 0.5
      }
      if whereText.isEmpty { whereText = T("whereBoth", ["a": nameOf(g.a), "pa": placeName(G.placeAt(g.a, next.from)), "b": nameOf(g.b!), "pb": placeName(G.placeAt(g.b!, next.from))]) }
    }
    var views: [UIView] = [label(T("phaseDone", ["p": ph.name[LANG] ?? ""]), F.b(13), C.roof), label(T("spreadLine", ["n": String(reach), "m": String(believe)]), F.r(15)),
                           label(T("progress"), F.b(16)), goalMeterView(town!)]
    for l in lines { views.append(label("・" + l, F.r(14))) }
    if !status.isEmpty { views.append(label(status, F.b(15), C.ok)) }
    if !whereText.isEmpty { views.append(label(T("nextWhere", ["p": next.name[LANG] ?? ""]) + "  " + whereText, F.r(13), C.ink2)) }
    let go = Btn(T("cont"), primary: true); go.onTap = { [weak self] in self?.modal.hide(); self?.plan() }
    views.append(buttonRow([go]))
    feed.isHidden = true; playbar.isHidden = true
    modal.show(views)
    autopilot?.event("progress")
  }

  // ── the end of the day ──
  func showResult() {
    state = "result"
    let d = day, r = d.result!, g = d.goal
    panel.isHidden = true; playbar.isHidden = true; feed.isHidden = true
    hudUpdate()
    if !d.logged {
      var rec = Saves.shared.records; rec.append(Record(day: d.day, type: g.type, ok: r.goalMet, stars: r.stars, reach: r.reach, gen: r.gen, at: Date()))
      Saves.shared.records = rec; d.logged = true; save()
    }
    var views: [UIView] = [label("\(T("day", ["d": String(d.day)]))・\(T("dayEnd"))", F.b(13), C.roof),
                           label(r.goalMet ? T("goalDone") : T("goalFail"), F.round(26), r.goalMet ? C.ok : C.bad)]
    let gl = label("", F.b(15)); gl.attributedText = iconText(goalIcon(g), goalText(g), font: F.b(15)); views.append(gl)
    if !r.goalMet && g.type != "protest" { views.append(label(T("reasonFail", ["a": nameOf(g.a), "b": nameOf(g.b!)]), F.r(13), C.ink2)) }
    var starRow: [UIView] = [UIView()]
    for i in 0..<3 { starRow.append(iconView(i < r.stars ? "star" : "star_off", 46)) }
    starRow.append(UIView())
    views.append(hstack(starRow, spacing: 6))
    for (ok, text) in [(r.goalMet, goalText(g)), (r.reach >= 10, T("reach", ["n": String(r.reach)]) + "（≥10）"), (r.gen >= 3, T("gen", ["n": String(r.gen)]) + "（≥3）")] {
      let l = label("", F.r(14)); l.attributedText = iconText(ok ? "star" : "star_off", text, font: F.r(14)); views.append(l)
    }
    let paper = vstack([label("", F.r(12)), label(d.headline ?? "", F.b(17), lines: 0)], spacing: 2)
    (paper.arrangedSubviews[0] as! UILabel).attributedText = iconText("paper", T("headline"), font: F.b(12), color: C.ink2)
    paper.isLayoutMarginsRelativeArrangement = true; paper.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    paper.backgroundColor = hex("#f6efe0"); paper.layer.cornerRadius = 10
    views.append(paper)
    views.append(treeView())
    views.append(label(T("saved", ["n": String(Prefs.shared.slot)]), F.r(12), C.ink2))
    let retry = Btn(T("retryDay")); retry.onTap = { [weak self] in self?.retryDay() }
    let next = Btn(T("nextDay"), primary: true); next.onTap = { [weak self] in self?.nextDayTap() }
    views.append(buttonRow([retry, next]))
    modal.show(views)
    autopilot?.event("result")
  }
  func nextDayTap() {
    modal.hide()
    if day.day == 3 { toast(T("week"), 4000) }
    Sim.nextDay(town!); snapshot(); save()
    Task { await dayIntro() }
  }
  func retryDay() {
    modal.hide()
    let g0 = day.goal, q0 = day.quest
    if let data = town!.snap, let s = try? JSONDecoder().decode(Snap.self, from: data) {
      town!.aff = s.aff; town!.couples = s.couples; town!.fixed = s.fixed; town!.cancelled = s.cancelled; town!.feuds = s.feuds; town!.totalWhispers = s.totalWhispers
    }
    town!.today = nil
    Sim.startDay(town!, keepGoal: g0); town!.today!.quest = q0; save()
    Task { await dayIntro() }
  }
  /// rumour tree: each whisper → who told whom, where it changed
  func treeView() -> UIView {
    let d = day
    var rows: [UIView] = [label(T("tree"), F.b(15))]
    for (i, w) in d.whispers.enumerated() {
      rows.append(label("\(i + 1). \(G.claimText(w.c, LANG))", F.b(13)))
      let nodes = d.nodes.filter { $0.root == i && $0.out != "again" }
      for n in nodes.prefix(12) {
        var depth = 0, x = n
        while let p = x.parent, depth < 8 { x = d.nodes[p]; depth += 1 }
        let teller = n.teller == YOU ? T("you") : nameOf(n.teller)
        var s = "\(String(repeating: "  ", count: depth))\(teller) → \(nameOf(n.listener))  「\(G.claimText(n.c, LANG))」"
        if let m = n.mut, let mt = G.mutations[m]?[LANG] { s += " [\(mt)]" }
        let icon = n.out == "believe" || n.out == "agree" ? "yes" : n.out == "self" ? nil : "no"
        let l = label("", F.r(12)); l.attributedText = iconText(icon, s, font: F.r(12), size: 13); l.numberOfLines = 0
        rows.append(l)
      }
      if nodes.count > 12 { rows.append(label("+\(nodes.count - 12)", F.r(11), C.ink2)) }
    }
    if d.whispers.isEmpty { rows.append(label(T("nothing"), F.r(13), C.ink2)) }
    let st = vstack(rows, spacing: 3)
    st.isLayoutMarginsRelativeArrangement = true; st.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    st.backgroundColor = C.log; st.layer.cornerRadius = 10
    return st
  }

  // ── settings ──
  @objc func openSettingsTap() { openSettings() }
  func openSettings() {
    let close = Btn(T("close"), primary: true); close.onTap = { [weak self] in self?.modal.hide() }
    var views: [UIView] = [label(T("settings"), F.b(20)), label(T("lang"), F.b(14))]
    let langs = hstack(G.langs.map { l -> UIView in
      let b = Btn((G.raw["langNames"] as? [String: String])?[l] ?? l, primary: l == LANG, small: true)
      b.onTap = { [weak self] in Prefs.shared.lang = l; self?.setLabels(); self?.modal.hide(); self?.refreshAfterLang() }
      return b
    }, spacing: 4)
    let lsc = UIScrollView(); lsc.showsHorizontalScrollIndicator = false; lsc.addSubview(langs); langs.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([langs.leadingAnchor.constraint(equalTo: lsc.contentLayoutGuide.leadingAnchor), langs.trailingAnchor.constraint(equalTo: lsc.contentLayoutGuide.trailingAnchor),
                                 langs.topAnchor.constraint(equalTo: lsc.contentLayoutGuide.topAnchor, constant: 2), langs.bottomAnchor.constraint(equalTo: lsc.contentLayoutGuide.bottomAnchor, constant: -4),
                                 langs.heightAnchor.constraint(equalTo: lsc.frameLayoutGuide.heightAnchor, constant: -6), lsc.heightAnchor.constraint(equalToConstant: 42)])
    views.append(lsc)
    let sw = UISwitch(); sw.isOn = Prefs.shared.voice; sw.onTintColor = C.roof
    let vl = label(Prefs.shared.voice ? T("voiceOn") : T("voiceOff"), F.r(15))
    sw.addAction(UIAction { [weak self] _ in Prefs.shared.voice = sw.isOn; vl.text = sw.isOn ? T("voiceOn") : T("voiceOff"); if sw.isOn { Task { await Voice.shared.speak(T("voiceOn"), "cafe") } } else { Voice.shared.hush() }; _ = self }, for: .valueChanged)
    views.append(hstack([vl, UIView(), sw]))
    views.append(label(Voice.shared.onDevice ? T("micLocal") : T("micCloud"), F.r(12), C.ink2))
    let net = Net.shared
    views.append(label("\(net.mode == .live ? T("llmLive") : net.mode == .cap ? T("llmCap") : T("llmMock"))  \(net.model)", F.b(13), net.mode == .live ? C.ok : C.ink2))
    views.append(label(N("aiCost", ["n": String(net.calls), "c": String(format: "%.4f", net.cost)]), F.r(12), C.ink2))
    if net.mode != .live {
      // internal test build: the lab password gate (same as the web page)
      let tf = UITextField(); tf.placeholder = N("lab"); tf.isSecureTextEntry = true; tf.keyboardType = .numberPad; tf.font = F.r(16)
      tf.borderStyle = .roundedRect
      let go = Btn(N("unlock"), small: true)
      go.onTap = { [weak self] in
        let pw = tf.text ?? ""
        Task { let ok = await Net.shared.unlock(pw); Voice.shared.cloud = Net.shared.tts && ok; self?.toast(ok ? N("unlocked") : N("wrong")); if ok { self?.openSettings() } }
      }
      views.append(label(N("labHint"), F.r(12), C.ink2))
      views.append(hstack([tf, go], spacing: 8))
    }
    var btns: [UIView] = []
    if state != "title" {
      let back = Btn(T("back")); back.onTap = { [weak self] in self?.modal.hide(); Voice.shared.hush(); self?.skipping = true; self?.stopTalking(); self?.showTitle() }
      btns.append(back)
    }
    let saves = Btn(N("saves")); saves.onTap = { [weak self] in self?.openSaves() }
    btns += [saves, close]
    views.append(buttonRow(btns))
    modal.show(views)
  }
  func refreshAfterLang() {
    if state == "title" { showTitle() } else { hudUpdate(); if state == "plan" { if selected != nil { renderChat() } else { panelPick() } } }
  }

  // ── saves: 3 slots, export / import .json, recent results ──
  var deleteArmed: Int? = nil
  var importSlot = 1
  func openSaves() {
    var views: [UIView] = [label("", F.b(20)), label(N("savesHint"), F.r(12), C.ink2)]
    (views[0] as! UILabel).attributedText = iconText("diary", N("saves"), font: F.b(20), size: 26)
    let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
    for n in 1...3 {
      let t = Saves.shared.load(n), active = n == Prefs.shared.slot
      var head = N("slot", ["n": String(n)])
      if active { head += "  ·  " + N("inUse") }
      var lines: [UIView] = [label(head, F.b(15), active ? C.roof : C.ink)]
      if let t {
        let stars = t.stars.values.reduce(0, +)
        lines.append(label("", F.r(13)))
        (lines.last as! UILabel).attributedText = iconText("star", "\(T("day", ["d": String(t.day)]))・\(stars)・\(T("rumorsTotal", ["n": String(t.totalWhispers)]))", font: F.r(13))
        if let at = Saves.shared.savedAt(n) { lines.append(label(N("lastSave", ["d": df.string(from: at)]), F.r(11), C.ink2)) }
      } else { lines.append(label(N("empty"), F.r(13), C.ink2)) }
      var btns: [UIView] = []
      if !active || t == nil {
        let use = Btn(t == nil ? N("newGame") : N("use"), primary: true, small: true)
        use.onTap = { [weak self] in
          guard let self else { return }
          if let cur = self.town { Saves.shared.save(cur) }
          Prefs.shared.slot = n; self.town = Saves.shared.load(n); self.modal.hide(); Voice.shared.hush(); self.showTitle()
        }
        btns.append(use)
      }
      if t != nil {
        let ex = Btn(N("export"), small: true); ex.onTap = { [weak self] in self?.exportSlot(n) }
        btns.append(ex)
      }
      let im = Btn(N("import"), small: true); im.onTap = { [weak self] in self?.importSlot = n; self?.pickImport() }
      btns.append(im)
      if t != nil {
        let del = Btn(deleteArmed == n ? N("confirmDelete") : N("delete"), small: true)
        del.onTap = { [weak self] in
          guard let self else { return }
          if self.deleteArmed == n { Saves.shared.delete(n); if active { self.town = nil }; self.deleteArmed = nil; self.openSaves(); if active { self.showTitle() } }
          else { self.deleteArmed = n; self.openSaves() }
        }
        btns.append(del)
      }
      let bsc = UIScrollView(); let brow = hstack(btns, spacing: 6); bsc.showsHorizontalScrollIndicator = false
      bsc.addSubview(brow); brow.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([brow.leadingAnchor.constraint(equalTo: bsc.contentLayoutGuide.leadingAnchor), brow.trailingAnchor.constraint(equalTo: bsc.contentLayoutGuide.trailingAnchor),
                                   brow.topAnchor.constraint(equalTo: bsc.contentLayoutGuide.topAnchor, constant: 2), brow.bottomAnchor.constraint(equalTo: bsc.contentLayoutGuide.bottomAnchor, constant: -4),
                                   brow.heightAnchor.constraint(equalTo: bsc.frameLayoutGuide.heightAnchor, constant: -6), bsc.heightAnchor.constraint(equalToConstant: 40)])
      lines.append(bsc)
      let box = vstack(lines, spacing: 3)
      box.isLayoutMarginsRelativeArrangement = true; box.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
      box.backgroundColor = active ? hex("#fff6e8") : C.log; box.layer.cornerRadius = 12
      box.layer.borderWidth = active ? 2 : 0; box.layer.borderColor = C.roof.cgColor
      views.append(box)
    }
    views.append(label(N("records"), F.b(15)))
    let rec = Saves.shared.records.suffix(8).reversed()
    if rec.isEmpty { views.append(label(N("noRecords"), F.r(13), C.ink2)) }
    for r in rec {
      let l = label("", F.r(13))
      l.attributedText = iconText(r.ok ? "star" : "star_off", "\(T("day", ["d": String(r.day)]))  \(r.ok ? T("goalDone") : T("goalFail"))  \(T("starsN", ["n": String(r.stars)]))・\(T("reach", ["n": String(r.reach)]))", font: F.r(13))
      views.append(l)
    }
    let close = Btn(T("close"), primary: true); close.onTap = { [weak self] in self?.deleteArmed = nil; self?.modal.hide() }
    views.append(buttonRow([close]))
    modal.show(views)
  }
  func exportSlot(_ n: Int) {
    guard let f = Saves.shared.exportFile(n) else { return }
    let ac = UIActivityViewController(activityItems: [f], applicationActivities: nil)
    ac.popoverPresentationController?.sourceView = view
    present(ac, animated: true)
  }
  func pickImport() {
    let p = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
    p.delegate = self
    present(p, animated: true)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let u = urls.first else { return }
    if Saves.shared.importFile(u, into: importSlot) {
      toast(N("imported", ["n": String(importSlot)]))
      if importSlot == Prefs.shared.slot { town = Saves.shared.load(); showTitle() }
      openSaves()
    } else { toast(N("importFailed")) }
  }
}

extension UIImage {
  func resized(_ s: CGFloat) -> UIImage { UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { _ in draw(in: CGRect(x: 0, y: 0, width: s, height: s)) } }
}

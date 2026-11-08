// The town map — port of the web render.js: the illustration (cover-scaled, drag to pan, the camera follows whoever talks),
// residents as round portraits that walk between places, speech bubbles, rumour arcs, believe/doubt badges, heart / protest
// sign bursts and the tappable map objects. Coordinates are illustration pixels (2048×1144). The illustration is an image
// view (GPU); everything else is drawn by `Overlay` with Core Graphics every frame (CADisplayLink).
import UIKit
import GossipCore

let IW: CGFloat = 2048, IH: CGFloat = 1144
private func ease(_ t: CGFloat) -> CGFloat { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

final class TownView: UIView {
  struct Tok { var x, y, fx, fy, tx, ty: CGFloat; var t0: Double; var dur: Double }
  struct Bubble { var id: String; var text: String; var t0: Double; var ms: Double; var kind: String }
  struct Arc { var from, to: String; var t0: Double; var ms: Double }
  struct Fx { var id: String; var kind: String; var t0: Double; var ms: Double }
  struct Spot { var id: String; var x, y: CGFloat; var used: Bool }

  var onPick: ((String) -> Void)?
  private let blurView = UIImageView()
  private let veil = UIView()
  private let bg = UIImageView(image: Art.town)
  private let overlay = Overlay()
  private var link: CADisplayLink?
  fileprivate var tok: [String: Tok] = [:]
  fileprivate var bubbles: [Bubble] = [], arcs: [Arc] = [], fx: [Fx] = []
  fileprivate var marks: [String: String] = [:], labels: [String: String] = [:]
  fileprivate var selected: String? = nil, dim = false
  fileprivate var spots: [Spot] = []
  fileprivate var s: CGFloat = 1, ox: CGFloat = 0, oy: CGFloat = 0, tokenR: CGFloat = 26
  private var panX: CGFloat = 0.5, panY: CGFloat = 0.5, wantX: CGFloat = 0.5, wantY: CGFloat = 0.5
  private var topIn: CGFloat = 0, botIn: CGFloat = 0
  private var drag: (start: CGPoint, px: CGFloat, py: CGFloat)?
  fileprivate var now: Double { CACurrentMediaTime() * 1000 }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = C.sky
    blurView.contentMode = .scaleAspectFill; blurView.clipsToBounds = true
    blurView.image = TownView.blurred(Art.town)
    veil.backgroundColor = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 0.35)
    overlay.town = self; overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.isUserInteractionEnabled = false
    for v in [blurView, veil, bg, overlay] { addSubview(v) }
    let G = GameData.shared!
    for r in G.residents {
      let p = G.place[r.home]!
      let x = CGFloat(p.x) * IW, y = CGFloat(p.y) * IH
      tok[r.id] = Tok(x: x, y: y, fx: x, fy: y, tx: x, ty: y, t0: 0, dur: 1)
    }
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(onPan(_:))))
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap(_:))))
    link = CADisplayLink(target: self, selector: #selector(frameTick))
    link?.add(to: .main, forMode: .common)
  }
  required init?(coder: NSCoder) { fatalError() }
  static func blurred(_ img: UIImage) -> UIImage {
    // the same picture shrunk to 96×54 and scaled back up = a soft backdrop for the strips the map does not cover
    UIGraphicsImageRenderer(size: CGSize(width: 96, height: 54)).image { _ in img.draw(in: CGRect(x: 0, y: 0, width: 96, height: 54)) }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let W = bounds.width, H = bounds.height
    // phone portrait: the map is 46% of the screen high (like the web; 72% showed only the square), placed between HUD and panel
    s = W < H ? max(W / IW, H * 0.46 / IH) : max(W / IW, H / IH)
    tokenR = max(20, min(30, min(W, H) / 22))
    blurView.frame = bounds; veil.frame = bounds; overlay.frame = bounds
  }
  /// space covered by the HUD (top) and the panel (bottom); the map sits in the band between
  func setInsets(top: CGFloat, bottom: CGFloat) { topIn = top; botIn = bottom }

  fileprivate func toScreen(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s + ox, y: y * s + oy) }
  private func updatePan() {
    let W = bounds.width, H = bounds.height
    panX += (wantX - panX) * 0.08; panY += (wantY - panY) * 0.08
    let ow = IW * s - W, ih = IH * s
    ox = -max(0, min(ow, panX * IW * s - W / 2))
    let T = W < H ? topIn : 0, B = W < H ? max(T + 60, H - botIn) : H
    oy = ih <= B - T ? T + (B - T - ih) / 2 : max(B - ih, min(T, (T + B) / 2 - panY * ih))
    bg.frame = CGRect(x: ox, y: oy, width: IW * s, height: IH * s)
    let cover = ih < H
    blurView.isHidden = !cover; veil.isHidden = !cover
  }
  @objc private func frameTick() {
    updatePan()
    let n = now
    for id in Array(tok.keys) {
      var t = tok[id]!
      let k = t.dur > 0 ? ease(CGFloat(min(1, (n - t.t0) / t.dur))) : 1
      t.x = t.fx + (t.tx - t.fx) * k; t.y = t.fy + (t.ty - t.fy) * k
      tok[id] = t
    }
    bubbles.removeAll { n - $0.t0 > $0.ms }
    arcs.removeAll { n - $0.t0 > $0.ms + 300 }
    fx.removeAll { n - $0.t0 > $0.ms }
    overlay.setNeedsDisplay()
  }

  // ── API (same as render.js) ──
  /// residents at the same place stand in a little circle
  func layout(_ loc: [String: String], instant: Bool) {
    let G = GameData.shared!
    var groups: [String: [String]] = [:]
    for id in G.ids { groups[loc[id]!, default: []].append(id) }
    let n0 = now
    for (place, ids) in groups {
      guard let P = G.place[place] else { continue }
      let n = ids.count, rad: CGFloat = n == 1 ? 0 : 46 + CGFloat(n) * 9
      for (k, id) in ids.enumerated() {
        let ang = CGFloat(k) / CGFloat(n) * .pi * 2 + 0.6
        let nx = CGFloat(P.x) * IW + cos(ang) * rad * 1.25, ny = CGFloat(P.y) * IH + sin(ang) * rad * 0.7
        var t = tok[id]!
        if instant { t = Tok(x: nx, y: ny, fx: nx, fy: ny, tx: nx, ty: ny, t0: 0, dur: 1) }
        else if hypot(nx - t.tx, ny - t.ty) > 1 { t.fx = t.x; t.fy = t.y; t.tx = nx; t.ty = ny; t.t0 = n0; t.dur = 650 + Double(hypot(nx - t.x, ny - t.y)) * 0.5 }
        tok[id] = t
      }
    }
  }
  func focus(_ ids: [String]) {
    let pts = ids.compactMap { tok[$0] }
    guard !pts.isEmpty else { return }
    wantX = pts.reduce(0) { $0 + $1.tx } / CGFloat(pts.count) / IW
    wantY = pts.reduce(0) { $0 + $1.ty } / CGFloat(pts.count) / IH
  }
  func say(_ id: String, _ text: String, ms: Double, kind: String = "say") {
    bubbles.removeAll { $0.id == id }
    bubbles.append(Bubble(id: id, text: text, t0: now, ms: ms, kind: kind))
  }
  func arc(_ from: String, _ to: String, ms: Double = 700) { arcs.append(Arc(from: from, to: to, t0: now, ms: ms)) }
  func burst(_ id: String, _ kind: String) { fx.append(Fx(id: id, kind: kind, t0: now, ms: 2200)) }
  func clearTalk() { bubbles.removeAll() }
  func setMarks(_ m: [String: String]) { marks = m }
  func setLabels(_ l: [String: String]) { labels = l }
  func setSpots(_ s: [Spot]) { spots = s }
  func select(_ id: String?, dim d: Bool = false) { selected = id; dim = d; if let id { focus([id]) } }

  // ── touch ──
  private func hit(_ p: CGPoint) -> String? {
    var best: String? = nil, bd = CGFloat.greatestFiniteMagnitude
    for (id, t) in tok {
      let q = toScreen(t.x, t.y), d = hypot(p.x - q.x, p.y - q.y)
      if d < tokenR + 10 && d < bd { bd = d; best = id }
    }
    if let best { return best }
    for sp in spots { let q = toScreen(sp.x * IW, sp.y * IH); if hypot(p.x - q.x, p.y - q.y) < tokenR * 1.2 { return "spot:" + sp.id } }
    return nil
  }
  @objc private func onTap(_ g: UITapGestureRecognizer) { if let id = hit(g.location(in: self)) { onPick?(id) } }
  @objc private func onPan(_ g: UIPanGestureRecognizer) {
    let p = g.location(in: self)
    switch g.state {
    case .began: drag = (p, wantX, wantY)
    case .changed:
      guard let d = drag else { return }
      wantX = d.px - (p.x - d.start.x) / (IW * s); wantY = d.py - (p.y - d.start.y) / (IH * s)
      panX = wantX; panY = wantY
    default: drag = nil
    }
  }
}

/// Draws residents, bubbles, arcs, effects and map objects (render.js drawToken / drawBubble / drawArc / drawFx).
final class Overlay: UIView {
  weak var town: TownView?
  private var faceCache: [String: UIImage] = [:]
  private func face(_ id: String, _ r: CGFloat) -> UIImage {
    if let f = faceCache[id] { return f }
    let f = Art.face(id, size: 2 * r * 2.2 * UIScreen.main.scale)   // drawn at 2r, extra detail for the selected (×1.18) size
    faceCache[id] = f
    return f
  }
  override func draw(_ rect: CGRect) {
    guard let tv = town, let g = UIGraphicsGetCurrentContext() else { return }
    let n = tv.now
    // map objects
    for sp in tv.spots {
      let q = tv.toScreen(sp.x * IW, sp.y * IH), z = tv.tokenR * 1.7
      let bob: CGFloat = sp.used ? 0 : sin(CGFloat(n) / 420 + sp.x * 9) * 3
      g.saveGState()
      if sp.used { g.setAlpha(0.35) } else {
        g.setFillColor(UIColor(red: 1, green: 0.98, blue: 0.92, alpha: 0.75).cgColor)
        g.fillEllipse(in: CGRect(x: q.x - z * 0.45, y: q.y + z * 0.42 - z * 0.14, width: z * 0.9, height: z * 0.28))
      }
      Art.ui(sp.id).draw(in: CGRect(x: q.x - z / 2, y: q.y - z / 2 + bob - z * 0.1, width: z, height: z))
      g.restoreGState()
    }
    // residents, back to front
    var pos: [String: (CGPoint, CGFloat)] = [:]
    for id in GameData.shared.ids.sorted(by: { tv.tok[$0]!.y < tv.tok[$1]!.y }) { pos[id] = drawToken(g, tv, id, n) }
    for a in tv.arcs { drawArc(g, a, n, pos) }
    for f in tv.fx { drawFx(g, f, n, pos) }
    for b in tv.bubbles { drawBubble(g, tv, b, n, pos) }
  }
  private func drawToken(_ g: CGContext, _ tv: TownView, _ id: String, _ n: Double) -> (CGPoint, CGFloat) {
    let t = tv.tok[id]!, q = tv.toScreen(t.x, t.y)
    let walking = n - t.t0 < t.dur
    let bob: CGFloat = walking ? abs(sin(CGFloat(n) / 90)) * 3 : 0
    let r = tv.tokenR * (tv.selected == id ? 1.18 : 1)
    g.saveGState()
    g.setAlpha(tv.dim && tv.selected != nil && tv.selected != id ? 0.55 : 1)
    g.setFillColor(UIColor(red: 40 / 255, green: 30 / 255, blue: 20 / 255, alpha: 0.28).cgColor)
    g.fillEllipse(in: CGRect(x: q.x - r * 0.8, y: q.y + r * 0.95 - r * 0.25, width: r * 1.6, height: r * 0.5))
    let cy = q.y - bob
    g.setFillColor((tv.selected == id ? hex("#ffd24a") : C.paper).cgColor)
    g.fillEllipse(in: CGRect(x: q.x - r - 3.5, y: cy - r - 3.5, width: 2 * r + 7, height: 2 * r + 7))
    face(id, tv.tokenR).draw(in: CGRect(x: q.x - r, y: cy - r, width: 2 * r, height: 2 * r))
    g.setStrokeColor(UIColor(red: 80 / 255, green: 50 / 255, blue: 30 / 255, alpha: 0.55).cgColor); g.setLineWidth(1.5)
    g.strokeEllipse(in: CGRect(x: q.x - r - 3.5, y: cy - r - 3.5, width: 2 * r + 7, height: 2 * r + 7))
    if let lab = tv.labels[id] {
      let f = UIFont.systemFont(ofSize: max(10, (r * 0.5).rounded()), weight: .semibold)
      let w = (lab as NSString).size(withAttributes: [.font: f]).width + 10
      let box = CGRect(x: q.x - w / 2, y: cy + r + 4, width: w, height: r * 0.62)
      g.setFillColor(UIColor(red: 1, green: 0.98, blue: 0.94, alpha: 0.92).cgColor)
      g.addPath(UIBezierPath(roundedRect: box, cornerRadius: 5).cgPath); g.fillPath()
      let ps = NSMutableParagraphStyle(); ps.alignment = .center
      (lab as NSString).draw(in: CGRect(x: box.minX, y: box.midY - f.lineHeight / 2, width: w, height: f.lineHeight),
                             withAttributes: [.font: f, .foregroundColor: hex("#5a3a24"), .paragraphStyle: ps])
    }
    if let m = tv.marks[id] {
      let br = r * 0.34, bx = q.x + r * 0.78, by = cy - r * 0.78
      g.setFillColor((m == "believe" ? hex("#3aa760") : m == "doubt" ? hex("#9a9a9a") : hex("#e0a128")).cgColor)
      g.fillEllipse(in: CGRect(x: bx - br, y: by - br, width: 2 * br, height: 2 * br))
      g.setStrokeColor(UIColor.white.cgColor); g.setLineWidth(2); g.setLineCap(.round)
      if m == "believe" { g.move(to: CGPoint(x: bx - br * 0.45, y: by)); g.addLine(to: CGPoint(x: bx - br * 0.1, y: by + br * 0.4)); g.addLine(to: CGPoint(x: bx + br * 0.5, y: by - br * 0.4)) }
      else if m == "doubt" { g.move(to: CGPoint(x: bx - br * 0.4, y: by - br * 0.4)); g.addLine(to: CGPoint(x: bx + br * 0.4, y: by + br * 0.4)); g.move(to: CGPoint(x: bx + br * 0.4, y: by - br * 0.4)); g.addLine(to: CGPoint(x: bx - br * 0.4, y: by + br * 0.4)) }
      else { g.addEllipse(in: CGRect(x: bx - br * 0.35, y: by - br * 0.35, width: br * 0.7, height: br * 0.7)) }
      g.strokePath()
    }
    g.restoreGState()
    return (CGPoint(x: q.x, y: cy), r)
  }
  private func drawBubble(_ g: CGContext, _ tv: TownView, _ b: TownView.Bubble, _ n: Double, _ pos: [String: (CGPoint, CGFloat)]) {
    guard let pr = pos[b.id] else { return }
    let p = pr.0, r = pr.1
    let age = n - b.t0, W = bounds.width
    let a = CGFloat(min(1, age / 160, (b.ms - age) / 220))
    let fs = max(13, min(16, W / 26))
    let font = UIFont.systemFont(ofSize: fs, weight: b.kind == "event" ? .bold : .medium)
    let maxW = min(250, W * 0.62)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: C.ink]
    let size = (b.text as NSString).boundingRect(with: CGSize(width: maxW, height: fs * 1.35 * 5), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil).size
    let w = ceil(size.width) + 22, h = ceil(size.height) + 14
    var bx = p.x - w / 2, by = p.y - r - 16 - h
    bx = max(6, min(W - w - 6, bx)); if by < tv.safeAreaInsets.top + 50 { by = p.y + r + 26 }
    let below = by > p.y
    g.saveGState(); g.setAlpha(max(0, a))
    let fill: UIColor = b.kind == "reply" ? hex("#eef6ff") : b.kind == "event" ? hex("#fff0c2") : b.kind == "whisper" ? hex("#ffe3ef") : b.kind == "chat" ? hex("#fbf6ea") : .white
    let box = UIBezierPath(roundedRect: CGRect(x: bx, y: by, width: w, height: h), cornerRadius: 12)
    g.setFillColor(fill.cgColor); g.addPath(box.cgPath); g.fillPath()
    g.setStrokeColor((b.kind == "event" ? hex("#d08a1e") : UIColor(red: 90 / 255, green: 58 / 255, blue: 36 / 255, alpha: 0.55)).cgColor); g.setLineWidth(1.6)
    g.addPath(box.cgPath); g.strokePath()
    let tx = max(bx + 14, min(bx + w - 14, p.x))
    if below { g.move(to: CGPoint(x: tx - 7, y: by + 1)); g.addLine(to: CGPoint(x: p.x, y: p.y + r + 4)); g.addLine(to: CGPoint(x: tx + 7, y: by + 1)) }
    else { g.move(to: CGPoint(x: tx - 7, y: by + h - 1)); g.addLine(to: CGPoint(x: p.x, y: p.y - r - 4)); g.addLine(to: CGPoint(x: tx + 7, y: by + h - 1)) }
    g.setFillColor(fill.cgColor); g.fillPath()
    (b.text as NSString).draw(with: CGRect(x: bx + 11, y: by + 7, width: maxW, height: h), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
    g.restoreGState()
  }
  private func drawArc(_ g: CGContext, _ a: TownView.Arc, _ n: Double, _ pos: [String: (CGPoint, CGFloat)]) {
    guard let q0 = pos[a.from], let q1 = pos[a.to] else { return }
    let p0 = q0.0, p1 = q1.0
    let k = ease(CGFloat(min(1, (n - a.t0) / a.ms)))
    let mx = (p0.x + p1.x) / 2, my = min(p0.y, p1.y) - 60 - hypot(p1.x - p0.x, p1.y - p0.y) * 0.25
    func pt(_ u: CGFloat) -> CGPoint { CGPoint(x: (1 - u) * (1 - u) * p0.x + 2 * (1 - u) * u * mx + u * u * p1.x, y: (1 - u) * (1 - u) * p0.y + 2 * (1 - u) * u * my + u * u * p1.y) }
    let col = hex("#ff8a3d")
    g.saveGState()
    g.setStrokeColor(col.withAlphaComponent(0.75).cgColor); g.setLineWidth(2.5); g.setLineDash(phase: 0, lengths: [6, 6])
    var u: CGFloat = 0
    g.move(to: pt(0))
    while u <= k { g.addLine(to: pt(u)); u += 0.04 }
    g.strokePath(); g.setLineDash(phase: 0, lengths: [])
    let h = pt(k)
    let env = UIBezierPath(roundedRect: CGRect(x: h.x - 11, y: h.y - 8, width: 22, height: 16), cornerRadius: 5)
    g.setFillColor(UIColor.white.cgColor); g.addPath(env.cgPath); g.fillPath()
    g.setStrokeColor(col.cgColor); g.setLineWidth(2); g.addPath(env.cgPath); g.strokePath()
    g.setFillColor(col.cgColor)
    for i in -1...1 { g.fillEllipse(in: CGRect(x: h.x + CGFloat(i) * 5 - 1.7, y: h.y - 1.7, width: 3.4, height: 3.4)) }
    g.restoreGState()
  }
  private func drawFx(_ g: CGContext, _ f: TownView.Fx, _ n: Double, _ pos: [String: (CGPoint, CGFloat)]) {
    guard let pr = pos[f.id] else { return }
    let p = pr.0, r = pr.1
    let k = CGFloat((n - f.t0) / f.ms)
    g.saveGState(); g.setAlpha(max(0, 1 - k))
    let img = Art.ui(f.kind == "sign" ? "sign" : "heart")
    for i in 0..<6 {
      let ang = CGFloat(i) / 6 * .pi * 2 + k * 2, d = r + k * 50
      let x = p.x + cos(ang) * d, y = p.y - r - k * 40 + sin(ang) * d * 0.4
      img.draw(in: CGRect(x: x - 10, y: y - 10, width: 20, height: 20))
    }
    g.restoreGState()
  }
}

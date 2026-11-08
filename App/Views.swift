// Reusable views: paper cards, the goal meter, chat rows, the playback feed, the modal host, the round mic button.
import UIKit
import GossipCore

/// cream card with an ink outline (.panel / .mbox)
class Card: UIView {
  init(radius: CGFloat = 18, top: Bool = false) {
    super.init(frame: .zero)
    backgroundColor = C.paper
    layer.borderColor = C.ink.cgColor; layer.borderWidth = 3; layer.cornerRadius = radius
    if top { layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] }
    layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.18; layer.shadowRadius = 8; layer.shadowOffset = CGSize(width: 0, height: 3)
  }
  required init?(coder: NSCoder) { fatalError() }
}

/// one goal bar: x's feeling for y (-100…100) with the target tick (web .meter)
final class BarView: UIView {
  var value: CGFloat = 0, target: CGFloat = 0, frac: CGFloat? = nil
  init(value: Int, target: Int) { self.value = CGFloat(value); self.target = CGFloat(target); super.init(frame: .zero); backgroundColor = .clear }
  init(frac: CGFloat) { self.frac = frac; super.init(frame: .zero); backgroundColor = .clear }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: CGSize { CGSize(width: 60, height: 10) }
  override func draw(_ rect: CGRect) {
    let r = bounds.insetBy(dx: 1, dy: 1)
    let track = UIBezierPath(roundedRect: r, cornerRadius: r.height / 2)
    hex("#e8dcc4").setFill(); track.fill()
    let pct = frac ?? (value + 100) / 200
    let col: UIColor = frac != nil ? C.roof : value >= target ? C.ok : value < 0 ? C.bad : C.gold
    col.setFill(); UIBezierPath(roundedRect: CGRect(x: r.minX, y: r.minY, width: max(r.height, r.width * min(1, max(0, pct))), height: r.height), cornerRadius: r.height / 2).fill()
    if frac == nil {
      C.ink.setFill(); UIRectFill(CGRect(x: r.minX + r.width * (target + 100) / 200 - 1, y: 0, width: 2, height: bounds.height))
    }
  }
}

/// a row of the goal meter: face a → bar → face b  value
@MainActor func meterRow(_ a: String, _ b: String, _ v: Int, _ target: Int, face: CGFloat = 20) -> UIView {
  let bar = BarView(value: v, target: target)
  bar.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
  bar.heightAnchor.constraint(equalToConstant: 10).isActive = true
  let l = label(String(v), F.b(13)); l.setContentHuggingPriority(.required, for: .horizontal)
  return hstack([faceView(a, face), bar, faceView(b, face), l], spacing: 4)
}
@MainActor func goalMeterView(_ town: Town) -> UIView {
  let d = town.today!, g = d.goal
  if g.type == "protest" {
    let n = (d.protest[g.p!] ?? []).count
    let bar = BarView(frac: CGFloat(n) / 5)
    bar.heightAnchor.constraint(equalToConstant: 10).isActive = true
    return hstack([bar, label("\(n)/5", F.b(13))], spacing: 6)
  }
  let target = g.type == "reconcile" ? 0 : 50
  return hstack([meterRow(g.a, g.b!, town.aff[g.a]![g.b!]!, target), meterRow(g.b!, g.a, town.aff[g.b!]![g.a]!, target)], spacing: 10, align: .center)
}

/// a resident's line in the chat log (face + name + bubble), your line (pink, right), a note, or the rumour chip
@MainActor func chatRowView(_ r: ChatRow) -> UIView {
  if let chip = r.chip {
    let v = UIView(); v.backgroundColor = hex("#ffe3ef"); v.layer.cornerRadius = 10
    let t = label("", F.r(13)); t.attributedText = iconText("gossip", T("rumorOut") + "「\(chip)」", font: F.b(13))
    var items: [UIView] = [t]
    let heard = (r.heard ?? []).map { h -> UIView in
      let icon = h.out == "believe" || h.out == "agree" ? "yes" : h.out == "self" ? nil : "no"
      let l = label("", F.r(12)); l.attributedText = iconText(icon, nameOf(h.id), font: F.r(12), size: 13)
      return l
    }
    let flow = UIStackView(arrangedSubviews: heard); flow.axis = .horizontal; flow.spacing = 8; flow.alignment = .center
    let hs = UIScrollView(); hs.showsHorizontalScrollIndicator = false; hs.addSubview(flow)
    flow.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([flow.leadingAnchor.constraint(equalTo: hs.contentLayoutGuide.leadingAnchor), flow.trailingAnchor.constraint(equalTo: hs.contentLayoutGuide.trailingAnchor),
                                 flow.topAnchor.constraint(equalTo: hs.contentLayoutGuide.topAnchor), flow.bottomAnchor.constraint(equalTo: hs.contentLayoutGuide.bottomAnchor),
                                 flow.heightAnchor.constraint(equalTo: hs.frameLayoutGuide.heightAnchor), hs.heightAnchor.constraint(equalToConstant: 20)])
    items.append(hs)
    for e in r.eff ?? [] { items.append(label(e, F.b(12), hex("#2e7d32"))) }
    let st = vstack(items, spacing: 3); st.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(st)
    NSLayoutConstraint.activate([st.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8), st.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -8),
                                 st.topAnchor.constraint(equalTo: v.topAnchor, constant: 5), st.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -5)])
    return v
  }
  if let note = r.note { return label(note, F.r(13), C.ink2) }
  let bubble = PaddedLabel(r.text ?? "", r.who == YOU ? hex("#ffe3ef") : .white)
  if r.who == YOU {
    let row = hstack([UIView(), bubble], spacing: 0)
    bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.85).isActive = true
    return row
  }
  let who = r.who ?? "cafe"
  let name = label(nameOf(who), F.b(11), C.ink2)
  let col = vstack([name, bubble], spacing: 1, align: .leading)
  return hstack([faceView(who, 24), col, UIView()], spacing: 6, align: .top)
}

final class PaddedLabel: UIView {
  let l = UILabel()
  init(_ text: String, _ bg: UIColor, font: UIFont = F.r(14)) {
    super.init(frame: .zero)
    backgroundColor = bg; layer.cornerRadius = 12; layer.borderWidth = 1; layer.borderColor = hex("#e8dcc4").cgColor
    l.text = text; l.font = font; l.textColor = C.ink; l.numberOfLines = 0
    l.translatesAutoresizingMaskIntoConstraints = false
    addSubview(l)
    NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), l.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                                 l.topAnchor.constraint(equalTo: topAnchor, constant: 5), l.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)])
  }
  required init?(coder: NSCoder) { fatalError() }
}

/// the big round mic in the middle (company rule: ≥72 pt, centered under the input, clearly changes colour while listening)
final class MicButton: UIButton {
  var recording = false { didSet { refresh() } }
  init() {
    super.init(frame: .zero)
    setImage(Art.ui("mic"), for: .normal)
    imageView?.contentMode = .scaleAspectFit
    imageEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    layer.borderWidth = 3; layer.borderColor = C.ink.cgColor
    layer.shadowColor = C.ink.cgColor; layer.shadowOpacity = 1; layer.shadowRadius = 0; layer.shadowOffset = CGSize(width: 0, height: 4)
    translatesAutoresizingMaskIntoConstraints = false
    widthAnchor.constraint(equalToConstant: 76).isActive = true; heightAnchor.constraint(equalToConstant: 76).isActive = true
    refresh()
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); layer.cornerRadius = bounds.width / 2 }
  private func refresh() {
    backgroundColor = recording ? C.rose : hex("#fff3d6")
    layer.removeAnimation(forKey: "pulse")
    if recording {
      let a = CABasicAnimation(keyPath: "transform.scale"); a.fromValue = 1; a.toValue = 1.08; a.duration = 0.5; a.autoreverses = true; a.repeatCount = .infinity
      layer.add(a, forKey: "pulse")
    }
  }
}

/// dim backdrop + one card in the middle; content is a vertical stack inside a scroll view
final class ModalHost: UIView {
  let card = Card()
  let scroll = UIScrollView()
  let stack = vstack([], spacing: 10)
  private var heightC: NSLayoutConstraint!
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor.black.withAlphaComponent(0.35)
    isHidden = true
    addSubview(card); card.addSubview(scroll); scroll.addSubview(stack)
    for v in [card, scroll, stack] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
    heightC = scroll.heightAnchor.constraint(equalToConstant: 100); heightC.priority = .defaultHigh
    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: centerXAnchor), card.centerYAnchor.constraint(equalTo: centerYAnchor),
      card.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.92), card.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
      card.heightAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.heightAnchor, multiplier: 0.86),
      scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 4), scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4), heightC,
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -14),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  func show(_ views: [UIView]) {
    for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
    for v in views { stack.addArrangedSubview(v) }
    isHidden = false
    setNeedsLayout(); layoutIfNeeded()
    heightC.constant = stack.systemLayoutSizeFitting(CGSize(width: stack.bounds.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height + 28
    scroll.setContentOffset(.zero, animated: false)
  }
  func hide() { isHidden = true }
}

/// a row of buttons aligned right (.mrow)
@MainActor func buttonRow(_ b: [UIView]) -> UIView { hstack([UIView()] + b, spacing: 8) }

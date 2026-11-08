// Look of the web build (style.css): cream paper cards with an ink outline, roof-red primary buttons, round faces.
// Art: the Gemini town illustration, the 4×3 portrait sheet and the 4×4 UI icon sheet, all copied from the web repo.
import UIKit
import GossipCore

func hex(_ s: String) -> UIColor {
  var v: UInt64 = 0; Scanner(string: s.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
  return UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
enum C {
  static let roof = hex("#c8553d"), roof2 = hex("#a8422e"), cream = hex("#f4e8d0"), paper = hex("#fffaf0"), ink = hex("#3d2817"), ink2 = hex("#6d5340")
  static let sky = hex("#a8dadc"), gold = hex("#f2b134"), rose = hex("#ff5d8f"), tree = hex("#6a994e"), tut = hex("#fff0c2"), log = hex("#fbf6ea")
  static let ok = hex("#4f9d4a"), bad = hex("#c8553d")
}
enum F {
  static func r(_ s: CGFloat) -> UIFont { .systemFont(ofSize: s, weight: .regular) }
  static func b(_ s: CGFloat) -> UIFont { .systemFont(ofSize: s, weight: .bold) }
  static func round(_ s: CGFloat) -> UIFont {
    let f = UIFont.systemFont(ofSize: s, weight: .heavy)
    return f.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: s) } ?? f
  }
}

/// Images from the bundled GameData folder.
enum Art {
  static func url(_ p: String) -> URL { Bundle.main.bundleURL.appendingPathComponent("GameData").appendingPathComponent(p) }
  static let town: UIImage = UIImage(contentsOfFile: url("img/town.webp").path) ?? UIImage()
  static let facesSheet: UIImage = UIImage(contentsOfFile: url("img/faces.webp").path) ?? UIImage()
  private static var cache: [String: UIImage] = [:]
  static func ui(_ name: String) -> UIImage {
    if let i = cache["ui/" + name] { return i }
    let i = UIImage(contentsOfFile: url("img/ui/\(name).png").path) ?? UIImage()
    cache["ui/" + name] = i
    return i
  }
  /// A resident's portrait: the top 180×180 of their 256×192 cell (cut_faces.py layout), as a circle with a white rim.
  static func face(_ id: String, size: CGFloat = 120, rim: CGFloat = 0) -> UIImage {
    let key = "face/\(id)/\(Int(size))/\(Int(rim))"
    if let i = cache[key] { return i }
    let f = GameData.shared.res[id]?.face ?? 0
    let sheet = facesSheet, sc = sheet.size.width / 1024   // sheet is 4×256 wide
    let cell = CGRect(x: CGFloat(f % 4) * 256 * sc + 38 * sc, y: CGFloat(f / 4) * 192 * sc + 4 * sc, width: 180 * sc, height: 180 * sc)
    let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
      let full = CGRect(x: 0, y: 0, width: size, height: size)
      if rim > 0 { UIColor.white.setFill(); UIBezierPath(ovalIn: full).fill() }
      let inner = full.insetBy(dx: rim, dy: rim)
      C.cream.setFill(); UIBezierPath(ovalIn: inner).fill()
      UIBezierPath(ovalIn: inner).addClip()
      if let cg = sheet.cgImage?.cropping(to: CGRect(x: cell.minX * sheet.scale, y: cell.minY * sheet.scale, width: cell.width * sheet.scale, height: cell.height * sheet.scale)) {
        UIImage(cgImage: cg).draw(in: inner)
      }
      _ = ctx
    }
    cache[key] = img
    return img
  }
}

/// Rounded pill button in the web style (.btn / .btn.pri)
final class Btn: UIButton {
  var onTap: (() -> Void)?
  let primary: Bool
  init(_ title: String, primary: Bool = false, small: Bool = false) {
    self.primary = primary
    super.init(frame: .zero)
    setTitle(title, for: .normal)
    titleLabel?.font = F.b(small ? 14 : 16)
    titleLabel?.adjustsFontSizeToFitWidth = true; titleLabel?.minimumScaleFactor = 0.6
    setTitleColor(primary ? .white : C.ink, for: .normal)
    setTitleColor(C.ink2.withAlphaComponent(0.5), for: .disabled)
    backgroundColor = primary ? C.roof : C.paper
    layer.borderColor = C.ink.cgColor; layer.borderWidth = 2
    layer.shadowColor = C.ink.cgColor; layer.shadowOpacity = 1; layer.shadowRadius = 0; layer.shadowOffset = CGSize(width: 0, height: 3)
    contentEdgeInsets = UIEdgeInsets(top: small ? 6 : 9, left: small ? 12 : 18, bottom: small ? 6 : 9, right: small ? 12 : 18)
    addTarget(self, action: #selector(tap), for: .touchUpInside)
    addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
    addTarget(self, action: #selector(up), for: [.touchCancel, .touchDragExit, .touchUpInside, .touchUpOutside])
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); layer.cornerRadius = bounds.height / 2 }
  @objc private func tap() { Haptic.tap(); onTap?() }
  @objc private func down() { transform = CGAffineTransform(translationX: 0, y: 2) }
  @objc private func up() { transform = .identity }
  override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.5 } }
}

/// Text with a small icon in front (img/ui icons replace the web's emoji/symbols)
@MainActor func iconText(_ icon: String?, _ text: String, font: UIFont, color: UIColor = C.ink, size: CGFloat? = nil) -> NSAttributedString {
  let out = NSMutableAttributedString()
  if let icon {
    let a = NSTextAttachment(); a.image = Art.ui(icon)
    let s = size ?? font.pointSize * 1.15
    a.bounds = CGRect(x: 0, y: (font.capHeight - s) / 2, width: s, height: s)
    out.append(NSAttributedString(attachment: a)); out.append(NSAttributedString(string: " "))
  }
  out.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
  return out
}

@MainActor func label(_ text: String, _ font: UIFont = F.r(15), _ color: UIColor = C.ink, lines: Int = 0, align: NSTextAlignment = .natural) -> UILabel {
  let l = UILabel(); l.text = text; l.font = font; l.textColor = color; l.numberOfLines = lines; l.textAlignment = align
  return l
}
@MainActor func hstack(_ v: [UIView], spacing: CGFloat = 6, align: UIStackView.Alignment = .center) -> UIStackView {
  let s = UIStackView(arrangedSubviews: v); s.axis = .horizontal; s.spacing = spacing; s.alignment = align; return s
}
@MainActor func vstack(_ v: [UIView], spacing: CGFloat = 6, align: UIStackView.Alignment = .fill) -> UIStackView {
  let s = UIStackView(arrangedSubviews: v); s.axis = .vertical; s.spacing = spacing; s.alignment = align; return s
}
@MainActor func faceView(_ id: String, _ size: CGFloat) -> UIImageView {
  let v = UIImageView(image: Art.face(id, size: size * UIScreen.main.scale, rim: 2 * UIScreen.main.scale))
  v.translatesAutoresizingMaskIntoConstraints = false
  v.widthAnchor.constraint(equalToConstant: size).isActive = true; v.heightAnchor.constraint(equalToConstant: size).isActive = true
  return v
}
@MainActor func iconView(_ name: String, _ size: CGFloat) -> UIImageView {
  let v = UIImageView(image: Art.ui(name)); v.contentMode = .scaleAspectFit
  v.translatesAutoresizingMaskIntoConstraints = false
  v.widthAnchor.constraint(equalToConstant: size).isActive = true; v.heightAnchor.constraint(equalToConstant: size).isActive = true
  return v
}

@MainActor enum Haptic {
  static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
  static func rumor() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
  static func event() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}

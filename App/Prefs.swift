// Settings, language and save slots.
// Five languages (繁中 / English / 日本語 / 한국어 / Español): picked from the device language (zh* → 繁中, ja/ko/es → that
// language, anything else → English); can be changed in Settings. All text comes from data.json (web i18n.js).
import Foundation
import GossipCore

final class Prefs {
  static let shared = Prefs()
  let d = UserDefaults.standard
  var lang: String {
    get { d.string(forKey: "lang") ?? Prefs.deviceLang() }
    set { d.set(newValue, forKey: "lang") }
  }
  var voice: Bool { get { d.object(forKey: "voice") as? Bool ?? true } set { d.set(newValue, forKey: "voice") } }
  var speed: Int { get { max(1, d.integer(forKey: "speed")) } set { d.set(newValue, forKey: "speed") } }
  var slot: Int { get { max(1, d.integer(forKey: "slot")) } set { d.set(newValue, forKey: "slot") } }
  var clientId: String {
    if let s = d.string(forKey: "cid") { return s }
    let s = String(UUID().uuidString.prefix(10)).lowercased(); d.set(s, forKey: "cid"); return s
  }
  static func deviceLang() -> String {
    let args = ProcessInfo.processInfo.arguments
    if let i = args.firstIndex(of: "-lang"), i + 1 < args.count { return args[i + 1] }
    for id in Locale.preferredLanguages {
      let l = id.lowercased()
      if l.hasPrefix("zh") { return "zh" }
      if l.hasPrefix("ja") { return "ja" }
      if l.hasPrefix("ko") { return "ko" }
      if l.hasPrefix("es") { return "es" }
      if l.hasPrefix("en") { return "en" }
    }
    return "en"
  }
}

var LANG: String { Prefs.shared.lang }
/// UI text (web i18n.js keys)
func T(_ key: String, _ p: [String: String] = [:]) -> String { GameData.shared.t(key, LANG, p) }
func nameOf(_ id: String) -> String { GameData.shared.nameOf(id, LANG) }
func fullName(_ id: String) -> String { GameData.shared.fullName(id, LANG) }
func placeName(_ id: String?) -> String { GameData.shared.placeName(id, LANG) }

/// 3 save slots (company rule): auto-save to the active slot, export / import .json, recent results.
struct Record: Codable { var day: Int; var type: String; var ok: Bool; var stars, reach, gen: Int; var at: Date }
final class Saves {
  static let shared = Saves()
  let dir: URL = {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("saves")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }()
  func url(_ n: Int) -> URL { dir.appendingPathComponent("slot\(n).json") }
  func load(_ n: Int = Prefs.shared.slot) -> Town? {
    guard let data = try? Data(contentsOf: url(n)) else { return nil }
    return try? JSONDecoder().decode(Town.self, from: data)
  }
  func save(_ town: Town, _ n: Int = Prefs.shared.slot) {
    if let data = try? JSONEncoder().encode(town) { try? data.write(to: url(n), options: .atomic) }
  }
  func delete(_ n: Int) { try? FileManager.default.removeItem(at: url(n)) }
  func savedAt(_ n: Int) -> Date? { (try? FileManager.default.attributesOfItem(atPath: url(n).path))?[.modificationDate] as? Date }
  var records: [Record] {
    get { (UserDefaults.standard.data(forKey: "records").flatMap { try? JSONDecoder().decode([Record].self, from: $0) }) ?? [] }
    set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.suffix(30))), forKey: "records") }
  }
  /// export file in the Documents folder (shared with the Files app) for the share sheet
  func exportFile(_ n: Int) -> URL? {
    guard let data = try? Data(contentsOf: url(n)) else { return nil }
    let f = FileManager.default.temporaryDirectory.appendingPathComponent("GossipTown-slot\(n).json")
    try? data.write(to: f)
    return f
  }
  func importFile(_ from: URL, into n: Int) -> Bool {
    let ok = from.startAccessingSecurityScopedResource()
    defer { if ok { from.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: from), (try? JSONDecoder().decode(Town.self, from: data)) != nil else { return false }
    return (try? data.write(to: url(n), options: .atomic)) != nil
  }
}

// Voice: the player speaks (Speech framework, on-device when the phone supports it; the text goes into the editable input box,
// never sent automatically) and residents talk (Worker /api/tts → Google voices by gender and age; if that is unavailable,
// the system voice with each resident's pitch and rate). Lines queue: the next one starts only when the previous one finished.
import AVFoundation
import Speech
import GossipCore

@MainActor
final class Voice: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
  static let shared = Voice()
  var cloud = false                       // Worker TTS available (set after Net.status)
  private var gen = 0                     // bumps on hush(): queued lines are dropped
  private var tail: Task<Void, Never>? = nil
  private var player: AVAudioPlayer?
  private var playDone: CheckedContinuation<Void, Never>?
  private let synth = AVSpeechSynthesizer()
  private var synthDone: CheckedContinuation<Void, Never>?
  private var clips: [String: Data] = [:]
  private var inflight: [String: Task<Data?, Never>] = [:]

  override init() {
    super.init()
    synth.delegate = self
    try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
  }

  static func clean(_ s: String) -> String {
    s.replacingOccurrences(of: "[（(][^）)]*[）)]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  private func key(_ text: String, _ who: String) -> String { "\(LANG)|\(who)|\(text)" }

  private func fetch(_ text: String, _ who: String) -> Task<Data?, Never> {
    let k = key(text, who), lang = LANG
    if let d = clips[k] { return Task { () -> Data? in d } }
    if let t = inflight[k] { return t }
    let t = Task { () -> Data? in
      var req = URLRequest(url: Net.base.appendingPathComponent("api/tts"))
      req.httpMethod = "POST"; req.timeoutInterval = 7
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "lang": lang, "who": who])
      guard let got = try? await Net.shared.session.data(for: req), let h = got.1 as? HTTPURLResponse, h.statusCode == 200,
            (h.value(forHTTPHeaderField: "X-TTS-Engine") ?? "") != "melotts", got.0.count > 500 else { return nil }
      return got.0
    }
    inflight[k] = t
    Task { let d = await t.value; self.inflight[k] = nil; if let d { self.clips[k] = d; if self.clips.count > 120 { self.clips.removeAll() } } }
    return t
  }
  /// get the next lines' audio ready while the current one plays
  func prefetch(_ text: String, _ who: String) {
    let t = Voice.clean(text)
    if cloud && Prefs.shared.voice && !t.isEmpty && GameData.shared.res[who] != nil { _ = fetch(t, who) }
  }

  /// Queue a line; returns when it has been spoken (or dropped by hush()).
  func speak(_ text: String, _ who: String) async {
    let t = Voice.clean(text)
    guard !t.isEmpty else { return }
    let my = gen, prev = tail
    let task = Task { @MainActor in
      await prev?.value
      guard my == self.gen else { return }
      if self.cloud, GameData.shared.res[who] != nil, let data = await self.fetch(t, who).value, my == self.gen, await self.play(data) { return }
      guard my == self.gen else { return }
      await self.system(t, who)
    }
    tail = task
    await task.value
  }
  private func play(_ data: Data) async -> Bool {
    guard let p = try? AVAudioPlayer(data: data) else { return false }
    player = p; p.delegate = self
    guard p.play() else { return false }
    let limit = p.duration + 2
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
      playDone = c
      Task { @MainActor [weak self] in try? await Task.sleep(nanoseconds: UInt64(limit * 1e9)); self?.finishPlay() }
    }
    return true
  }
  private func finishPlay() { let c = playDone; playDone = nil; c?.resume() }
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.finishPlay() } }

  private func system(_ text: String, _ who: String) async {
    let u = AVSpeechUtterance(string: text)
    let tag = (GameData.shared.raw["speechLang"] as? [String: String])?[LANG] ?? "en-US"
    u.voice = AVSpeechSynthesisVoice(language: tag)
    let v = GameData.shared.res[who]?.voice ?? [1, 1]
    u.pitchMultiplier = Float(min(2, max(0.5, v.first ?? 1)))
    u.rate = AVSpeechUtteranceDefaultSpeechRate * Float(min(1.3, max(0.8, v.count > 1 ? v[1] : 1)))
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
      synthDone = c
      synth.speak(u)
      let limit = 2 + Double(text.count) * 0.35
      Task { @MainActor [weak self] in try? await Task.sleep(nanoseconds: UInt64(limit * 1e9)); self?.finishSynth() }
    }
  }
  private func finishSynth() { let c = synthDone; synthDone = nil; c?.resume() }
  nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.finishSynth() } }
  nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.finishSynth() } }

  /// stop talking and drop everything queued
  func hush() {
    gen += 1
    player?.stop(); finishPlay()
    if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    finishSynth()
    tail = nil
  }

  // ── listening ──
  private let engine = AVAudioEngine()
  private var recog: SFSpeechRecognitionTask?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private(set) var listening = false
  var onDevice: Bool {
    let tag = (GameData.shared.raw["speechLang"] as? [String: String])?[LANG] ?? "en-US"
    return SFSpeechRecognizer(locale: Locale(identifier: tag))?.supportsOnDeviceRecognition ?? false
  }

  /// Ask for permission (first time), then listen. onText: partial text; onFinal: the final text (goes into the input box).
  func listen(onText: @escaping (String) -> Void, onFinal: @escaping (String) -> Void, onEnd: @escaping () -> Void, onError: @escaping (String) -> Void) {
    SFSpeechRecognizer.requestAuthorization { st in
      AVAudioSession.sharedInstance().requestRecordPermission { mic in
        Task { @MainActor in
          guard st == .authorized, mic else { onError("not-allowed"); onEnd(); return }
          self.start(onText: onText, onFinal: onFinal, onEnd: onEnd, onError: onError)
        }
      }
    }
  }
  private func start(onText: @escaping (String) -> Void, onFinal: @escaping (String) -> Void, onEnd: @escaping () -> Void, onError: @escaping (String) -> Void) {
    hush()
    let tag = (GameData.shared.raw["speechLang"] as? [String: String])?[LANG] ?? "en-US"
    guard let rec = SFSpeechRecognizer(locale: Locale(identifier: tag)), rec.isAvailable else { onError("na"); onEnd(); return }
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
    request = req
    let input = engine.inputNode
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
    engine.prepare()
    do { try engine.start() } catch { onError("na"); onEnd(); return }
    listening = true
    let box = ListenBox()
    let finish: @MainActor () -> Void = { [weak self] in
      guard let self, !box.ended else { return }
      box.ended = true; box.finish = nil
      self.stopEngine()
      if !box.last.isEmpty { onFinal(box.last) }
      onEnd()
    }
    box.finish = finish
    recog = rec.recognitionTask(with: req) { [weak self] res, err in
      let text = res?.bestTranscription.formattedString, isFinal = res?.isFinal ?? false, failed = err != nil
      Task { @MainActor in
        if let text {
          box.last = text
          onText(text)
          if isFinal { box.finish?(); return }
          self?.armStop(1.6, box)          // a short pause ends it
        }
        if failed { box.finish?() }
      }
    }
    armStop(12, box)
  }
  private func armStop(_ s: Double, _ box: ListenBox) {
    box.timer += 1
    let my = box.timer
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(s * 1e9))
      if my == box.timer { box.finish?() }
    }
  }
  func stop() { request?.endAudio() }
  private func stopEngine() {
    if engine.isRunning { engine.stop() }
    engine.inputNode.removeTap(onBus: 0)
    request?.endAudio(); recog?.cancel(); recog = nil; request = nil
    listening = false
  }
}

/// state of one listening session (shared between the recognizer callback and the timers)
@MainActor final class ListenBox {
  var last = ""
  var ended = false
  var timer = 0
  var finish: (@MainActor () -> Void)?
}

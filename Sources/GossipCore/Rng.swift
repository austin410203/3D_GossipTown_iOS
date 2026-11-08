// Random numbers and the JavaScript semantics the port depends on (sim.js runs in V8; this must match it exactly).
import Foundation

/// mulberry32 — identical to `rng()` in sim.js.
public final class Mulberry {
  var a: UInt32
  public init(_ seed: UInt32) { a = seed }
  /// `rng(seed)` takes `seed >>> 0`; seeds here are non-negative doubles below 2^53
  public convenience init(js seed: Double) { self.init(UInt32(truncatingIfNeeded: Int64(seed))) }
  public func next() -> Double {
    a = a &+ 0x6D2B79F5
    var t = a
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4294967296
  }
  @inline(__always) public func callAsFunction() -> Double { next() }
}

@inline(__always) func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : v > b ? b : v }
@inline(__always) func clampI(_ v: Int, _ a: Int, _ b: Int) -> Int { v < a ? a : v > b ? b : v }
/// Math.round
@inline(__always) func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }
/// Math.floor(r() * n)
@inline(__always) func jsFloor(_ v: Double) -> Int { Int(v.rounded(.down)) }

/// `arr.sort(() => r() - .5)` exactly as V8 runs it for short arrays (< 64): TimSort's CountAndMakeRun (finds the first
/// ascending / strictly descending run, reverses a descending one), then binary insertion for the rest.
/// Checked against Node 22 for n = 2…12 (199/199 seeds each); plain binary insertion only matches n = 2.
func v8RandomSort<T>(_ input: [T], _ r: Mulberry) -> [T] {
  var a = input
  let n = a.count
  if n < 2 { return a }
  var run = 2
  let desc = r() - 0.5 < 0
  var i = 2
  while i < n {
    let order = r() - 0.5
    if desc ? order >= 0 : order < 0 { break }
    run += 1; i += 1
  }
  if desc { a.replaceSubrange(0..<run, with: a[0..<run].reversed()) }
  var start = run
  while start < n {
    var left = 0, right = start
    let pivot = a[start]
    while left < right {
      let mid = left + ((right - left) >> 1)
      if r() - 0.5 < 0 { right = mid } else { left = mid + 1 }
    }
    var p = start
    while p > left { a[p] = a[p - 1]; p -= 1 }
    a[left] = pivot
    start += 1
  }
  return a
}

extension Array {
  /// Array.prototype.sort with a numeric comparator — stable, like V8's TimSort.
  func jsSorted(_ cmp: (Element, Element) -> Double) -> [Element] {
    enumerated().sorted { x, y in
      let c = cmp(x.element, y.element)
      return c < 0 || (c == 0 && x.offset < y.offset)
    }.map(\.element)
  }
}

/// lines.js `hash()`: `h = (h * 31 + codePoint) | 0` over code points
public func jsHash(_ s: String) -> Int {
  var h: Int32 = 7
  for u in s.unicodeScalars { h = h &* 31 &+ Int32(bitPattern: u.value) }
  return Int(h)
}
/// JS `String(number)` for the small numbers the game logs (8, 8.5, -12)
public func jsNum(_ v: Double) -> String { v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v) }

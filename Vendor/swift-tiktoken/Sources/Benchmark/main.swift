/// Performance benchmarks for SwiftTiktoken.
///
/// This executable provides performance measurements to compare against tiktoken (Python/Rust).
/// Run with:
///
///     swift run -c release Benchmark
///
/// Results on Apple M3:
///     cl100k_base:
///       Basic encode (1000x):     16.64ms   (Python: 12.76ms, 1.3x slower)
///       Medium encode (100x):     32.27ms   (Python: 4.32ms, 7.5x slower)
///       Large encode (10x):       31.78ms   (Python: 4.06ms, 7.8x slower)
///       Catastrophic (6 chars):   225.79ms  (Python: 85.19ms, 2.7x slower)
///       Decode (100x):            0.29ms    (Python: 0.30ms, ~same)
///       Single token RT (1000):   0.15ms    (Python: 0.89ms, 6x faster!)
///       Batch encode (10x100):    25.31ms   (Python: 21.47ms, 1.2x slower)
///
/// Performance notes:
/// - The main bottleneck is Swift's Regex being slower than Rust's regex crate
/// - Decode performance matches Python/Rust
/// - Single token operations are actually faster in Swift
/// - For maximum throughput on large texts, consider using tiktoken via FFI

import Foundation
import SwiftTiktoken

/// Simple benchmark helper
func benchmark(_: String, iterations: Int = 1, _ block: () -> Void) -> Double {
  let start = CFAbsoluteTimeGetCurrent()
  for _ in 0 ..< iterations {
    block()
  }
  let elapsed = CFAbsoluteTimeGetCurrent() - start
  return elapsed
}

@main
struct Benchmark {
  static func main() async throws {
    let encodingNames = ["cl100k_base", "r50k_base", "p50k_base", "o200k_base"]

    print(String(repeating: "=", count: 60))
    print("SWIFTTIKTOKEN BENCHMARKS")
    print(String(repeating: "=", count: 60))

    for encName in encodingNames {
      let enc = try await CoreBPE.loadEncoding(named: encName)
      print("\n\(encName):")
      print(String(repeating: "-", count: 40))

      // 1. Basic encoding - 1000 iterations of short text
      let text = "The quick brown fox jumps over the lazy dog."
      var elapsed = benchmark("Basic encode (1000x short)", iterations: 1000) {
        _ = try! enc.encodeOrdinary(text: text)
      }
      print(String(format: "  Basic encode (1000x):     %.2fms", elapsed * 1000))

      // 2. Medium text - ~1000 tokens worth
      let mediumText = String(repeating: text, count: 25)
      elapsed = benchmark("Medium encode", iterations: 100) {
        _ = try! enc.encodeOrdinary(text: mediumText)
      }
      print(String(format: "  Medium encode (100x):     %.2fms", elapsed * 1000))

      // 3. Large text - ~10000 tokens worth
      let largeText = String(repeating: text, count: 250)
      elapsed = benchmark("Large encode", iterations: 10) {
        _ = try! enc.encodeOrdinary(text: largeText)
      }
      print(String(format: "  Large encode (10x):       %.2fms", elapsed * 1000))

      // 4. Catastrophically repetitive input
      let testChars = ["^", "0", "a", "'s", " ", "\n"]
      var total: Double = 0
      for c in testChars {
        let bigValue = String(repeating: c, count: 10000)
        elapsed = benchmark("Repetitive \(c)", iterations: 1) {
          _ = try! enc.encodeOrdinary(text: bigValue)
        }
        total += elapsed
      }
      print(String(format: "  Catastrophic (6 chars):   %.2fms", total * 1000))

      // 5. Decode
      let tokens = try! enc.encodeOrdinary(text: mediumText)
      elapsed = benchmark("Decode", iterations: 100) {
        _ = try? enc.decode(tokens: tokens)
      }
      print(String(format: "  Decode (100x):            %.2fms", elapsed * 1000))

      // 6. Single token roundtrip (first 1000 tokens)
      elapsed = benchmark("Single token RT", iterations: 1) {
        for t: Rank in 0 ..< 1000 {
          if let bytes = try? enc.decodeSingleTokenBytes(token: t) {
            _ = try? enc.encodeSingleToken(piece: bytes)
          }
        }
      }
      print(String(format: "  Single token RT (1000):   %.2fms", elapsed * 1000))

      // 7. Batch encode
      let texts = Array(repeating: text, count: 100)
      elapsed = benchmark("Batch encode", iterations: 10) {
        // Using .none since benchmark text has no special tokens
        _ = try? enc.encodeBatchSync(texts, disallowedSpecial: .none)
      }
      print(String(format: "  Batch encode (10x100):    %.2fms", elapsed * 1000))
    }

    print("\n" + String(repeating: "=", count: 60))
  }
}

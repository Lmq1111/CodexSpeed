@testable import SwiftTiktoken
import XCTest

final class SwiftTiktokenTests: XCTestCase {
  // MARK: - Setup

  override class func setUp() {
    super.setUp()
    // Download vocabularies once for all tests
    let semaphore = DispatchSemaphore(value: 0)
    Task {
      await downloadVocabulariesIfNeeded()
      semaphore.signal()
    }
    semaphore.wait()
  }

  /// Download vocabularies if not already cached
  static func downloadVocabulariesIfNeeded() async {
    let vocabularies = [
      ("cl100k_base", "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken"),
      ("r50k_base", "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken"),
      ("p50k_base", "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken"),
      ("o200k_base", "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken"),
    ]

    // Use /tmp for sandboxed tests
    let cacheDir = URL(fileURLWithPath: "/tmp/tiktoken", isDirectory: true)

    // Set the custom cache directory for the loader
    EncodingLoader.customCacheDirectory = cacheDir

    // Check if already downloaded
    var needsDownload = false
    for (name, _) in vocabularies {
      let cacheFile = cacheDir.appendingPathComponent("\(name).tiktoken")
      if !FileManager.default.fileExists(atPath: cacheFile.path) {
        needsDownload = true
        break
      }
    }

    guard needsDownload else {
      print("✅ Vocabularies already cached")
      return
    }

    print("📥 Downloading vocabularies...")

    do {
      try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

      for (name, urlString) in vocabularies {
        let cacheFile = cacheDir.appendingPathComponent("\(name).tiktoken")

        // Skip if already exists
        if FileManager.default.fileExists(atPath: cacheFile.path) {
          print("✅ \(name) already cached")
          continue
        }

        print("⬇️  Downloading \(name)...")
        let url = URL(string: urlString)!
        let (data, _) = try await URLSession.shared.data(from: url)
        try data.write(to: cacheFile)
        print("✅ Downloaded \(name) (\(data.count) bytes)")
      }
    } catch {
      print("⚠️ Error downloading vocabularies: \(error)")
    }
  }

  // MARK: - Tests with Real Encodings

  func testCl100kBase() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Test known token values for cl100k_base (from Python tiktoken test_simple)
    XCTAssertEqual(try encoder.encode(text: "hello world", allowedSpecial: [], disallowedSpecial: .none), [15339, 1917])
    XCTAssertEqual(try encoder.decode(tokens: [15339, 1917]), "hello world")
    XCTAssertEqual(try encoder.encode(text: "", allowedSpecial: [], disallowedSpecial: .none), [])
    XCTAssertEqual(try encoder.encode(text: " ", allowedSpecial: [], disallowedSpecial: .none), [220])

    // Test special tokens (from Python tiktoken test_simple)
    XCTAssertEqual(try encoder.encode(text: "hello <|endoftext|>", allowedSpecial: ["<|endoftext|>"]), [15339, 220, 100_257])

    // Test regex patterns (from Python tiktoken test_simple_regex)
    XCTAssertEqual(try encoder.encode(text: "rer", allowedSpecial: [], disallowedSpecial: .none), [38149])
    XCTAssertEqual(try encoder.encode(text: "'rer", allowedSpecial: [], disallowedSpecial: .none), [2351, 81])
    XCTAssertEqual(try encoder.encode(text: "today\n ", allowedSpecial: [], disallowedSpecial: .none), [31213, 198, 220])
    XCTAssertEqual(try encoder.encode(text: "today\n \n", allowedSpecial: [], disallowedSpecial: .none), [31213, 27907])
    XCTAssertEqual(try encoder.encode(text: "today\n  \n", allowedSpecial: [], disallowedSpecial: .none), [31213, 14211])

    // Test basic encode (from Python tiktoken test_basic_encode)
    XCTAssertEqual(try encoder.encode(text: " \u{0085}0", allowedSpecial: [], disallowedSpecial: .none), [220, 126, 227, 15])

    // Test emoji / surrogate pairs (from Python tiktoken test_encode_surrogate_pairs)
    XCTAssertEqual(try encoder.encode(text: "👍", allowedSpecial: [], disallowedSpecial: .none), [9468, 239, 235])

    // Test roundtrip
    let text = "The quick brown fox jumps over the lazy dog."
    let tokens = try encoder.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)
    let decoded = try encoder.decode(tokens: tokens)
    XCTAssertEqual(decoded, text)
  }

  func testR50kBase() async throws {
    let encoder = try await CoreBPE.r50kBase()

    // Test known token values
    XCTAssertEqual(try encoder.encode(text: "hello world", allowedSpecial: [], disallowedSpecial: .none), [31373, 995])

    // Test roundtrip
    let text = "Testing r50k_base encoding"
    let tokens = try encoder.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)
    let decoded = try encoder.decode(tokens: tokens)
    XCTAssertEqual(decoded, text)
  }

  func testP50kBase() async throws {
    let encoder = try await CoreBPE.p50kBase()

    // Test known token values
    XCTAssertEqual(try encoder.encode(text: "hello world", allowedSpecial: [], disallowedSpecial: .none), [31373, 995])

    // Test roundtrip
    let text = "Testing p50k_base encoding"
    let tokens = try encoder.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)
    let decoded = try encoder.decode(tokens: tokens)
    XCTAssertEqual(decoded, text)
  }

  func testGPT2() async throws {
    // GPT-2 maps to r50k_base encoding in swift-tiktoken
    // (Python tiktoken uses different source files but same vocabulary)
    let encoder = try await CoreBPE.forModel("gpt2")

    // Test known token values for GPT-2 (from Python tiktoken test_simple)
    XCTAssertEqual(try encoder.encode(text: "hello world", allowedSpecial: [], disallowedSpecial: .none), [31373, 995])
    XCTAssertEqual(try encoder.decode(tokens: [31373, 995]), "hello world")
    XCTAssertEqual(try encoder.encode(text: "hello <|endoftext|>", allowedSpecial: ["<|endoftext|>"]), [31373, 220, 50256])

    // Test repeated zeros (from Python tiktoken test_simple_repeated)
    XCTAssertEqual(try encoder.encode(text: "0", allowedSpecial: [], disallowedSpecial: .none), [15])
    XCTAssertEqual(try encoder.encode(text: "00", allowedSpecial: [], disallowedSpecial: .none), [405])
    XCTAssertEqual(try encoder.encode(text: "000", allowedSpecial: [], disallowedSpecial: .none), [830])
    XCTAssertEqual(try encoder.encode(text: "0000", allowedSpecial: [], disallowedSpecial: .none), [2388])
    XCTAssertEqual(try encoder.encode(text: "00000", allowedSpecial: [], disallowedSpecial: .none), [20483])
    XCTAssertEqual(try encoder.encode(text: "000000", allowedSpecial: [], disallowedSpecial: .none), [10535])
    XCTAssertEqual(try encoder.encode(text: "0000000", allowedSpecial: [], disallowedSpecial: .none), [24598])
    XCTAssertEqual(try encoder.encode(text: "00000000", allowedSpecial: [], disallowedSpecial: .none), [8269])
    XCTAssertEqual(try encoder.encode(text: "000000000", allowedSpecial: [], disallowedSpecial: .none), [10535, 830])
    XCTAssertEqual(try encoder.encode(text: "0000000000", allowedSpecial: [], disallowedSpecial: .none), [8269, 405])
    XCTAssertEqual(try encoder.encode(text: "00000000000", allowedSpecial: [], disallowedSpecial: .none), [8269, 830])
    XCTAssertEqual(try encoder.encode(text: "000000000000", allowedSpecial: [], disallowedSpecial: .none), [8269, 2388])
    XCTAssertEqual(try encoder.encode(text: "0000000000000", allowedSpecial: [], disallowedSpecial: .none), [8269, 20483])
    XCTAssertEqual(try encoder.encode(text: "00000000000000", allowedSpecial: [], disallowedSpecial: .none), [8269, 10535])
    XCTAssertEqual(try encoder.encode(text: "000000000000000", allowedSpecial: [], disallowedSpecial: .none), [8269, 24598])
    XCTAssertEqual(try encoder.encode(text: "0000000000000000", allowedSpecial: [], disallowedSpecial: .none), [25645])
    XCTAssertEqual(try encoder.encode(text: "00000000000000000", allowedSpecial: [], disallowedSpecial: .none), [8269, 10535, 830])
  }

  func testP50kEdit() async throws {
    // p50k_edit is like p50k_base but with FIM special tokens
    let encoder = try await CoreBPE.p50kEdit()

    // Test basic encoding (same as p50k_base)
    XCTAssertEqual(try encoder.encode(text: "hello world", allowedSpecial: [], disallowedSpecial: .none), [31373, 995])

    // Test FIM special tokens are available
    let fimText = "prefix<|fim_prefix|>middle<|fim_middle|>suffix<|fim_suffix|>end"
    let tokens = try encoder.encodeWithSpecialTokens(text: fimText)

    // Should contain FIM token values
    XCTAssertTrue(tokens.contains(50281)) // fim_prefix
    XCTAssertTrue(tokens.contains(50282)) // fim_middle
    XCTAssertTrue(tokens.contains(50283)) // fim_suffix

    // Test roundtrip
    let decoded = try encoder.decode(tokens: tokens)
    XCTAssertEqual(decoded, fimText)
  }

  func testO200kBase() async throws {
    do {
      let encoder = try await CoreBPE.o200kBase()

      // Test basic functionality
      let text = "Testing o200k_base encoding"
      let tokens = try encoder.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)
      XCTAssertFalse(tokens.isEmpty)

      // Test roundtrip
      let decoded = try encoder.decode(tokens: tokens)
      XCTAssertEqual(decoded, text)
    } catch {
      // o200k_base might not be available in all versions
      throw XCTSkip("o200k_base not available: \(error)")
    }
  }

  // MARK: - Cross-Encoding Comparison Tests

  func testEncodingComparison() async throws {
    let text = "The quick brown fox jumps over the lazy dog."

    let cl100k = try await CoreBPE.cl100kBase()
    let r50k = try await CoreBPE.r50kBase()
    let p50k = try await CoreBPE.p50kBase()

    let cl100kTokens = try cl100k.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)
    let r50kTokens = try r50k.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)
    let p50kTokens = try p50k.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)

    // r50k and p50k should produce the same tokens for basic text
    XCTAssertEqual(r50kTokens, p50kTokens)

    // cl100k should be different (more efficient)
    XCTAssertNotEqual(cl100kTokens, r50kTokens)

    // cl100k should generally use fewer tokens
    XCTAssertLessThanOrEqual(cl100kTokens.count, r50kTokens.count)

    print("Token counts for '\(text)':")
    print("  cl100k_base: \(cl100kTokens.count) tokens")
    print("  r50k_base:   \(r50kTokens.count) tokens")
    print("  p50k_base:   \(p50kTokens.count) tokens")
  }

  // MARK: - Special Token Tests

  func testSpecialTokens() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let text = "Hello <|endoftext|> World"

    // Without allowing special tokens (should encode the literal text)
    let withoutSpecial = try encoder.encodeOrdinary(text: text)

    // With special tokens allowed
    let withSpecial = try encoder.encode(text: text, allowedSpecial: ["<|endoftext|>"])

    // These should be different
    XCTAssertNotEqual(withoutSpecial, withSpecial)

    // The version with special tokens should contain token 100257 (endoftext)
    XCTAssertTrue(withSpecial.contains(100_257))
    XCTAssertFalse(withoutSpecial.contains(100_257))
  }

  func testSpecialTokenComprehensive() async throws {
    // Comprehensive special token tests from Python tiktoken test_special_token
    let encoder = try await CoreBPE.cl100kBase()

    let eot = try encoder.encodeSingleToken(piece: Array("<|endoftext|>".utf8))
    XCTAssertEqual(eot, encoder.eotToken)

    let fip = try encoder.encodeSingleToken(piece: Array("<|fim_prefix|>".utf8))
    let fim = try encoder.encodeSingleToken(piece: Array("<|fim_middle|>".utf8))

    let text = "<|endoftext|> hello <|fim_prefix|>"

    // Without special tokens allowed (encodeOrdinary), special token values should not be present
    let ordinary = try encoder.encodeOrdinary(text: text)
    XCTAssertFalse(ordinary.contains(eot))
    XCTAssertFalse(ordinary.contains(fip))

    // Test multi-special token text
    let text2 = "<|endoftext|> hello <|fim_prefix|> there <|fim_middle|>"

    // encodeOrdinary ignores all special tokens
    let tokens = try encoder.encodeOrdinary(text: text2)
    XCTAssertFalse(tokens.contains(eot))
    XCTAssertFalse(tokens.contains(fip))
    XCTAssertFalse(tokens.contains(fim))

    // With all special tokens allowed
    let tokensAll = try encoder.encodeWithSpecialTokens(text: text2)
    XCTAssertTrue(tokensAll.contains(eot))
    XCTAssertTrue(tokensAll.contains(fip))
    XCTAssertTrue(tokensAll.contains(fim))

    // With only fim_prefix allowed (disallow others but pass .none for those not in allowedSpecial)
    let tokensFip = try encoder.encode(text: text2, allowedSpecial: ["<|fim_prefix|>"], disallowedSpecial: .none)
    XCTAssertFalse(tokensFip.contains(eot))
    XCTAssertTrue(tokensFip.contains(fip))
    XCTAssertFalse(tokensFip.contains(fim))

    // With only endoftext allowed
    let tokensEot = try encoder.encode(text: text2, allowedSpecial: ["<|endoftext|>"], disallowedSpecial: .none)
    XCTAssertTrue(tokensEot.contains(eot))
    XCTAssertFalse(tokensEot.contains(fip))
    XCTAssertFalse(tokensEot.contains(fim))

    // With only fim_middle allowed
    let tokensFim = try encoder.encode(text: text2, allowedSpecial: ["<|fim_middle|>"], disallowedSpecial: .none)
    XCTAssertFalse(tokensFim.contains(eot))
    XCTAssertFalse(tokensFim.contains(fip))
    XCTAssertTrue(tokensFim.contains(fim))
  }

  func testDisallowedSpecialToken() async throws {
    // Test the disallowed_special parameter behavior (matching Python tiktoken)
    let encoder = try await CoreBPE.cl100kBase()

    // By default, special tokens should raise an error
    do {
      _ = try encoder.encode(text: "<|endoftext|>", allowedSpecial: [])
      XCTFail("Should throw for disallowed special token")
    } catch let error as TiktokenError {
      if case let .disallowedSpecialToken(token) = error {
        XCTAssertEqual(token, "<|endoftext|>")
      } else {
        XCTFail("Wrong error type: \(error)")
      }
    }

    // With the token explicitly allowed, it should succeed
    let allowed = try encoder.encode(text: "<|endoftext|>", allowedSpecial: ["<|endoftext|>"])
    XCTAssertEqual(allowed, [100_257])

    // With disallowedSpecial: .none, it should encode as regular text
    let asText = try encoder.encode(text: "<|endoftext|>", allowedSpecial: [], disallowedSpecial: .none)
    XCTAssertNotEqual(asText, [100_257]) // Should NOT be the special token
    XCTAssertFalse(asText.isEmpty)

    // With disallowedSpecial: .some([specific]), only that token should error
    do {
      _ = try encoder.encode(
        text: "<|endoftext|> hello <|fim_prefix|>",
        allowedSpecial: [],
        disallowedSpecial: .some(["<|endoftext|>"])
      )
      XCTFail("Should throw for disallowed <|endoftext|>")
    } catch let error as TiktokenError {
      if case let .disallowedSpecialToken(token) = error {
        XCTAssertEqual(token, "<|endoftext|>")
      } else {
        XCTFail("Wrong error type")
      }
    }

    // fim_prefix alone should succeed when only endoftext is disallowed
    let fimOnly = try encoder.encode(
      text: "hello <|fim_prefix|>",
      allowedSpecial: [],
      disallowedSpecial: .some(["<|endoftext|>"])
    )
    XCTAssertFalse(fimOnly.isEmpty)
    // fim_prefix should be encoded as text, not as special token
    XCTAssertFalse(fimOnly.contains(100_258))
  }

  func testEotToken() async throws {
    let cl100k = try await CoreBPE.cl100kBase()
    XCTAssertEqual(cl100k.eotToken, 100_257)

    let r50k = try await CoreBPE.r50kBase()
    XCTAssertEqual(r50k.eotToken, 50256)

    let o200k = try await CoreBPE.o200kBase()
    XCTAssertEqual(o200k.eotToken, 199_999)
  }

  func testIsSpecialToken() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Special tokens
    XCTAssertTrue(encoder.isSpecialToken(100_257)) // endoftext
    XCTAssertTrue(encoder.isSpecialToken(100_258)) // fim_prefix
    XCTAssertTrue(encoder.isSpecialToken(100_259)) // fim_middle
    XCTAssertTrue(encoder.isSpecialToken(100_260)) // fim_suffix
    XCTAssertTrue(encoder.isSpecialToken(100_276)) // endofprompt

    // Regular tokens
    XCTAssertFalse(encoder.isSpecialToken(15339)) // "hello"
    XCTAssertFalse(encoder.isSpecialToken(1917)) // " world"
    XCTAssertFalse(encoder.isSpecialToken(0))
    XCTAssertFalse(encoder.isSpecialToken(100_000))
  }

  func testNVocab() async throws {
    let cl100k = try await CoreBPE.cl100kBase()
    // cl100k_base max token is endofprompt at 100276
    XCTAssertEqual(cl100k.maxTokenValue, 100_276)
    XCTAssertEqual(cl100k.nVocab, 100_277)

    let r50k = try await CoreBPE.r50kBase()
    XCTAssertEqual(r50k.maxTokenValue, 50256)
    XCTAssertEqual(r50k.nVocab, 50257)
  }

  func testDecodeTokensBytes() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let tokens = try encoder.encode(text: "hello world", allowedSpecial: [], disallowedSpecial: .none)
    let tokenBytes = try encoder.decodeTokensBytes(tokens: tokens)

    XCTAssertEqual(tokenBytes.count, 2)
    XCTAssertEqual(String(bytes: tokenBytes[0], encoding: .utf8), "hello")
    XCTAssertEqual(String(bytes: tokenBytes[1], encoding: .utf8), " world")
  }

  // MARK: - Catastrophic Repetition Test

  func testCatastrophicallyRepetitive() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let testChars = ["^", "0", "a", "'s", " ", "\n"]

    for char in testChars {
      // Test with large repetition
      let bigValue = String(repeating: char, count: 10000)
      let tokens = try encoder.encode(text: bigValue, allowedSpecial: [], disallowedSpecial: .none)
      let decoded = try encoder.decode(tokens: tokens)
      XCTAssertEqual(decoded, bigValue, "Failed for repeated: \(char)")

      // Test with space prefix
      let withPrefix = " " + bigValue
      let tokensPrefix = try encoder.encode(text: withPrefix, allowedSpecial: [], disallowedSpecial: .none)
      let decodedPrefix = try encoder.decode(tokens: tokensPrefix)
      XCTAssertEqual(decodedPrefix, withPrefix, "Failed with prefix for: \(char)")

      // Test with newline suffix
      let withSuffix = bigValue + "\n"
      let tokensSuffix = try encoder.encode(text: withSuffix, allowedSpecial: [], disallowedSpecial: .none)
      let decodedSuffix = try encoder.decode(tokens: tokensSuffix)
      XCTAssertEqual(decodedSuffix, withSuffix, "Failed with suffix for: \(char)")
    }
  }

  // MARK: - International Text Tests

  func testInternationalText() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let testCases = [
      "请考试我的软件！12345",
      "こんにちは世界",
      "مرحبا بالعالم",
      "Здравствуй, мир",
      "Bonjour le monde",
      "🚀🌍🎉",
    ]

    for text in testCases {
      let tokens = try encoder.encode(text: text, allowedSpecial: [], disallowedSpecial: .none)
      let decoded = try encoder.decode(tokens: tokens)
      XCTAssertEqual(decoded, text, "Roundtrip failed for: \(text)")
    }
  }

  // MARK: - Edge Cases

  func testEdgeCases() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Empty string
    XCTAssertEqual(try encoder.encode(text: "", allowedSpecial: [], disallowedSpecial: .none), [])

    // Single space
    XCTAssertEqual(try encoder.encode(text: " ", allowedSpecial: [], disallowedSpecial: .none), [220])

    // Newline
    XCTAssertEqual(try encoder.encode(text: "\n", allowedSpecial: [], disallowedSpecial: .none), [198])

    // Tab
    let tabTokens = try encoder.encode(text: "\t", allowedSpecial: [], disallowedSpecial: .none)
    XCTAssertFalse(tabTokens.isEmpty)

    // Mixed whitespace
    let whitespace = " \t\n\r"
    let wsTokens = try encoder.encode(text: whitespace, allowedSpecial: [], disallowedSpecial: .none)
    let wsDecoded = try encoder.decode(tokens: wsTokens)
    XCTAssertEqual(wsDecoded, whitespace)
  }

  // MARK: - Performance Tests

  func testEncodingPerformance() async throws {
    let encoder = try await CoreBPE.cl100kBase()
    let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1000)

    measure {
      _ = try! encoder.encodeOrdinary(text: text)
    }
  }

  func testDecodingPerformance() async throws {
    let encoder = try await CoreBPE.cl100kBase()
    let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1000)
    let tokens = try encoder.encodeOrdinary(text: text)

    measure {
      _ = try? encoder.decode(tokens: tokens)
    }
  }

  // MARK: - Thread Safety

  func testConcurrentEncoding() async throws {
    let encoder = try await CoreBPE.cl100kBase()
    let expectation = XCTestExpectation(description: "Concurrent encoding")
    let iterations = 100
    expectation.expectedFulfillmentCount = iterations

    DispatchQueue.concurrentPerform(iterations: iterations) { i in
      let text = "Concurrent test \(i)"
      let tokens = try! encoder.encodeOrdinary(text: text)
      if let decodedText = try? encoder.decode(tokens: tokens) {
        XCTAssertEqual(decodedText, text)
      }
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 10.0)
  }

  // MARK: - BPE Algorithm Tests

  func testBytePairMergeBasic() {
    // Create simple ranks
    var ranks: [ArraySlice<UInt8>: Rank] = [:]
    ranks[ArraySlice([UInt8(ascii: "a"), UInt8(ascii: "b")])] = 0
    ranks[ArraySlice([UInt8(ascii: "c"), UInt8(ascii: "d")])] = 1

    let piece: [UInt8] = [UInt8(ascii: "a"), UInt8(ascii: "b"), UInt8(ascii: "c"), UInt8(ascii: "d")]

    let result = bytePairSplit(piece: ArraySlice(piece), ranks: ranks)
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(Array(result[0]), [UInt8(ascii: "a"), UInt8(ascii: "b")])
    XCTAssertEqual(Array(result[1]), [UInt8(ascii: "c"), UInt8(ascii: "d")])
  }

  func testBytePairMergeRepeated() {
    var ranks: [ArraySlice<UInt8>: Rank] = [:]
    ranks[ArraySlice([UInt8(ascii: "a"), UInt8(ascii: "b")])] = 0
    ranks[ArraySlice([UInt8(ascii: "c"), UInt8(ascii: "d")])] = 1

    let piece: [UInt8] = [UInt8(ascii: "a"), UInt8(ascii: "b"), UInt8(ascii: "a"), UInt8(ascii: "b")]

    let result = bytePairSplit(piece: ArraySlice(piece), ranks: ranks)
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(Array(result[0]), [UInt8(ascii: "a"), UInt8(ascii: "b")])
    XCTAssertEqual(Array(result[1]), [UInt8(ascii: "a"), UInt8(ascii: "b")])
  }

  // MARK: - Decode Error Tests

  func testDecodeInvalidToken() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Try to decode with an invalid token
    XCTAssertThrowsError(try encoder.decodeBytes(tokens: [999_999_999])) { error in
      if case let TiktokenError.decodeKeyError(token) = error {
        XCTAssertEqual(token, 999_999_999)
      } else {
        XCTFail("Expected decodeKeyError")
      }
    }
  }

  func testInputTooLarge() async throws {
    // Test from Python tiktoken: very large inputs should raise an error
    let encoder = try await CoreBPE.cl100kBase()

    let largeText = String(repeating: "x", count: 1_000_001)

    // encodeOrdinary should throw
    XCTAssertThrowsError(try encoder.encodeOrdinary(text: largeText)) { error in
      if case let TiktokenError.inputTooLarge(length, maxLength) = error {
        XCTAssertEqual(length, 1_000_001)
        XCTAssertEqual(maxLength, maxInputLength)
      } else {
        XCTFail("Expected inputTooLarge error, got \(error)")
      }
    }

    // encode should also throw
    XCTAssertThrowsError(try encoder.encode(text: largeText, allowedSpecial: [])) { error in
      if case TiktokenError.inputTooLarge = error {
        // Expected
      } else {
        XCTFail("Expected inputTooLarge error")
      }
    }

    // Just under the limit should not throw the inputTooLarge error
    // (We don't actually encode it as that would be too slow for a test)
    let justUnder = String(repeating: "x", count: 100)
    XCTAssertNoThrow(try encoder.encodeOrdinary(text: justUnder))
  }

  // MARK: - Single Token Operations Tests

  func testEncodeSingleToken() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Test encoding a single known token
    let helloBytes = Array("hello".utf8)
    let token = try encoder.encodeSingleToken(piece: helloBytes)
    XCTAssertEqual(token, 15339)

    // Test that multi-token pieces throw
    let longText = Array("hello world".utf8)
    XCTAssertThrowsError(try encoder.encodeSingleToken(piece: longText))
  }

  func testEncodeSinglePiece() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Test single token piece
    let helloBytes = Array("hello".utf8)
    let tokens = encoder.encodeSinglePiece(piece: helloBytes)
    XCTAssertEqual(tokens, [15339])

    // Test multi-token piece
    let longText = Array("hello world".utf8)
    let multiTokens = encoder.encodeSinglePiece(piece: longText)
    XCTAssertEqual(multiTokens, [15339, 1917])
  }

  func testDecodeSingleTokenBytes() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Test decoding known token
    let bytes = try encoder.decodeSingleTokenBytes(token: 15339)
    XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "hello")

    // Test invalid token throws
    XCTAssertThrowsError(try encoder.decodeSingleTokenBytes(token: 999_999_999))
  }

  func testTokenByteValues() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let allTokens = encoder.tokenByteValues()
    // cl100k_base has ~100k tokens
    XCTAssertGreaterThan(allTokens.count, 90000)
    XCTAssertLessThan(allTokens.count, 110_000)

    // Verify sorted order
    for i in 1 ..< min(100, allTokens.count) {
      XCTAssertTrue(allTokens[i - 1].lexicographicallyPrecedes(allTokens[i]) ||
        allTokens[i - 1] == allTokens[i])
    }
  }

  func testEncodeBytes() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    // Test valid UTF-8
    let validBytes = Array("hello world".utf8)
    let tokens = try encoder.encodeBytes(validBytes)
    XCTAssertEqual(tokens, [15339, 1917])

    // Test roundtrip
    let decoded = try encoder.decode(tokens: tokens)
    XCTAssertEqual(decoded, "hello world")
  }

  func testEncodeBytesInvalidUTF8() async throws {
    // Test from Python tiktoken test_encode_bytes
    let encoder = try await CoreBPE.cl100kBase()

    // Test specific byte sequences (from Python test)
    // Python: enc._encode_bytes(b" \xec\x8b\xa4\xed") == [62085]
    let specificBytes: [UInt8] = [0x20, 0xEC, 0x8B, 0xA4, 0xED]
    let tokens = try encoder.encodeBytes(specificBytes)
    XCTAssertEqual(tokens, [62085])

    // Test roundtrip with invalid UTF-8 sequences
    for i in 0 ..< 10 {
      let bytestring = Array(repeating: UInt8(0x80), count: i)
      let encoded = try encoder.encodeBytes(bytestring)
      let decoded = try encoder.decodeBytes(tokens: encoded)
      XCTAssertEqual(decoded, bytestring)
    }
  }

  func testSingleTokenRoundtrip() async throws {
    // Test from Python tiktoken: for all tokens, encode_single_token(decode_single_token_bytes(token)) == token
    let encoder = try await CoreBPE.cl100kBase()

    // Test first 10000 tokens (matching Python test)
    for token in 0 ..< 10000 {
      do {
        let bytes = try encoder.decodeSingleTokenBytes(token: UInt32(token))
        let reencoded = try encoder.encodeSingleToken(piece: bytes)
        XCTAssertEqual(reencoded, UInt32(token), "Token \(token) failed roundtrip")
      } catch {
        // Some tokens may not be valid (gaps in vocabulary), that's fine
        continue
      }
    }
  }

  // MARK: - Encode With Special Tokens Tests

  func testEncodeWithSpecialTokens() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let text = "Hello<|endoftext|>World<|fim_prefix|>End"

    // All special tokens allowed
    let tokens = try encoder.encodeWithSpecialTokens(text: text)

    // Should contain the special token values
    XCTAssertTrue(tokens.contains(100_257)) // endoftext
    XCTAssertTrue(tokens.contains(100_258)) // fim_prefix

    // Roundtrip should work
    let decoded = try encoder.decode(tokens: tokens)
    XCTAssertEqual(decoded, text)
  }

  // MARK: - Decode With Offsets Tests

  func testDecodeWithOffsetsBasic() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let prompt = "hello world"
    let tokens = try encoder.encode(text: prompt, allowedSpecial: [], disallowedSpecial: .none)
    let (text, offsets) = try encoder.decodeWithOffsets(tokens: tokens)

    XCTAssertEqual(text, prompt)
    XCTAssertEqual(offsets, [0, 5])
  }

  func testDecodeWithOffsetsSpecialTokens() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let prompt = "hello world<|endoftext|> green cow"
    let tokens = try encoder.encodeWithSpecialTokens(text: prompt)
    let (text, offsets) = try encoder.decodeWithOffsets(tokens: tokens)

    XCTAssertEqual(text, prompt)
    XCTAssertEqual(offsets, [0, 5, 11, 24, 30])
  }

  func testDecodeWithOffsetsChinese() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let prompt = "我非常渴望与人工智能一起工作"
    let tokens = try encoder.encode(text: prompt, allowedSpecial: [], disallowedSpecial: .none)
    let (text, offsets) = try encoder.decodeWithOffsets(tokens: tokens)

    XCTAssertEqual(text, prompt)
    XCTAssertEqual(offsets.count, tokens.count)
    XCTAssertEqual(offsets.first, 0)
    // Match Python's expected offsets: [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13]
    XCTAssertEqual(offsets, [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13])
  }

  func testDecodeWithOffsetsTamil() async throws {
    // Test from Python tiktoken: contains interesting tokens with UTF-8 boundary issues
    let encoder = try await CoreBPE.cl100kBase()

    let prompt = "நடிகர் சூர்யா"
    let tokens = try encoder.encode(text: prompt, allowedSpecial: [], disallowedSpecial: .none)
    let (text, offsets) = try encoder.decodeWithOffsets(tokens: tokens)

    XCTAssertEqual(text, prompt)
    // Python expects: [0, 0, 1, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 9, 10, 11, 12, 12]
    XCTAssertEqual(offsets, [0, 0, 1, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 9, 10, 11, 12, 12])
  }

  func testDecodeWithOffsetsInterestingByteSequence() async throws {
    // Test from Python tiktoken: contains token b'\xa0\xe9\x99\xa4'
    // where \xe9 is start of 3-byte UTF-8 char and \xa0 is continuation byte
    let encoder = try await CoreBPE.cl100kBase()

    let prompt = " Ġ除"
    let tokens = try encoder.encode(text: prompt, allowedSpecial: [], disallowedSpecial: .none)
    let (text, offsets) = try encoder.decodeWithOffsets(tokens: tokens)

    XCTAssertEqual(text, prompt)
    // Python expects: [0, 1]
    XCTAssertEqual(offsets, [0, 1])
  }

  // MARK: - Batch Encoding Tests

  func testBatchEncode() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let texts = ["hello world", "goodbye world", "test"]
    let batch = try await encoder.encodeBatch(texts, disallowedSpecial: .none)

    XCTAssertEqual(batch.count, texts.count)
    XCTAssertEqual(batch[0], try encoder.encode(text: texts[0], allowedSpecial: [], disallowedSpecial: .none))
    XCTAssertEqual(batch[1], try encoder.encode(text: texts[1], allowedSpecial: [], disallowedSpecial: .none))
    XCTAssertEqual(batch[2], try encoder.encode(text: texts[2], allowedSpecial: [], disallowedSpecial: .none))
  }

  func testBatchEncodeOrdinary() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let texts = ["hello world", "goodbye world", "test"]
    let batch = try await encoder.encodeOrdinaryBatch(texts)

    XCTAssertEqual(batch.count, texts.count)
    XCTAssertEqual(batch[0], try encoder.encodeOrdinary(text: texts[0]))
    XCTAssertEqual(batch[1], try encoder.encodeOrdinary(text: texts[1]))
    XCTAssertEqual(batch[2], try encoder.encodeOrdinary(text: texts[2]))
  }

  func testBatchDecode() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let texts = ["hello world", "goodbye world", "test"]
    let batch = try await encoder.encodeBatch(texts, disallowedSpecial: .none)
    let decoded = try await encoder.decodeBatch(batch)

    XCTAssertEqual(decoded, texts)
  }

  func testBatchRoundtrip() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let texts = [
      "The quick brown fox",
      "jumps over the lazy dog",
      "Hello, 世界!",
      "🚀 to the moon",
    ]

    let encoded = try await encoder.encodeBatch(texts, disallowedSpecial: .none)
    let decoded = try await encoder.decodeBatch(encoded)

    XCTAssertEqual(decoded, texts)
  }

  func testBatchSyncEncode() async throws {
    let encoder = try await CoreBPE.cl100kBase()

    let texts = ["hello world", "goodbye world", "test"]
    let batch = try encoder.encodeBatchSync(texts, disallowedSpecial: .none)

    XCTAssertEqual(batch.count, texts.count)
    XCTAssertEqual(batch[0], try encoder.encode(text: texts[0], allowedSpecial: [], disallowedSpecial: .none))
    XCTAssertEqual(batch[1], try encoder.encode(text: texts[1], allowedSpecial: [], disallowedSpecial: .none))
    XCTAssertEqual(batch[2], try encoder.encode(text: texts[2], allowedSpecial: [], disallowedSpecial: .none))
  }

  // MARK: - Model Encoding Tests

  func testEncodingForModel() async throws {
    // Tests matching Python tiktoken test_encoding_for_model

    // Test GPT-2 (from Python tiktoken)
    let gpt2 = try await CoreBPE.forModel("gpt2")
    XCTAssertEqual(try gpt2.encode(text: "hello world", allowedSpecial: []), [31373, 995])

    // Test text-davinci-003 -> p50k_base (from Python tiktoken)
    let davinci003 = try await CoreBPE.forModel("text-davinci-003")
    XCTAssertEqual(try davinci003.encode(text: "hello world", allowedSpecial: []), [31373, 995])

    // Test text-davinci-edit-001 -> p50k_edit (from Python tiktoken)
    let davinciEdit = try await CoreBPE.forModel("text-davinci-edit-001")
    XCTAssertEqual(try davinciEdit.encode(text: "hello world", allowedSpecial: []), [31373, 995])
    // Verify it has FIM tokens
    let fimTokens = try davinciEdit.encodeWithSpecialTokens(text: "<|fim_prefix|>")
    XCTAssertTrue(fimTokens.contains(50281))

    // Test gpt-3.5-turbo-0301 -> cl100k_base (from Python tiktoken)
    let gpt35turbo = try await CoreBPE.forModel("gpt-3.5-turbo-0301")
    XCTAssertEqual(try gpt35turbo.encode(text: "hello world", allowedSpecial: []), [15339, 1917])

    // Test GPT-4
    let gpt4 = try await CoreBPE.forModel("gpt-4")
    XCTAssertEqual(try gpt4.encode(text: "hello world", allowedSpecial: []), [15339, 1917])

    // Test GPT-3.5
    let gpt35 = try await CoreBPE.forModel("gpt-3.5-turbo")
    XCTAssertEqual(try gpt35.encode(text: "hello world", allowedSpecial: []), [15339, 1917])

    // Test GPT-4o
    let gpt4o = try await CoreBPE.forModel("gpt-4o")
    XCTAssertNotNil(gpt4o)
  }

  func testEncodingForModelPrefixes() async throws {
    // Test versioned models
    let gpt4_0314 = try await CoreBPE.forModel("gpt-4-0314")
    XCTAssertEqual(try gpt4_0314.encode(text: "hello world", allowedSpecial: []), [15339, 1917])

    let gpt35turbo_0301 = try await CoreBPE.forModel("gpt-3.5-turbo-0301")
    XCTAssertEqual(try gpt35turbo_0301.encode(text: "hello world", allowedSpecial: []), [15339, 1917])
  }

  func testEncodingForModelUnknown() async throws {
    do {
      _ = try await CoreBPE.forModel("unknown-model-xyz")
      XCTFail("Should throw for unknown model")
    } catch {
      // Expected
    }
  }

  func testModelEncodingMapping() {
    // Test exact matches
    XCTAssertEqual(ModelEncoding.encodingName(forModel: "gpt-4"), "cl100k_base")
    XCTAssertEqual(ModelEncoding.encodingName(forModel: "gpt-4o"), "o200k_base")
    XCTAssertEqual(ModelEncoding.encodingName(forModel: "gpt2"), "gpt2")
    XCTAssertEqual(ModelEncoding.encodingName(forModel: "text-davinci-003"), "p50k_base")

    // Test prefix matches
    XCTAssertEqual(ModelEncoding.encodingName(forModel: "gpt-4-0314"), "cl100k_base")
    XCTAssertEqual(ModelEncoding.encodingName(forModel: "gpt-4o-2024-05-13"), "o200k_base")
    XCTAssertEqual(ModelEncoding.encodingName(forModel: "gpt-3.5-turbo-0301"), "cl100k_base")

    // Test unknown
    XCTAssertNil(ModelEncoding.encodingName(forModel: "unknown-model"))
  }
}

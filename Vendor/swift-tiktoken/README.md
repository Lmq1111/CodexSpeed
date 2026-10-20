# Swift Tiktoken

A pure Swift implementation of OpenAI's [tiktoken](https://github.com/openai/tiktoken) tokenizer.

## Motivation

FFI-based wrappers of tiktoken bundle a ~50 MB Rust binary. This library is pure Swift, resulting in a much smaller footprint. Performance is slightly slower than Rust for encoding (see [Benchmarks](Benchmarks/)), but decoding matches Rust speed.

## Installation

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourname/swift-tiktoken.git", from: "1.0.0")
]
```

## Usage

```swift
import SwiftTiktoken

// Load an encoding
let encoder = try await CoreBPE.cl100kBase()  // GPT-3.5/4
let encoder = try await CoreBPE.o200kBase()   // GPT-4o
let encoder = try await CoreBPE.forModel("gpt-4o")

// Encode
let tokens = encoder.encodeOrdinary(text: "Hello, world!")
// [9906, 11, 1917, 0]

// Decode
let text = try encoder.decode(tokens: tokens)
// "Hello, world!"

// With special tokens
let tokens = encoder.encodeWithSpecialTokens(text: "Hello<|endoftext|>")
```

## API

| Method | Description |
|--------|-------------|
| `encodeOrdinary(text:)` | Encode text to tokens |
| `encode(text:allowedSpecial:)` | Encode with special token handling |
| `decode(tokens:)` | Decode tokens to string |
| `decodeBytes(tokens:)` | Decode tokens to raw bytes |
| `decodeWithOffsets(tokens:)` | Decode with character offsets |
| `encodeBatch(_:)` | Parallel encoding (async) |
| `decodeBatch(_:)` | Parallel decoding (async) |

## Supported Encodings

| Encoding | Models |
|----------|--------|
| `cl100k_base` | GPT-3.5, GPT-4 |
| `o200k_base` | GPT-4o, GPT-4.1, GPT-5, o1, o3, o4-mini |
| `o200k_harmony` | gpt-oss-20b, gpt-oss-120b |
| `p50k_base` | Codex |
| `r50k_base` | GPT-2 |

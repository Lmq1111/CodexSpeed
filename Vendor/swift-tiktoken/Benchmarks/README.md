# Benchmarks

Performance comparison between SwiftTiktoken and the reference Python/Rust tiktoken implementation.

## Running Benchmarks

### Swift

```bash
swift run -c release Benchmark
```

### Python

```bash
pip install tiktoken
python Benchmarks/benchmark_tiktoken.py
```

## Results (Apple M3)

| Benchmark | Python (Rust) | Swift | Ratio |
|-----------|---------------|-------|-------|
| Basic encode (1000x) | 12.76ms | 16.64ms | 1.3x slower |
| Medium encode (100x) | 4.32ms | 32.27ms | 7.5x slower |
| Large encode (10x) | 4.06ms | 31.78ms | 7.8x slower |
| Catastrophic (6 chars) | 85.19ms | 225.79ms | 2.7x slower |
| Decode (100x) | 0.30ms | 0.29ms | ~same |
| Single token RT (1000) | 0.89ms | 0.15ms | 6x faster |
| Batch encode (10x100) | 21.47ms | 25.31ms | 1.2x slower |

## Analysis

- **Decode performance matches** Python/Rust - the bottleneck is encoding, not decoding
- **Single-token operations are faster** in Swift due to efficient dictionary lookups
- **Encoding is slower** primarily due to Swift's Regex being slower than Rust's regex crate
- **Batch encoding** helps amortize overhead through parallelization

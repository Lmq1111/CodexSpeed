#!/usr/bin/env python
"""
Performance benchmarks for tiktoken (Python/Rust reference implementation).

This script provides baseline measurements to compare against SwiftTiktoken.
Run this with the official tiktoken package installed:

    pip install tiktoken
    python Benchmarks/benchmark_tiktoken.py

Results on Apple M3:
    cl100k_base:
      Basic encode (1000x):     12.76ms
      Medium encode (100x):     4.32ms
      Large encode (10x):       4.06ms
      Catastrophic (6 chars):   85.19ms
      Decode (100x):            0.30ms
      Single token RT (1000):   0.89ms
      Batch encode (10x100):    21.47ms
"""

import time
import tiktoken


def benchmark(name, func, iterations=1):
    """Run a benchmark and return elapsed time in seconds."""
    start = time.perf_counter()
    for _ in range(iterations):
        func()
    elapsed = time.perf_counter() - start
    return elapsed


def main():
    encodings = ["cl100k_base", "r50k_base", "p50k_base", "o200k_base"]

    print("=" * 60)
    print("TIKTOKEN PYTHON BENCHMARKS")
    print("=" * 60)

    for enc_name in encodings:
        enc = tiktoken.get_encoding(enc_name)
        print(f"\n{enc_name}:")
        print("-" * 40)

        # 1. Basic encoding - 1000 iterations of short text
        text = "The quick brown fox jumps over the lazy dog."
        elapsed = benchmark(
            "Basic encode (1000x short)", lambda: enc.encode(text), iterations=1000
        )
        print(f"  Basic encode (1000x):     {elapsed*1000:.2f}ms")

        # 2. Medium text - ~1000 tokens worth
        medium_text = text * 25
        elapsed = benchmark(
            "Medium encode", lambda: enc.encode(medium_text), iterations=100
        )
        print(f"  Medium encode (100x):     {elapsed*1000:.2f}ms")

        # 3. Large text - ~10000 tokens worth
        large_text = text * 250
        elapsed = benchmark("Large encode", lambda: enc.encode(large_text), iterations=10)
        print(f"  Large encode (10x):       {elapsed*1000:.2f}ms")

        # 4. Catastrophically repetitive input
        test_chars = ["^", "0", "a", "'s", " ", "\n"]
        total = 0
        for c in test_chars:
            big_value = c * 10_000
            elapsed = benchmark(
                f"Repetitive {repr(c)}", lambda bv=big_value: enc.encode(bv), iterations=1
            )
            total += elapsed
        print(f"  Catastrophic (6 chars):   {total*1000:.2f}ms")

        # 5. Decode
        tokens = enc.encode(medium_text)
        elapsed = benchmark("Decode", lambda: enc.decode(tokens), iterations=100)
        print(f"  Decode (100x):            {elapsed*1000:.2f}ms")

        # 6. Single token roundtrip (first 1000 tokens)
        elapsed = benchmark(
            "Single token RT",
            lambda: [
                enc.encode_single_token(enc.decode_single_token_bytes(t))
                for t in range(min(1000, enc.n_vocab))
            ],
            iterations=1,
        )
        print(f"  Single token RT (1000):   {elapsed*1000:.2f}ms")

        # 7. Batch encode
        texts = [text] * 100
        elapsed = benchmark("Batch encode", lambda: enc.encode_batch(texts), iterations=10)
        print(f"  Batch encode (10x100):    {elapsed*1000:.2f}ms")

    print("\n" + "=" * 60)


if __name__ == "__main__":
    main()

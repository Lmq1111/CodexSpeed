<div align="center">

# CodexSpeed

**Know how fast Codex writes. Keep the result in your menu bar.**

A native macOS companion for the Codex desktop app — with persistent text-speed estimates, per-turn usage, and a compact glass panel.

[English](README.md) · [简体中文](README.zh-CN.md)

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-111827?logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple-Silicon-64748b)
![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)
[![MIT License](https://img.shields.io/badge/License-MIT-22c55e)](LICENSE)

[Get started](#get-started) · [How speed is measured](#how-speed-is-measured) · [Contributing](CONTRIBUTING.md) · [Report a bug](https://github.com/Lmq1111/CodexSpeed/issues/new/choose)

<img src="docs/assets/preview-light.png" width="360" alt="CodexSpeed light appearance: a compact panel with text speed, turn timing, token usage, and context occupancy">
<img src="docs/assets/preview-dark.png" width="360" alt="The same CodexSpeed panel in dark appearance">

*Native UI rendered with synthetic example data. The app interface is currently in Simplified Chinese.*

</div>

## Why CodexSpeed?

A burst of output can be over before you look at the menu bar. CodexSpeed keeps a recent average visible after generation stops, so you can check it when it suits you.

- **Follow your conversation.** Track the chat in the most recently focused Codex window, or pin a long-running task.
- **Keep the result.** See `≈ N tok/s` from the latest five eligible text requests, grouped by conversation, model, and reasoning effort.
- **Inspect a turn.** Switch between the current and previous turn for elapsed time, first-token latency when reported, tool duration, and official token usage.
- **Stay native.** A compact AppKit/SwiftUI panel with system material, light/dark appearance, and no Dock icon.
- **Work locally.** No API key, additional model request, analytics, or cloud account for CodexSpeed. Existing Codex data is read locally.

> **Early-stage, unofficial project.** CodexSpeed uses Codex's internal desktop IPC and local log formats. Codex updates can break compatibility. It is not affiliated with or endorsed by OpenAI.

## Get started

### Requirements

| Component | Requirement |
| --- | --- |
| Mac | Apple Silicon, macOS 26 or later |
| Codex | Desktop app with local conversations; initial compatibility baseline: `26.1007.71326`, stream-state protocol v11 |
| Build tools | Xcode 26+ with Swift 6.2+ and the macOS 26 SDK |
| App signing | An installed Apple Development signing identity for the installation script |
| Automatic following | macOS Accessibility permission for CodexSpeed; manual selection works without it |

Intel Macs, remote hosts, ChatGPT Work cloud conversations, and custom `CODEX_HOME` locations are not currently supported or validated. English documentation does not imply an English app interface.

### Build and install

Source installation is the supported distribution path today. There is no notarized download, Homebrew formula, or automatic updater yet.

```sh
git clone https://github.com/Lmq1111/CodexSpeed.git
cd CodexSpeed
swift test
# Quit an already-running CodexSpeed before installing.
./scripts/build-install.sh
open "$HOME/Applications/CodexSpeed.app"
```

The installer builds a release executable, bundles the offline tokenizer vocabulary and license notices, signs the app with your local Apple Development identity, and installs it in `~/Applications`. It does not change Codex or its database. To select a specific signing identity:

```sh
CODEX_SPEED_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-install.sh
```

Use the same identity for later updates so macOS can retain Accessibility authorization. Without a certificate, you can still run `swift build` and `swift test`; the installation script requires a signing identity. See [troubleshooting](docs/troubleshooting.md) for setup and permission issues.

### First run

1. Open CodexSpeed and click its waveform icon in the menu bar.
2. Enable Accessibility access when prompted to use automatic following.
3. View a local conversation in Codex. The panel will follow a uniquely identified conversation.
4. Click **跟随** (Follow) to pin it; click **已固定** (Pinned) to resume following.
5. Click the conversation title to search and select a task. Manual selection pins it.

Click outside to dismiss. **Esc** closes the info panel or conversation chooser first, then the main panel. Right-click the menu bar item to quit. When Codex loses focus, the last identified conversation is retained.

## How speed is measured

The menu bar and panel show the same **estimated text-output average**:

```text
                  Σ (official output tokens − reasoning tokens)
text tok/s  =  ───────────────────────────────────────────────────
                  Σ (visible assistant-message interval seconds)
```

Only requests **without generated tool calls** and with complete, valid text timing are eligible. This prevents tool-argument tokens from being counted as prose. Within each request, overlapping text intervals are merged. The latest **five eligible requests for the selected conversation, model, and reasoning effort** are combined by totals, not by averaging their individual rates.

A request is one model response; a turn can contain many requests. Samples can span multiple turns. With fewer than five eligible requests, all available samples are used. Results persist until newer eligible samples replace them.

The `≈` matters: these are client-observed message intervals, affected by network delivery and batching. **This is not server-side decoding throughput, reasoning speed, or a complete model-performance benchmark.** Reasoning and tool-argument tokens are excluded from this speed, but remain visible in official usage totals where applicable.

| Metric | What it means |
| --- | --- |
| Text speed | Persistent, weighted average of the latest five eligible requests |
| Turn elapsed | While running: elapsed time from the available turn start; after completion: official `duration_ms`, including final-answer output |
| First token | Official turn-level `time_to_first_token_ms`, shown when available; not per-request latency |
| Tool cumulative | Sum of recorded tool durations; parallel or nested tools can overlap |
| Input / output | Official usage for the selected current or previous turn, including its multiple requests |
| Cache hit | Cached input ÷ input for that same turn |
| Reasoning | A subset of output tokens, not an extra amount to add to the total |
| Conversation total | Official thread-level token usage, not a monetary cost |
| Context | Estimated latest-request token total ÷ reported context window; not historical usage |

The speed above the turn selector always refers to the rolling sample window. Switching **本轮 / 上一轮** changes the timing and usage section, not the speed window. Read [measurement details](docs/metrics.md) for eligibility, unknown values, and timing caveats.

## Privacy and compatibility

CodexSpeed reads the local IPC socket, the conversation catalog in `~/.codex`, the selected conversation's JSONL log, and Accessibility information used to identify the current conversation. It does not edit the Codex installation, send prompts, or create model sessions.

Assistant text is processed in memory. Local caches contain numeric summaries, identifiers, and log read offsets/paths; optional diagnostics also contain identifiers and status information. They are **not anonymous**, and should be reviewed before sharing. No chat-body copy is intentionally persisted by CodexSpeed. See [security and data handling](SECURITY.md).

If the stream disconnects or becomes incompatible, the app reconnects with backoff and retains recorded results. Live status may be unavailable; retained numbers are not evidence of ongoing generation. Catalog errors clear automatically when a later refresh succeeds. Permission, connection, and catalog issues are covered in [troubleshooting](docs/troubleshooting.md).

## Development

```sh
swift build
swift test
```

The test suite covers stream framing and revisions, reconnect behavior, usage deduplication, metric eligibility, timing, catalog parsing, and tokenization. Live Codex integration and UI permissions still need manual verification; passing unit tests is not a compatibility guarantee for every Codex version.

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the code map, validation workflow, and reporting guidelines. See [CHANGELOG.md](CHANGELOG.md) for version history.

## Acknowledgments

- [swift-tiktoken](https://github.com/DePasqualeOrg/swift-tiktoken) — vendored Swift tokenizer, pinned to a specific upstream commit.
- [OpenAI tiktoken](https://github.com/openai/tiktoken) — tokenizer definitions and the bundled `o200k_base` vocabulary.

The tokenizer supports the internal visible-text stream counter; the displayed rolling average uses official usage records. Third-party attribution and vocabulary provenance are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE) © 2026 Leo Li. Bundled dependencies retain their own license notices.

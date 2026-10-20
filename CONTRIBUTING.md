# Contributing to CodexSpeed

[English](CONTRIBUTING.md) · [简体中文](CONTRIBUTING.zh-CN.md)

Bug reports, compatibility fixes, documentation, and localization work are welcome. For a substantial change, open an issue first to agree on the intended behavior. Small focused fixes can go straight to a pull request.

## Local setup

Use an Apple Silicon Mac with macOS 26+, Xcode 26+, and Swift 6.2+. From the repository root:

```sh
swift build
swift test
```

Tests use synthetic records and local test sockets; they do not require a Codex account or live conversation. To exercise the real integration, run Codex and follow the installation steps in the README. Keep a stable signing identity across installations.

## Code map

| Location | Responsibility |
| --- | --- |
| `Sources/CodexSpeed` | Status item, native panel, presentation state, Accessibility-based conversation resolution |
| `Sources/MonitorCore/DesktopIPCClient.swift` | Local socket subscription and reconnects |
| `Sources/MonitorCore/Protocol.swift` | Framing and snapshot/patch reduction |
| `Sources/MonitorCore/UsageLogReader.swift` | Incremental log reads and numeric checkpoints |
| `Sources/MonitorCore/PerformanceHistory.swift` | Request/turn accounting and eligible body-speed samples |
| `Sources/MonitorCore/MetricsEngine.swift` | Live state and internal visible-text counter |
| `Tests/MonitorCoreTests` | Deterministic core, catalog, and transport tests |
| `Vendor` | Pinned dependency sources and upstream license notices |

## Before submitting

- Keep the patch scoped and explain what a user will observe differently.
- Test metric or protocol changes with synthetic fixtures, including duplicates, missing fields, and reconnects where relevant.
- Never use a subscription timestamp as an invented generation start or treat replayed text as freshly generated.
- Preserve unknown values. Do not add a reasoning-speed number without evidence of both the token count and the complete matching time interval.
- For UI changes, check light/dark appearance, narrow width, follow/pin, turn selection, and Esc behavior.
- Keep English and Simplified Chinese README/measurement documentation consistent.
- Include the commands you ran and distinguish automated tests from manual/live checks.

Do not submit real rollout files, IPC dumps, conversation text, local caches, access tokens, private paths, signing keys, or provisioning profiles. Use invented conversation IDs, titles, and text in tests and screenshots.

GitHub Actions runs tests and a release build on macOS. That build is not a signed or notarized app release. Contributions are provided under the repository's MIT license; upstream dependencies keep their own terms.

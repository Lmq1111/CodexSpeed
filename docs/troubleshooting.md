# Troubleshooting

[English](troubleshooting.md) · [简体中文](troubleshooting.zh-CN.md) · [README](../README.md)

## Build or signing fails

Check `xcodebuild -version` and `swift --version`. The package needs Swift 6.2+ and a macOS 26 SDK. Point the active developer directory at your compatible Xcode installation if necessary.

The installer requires an Apple Development certificate with its private key available in your keychain. Check available identities with `security find-identity -v -p codesigning`, or select one with `CODEX_SPEED_SIGN_IDENTITY`. Building/tests do not need that identity. Quit CodexSpeed, including any probe process, before installing.

## Following does not identify a conversation

Grant Accessibility to **CodexSpeed** in System Settings → Privacy & Security → Accessibility, then return to a local Codex conversation. A duplicated or truncated title that cannot be uniquely matched is deliberately not guessed. Use the title button to manually select and pin a conversation.

Keep the same signing identity across updates. If authorization stops working after a signing-identity change, remove and re-add CodexSpeed in Accessibility settings, then restart it. Do not reset permissions for unrelated apps.

## Catalog error remains after recovery

Fixed in v0.4.2: after a complete successful refresh, the catalog error clears automatically, even when the conversation list is unchanged. Independent service errors remain visible. Older versions can leave a stale banner; update to v0.4.2 or later.

If a catalog error persists, the panel shows a readable reason and SQLite code; hover over it for the underlying database detail. Refreshes retry automatically. An incomplete/failed query preserves the last successful catalog rather than accepting a partial result. Catalog reads and the selected thread's stream/log reads are separate; this banner alone does not establish that the stream is disconnected.

## Speed is missing or remains unchanged

Speed updates only after an eligible request finishes and both usage and valid timing are available. Tool-calling requests are excluded. A long tool-heavy task can keep an older result visible. Check the sample count and update time in the panel. A new model/effort group can have no eligible samples yet.

## Connection is unavailable

Ensure the Codex desktop app is running. CodexSpeed retries automatically and retains recorded results. An internal protocol change may need a compatibility update; do not start a separate model session to simulate monitoring. Remote/cloud conversations and custom Codex home paths are outside current support.

## Turn time differs from Codex's label

CodexSpeed uses the completed turn's official duration, including final-answer output. Another UI label may stop earlier. Do not subtract tool cumulative duration to infer thinking time: tool intervals can overlap. See [metrics](metrics.md).

## Safe diagnostics

```sh
open "$HOME/Applications/CodexSpeed.app" --args --diagnostics --show
```

Quit an existing instance first so the new launch receives these arguments. The file is `~/Library/Application Support/CodexSpeed/diagnostics.json`. Review identifiers and paths before sharing excerpts; never upload full logs or caches. To disable file diagnostics, quit and relaunch without `--diagnostics`.

## Uninstall

Quit from the menu bar's context menu and move `~/Applications/CodexSpeed.app` to Trash. If you want to remove saved results too, move `~/Library/Application Support/CodexSpeed/` to Trash. Neither action requires deleting Codex data. The preference domain is `local.lmq.CodexSpeed`.

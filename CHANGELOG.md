# Changelog

Version numbers below describe local development milestones. They do not imply that a signed or notarized download was published for each version.

## Unreleased

- Prepare the public repository with English and Simplified Chinese documentation, MIT licensing, third-party notices, synthetic native UI previews, contribution/issue templates, and macOS CI.
- Include project and tokenizer license notices in newly built app bundles.

## 0.4.2 — 2026-10-20

- Clear stale catalog-error messages after a successful refresh, including unchanged lists.
- Keep catalog failures separate from independent service errors.
- Show readable SQLite error reasons with details on hover; reject incomplete query results.
- Add regression tests for error recovery, independent errors, database contention, and schema failures.

## 0.4.1 — 2026-10-19

- Reduce the displayed body-speed window from ten to five eligible requests.
- Keep the weighted calculation, model/effort grouping, and retained results.

## 0.4.0 — 2026-10-19

- Introduce a compact 360pt glass panel, aligned timing/usage sections, and an info overlay.
- Shorten the menu bar text to `≈ N tok/s`.
- Move conversation selection to the title and consolidate repeated information.

## 0.3.2 — 2026-10-19

- Use estimated body-output speed consistently in the menu and panel.
- Remove unreliable combined/reasoning speed metrics and their placeholders.
- Retain official usage, turn timing, follow/pin, and recorded body-speed results.

Earlier development explored combined generation-interval estimates. Those values were withdrawn because observed reasoning-item lifecycles did not establish complete hidden-reasoning time. They are not supported performance metrics.

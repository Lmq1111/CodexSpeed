# Security and data handling

CodexSpeed is a local, unofficial Codex desktop companion. Only the current source version receives fixes; there is no promised response-time SLA.

## Reporting a vulnerability

Use GitHub's **Security → Report a vulnerability** for this repository. Please do not disclose exploitable details, real conversation data, or secrets in a public issue. For ordinary UI and compatibility bugs, use the issue templates instead.

Include the affected version, macOS/Codex versions, a minimal reproduction with synthetic data, and the impact. Redact account identifiers and local paths.

## Data access

- Reads `~/.codex/ipc/ipc.sock`, the local SQLite conversation catalog, and the selected rollout file.
- Uses Accessibility to inspect the Codex window hierarchy for a current conversation identifier or uniquely matching title. Processing can encounter other exposed UI text; CodexSpeed does not intentionally persist that text.
- Writes numeric summaries, conversation/request/item identifiers, log paths and offsets under `~/Library/Application Support/CodexSpeed/`.
- Stores preferences such as a pinned conversation ID in macOS UserDefaults.
- With `--diagnostics`, writes a local status/identifier/numeric diagnostic file. It is not anonymous.
- Does not upload telemetry, request an API key, send model prompts, or alter the Codex app/database. Local IPC messages establish and manage the subscription.

Do not attach your full `.codex` directory, rollout logs, caches, or diagnostics to an issue. Review even small excerpts before sharing. Local numeric caches still reveal activity and identifiers.

## 简体中文

安全漏洞请通过本仓库 **Security → Report a vulnerability** 私下报告，不要在公开 Issue 中披露可利用细节或真实聊天数据。普通界面与兼容性问题使用 Issue 模板。

应用只读取 Codex 本地 Socket、对话目录和所选日志；辅助功能遍历可能接触窗口暴露的其他文本，但不主动持久化这些文本。缓存含数值、标识符、路径与读取位置；偏好保存固定会话 ID；可选诊断也含标识符，因此不能视为匿名文件。

没有遥测上传、额外模型请求或 Codex 数据库改写。请勿公开完整 `.codex` 目录、日志、缓存和诊断。报告使用构造数据并清理个人信息。当前源码版本接受修复，不承诺响应时限。

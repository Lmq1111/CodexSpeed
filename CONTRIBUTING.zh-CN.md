# 参与贡献

[English](CONTRIBUTING.md) · [简体中文](CONTRIBUTING.zh-CN.md)

欢迎报告问题、修复兼容性、改善文档和参与本地化。较大的改动请先开 Issue 对齐行为；小范围修复可以直接提交 Pull Request。

## 本地开发

使用 Apple Silicon Mac、macOS 26+、Xcode 26+ 和 Swift 6.2+，在仓库根目录执行：

```sh
swift build
swift test
```

测试使用构造记录和本地测试 Socket，不需要 Codex 账号或真实会话。真实集成验证需要运行 Codex，并按 README 安装应用；更新时保持相同签名身份。

## 代码结构

- `Sources/CodexSpeed`：菜单栏、原生面板、展示状态、辅助功能对话识别。
- `DesktopIPCClient.swift` / `Protocol.swift`：本地订阅、重连、分帧与快照补丁。
- `UsageLogReader.swift`：增量日志读取与数值缓存。
- `PerformanceHistory.swift`：请求／轮次统计和有效正文样本。
- `MetricsEngine.swift`：实时状态与内部可见文本计数。
- `Tests/MonitorCoreTests`：确定性核心、目录和传输测试。
- `Vendor`：固定依赖源码与上游许可证。

## 提交前

- 保持改动聚焦，说明用户会看到的变化。
- 指标或协议改动使用构造样本验证，按需覆盖重复事件、缺失字段和重连。
- 不用订阅时间补造生成起点，不把历史补发当成刚刚生成的文本。
- 保留未知值；没有可靠的 token 数和对应完整时间区间，不加入思考速度。
- 界面改动检查浅深色、窄宽度、跟随／固定、轮次切换和 Esc。
- 同步更新中英文 README 和统计说明。
- 写明运行过的命令，区分自动化测试和人工／真实集成验证。

不要提交真实 rollout、IPC 转储、聊天内容、本地缓存、访问令牌、私有路径、签名密钥或描述文件。测试和截图使用虚构会话 ID、标题和文本。

GitHub Actions 在 macOS 上执行测试和 Release 构建，不等于签名、公证后的应用发布。贡献采用本仓库 MIT 许可证，上游依赖保留各自条款。

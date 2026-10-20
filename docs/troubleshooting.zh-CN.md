# 故障排查

[English](troubleshooting.md) · [简体中文](troubleshooting.zh-CN.md) · [README](../README.zh-CN.md)

## 构建或签名失败

检查 `xcodebuild -version` 和 `swift --version`，需要 Swift 6.2+ 和 macOS 26 SDK，必要时选择兼容的 Xcode 开发目录。

安装脚本需要钥匙串中包含私钥的 Apple Development 证书。可运行 `security find-identity -v -p codesigning` 查看身份，或通过 `CODEX_SPEED_SIGN_IDENTITY` 指定。单独构建和测试不需要签名。安装前退出 CodexSpeed，包括探测进程。

## 自动跟随识别不到对话

在系统设置 → 隐私与安全性 → 辅助功能中允许 **CodexSpeed**，再回到 Codex 本地对话。重名、截断等导致无法唯一匹配时，程序不会猜测。可以点击顶部标题手动选择并固定。

更新时保持同一签名身份。如果更换签名后授权失效，可在辅助功能设置中移除并重新添加 CodexSpeed，再重启工具。不需要重置其他应用权限。

## 目录恢复后错误提示仍存在

**v0.4.1 已知问题：**一次目录刷新失败后，即使后续查询成功，旧提示仍可能残留。对话目录与所选会话的事件流／日志读取相互独立，不能仅凭这条提示判断实时连接已断开。重启 CodexSpeed 可清除内存中的旧提示；若再次出现，请报告完整错误与应用、Codex 版本。旧版通用错误未保留足够信息，不能据此确认原始 SQLite 失败原因。

## 速度缺失或一直不变

只有有效请求完成、用量与计时齐全后才更新速度；带工具调用的请求被排除，因此长时间执行工具时会保留旧结果。检查样本数和更新时间。新模型或推理档位可能暂时没有有效样本。

## 无法实时连接

确认 Codex 桌面端正在运行。CodexSpeed 会自动重试并保留已有结果。内部协议变化可能需要更新适配，不要通过新建模型会话来代替监听。远程／云端会话和自定义 Codex home 路径暂不支持。

## 整轮耗时与 Codex 的标签不同

CodexSpeed 使用官方整轮完成耗时，包含最终回答输出；其他界面标签可能更早停止计时。工具累计可能重叠，不能从整轮耗时中减掉它来求思考时间。详见[统计口径](metrics.zh-CN.md)。

## 安全地提供诊断

```sh
open "$HOME/Applications/CodexSpeed.app" --args --diagnostics --show
```

先退出已有实例，确保新启动接收参数。诊断文件位于 `~/Library/Application Support/CodexSpeed/diagnostics.json`。分享片段前检查标识符与路径，不上传完整日志或缓存。退出后不带 `--diagnostics` 重新启动，即停止写入诊断文件。

## 卸载

从菜单栏右键菜单退出，将 `~/Applications/CodexSpeed.app` 移到废纸篓。如需清除已保存结果，再将 `~/Library/Application Support/CodexSpeed/` 移到废纸篓。不需要删除 Codex 数据。偏好设置域为 `local.lmq.CodexSpeed`。

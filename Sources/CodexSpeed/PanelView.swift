import SwiftUI
import MonitorCore

struct PanelView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            if model.chooser { chooser }
            else if model.selected == nil { empty }
            else { content }
        }
        .foregroundStyle(.primary)
        .font(.system(size: 13))
        .frame(maxWidth: .infinity)
        .frame(minHeight: model.infoVisible ? 390 : nil)
        .overlay {
            if model.infoVisible {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.08).onTapGesture { model.infoVisible = false }
                    information.padding(10)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                model.infoVisible = false
                model.chooser.toggle()
                model.refreshCatalog()
            } label: {
                HStack(spacing: 8) {
                    Text(model.selected?.title ?? "选择一个对话")
                        .font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: model.chooser ? "chevron.up" : "chevron.down").font(.system(size: 10))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(model.selected?.title ?? "选择对话")
            HStack {
                Text(statModel).lineLimit(1)
                Spacer(minLength: 8)
                Button(action: model.togglePin) {
                    Label(model.isPinned ? "已固定" : "跟随", systemImage: model.isPinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain)
                    .disabled(model.selected == nil && !model.isPinned)
                    .help(model.isPinned ? "点击恢复跟随当前对话" : model.modeLabel + "；点击固定此任务")
                    .accessibilityLabel(model.isPinned ? "已固定，点击恢复跟随" : "跟随，点击固定任务")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.horizontal, 17).padding(.top, 14).padding(.bottom, 11)
    }
    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "scope").font(.system(size: 26)).foregroundStyle(.secondary)
            Text(model.isPinned ? "固定的对话暂不可用" : model.resolution.source).font(.system(size: 14, weight: .medium))
            Text("打开一个 Codex 对话，或选择任务并固定。") .font(.system(size: 12)).foregroundStyle(.secondary)
            if !model.resolution.trusted { Button("开启辅助功能权限") { model.resolver.requestPermission() } }
            Button("选择对话") { model.chooser = true; model.refreshCatalog() }
            if let error = model.displayedError { Text(error).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).help(model.catalogErrorDetail ?? error) }
        }.frame(maxWidth: .infinity).padding(.horizontal, 18).padding(.vertical, 42)
    }
    private var chooser: some View {
        VStack(spacing: 10) {
            Button { model.follow() } label: {
                HStack { VStack(alignment: .leading, spacing: 3) { Text("跟随当前查看"); Text("切换 Codex 对话时自动跟随").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); if !model.isPinned { Image(systemName: "checkmark") } }.contentShape(Rectangle())
            }.buttonStyle(.plain).padding(8)
            TextField("查找对话", text: $model.search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.conversations.filter { model.search.isEmpty || $0.title.localizedCaseInsensitiveContains(model.search) || $0.project.localizedCaseInsensitiveContains(model.search) }) { conversation in
                        Button { model.pin(conversation) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) { Text(conversation.title).lineLimit(2); Text(conversation.project).font(.system(size: 11)).foregroundStyle(.secondary) }
                                Spacer(minLength: 6)
                                if model.pinnedID == conversation.id { Image(systemName: "pin.fill") }
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("固定：" + conversation.title)
                    }
                }
            }.frame(height: 330)
            if !model.resolution.trusted { Button("设置自动跟随权限") { model.resolver.requestPermission() }.font(.system(size: 12)) }
        }.padding(12)
    }

    private var content: some View {
        VStack(spacing: 0) {
            hero
            if model.connection != .connected {
                notice("实时连接不可用 · 显示已记录结果")
            }
            if let error = model.displayedError { notice(error).help(model.catalogErrorDetail ?? error) }
            if !model.resolution.trusted {
                Button("开启自动跟随权限") { model.resolver.requestPermission() }
                    .font(.system(size: 11)).padding(.bottom, 10)
            }
            VStack(alignment: .leading, spacing: 0) {
                Divider().opacity(0.55)
                HStack {
                    HStack(spacing: 2) {
                        ForEach([false, true], id: \.self) { previous in
                            Button(previous ? "上一轮" : "本轮") { model.previous = previous }
                                .buttonStyle(.plain).font(.system(size: 11))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(model.previous == previous ? Color.primary.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                .accessibilityAddTraits(model.previous == previous ? .isSelected : [])
                        }
                    }.padding(2).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                    Spacer(minLength: 8)
                    if let usage = model.usage {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(number(usage.total)).monospacedDigit()
                            Text("tokens").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.help("官方累计用量：包含所选轮次的多次请求；输入含缓存，输出含推理。")
                    }
                }.padding(.top, 11)
                if turnDuration != nil || model.displayedResult?.firstToken != nil || (model.displayedResult?.toolCount ?? 0) > 0 {
                    HStack(alignment: .top, spacing: 10) {
                        if let elapsed = turnDuration { statCell("整轮耗时", duration(elapsed)) }
                        if let first = model.displayedResult?.firstToken {
                            statCell("首 token", duration(first))
                                .help("整轮首 token 等待，由官方在轮次结束后上报；不是单次请求延迟。")
                        }
                        if let result = model.displayedResult, result.toolCount > 0 {
                            statCell("工具累计", duration(result.toolSeconds))
                                .help("已记录工具时长之和，可能并行或嵌套，不能直接当作整轮等待时间。")
                        }
                    }.padding(.top, 14).padding(.bottom, 12)
                }
                if let usage = model.usage {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 8) {
                            pair("输入", number(usage.input))
                            if let hit = usage.hit {
                                pair("缓存命中", String(format: "%.2f%%", hit * 100))
                                    .help("缓存输入 " + number(usage.cached) + " token ÷ 本轮输入；缓存已包含在输入中。")
                            }
                        }
                        VStack(spacing: 8) {
                            pair("输出", number(usage.output))
                            pair("其中推理", number(usage.reasoning))
                        }
                    }.padding(.top, turnDuration == nil && model.displayedResult?.firstToken == nil && (model.displayedResult?.toolCount ?? 0) == 0 ? 12 : 0)
                } else {
                    Text(model.previous ? "暂无上一轮用量记录" : "本轮用量等待官方上报")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
                }
            }.padding(.horizontal, 17).padding(.bottom, 12)
            footer
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                HStack(spacing: 5) {
                    Text("正文均速")
                    Button { model.infoVisible.toggle() } label: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("查看统计说明").help("统计口径与数据来源")
                }.font(.system(size: 12))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(model.connection == .connected && [.writing, .tool, .thinking].contains(model.metrics.phase) ? Color.green : Color.secondary)
                        .frame(width: 5, height: 5)
                    Text(model.status)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let rate = model.metrics.performance.bodyAverage {
                    Text("≈ \(Int(rate.rounded()))")
                        .font(.system(size: 40, weight: .medium)).tracking(-1.5).monospacedDigit()
                    Text("tok/s").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(sampleCaption).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).help(sampleDetail)
                } else {
                    Text(model.metrics.performance.loading ? "正在加载正文样本" : "暂无正文样本")
                        .font(.system(size: 20, weight: .medium)).padding(.vertical, 9)
                        .help("只统计无工具调用且正文计时完整的请求。")
                }
            }
        }.padding(.horizontal, 17).padding(.top, 13).padding(.bottom, 12)
    }
    @ViewBuilder private var footer: some View {
        if model.metrics.totalUsage != nil || model.metrics.context != nil {
            Divider().opacity(0.55)
            HStack(spacing: 10) {
                if let context = model.metrics.context {
                    HStack(spacing: 5) {
                        Text("上下文").foregroundStyle(.secondary)
                        Text(String(format: "%.0f%%", context * 100)).monospacedDigit()
                        GeometryReader { geometry in
                            Capsule().fill(.primary.opacity(0.1))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.secondary.opacity(0.6))
                                        .frame(width: geometry.size.width * min(1, max(0, context)))
                                }
                        }.frame(width: 30, height: 3).accessibilityHidden(true)
                    }.help("估算：最新请求 token 总量 ÷ 已报告上下文窗口，不是历史累计。")
                }
                Spacer(minLength: 0)
                if let total = model.metrics.totalUsage {
                    HStack(spacing: 5) {
                        Text("会话累计").foregroundStyle(.secondary)
                        Text(number(total.total)).monospacedDigit()
                    }.help("本会话官方累计 token，包含多轮输入与输出。")
                }
            }.font(.system(size: 11)).padding(.horizontal, 17).padding(.top, 11).padding(.bottom, 13)
        }
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("统计说明").fontWeight(.medium)
                Spacer()
                Button { model.infoVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭统计说明")
            }
            Text("正文均速为估算：仅使用无工具调用请求，以官方输出减推理 token，除以正文接收区间。按当前模型与推理档位统计。")
                .foregroundStyle(.secondary)
            Text("最近最多 5 个有效样本加权平均；停止输出后保留。网络与接收延迟仍会影响结果。")
                .foregroundStyle(.secondary)
            if !model.metrics.performance.body.isEmpty {
                pair("正文样本", "\(model.metrics.performance.body.reduce(0) { $0 + $1.tokens }) token / " + duration(model.metrics.performance.body.reduce(0) { $0 + $1.seconds }))
                Text(sampleDetail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            pair("用量来源", "Codex 官方记录")
            pair("会话来源", (model.selected?.project ?? "未知") + " · 本机")
            pair("跟随状态", model.modeLabel)
            pair("连接", model.connection.label)
            Text("首 token 是整轮官方记录，完成后上报。工具累计可能重叠。缓存属于输入，推理属于输出，均不重复相加。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var statModel: String {
        let p = model.metrics.performance
        let name = p.model.isEmpty ? (model.selected?.model ?? "") : p.model
        return (name.isEmpty ? "模型未知" : name) + (p.effort.isEmpty ? "" : " · " + p.effort)
    }
    private var sampleCaption: String {
        let samples = model.metrics.performance.body
        return "近 \(samples.count) 次" + (samples.last.map { " · " + $0.completedAt.formatted(.dateTime.hour().minute()) } ?? "")
    }
    private var sampleDetail: String {
        guard let date = model.metrics.performance.body.last?.completedAt else { return "暂无有效样本" }
        return "最近 \(model.metrics.performance.body.count) 个有效正文请求，更新于 " + date.formatted(.dateTime.year().month().day().hour().minute())
    }
    private var turnDuration: Double? {
        if let duration = model.displayedResult?.duration { return duration }
        if model.displayedResult?.completedAt != nil || model.previous || [.done, .interrupted, .failed].contains(model.metrics.phase) { return nil }
        return model.metrics.elapsed
    }
    private func notice(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 17).padding(.bottom, 10)
    }
    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .medium)).monospacedDigit().lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func duration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.1f秒", seconds) }
        return "\(Int(seconds) / 60)分\(Int(seconds) % 60)秒"
    }
    private func pair(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).monospacedDigit()
        }.font(.system(size: 12)).frame(maxWidth: .infinity)
    }
    private func number(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1000 { return String(format: "%.1fK", Double(value) / 1000) }
        return String(value)
    }
}

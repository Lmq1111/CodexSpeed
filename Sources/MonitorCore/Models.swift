import Foundation

public struct Conversation: Identifiable, Equatable, Sendable {
    public let id: String
    public let hostId: String
    public let title: String
    public let cwd: String
    public let rollout: String
    public let model: String
    public var project: String { URL(fileURLWithPath: cwd).lastPathComponent }
    public init(id: String, hostId: String = "local", title: String, cwd: String = "", rollout: String = "", model: String = "") {
        self.id = id; self.hostId = hostId; self.title = title; self.cwd = cwd; self.rollout = rollout; self.model = model
    }
}
public enum TaskPhase: String, Codable, Sendable {
    case unknown = "等待数据", waiting = "等待首段", writing = "输出中", tool = "执行工具"
    case thinking = "处理中"
    case approval = "等待确认", done = "已完成", interrupted = "已中断", failed = "失败"
}
public struct Usage: Codable, Equatable, Sendable {
    public var input: Int, cached: Int, output: Int, reasoning: Int, total: Int
    public var hit: Double? { input > 0 ? Double(cached) / Double(input) : nil }
    public init?(_ value: Any?) {
        guard let d = value as? [String: Any], let total = (d["total_tokens"] ?? d["totalTokens"]) as? Int else { return nil }
        self.total = total
        input = (d["input_tokens"] ?? d["inputTokens"]) as? Int ?? 0
        cached = (d["cached_input_tokens"] ?? d["cachedInputTokens"]) as? Int ?? 0
        output = (d["output_tokens"] ?? d["outputTokens"]) as? Int ?? 0
        reasoning = (d["reasoning_output_tokens"] ?? d["reasoningOutputTokens"]) as? Int ?? 0
    }
}
public struct SpeedPoint: Identifiable, Sendable {
    public let time: Double
    public let value: Double?
    public var id: Double { time }
}
public struct Metrics: Sendable {
    public var conversationID: String?
    public var performance = PerformanceView()
    public var phase: TaskPhase = .unknown
    public var speed: Double?
    public var firstLatency: Double?
    public var elapsed: Double?
    public var context: Double?
    public var currentUsage: Usage?
    public var previousUsage: Usage?
    public var totalUsage: Usage?
    public var points: [SpeedPoint] = []
    public var lastEvent: Date?
    public var turnId: String?
    public var eventCount = 0
    public var revision = 0
    public var sampledTokens = 0
    public var average: Double?
    public var tokenizerOK = true
    public init() {}
}
public protocol TokenCounting: Sendable { func count(_ text: String) throws -> Int }

public enum SelectionResolver {
    // Never treat a UUID anywhere in the sidebar as the focused conversation.
    public static func resolve(explicitID: String?, title: String?, project: String?, conversations: [Conversation]) -> Conversation? {
        if let id = explicitID { return conversations.first { $0.id == id } }
        guard let title, !title.isEmpty, !title.contains("…") else { return nil }
        let candidates = conversations.filter { $0.title == title && (project == nil || $0.project == project || $0.cwd == project) }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

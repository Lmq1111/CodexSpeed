import Foundation

public enum StreamError: Error { case oversizedFrame, invalidJSON, revisionGap, invalidPatch, incompatibleVersion }
public struct FrameDecoder {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [[String: Any]] {
        buffer.append(data)
        var result: [[String: Any]] = []
        while buffer.count >= 4 {
            let count = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            guard count > 0, count <= 268_435_456 else { throw StreamError.oversizedFrame }
            guard buffer.count >= count + 4 else { break }
            guard let object = try JSONSerialization.jsonObject(with: buffer.subdata(in: 4..<(4 + count))) as? [String: Any] else { throw StreamError.invalidJSON }
            result.append(object); buffer = Data(buffer.dropFirst(4 + count))
        }
        return result
    }
    public static func encode(_ message: [String: Any]) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: message)
        var length = UInt32(payload.count).littleEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(payload); return result
    }
}
public struct StreamReducer {
    public private(set) var state: [String: Any] = [:]
    public private(set) var revision = 0
    public init() {}
    /// False means a duplicate; snapshots reset the baseline, patches require contiguous revisions.
    public mutating func apply(_ change: [String: Any]) throws -> Bool {
        guard let next = change["revision"] as? Int else { throw StreamError.invalidPatch }
        if change["type"] as? String == "snapshot" {
            guard let snapshot = change["conversationState"] as? [String: Any] else { throw StreamError.invalidPatch }
            state = snapshot; revision = next; return true
        }
        guard change["type"] as? String == "patches" else { throw StreamError.invalidPatch }
        if next <= revision { return false }
        guard revision > 0, change["baseRevision"] as? Int == revision,
              let patches = change["patches"] as? [[String: Any]] else { throw StreamError.revisionGap }
        var value: Any = state
        for patch in patches {
            guard let op = patch["op"] as? String, ["add", "replace", "remove"].contains(op), let path = patch["path"] as? [Any] else { throw StreamError.invalidPatch }
            value = try Self.update(value, path: ArraySlice(path), op: op, value: patch["value"] ?? NSNull())
        }
        guard let updated = value as? [String: Any] else { throw StreamError.invalidPatch }
        state = updated; revision = next; return true
    }
    private static func update(_ node: Any, path: ArraySlice<Any>, op: String, value: Any) throws -> Any {
        guard let component = path.first else { return op == "remove" ? NSNull() : value }
        let tail = path.dropFirst()
        if var dictionary = node as? [String: Any], let key = component as? String {
            if tail.isEmpty {
                if op != "add", dictionary[key] == nil { throw StreamError.invalidPatch }
                if op == "remove" { dictionary.removeValue(forKey: key) } else { dictionary[key] = value }
            } else {
                guard let child = dictionary[key] else { throw StreamError.invalidPatch }
                dictionary[key] = try update(child, path: tail, op: op, value: value)
            }
            return dictionary
        }
        if var array = node as? [Any], let index = component as? Int {
            if tail.isEmpty {
                if op == "add" { guard index >= 0, index <= array.count else { throw StreamError.invalidPatch }; array.insert(value, at: index) }
                else { guard array.indices.contains(index) else { throw StreamError.invalidPatch }; if op == "remove" { array.remove(at: index) } else { array[index] = value } }
            } else {
                guard array.indices.contains(index) else { throw StreamError.invalidPatch }
                array[index] = try update(array[index], path: tail, op: op, value: value)
            }
            return array
        }
        throw StreamError.invalidPatch
    }
}

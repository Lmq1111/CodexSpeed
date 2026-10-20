import Foundation

/// Drop bulky item bodies before decoding, keeping only timing identity. Codex's
/// compact JSONL layout puts timestamps after the item; other small layouts use
/// the general JSON decoder. Unknown large layouts are omitted, never guessed.
enum LogRecordDecoder {
    private static let itemKey = Data(#""item":"#.utf8)
    private static let timingKey = Data(#","started_at_ms":"#.utf8)
    private static let marker = Data(#""item_completed""#.utf8)
    private static let identity = try! NSRegularExpression(pattern: #"^\{"type":"([A-Za-z][A-Za-z0-9_]*)","id":"([^"\\]+)""#)
    private static let bodyKey = try! NSRegularExpression(pattern: #",\"(?:arguments|input|content|summary|encrypted_content|output)\":"#)
    static func decode(_ line: Data) -> [String: Any]? {
        // Compact response items put their metadata before their potentially huge
        // arguments/content. Only decode that prefix, never the generated body.
        let prefix = String(decoding: line.prefix(2048), as: UTF8.self)
        if prefix.contains(#""type":"response_item","payload":{"#),
           let match = bodyKey.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
           let range = Range(match.range, in: prefix) {
            let reduced = Data((prefix[..<range.lowerBound] + "}}").utf8)
            if let object = (try? JSONSerialization.jsonObject(with: reduced)) as? [String: Any] { return object }
        }
        if line.range(of: marker) != nil, let key = line.range(of: itemKey),
           let tail = line.range(of: timingKey, options: .backwards), tail.lowerBound > key.upperBound {
            let head = String(decoding: line[key.upperBound..<min(key.upperBound + 512, line.endIndex)], as: UTF8.self)
            if let match = identity.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
               let typeRange = Range(match.range(at: 1), in: head), let idRange = Range(match.range(at: 2), in: head),
               let item = try? JSONSerialization.data(withJSONObject: ["type":String(head[typeRange]),"id":String(head[idRange])]) {
                let reduced = Data(line[..<key.upperBound]) + item + line[tail.lowerBound...]
                if let object = (try? JSONSerialization.jsonObject(with: reduced)) as? [String: Any],
                   let payload = object["payload"] as? [String: Any],
                   payload["started_at_ms"] != nil, payload["completed_at_ms"] != nil { return object }
            }
        }
        guard line.count <= 256 * 1024 else { return nil }
        return (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }
}

import Foundation
import SwiftTiktoken

public final class LocalTokenizer: TokenCounting, @unchecked Sendable {
    private let encoder: CoreBPE
    public init() throws {
        guard let url = Bundle.main.url(forResource: "o200k_base", withExtension: "tiktoken") ?? Bundle.module.url(forResource: "o200k_base", withExtension: "tiktoken") else { throw CocoaError(.fileNoSuchFile) }
        let contents = try String(contentsOf: url, encoding: .utf8)
        var ranks: [[UInt8]: UInt32] = [:]; ranks.reserveCapacity(200000)
        for line in contents.split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard fields.count == 2, let bytes = Data(base64Encoded: String(fields[0])), let rank = UInt32(fields[1]) else { throw CocoaError(.fileReadCorruptFile) }
            ranks[Array(bytes)] = rank
        }
        guard ranks.count == 199998 else { throw CocoaError(.fileReadCorruptFile) }
        let pattern = #"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n/]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
        encoder = try CoreBPE(encoder: ranks, specialTokensEncoder: [:], pattern: pattern)
    }
    public func count(_ text: String) throws -> Int { try encoder.encodeOrdinary(text: text).count }
}

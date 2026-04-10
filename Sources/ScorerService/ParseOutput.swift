import Foundation
import XdigestCore

/// Claude's response envelope from `--output-format json`.
private struct ClaudeEnvelope: Decodable {
    let structured_output: StructuredOutput?
    let total_cost_usd: Double?
    let duration_ms: Int?
}

private struct StructuredOutput: Decodable {
    let picks: [Pick]?
}

private struct Pick: Decodable {
    let index: Int
    let score: Double
    let reason: String
    let tags: [String]
}

/// Parses Claude's JSON output and maps picks back to candidate tweets.
/// Skips picks with out-of-bounds indices.
public func parseClaudeOutput(_ data: Data, candidates: [Tweet]) throws -> [ScoredPost] {
    let envelope = try decodeEnvelope(data)
    let picks = try extractPicks(from: envelope)
    return mapPicksToScoredPosts(picks, candidates: candidates)
}

/// Decodes the outer Claude JSON envelope.
private func decodeEnvelope(_ data: Data) throws -> ClaudeEnvelope {
    do {
        return try JSONDecoder().decode(ClaudeEnvelope.self, from: data)
    } catch {
        throw XdigestError.claudeOutputInvalid(detail: "JSON decode failed: \(error)")
    }
}

/// Extracts the picks array from the envelope, throws if missing.
private func extractPicks(from envelope: ClaudeEnvelope) throws -> [Pick] {
    guard let picks = envelope.structured_output?.picks else {
        throw XdigestError.claudeOutputInvalid(detail: "missing structured_output.picks")
    }
    return picks
}

/// Maps Claude's picks (by index) back to the candidate tweets.
/// Skips indices that are out of bounds.
private func mapPicksToScoredPosts(_ picks: [Pick], candidates: [Tweet]) -> [ScoredPost] {
    picks.compactMap { pick in
        guard pick.index >= 0, pick.index < candidates.count else { return nil }
        return ScoredPost(
            tweet: candidates[pick.index],
            score: pick.score,
            reason: pick.reason,
            tags: pick.tags
        )
    }
}

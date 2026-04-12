import Foundation
import XdigestCore

private let systemPrompt = """
You are a personal X feed curator.

You receive the user's taste profile (extracted from their bookmarks) and a \
list of candidate tweets from their current For You feed. Your job: pick the \
candidates that best match their taste.

Judge on content substance. An unknown account with strong content should beat \
a familiar account with a throwaway post.
"""

public struct ScorerService: Sendable {
    private let claudePath: String

    public init() throws {
        guard let path = findClaude() else {
            throw XdigestError.claudeNotFound
        }
        self.claudePath = path
    }

    /// Scores candidates against a taste profile using Claude.
    /// Filters seen tweets before scoring.
    public func score(
        _ tweets: [Tweet],
        tasteProfile: String,
        topN: Int = 10,
        seen: Set<String> = []
    ) async throws -> [ScoredPost] {
        let candidates = filterSeenTweets(tweets, seen: seen)
        guard !candidates.isEmpty, !tasteProfile.isEmpty else { return [] }

        let prompt = buildPrompt(tasteProfile: tasteProfile, candidates: candidates, topN: topN)
        let schema = buildSchema()
        let data = try await runClaude(
            at: claudePath,
            prompt: prompt,
            schema: schema,
            systemPrompt: systemPrompt
        )
        return try parseClaudeOutput(data, candidates: candidates)
    }
}

import Foundation
import BirdService
import ScorerService
import DigestService
import XdigestCore

/// Result of running the pipeline: the new (merged) digest and the updated
/// set of seen IDs. The caller is responsible for persisting both -- the
/// pipeline itself does no disk I/O on the output side.
public struct GenerateOutcome: Sendable {
    public let digest: Digest
    public let seenIds: Set<String>
}

/// Runs the full digest pipeline: fetch -> score -> assemble -> merge.
///
/// `currentDigest` is the app's authoritative current digest (from DigestState),
/// not read from disk. This ensures the pipeline never diverges from the
/// in-memory server state.
public func generate(
    currentDigest: Digest?,
    count: Int = 100,
    topN: Int = 10,
    cacheDir: URL = defaultCacheDir(),
    onProgress: (@Sendable (String) -> Void)? = nil
) async throws -> GenerateOutcome {
    let bird = try BirdService()
    let scorer = try ScorerService()

    let seen = loadSeen(from: cacheDir)

    onProgress?("Fetching your timeline...")
    let tweets = try await withRetry { try await bird.fetchHome(count: count) }
    onProgress?("Loading your taste profile...")
    let tasteProfile = try await withRetry { try await loadTasteProfile(using: bird, cacheDir: cacheDir) }
    onProgress?("Scoring posts against your taste...")
    let scored = try await withRetry {
        try await scorer.score(tweets, tasteProfile: tasteProfile, topN: topN, seen: seen)
    }
    onProgress?("Assembling your digest...")
    let newDigest = assemble(scored)

    let newIds = renderedIds(from: newDigest)
    let updatedSeen = newIds.isEmpty ? seen : seen.union(newIds)

    let merged = mergeDigests(new: newDigest, existing: currentDigest)

    return GenerateOutcome(digest: merged, seenIds: updatedSeen)
}

/// Prepends new sections to an existing digest. Drops posts from the new
/// section whose text content already appears in existing sections --
/// catches legitimate content duplicates (reposts with different IDs,
/// account re-shares) that the by-ID seen cache can't detect.
private func mergeDigests(new: Digest, existing: Digest?) -> Digest {
    guard let existing else { return new }
    let existingTexts = Set(existing.sections.flatMap { $0.posts }.map { normalizedText($0.tweet.text) })
    let dedupedSections = new.sections.compactMap { section -> DigestSection? in
        let kept = section.posts.filter { !existingTexts.contains(normalizedText($0.tweet.text)) }
        return kept.isEmpty ? nil : DigestSection(timestamp: section.timestamp, posts: kept)
    }
    return Digest(date: new.date, sections: dedupedSections + existing.sections)
}

private func normalizedText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        .lowercased()
}

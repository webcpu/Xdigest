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
    cacheDir: URL = defaultCacheDir()
) async throws -> GenerateOutcome {
    let bird = try BirdService()
    let scorer = try ScorerService()

    let seen = loadSeen(from: cacheDir)

    let tweets = try await withRetry { try await bird.fetchHome(count: count) }
    let bookmarks = try await withRetry { try await loadBookmarks(using: bird, cacheDir: cacheDir) }
    let scored = try await withRetry {
        try await scorer.score(tweets, against: bookmarks, topN: topN, seen: seen)
    }
    let newDigest = assemble(scored)

    let newIds = renderedIds(from: newDigest)
    let updatedSeen = newIds.isEmpty ? seen : seen.union(newIds)

    let merged = mergeDigests(new: newDigest, existing: currentDigest)

    return GenerateOutcome(digest: merged, seenIds: updatedSeen)
}

/// Prepends new sections to an existing digest.
private func mergeDigests(new: Digest, existing: Digest?) -> Digest {
    guard let existing else { return new }
    let allSections = new.sections + existing.sections
    return Digest(date: new.date, sections: allSections)
}

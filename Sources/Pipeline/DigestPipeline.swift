import Foundation
import BirdService
import ScorerService
import DigestService
import XdigestCore

/// Runs the full digest pipeline: fetch -> score -> assemble.
/// Manages the seen cache for cross-run dedup.
public func generate(
    count: Int = 100,
    topN: Int = 10,
    cacheDir: URL = defaultCacheDir()
) async throws -> Digest {
    let bird = try BirdService()
    let scorer = try ScorerService()

    let seen = loadSeen(from: cacheDir)

    let tweets = try await withRetry { try await bird.fetchHome(count: count) }
    let bookmarks = try await withRetry { try await bird.fetchBookmarks() }
    let scored = try await withRetry {
        try await scorer.score(tweets, against: bookmarks, topN: topN, seen: seen)
    }
    let newDigest = assemble(scored)

    let newIds = renderedIds(from: newDigest)
    if !newIds.isEmpty {
        let updated = seen.union(newIds)
        try saveSeen(updated, to: cacheDir)
    }

    // Merge: prepend new sections to existing digest
    let existing = loadDigest(from: cacheDir)
    let merged = mergeDigests(new: newDigest, existing: existing)

    try saveDigest(merged, to: cacheDir)
    return merged
}

/// Prepends new sections to an existing digest.
private func mergeDigests(new: Digest, existing: Digest?) -> Digest {
    guard let existing else { return new }
    let allSections = new.sections + existing.sections
    return Digest(date: new.date, sections: allSections)
}

import Foundation
import XdigestCore

/// Assembles scored posts into a Digest.
/// Filters by threshold, deduplicates reposts, caps at top N.
public func assemble(
    _ posts: [ScoredPost],
    threshold: Double = 0.0,
    top: Int = .max
) -> Digest {
    let passing = filterByThreshold(posts, minimum: threshold)
    let deduped = deduplicateReposts(passing)
    let capped = cap(deduped, at: top)
    let section = DigestSection(timestamp: currentTimestamp(), posts: capped)
    return Digest(date: currentDate(), sections: [section])
}

/// Collects all tweet IDs and repost original IDs from a digest.
/// Used to update the seen cache after rendering.
public func renderedIds(from digest: Digest) -> Set<String> {
    var ids = Set<String>()
    for section in digest.sections {
        for post in section.posts {
            ids.insert(post.tweet.id)
            if let originalId = post.tweet.repost?.originalId {
                ids.insert(originalId)
            }
        }
    }
    return ids
}

// MARK: - Helpers

/// Keeps only posts at or above the minimum score.
private func filterByThreshold(_ posts: [ScoredPost], minimum: Double) -> [ScoredPost] {
    posts.filter { $0.score >= minimum }
}

/// Removes reposts whose original tweet is already in the list.
private func deduplicateReposts(_ posts: [ScoredPost]) -> [ScoredPost] {
    let tweetIds = Set(posts.map(\.tweet.id))
    return posts.filter { post in
        guard let originalId = post.tweet.repost?.originalId else { return true }
        return !tweetIds.contains(originalId)
    }
}

/// Takes the first N posts.
private func cap(_ posts: [ScoredPost], at limit: Int) -> [ScoredPost] {
    Array(posts.prefix(limit))
}

private func currentTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: Date())
}

private func currentDate() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

import XdigestCore

/// Removes tweets already shown in previous digests.
/// Checks both the tweet's own ID and the original ID for reposts.
public func filterSeenTweets(_ tweets: [Tweet], seen: Set<String>) -> [Tweet] {
    guard !seen.isEmpty else { return tweets }
    return tweets.filter { tweet in
        if seen.contains(tweet.id) { return false }
        if let originalId = tweet.repost?.originalId, seen.contains(originalId) { return false }
        return true
    }
}

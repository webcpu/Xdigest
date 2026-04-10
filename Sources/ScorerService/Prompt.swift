import XdigestCore

/// Formats a bookmark line for the prompt: "- @handle: text"
private func formatBookmarkLine(_ bookmark: Bookmark) -> String {
    let handle = bookmark.author.username
    let text = truncate(bookmark.text, limit: 600)
    return "- @\(handle): \(text)"
}

/// Formats a candidate line with index: "[0] @handle: text"
private func formatCandidateLine(index: Int, tweet: Tweet) -> String {
    let handle = tweet.author.username
    let text = truncate(tweet.text, limit: 800)
    return "[\(index)] @\(handle): \(text)"
}

/// Truncates text to a character limit, appending "..." if clipped.
private func truncate(_ text: String, limit: Int) -> String {
    let cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    guard cleaned.count > limit else { return cleaned }
    return String(cleaned.prefix(limit)) + "..."
}

/// Builds the scoring prompt for Claude.
public func buildPrompt(bookmarks: [Bookmark], candidates: [Tweet], topN: Int) -> String {
    let bookmarkLines = bookmarks.map(formatBookmarkLine)
    let candidateLines = candidates.enumerated().map { formatCandidateLine(index: $0.offset, tweet: $0.element) }

    return """
    Here are \(bookmarkLines.count) tweets the user recently bookmarked (taste signal):

    \(bookmarkLines.joined(separator: "\n"))

    ---

    Here are \(candidateLines.count) candidate tweets from their For You feed:

    \(candidateLines.joined(separator: "\n"))

    ---

    Pick the top \(topN) candidates that best match the user's taste. \
    Return a JSON object with a single field `picks`, an array of objects \
    each with `index` (integer referencing the candidate number above), \
    `score` (number 0..1), `reason` (one sentence), and `tags` (array of \
    short lowercase keyword tags describing the post's topics and concepts \
    -- include broader categories, e.g. a post about linear algebra should \
    also be tagged 'math'; let the post length guide how many tags you \
    generate). Sort by score descending. Prefer quality over quantity: if \
    fewer than \(topN) are genuinely strong, return fewer.
    """
}

/// Returns the JSON schema string for Claude's structured output.
public func buildSchema() -> String {
    """
    {"type":"object","properties":{"picks":{"type":"array","items":{"type":"object","properties":{"index":{"type":"integer"},"score":{"type":"number"},"reason":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["index","score","reason","tags"]}}},"required":["picks"]}
    """
}

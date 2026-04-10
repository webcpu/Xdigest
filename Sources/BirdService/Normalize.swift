import Foundation
import XdigestCore

/// Normalizes a raw bird tweet into a clean Tweet.
public func normalize(_ raw: RawBirdTweet) throws -> Tweet {
    let rawJSON = raw._raw
    let fullText = extractFullText(raw: rawJSON, fallback: raw.text)
    let repost = try extractRepost(raw: rawJSON, retweeter: raw.author)
    let (author, avatarUrl) = resolveAuthor(
        raw: rawJSON, repost: repost, fallbackAuthor: raw.author
    )
    let media = raw.media?.compactMap(normalizeMedia)
    let (urlReplacements, urlStrip) = extractUrlEntities(raw: rawJSON)

    return Tweet(
        id: raw.id,
        text: fullText,
        createdAt: raw.createdAt,
        author: author,
        authorId: raw.authorId,
        replyCount: raw.replyCount,
        retweetCount: raw.retweetCount,
        likeCount: raw.likeCount,
        conversationId: raw.conversationId,
        media: media,
        avatarUrl: avatarUrl,
        repost: repost,
        urlReplacements: urlReplacements.isEmpty ? nil : urlReplacements,
        urlStrip: urlStrip.isEmpty ? nil : urlStrip,
        quotedTweet: try raw.quotedTweet.map(normalize)
    )
}

// MARK: - Author Resolution

/// For reposts, returns the original author and avatar. Otherwise the tweet's own.
private func resolveAuthor(
    raw: JSONValue?,
    repost: Repost?,
    fallbackAuthor: RawAuthor
) -> (Author, String?) {
    let tweetAvatarUrl = extractAvatarUrl(raw: raw)

    if let repost {
        let author = Author(username: repost.originalHandle, name: repost.originalName)
        let avatar = repost.originalAvatarUrl ?? tweetAvatarUrl
        return (author, avatar)
    }

    let author = Author(username: fallbackAuthor.username, name: fallbackAuthor.name)
    return (author, tweetAvatarUrl)
}

// MARK: - Full Text Extraction

private func extractFullText(raw: JSONValue?, fallback: String) -> String {
    guard let raw else { return fallback }
    return extractRetweetFullText(raw: raw)
        ?? extractOwnFullText(raw: raw)
        ?? fallback
}

/// Extracts full text from the retweeted original (note tweet or legacy).
private func extractRetweetFullText(raw: JSONValue) -> String? {
    guard let rts = raw["legacy"]?["retweeted_status_result"]?["result"]
    else { return nil }
    return noteText(from: rts)
        ?? rts["legacy"]?["full_text"]?.stringValue
}

/// Extracts full text from this tweet's own note tweet or legacy.
private func extractOwnFullText(raw: JSONValue) -> String? {
    noteText(from: raw)
        ?? raw["legacy"]?["full_text"]?.stringValue
}

private func noteText(from obj: JSONValue) -> String? {
    obj["note_tweet"]?["note_tweet_results"]?["result"]?["text"]?.stringValue
}

// MARK: - Avatar Extraction

private func extractAvatarUrl(raw: JSONValue?) -> String? {
    raw?["core"]?["user_results"]?["result"]?["avatar"]?["image_url"]?.stringValue
}

// MARK: - Repost Detection

private func extractRepost(raw: JSONValue?, retweeter: RawAuthor) throws -> Repost? {
    guard let raw,
          let rts = raw["legacy"]?["retweeted_status_result"]?["result"]
    else { return nil }

    let origUser = rts["core"]?["user_results"]?["result"]
    let origCore = origUser?["core"]

    guard let origHandle = origCore?["screen_name"]?.stringValue,
          !origHandle.isEmpty
    else {
        throw XdigestError.birdOutputInvalid(
            command: "normalize",
            detail: "retweet missing original author screen_name"
        )
    }

    guard let origId = rts["rest_id"]?.stringValue,
          !origId.isEmpty
    else {
        throw XdigestError.birdOutputInvalid(
            command: "normalize",
            detail: "retweet missing original tweet rest_id"
        )
    }

    // Skip self-reposts
    guard origHandle.lowercased() != retweeter.username.lowercased()
    else { return nil }

    let origName = origCore?["name"]?.stringValue ?? origHandle
    let origAvatar = origUser?["avatar"]?["image_url"]?.stringValue

    return Repost(
        retweeterHandle: retweeter.username,
        retweeterName: retweeter.name,
        originalHandle: origHandle,
        originalName: origName,
        originalId: origId,
        originalAvatarUrl: origAvatar
    )
}

// MARK: - URL Entity Extraction

/// Extracts URL replacements and strip set from the tweet's _raw payload.
/// replacements: t.co -> expanded URL (for article links)
/// strip: t.co URLs pointing to media (already rendered separately)
private func extractUrlEntities(raw: JSONValue?) -> ([String: String], [String]) {
    guard let raw else { return ([:], []) }
    var replacements: [String: String] = [:]
    var stripSet: Set<String> = []

    let legacy = raw["legacy"]

    // Main tweet entities
    collectEntities(from: legacy?["entities"], replacements: &replacements, stripSet: &stripSet)
    collectEntities(from: legacy?["extended_entities"], replacements: &replacements, stripSet: &stripSet)

    // Note tweet entities
    let noteEntitySet = raw["note_tweet"]?["note_tweet_results"]?["result"]?["entity_set"]
    collectEntities(from: noteEntitySet, replacements: &replacements, stripSet: &stripSet)

    // Retweeted status entities
    if let rts = legacy?["retweeted_status_result"]?["result"] {
        collectEntities(from: rts["legacy"]?["entities"], replacements: &replacements, stripSet: &stripSet)
        collectEntities(from: rts["legacy"]?["extended_entities"], replacements: &replacements, stripSet: &stripSet)
        let rtsNote = rts["note_tweet"]?["note_tweet_results"]?["result"]?["entity_set"]
        collectEntities(from: rtsNote, replacements: &replacements, stripSet: &stripSet)
    }

    return (replacements, Array(stripSet))
}

/// Collects URL and media entities from an entity set.
private func collectEntities(
    from entitySet: JSONValue?,
    replacements: inout [String: String],
    stripSet: inout Set<String>
) {
    guard let entitySet else { return }

    // URL entities -> replacements
    if case .array(let urls) = entitySet["urls"] {
        for u in urls {
            if let tco = u["url"]?.stringValue,
               let expanded = u["expanded_url"]?.stringValue {
                replacements[tco] = expanded
            }
        }
    }

    // Media entities -> strip set
    if case .array(let media) = entitySet["media"] {
        for m in media {
            if let tco = m["url"]?.stringValue {
                stripSet.insert(tco)
            }
        }
    }
}

// MARK: - Media Normalization

private func normalizeMedia(_ raw: RawMedia) -> Media? {
    guard let type = MediaType(rawValue: raw.type) else { return nil }
    return Media(
        type: type,
        url: raw.url,
        width: raw.width ?? 0,
        height: raw.height ?? 0,
        previewUrl: raw.previewUrl,
        videoUrl: raw.videoUrl,
        durationMs: raw.durationMs
    )
}

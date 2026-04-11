import Foundation
import XdigestCore

// MARK: - Public API

/// Renders a single scored post as an HTML card.
///
/// The card structure matches the reader's JS expectations:
/// - Avatar img with width="32" (used by search to locate posts)
/// - `data-tags` attribute on the outer div (used by search for tag matching)
/// - Links to `x.com/username/status/id`
/// Resolved display identity for a post (original author for reposts).
private struct DisplayAuthor {
    let handle: String
    let name: String
    let avatar: String
    let tweetId: String
}

/// Resolves who to display as the author. For reposts, shows the original author.
private func resolveDisplayAuthor(_ tweet: Tweet) -> DisplayAuthor {
    if let repost = tweet.repost {
        return DisplayAuthor(
            handle: repost.originalHandle,
            name: repost.originalName,
            avatar: repost.originalAvatarUrl ?? "",
            tweetId: repost.originalId
        )
    }
    return DisplayAuthor(
        handle: tweet.author.username,
        name: tweet.author.name,
        avatar: tweet.avatarUrl ?? "",
        tweetId: tweet.id
    )
}

public func renderPost(_ post: ScoredPost) -> String {
    let tweet = post.tweet
    let display = resolveDisplayAuthor(tweet)
    let tweetURL = "https://x.com/\(escapeHTML(display.handle))/status/\(escapeHTML(display.tweetId))"
    let tagsAttr = post.tags.joined(separator: ",")
    let cleanedText = cleanTextForDisplay(tweet)
    let escapedText = escapeHTML(cleanedText)
    let withBreaks = newlinesToBreaks(escapedText)
    let textWithLinks = linkify(withBreaks)

    let relTime = relativeTime(tweet.createdAt)

    var parts: [String] = []

    // Post card outer div (data-post-id enables cross-device position sync)
    parts.append(
        """
        <div style="display:flex;gap:8px;padding:14px 0;border-bottom:1px solid #2f3336;" data-post-id="\(escapeHTML(display.tweetId))" data-tags="\(escapeHTML(tagsAttr))">
        """
    )

    // Avatar
    parts.append(
        """
        <img src="\(escapeHTML(display.avatar))" width="32" height="32" \
        style="border-radius:50%;flex-shrink:0;align-self:flex-start;" \
        onerror="this.style.display='none'" loading="lazy">
        """
    )

    // Content column
    parts.append("<div style=\"flex:1;min-width:0;\">")

    // Repost credit line (inside content column, matching Python)
    if let repost = tweet.repost {
        parts.append(
            """
            <div style="color:#536471;font-size:13px;margin-bottom:4px;">\
            &#128257; \(escapeHTML(repost.retweeterName)) reposted</div>
            """
        )
    }

    // Author line with time
    let timeSpan = relTime.isEmpty ? "" : "<span style=\"color:#536471;font-size:14px;\"> &middot; \(escapeHTML(relTime))</span>"
    parts.append(
        """
        <div style="line-height:1.3;margin-bottom:2px;">\
        <strong style="font-size:15px;">\(escapeHTML(display.name))</strong> \
        <a href="\(tweetURL)" style="color:#536471;font-size:14px;text-decoration:none;">\
        @\(escapeHTML(display.handle))</a>\
        \(timeSpan)</div>
        """
    )

    // Tweet text
    parts.append(
        """
        <div style="font-size:15px;line-height:1.5;padding:4px 0;">\(textWithLinks)</div>
        """
    )

    // Media
    if let mediaItems = tweet.media {
        parts.append(renderMedia(mediaItems))
    }

    // Quoted tweet
    if let quoted = tweet.quotedTweet {
        parts.append(renderQuotedTweet(quoted))
    }

    // Link to original
    parts.append(
        """
        <a href="\(tweetURL)" style="color:#7a8088;font-size:12px;text-decoration:none;" target="_blank">&#128279; original</a>
        """
    )

    // Close content column and card div
    parts.append("</div>")
    parts.append("</div>")

    return parts.joined(separator: "\n")
}

/// Renders a digest section as a foldable `<details>` element.
public func renderSection(_ section: DigestSection) -> String {
    let postsHTML = section.posts.map { renderPost($0) }.joined(separator: "\n")
    return """
    <details class="section" open>\
    <summary class="section-time">\(escapeHTML(section.timestamp))</summary>\
    \(postsHTML)\
    </details>
    """
}

/// Renders a full digest as an HTML fragment (sections concatenated).
public func renderDigest(_ digest: Digest) -> String {
    digest.sections.map { renderSection($0) }.joined(separator: "\n")
}

/// Returns the complete reader HTML page with digest content embedded.
public func readerPage(
    digestHTML: String,
    initialPosition: String = "",
    initialFraction: Double = 0,
    initialVersion: Int = 0,
    instanceId: String = ""
) -> String {
    readerTemplate
        .replacingOccurrences(of: "<!--DIGEST_DATA-->", with: digestHTML)
        .replacingOccurrences(of: "<!--INITIAL_POSITION-->", with: escapeHTML(initialPosition))
        .replacingOccurrences(of: "<!--INITIAL_FRACTION-->", with: "\(initialFraction)")
        .replacingOccurrences(of: "<!--INITIAL_VERSION-->", with: "\(initialVersion)")
        .replacingOccurrences(of: "<!--INSTANCE_ID-->", with: escapeHTML(instanceId))
}

// MARK: - Helpers

/// Decodes HTML entities in text (e.g. &amp; -> &).
private func unescapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&#x27;", with: "'")
}

/// Escapes HTML special characters to prevent XSS.
private func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

/// Cleans tweet text for display:
/// - Strips "RT @user:" prefix
/// - Expands t.co URLs to real destinations
/// - Strips t.co URLs that point to media (already rendered separately)
/// - Drops remaining unknown t.co URLs
/// - Collapses excess whitespace
private func cleanTextForDisplay(_ tweet: Tweet) -> String {
    var text = tweet.text

    // Strip RT prefix
    if let range = text.range(of: #"^RT @\w+:\s*"#, options: .regularExpression) {
        text.removeSubrange(range)
    }

    // Expand t.co URLs to real URLs
    if let replacements = tweet.urlReplacements {
        for (tco, expanded) in replacements {
            text = text.replacingOccurrences(of: tco, with: expanded)
        }
    }

    // Strip t.co URLs that point to media
    if let strip = tweet.urlStrip {
        for tco in strip {
            text = text.replacingOccurrences(of: tco, with: "")
        }
    }

    // Drop remaining t.co URLs (unknown/orphaned)
    text = text.replacingOccurrences(
        of: #"https?://t\.co/\w+"#,
        with: "",
        options: .regularExpression
    )

    // Decode HTML entities (bird sometimes returns pre-escaped text)
    text = unescapeHTML(text)

    // Collapse excess whitespace
    text = text.replacingOccurrences(
        of: #"[^\S\n]{2,}"#,
        with: " ",
        options: .regularExpression
    ).trimmingCharacters(in: .whitespaces)

    return text
}

/// Converts newlines to HTML line breaks.
private func newlinesToBreaks(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "<br>")
        .replacingOccurrences(of: "\n", with: "<br>")
}

/// Converts bare URLs in text to clickable links with shortened display text.
private func linkify(_ text: String) -> String {
    let pattern = #"(https?://[^\s<>&"]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    var result = text
    // Process matches in reverse order to preserve indices
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    for match in matches.reversed() {
        guard let range = Range(match.range, in: result) else { continue }
        let url = String(result[range])
        let display = shortenUrl(url)
        let link = "<a href=\"\(url)\" style=\"color:#1d9bf0;text-decoration:none;\" target=\"_blank\">\(display)</a>"
        result.replaceSubrange(range, with: link)
    }
    return result
}

/// Rewrites a video URL to go through the local proxy.
private func proxyUrl(_ url: String) -> String {
    guard !url.isEmpty else { return "" }
    let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
    return "/proxy?url=\(encoded)"
}

/// Shortens a URL for display: strips protocol and www, truncates at 35 chars.
private func shortenUrl(_ url: String) -> String {
    var display = url
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "www.", with: "")
    // Strip trailing slash
    if display.hasSuffix("/") { display = String(display.dropLast()) }
    if display.count > 35 {
        return String(display.prefix(35)) + "..."
    }
    return display
}

/// Computes relative time string from a Twitter date string (e.g. "3h", "2d").
private func relativeTime(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
    guard let date = formatter.date(from: dateString) else { return "" }
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    return "\(days)d"
}

/// Renders media items (photos, videos, gifs) as HTML.
private func renderMedia(_ items: [Media]) -> String {
    items.map { item in
        switch item.type {
        case .photo:
            return """
            <img src="\(escapeHTML(item.url))" \
            style="border-radius:16px;margin-top:12px;max-width:100%;" loading="lazy">
            """
        case .video, .animatedGif:
            let poster = escapeHTML(item.previewUrl ?? item.url)
            let videoSrc = item.videoUrl ?? ""
            let proxiedSrc = proxyUrl(videoSrc)
            return """
            <video poster="\(poster)" data-src="\(escapeHTML(proxiedSrc))" \
            preload="none" style="border-radius:16px;margin-top:12px;max-width:100%;max-height:560px;width:auto;height:auto;" \
            controls playsinline></video>
            """
        }
    }.joined(separator: "\n")
}

/// Renders a quoted tweet as an indented block.
private func renderQuotedTweet(_ tweet: Tweet) -> String {
    let handle = tweet.author.username
    let name = tweet.author.name
    let url = "https://x.com/\(escapeHTML(handle))/status/\(escapeHTML(tweet.id))"
    let cleaned = cleanTextForDisplay(tweet)
    let text = linkify(newlinesToBreaks(escapeHTML(cleaned)))

    return """
    <div style="border:1px solid #2f3336;border-radius:12px;padding:12px;margin-top:8px;">
    <div><b>\(escapeHTML(name))</b> \
    <a href="https://x.com/\(escapeHTML(handle))" style="color:#7a8088;text-decoration:none;">\
    @\(escapeHTML(handle))</a></div>
    <div style="font-size:14px;line-height:1.4;padding:4px 0;">\(text)</div>
    <a href="\(url)" style="color:#7a8088;font-size:12px;text-decoration:none;" target="_blank">&#128279;</a>
    </div>
    """
}

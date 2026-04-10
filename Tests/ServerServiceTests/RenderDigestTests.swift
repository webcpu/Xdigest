import Foundation
import Testing
@testable import ServerService
@testable import XdigestCore

// MARK: - renderPost

@Test("Renders a post with author, text, and link")
func renderPostBasic() {
    let post = makeScored(
        id: "123",
        text: "Hello world",
        username: "alice",
        name: "Alice",
        avatarUrl: "https://pbs.twimg.com/profile_images/alice.jpg"
    )
    let html = renderPost(post)

    #expect(html.contains("alice"))
    #expect(html.contains("Alice"))
    #expect(html.contains("Hello world"))
    #expect(html.contains("https://x.com/alice/status/123"))
    #expect(html.contains("alice.jpg"))
}

@Test("Renders a repost with retweeter credit")
func renderPostRepost() {
    let repost = Repost(
        retweeterHandle: "bob",
        retweeterName: "Bob",
        originalHandle: "alice",
        originalName: "Alice",
        originalId: "50",
        originalAvatarUrl: "https://pbs.twimg.com/profile_images/alice.jpg"
    )
    let post = makeScored(
        id: "100",
        text: "Great insight",
        username: "bob",
        name: "Bob",
        repost: repost
    )
    let html = renderPost(post)

    // Should show retweeter credit (display name)
    #expect(html.contains("Bob"))
    #expect(html.contains("reposted"))
    // Should show original author as the main author
    #expect(html.contains("Alice"))
    #expect(html.contains("alice"))
    // Should link to original tweet
    #expect(html.contains("/status/50"))
}

@Test("Renders post with photo media")
func renderPostWithPhoto() {
    let media = [Media(
        type: .photo,
        url: "https://pbs.twimg.com/media/photo1.jpg",
        width: 800,
        height: 600
    )]
    let post = makeScored(id: "1", text: "Look at this", media: media)
    let html = renderPost(post)

    #expect(html.contains("photo1.jpg"))
    #expect(html.contains("<img"))
}

@Test("Renders post with video media using poster and data-src")
func renderPostWithVideo() {
    let media = [Media(
        type: .video,
        url: "https://pbs.twimg.com/thumb.jpg",
        width: 1280,
        height: 720,
        previewUrl: "https://pbs.twimg.com/thumb.jpg",
        videoUrl: "https://video.twimg.com/ext_tw_video/123/video.mp4"
    )]
    let post = makeScored(id: "1", text: "Watch this", media: media)
    let html = renderPost(post)

    #expect(html.contains("<video"))
    #expect(html.contains("poster="))
    #expect(html.contains("data-src="))
}

@Test("Renders post with tags as data attribute")
func renderPostWithTags() {
    let post = makeScored(id: "1", text: "AI stuff", tags: ["ai", "ml", "research"])
    let html = renderPost(post)

    #expect(html.contains("data-tags=\"ai,ml,research\""))
}

@Test("Score is not displayed in rendered HTML (matches X style)")
func renderPostDoesNotShowScore() {
    let post = makeScored(id: "1", text: "Good post", score: 0.85)
    let html = renderPost(post)

    #expect(!html.contains("0.85"))
}

@Test("Escapes HTML in tweet text")
func renderPostEscapesHTML() {
    let post = makeScored(id: "1", text: "Use <script>alert('xss')</script> carefully")
    let html = renderPost(post)

    #expect(!html.contains("<script>alert"))
    #expect(html.contains("&lt;script&gt;"))
}

// MARK: - renderSection

@Test("Renders a section with timestamp header and posts")
func renderSectionBasic() {
    let posts = [
        makeScored(id: "1", text: "First"),
        makeScored(id: "2", text: "Second"),
    ]
    let section = DigestSection(timestamp: "14:30", posts: posts)
    let html = renderSection(section)

    #expect(html.contains("14:30"))
    #expect(html.contains("<details"))
    #expect(html.contains("section"))
    #expect(html.contains("First"))
    #expect(html.contains("Second"))
}

@Test("Renders section with open attribute by default")
func renderSectionOpen() {
    let section = DigestSection(timestamp: "10:00", posts: [makeScored(id: "1", text: "Hi")])
    let html = renderSection(section)

    #expect(html.contains("open"))
}

// MARK: - renderDigest

@Test("Renders full digest with all sections")
func renderDigestFull() {
    let section1 = DigestSection(timestamp: "10:00", posts: [makeScored(id: "1", text: "Morning")])
    let section2 = DigestSection(timestamp: "14:00", posts: [makeScored(id: "2", text: "Afternoon")])
    let digest = Digest(date: "2026-04-10", sections: [section1, section2])
    let html = renderDigest(digest)

    #expect(html.contains("10:00"))
    #expect(html.contains("14:00"))
    #expect(html.contains("Morning"))
    #expect(html.contains("Afternoon"))
}

@Test("Renders empty digest as empty string")
func renderDigestEmpty() {
    let digest = Digest(date: "2026-04-10", sections: [])
    let html = renderDigest(digest)

    #expect(html.isEmpty)
}

// MARK: - readerPage

@Test("Reader page contains digest HTML in the timeline div")
func readerPageContainsDigest() {
    let page = readerPage(digestHTML: "<p>test content</p>")

    #expect(page.contains("<p>test content</p>"))
    #expect(page.contains("<!DOCTYPE html>"))
    #expect(page.contains("xdigest"))
    #expect(page.contains("timeline"))
}

@Test("Reader page works with empty digest")
func readerPageEmpty() {
    let page = readerPage(digestHTML: "")

    #expect(page.contains("<!DOCTYPE html>"))
    #expect(page.contains("timeline"))
}

// MARK: - Helpers

private func makeScored(
    id: String,
    text: String,
    username: String = "user",
    name: String = "User",
    avatarUrl: String? = nil,
    score: Double = 0.8,
    repost: Repost? = nil,
    media: [Media]? = nil,
    tags: [String] = ["test"]
) -> ScoredPost {
    let tweet = Tweet(
        id: id,
        text: text,
        createdAt: "Thu Apr 10 12:00:00 +0000 2026",
        author: Author(username: username, name: name),
        authorId: "1",
        media: media,
        avatarUrl: avatarUrl,
        repost: repost
    )
    return ScoredPost(tweet: tweet, score: score, reason: "test", tags: tags)
}

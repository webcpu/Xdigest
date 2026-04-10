import Foundation
import Testing
@testable import DigestService
@testable import XdigestCore

// MARK: - Assemble

@Test("Assembles scored posts into a digest with one section")
func assemblesIntoDigest() {
    let posts = [
        makeScored(id: "1", score: 0.9),
        makeScored(id: "2", score: 0.7),
    ]
    let digest = assemble(posts)

    #expect(digest.sections.count == 1)
    #expect(digest.sections[0].posts.count == 2)
    #expect(!digest.date.isEmpty)
    #expect(!digest.sections[0].timestamp.isEmpty)
}

@Test("Assemble filters posts below threshold")
func assembleFiltersLowScores() {
    let posts = [
        makeScored(id: "1", score: 0.9),
        makeScored(id: "2", score: 0.3),
        makeScored(id: "3", score: 0.8),
    ]
    let digest = assemble(posts, threshold: 0.5)

    #expect(digest.sections[0].posts.count == 2)
    #expect(digest.sections[0].posts[0].tweet.id == "1")
    #expect(digest.sections[0].posts[1].tweet.id == "3")
}

@Test("Assemble caps at top N posts")
func assembleCapsAtTopN() {
    let posts = (1...10).map { makeScored(id: "\($0)", score: 0.9) }
    let digest = assemble(posts, top: 3)

    #expect(digest.sections[0].posts.count == 3)
}

@Test("Assemble returns empty digest when no posts pass threshold")
func assembleEmptyWhenNonePass() {
    let posts = [
        makeScored(id: "1", score: 0.2),
        makeScored(id: "2", score: 0.1),
    ]
    let digest = assemble(posts, threshold: 0.5)

    #expect(digest.sections.count == 1)
    #expect(digest.sections[0].posts.isEmpty)
}

@Test("Assemble returns empty digest for empty input")
func assembleEmptyInput() {
    let digest = assemble([])
    #expect(digest.sections.count == 1)
    #expect(digest.sections[0].posts.isEmpty)
}

// MARK: - Repost Dedup

@Test("Assemble removes repost when original is already in the list")
func assembleDedupsRepost() {
    let original = makeScored(id: "50", score: 0.9)
    let repost = makeScored(id: "100", score: 0.8, repost: Repost(
        retweeterHandle: "a", retweeterName: "A",
        originalHandle: "b", originalName: "B",
        originalId: "50"
    ))
    let digest = assemble([original, repost])

    #expect(digest.sections[0].posts.count == 1)
    #expect(digest.sections[0].posts[0].tweet.id == "50")
}

@Test("Assemble keeps repost when original is not in the list")
func assembleKeepsUniqueRepost() {
    let repost = makeScored(id: "100", score: 0.8, repost: Repost(
        retweeterHandle: "a", retweeterName: "A",
        originalHandle: "b", originalName: "B",
        originalId: "999"
    ))
    let digest = assemble([repost])

    #expect(digest.sections[0].posts.count == 1)
}

@Test("Assemble keeps repost when original is below threshold")
func assembleKeepsRepostWhenOriginalFiltered() {
    let original = makeScored(id: "50", score: 0.2)
    let repost = makeScored(id: "100", score: 0.8, repost: Repost(
        retweeterHandle: "a", retweeterName: "A",
        originalHandle: "b", originalName: "B",
        originalId: "50"
    ))
    let digest = assemble([original, repost], threshold: 0.5)

    #expect(digest.sections[0].posts.count == 1)
    #expect(digest.sections[0].posts[0].tweet.id == "100")
}

// MARK: - Rendered IDs

@Test("renderedIds collects tweet IDs")
func renderedIdsCollectsTweetIds() {
    let posts = [
        makeScored(id: "a", score: 0.9),
        makeScored(id: "b", score: 0.8),
    ]
    let digest = assemble(posts)
    let ids = renderedIds(from: digest)

    #expect(ids.contains("a"))
    #expect(ids.contains("b"))
}

@Test("renderedIds includes repost originalIds")
func renderedIdsIncludesOriginalIds() {
    let repost = Repost(
        retweeterHandle: "x", retweeterName: "X",
        originalHandle: "y", originalName: "Y",
        originalId: "orig-99"
    )
    let posts = [makeScored(id: "100", score: 0.9, repost: repost)]
    let digest = assemble(posts)
    let ids = renderedIds(from: digest)

    #expect(ids.contains("100"))
    #expect(ids.contains("orig-99"))
}

@Test("renderedIds returns empty set for empty digest")
func renderedIdsEmpty() {
    let digest = assemble([])
    let ids = renderedIds(from: digest)
    #expect(ids.isEmpty)
}

// MARK: - Helpers

private func makeScored(
    id: String,
    score: Double,
    repost: Repost? = nil
) -> ScoredPost {
    let tweet = Tweet(
        id: id,
        text: "Post \(id)",
        createdAt: "Thu Apr 10 12:00:00 +0000 2026",
        author: Author(username: "user", name: "User"),
        authorId: "1",
        repost: repost
    )
    return ScoredPost(tweet: tweet, score: score, reason: "test", tags: ["test"])
}

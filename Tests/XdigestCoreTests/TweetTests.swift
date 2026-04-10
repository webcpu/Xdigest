import Foundation
import Testing
@testable import XdigestCore

@Test("Decodes a tweet from bird JSON")
func decodesTweetFromBirdJSON() throws {
    let json = """
    {
      "id": "2042125968052302319",
      "text": "The number that should terrify every Western automaker is 1,500 kW.",
      "createdAt": "Thu Apr 09 06:22:26 +0000 2026",
      "replyCount": 42,
      "retweetCount": 180,
      "likeCount": 1200,
      "conversationId": "2042125968052302319",
      "author": { "username": "aakashgupta", "name": "Aakash Gupta" },
      "authorId": "123456",
      "media": [
        {
          "type": "photo",
          "url": "https://pbs.twimg.com/media/example.jpg",
          "width": 1200,
          "height": 800,
          "previewUrl": "https://pbs.twimg.com/media/example.jpg:small"
        }
      ]
    }
    """.data(using: .utf8)!

    let tweet = try JSONDecoder().decode(Tweet.self, from: json)

    #expect(tweet.id == "2042125968052302319")
    #expect(tweet.text == "The number that should terrify every Western automaker is 1,500 kW.")
    #expect(tweet.author.username == "aakashgupta")
    #expect(tweet.author.name == "Aakash Gupta")
    #expect(tweet.media?.count == 1)
    #expect(tweet.media?.first?.type == .photo)
    #expect(tweet.media?.first?.width == 1200)
}

@Test("Decodes a tweet with video media")
func decodesTweetWithVideo() throws {
    let json = """
    {
      "id": "123",
      "text": "Check this out",
      "createdAt": "Thu Apr 09 06:22:26 +0000 2026",
      "author": { "username": "test", "name": "Test" },
      "authorId": "1",
      "media": [
        {
          "type": "video",
          "url": "https://pbs.twimg.com/thumb.jpg",
          "width": 1920,
          "height": 1080,
          "previewUrl": "https://pbs.twimg.com/thumb.jpg:small",
          "videoUrl": "https://video.twimg.com/video.mp4",
          "durationMs": 30000
        }
      ]
    }
    """.data(using: .utf8)!

    let tweet = try JSONDecoder().decode(Tweet.self, from: json)

    #expect(tweet.media?.first?.type == .video)
    #expect(tweet.media?.first?.videoUrl == "https://video.twimg.com/video.mp4")
    #expect(tweet.media?.first?.durationMs == 30000)
}

@Test("Decodes a tweet with no media")
func decodesTweetWithNoMedia() throws {
    let json = """
    {
      "id": "456",
      "text": "Just a text post",
      "createdAt": "Thu Apr 09 06:22:26 +0000 2026",
      "author": { "username": "user", "name": "User" },
      "authorId": "2"
    }
    """.data(using: .utf8)!

    let tweet = try JSONDecoder().decode(Tweet.self, from: json)

    #expect(tweet.id == "456")
    #expect(tweet.media == nil)
}

@Test("Decodes a tweet with quoted tweet")
func decodesTweetWithQuotedTweet() throws {
    let json = """
    {
      "id": "789",
      "text": "This is great",
      "createdAt": "Thu Apr 09 06:22:26 +0000 2026",
      "author": { "username": "quoter", "name": "Quoter" },
      "authorId": "3",
      "quotedTweet": {
        "id": "111",
        "text": "Original thought here",
        "createdAt": "Wed Apr 08 12:00:00 +0000 2026",
        "author": { "username": "original", "name": "Original" },
        "authorId": "4"
      }
    }
    """.data(using: .utf8)!

    let tweet = try JSONDecoder().decode(Tweet.self, from: json)

    #expect(tweet.quotedTweet?.id == "111")
    #expect(tweet.quotedTweet?.author.username == "original")
}

@Test("ScoredPost holds tweet with score, reason, and tags")
func scoredPostStructure() {
    let tweet = Tweet(
        id: "1",
        text: "AI is reshaping linear algebra education",
        createdAt: "Thu Apr 09 06:22:26 +0000 2026",
        author: Author(username: "prof", name: "Professor"),
        authorId: "1"
    )

    let scored = ScoredPost(
        tweet: tweet,
        score: 0.85,
        reason: "Matches interest in AI + math education",
        tags: ["ai", "math", "linear-algebra", "education"]
    )

    #expect(scored.score == 0.85)
    #expect(scored.tags.contains("math"))
    #expect(scored.tags.contains("linear-algebra"))
}

@Test("DigestSection groups scored posts by timestamp")
func digestSectionGrouping() {
    let tweet = Tweet(
        id: "1",
        text: "Test",
        createdAt: "Thu Apr 09 06:22:26 +0000 2026",
        author: Author(username: "t", name: "T"),
        authorId: "1"
    )
    let post = ScoredPost(tweet: tweet, score: 0.9, reason: "good", tags: ["test"])

    let section = DigestSection(timestamp: "14:30", posts: [post])
    let digest = Digest(date: "2026-04-10", sections: [section])

    #expect(digest.sections.count == 1)
    #expect(digest.sections[0].timestamp == "14:30")
    #expect(digest.sections[0].posts.count == 1)
}

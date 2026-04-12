import Foundation
import Testing
@testable import ScorerService
@testable import XdigestCore

// MARK: - Dedup

@Test("filterSeenTweets removes tweets with seen IDs")
func filterSeenRemovesById() {
    let tweets = [
        makeTweet(id: "1"), makeTweet(id: "2"), makeTweet(id: "3"),
    ]
    let seen: Set<String> = ["2"]
    let result = filterSeenTweets(tweets, seen: seen)
    #expect(result.count == 2)
    #expect(result.map(\.id) == ["1", "3"])
}

@Test("filterSeenTweets removes reposts whose originalId is in seen")
func filterSeenRemovesByOriginalId() {
    let repost = makeTweet(id: "100", repost: Repost(
        retweeterHandle: "a", retweeterName: "A",
        originalHandle: "b", originalName: "B",
        originalId: "50"
    ))
    let tweets = [makeTweet(id: "1"), repost]
    let seen: Set<String> = ["50"]
    let result = filterSeenTweets(tweets, seen: seen)
    #expect(result.count == 1)
    #expect(result[0].id == "1")
}

@Test("filterSeenTweets returns all tweets when seen is empty")
func filterSeenEmptySet() {
    let tweets = [makeTweet(id: "1"), makeTweet(id: "2")]
    let result = filterSeenTweets(tweets, seen: [])
    #expect(result.count == 2)
}

// MARK: - Build Prompt

@Test("buildPrompt includes taste profile and candidate texts")
func buildPromptIncludesTexts() {
    let profile = "User loves AI essays and technical content"
    let candidates = [makeTweet(id: "c1", text: "new Claude feature")]
    let prompt = buildPrompt(tasteProfile: profile, candidates: candidates, topN: 5)

    #expect(prompt.contains("AI essays and technical content"))
    #expect(prompt.contains("new Claude feature"))
    #expect(prompt.contains("[0]"))
    #expect(prompt.contains("top 5"))
}

@Test("buildPrompt includes candidate index numbers")
func buildPromptIncludesIndices() {
    let candidates = [
        makeTweet(id: "1", text: "first"),
        makeTweet(id: "2", text: "second"),
    ]
    let prompt = buildPrompt(tasteProfile: "", candidates: candidates, topN: 2)
    #expect(prompt.contains("[0]"))
    #expect(prompt.contains("[1]"))
}

// MARK: - Build Schema

@Test("buildSchema produces valid JSON with picks array")
func buildSchemaIsValidJSON() throws {
    let schema = buildSchema()
    let data = schema.data(using: .utf8)!
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(obj["type"] as? String == "object")
    let props = obj["properties"] as! [String: Any]
    #expect(props["picks"] != nil)
}

// MARK: - Parse Claude Output

@Test("parseClaudeOutput maps picks to correct tweets")
func parseClaudeOutputMapsPicks() throws {
    let candidates = [
        makeTweet(id: "a", text: "first post"),
        makeTweet(id: "b", text: "second post"),
    ]

    let claudeJSON = """
    {
      "result": "",
      "structured_output": {
        "picks": [
          {"index": 1, "score": 0.9, "reason": "great", "tags": ["ai"]},
          {"index": 0, "score": 0.7, "reason": "good", "tags": ["tech"]}
        ]
      },
      "total_cost_usd": 0.5,
      "duration_ms": 30000
    }
    """.data(using: .utf8)!

    let scored = try parseClaudeOutput(claudeJSON, candidates: candidates)
    #expect(scored.count == 2)
    #expect(scored[0].tweet.id == "b")
    #expect(scored[0].score == 0.9)
    #expect(scored[0].tags == ["ai"])
    #expect(scored[1].tweet.id == "a")
    #expect(scored[1].score == 0.7)
}

@Test("parseClaudeOutput skips picks with out-of-bounds indices")
func parseClaudeOutputSkipsInvalidIndices() throws {
    let candidates = [makeTweet(id: "a")]

    let claudeJSON = """
    {
      "result": "",
      "structured_output": {
        "picks": [
          {"index": 0, "score": 0.8, "reason": "ok", "tags": []},
          {"index": 99, "score": 0.9, "reason": "phantom", "tags": []}
        ]
      }
    }
    """.data(using: .utf8)!

    let scored = try parseClaudeOutput(claudeJSON, candidates: candidates)
    #expect(scored.count == 1)
    #expect(scored[0].tweet.id == "a")
}

@Test("parseClaudeOutput throws on invalid JSON")
func parseClaudeOutputThrowsOnBadJSON() {
    let bad = "not json".data(using: .utf8)!
    #expect(throws: XdigestError.self) {
        try parseClaudeOutput(bad, candidates: [])
    }
}

@Test("parseClaudeOutput throws when structured_output is missing")
func parseClaudeOutputThrowsOnMissingOutput() {
    let json = """
    {"result": "something went wrong"}
    """.data(using: .utf8)!
    #expect(throws: XdigestError.self) {
        try parseClaudeOutput(json, candidates: [])
    }
}

// MARK: - Find Claude

@Test("findClaude returns path when claude is installed")
func findClaudeReturnsPath() {
    let path = findClaude()
    if path == nil {
        print("claude not installed, skipping")
        return
    }
    #expect(FileManager.default.isExecutableFile(atPath: path!))
}

// MARK: - Helpers

private func makeTweet(
    id: String,
    text: String = "test",
    handle: String = "user",
    repost: Repost? = nil
) -> Tweet {
    Tweet(
        id: id,
        text: text,
        createdAt: "Thu Apr 09 06:22:26 +0000 2026",
        author: Author(username: handle, name: handle),
        authorId: "1",
        repost: repost
    )
}

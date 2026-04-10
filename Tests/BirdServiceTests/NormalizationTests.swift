import Foundation
import Testing
@testable import BirdService
@testable import XdigestCore

@Test("Normalizes a plain tweet")
func normalizesPlainTweet() throws {
    let tweets = try loadFixture("home-sample.json")
    let normalized = try tweets.map(normalize)

    let plain = normalized.first { !$0.text.starts(with: "RT @") && $0.repost == nil }!
    #expect(!plain.id.isEmpty)
    #expect(!plain.text.isEmpty)
    #expect(!plain.author.username.isEmpty)
    #expect(plain.avatarUrl != nil)
}

@Test("Normalizes a retweet with original author")
func normalizesRetweet() throws {
    let tweets = try loadFixture("home-sample.json")
    let normalized = try tweets.map(normalize)

    let rt = normalized.first { $0.repost != nil }!
    #expect(rt.repost?.retweeterHandle != nil)
    #expect(rt.repost?.originalHandle != nil)
    #expect(rt.repost?.retweeterHandle != rt.repost?.originalHandle)
    #expect(rt.repost?.originalId != nil)
}

@Test("Extracts full text from note tweet")
func extractsNoteTweetFullText() throws {
    let tweets = try loadFixture("home-sample.json")
    let normalized = try tweets.map(normalize)

    // Note tweets have text longer than 280 chars
    let note = normalized.first { $0.text.count > 280 }
    #expect(note != nil, "Should have a note tweet with full text > 280 chars")
}

@Test("Extracts avatar URL from _raw")
func extractsAvatarUrl() throws {
    let tweets = try loadFixture("home-sample.json")
    let normalized = try tweets.map(normalize)

    for tweet in normalized {
        #expect(tweet.avatarUrl != nil, "Tweet by @\(tweet.author.username) should have avatar")
    }
}

@Test("Extracts full text from retweet original")
func extractsRetweetFullText() throws {
    let tweets = try loadFixture("home-sample.json")
    let normalized = try tweets.map(normalize)

    let rt = normalized.first { $0.repost != nil }!
    // Retweet full text should NOT start with "RT @"
    #expect(!rt.text.starts(with: "RT @"), "Normalized retweet should use original full text, not RT prefix")
}

private func loadFixture(_ name: String) throws -> [RawBirdTweet] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/\(name)")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([RawBirdTweet].self, from: data)
}

import Foundation
import Testing
@testable import BirdService
@testable import XdigestCore

@Test("findBird returns path when bird is installed")
func findBirdReturnsPath() throws {
    // This test runs on a machine with bird installed.
    // If bird is not installed, the test is skipped.
    let path = findBird()
    if path == nil {
        print("bird not installed, skipping")
        return
    }
    #expect(FileManager.default.isExecutableFile(atPath: path!))
}

@Test("runBird throws birdNotFound when binary missing")
func runBirdThrowsWhenMissing() async {
    // Use a nonexistent path to simulate bird not found
    await #expect(throws: XdigestError.self) {
        try await runBirdProcess(at: "/nonexistent/bird", arguments: ["home"])
    }
}

@Test("parseBirdOutput decodes valid JSON array")
func parseBirdOutputDecodesJSON() throws {
    let json = """
    [{"id":"1","text":"hello","createdAt":"Thu Apr 09 06:22:26 +0000 2026","author":{"username":"test","name":"Test"},"authorId":"1"}]
    """.data(using: .utf8)!

    let tweets = try parseBirdOutput(json, command: "home")
    #expect(tweets.count == 1)
    #expect(tweets[0].id == "1")
}

@Test("parseBirdOutput throws on invalid JSON")
func parseBirdOutputThrowsOnInvalid() {
    let bad = "not json".data(using: .utf8)!
    #expect(throws: XdigestError.self) {
        try parseBirdOutput(bad, command: "home")
    }
}

@Test("parseBirdOutput unwraps tweets key from dict response")
func parseBirdOutputUnwrapsTweetsKey() throws {
    let json = """
    {"tweets":[{"id":"1","text":"hello","createdAt":"Thu Apr 09 06:22:26 +0000 2026","author":{"username":"test","name":"Test"},"authorId":"1"}],"nextCursor":"abc"}
    """.data(using: .utf8)!

    let tweets = try parseBirdOutput(json, command: "bookmarks")
    #expect(tweets.count == 1)
}

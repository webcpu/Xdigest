import Foundation
import XdigestCore

public struct BirdService: Sendable {
    private let birdPath: String

    public init() throws {
        guard let path = findBird() else {
            throw XdigestError.birdNotFound
        }
        self.birdPath = path
    }

    public func fetchHome(count: Int = 100) async throws -> [Tweet] {
        let data = try await runBirdProcess(
            at: birdPath,
            arguments: ["home", "-n", "\(count)", "--json-full"]
        )
        let raw = try parseBirdOutput(data, command: "home -n \(count)")
        return try raw.map(normalize)
    }

    public func fetchLatestBookmark() async throws -> Bookmark? {
        let data = try await runBirdProcess(at: birdPath, arguments: ["bookmarks", "-n", "1", "--json-full"])
        let raw = try parseBirdOutput(data, command: "bookmarks -n 1")
        return try raw.first.map(normalize)
    }

    public func fetchBookmarks(count: Int? = nil) async throws -> [Bookmark] {
        var args = ["bookmarks", "--json-full"]
        if let count {
            args += ["-n", "\(count)"]
        } else {
            args.append("--all")
        }
        let data = try await runBirdProcess(at: birdPath, arguments: args)
        let raw = try parseBirdOutput(data, command: args.joined(separator: " "))
        return try raw.map(normalize)
    }
}

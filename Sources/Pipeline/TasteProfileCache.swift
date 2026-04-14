import Foundation
import BirdService
import ScorerService
import XdigestCore

private let profileFileName = "taste-profile.json"

private struct CachedProfile: Codable {
    let bookmarkLatestId: String
    let profile: String
}

private func buildExtractionPrompt(bookmarkLines: [String]) -> String {
    """
    Here are \(bookmarkLines.count) tweets a user has bookmarked on X. Analyze \
    ALL of them thoroughly and produce a detailed taste profile.

    \(bookmarkLines.joined(separator: "\n"))

    ---

    Produce a comprehensive taste profile that captures everything about what \
    this user likes. Include:
    1. Topics and themes (be specific and exhaustive)
    2. Content styles they prefer (threads, insights, technical, philosophical, etc.)
    3. Authors they gravitate toward and why
    4. Patterns in what they bookmark vs what they probably skip
    5. Any surprising or non-obvious preferences
    6. Languages and cultural context

    Be thorough. This profile will replace the raw bookmarks in future scoring, \
    so any pattern you miss will be lost. Aim for completeness over brevity.
    """
}

/// Loads the taste profile, extracting a new one if bookmarks have changed.
///
/// Two-layer cache: bookmark cache (raw data) feeds into taste profile cache
/// (compressed representation). The profile regenerates when the bookmark
/// cache's `latestId` changes.
public func loadTasteProfile(
    using bird: BirdService,
    cacheDir: URL = defaultCacheDir()
) async throws -> String {
    let bookmarks = try await loadBookmarks(using: bird, cacheDir: cacheDir)
    guard let latestId = bookmarks.first?.id else { return "" }

    if let cached = readProfileCache(from: cacheDir),
       cached.bookmarkLatestId == latestId {
        return cached.profile
    }

    let profile = try await extractProfile(from: bookmarks)
    try saveProfileCache(bookmarkLatestId: latestId, profile: profile, to: cacheDir)
    return profile
}

private func extractProfile(from bookmarks: [Bookmark]) async throws -> String {
    guard let claudePath = findClaude() else {
        throw XdigestError.claudeNotFound
    }

    let lines = bookmarks.compactMap { bookmark -> String? in
        let text = bookmark.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard text.count > 20 else { return nil }
        let truncated = text.count > 600 ? String(text.prefix(600)) + "..." : text
        return "- @\(bookmark.author.username): \(truncated)"
    }

    let prompt = buildExtractionPrompt(bookmarkLines: lines)

    let data = try await runClaudePlainText(
        at: claudePath,
        prompt: prompt
    )

    guard let profile = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !profile.isEmpty
    else {
        throw XdigestError.claudeScoringFailed(exitCode: -1, stderr: "empty profile output")
    }

    return profile
}

private func readProfileCache(from cacheDir: URL) -> CachedProfile? {
    let file = cacheDir.appendingPathComponent(profileFileName)
    guard let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(CachedProfile.self, from: data)
}

private func saveProfileCache(
    bookmarkLatestId: String,
    profile: String,
    to cacheDir: URL
) throws {
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let file = cacheDir.appendingPathComponent(profileFileName)
    let cached = CachedProfile(bookmarkLatestId: bookmarkLatestId, profile: profile)
    let data = try JSONEncoder().encode(cached)
    try data.write(to: file)
}

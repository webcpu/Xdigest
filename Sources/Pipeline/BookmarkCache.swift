import Foundation
import BirdService
import XdigestCore

private let bookmarkFileName = "bookmarks.json"

private let cacheMaxAge: TimeInterval = 7 * 24 * 60 * 60  // 1 week

private struct CachedBookmarks: Codable {
    let latestId: String
    let savedAt: Date
    let bookmarks: [Bookmark]
}

/// Loads cached bookmarks, checking freshness against the latest bookmark on X.
///
/// Strategy (bookmarks are append-only, newest first):
/// 1. Fetch latest bookmark (1 request, ~1s).
/// 2. If its ID matches the cache → return cache.
/// 3. If not, fetch a small page (20). If the cached latest ID appears → prepend new ones.
/// 4. Fallback: full fetch, rebuild cache.
public func loadBookmarks(
    using bird: BirdService,
    cacheDir: URL = defaultCacheDir()
) async throws -> [Bookmark] {
    let cached = freshCache(from: cacheDir)

    guard let latest = try await bird.fetchLatestBookmark() else {
        return cached?.bookmarks ?? []
    }

    if let cached, cached.latestId == latest.id {
        return cached.bookmarks
    }

    if let cached {
        let recent = try await bird.fetchBookmarks(count: 20)
        if let cutoff = recent.firstIndex(where: { $0.id == cached.latestId }) {
            let newBookmarks = Array(recent[..<cutoff])
            let merged = Array((newBookmarks + cached.bookmarks).prefix(500))
            try saveBookmarkCache(latestId: latest.id, bookmarks: merged, to: cacheDir)
            return merged
        }
    }

    let all = try await bird.fetchBookmarks()
    try saveBookmarkCache(latestId: latest.id, bookmarks: all, to: cacheDir)
    return all
}

/// Returns cached bookmarks only if younger than `cacheMaxAge`.
private func freshCache(from cacheDir: URL) -> CachedBookmarks? {
    let file = cacheDir.appendingPathComponent(bookmarkFileName)
    guard let data = try? Data(contentsOf: file),
          let cached = try? JSONDecoder().decode(CachedBookmarks.self, from: data),
          Date().timeIntervalSince(cached.savedAt) < cacheMaxAge
    else { return nil }
    return cached
}

private func saveBookmarkCache(
    latestId: String,
    bookmarks: [Bookmark],
    to cacheDir: URL
) throws {
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let file = cacheDir.appendingPathComponent(bookmarkFileName)
    let cached = CachedBookmarks(latestId: latestId, savedAt: Date(), bookmarks: bookmarks)
    let data = try JSONEncoder().encode(cached)
    try data.write(to: file)
}

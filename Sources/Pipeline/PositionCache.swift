import Foundation

private let positionFileName = "position.json"

private struct Position: Codable {
    let lastSeenPostId: String
}

/// Loads the persisted reading position.
/// Returns empty string if no position has been saved.
public func loadPosition(from cacheDir: URL = defaultCacheDir()) -> String {
    let file = cacheDir.appendingPathComponent(positionFileName)
    guard let data = try? Data(contentsOf: file),
          let position = try? JSONDecoder().decode(Position.self, from: data)
    else { return "" }
    return position.lastSeenPostId
}

/// Saves the reading position to disk.
public func savePosition(_ postId: String, to cacheDir: URL = defaultCacheDir()) throws {
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let file = cacheDir.appendingPathComponent(positionFileName)
    let data = try JSONEncoder().encode(Position(lastSeenPostId: postId))
    try data.write(to: file)
}

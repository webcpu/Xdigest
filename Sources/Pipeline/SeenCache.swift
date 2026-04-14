import Foundation

private let seenFileName = "seen.json"

/// Loads previously seen tweet IDs from disk.
/// Returns empty set if file doesn't exist.
public func loadSeen(from cacheDir: URL = defaultCacheDir()) -> Set<String> {
    let file = cacheDir.appendingPathComponent(seenFileName)
    guard let data = try? Data(contentsOf: file),
          let ids = try? JSONDecoder().decode(Set<String>.self, from: data)
    else { return [] }
    return ids
}

/// Saves seen tweet IDs to disk.
public func saveSeen(_ ids: Set<String>, to cacheDir: URL = defaultCacheDir()) throws {
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let file = cacheDir.appendingPathComponent(seenFileName)
    let data = try JSONEncoder().encode(ids)
    try data.write(to: file)
}

/// App data directory: ~/Library/Application Support/Xdigest/
public func defaultCacheDir() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Xdigest")
}

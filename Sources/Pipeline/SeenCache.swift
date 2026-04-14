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
    let target = appSupport.appendingPathComponent("Xdigest")
    migrateLegacyCacheIfNeeded(to: target)
    return target
}

/// One-time migration from the legacy ~/.cache/xdigest/ location.
/// Runs only if the target doesn't exist and the legacy location does.
private func migrateLegacyCacheIfNeeded(to target: URL) {
    let fm = FileManager.default
    guard !fm.fileExists(atPath: target.path) else { return }
    let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache/xdigest")
    guard fm.fileExists(atPath: legacy.path) else { return }
    try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fm.copyItem(at: legacy, to: target)
}

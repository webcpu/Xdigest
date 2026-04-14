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

/// Data directory: iCloud container if available, otherwise ~/.cache/xdigest/.
/// Using iCloud as the primary store means all data syncs automatically
/// across Macs signed into the same Apple ID. No explicit sync logic needed.
public func defaultCacheDir() -> URL {
    if let container = FileManager.default.url(
        forUbiquityContainerIdentifier: "iCloud.com.webcpu.xdigest"
    ) {
        let docs = container.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/xdigest")
}

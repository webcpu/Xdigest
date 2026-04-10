import Foundation
import XdigestCore

private let digestsDir = "digests"

/// Returns the file path for a given date's digest.
private func digestFile(for date: String, in cacheDir: URL) -> URL {
    cacheDir.appendingPathComponent(digestsDir).appendingPathComponent("\(date).json")
}

/// Returns today's date string (yyyy-MM-dd).
private func todayString() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

/// Loads today's digest from disk.
/// Returns nil if no digest exists for today.
public func loadDigest(from cacheDir: URL = defaultCacheDir()) -> Digest? {
    loadDigest(for: todayString(), from: cacheDir)
}

/// Loads a specific date's digest from disk.
public func loadDigest(for date: String, from cacheDir: URL = defaultCacheDir()) -> Digest? {
    let file = digestFile(for: date, in: cacheDir)
    guard let data = try? Data(contentsOf: file),
          let digest = try? JSONDecoder().decode(Digest.self, from: data)
    else { return nil }
    return digest
}

/// Saves a digest to disk under its date.
public func saveDigest(_ digest: Digest, to cacheDir: URL = defaultCacheDir()) throws {
    let dir = cacheDir.appendingPathComponent(digestsDir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = digestFile(for: digest.date, in: cacheDir)
    let data = try JSONEncoder().encode(digest)
    try data.write(to: file)
}

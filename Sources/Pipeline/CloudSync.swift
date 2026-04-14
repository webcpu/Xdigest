import Foundation

private let containerID = "iCloud.com.webcpu.xdigest"

/// Returns the iCloud Documents directory for syncing, or nil if iCloud is unavailable.
public func iCloudDocumentsDir() -> URL? {
    guard let container = FileManager.default.url(
        forUbiquityContainerIdentifier: containerID
    ) else { return nil }
    let docs = container.appendingPathComponent("Documents")
    try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    return docs
}

/// Copies a local file to iCloud Documents for sync.
public func syncToCloud(localFile: URL, fileName: String) {
    guard let cloudDir = iCloudDocumentsDir() else { return }
    let cloudFile = cloudDir.appendingPathComponent(fileName)
    try? FileManager.default.removeItem(at: cloudFile)
    try? FileManager.default.copyItem(at: localFile, to: cloudFile)
}

/// Restores a file from iCloud Documents to local cache if the local file
/// doesn't exist. Returns true if a cloud copy was found and restored.
public func restoreFromCloud(fileName: String, to localFile: URL) -> Bool {
    guard let cloudDir = iCloudDocumentsDir() else { return false }
    let cloudFile = cloudDir.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: cloudFile.path) else { return false }
    guard !FileManager.default.fileExists(atPath: localFile.path) else { return false }
    do {
        try FileManager.default.createDirectory(
            at: localFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: cloudFile, to: localFile)
        return true
    } catch {
        return false
    }
}

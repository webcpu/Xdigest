import Foundation
import Testing
@testable import Pipeline

@Test("loadSeen returns empty set when file doesn't exist")
func loadSeenReturnsEmptyWhenMissing() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("xdigest-test-\(UUID().uuidString)")
    let seen = loadSeen(from: dir)
    #expect(seen.isEmpty)
}

@Test("saveSeen then loadSeen roundtrips")
func saveAndLoadRoundtrips() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("xdigest-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let ids: Set<String> = ["abc", "def", "123"]
    try saveSeen(ids, to: dir)
    let loaded = loadSeen(from: dir)
    #expect(loaded == ids)
}

@Test("saveSeen overwrites previous data")
func saveSeenOverwrites() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("xdigest-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    try saveSeen(["old"], to: dir)
    try saveSeen(["new"], to: dir)
    let loaded = loadSeen(from: dir)
    #expect(loaded == ["new"])
}

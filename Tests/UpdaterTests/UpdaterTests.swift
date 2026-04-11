import Testing
@testable import Updater

/// Unit tests for the pure version-comparison logic in Updater.
///
/// `checkForUpdate` itself hits the network and is not tested here --
/// that's covered by manual live verification against GitHub. These
/// tests lock in the behavior of the semver comparator, which has
/// several non-obvious corners (v-prefix, segment-count mismatch,
/// non-numeric fallback, known pre-release limitation).

@Test("isNewer handles leading v prefix")
func leadingV() {
    #expect(isNewer("v0.2.0", than: "0.1.0") == true)
    #expect(isNewer("0.2.0", than: "v0.1.0") == true)
    #expect(isNewer("v0.1.0", than: "v0.1.0") == false)
}

@Test("isNewer is strict (not greater-or-equal)")
func strictComparison() {
    #expect(isNewer("0.1.0", than: "0.1.0") == false)
    #expect(isNewer("1.0.0", than: "1.0.0") == false)
}

@Test("isNewer treats shorter segment count as padded zeros")
func segmentCountMismatch() {
    #expect(isNewer("1.2", than: "1.2.0") == false)
    #expect(isNewer("1.2.0", than: "1.2") == false)
    #expect(isNewer("1.2.1", than: "1.2") == true)
    #expect(isNewer("1.2", than: "1.2.1") == false)
}

@Test("isNewer compares segments numerically, not lexically")
func numericNotLexical() {
    #expect(isNewer("10.0.0", than: "9.9.9") == true)
    #expect(isNewer("0.10.0", than: "0.9.9") == true)
}

@Test("isNewer handles zero versions")
func zeroVersions() {
    #expect(isNewer("0.0.0", than: "0.1.0") == false)
    #expect(isNewer("0.1.0", than: "0.0.0") == true)
}

@Test("isNewer cross-major")
func majorVersionBump() {
    #expect(isNewer("2.0.0", than: "1.99.99") == true)
    #expect(isNewer("1.99.99", than: "2.0.0") == false)
}

@Test("isNewer known limitation: pre-release tags equal their final release")
func preReleaseLimitation() {
    // Documented limitation: "1.2.0-beta" parses the beta segment as 0
    // (Int("0-beta") fails), so it compares equal to "1.2.0".
    #expect(isNewer("1.2.0-beta", than: "1.2.0") == false)
    #expect(isNewer("1.2.0", than: "1.2.0-beta") == false)
}

@Test("GitHubRepo holds owner and name")
func repoStruct() {
    let repo = GitHubRepo(owner: "webcpu", name: "Xdigest")
    #expect(repo.owner == "webcpu")
    #expect(repo.name == "Xdigest")
}

@Test("GitHubRelease public init")
func releaseInit() {
    let release = GitHubRelease(
        tagName: "v0.2.0",
        name: "Xdigest 0.2.0",
        htmlUrl: "https://github.com/webcpu/Xdigest/releases/tag/v0.2.0",
        dmgUrl: "https://github.com/webcpu/Xdigest/releases/download/v0.2.0/Xdigest.dmg"
    )
    #expect(release.tagName == "v0.2.0")
    #expect(release.name == "Xdigest 0.2.0")
    #expect(release.dmgUrl?.hasSuffix(".dmg") == true)
}

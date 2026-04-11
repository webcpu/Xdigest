import Foundation

/// Updater: queries GitHub for the latest release of a given repo and
/// compares it to a caller-supplied version. Pure functions + one
/// network call. No persistent state; throttling is the caller's
/// responsibility.
///
/// The module deliberately does NOT read the host app's Info.plist --
/// version discovery is an app-level concern. Callers pass their
/// current version explicitly so this module can be dropped into any
/// Swift app distributed via GitHub Releases.

public struct GitHubRepo: Sendable {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }
}

public struct GitHubRelease: Sendable {
    public let tagName: String   // e.g. "v0.2.0" or "0.2.0"
    public let name: String      // e.g. "Xdigest 0.2.0" (falls back to tagName)
    public let htmlUrl: String   // release page on github.com
    public let dmgUrl: String?   // direct download for the first .dmg asset (if any)

    public init(tagName: String, name: String, htmlUrl: String, dmgUrl: String?) {
        self.tagName = tagName
        self.name = name
        self.htmlUrl = htmlUrl
        self.dmgUrl = dmgUrl
    }
}

public enum UpdateCheckResult: Sendable {
    case updateAvailable(GitHubRelease)
    case upToDate
    case noReleases
    case networkError(String)
}

/// Queries GitHub's "latest release" endpoint and returns a typed result.
/// Never throws -- all failure modes are enum cases.
///
/// - Parameters:
///   - repo: Owner + repo coordinates on GitHub.
///   - userAgent: Required by GitHub on every API request. Pass the
///     app name.
///   - currentVersion: The caller's own version. The module compares
///     the returned tag against this to decide `updateAvailable` vs
///     `upToDate`. Pass exactly what `CFBundleShortVersionString`
///     contains; the comparator handles a leading "v".
public func checkForUpdate(
    repo: GitHubRepo,
    userAgent: String,
    currentVersion: String
) async -> UpdateCheckResult {
    let url = URL(string: "https://api.github.com/repos/\(repo.owner)/\(repo.name)/releases/latest")!
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        return .networkError(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
        return .networkError("invalid HTTP response")
    }
    if http.statusCode == 404 {
        // GitHub returns 404 from /releases/latest when the repo has
        // never published a release. Not an error -- just nothing to
        // update to.
        return .noReleases
    }
    guard http.statusCode == 200 else {
        return .networkError("HTTP \(http.statusCode)")
    }

    guard let release = parseRelease(data) else {
        return .networkError("couldn't parse GitHub response")
    }

    if isNewer(release.tagName, than: currentVersion) {
        return .updateAvailable(release)
    }
    return .upToDate
}

/// Strict-greater comparison. Handles leading "v", variable segment
/// count (1.2 == 1.2.0), and non-numeric segments (treated as 0).
///
/// Internal so the pre-release limitation below isn't frozen into the
/// public API.
///
/// Limitation: "1.2.0-beta" parses as [1, 2, 0] (the beta suffix fails
/// Int parsing and becomes 0), so pre-release tags compare equal to
/// their final release. Don't ship pre-release tags until this is
/// handled explicitly.
func isNewer(_ lhs: String, than rhs: String) -> Bool {
    let a = normalizeVersion(lhs)
    let b = normalizeVersion(rhs)
    for i in 0..<Swift.max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

private func normalizeVersion(_ version: String) -> [Int] {
    let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
    return trimmed.split(separator: ".").map { Int($0) ?? 0 }
}

private func parseRelease(_ data: Data) -> GitHubRelease? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tagName = json["tag_name"] as? String,
          let htmlUrl = json["html_url"] as? String
    else { return nil }

    let name = (json["name"] as? String) ?? tagName
    let assets = (json["assets"] as? [[String: Any]]) ?? []
    let dmgUrl = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })
        .flatMap { $0["browser_download_url"] as? String }

    return GitHubRelease(tagName: tagName, name: name, htmlUrl: htmlUrl, dmgUrl: dmgUrl)
}

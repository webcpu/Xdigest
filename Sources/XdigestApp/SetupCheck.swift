import Foundation
import BirdService
import ScorerService

/// A requirement that must be met before the app can work.
struct SetupIssue: Sendable {
    let title: String
    let description: String
    let action: String
    let actionUrl: String?

    init(title: String, description: String, action: String, actionUrl: String? = nil) {
        self.title = title
        self.description = description
        self.action = action
        self.actionUrl = actionUrl
    }
}

/// Checks all requirements and returns any issues found.
func checkSetup() -> [SetupIssue] {
    var issues: [SetupIssue] = []

    // 1. Bird CLI
    if findBird() == nil {
        issues.append(SetupIssue(
            title: "bird CLI not installed",
            description: "Xdigest uses bird to fetch your X feed.",
            action: "Run in Terminal: npm install -g @steipete/bird"
        ))
    }

    // 2. Claude Code CLI
    if findClaude() == nil {
        issues.append(SetupIssue(
            title: "Claude Code not installed",
            description: "Xdigest uses Claude to score posts against your taste. Install it, then run `claude` and use /login to sign in with your subscription (not API key).",
            action: "Install Claude Code",
            actionUrl: "https://code.claude.com/docs/en/setup"
        ))
    } else if !isClaudeLoggedIn() {
        issues.append(SetupIssue(
            title: "Claude Code not signed in",
            description: "Claude Code is installed but you haven't signed in yet. In Terminal, run `claude` and use /login to sign in with your subscription (not API key).",
            action: "Open Setup Guide",
            actionUrl: "https://code.claude.com/docs/en/setup"
        ))
    }

    // 3. Full Disk Access (must come before X login -- bird needs it to read cookies)
    if !hasFullDiskAccess() {
        issues.append(SetupIssue(
            title: "Full Disk Access required",
            description: "macOS needs your permission for Xdigest to read Safari's cookies. Click below to open System Settings, enable Xdigest in the list, then switch back to this window.",
            action: "Open Full Disk Access Settings",
            actionUrl: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ))
        return issues
    }

    // 4. X login / Safari cookie access
    if findBird() != nil {
        switch diagnoseBird() {
        case .ok, .needsFullDiskAccess:
            break
        case .notLoggedIn:
            issues.append(SetupIssue(
                title: "Not logged into X",
                description: "bird reads your browser cookies to access X. Log into x.com in Safari, Chrome, or Firefox (not a web app added to the dock -- those have isolated cookies).",
                action: "Open x.com in Safari",
                actionUrl: "https://x.com/login"
            ))
        }
    }

    return issues
}

/// Runs `claude auth status` and returns true iff the JSON output
/// reports `"loggedIn": true`. This is a fast local check (~150ms, no
/// API call) backed by Claude Code's own credential store, so it's
/// strictly better than heuristic signals like keychain presence.
///
/// Blocks the caller for up to `timeout` seconds. `checkSetup()`
/// already runs synchronously on MainActor during launch and spawns
/// `bird home` too, so a brief block is acceptable. If setup check
/// ever grows more processes, move this off the main actor.
///
/// Treats timeout and all error paths (process spawn fails, non-zero
/// exit, broken binary, unparseable output) as "not logged in". This
/// is a slight false-attribution for edge cases (e.g. a corrupt
/// Claude binary surfaces as "not signed in" rather than "broken"),
/// but the user-facing action -- reinstall / reauth via the linked
/// setup guide -- is the same for both.
private func isClaudeLoggedIn(timeout: TimeInterval = 3.0) -> Bool {
    guard let claudePath = findClaude() else { return false }

    let process = Process()
    let outPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: claudePath)
    process.arguments = ["auth", "status"]
    process.standardOutput = outPipe
    process.standardError = FileHandle.nullDevice

    let sem = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in sem.signal() }

    do {
        try process.run()
    } catch {
        return false
    }

    if sem.wait(timeout: .now() + timeout) == .timedOut {
        // SIGTERM first; if it ignores us, SIGKILL after a short grace
        // period so we never leak a hung subprocess.
        process.terminate()
        if sem.wait(timeout: .now() + 0.5) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
        }
        return false
    }

    guard process.terminationStatus == 0 else { return false }

    let output = String(
        data: outPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    return parseLoggedInField(output)
}

/// Extracted so it's unit-testable without spawning a real process.
/// Returns true iff `output` contains a JSON field whose key is
/// `loggedIn` (double-quoted) and whose value is the literal `true`,
/// with any amount of whitespace between the colon and the value.
/// The trailing `\b` word boundary prevents matching extended values
/// like `true_but_expired` if Claude Code ever extends the field.
func parseLoggedInField(_ output: String) -> Bool {
    output.range(of: "\"loggedIn\"\\s*:\\s*true\\b", options: .regularExpression) != nil
}

/// Checks whether macOS has *explicitly* blocked incoming connections for
/// this app. Returns nil in all other cases (allowed, or state unknown).
///
/// We ask macOS directly via `socketfilterfw --listapps`. A network probe
/// is unreliable -- a failed HTTP request could be timing, network flake,
/// or LAN resolution, not the firewall. Only when macOS explicitly reports
/// "Block incoming connections" do we surface the warning.
func checkFirewallAccess(port: Int) -> SetupIssue? {
    guard firewallIsEnabled() else { return nil }
    guard let appPath = Bundle.main.executablePath ?? CommandLine.arguments.first else { return nil }
    guard let state = firewallStateForApp(at: appPath) else { return nil }
    guard state == .blocked else { return nil }

    return SetupIssue(
        title: "Firewall is blocking Xdigest",
        description: "macOS has blocked incoming connections for Xdigest. Your iPhone and iPad can't connect to the reader. Set Xdigest to \"Allow incoming connections\" in Firewall Options.",
        action: "Open Firewall Settings",
        actionUrl: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
    )
}

private enum FirewallAppState { case allowed, blocked }

/// Is the macOS application firewall enabled at all?
private func firewallIsEnabled() -> Bool {
    let output = runSocketFilterFW(["--getglobalstate"]) ?? ""
    // "Firewall is enabled. (State = 1)" or "Firewall is disabled."
    return output.contains("enabled")
}

/// Reads `socketfilterfw --listapps` and returns the firewall state for the
/// given binary path, or nil if the app isn't listed.
private func firewallStateForApp(at path: String) -> FirewallAppState? {
    guard let output = runSocketFilterFW(["--listapps"]) else { return nil }
    let lines = output.components(separatedBy: "\n")
    for (i, line) in lines.enumerated() {
        guard line.contains(path) else { continue }
        // Next line describes the state: "(Allow incoming connections)" or "(Block incoming connections)"
        let next = i + 1 < lines.count ? lines[i + 1] : ""
        if next.contains("Allow") { return .allowed }
        if next.contains("Block") { return .blocked }
        return nil
    }
    return nil
}

/// Runs `socketfilterfw` with the given arguments. Returns stdout or nil on failure.
private func runSocketFilterFW(_ args: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
    process.arguments = args
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

/// Checks if the app has Full Disk Access by probing a TCC-protected path.
/// Safari's containerized cookie database requires Full Disk Access.
private func hasFullDiskAccess() -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let containerCookies = "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
    let legacyCookies = "\(home)/Library/Cookies/Cookies.binarycookies"
    return FileManager.default.isReadableFile(atPath: containerCookies)
        || FileManager.default.isReadableFile(atPath: legacyCookies)
}

/// Quick check: can bird fetch at least one tweet?
private enum BirdDiagnosis {
    case ok
    case needsFullDiskAccess
    case notLoggedIn
}

/// Runs bird and classifies the failure mode, so the setup window can
/// give a targeted fix (Full Disk Access vs log into X).
private func diagnoseBird() -> BirdDiagnosis {
    guard let birdPath = findBird() else { return .notLoggedIn }

    let process = Process()
    let errPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: birdPath)
    process.arguments = ["home", "-n", "1", "--plain"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errPipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return .notLoggedIn
    }

    if process.terminationStatus == 0 { return .ok }

    let stderr = String(
        data: errPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    // TCC-blocked Safari cookie access. This happens when the app is
    // launched from Finder (no Full Disk Access) instead of a terminal
    // whose parent Terminal.app has the permission.
    if stderr.contains("EPERM") || stderr.contains("operation not permitted") {
        return .needsFullDiskAccess
    }
    return .notLoggedIn
}

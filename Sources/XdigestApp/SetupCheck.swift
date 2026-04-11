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
            action: "Run in Terminal: brew install steipete/tap/bird"
        ))
    }

    // 2. Claude Code CLI
    if findClaude() == nil {
        issues.append(SetupIssue(
            title: "Claude Code not installed",
            description: "Xdigest uses Claude to score posts against your taste. You need an active Claude Code subscription (not API).",
            action: "Install Claude Code",
            actionUrl: "https://claude.ai/code"
        ))
    }

    // 3. X login (check if bird can actually fetch from any browser)
    if findBird() != nil {
        if !canBirdAccessX() {
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

/// Quick check: can bird fetch at least one tweet?
private func canBirdAccessX() -> Bool {
    guard let birdPath = findBird() else { return false }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: birdPath)
    process.arguments = ["home", "-n", "1", "--plain"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return false
    }

    return process.terminationStatus == 0
}

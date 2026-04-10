import Foundation
import BirdService
import ScorerService

/// A requirement that must be met before the app can work.
struct SetupIssue: Sendable {
    let title: String
    let description: String
    let action: String
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
            action: "Install from: https://claude.ai/code"
        ))
    }

    // 3. Safari X login (check if bird can actually fetch)
    if findBird() != nil {
        if !canBirdAccessX() {
            issues.append(SetupIssue(
                title: "Not logged into X in Safari",
                description: "bird reads your Safari cookies to access X. You need to be logged into x.com in Safari.",
                action: "Open Safari, go to x.com, and log in."
            ))
        }
    }

    return issues
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

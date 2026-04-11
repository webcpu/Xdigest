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

/// Checks if the firewall allows incoming connections to a given port.
/// Call this after the server starts.
func checkFirewallAccess(port: Int) -> SetupIssue? {
    guard let lanIP = getLanIP() else { return nil }

    let semaphore = DispatchSemaphore(value: 0)
    var reachable = false

    let url = URL(string: "http://\(lanIP):\(port)/api/mtime")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 3

    let task = URLSession.shared.dataTask(with: request) { data, response, _ in
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            reachable = true
        }
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    if !reachable {
        return SetupIssue(
            title: "Firewall is blocking Xdigest",
            description: "Your iPhone and iPad can't connect to the reader. macOS blocked incoming connections for Xdigest. Set Xdigest to \"Allow incoming connections\" in Firewall Options.",
            action: "Open Firewall Settings",
            actionUrl: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
        )
    }
    return nil
}

/// Returns the Mac's LAN IP address.
private func getLanIP() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let addr = ptr.pointee.ifa_addr.pointee
        guard addr.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: ptr.pointee.ifa_name)
        guard name == "en0" || name == "en1" else { continue }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                       &hostname, socklen_t(hostname.count),
                       nil, 0, NI_NUMERICHOST) == 0 {
            return String(cString: hostname)
        }
    }
    return nil
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

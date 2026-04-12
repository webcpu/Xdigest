import AppKit

/// Terminates any other running processes with the given bundle ID so
/// this instance can take over shared resources (menu bar, server port)
/// without contention. Sends SIGTERM first, waits up to 2 seconds,
/// then force-kills any stragglers.
func terminateOtherInstances(bundleIdentifier: String) {
    let myPid = getpid()

    func othersRunning() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != myPid }
    }

    let others = othersRunning()
    guard !others.isEmpty else { return }

    for other in others { other.terminate() }

    for _ in 0..<20 {
        if othersRunning().isEmpty { return }
        Thread.sleep(forTimeInterval: 0.1)
    }

    for straggler in othersRunning() { straggler.forceTerminate() }
}

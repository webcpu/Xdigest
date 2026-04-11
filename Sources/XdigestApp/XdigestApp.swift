import AppKit
import SwiftUI
import Pipeline
import ServerService
import XdigestCore

private let serverPort = 8408

private final class ResultBox: @unchecked Sendable {
    var result = GenerateResult(picks: 0, error: nil)
}

@main
struct XdigestApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings {
            Text("Xdigest Settings")
                .frame(width: 300, height: 200)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var serverHandle: ServerHandle?
    private var setupWindow: NSWindow?
    private var isGenerating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Single-instance policy: the latest launched instance wins. Any
        // older Xdigest processes get terminated before we bind port 8408
        // or register a status item, so two instances never compete.
        terminateOtherInstances()
    }

    /// Terminates any other running Xdigest processes (same bundle ID) so
    /// this instance can take over the menu bar, the server port, and the
    /// Obsidian vault without resource contention.
    private func terminateOtherInstances() {
        let myPid = getpid()
        let bundleId = "com.xdigest.app"

        func othersRunning() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != myPid }
        }

        let others = othersRunning()
        guard !others.isEmpty else { return }

        for other in others { other.terminate() }

        // Wait up to 2 seconds for graceful shutdown (20 × 100ms).
        for _ in 0..<20 {
            if othersRunning().isEmpty { return }
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Force-kill any stragglers that ignored SIGTERM.
        for straggler in othersRunning() { straggler.forceTerminate() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        // Re-run the setup check every time the app regains focus.
        // When the user returns from System Settings after granting Full
        // Disk Access, the setup window closes automatically and the
        // server starts -- no need to click "Check Again".
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        runSetupCheck()
    }

    @objc private func appBecameActive() {
        // Only relevant while the setup window is visible.
        guard setupWindow != nil else { return }
        runSetupCheck()
    }

    private func runSetupCheck() {
        let issues = checkSetup()
        if issues.isEmpty {
            setupWindow?.close()
            setupWindow = nil
            NSApp.setActivationPolicy(.accessory)
            if serverHandle == nil { startServer() }
        } else {
            NSApp.setActivationPolicy(.regular)
            setupWindow = showSetupWindow(issues: issues) { [weak self] in
                self?.runSetupCheck()
            }
        }
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = menuBarIcon()
        rebuildMenu()
    }

    /// "XD" wordmark rendered as a template image so macOS handles dark
    /// mode, light mode, and tinted menu bar automatically.
    private func menuBarIcon() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 14, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            let text = "XD" as NSString
            let textSize = text.size(withAttributes: attrs)
            let origin = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2 - 1
            )
            text.draw(at: origin, withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Xdigest"
        return image
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let generateItem = NSMenuItem(
            title: isGenerating ? "Generating..." : "Generate Digest",
            action: isGenerating ? nil : #selector(generateDigest),
            keyEquivalent: "g"
        )
        menu.addItem(generateItem)

        menu.addItem(NSMenuItem(
            title: "Open Reader",
            action: #selector(openReader),
            keyEquivalent: "o"
        ))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func generateDigest() {
        performGeneration(thenOpen: false)
    }

    /// Runs the pipeline, updates server state, and optionally opens the
    /// reader on success. Shared by the menu action and the auto-open flow.
    private func performGeneration(thenOpen: Bool) {
        guard !isGenerating else { return }
        isGenerating = true
        rebuildMenu()

        Task {
            do {
                let currentDigest = serverHandle.map { ServerService.currentDigest($0) }
                let outcome = try await generate(currentDigest: currentDigest)
                try? saveSeen(outcome.seenIds)
                if let handle = serverHandle {
                    updateDigest(handle, digest: outcome.digest)
                }
                let picks = outcome.digest.sections.first?.posts.count ?? 0
                showNotification(title: "Xdigest", body: "\(picks) new posts")
                if thenOpen { openReader() }
            } catch {
                // On failure, show the error but do NOT open the reader --
                // the user needs to see what went wrong.
                showNotification(title: "Xdigest Error", body: error.localizedDescription)
            }
            isGenerating = false
            rebuildMenu()
        }
    }

    @objc private func openReader() {
        let url = URL(string: "http://localhost:\(serverPort)")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        if let handle = serverHandle {
            stopServer(handle)
        }
        NSApp.terminate(nil)
    }

    // MARK: - Server

    private func startServer() {
        NSApp.setActivationPolicy(.accessory)
        let initialDigest = Pipeline.loadDigest() ?? Digest(date: "", sections: [])
        let initialPosition = Pipeline.loadPosition()
        Task {
            do {
                self.serverHandle = try await ServerService.startServer(
                    port: serverPort,
                    digest: initialDigest,
                    lastSeenPostId: initialPosition,
                    onGenerate: { [weak self] in
                        self?.runPipelineSync() ?? GenerateResult(picks: 0, error: "app not ready")
                    },
                    onPositionChange: { postId in
                        try? Pipeline.savePosition(postId)
                    },
                    onDigestChange: { digest in
                        try? Pipeline.saveDigest(digest)
                    }
                )
                self.log("[App] Server started on port \(serverPort)")
                self.checkFirewall()
                self.runAutoOpenFlow()
            } catch {
                self.log("[App] Server failed: \(error)")
                showNotification(title: "Xdigest Error", body: "Server: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Auto-Open Flow
    //
    // Runs once the server is up (both on first launch and after onboarding
    // completes). If today's digest already has posts, just open the reader.
    // Otherwise generate first, then open. Launching the app == reading
    // today's digest.
    //
    // Why post-count, not file-existence: the spec is literal ("if there
    // are any today's posts"). A digest file with zero picks typically
    // means a transient scorer miss or slow X response -- retrying on the
    // next launch is the behavior the user wants. If your generator
    // consistently produces zero picks, that's a separate bug to chase in
    // the scorer/bird stack, not a reason to cache empty digests.

    private func runAutoOpenFlow() {
        if let digest = Pipeline.loadDigest(),
           digest.sections.contains(where: { !$0.posts.isEmpty }) {
            log("Today's digest has posts -- opening reader")
            openReader()
            return
        }
        log("No today's posts -- generating then opening")
        performGeneration(thenOpen: true)
    }

    // MARK: - Firewall Check

    private func checkFirewall() {
        Task.detached {
            if let issue = checkFirewallAccess(port: serverPort) {
                await MainActor.run {
                    NSApp.setActivationPolicy(.regular)
                    self.setupWindow = showSetupWindow(issues: [issue]) { [weak self] in
                        NSApp.setActivationPolicy(.accessory)
                        self?.setupWindow = nil
                    }
                }
            }
        }
    }

    // MARK: - Pipeline (blocking, for server callback)

    private nonisolated func runPipelineSync() -> GenerateResult {
        self.log("[App] runPipelineSync started")
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()

        Task.detached {
            self.log("[App] Pipeline task started")
            do {
                // Read the current digest from the single writer (DigestState)
                let currentDigest = await MainActor.run { () -> Digest? in
                    guard let handle = self.serverHandle else { return nil }
                    return ServerService.currentDigest(handle)
                }
                let outcome = try await generate(currentDigest: currentDigest)
                let picks = outcome.digest.sections.first?.posts.count ?? 0
                self.log("[App] Pipeline produced \(picks) posts")
                // Persist seen cache (the digest persists via DigestState.onDigestChange)
                try? saveSeen(outcome.seenIds)
                await MainActor.run {
                    if let handle = self.serverHandle {
                        ServerService.updateDigest(handle, digest: outcome.digest)
                    }
                    self.isGenerating = false
                    self.rebuildMenu()
                }
                box.result = GenerateResult(picks: picks)
            } catch {
                self.log("[App] Pipeline error: \(error)")
                box.result = GenerateResult(picks: 0, error: error.localizedDescription)
                await MainActor.run {
                    self.isGenerating = false
                    self.rebuildMenu()
                }
            }
            semaphore.signal()
        }

        semaphore.wait()
        self.log("[App] runPipelineSync returning \(box.result.picks) picks")
        return box.result
    }

    // MARK: - Logging

    private nonisolated func log(_ message: String) {
        let line = "[App] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func showNotification(title: String, body: String) {
        log("\(title): \(body)")
    }
}

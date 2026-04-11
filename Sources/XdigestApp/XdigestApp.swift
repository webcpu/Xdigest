import AppKit
import SwiftUI
import Pipeline
import ServerService
import Updater
import XdigestCore

private let serverPort = 8408

private final class ResultBox: @unchecked Sendable {
    var result = GenerateResult(picks: 0, error: nil)
}

/// Runs one full generation cycle: read currentDigest, generate, write
/// seen cache, update server digest. Extracted as a function so the
/// ordering invariant is enforced by a function boundary rather than
/// inline comments -- future edits can't silently reorder or skip a
/// step without modifying this helper.
///
/// Partial failure: if `generate()` throws, nothing is persisted (the
/// next run re-scores everything, which is the right thing). If
/// `saveSeen` throws, we log and continue -- the generation is still
/// valid, but the next run may re-pick some of these tweets until the
/// disk write succeeds.
private func runGenerationCycle(serverHandle: ServerHandle?) async throws -> GenerateOutcome {
    // 1. Read currentDigest AFTER the predecessor's updateDigest has
    //    committed, so our merge sees the latest state.
    let currentDigest = serverHandle.map { ServerService.currentDigest($0) }

    // 2. Run the expensive pipeline.
    let outcome = try await generate(currentDigest: currentDigest)

    // 3. Write seen cache BEFORE the next submission reads it. If the
    //    disk write fails, log visibly -- silent failure here causes
    //    duplicates in later digests.
    do {
        try saveSeen(outcome.seenIds)
    } catch {
        let line = "[App] [GenerationQueue] WARN saveSeen failed: \(error)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    // 4. Update server digest BEFORE the next submission reads
    //    currentDigest. Without this, the next merge is based on stale
    //    state and our contribution gets overwritten.
    if let handle = serverHandle {
        ServerService.updateDigest(handle, digest: outcome.digest)
    }

    return outcome
}

/// Serializes the full read-modify-write cycle of generation state so
/// two generations never race on the seen cache or the server digest.
/// Each call to `submit` chains behind the previous one (FIFO) and only
/// completes after `runGenerationCycle` has fully committed all state.
///
/// This is "option 3": each submission runs its own generation, but
/// they're strictly serialized. Two rapid calls pay 2x the API cost,
/// and the second run picks up fresh data from X (posts that arrived
/// during the first run).
///
/// Known limitation -- head-of-line blocking: a stuck `generate()`
/// (network hang, slow scorer) silently blocks every later caller,
/// including the HTTP `/api/generate` handler that sits on a semaphore.
/// Add a timeout to `generate()` upstream if this becomes a problem.
///
/// Cancellation is NOT propagated. `Task.detached` intentionally breaks
/// the parent-child link -- if a caller of `submit` is cancelled (e.g.
/// app quit), the in-flight `generate()` keeps running until it returns
/// or the process dies. This avoids half-written seen caches from
/// mid-run cancellation.
///
/// Task.detached also keeps the cycle off the actor, so the actor is
/// only held for the brief bookkeeping around submission.
private actor GenerationQueue {
    private var current: Task<GenerateOutcome, Error>?

    func submit(serverHandle: ServerHandle?) async throws -> GenerateOutcome {
        let previous = current
        let task = Task.detached { () -> GenerateOutcome in
            // Wait for the predecessor regardless of its success or
            // failure. Each submission is independent, so a failed
            // predecessor shouldn't block or poison the next run.
            _ = await previous?.result
            return try await runGenerationCycle(serverHandle: serverHandle)
        }
        current = task
        return try await task.value
    }
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

    /// Counter of in-flight generations across all entry points (menu,
    /// auto-open, HTTP /api/generate). Must be a counter, not a Bool,
    /// because multiple paths can concurrently bump it and a single flag
    /// would clobber: menu's end-of-generation would flip it false while
    /// HTTP's generation is still running.
    private var generatingCount = 0
    private var isGenerating: Bool { generatingCount > 0 }

    // Nonisolated because `runPipelineSync` (called from the HTTP handler
    // thread) needs to reach it without hopping to MainActor. Actors are
    // Sendable, so a `let` reference is safe to share across isolation.
    nonisolated private let generationQueue = GenerationQueue()

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
        menu.addItem(NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        ))
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
        generatingCount += 1
        rebuildMenu()

        Task {
            do {
                // The queue handles read-currentDigest, generate, save-seen,
                // and update-digest atomically. Caller only does UI work.
                let outcome = try await generationQueue.submit(serverHandle: serverHandle)
                let picks = outcome.digest.sections.first?.posts.count ?? 0
                showNotification(title: "Xdigest", body: "\(picks) new posts")
                if thenOpen { openReader() }
            } catch {
                // On failure, show the error but do NOT open the reader --
                // the user needs to see what went wrong.
                showNotification(title: "Xdigest Error", body: error.localizedDescription)
            }
            generatingCount -= 1
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

    // MARK: - Update Check
    //
    // The app checks GitHub for a newer release. Auto-check runs once per
    // 24h on launch and only bothers the user if there's actually an
    // update. The menu item lets the user force a check -- that path
    // always shows feedback (up-to-date, no releases, or error).

    private static let lastCheckDefaultsKey = "com.xdigest.app.lastUpdateCheck"
    private static let autoCheckInterval: TimeInterval = 24 * 3600
    private static let xdigestRepo = GitHubRepo(owner: "webcpu", name: "Xdigest")
    private static let userAgent = "Xdigest"

    /// Guard against stacked alerts when a menu click lands while an
    /// auto-check is still in flight, or two rapid menu clicks.
    private var isCheckingForUpdate = false

    /// The app's current version. Returns nil if there is no bundled
    /// Info.plist -- typically a dev build launched via dev.sh from
    /// .build/debug/Xdigest. Reading Info.plist is an app concern,
    /// not an Updater-module concern.
    private func currentAppVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    @objc private func checkForUpdatesFromMenu() {
        guard !isCheckingForUpdate else { return }
        guard let version = currentAppVersion() else {
            // Dev build -- tell the user rather than silently failing.
            let alert = NSAlert()
            alert.messageText = "Dev build"
            alert.informativeText = "This build has no version info in Info.plist."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        isCheckingForUpdate = true
        Task { @MainActor in
            defer { self.isCheckingForUpdate = false }
            let result = await checkForUpdate(
                repo: Self.xdigestRepo,
                userAgent: Self.userAgent,
                currentVersion: version
            )
            self.presentUpdateResult(result, silent: false, currentVersion: version)
            self.recordCheckTimestamp(for: result)
        }
    }

    /// Silent auto-check: runs at most once per `autoCheckInterval`. Only
    /// surfaces UI when there's actually an update. Skips entirely when
    /// the app has no bundled Info.plist (dev builds launched via
    /// dev.sh run from .build/debug/Xdigest).
    private func autoCheckForUpdates() {
        guard let version = currentAppVersion() else { return }
        guard !isCheckingForUpdate else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckDefaultsKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.autoCheckInterval else { return }

        isCheckingForUpdate = true
        Task { @MainActor in
            defer { self.isCheckingForUpdate = false }
            let result = await checkForUpdate(
                repo: Self.xdigestRepo,
                userAgent: Self.userAgent,
                currentVersion: version
            )
            self.presentUpdateResult(result, silent: true, currentVersion: version)
            self.recordCheckTimestamp(for: result)
        }
    }

    /// Persists the check timestamp, but only for NON-error results.
    /// A transient network failure shouldn't lock the user out of
    /// auto-checks for the next 24 hours.
    private func recordCheckTimestamp(for result: UpdateCheckResult) {
        switch result {
        case .networkError:
            return
        case .updateAvailable, .upToDate, .noReleases:
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckDefaultsKey)
        }
    }

    /// Routes an UpdateCheckResult to the right UI. `silent=true` hides
    /// "up to date", "no releases", and "network error" -- they only
    /// matter when the user explicitly asked.
    private func presentUpdateResult(_ result: UpdateCheckResult, silent: Bool, currentVersion: String) {
        switch result {
        case .updateAvailable(let release):
            showUpdateAlert(release: release, currentVersion: currentVersion)
        case .upToDate:
            guard !silent else { return }
            let alert = NSAlert()
            alert.messageText = "Xdigest is up to date"
            alert.informativeText = "You're on version \(currentVersion)."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .noReleases:
            guard !silent else { return }
            let alert = NSAlert()
            alert.messageText = "No releases published"
            alert.informativeText = "Xdigest hasn't published any releases on GitHub yet."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .networkError(let message):
            guard !silent else { return }
            let alert = NSAlert()
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = message
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func showUpdateAlert(release: GitHubRelease, currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Update available: \(release.name)"
        alert.informativeText = "You have version \(currentVersion). The latest is \(release.tagName)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Prefer direct DMG download; fall back to the release page
            // if no DMG asset is attached.
            let urlString = release.dmgUrl ?? release.htmlUrl
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
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
                self.autoCheckForUpdates()
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
                // Mark a generation as in-flight so the menu reflects
                // HTTP-triggered runs, and grab the server handle to
                // hand to the queue (it's Sendable).
                let handle = await MainActor.run { () -> ServerHandle? in
                    self.generatingCount += 1
                    self.rebuildMenu()
                    return self.serverHandle
                }
                // The queue handles read-currentDigest, generate, save-seen,
                // and update-digest atomically -- all gated on predecessor
                // completion, so concurrent HTTP requests can't race.
                let outcome = try await self.generationQueue.submit(serverHandle: handle)
                let picks = outcome.digest.sections.first?.posts.count ?? 0
                self.log("[App] Pipeline produced \(picks) posts")
                await MainActor.run {
                    self.generatingCount -= 1
                    self.rebuildMenu()
                }
                box.result = GenerateResult(picks: picks)
            } catch {
                self.log("[App] Pipeline error: \(error)")
                box.result = GenerateResult(picks: 0, error: error.localizedDescription)
                await MainActor.run {
                    self.generatingCount -= 1
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

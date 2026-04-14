import AppKit
import SwiftUI
import Pipeline
import ServerService
import Sparkle
import XdigestCore

private let serverPort = 8408

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
    private var qrWindow: NSWindow?
    private var generatingCount = 0
    private var isGenerating: Bool { generatingCount > 0 }
    nonisolated private let generationQueue = GenerationQueue()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        terminateOtherInstances(bundleIdentifier: "com.webcpu.xdigest")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        runSetupCheck()
    }

    private var wizardModel: SetupWizardModel?

    private func runSetupCheck() {
        NSApp.setActivationPolicy(.regular)
        let (window, model) = showSetupWizard { [weak self] in
            // Setup steps passed — start server (which triggers first generation)
            if self?.serverHandle == nil { self?.startServer() }
        }
        setupWindow = window
        wizardModel = model
    }

    private func dismissWizard() {
        wizardModel?.finishGenerating()
        setupWindow?.close()
        setupWindow = nil
        wizardModel = nil
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Menu Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = makeMenuBarIcon()
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusItem?.menu = buildStatusMenu(
            isGenerating: isGenerating,
            generateAction: #selector(generateDigest),
            openReaderAction: #selector(openReader),
            qrCodeAction: #selector(showQRCode),
            quitAction: #selector(quit),
            updaterController: updaterController
        )
    }

    // MARK: - Actions

    @objc private func generateDigest() { performGeneration(thenOpen: false) }

    @objc private func openReader() {
        NSWorkspace.shared.open(URL(string: "http://localhost:\(serverPort)")!)
    }

    @objc private func showQRCode() {
        if let existing = qrWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        qrWindow = showQRCodeWindow()
    }

    @objc private func quit() {
        if let handle = serverHandle { stopServer(handle) }
        NSApp.terminate(nil)
    }

    private func performGeneration(thenOpen: Bool) {
        log("performGeneration called: isGenerating=\(isGenerating) serverHandle=\(serverHandle != nil)")
        guard !isGenerating else { log("performGeneration: skipped (already generating)"); return }
        generatingCount += 1
        rebuildMenu()
        Task {
            do {
                let outcome = try await generationQueue.submit(
                    serverHandle: serverHandle,
                    onProgress: { [weak self] status in
                        Task { @MainActor in
                            self?.wizardModel?.generatingStatus = status
                        }
                    }
                )
                let picks = outcome.digest.sections.first?.posts.count ?? 0
                showNotification(title: "Xdigest", body: "\(picks) new posts")
                if wizardModel != nil { dismissWizard() }
                if thenOpen { openReader() }
            } catch {
                showNotification(title: "Xdigest Error", body: error.localizedDescription)
            }
            generatingCount -= 1
            rebuildMenu()
        }
    }

    // MARK: - Server

    private func startServer() {
        let initialDigest = Pipeline.loadDigest() ?? Digest(date: "", sections: [])
        let initialPosition = Pipeline.loadPosition()
        Task {
            do {
                self.serverHandle = try await ServerService.startServer(
                    port: serverPort, digest: initialDigest, lastSeenPostId: initialPosition,
                    onGenerate: { [weak self] in
                        self?.runPipelineSync() ?? GenerateResult(picks: 0, error: "app not ready")
                    },
                    onPositionChange: { postId in try? Pipeline.savePosition(postId) },
                    onDigestChange: { digest in try? Pipeline.saveDigest(digest) }
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

    // MARK: - Auto-Open

    private func runAutoOpenFlow() {
        let hasWizard = wizardModel != nil
        let digest = Pipeline.loadDigest()
        let hasPosts = digest?.sections.contains(where: { !$0.posts.isEmpty }) ?? false
        log("autoOpen: wizard=\(hasWizard) hasPosts=\(hasPosts) sections=\(digest?.sections.count ?? 0)")
        if hasWizard || !hasPosts {
            log("Generating first digest")
            performGeneration(thenOpen: true)
            return
        }
        log("Today's digest has posts -- opening reader")
        openReader()
    }

    // MARK: - Firewall

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

    // MARK: - Pipeline Sync Bridge

    private nonisolated func runPipelineSync() -> GenerateResult {
        generationQueue.submitSync(
            prepare: { await MainActor.run {
                self.generatingCount += 1
                self.rebuildMenu()
                return self.serverHandle
            }},
            cleanup: { await MainActor.run {
                self.generatingCount -= 1
                self.rebuildMenu()
            }},
            log: { self.log($0) }
        )
    }

    // MARK: - Logging

    private nonisolated func log(_ message: String) {
        FileHandle.standardError.write(Data("[App] \(message)\n".utf8))
    }

    private func showNotification(title: String, body: String) {
        log("\(title): \(body)")
    }
}

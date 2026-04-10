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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        runSetupCheck()
    }

    private func runSetupCheck() {
        let issues = checkSetup()
        if issues.isEmpty {
            setupWindow?.close()
            setupWindow = nil
            startServer()
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
        button.image = NSImage(
            systemSymbolName: "doc.text.magnifyingglass",
            accessibilityDescription: "Xdigest"
        )
        rebuildMenu()
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
        guard !isGenerating else { return }
        isGenerating = true
        rebuildMenu()

        Task {
            do {
                let digest = try await generate()
                if let handle = serverHandle {
                    updateDigest(handle, digest: digest)
                }
                showNotification(
                    title: "Xdigest",
                    body: "\(digest.sections.first?.posts.count ?? 0) new posts"
                )
            } catch {
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
        Task {
            do {
                serverHandle = try await ServerService.startServer(
                    port: serverPort,
                    digest: initialDigest,
                    onGenerate: { [weak self] in
                        self?.runPipelineSync() ?? GenerateResult(picks: 0, error: "app not ready")
                    }
                )
                self.log("[App] Server started on port \(serverPort)")
            } catch {
                self.log("[App] Server failed: \(error)")
                showNotification(title: "Xdigest Error", body: "Server: \(error.localizedDescription)")
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
                let digest = try await generate()
                let picks = digest.sections.first?.posts.count ?? 0
                self.log("[App] Pipeline produced \(picks) posts")
                await MainActor.run {
                    if let handle = self.serverHandle {
                        ServerService.updateDigest(handle, digest: digest)
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

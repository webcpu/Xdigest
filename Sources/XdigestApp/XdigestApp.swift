import AppKit
import SwiftUI

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "Xdigest")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Generate Digest", action: #selector(generateDigest), keyEquivalent: "g"))
        menu.addItem(NSMenuItem(title: "Open Reader", action: #selector(openReader), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func generateDigest() {
    }

    @objc private func openReader() {
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

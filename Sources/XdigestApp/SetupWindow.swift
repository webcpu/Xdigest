import AppKit
import SwiftUI

struct SetupView: View {
    let issues: [SetupIssue]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Xdigest Setup")
                .font(.system(size: 20, weight: .semibold))

            Text("A few things need to be set up before Xdigest can work:")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.orange))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(issue.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(issue.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let urlString = issue.actionUrl, let url = URL(string: urlString) {
                                Button(action: { openInSafari(url) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.forward.square")
                                        Text(issue.action)
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                }
                                .buttonStyle(.link)
                                .padding(.top, 2)
                            } else {
                                Text(issue.action)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.blue)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Check Again") {
                    onDismiss()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// Opens a web URL specifically in Safari, not a web app or other default handler.
/// For non-web URLs (like x-apple.systempreferences:), falls back to the default handler.
private func openInSafari(_ url: URL) {
    let scheme = url.scheme?.lowercased() ?? ""
    guard scheme == "http" || scheme == "https" else {
        NSWorkspace.shared.open(url)
        return
    }

    let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: config)
}

@MainActor
func showSetupWindow(issues: [SetupIssue], onDismiss: @escaping () -> Void) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Xdigest Setup"
    window.contentView = NSHostingView(rootView: SetupView(issues: issues, onDismiss: {
        window.close()
        onDismiss()
    }))
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return window
}

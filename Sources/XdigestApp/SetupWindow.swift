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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(issue.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(issue.action)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.blue)
                                .textSelection(.enabled)
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

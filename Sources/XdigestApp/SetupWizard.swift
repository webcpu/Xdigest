import AppKit
import SwiftUI
import BirdService
import ScorerService
import XdigestCore

// MARK: - Setup Step Model

struct SetupStep: Identifiable {
    let id: String
    let title: String
    let description: String
    let command: String?
    let actionLabel: String?
    let actionUrl: String?
    let autoOpen: Bool
    let check: @Sendable () -> Bool

    init(
        id: String, title: String, description: String,
        command: String? = nil, actionLabel: String? = nil,
        actionUrl: String? = nil, autoOpen: Bool = false,
        check: @escaping @Sendable () -> Bool
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.command = command
        self.actionLabel = actionLabel
        self.actionUrl = actionUrl
        self.autoOpen = autoOpen
        self.check = check
    }
}

func buildSetupSteps() -> [SetupStep] {
    var steps: [SetupStep] = []

    steps.append(SetupStep(
        id: "node",
        title: "Install Node.js",
        description: "Xdigest needs Node.js to install a dependency. Download and install it first.",
        actionLabel: "Download Node.js",
        actionUrl: "https://nodejs.org",
        check: { findExecutable(named: "npm") != nil || findExecutable(named: "node") != nil }
    ))

    steps.append(SetupStep(
        id: "bird",
        title: "Install bird CLI",
        description: "Xdigest uses bird to fetch your X feed. Run this command in Terminal:",
        command: "npm install -g @steipete/bird",
        check: { findBird() != nil }
    ))

    steps.append(SetupStep(
        id: "claude",
        title: "Install Claude Code",
        description: "Xdigest uses Claude to score posts against your taste.",
        actionLabel: "Install Claude Code",
        actionUrl: "https://code.claude.com/docs/en/setup",
        check: { findClaude() != nil }
    ))

    steps.append(SetupStep(
        id: "claude-login",
        title: "Sign in to Claude Code",
        description: "Open Terminal and sign in with your subscription (not API key):",
        command: "claude /login",
        check: {
            guard let path = findClaude() else { return false }
            return checkClaudeLoggedIn(at: path)
        }
    ))

    steps.append(SetupStep(
        id: "fda",
        title: "Grant Full Disk Access",
        description: "macOS needs permission for Xdigest to read Safari's cookies. Toggle Xdigest on in the list, then come back here.",
        actionLabel: "Open Full Disk Access Settings",
        actionUrl: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        autoOpen: true,
        check: {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let container = "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
            let legacy = "\(home)/Library/Cookies/Cookies.binarycookies"
            return FileManager.default.isReadableFile(atPath: container)
                || FileManager.default.isReadableFile(atPath: legacy)
        }
    ))

    steps.append(SetupStep(
        id: "x-login",
        title: "Log in to X",
        description: "Log into x.com in Safari, Chrome, or Firefox. Don't use a web app added to the dock — those have isolated cookies.",
        actionLabel: "Open x.com",
        actionUrl: "https://x.com/login",
        autoOpen: true,
        check: {
            guard let birdPath = findBird() else { return false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: birdPath)
            process.arguments = ["home", "-n", "1", "--plain"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch { return false }
            return process.terminationStatus == 0
        }
    ))

    return steps
}

/// Synchronous Claude login check (for background thread).
private func checkClaudeLoggedIn(at path: String, timeout: TimeInterval = 3.0) -> Bool {
    let process = Process()
    let outPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["auth", "status"]
    process.standardOutput = outPipe
    process.standardError = FileHandle.nullDevice

    let sem = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in sem.signal() }

    do { try process.run() } catch { return false }

    if sem.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        if sem.wait(timeout: .now() + 0.5) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
        }
        return false
    }

    guard process.terminationStatus == 0 else { return false }
    let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.range(of: "\"loggedIn\"\\s*:\\s*true\\b", options: .regularExpression) != nil
}

// MARK: - Wizard ViewModel

@MainActor
final class SetupWizardModel: ObservableObject {
    let steps: [SetupStep]
    @Published var currentIndex: Int = 0
    @Published var stepPassed: Bool = false
    @Published var checking: Bool = true
    @Published var generating: Bool = false
    @Published var generatingStatus: String = ""
    var onComplete: (() -> Void)?

    private var pollTimer: Timer?
    private var didAutoOpen: Set<String> = []

    init(steps: [SetupStep]) {
        self.steps = steps
    }

    var currentStep: SetupStep? {
        guard currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    var isLastStep: Bool { currentIndex >= steps.count - 1 }

    func start() {
        advanceToFirstFailingStep()
    }

    func next() {
        guard stepPassed else { return }
        stopPolling()
        currentIndex += 1
        if currentIndex >= steps.count {
            startGenerating()
            return
        }
        advanceToFirstFailingStep()
    }

    private func startGenerating() {
        generating = true
        generatingStatus = "Analyzing your taste from bookmarks..."
        onComplete?()
    }

    func finishGenerating() {
        generating = false
    }

    private func advanceToFirstFailingStep() {
        checking = true
        stepPassed = false
        Task.detached { [weak self] in
            guard let self else { return }
            let steps = self.steps
            var idx = await self.currentIndex
            while idx < steps.count {
                if steps[idx].check() {
                    idx += 1
                } else {
                    break
                }
            }
            await MainActor.run {
                if idx >= steps.count {
                    self.startGenerating()
                } else {
                    self.currentIndex = idx
                    self.checking = false
                    self.autoOpenIfNeeded()
                    self.startPolling()
                }
            }
        }
    }

    private func autoOpenIfNeeded() {
        guard let step = currentStep, step.autoOpen,
              let urlStr = step.actionUrl, let url = URL(string: urlStr),
              !didAutoOpen.contains(step.id)
        else { return }
        didAutoOpen.insert(step.id)
        openUrl(url)
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runCheck()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func runCheck() {
        guard let step = currentStep, !stepPassed else { return }
        Task.detached { [weak self] in
            let passed = step.check()
            await MainActor.run {
                if passed { self?.stepPassed = true }
            }
        }
    }

    func cleanup() {
        stopPolling()
    }
}

// MARK: - Wizard View

struct SetupWizardView: View {
    @ObservedObject var model: SetupWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Xdigest Setup")
                .font(.system(size: 20, weight: .semibold))

            if model.generating {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Generating your first digest...")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(model.generatingStatus)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("This only happens the first time. It usually takes 2-4 minutes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            } else if model.checking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking...")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
            } else if let step = model.currentStep {
                stepProgress

                Text(step.title)
                    .font(.system(size: 16, weight: .semibold))

                Text(step.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let command = step.command {
                    commandBlock(command)
                }

                if let label = step.actionLabel,
                   let urlStr = step.actionUrl, let url = URL(string: urlStr) {
                    Button(action: { openUrl(url) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.square")
                            Text(label)
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.link)
                }

                if model.stepPassed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Done!")
                            .foregroundStyle(.green)
                            .font(.system(size: 13, weight: .medium))
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button(model.isLastStep ? "Finish" : "Next") {
                        model.next()
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.stepPassed)
                }
            }
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: model.currentIndex)
        .animation(.easeInOut(duration: 0.2), value: model.stepPassed)
    }

    private var stepProgress: some View {
        let total = model.steps.count
        let current = model.currentIndex + 1
        return Text("Step \(current) of \(total)")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func commandBlock(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(.controlBackgroundColor)))
    }
}

// MARK: - Window

private func openUrl(_ url: URL) {
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
func showSetupWizard(onComplete: @escaping () -> Void) -> (NSWindow, SetupWizardModel) {
    let steps = buildSetupSteps()
    let model = SetupWizardModel(steps: steps)
    model.onComplete = onComplete

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Xdigest Setup"
    window.contentView = NSHostingView(rootView: SetupWizardView(model: model))
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    model.start()

    return (window, model)
}

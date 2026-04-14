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
            // Actually read a few bytes to force a real TCC check.
            // isReadableFile() returns cached state and may lag after
            // the user toggles the permission in System Settings.
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let paths = [
                "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
                "\(home)/Library/Cookies/Cookies.binarycookies",
            ]
            for path in paths {
                if let handle = FileHandle(forReadingAtPath: path) {
                    _ = try? handle.read(upToCount: 1)
                    try? handle.close()
                    return true
                }
            }
            return false
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
        VStack(spacing: 0) {
            if model.generating {
                generatingView
            } else if model.checking {
                checkingView
            } else if let step = model.currentStep {
                stepView(step)
            }
        }
        .frame(width: 480, height: 400)
        .animation(.easeInOut(duration: 0.3), value: model.currentIndex)
        .animation(.easeInOut(duration: 0.3), value: model.stepPassed)
        .animation(.easeInOut(duration: 0.3), value: model.generating)
    }

    // MARK: - Generating Screen

    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

            Text("Almost ready")
                .font(.system(size: 24, weight: .semibold))

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 240)

                Text(model.generatingStatus)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Text("This only happens the first time.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Checking Screen

    private var checkingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Checking requirements...")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(40)
    }

    // MARK: - Step Screen

    private func stepView(_ step: SetupStep) -> some View {
        VStack(spacing: 24) {
            Spacer()

            stepIcon(step)

            Text(step.title)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(step.description)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            if let command = step.command {
                commandBlock(command)
            }

            if let label = step.actionLabel,
               let urlStr = step.actionUrl, let url = URL(string: urlStr) {
                Button(action: { openUrl(url) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                        Text(label)
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.link)
            }

            if model.stepPassed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 18))
                    Text("Done!")
                        .foregroundStyle(.green)
                        .font(.system(size: 15, weight: .medium))
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            VStack(spacing: 16) {
                stepDots

                Button(action: { model.next() }) {
                    Text(model.isLastStep ? "Finish" : "Next")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 200)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.stepPassed)
            }
        }
        .padding(40)
    }

    private func stepIcon(_ step: SetupStep) -> some View {
        let name: String = switch step.id {
        case "node": "shippingbox"
        case "bird": "bird"
        case "claude": "brain.head.profile"
        case "claude-login": "person.badge.key"
        case "fda": "lock.shield"
        case "x-login": "globe"
        default: "gear"
        }
        return Image(systemName: name)
            .font(.system(size: 40))
            .foregroundStyle(.blue)
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<model.steps.count, id: \.self) { i in
                Circle()
                    .fill(i == model.currentIndex ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func commandBlock(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 16)
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
        .frame(maxWidth: 360)
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
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.contentView = NSHostingView(rootView: SetupWizardView(model: model))
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    model.start()

    return (window, model)
}

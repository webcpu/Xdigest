import AppKit

/// Intervals for automatic background generation.
enum GenerateInterval: Int, CaseIterable {
    case every1h = 3600
    case every2h = 7200
    case every4h = 14400
    case every8h = 28800
    case manual = 0

    var title: String {
        switch self {
        case .every1h: "Every Hour"
        case .every2h: "Every 2 Hours"
        case .every4h: "Every 4 Hours"
        case .every8h: "Every 8 Hours"
        case .manual: "Manual Only"
        }
    }

    static let defaultInterval: GenerateInterval = .every4h
    private static let userDefaultsKey = "autoGenerateInterval"

    static func load() -> GenerateInterval {
        guard UserDefaults.standard.object(forKey: userDefaultsKey) != nil else {
            return defaultInterval
        }
        let raw = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return GenerateInterval(rawValue: raw) ?? defaultInterval
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: GenerateInterval.userDefaultsKey)
    }
}

/// Manages periodic background generation with wake coalescing.
///
/// - Fires a repeating timer at the configured interval.
/// - On wake from sleep, generates once if the interval has elapsed.
/// - Skips if a generation is already in progress.
/// - Manual generation is handled separately by the caller.
@MainActor
final class AutoGenerateScheduler {
    private var timer: Timer?
    private var wakeObserver: Any?
    private var interval: GenerateInterval
    private var lastGenerationTime: Date?
    private let generate: () -> Void

    init(generate: @escaping () -> Void) {
        self.interval = GenerateInterval.load()
        self.generate = generate
    }

    func start() {
        scheduleTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
    }

    func updateInterval(_ newInterval: GenerateInterval) {
        interval = newInterval
        newInterval.save()
        timer?.invalidate()
        timer = nil
        if newInterval != .manual {
            generate()
            scheduleTimer()
        }
    }

    var currentInterval: GenerateInterval { interval }

    func recordGeneration() {
        lastGenerationTime = Date()
    }

    // MARK: - Private

    private func scheduleTimer() {
        guard interval != .manual else { return }
        let seconds = TimeInterval(interval.rawValue)
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generate()
            }
        }
        timer?.tolerance = 600  // 10 minutes -- fine for 2-8 hour intervals
    }

    private func handleWake() {
        guard interval != .manual else { return }
        let seconds = TimeInterval(interval.rawValue)
        if let last = lastGenerationTime, Date().timeIntervalSince(last) < seconds {
            return
        }
        generate()
    }
}

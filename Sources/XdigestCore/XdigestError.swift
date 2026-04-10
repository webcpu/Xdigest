import Foundation

public enum XdigestError: Error, CustomStringConvertible, Sendable {
    // BirdService
    case birdNotFound
    case birdFetchFailed(command: String, stderr: String)
    case birdOutputInvalid(command: String, detail: String)

    // ScorerService
    case claudeNotFound
    case claudeScoringFailed(exitCode: Int, stderr: String)
    case claudeOutputInvalid(detail: String)

    // DigestService
    case digestAssemblyFailed(reason: String)

    // ServerService
    case serverPortInUse(port: Int)
    case serverStartFailed(port: Int, reason: String)

    public var isRecoverable: Bool {
        switch self {
        case .birdFetchFailed, .claudeScoringFailed, .serverStartFailed: true
        case .birdNotFound, .claudeNotFound, .serverPortInUse: false
        case .birdOutputInvalid, .claudeOutputInvalid, .digestAssemblyFailed: false
        }
    }

    public var description: String {
        switch self {
        case .birdNotFound:
            "bird CLI not found. Install via: brew install steipete/tap/bird"
        case .birdFetchFailed(let command, let stderr):
            "[Bird] \(command) failed: \(stderr)"
        case .birdOutputInvalid(let command, let detail):
            "[Bird] \(command) returned invalid output: \(detail)"
        case .claudeNotFound:
            "Claude Code not found. Install from: https://claude.ai/code"
        case .claudeScoringFailed(let exitCode, let stderr):
            "[Scorer] claude exited \(exitCode): \(stderr)"
        case .claudeOutputInvalid(let detail):
            "[Scorer] claude returned invalid output: \(detail)"
        case .digestAssemblyFailed(let reason):
            "[Digest] assembly failed: \(reason)"
        case .serverPortInUse(let port):
            "[Server] port \(port) already in use"
        case .serverStartFailed(let port, let reason):
            "[Server] failed to start on port \(port): \(reason)"
        }
    }
}

import Foundation
import Synchronization

/// Thread-safe one-shot flag for guarding continuation resume.
public final class OnceFlag: Sendable {
    private let state = Mutex(false)

    public init() {}

    /// Returns true only the first time it's called.
    public func tryFire() -> Bool {
        state.withLock { fired in
            if fired { return false }
            fired = true
            return true
        }
    }
}

/// Runs an external process asynchronously, returning stdout as Data.
/// - Stdout and stderr both go to temp files (avoids pipe buffer deadlocks).
/// - Uses NSLock to guard against double continuation resume.
/// - Cleans up temp files on completion.
public func runProcess(
    at path: String,
    arguments: [String],
    stdinFile: URL? = nil,
    label: String,
    makeError: @escaping @Sendable (String) -> any Error
) async throws -> Data {
    let stdoutFile = makeTempURL(label: label, suffix: "stdout")
    let stderrFile = makeTempURL(label: label, suffix: "stderr")

    guard FileManager.default.createFile(atPath: stdoutFile.path, contents: nil),
          FileManager.default.createFile(atPath: stderrFile.path, contents: nil)
    else {
        throw makeError("failed to create temp files")
    }

    let stdoutHandle = try FileHandle(forWritingTo: stdoutFile)
    let stderrHandle = try FileHandle(forWritingTo: stderrFile)

    return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        if let stdinFile {
            process.standardInput = try? FileHandle(forReadingFrom: stdinFile)
        }

        let once = OnceFlag()

        process.terminationHandler = { process in
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
                try? FileManager.default.removeItem(at: stdoutFile)
                try? FileManager.default.removeItem(at: stderrFile)
            }

            guard once.tryFire() else { return }

            let stderr = readStderr(from: stderrFile)

            guard process.terminationStatus == 0 else {
                let msg = stderr.isEmpty
                    ? "exit code \(process.terminationStatus)"
                    : stderr
                continuation.resume(throwing: makeError(msg))
                return
            }

            do {
                let data = try Data(contentsOf: stdoutFile)
                guard !data.isEmpty else {
                    continuation.resume(throwing: makeError("empty output"))
                    return
                }
                continuation.resume(returning: data)
            } catch {
                continuation.resume(throwing: makeError("failed to read output: \(error)"))
            }
        }

        do {
            try process.run()
        } catch {
            guard once.tryFire() else { return }
            continuation.resume(throwing: makeError("failed to launch: \(error)"))
        }
    }
}

// MARK: - Helpers

private func makeTempURL(label: String, suffix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("xdigest-\(label)-\(UUID().uuidString).\(suffix)")
}

private func readStderr(from file: URL) -> String {
    (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

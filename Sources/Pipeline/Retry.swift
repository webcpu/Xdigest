import Foundation
import XdigestCore

/// Retries an operation when it fails with a recoverable error.
/// Non-recoverable errors propagate immediately.
/// Backs off exponentially: delay * attempt.
public func withRetry<T>(
    maxAttempts: Int = 3,
    delay: Duration = .seconds(2),
    operation: () async throws -> T
) async throws -> T {
    precondition(maxAttempts >= 1, "maxAttempts must be at least 1")
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch let error as XdigestError where error.isRecoverable && attempt < maxAttempts {
            try await Task.sleep(for: delay * attempt)
        }
        // Non-recoverable errors or last attempt: catch doesn't match, error propagates
    }
    // Unreachable: loop always returns or throws
    fatalError("withRetry: unreachable")
}

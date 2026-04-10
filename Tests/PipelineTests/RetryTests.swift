import Foundation
import Testing
@testable import Pipeline
@testable import XdigestCore

@Test("withRetry succeeds on first attempt")
func retrySucceedsFirstAttempt() async throws {
    var attempts = 0
    let result = try await withRetry(maxAttempts: 3) {
        attempts += 1
        return "ok"
    }
    #expect(result == "ok")
    #expect(attempts == 1)
}

@Test("withRetry retries recoverable errors")
func retryRetriesRecoverable() async throws {
    var attempts = 0
    let result: String = try await withRetry(maxAttempts: 3, delay: .milliseconds(10)) {
        attempts += 1
        if attempts < 3 {
            throw XdigestError.birdFetchFailed(command: "home", stderr: "timeout")
        }
        return "recovered"
    }
    #expect(result == "recovered")
    #expect(attempts == 3)
}

@Test("withRetry does not retry non-recoverable errors")
func retryDoesNotRetryFatal() async {
    var attempts = 0
    await #expect(throws: XdigestError.self) {
        let _: String = try await withRetry(maxAttempts: 3) {
            attempts += 1
            throw XdigestError.birdNotFound
        }
    }
    #expect(attempts == 1)
}

@Test("withRetry with maxAttempts 1 does not retry")
func retryMaxAttemptsOneDoesNotRetry() async {
    var attempts = 0
    await #expect(throws: XdigestError.self) {
        let _: String = try await withRetry(maxAttempts: 1) {
            attempts += 1
            throw XdigestError.birdFetchFailed(command: "home", stderr: "timeout")
        }
    }
    #expect(attempts == 1)
}

@Test("withRetry propagates non-XdigestError immediately")
func retryPropagatesNonXdigestError() async {
    var attempts = 0
    await #expect(throws: CancellationError.self) {
        let _: String = try await withRetry(maxAttempts: 3) {
            attempts += 1
            throw CancellationError()
        }
    }
    #expect(attempts == 1)
}

@Test("withRetry throws after max attempts exhausted")
func retryThrowsAfterMaxAttempts() async {
    var attempts = 0
    await #expect(throws: XdigestError.self) {
        let _: String = try await withRetry(maxAttempts: 2, delay: .milliseconds(10)) {
            attempts += 1
            throw XdigestError.birdFetchFailed(command: "home", stderr: "flaky")
        }
    }
    #expect(attempts == 2)
}

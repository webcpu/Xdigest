import Foundation
import Pipeline
import ServerService
import XdigestCore

/// Thread-safe container for passing a result out of a Task.detached
/// block that signals a DispatchSemaphore. The @unchecked Sendable
/// conformance is safe because the writer (inside the task) finishes
/// and signals BEFORE the reader (after semaphore.wait) touches it.
private final class ResultBox: @unchecked Sendable {
    var result = GenerateResult(picks: 0, error: nil)
}

/// Runs one full generation cycle: read currentDigest, generate, write
/// seen cache, update server digest. Extracted as a function so the
/// ordering invariant is enforced by a function boundary rather than
/// inline comments -- future edits can't silently reorder or skip a
/// step without modifying this helper.
///
/// Partial failure: if `generate()` throws, nothing is persisted (the
/// next run re-scores everything, which is the right thing). If
/// `saveSeen` throws, we log and continue -- the generation is still
/// valid, but the next run may re-pick some of these tweets until the
/// disk write succeeds.
private func runGenerationCycle(serverHandle: ServerHandle?) async throws -> GenerateOutcome {
    // 1. Read currentDigest AFTER the predecessor's updateDigest has
    //    committed, so our merge sees the latest state.
    let currentDigest = serverHandle.map { ServerService.currentDigest($0) }

    // 2. Run the expensive pipeline.
    let outcome = try await generate(currentDigest: currentDigest)

    // 3. Write seen cache BEFORE the next submission reads it. If the
    //    disk write fails, log visibly -- silent failure here causes
    //    duplicates in later digests.
    do {
        try saveSeen(outcome.seenIds)
    } catch {
        let line = "[App] [GenerationQueue] WARN saveSeen failed: \(error)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    // 4. Update server digest BEFORE the next submission reads
    //    currentDigest. Without this, the next merge is based on stale
    //    state and our contribution gets overwritten.
    if let handle = serverHandle {
        ServerService.updateDigest(handle, digest: outcome.digest)
    }

    return outcome
}

/// Serializes the full read-modify-write cycle of generation state so
/// two generations never race on the seen cache or the server digest.
/// Each call to `submit` chains behind the previous one (FIFO) and only
/// completes after `runGenerationCycle` has fully committed all state.
///
/// This is "option 3": each submission runs its own generation, but
/// they're strictly serialized. Two rapid calls pay 2x the API cost,
/// and the second run picks up fresh data from X (posts that arrived
/// during the first run).
///
/// Known limitation -- head-of-line blocking: a stuck `generate()`
/// (network hang, slow scorer) silently blocks every later caller,
/// including the HTTP `/api/generate` handler that sits on a semaphore.
/// Add a timeout to `generate()` upstream if this becomes a problem.
///
/// Cancellation is NOT propagated. `Task.detached` intentionally breaks
/// the parent-child link -- if a caller of `submit` is cancelled (e.g.
/// app quit), the in-flight `generate()` keeps running until it returns
/// or the process dies. This avoids half-written seen caches from
/// mid-run cancellation.
///
/// Task.detached also keeps the cycle off the actor, so the actor is
/// only held for the brief bookkeeping around submission.
actor GenerationQueue {
    private var current: Task<GenerateOutcome, Error>?

    func submit(serverHandle: ServerHandle?) async throws -> GenerateOutcome {
        let previous = current
        let task = Task.detached { () -> GenerateOutcome in
            _ = await previous?.result
            return try await runGenerationCycle(serverHandle: serverHandle)
        }
        current = task
        return try await task.value
    }

    /// Blocking bridge for HTTP handler threads that can't use
    /// async/await. Wraps `submit()` in a semaphore wait.
    ///
    /// `prepare` runs first -- return the server handle and do any
    /// pre-flight work (e.g. bump a UI counter). `cleanup` runs after
    /// the cycle completes (success or failure).
    nonisolated func submitSync(
        prepare: @Sendable @escaping () async -> ServerHandle?,
        cleanup: @Sendable @escaping () async -> Void,
        log: @Sendable @escaping (String) -> Void
    ) -> GenerateResult {
        log("runPipelineSync started")
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()

        Task.detached {
            log("Pipeline task started")
            do {
                let handle = await prepare()
                let outcome = try await self.submit(serverHandle: handle)
                let picks = outcome.digest.sections.first?.posts.count ?? 0
                log("Pipeline produced \(picks) posts")
                await cleanup()
                box.result = GenerateResult(picks: picks)
            } catch {
                log("Pipeline error: \(error)")
                box.result = GenerateResult(picks: 0, error: error.localizedDescription)
                await cleanup()
            }
            semaphore.signal()
        }

        semaphore.wait()
        log("runPipelineSync returning \(box.result.picks) picks")
        return box.result
    }
}

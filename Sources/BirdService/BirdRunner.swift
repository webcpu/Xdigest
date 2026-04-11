import Foundation
import XdigestCore

// MARK: - Find Bird

/// Locates the bird binary. Checks common user and system install paths.
/// This is more reliable than `which` because bundled apps have a minimal
/// PATH that excludes ~/.local/bin and similar user-specific directories.
public func findBird() -> String? {
    findExecutable(named: "bird")
}

// MARK: - Run Bird

/// Runs bird CLI at the given path, returns raw stdout data.
public func runBirdProcess(at path: String, arguments: [String]) async throws -> Data {
    guard FileManager.default.isExecutableFile(atPath: path) else {
        throw XdigestError.birdNotFound
    }

    let command = arguments.joined(separator: " ")
    return try await runProcess(
        at: path,
        arguments: arguments,
        label: "bird",
        makeError: { detail in XdigestError.birdFetchFailed(command: command, stderr: detail) }
    )
}

// MARK: - Parse Output

/// Decodes bird JSON stdout into RawBirdTweets.
/// Handles flat arrays and {"tweets": [...]} dict responses.
public func parseBirdOutput(_ data: Data, command: String) throws -> [RawBirdTweet] {
    let decoder = JSONDecoder()

    if let tweets = try? decoder.decode([RawBirdTweet].self, from: data) {
        return tweets
    }

    return try parseWrappedResponse(data, command: command, decoder: decoder)
}

/// Decodes a {"tweets": [...]} or {"users": [...]} wrapped response.
private func parseWrappedResponse(
    _ data: Data,
    command: String,
    decoder: JSONDecoder
) throws -> [RawBirdTweet] {
    struct WrappedResponse: Decodable {
        let tweets: [RawBirdTweet]?
        let users: [RawBirdTweet]?
    }

    do {
        let wrapped = try decoder.decode(WrappedResponse.self, from: data)
        let result = wrapped.tweets ?? wrapped.users ?? []
        guard !result.isEmpty else {
            throw XdigestError.birdOutputInvalid(
                command: command,
                detail: "response contained neither 'tweets' nor 'users'"
            )
        }
        return result
    } catch let error as XdigestError {
        throw error
    } catch {
        throw XdigestError.birdOutputInvalid(
            command: command,
            detail: "decode failed: \(error)"
        )
    }
}

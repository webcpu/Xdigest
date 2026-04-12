import Foundation
import XdigestCore

/// Locates the claude binary via `which` in a login shell.
public func findClaude() -> String? {
    findExecutable(named: "claude")
}

/// Writes the prompt to a temp file and runs claude with structured output.
public func runClaude(
    at path: String,
    prompt: String,
    schema: String,
    systemPrompt: String
) async throws -> Data {
    guard FileManager.default.isExecutableFile(atPath: path) else {
        throw XdigestError.claudeNotFound
    }

    let promptFile = try writePromptToTemp(prompt)
    defer { try? FileManager.default.removeItem(at: promptFile) }

    return try await runProcess(
        at: path,
        arguments: [
            "-p",
            "--model", "opus",
            "--output-format", "json",
            "--json-schema", schema,
            "--append-system-prompt", systemPrompt,
            "--no-session-persistence",
        ],
        stdinFile: promptFile,
        label: "claude",
        makeError: { detail in XdigestError.claudeScoringFailed(exitCode: -1, stderr: detail) }
    )
}

/// Runs claude in plain text mode (no structured output).
public func runClaudePlainText(
    at path: String,
    prompt: String
) async throws -> Data {
    guard FileManager.default.isExecutableFile(atPath: path) else {
        throw XdigestError.claudeNotFound
    }

    let promptFile = try writePromptToTemp(prompt)
    defer { try? FileManager.default.removeItem(at: promptFile) }

    return try await runProcess(
        at: path,
        arguments: [
            "-p",
            "--model", "opus",
            "--output-format", "text",
            "--no-session-persistence",
        ],
        stdinFile: promptFile,
        label: "claude",
        makeError: { detail in XdigestError.claudeScoringFailed(exitCode: -1, stderr: detail) }
    )
}

/// Writes prompt text to a temp file for piping to claude's stdin.
private func writePromptToTemp(_ prompt: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("xdigest-prompt-\(UUID().uuidString).txt")
    try prompt.write(to: url, atomically: true, encoding: .utf8)
    return url
}

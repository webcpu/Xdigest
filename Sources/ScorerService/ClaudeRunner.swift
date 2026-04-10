import Foundation
import XdigestCore

/// Locates the claude binary on the system.
public func findClaude() -> String? {
    findClaudeInKnownPaths() ?? findClaudeInPATH()
}

private func findClaudeInKnownPaths() -> String? {
    let candidates = [
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func findClaudeInPATH() -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["claude"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let path, !path.isEmpty,
          FileManager.default.isExecutableFile(atPath: path)
    else { return nil }

    return path
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

/// Writes prompt text to a temp file for piping to claude's stdin.
private func writePromptToTemp(_ prompt: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("xdigest-prompt-\(UUID().uuidString).txt")
    try prompt.write(to: url, atomically: true, encoding: .utf8)
    return url
}

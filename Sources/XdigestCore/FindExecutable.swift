import Foundation

/// Locates an executable by checking common install directories first,
/// then falling back to the user's login shell for pathological setups.
///
/// Why the fast path: when the app bundle is launched from LaunchServices
/// (e.g. Finder, `open /Applications/Xdigest.app`), it inherits a minimal
/// PATH that excludes user-specific directories like `~/.local/bin`. The
/// previous implementation ran `$SHELL -l -c "which X"`, but a non-
/// interactive login shell sources `.zprofile` and `.zshenv`, NOT `.zshrc`.
/// Many users (including Claude Code's official installer) add their PATH
/// in `.zshrc` (interactive) or via sourced env files that `.zshrc` loads.
/// The net result: `which` returned nothing, and setup check falsely
/// reported the binary as missing.
///
/// The direct filesystem check covers the common install locations for
/// Homebrew, pipx, npm global, bun, and Claude Code's installer -- no
/// subprocess, no shell config dependence, ~microseconds per check.
///
/// The shell fallback uses `-i -l -c` (interactive + login + command) so
/// it sources `.zshrc` too, catching tools installed in non-standard
/// locations that only `.zshrc` knows about.
public func findExecutable(named name: String) -> String? {
    // Fast path: check common install directories directly.
    let home = NSHomeDirectory()
    let commonDirs = [
        "\(home)/.local/bin",        // Claude Code's installer, pipx
        "/opt/homebrew/bin",          // Homebrew on Apple Silicon
        "/usr/local/bin",             // Homebrew on Intel, common installers
        "\(home)/.npm-global/bin",    // npm global when configured to user dir
        "\(home)/.bun/bin",           // bun-installed CLIs
        "/usr/bin",                   // system-installed
    ]
    for dir in commonDirs {
        let candidate = "\(dir)/\(name)"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }

    // Fallback: spawn an interactive login shell and run `which`. `-i -l`
    // sources `.zprofile` AND `.zshrc`, so PATH additions in either file
    // are picked up. Stderr is discarded so noise from `.zshrc` (e.g.
    // "atuin not found" warnings) doesn't leak into the parsed output.
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-i", "-l", "-c", "which \(name)"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let path, !path.isEmpty,
          FileManager.default.isExecutableFile(atPath: path)
    else { return nil }

    return path
}

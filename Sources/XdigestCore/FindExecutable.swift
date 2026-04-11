import Foundation

/// Locates an executable on the user's PATH by running `which` through a
/// login shell.
///
/// Why a login shell? When an app bundle is launched from Finder, it
/// inherits a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) that excludes
/// user-specific directories like `~/.local/bin`. Running `which` in that
/// context finds nothing. A login shell (`$SHELL -l -c ...`) sources the
/// user's profile (`~/.zshrc`, `~/.bash_profile`, etc.) so it has the same
/// PATH the user sees in their terminal.
public func findExecutable(named name: String) -> String? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-l", "-c", "which \(name)"]
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

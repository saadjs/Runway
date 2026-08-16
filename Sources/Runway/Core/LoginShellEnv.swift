import Foundation

/// Environment variables as the user's *shell* sees them.
///
/// Runway ships as a menu-bar/login-item app launched by launchd or Finder, which
/// does not source `.zshrc`/`.zprofile` — so a variable the CLIs rely on (an XDG
/// override, an API key) is simply absent from `ProcessInfo`. Falling back to a
/// login shell recovers it. Results are cached: at most one subprocess per
/// variable per launch, and only when the process environment came up empty.
enum LoginShellEnv {
    private static let lock = NSLock()
    private static var cache: [String: String?] = [:]

    /// The process environment first, then the login shell. Nil if unset or blank.
    static func value(_ name: String) -> String? {
        if let direct = ProcessInfo.processInfo.environment[name]?.nonBlank { return direct }

        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        let resolved = readFromLoginShell(name)
        cache[name] = resolved
        return resolved
    }

    static func resetCacheForTesting() {
        lock.lock()
        cache = [:]
        lock.unlock()
    }

    private static func readFromLoginShell(_ name: String, timeout: TimeInterval = 2.0) -> String? {
        // Interpolated into a shell command, so accept only variable-name characters.
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShellPath())
        process.arguments = ["-lc", "printf %s \"${\(name)-}\""]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        // Read concurrently: a profile that prints a lot could fill the pipe buffer
        // and deadlock a shell we're waiting on.
        let box = OutputBox()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = stdout.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        guard exited.wait(timeout: .now() + timeout) != .timedOut else {
            process.terminate()
            return nil
        }
        _ = drained.wait(timeout: .now() + 1.0)
        guard process.terminationStatus == 0 else { return nil }
        return String(data: box.data, encoding: .utf8)?.nonBlank
    }

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    /// `SHELL` is unset under launchd, so fall back to the account's shell.
    private static func loginShellPath() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"]?.nonBlank,
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }
}

extension String {
    /// The string trimmed, or nil if it holds nothing but whitespace.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

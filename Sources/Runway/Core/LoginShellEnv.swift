import Foundation

/// Env vars as the login shell sees them; apps launched by launchd don't source the user's profile.
enum LoginShellEnv {
    private static let lock = NSLock()
    private static var cache: [String: String?] = [:]

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
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

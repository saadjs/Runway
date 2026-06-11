import Foundation
import Security

/// Read-only access to a macOS generic-password keychain item.
enum Keychain {
    /// Reads the secret by shelling out to `/usr/bin/security`.
    ///
    /// The `claude` CLI stores its credentials *through* the `security` tool, which
    /// puts `/usr/bin/security` on the item's ACL — so reads via this path never
    /// trigger a keychain prompt, and keep working after the CLI rotates the token
    /// and rewrites the item (which resets the ACL and would otherwise invalidate
    /// any "Always Allow" grant given to Runway's own code signature).
    static func readGenericPasswordViaSecurityCLI(
        service: String, timeout: TimeInterval = 2.0
    ) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        guard exited.wait(timeout: .now() + timeout) != .timedOut else {
            // Still running means the ACL unexpectedly required a prompt. SIGTERM
            // is enough to dismiss it; the caller falls back to the direct
            // Security.framework read.
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        var data = stdout.fileHandleForReading.readDataToEndOfFile()
        while let last = data.last, last == 0x0A || last == 0x0D {
            data.removeLast()
        }
        return data.isEmpty ? nil : data
    }

    /// Direct Security.framework read. Reading another app's item this way triggers
    /// an access prompt; "Always Allow" binds the grant to Runway's code signature
    /// but is lost whenever the owning app rewrites the item. Kept as a fallback
    /// for items the `security` CLI cannot read without UI.
    static func readGenericPassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}

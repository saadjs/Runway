import Foundation
import Security

enum Keychain {
    /// Never prompts for the `claude` CLI's item: the CLI writes it via `/usr/bin/security`, putting that binary on its ACL.
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

    /// Attributes aren't ACL-protected, so this never prompts.
    static func modificationDate(service: String) -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return (item as? [String: Any])?[kSecAttrModificationDate as String] as? Date
    }

    /// Prompts when Runway isn't on the item's ACL; a fallback only.
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

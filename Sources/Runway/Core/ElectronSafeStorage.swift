import CommonCrypto
import Foundation

/// Decrypts values written by Electron's `safeStorage` API on macOS — the format
/// the Claude desktop app uses for its `oauth:tokenCache` in `config.json`.
///
/// Electron/Chromium's macOS scheme: a `v10` magic prefix, then AES-128-CBC over
/// the ciphertext with a key derived from a keychain password ("<App> Safe
/// Storage") via PBKDF2-HMAC-SHA1 (salt `saltysalt`, 1003 iterations, 16-byte
/// key) and a fixed IV of sixteen space bytes. PKCS#7 padding.
enum ElectronSafeStorage {
    private static let magic = Data("v10".utf8)
    private static let salt = Data("saltysalt".utf8)
    private static let iterations: UInt32 = 1003
    private static let keyLength = 16
    private static let iv = Data(repeating: 0x20, count: 16) // sixteen spaces

    /// Decrypt a base64-encoded `v10…` blob using the app's Safe Storage password.
    /// Returns nil if the input isn't the expected format or decryption fails.
    static func decrypt(base64 blob: String, password: String) -> Data? {
        guard let raw = Data(base64Encoded: blob), raw.count > magic.count,
              raw.prefix(magic.count) == magic
        else { return nil }
        let ciphertext = raw.dropFirst(magic.count)
        guard let key = deriveKey(password: password) else { return nil }
        return aes128CBCDecrypt(ciphertext: ciphertext, key: key)
    }

    private static func deriveKey(password: String) -> Data? {
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBytes { saltPtr -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, password.utf8.count,
                saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                iterations,
                &derived, keyLength)
        }
        return status == kCCSuccess ? Data(derived) : nil
    }

    private static func aes128CBCDecrypt(ciphertext: Data, key: Data) -> Data? {
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var moved = 0
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                ciphertext.withUnsafeBytes { dataPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, key.count,
                        ivPtr.baseAddress,
                        dataPtr.baseAddress, ciphertext.count,
                        &output, output.count,
                        &moved)
                }
            }
        }
        return status == kCCSuccess ? Data(output.prefix(moved)) : nil
    }
}

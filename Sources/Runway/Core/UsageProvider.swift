import Foundation

protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var shortCode: String { get }
    var logoResource: String { get }

    func fetchUsage() async throws -> ProviderUsage
}

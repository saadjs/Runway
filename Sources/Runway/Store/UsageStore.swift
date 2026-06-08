import Foundation
import SwiftUI

/// Owns provider state and drives refreshes (on launch, on a timer, and manually).
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var states: [String: ProviderState] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    let providers = ProviderRegistry.all

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 5 * 60
    /// Skip refreshes (other than the manual button) within this window.
    private let minimumRefreshInterval: TimeInterval = 30

    init() {
        for provider in providers { states[provider.id] = .loading }
    }

    func start() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Refreshes all providers. Throttled to avoid rate-limiting the upstream
    /// usage endpoints when the popover is opened repeatedly; pass `force: true`
    /// (the manual Refresh button) to bypass the throttle.
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < minimumRefreshInterval {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: (String, ProviderState).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let usage = try await provider.fetchUsage()
                        return (provider.id, .loaded(usage))
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        return (provider.id, .failed(message))
                    }
                }
            }
            for await (id, state) in group {
                states[id] = state
            }
        }
        lastUpdated = Date()
    }

    func state(for provider: any UsageProvider) -> ProviderState {
        states[provider.id] ?? .loading
    }
}

import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var states: [String: ProviderState] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    let providers = ProviderRegistry.all

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let minimumRefreshInterval: TimeInterval = 30

    init() {
        for provider in providers { states[provider.id] = .loading }
    }

    func start() {
        Task { await refresh() }
        scheduleTimer(minutes: AppSettings.shared.refreshIntervalMinutes)
        // `@Published` emits in `willSet`, so use the delivered value, not the stale property.
        AppSettings.shared.$refreshIntervalMinutes
            .dropFirst()
            .sink { [weak self] minutes in self?.scheduleTimer(minutes: minutes) }
            .store(in: &cancellables)
    }

    private func scheduleTimer(minutes: Int) {
        timer?.invalidate()
        let interval = TimeInterval(minutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        timer?.tolerance = interval * 0.1
    }

    /// Non-forced refreshes are throttled to stay under Anthropic's rate limit.
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
                if states[id] != state { states[id] = state }
            }
        }
        lastUpdated = Date()
    }

    func state(for provider: any UsageProvider) -> ProviderState {
        states[provider.id] ?? .loading
    }
}

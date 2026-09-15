// RootTabRouter.swift — the ONLY cross-tab action: pure routing (D4 red line).
// No data flows between tabs; the router just says which one you're looking at.
// Persistence via UserDefaults (lastTab memory, U1 首启入口终案).

import SwiftUI
import Combine

@MainActor
final class RootTabRouter: ObservableObject {
    static let shared = RootTabRouter()

    static let storageKey = "app.rootSourceMode"

    @Published var mode: AppSourceMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            // First visit marks the remote tab as "seen" so the shell can keep
            // it alive afterwards (lazy-create once, then both tabs persist).
            if mode == .remote { seenRemote = true }
        }
    }

    /// Whether the remote tab has ever been opened — drives lazy instantiation.
    @Published private(set) var seenRemote: Bool = false

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        mode = AppSourceMode(rawValue: stored ?? "") ?? .local
        seenRemote = (mode == .remote)
    }

    /// Deep-link entry (push / approval tap): switch tab, nothing else.
    func route(to target: AppSourceMode) {
        mode = target
    }
}

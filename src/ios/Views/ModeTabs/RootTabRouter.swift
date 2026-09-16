// RootTabRouter.swift — the ONLY cross-tab action: pure routing (D4 red line).
// No data flows between tabs; the router just says which one you're looking at.
// Persistence via UserDefaults (lastTab memory, U1 首启入口终案).

import SwiftUI
import Combine

// NOTE B8-FIX: intentionally NOT @MainActor — ContentView (nonisolated struct)
// initializes it as a stored property; all mutations originate from UI (main).
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
        // U1 §6 (pp 2026-09-15 拍板, 覆盖三页引导案): 首启入口 = AA 官方登录页。
        // No stored value (fresh install) therefore lands on .remote, where
        // RootModeTabsView's needsLoginGate raises the full-screen ServiceEntryView;
        // its JO-6 grey button routes to .local. Once the user has chosen, lastTab
        // memory wins — the local tab itself is upstream ContentView, untouched.
        mode = AppSourceMode(rawValue: stored ?? "") ?? .remote
        seenRemote = (mode == .remote)
    }

    /// Deep-link entry (push / approval tap): switch tab, nothing else.
    func route(to target: AppSourceMode) {
        mode = target
    }

    /// B16: the Settings sheet is presented by RootModeTabsView, not by ContentView.
    /// On the Remote tab ContentView is alive but `opacity 0`, and "can an invisible
    /// host present a sheet" is exactly the kind of thing that should not be load-bearing.
    /// One flag, one visible presenter, both tabs use it.
    @Published var showSettings: Bool = false

    /// B16 mirrors, one-way, presentation-only, written by ContentView from its own
    /// existing sources of truth (never the reverse):
    /// `localAtRoot` — the fixed gear must step aside when the local line pushes a chat
    /// (that chat owns its own navigation bar). Same root test as `goHome()`.
    @Published var localAtRoot: Bool = true
    /// `localSelecting` — while rows are checked the page's own toolbar shows Cancel at
    /// this edge, so the fixed gear stands down instead of doubling it.
    @Published var localSelecting: Bool = false

    /// True while a horizontal page swipe is ARMED (the shell has committed to switching
    /// tabs for this gesture). The session lists read this and freeze their scroll, so a
    /// horizontal swipe can no longer also scroll the list vertically
    /// (pp 2026-09-16「左右滑动页面的时候容易滑到上下」). Reset when the finger lifts or
    /// the mode settles.
    @Published var pageSwipeArmed: Bool = false
}

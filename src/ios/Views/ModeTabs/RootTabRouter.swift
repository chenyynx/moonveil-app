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

    /// B14e seam. The whole resting-state top bar (capsule + gear + alarm + terminal
    /// menu) is drawn by RootModeTabsView so it stays FIXED while both pages slide —
    /// a control that lived in one page's toolbar can no longer write that page's
    /// @State directly, so every tap comes back here as a one-shot request, consumed
    /// and cleared by ContentView. Actions only: no data, no session state.
    @Published var requestedBarAction: LocalBarAction?

    /// B14d/e flags, all presentation-only and written one-way BY ContentView from its
    /// own existing sources of truth (see the mirrors in bodyPresentationStage).
    /// `localAtRoot`: the fixed bar must step aside when the local line pushes a chat
    /// (the in-toolbar version used to disappear with the push for free).
    @Published var localAtRoot: Bool = true
    /// `localSelecting`: while rows are checked the local page's own toolbar draws
    /// Cancel / Select All, so the fixed bar's copies stand down and nothing doubles.
    @Published var localSelecting: Bool = false
    /// Whether an alarm exists → whether the fixed bar draws the alarm button.
    @Published var barHasAlarms: Bool = false
    /// The sync pill next to the capsule (upstream's title indicator, same states).
    @Published var barSyncSubtitle: ContentView.SyncSubtitleState?
    /// DEBUG-only menu checkmark, mirrored from ContentView's idle-timer flag.
    @Published var barKeepScreenAwake: Bool = false
}

/// One control on the fixed top bar, as requested by the shell. `.toolSheet` reuses
/// the upstream enum so no second source of truth for sheets is born.
enum LocalBarAction {
    case toolSheet(ToolSheet)
    case terminal
    case alarmList
    #if DEBUG
    /// Drives ContentView's `keepScreenAwake`, which is itself declared inside
    /// `#if DEBUG` — so the case has to be DEBUG-only too, otherwise Release builds
    /// reference a symbol that does not exist (CI 426e2a2).
    case toggleKeepAwake
    #endif
}

// SettingsKit.swift — 8b (B8-VISUAL): local settings surface adopts the AA
// settings visual language. The chrome pieces below are line-for-line ports of
// upstream AA `Views/Settings/SettingsComponents.swift` (v2.0.0) kit parts
// (closeSettings env key / SettingsRow / page chrome), with the private
// modifier exposed through the same `.settingsPage(_:)` entry point so pages
// read identical to upstream AA call sites. Zero behaviour change: list style,
// title and close-button styling only — no state, no navigation, no data flow.
//
// Depends on: AppTheme + SheetCloseToolbar (AuthAA ports), AppSymbol (this dir).
import SwiftUI

// MARK: - closeSettings environment (AA SettingsComponents.swift:3-10, verbatim shape)

private struct SettingsCloseKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var closeSettings: () -> Void {
        get { self[SettingsCloseKey.self] }
        set { self[SettingsCloseKey.self] = newValue }
    }
}

/// Inject a dismiss action for pages presented as sheets (AA pattern).
extension View {
    func providingCloseSettings(_ action: @escaping () -> Void) -> some View {
        environment(\.closeSettings, action)
    }
}

// MARK: - SettingsRow (AA SettingsComponents.swift:13-28, verbatim body)

struct SettingsRow: View {
    let title: String
    let symbol: String
    var value: String?
    var body: some View {
        if let value, !value.isEmpty {
            LabeledContent {
                Text(value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } label: {
                Label(title, appSymbol: symbol)
            }
        } else {
            Label(title, appSymbol: symbol)
        }
    }
}

// MARK: - page chrome (AA SettingsComponents.swift:30-42; private -> internal)

struct SettingsPageChrome: ViewModifier {
    let title: String
    @Environment(\.closeSettings) private var close
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar(action: close) }
    }
}

extension View {
    func settingsPage(_ title: String) -> some View { modifier(SettingsPageChrome(title: title)) }
}

// Pushed-child variant (our glue, B8-VISUAL): same chrome minus the sheet
// close button — Moonveil settings sub-pages live inside one NavigationStack
// (upstream structure), back-swipe/nav-back stays the exit.
struct SettingsChildChrome: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func settingsChildPage(_ title: String) -> some View { modifier(SettingsChildChrome(title: title)) }
}


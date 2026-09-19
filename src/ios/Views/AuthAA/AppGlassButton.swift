import SwiftUI

struct AppGlassButton: View {
    enum Style {
        case regular
        case prominent
    }

    let title: String?
    let systemImage: String?
    let role: ButtonRole?
    let style: Style
    let isLoading: Bool
    let disabled: Bool
    let maxWidth: CGFloat?
    /// [NEWCHAT-INK] Prominent-style tint override; nil = AppTheme default
    /// (additive parameter — existing call sites unchanged).
    let tintOverride: Color?
    /// [NEWCHAT-WIDTH] Optional minimum width for the label (nil = no constraint).
    let labelMinWidth: CGFloat?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        style: Style = .regular,
        isLoading: Bool = false,
        disabled: Bool = false,
        maxWidth: CGFloat? = .infinity,
        tintOverride: Color? = nil,
        labelMinWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.style = style
        self.isLoading = isLoading
        self.disabled = disabled
        self.maxWidth = maxWidth
        self.tintOverride = tintOverride
        self.labelMinWidth = labelMinWidth
        self.action = action
    }

    init(
        systemImage: String,
        role: ButtonRole? = nil,
        style: Style = .regular,
        isLoading: Bool = false,
        disabled: Bool = false,
        maxWidth: CGFloat? = nil,
        tintOverride: Color? = nil,
        labelMinWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.systemImage = systemImage
        self.role = role
        self.style = style
        self.isLoading = isLoading
        self.disabled = disabled
        self.maxWidth = maxWidth
        self.tintOverride = tintOverride
        self.labelMinWidth = labelMinWidth
        self.action = action
    }

    var body: some View {
        if style == .prominent {
            button
                .modifier(PrimaryButtonStyleIfAvailable())
                .tint(tintOverride ?? AppTheme.primaryControlBackground(colorScheme))
                .foregroundStyle(AppTheme.primaryControlForeground(colorScheme))
        } else {
            button
                .modifier(SecondaryButtonStyleIfAvailable())
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            label
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(progressTint)
                    }
                }
                .frame(maxWidth: maxWidth)
        }
        .buttonBorderShape(title == nil ? .circle : .capsule)
        .controlSize(.large)
        .disabled(disabled || isLoading)
        .animation(.easeInOut(duration: 0.18), value: isLoading)
    }

    private var label: some View {
        HStack(spacing: 10) {
            if let systemImage {
                AppSymbol(systemImage)
            }
            if let title {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        // [NEWCHAT-WIDTH] 可选最小宽度（nil/0 = 原行为零变化）。
        .frame(minWidth: labelMinWidth ?? 0)
    }

    private var progressTint: Color {
        style == .prominent ? AppTheme.primaryControlForeground(colorScheme) : .secondary
    }
}

// B8-FIX availability shims: upstream (deployment 26.5) uses the iOS 26 glass
// button styles bare. On 26+ EXACT upstream styles; below, the closest system
// equivalents (borderedProminent/bordered) — honest degradation, no invented
// glass. Ledger: PATCHES.md B8-AUTH.
struct PrimaryButtonStyleIfAvailable: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.buttonStyle(.glassProminent) }
        else { content.buttonStyle(.borderedProminent) }
    }
}
struct SecondaryButtonStyleIfAvailable: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.buttonStyle(.glass) }
        else { content.buttonStyle(.bordered) }
    }
}

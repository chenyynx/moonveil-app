// RemoteNewSessionWelcome.swift — 新会话欢迎区（AA 官方
// Views/Chat/NewSessionWelcomeView.swift 移植）。
//
// 移植差异：
//   • sidebarDrawerIsTransitioning / sidebarDrawerObscuresDetail 是官方侧栏环境
//     值，本仓远端无侧栏 —— canReveal 恒 true（揭示不被侧栏过渡打断）。
//   • completionFeedback（官方触觉扩展）→ onChange + UIImpactFeedbackGenerator。
//   • streamingText 走 iOS 18 守卫（RemoteStreamingTextPhrase 是 iOS 18 API；
//     iOS <18 静态完整显示）。
//   • 文案保持官方 zh-Hans 值（六标题随机 × 两行副标题；官方 Localizable.xcstrings
//     的 dashboard.new.typewriter.* set）。

import SwiftUI
import UIKit

struct RemoteNewSessionWelcomeView<Workspace: View>: View {
    @ViewBuilder let workspace: () -> Workspace
    private static var revealDuration: Double { 0.4 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40
    @State private var copy = RemoteNewSessionWelcomeCopy.allCases.randomElement() ?? .start
    @State private var titlePhraseCount = 0
    @State private var detailPhraseCount = 0
    @State private var hasStarted = false
    @State private var initialFrame = CGRect.zero
    @State private var isRevealing = false
    @State private var workspaceRevealed = false
    @State private var revealCompletion = 0
    @State private var titleLedger = RemoteGlyphRevealLedger(duration: RemoteNewSessionWelcomeView.revealDuration)
    @State private var detailLedger = RemoteGlyphRevealLedger(duration: RemoteNewSessionWelcomeView.revealDuration)

    private var canReveal: Bool { true }   // 本仓无侧栏：揭示不被过渡打断
    private var title: String { copy.title }
    private var detail: String {
        ["把任务发送到合适的设备。", "开始一个专注会话。"].joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            welcomeText
            workspace()
                .modifier(RemoteWelcomeWorkspaceReveal(progress: workspaceRevealed ? 1 : 0))
                .allowsHitTesting(workspaceRevealed)
                .accessibilityHidden(!workspaceRevealed)
        }
        // 观察真实布局但不定死宽高（onGeometryChange 是 iOS 18 API，主 target
        // 16/17 —— 用仓内 firstRowFenceReporter 同款 GeometryReader 观察模式）。
        // 绘制开始后，几何更新不得取消揭示任务。
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { if !hasStarted { initialFrame = proxy.frame(in: .global) } }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        if !hasStarted { initialFrame = frame }
                    }
            }
        )
        .task(id: RemoteWelcomeRevealKey(canReveal: canReveal, reduceMotion: reduceMotion, frame: initialFrame)) {
            await reveal()
        }
        .onChange(of: revealCompletion) { _, _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private var welcomeText: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSymbol("sparkles", size: 28).foregroundStyle(.primary)
            streamingText(title, revealedPhrases: titlePhraseCount, ledger: titleLedger)
                .font(.system(size: titleSize, weight: .bold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.65)
                .accessibilityAddTraits(.isHeader)
            streamingText(detail, revealedPhrases: detailPhraseCount, ledger: detailLedger)
                .font(.body).foregroundStyle(.secondary)
                .lineLimit(2...)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func streamingText(_ text: String, revealedPhrases: Int, ledger: RemoteGlyphRevealLedger) -> some View {
        // 未来短语从首帧起参与断行；共享渲染器独自控制其可见性与揭示。
        if #available(iOS 18.0, *) {
            RemoteStreamingTextPhrase.text(text)
                .modifier(RemoteStreamingGlyphReveal(ledger: ledger, revealedPhraseCount: revealedPhrases))
                .environment(\.remoteStreamingGlyphAnimation, isRevealing)
                .multilineTextAlignment(.leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        } else {
            Text(text)
                .multilineTextAlignment(.leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        }
    }

    private func reveal() async {
        guard canReveal, !hasStarted, initialFrame.width > 0, initialFrame.height > 0 else { return }
        if !reduceMotion {
            // 导航 chrome、composer 尺寸与缓存 workspace 先完成首帧布局。
            // 帧变化会重启这个静默间隔；欢迎页不被任何网络请求闸门。
            do { try await Task.sleep(for: .milliseconds(120)) }
            catch { return }
        }
        guard !Task.isCancelled else { return }
        hasStarted = true
        isRevealing = !reduceMotion
        // 取消、离开页面与 Reduce Motion 一律落定完整文案。
        defer {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                titlePhraseCount = RemoteTextPhraseSequence.chunks(in: title).count
                detailPhraseCount = RemoteTextPhraseSequence.chunks(in: detail).count
                workspaceRevealed = true
                isRevealing = false
            }
        }
        guard !reduceMotion else { revealCompletion += 1; return }
        // 与逐字账本一致的 cubic ease-out。选择器从首帧就参与布局，只有绘制变化。
        withAnimation(.timingCurve(1.0 / 3, 1, 2.0 / 3, 1, duration: Self.revealDuration)) {
            workspaceRevealed = true
        }
        var schedule = RemoteReplyFlushSchedule(start: .now)
        do {
            for count in RemoteTextPhraseSequence.chunks(in: title).indices {
                try Task.checkCancellation()
                titlePhraseCount = count + 1
                try await Task.sleep(until: schedule.deadline, clock: .continuous)
                schedule.advance(after: .now)
            }
            for count in RemoteTextPhraseSequence.chunks(in: detail).indices {
                try Task.checkCancellation()
                detailPhraseCount = count + 1
                try await Task.sleep(until: schedule.deadline, clock: .continuous)
                schedule.advance(after: .now)
            }
            try await Task.sleep(for: .seconds(Self.revealDuration + 2 / RemoteReplyPresentation.flushesPerSecond))
            try Task.checkCancellation()
            if canReveal { revealCompletion += 1 }
        } catch {
            // 生命周期打断由 defer 收尾。
        }
    }
}

private struct RemoteWelcomeRevealKey: Equatable {
    let canReveal: Bool
    let reduceMotion: Bool
    let frame: CGRect
}

private struct RemoteWelcomeWorkspaceReveal: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let effect = RemoteGlyphRevealEffect(progress: progress)
        content.opacity(effect.opacity)
            .blur(radius: effect.blurRadius)
            .offset(y: effect.offsetY)
    }
}

/// 每次呈现随机选一次，独立于网络更新、目标选择、输入与弹窗开合。
private enum RemoteNewSessionWelcomeCopy: CaseIterable {
    case start, idea, question, nextStep, explore, together

    var title: String {
        switch self {
        case .start: "接下来要构建什么？"
        case .idea: "Agent 应该从哪里开始？"
        case .question: "我们要处理什么？"
        case .nextStep: "给 Agent 一个任务。"
        case .explore: "从一个项目开始。"
        case .together: "哪里需要关注？"
        }
    }
}

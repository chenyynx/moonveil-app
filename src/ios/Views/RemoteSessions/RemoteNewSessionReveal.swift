// RemoteNewSessionReveal.swift — 新会话欢迎页的 glyph 级揭示动画。
//
// 移植自 AA 官方（origin-cache/ios/Agents Anywhere/Agents Anywhere）：
//   • Models/Chat/GlyphRevealLedger.swift  (GlyphRevealEffect + GlyphRevealLedger)
//   • Models/Chat/TextPhraseSequence.swift
//   • Models/Chat/ReplyPresentation.swift
//   • Views/Chat/Markdown/StreamingGlyphReveal.swift
//      (StreamingTextPhrase + StreamingGlyphReveal + GlyphRevealRenderer)
//
// 唯一差异（版本兼容，非功能裁剪）：textRenderer / TextAttribute 是 iOS 18 API，
// 主 target 16.0/17.0 —— 按仓内 glassEffect/#available 既有约定加守卫：
// iOS 18+ 走官方同款 TextRenderer 路径（逐 glyph 出生 + 揭示曲线），以下版本
// 静态完整显示（几何永远用未变换的最终字形；低版本无揭示时钟）。
// 替换 @Entry 宏为传统 EnvironmentKey（仓内 16/17 部署目标兼容）。

import SwiftUI
import Foundation

// MARK: - 揭示曲线（官方 GlyphRevealEffect，逐字）

/// 一条曲线同时驱动 opacity / blur / 位移，不改文字测量尺寸。
nonisolated struct RemoteGlyphRevealEffect {
    let progress: Double
    var opacity: Double { progress }
    var blurRadius: Double { 3 * (1 - progress) }
    var offsetY: Double { 3 * (1 - progress) }
}

// MARK: - 逐字出生时刻账本（官方 GlyphRevealLedger，逐字）

/// TextRenderer 可能在主线程外绘制。出生时刻属于新追加的字形；
/// 之后的 flush 不会重启早先批次的动画。
nonisolated final class RemoteGlyphRevealLedger: @unchecked Sendable {
    private let lock = NSLock()
    private let duration: TimeInterval
    private var settledCount = 0
    // 只有新揭示的后缀需要逐字出生时刻；静态历史不得在每次绘制时分配字符级数组。
    private var births: [TimeInterval] = []

    init(duration: TimeInterval = RemoteReplyPresentation.revealSeconds) {
        precondition(duration > 0 && duration.isFinite)
        self.duration = duration
    }

    func progress(count: Int, now: TimeInterval, enabled: Bool) -> [Double]? {
        lock.lock()
        defer { lock.unlock() }
        // Text 重建标题/片段时可能短暂发出空 Text——中间绘制不得抹掉既有出生时刻。
        guard count > 0 else { return nil }
        guard enabled else {
            settledCount = count
            births.removeAll(keepingCapacity: false)
            return nil
        }
        settledCount = min(settledCount, count)
        let revealingCount = count - settledCount
        if revealingCount < births.count { births.removeLast(births.count - revealingCount) }
        if revealingCount > births.count {
            births.append(contentsOf: repeatElement(now, count: revealingCount - births.count))
        }
        guard births.contains(where: { now - $0 < duration }) else {
            settledCount = count
            births.removeAll(keepingCapacity: true)
            return nil
        }
        return Array(repeating: 1, count: settledCount) + births.map { born in
            let progress = min(1, max(0, (now - born) / duration))
            return 1 - pow(1 - progress, 3)
        }
    }
}

// MARK: - 短语切分（官方 TextPhraseSequence，逐字）

/// 保持本地化词完整（含中文词边界）。每块携带原标点与空格，拼接无损。
nonisolated enum RemoteTextPhraseSequence {
    static func chunks(in text: String) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        var wordCount = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { _, range, _, _ in
            wordCount += 1
            let phrase = text[start..<range.upperBound]
            if wordCount >= 2 || phrase.count >= 8 {
                result.append(String(phrase))
                start = range.upperBound
                wordCount = 0
            }
        }
        if start < text.endIndex {
            let remainder = String(text[start...])
            if !result.isEmpty && remainder.allSatisfy({ $0.isWhitespace || $0.isPunctuation }) {
                result[result.count - 1] += remainder
            } else {
                result.append(remainder)
            }
        }
        return result
    }
}

// MARK: - 揭示节拍（官方 ReplyPresentation + ReplyFlushSchedule，逐字）

nonisolated enum RemoteReplyPresentation {
    static let flushesPerSecond = 30.0
    static let flushInterval: Duration = .seconds(1 / flushesPerSecond)
    static let revealSeconds: TimeInterval = 0.24
    // 最后一次 flush 后留两个布局/绘制帧，再收起 renderer 或停绘制时钟。
    static let settleDelay: Duration = .seconds(revealSeconds + 2 / flushesPerSecond)
}

/// 独立推进截止时刻，处理耗时不累计成更慢的节拍。主线程忙时跳过错过的帧。
nonisolated struct RemoteReplyFlushSchedule {
    let interval: Duration
    private(set) var deadline: ContinuousClock.Instant

    init(start: ContinuousClock.Instant, interval: Duration = RemoteReplyPresentation.flushInterval) {
        precondition(interval > .zero)
        self.interval = interval
        deadline = start.advanced(by: interval)
    }

    mutating func advance(after now: ContinuousClock.Instant) {
        deadline = deadline.advanced(by: interval)
        if deadline <= now { deadline = now.advanced(by: interval) }
    }
}

// MARK: - 揭示环境（传统 EnvironmentKey，仓内 16/17 兼容）

extension EnvironmentValues {
    var remoteStreamingGlyphAnimation: Bool {
        get { self[RemoteStreamingGlyphAnimationKey.self] }
        set { self[RemoteStreamingGlyphAnimationKey.self] = newValue }
    }
}

private struct RemoteStreamingGlyphAnimationKey: EnvironmentKey {
    static let defaultValue = false
}

// MARK: - 短语属性 + 揭示修饰（官方 StreamingTextPhrase / StreamingGlyphReveal /
// GlyphRevealRenderer；iOS 18 守卫——textRenderer 是 iOS 18 API）

@available(iOS 18.0, *)
nonisolated struct RemoteStreamingTextPhrase: TextAttribute {
    let index: Int

    @MainActor static func text(_ value: String) -> Text {
        let phrases = RemoteTextPhraseSequence.chunks(in: value)
        var interpolation = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: phrases.count)
        for (index, phrase) in phrases.enumerated() {
            interpolation.appendInterpolation(Text(verbatim: phrase).customAttribute(Self(index: index)))
        }
        return Text(LocalizedStringKey(stringInterpolation: interpolation))
    }
}

/// 时钟只更新绘制：不追加文字、不重解析、不动画布局约束。
/// 每个段落/代码片段拥有自己的账本。iOS 18+ 官方同款路径。
struct RemoteStreamingGlyphReveal: ViewModifier {
    @Environment(\.remoteStreamingGlyphAnimation) private var isStreaming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ledger: RemoteGlyphRevealLedger
    private let revealedPhraseCount: Int?

    init(ledger: RemoteGlyphRevealLedger = RemoteGlyphRevealLedger(), revealedPhraseCount: Int? = nil) {
        _ledger = State(initialValue: ledger)
        self.revealedPhraseCount = revealedPhraseCount
    }

    func body(content: Content) -> some View {
        let enabled = isStreaming && !reduceMotion
        if !enabled && revealedPhraseCount == nil {
            // 已定稿历史：原生 Text 绘制，无时钟、无逐字遍历。
            content
        } else if #available(iOS 18.0, *) {
            TimelineView(.animation(paused: !enabled)) { timeline in
                content.textRenderer(RemoteGlyphRevealRenderer(
                    ledger: ledger,
                    now: timeline.date.timeIntervalSinceReferenceDate,
                    enabled: enabled,
                    revealedPhraseCount: revealedPhraseCount
                ))
            }
        } else {
            // iOS < 18：TextRenderer 不可用——静态完整显示（几何 = 最终态）。
            content
        }
    }
}

@available(iOS 18.0, *)
nonisolated struct RemoteGlyphRevealRenderer: TextRenderer {
    let ledger: RemoteGlyphRevealLedger
    let now: TimeInterval
    let enabled: Bool
    var revealedPhraseCount: Int? = nil

    // 为模糊与轻微上浮扩栅格边界，不扩布局边界。
    var displayPadding: EdgeInsets { .init(top: 6, leading: 6, bottom: 9, trailing: 6) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let count = layout.reduce(0) { total, line in
            total + line.reduce(0) { $0 + (isRevealed($1) ? $1.count : 0) }
        }
        let progress = ledger.progress(count: count, now: now, enabled: enabled)
        if progress == nil {
            for line in layout {
                if line.allSatisfy(isRevealed) { context.draw(line) }
                else {
                    for run in line where isRevealed(run) { context.draw(run) }
                }
            }
            return
        }
        var index = 0
        for line in layout {
            for run in line where isRevealed(run) {
                guard let progress else { context.draw(run); continue }
                // 已定稿的 run 走系统高效绘制路径。
                if progress[index..<(index + run.count)].allSatisfy({ $0 >= 1 }) {
                    context.draw(run)
                    index += run.count
                } else {
                    for glyph in run {
                        var copy = context
                        let effect = RemoteGlyphRevealEffect(progress: progress[index])
                        copy.opacity *= effect.opacity
                        copy.translateBy(x: 0, y: effect.offsetY)
                        copy.addFilter(.blur(radius: effect.blurRadius))
                        copy.draw(glyph, options: .disablesSubpixelQuantization)
                        index += 1
                    }
                }
            }
        }
    }

    private func isRevealed(_ run: Text.Layout.Run) -> Bool {
        guard let revealedPhraseCount, let phrase = run[RemoteStreamingTextPhrase.self] else { return true }
        return phrase.index < revealedPhraseCount
    }
}

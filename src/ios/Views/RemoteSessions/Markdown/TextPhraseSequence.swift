// TextPhraseSequence.swift — AA 官方 Models/Chat/TextPhraseSequence.swift 逐字搬运。
// 位置差异：官方在 ClientCore Models 层，本仓放 app 层 Markdown/ 与消费方
// （StreamingGlyphReveal / RemoteNewSessionReveal / RemoteNewSessionWelcome）同组，同 GitDirective 先例。
// B9-FIX6（2026-09-22）：Batch 1 漏搬件第二例（穷举式缺口扫描：官方有定义+本仓无定义+被本仓引用，交集仅剩本件）。

import Foundation

/// Keep localized words intact, including Chinese word boundaries. Each chunk
/// carries its original punctuation and spacing, so concatenation is lossless.
nonisolated enum TextPhraseSequence {
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

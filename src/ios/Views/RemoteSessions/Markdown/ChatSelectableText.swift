// ChatSelectableText.swift — AA 官方 Views/Chat/Markdown/ChatSelectableText.swift 逐字搬运（[T-remote-skin] AA 原版皮肤批，pp 2026-09-22 拍板三皮肤/引 Textual）。
// 无其他差异。
import SwiftUI
import Textual

/// Uses the same range selection as Markdown without interpreting user input or
/// tool output as markup. SwiftUI Text's copy menu selects the entire value on iOS.
struct ChatSelectableText: View {
    let text: String

    var body: some View {
        InlineText(text, parser: LiteralTextParser())
            .textual.textSelection(.enabled)
    }
}

private struct LiteralTextParser: MarkupParser {
    func attributedString(for input: String) throws -> AttributedString {
        AttributedString(input)
    }
}

// SessionTurnActions.swift — AA 官方 Views/Chat/SessionTurnActions.swift 逐字搬运（P1 会话聊天页批）。
// 无差异。
// 差异/落地说明补充：
//   • 文案：本文件 String(localized:) 键为官方源键，取值已按官方 Localizable.xcstrings
//     的 zh-Hans 显示值落地（先例 COMPOSER-FULL / NEWSESSION-COPY；官方源键与其 en/zh
//     条目见 origin-cache/Resources/Localization/Localizable.xcstrings）。

import SwiftUI

struct SessionTurnActions: View {
    let action: TimelineTurnAction
    @State private var copied = false

    var body: some View {
        let text = action.copyText
        HStack(spacing: 2) {
            Button {
                UIPasteboard.general.string = text; copied = true
            } label: { AppSymbol(copied ? "checkmark" : "document.on.document").frame(width: 44, height: 44) }
            .accessibilityLabel(copied ? String(localized: "已复制") : String(localized: "复制回复"))
            .task(id: copied) {
                guard copied else { return }
                do { try await Task.sleep(for: .seconds(2)); copied = false } catch {}
            }
            ShareLink(item: text) { AppSymbol("square.and.arrow.up").frame(width: 44, height: 44) }
                .accessibilityLabel(String(localized: "分享"))
        }
        .disabled(text.isEmpty)
        .buttonStyle(.plain).font(.system(size: 15)).foregroundStyle(.secondary).padding(.leading, -10)
        .accessibilityIdentifier("chat.turn.actions")
    }
}

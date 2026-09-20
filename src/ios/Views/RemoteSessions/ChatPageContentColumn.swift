// ChatPageContentColumn.swift — AA 官方 Views/Chat/ChatPageContentColumn.swift 逐字搬运（P1 会话聊天页批）。
// 无差异。

import SwiftUI

/// Apply to the content inside the scroll view. The scroll viewport stays full
/// width while both detail pages share the session's ordinary centered layout.
struct ChatPageContentColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 24).padding(.top, 16)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
}

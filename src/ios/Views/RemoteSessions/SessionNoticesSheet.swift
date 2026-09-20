// SessionNoticesSheet.swift — AA 官方 Views/Chat/SessionNoticesSheet.swift 逐字搬运（P1 会话聊天页批）。
// 无差异（SheetCloseToolbar / appSheetPresentation 为本仓既有等价件：
// Views/AuthAA/SheetCloseButton.swift、AppSheetPresentation.swift）。

import SwiftUI

struct SessionNoticesSheet: View {
    let model: SessionChatModel
    var initialNoticeID: String? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(model.session.notices.notices.filter(\.isVisible)) { item in
                            SessionInteractionContent(item: item, chat: model).id(item.id)
                        }
                    }.padding(16)
                }
                .onAppear { if let initialNoticeID { proxy.scrollTo(initialNoticeID, anchor: .top) } }
            }
            .navigationTitle(String(localized: "交互与通知"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { dismiss() } }
        }
        .appSheetPresentation(.compact)
    }
}

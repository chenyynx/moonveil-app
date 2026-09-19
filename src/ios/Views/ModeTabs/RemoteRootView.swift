// RemoteRootView.swift — 远程 tab 三态壳（U1 终案；pp 2026-09-15 定稿：顶栏标题位
// 与本机侧渲染同一个 ModeTabPicker，切换时胶囊位置不动）。
//
// Consumes ONLY RemoteKit's public facade (RemoteService / RemoteServiceState).
// Staged with deadlines (完整性铁律 — 明示不藏):
//   • QR camera pairing → batch 8（manual bootstrap(url, token) 现在就是活路）
//   • R0 会话列表骨架   → 已接线（connected 态渲染列表；会话行数据仍为预览占位）
//   • 会话消息面 / notice 交互 UI → batch 8（timeline/snapshot/noticeSnapshot public 面）
// 不装成功态：没连上就显示没连上。

import SwiftUI

struct RemoteRootView: View {
    @ObservedObject var service: RemoteService
    @ObservedObject private var tabRouter = RootTabRouter.shared

    /// 与本机侧标题同源（SOUL.md name，回退 Moonveil）——同一真源，非平行命名通道。
    @State private var soulName: String = {
        let n = SoulStore.cachedMetadata.name
        return n.isEmpty ? "Moonveil" : n
    }()

    @State private var pendingNotices = 0

    var onOpenLogin: () -> Void = {}

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ModeTabPicker(
                            selection: $tabRouter.mode,
                            localLabel: soulName
                        )
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            soulName = n.isEmpty ? "Moonveil" : n
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .idle, .degraded: guide
        case .pairing:         pairingPending
        case .ready:           connected
        }
    }

    // MARK: State 1 — 未登录空态卡（U1 终案：一键回全屏登录；表单本体=官方 ManualLoginView）

    private var guide: some View {
        VStack(spacing: 14) {
            if case .degraded(let reason) = service.state {
                Label(reason, systemImage: "wifi.exclamationmark")
                    .font(.callout).foregroundStyle(.orange)
            }
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("还没有连接远程工作空间")
                .font(.title3.bold())
            Button {
                onOpenLogin()
            } label: {
                Text("去登录").fontWeight(.semibold).frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(20)
    }


    // MARK: State 2 — 已配置待配对

    private var pairingPending: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("等待配对完成…").font(.callout)
            Button("取消，回到引导") { service.reset() }.font(.callout)
        }
    }

    // MARK: State 3 — 已连接（R0 列表已接线：RemoteSessionListView 挂进本 NavigationStack，
    // 顶栏 ModeTabPicker 由此处提供，列表不再自建导航栈；断开入口在列表右上角菜单）

    private var connected: some View {
        RemoteSessionListView(service: service,
                              pendingNotices: pendingNotices,
                              onDisconnect: {
                                  service.reset()
                                  pendingNotices = 0
                              })
    }
}

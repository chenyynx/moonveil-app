// RemoteRootView.swift — 远程 tab 三态壳（U1 终案；bottom-dock 批次起顶栏胶囊已迁壳层，
// 本壳顶栏留空——不补标题、不补词条）。
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

    @State private var pendingNotices = 0
    /// 右上角 🔍（pp 2026-09-26「搜索放右上角」）：sheet 出搜索占位页。
    @State private var showsSearch = false
    /// 官方 RootView.swift:52 的全局染色数据源（黑/白自适应）。
    @Environment(\.colorScheme) private var colorScheme

    var onOpenLogin: () -> Void = {}

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // [SEARCH-TOPRIGHT] pp 2026-09-26「搜索放右上角」。
                    ToolbarItem(placement: .topBarTrailing) {
                        SearchToolbarButton(showsSearch: $showsSearch)
                    }
                }
                .sheet(isPresented: $showsSearch) { SearchPlaceholderView() }
        }
        // 子树拆卸兜底：content 按 service.state 分支，.pairing 会把整棵
        // RemoteSessionListView 换成 pairingPending——它的 @State 随葬，详情页 push
        // 期间由该列表 `.onChange(of: showsDeviceDetail)` 维护的 remoteAtRoot 就再也
        // 没人复位（标志永久卡 false：远端根部横滑切 tab 报废 + 齿轮回不来）。
        // 复位必须挂在活着的壳上，不能挂回被销毁的子树。
        // .idle/.degraded 仍渲染列表（同 switch），故只有 .pairing 需要。
        .onChange(of: service.state) { _, newState in
            if newState == .pairing { tabRouter.remoteAtRoot = true }
        }
        // 官方 RootView.swift:52 逐字同源：全局 tint = 主文本色（黑/白），官方
        // Assets 无 AccentColor、仅靠这行把 Menu/Label 图标/裸 Button 全染黑。
        // 漏搬导致「全部项目/新设备/创建项目」显示系统蓝（pp 官方截图 2026-09-21 定案）。
        .tint(AppTheme.primaryText(colorScheme))
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        // 未连接也用列表页：设备终端卡显示无设备 + 提醒连接（pp 2026-09-20
        // 「没连接的时候这个页面应该也是连接了的那个页面啊 只是没设备
        //   要提醒用户连接」）；首启登录由更上层的 needsLoginGate 全屏盖负责。
        case .pairing:               pairingPending
        case .idle, .degraded, .ready: connected
        }
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
    // 顶栏留空（胶囊已迁壳层，bottom-dock 批次），断开入口在列表右上角菜单）

    private var connected: some View {
        RemoteSessionListView(service: service,
                              pendingNotices: pendingNotices,
                              onDisconnect: {
                                  service.reset()
                                  pendingNotices = 0
                              },
                              onOpenLogin: onOpenLogin)
    }
}

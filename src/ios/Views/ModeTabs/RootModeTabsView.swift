// RootModeTabsView.swift — the single fork point (D4 §2). pp 2026-09-15 定稿:
// 胶囊不占独立行——每侧 tab 在自己的顶栏标题位渲染同一个 ModeTabPicker，
// 切换时胶囊纹丝不动（两侧 NavigationStack 同构 toolbar）。
//
// Isolation guarantees:
//   • 本机 tab = upstream ContentView() 本体零改动（其 toolbar principal 的
//     标题→胶囊替换是 pp 明示的 UI 改动，PATCHES.md B7-UI 立账；数据流零触碰）
//   • 远程 tab = RemoteRootView，首次访问才创建，只 import RemoteKit public 面
//   • 跨 tab 唯一动作 = RootTabRouter 纯路由；两侧胶囊共享同一 selection 源
//   • opacity+hitTesting 换层，两侧 @StateObject 均不churn（列表状态跨 tab 存活）

import SwiftUI
import RemoteKit

struct RootModeTabsView: View {
    @StateObject private var router = RootTabRouter.shared
    @StateObject private var remoteService = RemoteService()

    var body: some View {
        ZStack {
            ContentView()
                .opacity(router.mode == .local ? 1 : 0)
                .allowsHitTesting(router.mode == .local)

            if router.seenRemote {
                RemoteRootView(service: remoteService)
                    .opacity(router.mode == .remote ? 1 : 0)
                    .allowsHitTesting(router.mode == .remote)
            }
        }
    }
}

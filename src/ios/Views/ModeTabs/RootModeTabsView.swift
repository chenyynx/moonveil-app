// RootModeTabsView.swift — the single fork point (D4 §2) + 首启入口终案接线:
// 未登录且落在远程 tab → AA 官方登录页全屏盖（扫码/手动两颗 CTA + JO-6 本地灰字
// 入口）；登录成功 → 远程 tab；本地入口 → 本机 tab；lastTab 记忆（RootTabRouter）。
// 恢复：官方 restoreSession 语义（UserDefaults server + keychain token）。
// 隔离：本机 tab = upstream ContentView 本体零改动；登录盖只在远程侧出现，
// 首启默认 tab 仍是本机（lastTab 为空时），本机路径与上游逐字节同。

import SwiftUI
import RemoteKit

@MainActor
struct RootModeTabsView: View {
    @StateObject private var router = RootTabRouter.shared
    @StateObject private var remoteService = RemoteService()
    @State private var showsQRLogin = false
    @State private var showsManualLogin = false
    @State private var didRestore = false

    var body: some View {
        ZStack {
            ContentView()
                .opacity(router.mode == .local ? 1 : 0)
                .allowsHitTesting(router.mode == .local)

            if router.seenRemote {
                RemoteRootView(
                    service: remoteService,
                    onOpenLogin: { /* cover auto-presents via needsLoginGate */ }
                )
                .opacity(router.mode == .remote ? 1 : 0)
                .allowsHitTesting(router.mode == .remote)
            }
        }
        .task {
            guard !didRestore else { return }
            didRestore = true
            _ = remoteService.restoreSession()   // official restore; silent no-op if absent
        }
        .fullScreenCover(isPresented: needsLoginGate) {
            NavigationStack {
                ServiceEntryView(
                    service: remoteService,
                    onManualLogin: { showsManualLogin = true },
                    onQRCodeLogin: { showsQRLogin = true },
                    onLocalEntry: { router.route(to: .local) }
                )
            }
            .sheet(isPresented: $showsQRLogin) {
                QRCodeLoginView(
                    service: remoteService,
                    onDashboardRequested: { /* state flips .ready → gate closes itself */ }
                )
            }
            .sheet(isPresented: $showsManualLogin) {
                ManualLoginView(service: remoteService)
            }
        }
    }

    /// 远程 tab 且未登录 → 盖登录页；登录成功(ready)自动收起。
    private var needsLoginGate: Binding<Bool> {
        Binding(
            get: { router.mode == .remote && remoteService.state != .ready },
            set: { if !$0 && remoteService.state != .ready { router.route(to: .local) } }
        )
    }
}

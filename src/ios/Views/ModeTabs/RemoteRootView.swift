// RemoteRootView.swift — 远程 tab 三态壳（U1 终案；bottom-dock 批次起顶栏胶囊已迁壳层，
// 本壳顶栏留空——不补标题、不补词条）。
//
// [去嵌套 2026-09-30] 本壳**不再是导航容器**：原 body 的 NavigationStack 已拆，
// `content` 直接作为 body 根交给外层容器栈（RootModeTabsView 的
// `NavigationStack(path: $containerNav.path)`）承载。拆壳原因（build 438 装机实锤）：
// 树内层栈嵌在外层容器栈里时不渲染自己的导航栏，内层 toolbar 按钮上浮到容器栏，
// 而容器栏当时被 root 的 `.toolbar(.hidden)` 吸走 → 远端线顶栏全灭。全 App 收成
// 一层栈后：容器栏 = 唯一顶栏宿主，本壳的 ≡ / ＋（[SEARCH-SWAP 2026-10-01] 原为
// ≡ / 🔍，搜索已迁底栏）按 `RootTabRouter.shared.mode`
// 门控挂在这里（见 body），树内深页（聊天 / 设备详情）push 全部改走容器栈
// `ContainerNav.shared.pushChat(_:)`。
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
    /// 搜索占位 sheet 的开关。[SEARCH-SWAP 2026-10-01 pp「搜索 ⇄ 新会话 互换
    /// 位置」] 写入方从顶栏 🔍 换成底栏 ModeTabBar 的玻璃圆钮（onSearchTapped，
    /// 见 body 的 safeAreaInset）；sheet 本身与呈现位置未动。
    @State private var showsSearch = false
    /// 官方 RootView.swift:52 的全局染色数据源（黑/白自适应）。
    @Environment(\.colorScheme) private var colorScheme

    var onOpenLogin: () -> Void = {}

    var body: some View {
        // [去嵌套 2026-09-30] 导航由容器栈承担：本壳不再自带 NavigationStack，
        // `content` 直接作为 body 根，其上的修饰符链原样重挂（语义逐字不变，只是
        // 求值宿主从「树内层栈」换成了「容器栈的 root 内容」）。
        content
            // [切页转场 v3 2026-09-30 · cc] 缩放已从本层（v2 位：栈内、但仍在
            // safeAreaInset 求值链上）下沉到 content 各分支本体（pairingPending /
            // connected，见文件下半）。v2 残留在本层仍打坏安全区记账：装机日志
            // （build 431）实锤离场树底安全区窗口收尾塌到 0.0、进场树保持 0 直到
            // 切页后 ~214ms 才弹回 98 = 用户可见「画面高度在掉」。求值链必须零
            // 动画变换，勿挂回本层。详见 RootModeTabsView 末尾 TreeSwitchZoom
            // 「挂点纪律」。
            // [TG-TABBAR 2026-09-30] 自绘栏挂 root 页底边——远端线的
            // 二级页（会话聊天/设备详情）从容器栈 push 时整页覆盖含栏。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ModeTabBar(tabMode: .remote, onSearchTapped: { showsSearch = true })
            }
            // [TG-TABBAR-FIX 2026-09-30] 键盘豁免·权威挂点（原理与勿动理由见
            // ContentView.stackLayout 同款注释）：豁免须包在 inset 外侧。
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // [顶栏审计收口 2026-09-30 晚] displayMode 同属栏偏好写：按 mode 门控
            // （原无条件写 = 非当前树也替当值树顶值；审计漏网名单之一）。形状对照
            // .toolbar 门控与 TreeTitleDisplayMode。
            .treeTitleDisplayMode(tabRouter.mode == .remote)
            .toolbar {
                // [去嵌套 2026-09-30] chrome 门控：三棵树的 root 内容在容器栈的
                // ZStack 里同时活着（保活切页），而顶层栏是**唯一**一根——不门控
                // 三树的 ≡ / ＋（原 🔍）/ ⋯ 会一起出现在同一根栏里（串台）。判据 =
                // 当前树。
                if tabRouter.mode == .remote {
                    // [TABLER-ICONS] 与本机页左上角一致的设置入口（Tabler menu 两横，
                    // 走 tabRouter.showSettings，sheet 由壳层呈现）。
                    // [ICON-ALIGN 2026-10-01 · pp「远端页左上角那个图标大小和本地页
                    // 左上角那个图标大小不一样 对齐本地页左上角图标大小」] 本钮原为
                    // .resizable() 直出 20×20（等布局定尺才渲染，与本机页 ≡ 的 22pt
                    // 预栅格化位图既差尺寸又差管线）→ 换 ContentView.toolbarIcon
                    // 22pt 共用栅格化器，与本机页 ≡（ContentView:3767 调用点）同款
                    // 同尺寸同模板，两根线顶栏左右角从此对齐。
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            tabRouter.showSettings = true
                        } label: {
                            ContentView.toolbarIcon("aa-Tabler-Menu", pointSize: 22, template: true)
                        }
                        // [TINT-FIX2] 跟本机页统一，盖住 AccentColor 蓝。
                        .tint(.primary)
                        .accessibilityLabel(Text(String(localized: "Settings")))
                    }
                    // [SEARCH-SWAP 2026-10-01 pp「搜索 ⇄ 新会话 互换位置」] 本位
                    // 原是 🔍（搜索已迁底栏玻璃圆钮，见上 safeAreaInset 的
                    // onSearchTapped），现为 ＋ 新建远端会话，声明顺序不动。
                    // 显示条件 = 已登录/已连接（service.state == .ready）：新会话页
                    // 及其创建链路（services → repository）只在组合根就绪时存在，
                    // 非就绪态给出按钮 = 点了没反应，故直接不渲染（同 pairingPending
                    // 态整片无远端 chrome 的既有处理）。
                    // 动作复用远端已有的「开新会话页」单通道 `onReturnToNewSession`
                    //（官方 onSelectPage(.newSession) 的本仓等价物，由
                    // RemoteSessionListView.registerRootChannels 在 .ready 时注册
                    // ——注册条件与本按钮显示条件同值，故显示即可点）。该闭包持有
                    // 常驻列表页自身：栈顶不是 .remoteTreeChat 时不 pop，只开
                    // fullScreenCover(RemoteNewSessionView)，创建成功后的「刷新列表 +
                    // 关 cover 后 push 聊天页」时序沿用原链路（pendingChatSessionId），
                    // 不在本壳复刻、不阉割。
                    if service.state == .ready {
                        ToolbarItem(placement: .topBarTrailing) {
                            NewSessionToolbarButton {
                                service.chat?.onReturnToNewSession?()
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showsSearch) { SearchPlaceholderView() }
            // [去嵌套 2026-09-30] 原 `.toolbar(.visible, for: .navigationBar)` 对冲退役
            // （原 [容器化 C2-FIX] 判「容器 root 的 .toolbar(.hidden) 经环境传播会藏掉
            // 内层导航栏——就近钉 visible」）：容器 root 已不再 hidden，泄漏源已除，
            // 这句钉 visible 没有对冲对象了，留着只会盖住未来真正的可见性判据。
            // 判例留档：可见性对冲只在**确有对冲对象**时才加；根因（嵌套栈不渲染
            // 导航栏）被摘掉后，对冲必须同批摘，否则下一次容器栏改动会被它顶住。
            // [去嵌套 2026-09-30] 原 `.onChange(of: service.state)` 子树拆卸兜底
            // （.pairing 复位 remoteAtRoot）整体退役：remoteAtRoot 全仓删除，顶栏
            // 可见性改由「容器栏 = 唯一顶栏宿主」保证，不再需要任何标志复位。
            // 教训浓缩留档：**兜底复位必须挂在活着的宿主上**——原写法把复位挂在本壳
            // 是对的（壳在子树被 .pairing 换掉时仍活着），但它守的标志本身没了，
            // 于是整块随标志一起退役，不必移植到容器层。
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
        // [切页转场 v3 2026-09-30 · cc] 缩放挂点：等待态本体（v3 最内层，见
        // RootModeTabsView 末尾 TreeSwitchZoom 挂点纪律——求值链零变换）。
        .treeSwitchZoom(.remote)
        // [TG-TABBAR 2026-09-30] 此段原为 [TAB-RESTORE 2026-09-28] 的「系统 tab
        // 栏恢复原生渲染」说明——系统栏已整体退役；等待态在远端树 root 页内，
        // 自绘栏（ModeTabBar）照常在场。
    }

    // MARK: State 3 — 已连接（R0 列表已接线：RemoteSessionListView 是远端树的 root
    // 内容；[去嵌套 2026-09-30] 树壳已拆，本壳不再自带 NavigationStack，导航由容器栈
    // 承担；顶栏留空（胶囊已迁壳层，bottom-dock 批次），断开入口在列表右上角菜单）

    private var connected: some View {
        RemoteSessionListView(service: service,
                              pendingNotices: pendingNotices,
                              onDisconnect: {
                                  service.reset()
                                  pendingNotices = 0
                              },
                              onOpenLogin: onOpenLogin)
            // [切页转场 v3 2026-09-30 · cc] 缩放挂点：已连接态列表本体（v3 最内层，
            // 与 pairingPending 同款；求值链零变换——v2 挂在 safeAreaInset 内侧仍
            // 致 98→0.0 塌陷 + ~214ms 迟恢复，build 431 日志）。
            .treeSwitchZoom(.remote)
    }
}

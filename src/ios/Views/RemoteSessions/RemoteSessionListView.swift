// RemoteSessionListView.swift — 远端会话列表（R0，batch 8）
//
// 形态（pp 2026-09-20 定稿，REMOTE-REDESIGN-4 = 方案 B「Claude 设计语言」落地）：
// 暖奶油画布（→ 2026-09-26 pp「远端背景改成和本地一样」起改 systemBackground）
//   → 深色终端窗卡（设备）→ 液态玻璃操作 → 13pt tertiary 项目头 → 暖卡堆
// 会话（琥珀待批准 / teal running / 珊瑚未读点）；底栏 = 与本机同构的双圆 FAB 行
//   ——bottom-dock 批次：原「新会话胶囊 + 常驻搜索胶囊」退役，换回本机原装
//   双圆 FAB（搜索 FAB 点开 inline 搜索条，光束参数与本机栏一致、随条高改 28）；
//   [SEARCH-BEAM] pp 2026-09-24「远端也加」的光束随条保留。顶栏胶囊已迁壳层。
// AA 视觉只出现在点进去的弹窗页（PairDeviceSheet / ProjectEditor / 详情 / 归档）。
// 数据源只走 RemoteKit 的 public facade（RemoteService / RemotePairingPayload），
// 不读 ChatStore、不碰 ContentView 的 stackList（死隔离：远端列表与本机列表文件级零交集）。
//
// 功能面（AA 官方移动端会话列表全量，不阉割）：
//   • 设备：深色终端窗卡（三色点 + mono 地址 + CONNECTED）；配对新设备 =
//     顶栏右上角 ＋ → PairDeviceSheet（pp 2026-09-20 挪位）
//   • 项目：✳ + 13pt tertiary 折叠头（整行点击折叠）＋ 新建 → ProjectEditorSheet；
//     顶栏右上角 … = AA 官方全量列表菜单（侧栏显示 按项目/全部会话 + 归档筛选
//     活跃/已归档/全部 + 归档会话）——AA-LIST-MENU，2026-09-20
//   • 会话：暖卡堆（白圆 lucide 头像 + 标题/摘要 + 时间）；状态语义化——
//     等待批准=琥珀胶囊 / 运行中=teal 转圈+mono running / 未读=卡角珊瑚点 / 置顶=pin
//   • 长按菜单：Open / Rename / Pin·Unpin / Archive·Restore / Copy Session ID / Delete
//     ——[SESSION-SWIPE-TO-LONGPRESS] pp 2026-09-24「把左滑右滑的功能改成长按的
//     方式，让滑动卡片区域能滑动页面到本地列表页」：原行 swipeActions（置顶/归档/
//     删除）整体迁入长按菜单；Delete 服务端仍无删除端点（Staged，不假造成功态），
//     卡片区横滑让给页切手势（同批撤 RootModeTabsView 的 RemoteRowsFence）。
//   • 归档页（ArchivedSessionsSheet）+ 下拉刷新 + 空态诚实
//
// Staged with deadlines（完整性铁律 — 明示不藏）：
//   • DATA-1 已落地（2026-09-20）：列表读（listSessions 三态 + 项目名真实化）
//     与写（置顶 / 归档 / 取消归档 / 标记已读；乐观更新 + 失败回滚）全链路接通，
//     未读 / 运行 / 待批准指示器全部来自真实会话状态，预览假数据已全删。
//   • 删除会话：服务端无删除端点（仅归档/取消归档/标记已读）——Staged，不假造成功态。
//   • 重命名 UI（AA RenameSheet）：写端点 patchSessionMeta(title:) 已就绪，随弹窗批接入。
//   • 会话页聊天接线（timeline/snapshot）+ 分页加载（nextCursor）→ 下一批。

// [SEARCH-BEAM] 本地 SPM 包，与 ContentView 本机栏同源（vendored 自 libraries.dev
// border-beam 官方 iOS 移植，上游 MIT；BB1 比例补丁见 PATCHES.md）。
import BorderBeamKit
import SwiftUI

struct RemoteSessionListView: View {
    /// [FIX-auth-sheet-seq] 手动/扫码登录的延后弹出队列：AddDeviceSheet 退场
    /// 动画走完（onDismiss）后才真正弹登录表，防同帧叠表抖掉 OAuth 网页弹层。
    private enum PendingAuthSheet { case qr, manual }

    @ObservedObject var service: RemoteService
    /// [SESSION-SWIPE-TO-LONGPRESS] 页切冻结观察（与本机 ContentView 同款单例
    /// @ObservedObject）：横滑切页判定胜出时冻结本列表竖滚，防切页时列表跟着跑——
    /// 卡片区现在能武装页切，没有这条会露馅。
    @ObservedObject private var tabRouter = RootTabRouter.shared
    @Environment(\.colorScheme) private var colorScheme
    /// 审批计数与断开动作由 RemoteRootView 透传（本视图不持有连接生命周期）。
    var pendingNotices: Int = 0
    var onDisconnect: () -> Void = {}
    /// 未连接时的登录/配对入口（唤起 RootModeTabsView 的登录全屏盖）。
    var onOpenLogin: () -> Void = {}

    /// 配对观察器（官方 AgentSetupCoordinator：账号级、不随 sheet 存亡；列表页
    /// 是远端功能的常驻根视图，生命周期等价）。
    @StateObject private var agentSetup: AgentSetupCoordinator

    init(service: RemoteService, pendingNotices: Int = 0,
         onDisconnect: @escaping () -> Void = {}, onOpenLogin: @escaping () -> Void = {}) {
        self.service = service
        self.pendingNotices = pendingNotices
        self.onDisconnect = onDisconnect
        self.onOpenLogin = onOpenLogin
        _agentSetup = StateObject(wrappedValue: AgentSetupCoordinator(service: service))
    }

    // MARK: - 服务器地址（RemoteService 只写不读；读官方持久化键 agentsAnywhere.serverURL，
    // 与 RemoteRootView 同一来源）
    // [CI-FIX] 注释不出现 RemoteKit 符号名（import-scan 门禁连注释都扫，2026-09-20）

    private var serverLabel: String {
        UserDefaults.standard.string(forKey: "agentsAnywhere.serverURL") ?? "—"
    }

    /// 设备名行：取 URL host（如 moonveil.pipicore.cn）；解析失败回退原串。
    private var hostLabel: String {
        let raw = serverLabel
        guard raw != "—", let url = URL(string: raw), let host = url.host(percentEncoded: false), !host.isEmpty else {
            return raw == "—" ? "未配置服务器" : raw
        }
        return host
    }

    /// 数据源：RemoteSessionLoader（真实远端会话；归档三态在加载层完成）。
    private var sessions: [RemoteSessionItem] {
        loader.items
    }

    /// 归档筛选后的会话源（筛选已在加载层完成，此处仅保留接口形状）。
    private var sourceSessions: [RemoteSessionItem] {
        sessions
    }


    @State private var showsArchives = false
    @State private var showsPairSheet = false
    @State private var showsProjectEditor = false
    @State private var showsNewSession = false
    /// [NEW-SESSION-OPEN] 新建会话成功后的待打开 sessionId：官方是原地换 selection
    /// （ChatShellView:209 `openSession`），本仓新会话页是 fullScreenCover，必须等
    /// cover 关掉再 push——与 dismiss 同一事务里改导航路径有被吞的先例
    /// （[T-ios-stacknav-transition-attributegraph-race]）。
    /// [去嵌套 2026-09-30] 载体不变（时序纪律不变），落点从「本视图的
    /// showsChat/navigationDestination」换成容器栈 `ContainerNav.pushChat`。
    @State private var pendingChatSessionId: String?
    /// 官方 AgentsAnywhereApp.swift:23 的后台钩子（方案 B：App 根属本机线，
    /// 死隔离禁动 → 挂远端线页面根；services 未就绪时短路）。
    @Environment(\.scenePhase) private var scenePhase
    // 项目板块折叠（官方「项目 ▾」）
    @State private var projectsCollapsed = false
    /// 侧栏显示（AA 官方 ChatSidebarListMenu 同 key 持久化）：false = 按项目 / true = 全部会话。
    @AppStorage("aa.native.sidebar.session-list") private var showsAllSessions = false
    /// 归档筛选三态（AA V2DeviceSessionFilter 等价；仅按项目模式出现在菜单，同官方 filters()）。
    @State private var archiveFilter: RemoteSessionFilter = .active
    /// 「添加设备」表：终端卡在没有可用 connector 时弹出（pp 2026-09-27）。
    @State private var showsAddDevice = false
    /// [FIX-nested-sheet 2026-09-27] 添加设备页点登录后，由本页直接弹登录页
    /// （添加设备表已是 sheet，内嵌再弹会导致 OAuth 网页消失）。
    @State private var showsQRLogin = false
    @State private var showsManualLogin = false
    @State private var pendingAuthSheet: PendingAuthSheet?
    /// 远端会话数据层（共享单例：列表页 / 设备页 / 弹窗同源）。
    @StateObject private var loader = RemoteSessionLoader.shared
    /// P3-3：页面级错误 toast 存储（官方一槽一错语义，AAV2 冻结件）。
    @State private var toasts = ChatToastStore()

    // [去嵌套 2026-09-30] 导航容器 = 容器栈（RootModeTabsView 的
    // `NavigationStack(path: $containerNav.path)`）；本页是远端树的 root 内容，不再
    // 自带栈。深页（聊天 / 设备详情）一律 `ContainerNav.shared.pushChat(·)`，
    // 目的地视图（RemoteTreeChatDestination / RemoteDeviceDestination）在本文件末尾。
    // 顶栏：bottom-dock 批次起胶囊已迁壳层，本页顶栏只剩右上角控件。
    var body: some View {
        content
            // 页面画布与本机一致 = systemBackground（pp 2026-09-26「远端背景改成和
            // 本地背景颜色一样」；原方案 B 暖奶油画布退役），列表背景让位
            .background(RemotePalette.canvas.ignoresSafeArea())
            // [顶栏审计收口 2026-09-30 晚] displayMode 同属栏偏好写：按 mode 门控（原与
            // RemoteRootView:52 同链重复无条件写——审计漏网；两处均已门控，双写无害）。
            .treeTitleDisplayMode(tabRouter.mode == .remote)
            .toolbar {
                // [去嵌套 2026-09-30] chrome 门控：顶层栏全 App 只有一根，三棵树的
                // root 内容同时活着（保活切页）——本页的 ⋯ 不门控会串到别的树的栏上。
                if tabRouter.mode == .remote {
                    // 顶栏右上角：⋯ 菜单（配对新设备已收进菜单第一项，pp 2026-09-26）。
                    ToolbarItem(placement: .topBarTrailing) { topBarOptionsButton }
                }
            }
            // P3-3（2026-09-21）错误 toast 细化：官方 ChatErrorToasts + ChatToastStore
            // 分类逐字（网络已断开 / 登录状态需要验证 / 会话数据格式不兼容 / 操作未完成，
            // 标题由 AAV2 ChatToastStore 按 V2ClientFailure.kind 给出）。加载面源 "sync"
            // （带「刷新」按钮——官方重试语义：显式重读，不重放失败动作）；写操作面源
            // "operation"（乐观回滚后的诚实展示）。原「加载失败+行内重试」状态行保留
            // （pp 已验收骨架），toast 只在跨源并发时补分类信息，不互斥。
            .overlay(alignment: .top) {
                ChatErrorToasts(store: toasts, isRetrying: loader.phase == .loading,
                    onRetry: { _ in await loader.refresh(service: service, filter: archiveFilter) })
                    .padding(.top, 8)
            }
            .onChange(of: loader.loadFailure) { _, failure in
                toasts.update(source: "sync", failure: failure, canRetry: failure != nil)
            }
            .onChange(of: loader.writeFailure) { _, failure in
                toasts.update(source: "operation", failure: failure)
            }
            .sheet(isPresented: $showsPairSheet) {
                PairDeviceSheet(service: service, setup: agentSetup)
            }
            .sheet(isPresented: $showsProjectEditor) {
                // 项目编辑（AA 的 ProjectEditorSheet 视觉；数据面就绪前弹联动占位）
                RemoteProjectEditorSheet(service: service)
            }
            .fullScreenCover(isPresented: $showsNewSession) {
                // 新会话全屏页（AA 官方 NewSessionView 形态：欢迎区 glyph 揭示 +
                // 目标胶囊 + 工作目录行 + 底部 composer；2026-09-20 pp「aa的打开
                // 是这样的」）。创建成功 → 刷新列表 + 记下 sessionId 待 cover 关闭后
                // push 聊天页（[NEW-SESSION-OPEN]，对齐官方 ChatShellView:207-210）；
                // 与项目头 + 是两个不同入口。
                RemoteNewSessionView(service: service) { id in
                    pendingChatSessionId = id
                    loader.load(service: service, filter: archiveFilter, force: true)
                }
            }
            // [NEW-SESSION-OPEN] 官方 onCreated 的第二半（`openSession(session.id)`）：
            // cover 关闭事件到达后才 push，避免与 dismiss 抢同一次事务。
            // [去嵌套 2026-09-30] push 落点改容器栈（.remoteTreeChat）；「等 cover 关掉
            // 再动路径」的时序纪律原样保留——它守的是「dismiss 与导航路径写入同事务」
            // 这条先例（[T-ios-stacknav-transition-attributegraph-race]），与栈是哪一层无关。
            .onChange(of: showsNewSession) { _, presented in
                guard !presented, let id = pendingChatSessionId else { return }
                pendingChatSessionId = nil
                ContainerNav.shared.pushChat(.remoteTreeChat(sessionId: id))
            }
            .sheet(isPresented: $showsArchives) {
                RemoteArchivedSessionsSheet(service: service)
            }
            .onChange(of: scenePhase) { _, phase in
                // 官方 AppState.setAppInBackground：进后台 flushCache+suspend，
                // 回前台 resume。services 未就绪（未登录/未 bootstrap）时短路。
                guard let services = service.chat else { return }
                services.setAppInBackground(phase == .background)
            }
            // [SWIPE-ROOT-RESET 退役 2026-09-30] pp 2026-09-24「滑到本地页再滑回远端页
            // 是远端聊天页？」的原解法（本页 onChange(tabRouter.mode) 复位
            // showsChat / showsDeviceDetail）随树内层栈一起退役：深页不再挂在树自己的
            // 路径上，而是容器栈的 path——切树不碰 path，返回落点自然由容器栈管。
            // 留档：当初那条规则（push 态不劫持返回落点）仍然成立，只是它的宿主从
            // 「树内 NavigationStack」换成了「容器 NavigationStack」，规则无需重写。
            .onAppear {
                guard service.state == .ready else { return }
                loader.load(service: service, filter: archiveFilter)
                loader.loadArchived(service: service)
                // dashboard 兜底：RemoteService.syncState 只在跃迁到 .ready 时拉一次，
                // 那一发若因网络失败落地，connectors 仍是空 → 终端卡点进去没有设备身份。
                // repository.refresh 自带 isValid / !isLoading 守门，重复调用不会打串。
                Task { await service.chat?.dashboardRepository.refresh() }
            }
            // [去嵌套 2026-09-30] 常驻根通道注册（id = service.state：状态跃迁时补注册，
            // 幂等重复调用无害）。为何归到列表而不是聊天页目的地，见 registerRootChannels 注释。
            .task(id: service.state) {
                registerRootChannels()
            }
            .onChange(of: archiveFilter) { _, newFilter in
                loader.load(service: service, filter: newFilter, force: true)
            }
    }

    // MARK: - 常驻根通道（[去嵌套 2026-09-30] 从聊天页目的地搬来）

    /// 注册两条「根层」组合根回调。**为什么归列表而不是聊天页目的地**：
    /// 这两条通道的消费端本来就在本页——
    ///  ① `sessionReads.onChange`（官方 AppState:804，已读态变化投影回列表）闭包里
    ///     读的是本页的 `archiveFilter`；把它留在目的地 wrapper 里就得给共享单例
    ///     `RemoteSessionLoader` 开一个 `currentFilter` 读口（跨文件改动、且等于把
    ///     列表的私有状态提到数据层），或让 wrapper 反向依赖列表——两条都比
    ///     「常驻根自己持有」差。列表是容器栈之下的常驻 root（切树/推深页都不销毁
    ///     它），本来就是这条投影的宿主。
    ///  ② `onReturnToNewSession`（官方 onSelectPage(.newSession) 的等价物）要求
    ///     「关聊天页 + 开新会话页」。新会话页（`showsNewSession` / `pendingChatSessionId`）
    ///     是本页的状态，且本页是唯一持有 `archiveFilter` 的人（新建成功后要用它
    ///     强刷列表）；让 wrapper 自持一份 cover 会把这两处状态劈成两份。
    /// 副作用方向也一致：两条都只由「打开的聊天页」触发，列表侧无行为差异。
    /// 幂等：重复注册只是覆盖同一个闭包。
    private func registerRootChannels() {
        guard service.state == .ready, let services = service.chat else { return }
        // 官方 AppState:804 sessionReads.onChange：已读态变化投影回列表。
        // 本仓列表项由 RemoteSessionLoader 持有（无单条 upsert API）→
        // 已读变化触发一次列表刷新等价覆盖，refresh 内部自带节流。
        // 闭包捕获的是本视图结构体本身：@State/@StateObject 的存储盒是引用，
        // 之后读 archiveFilter 拿到的是**当前**值，不是注册那一刻的快照（原写法
        // 在目的地 .task 里隐式捕获 self，同款语义）。
        services.sessionReads.onChange = { _ in
            guard self.service.state == .ready else { return }
            self.loader.load(service: self.service, filter: self.archiveFilter)
        }
        // 「返回编辑」跳页通道（官方 onSelectPage(.newSession) 的本仓等价物）：
        // 聊天页 editCreation 暂存草稿后回调这里 → 出栈关聊天页 + 开新会话页。
        services.onReturnToNewSession = {
            self.returnToNewSession()
        }
    }

    /// 原 `{ showsChat = false; showsNewSession = true }` 的容器栈等价物：
    /// 出栈（回根列表）+ 开新会话全屏页，两次写入仍在同一 tick（与原写法同序同帧）。
    private func returnToNewSession() {
        // 只在栈顶确实是本页推的聊天页时出栈——陈旧注册（聊天页早已退栈、闭包仍挂在
        // 组合根上）不许误伤别的页。判据取 ChatRoute 本值，不依赖 path.count。
        if case .remoteTreeChat = ContainerNav.shared.path.last {
            ContainerNav.shared.pop()
        }
        showsNewSession = true
    }

    /// 设备详情页的容器栈入口（REMOTE-DEVICE-1 / P2-A）。
    /// connector 解析与终端卡单击同款（在线优先、回退第一台），解析不出时传空串
    /// ——目的地 `RemoteDeviceDestination` 按同款判据再解析一次，仍解析不出才落
    /// pending 空态（「正在同步设备信息…」+ 重试）。空串不是 bug 值，是「数据未到」
    /// 的显式载体（ChatRoute.remoteDevice 注释同款判据）。
    private func pushDeviceDetail() {
        let connectors = service.chat?.dashboardRepository.connectors ?? []
        let id = (connectors.first { $0.status == .online } ?? connectors.first)?.id ?? ""
        ContainerNav.shared.pushChat(.remoteDevice(connectorId: id))
    }

    private var content: some View {
        // 页面骨架（设备终端卡 + 项目头 + 底栏）永远在；加载 / 错误 / 空都只
        // 发生在会话区内部（pp 2026-09-20「这个页面没改？」：整页空态连设备卡
        // 都吞掉了，未连接/已连接必须同构）。
        sessionList
    }

    // MARK: - 列表（方案 B：深色终端卡 → 玻璃操作 → 项目头 → 暖卡堆）

    private var sessionList: some View {
        List {
            // —— 设备（终端窗卡 = 页面主语；pp 2026-09-26「组头弄这样」：历史消息式
            // 大标题组头）——
            Section {
                deviceSectionTitle
                deviceTerminalCard
                if pendingNotices > 0 {
                    pendingNoticesRow
                }
            }

            // —— 项目（✳ + 13pt tertiary 头；会话 = 暖卡堆）——
            // 未连接时不渲染：设备终端卡已提醒连接，会话区无数据可列。
            if service.state == .ready {
            Section {
                projectHeader
                if !projectsCollapsed {
                    switch loader.phase {
                    case .idle, .loading:
                        // 加载中也保留页面骨架：状态只在会话区内呈现。
                        sessionStatusRow {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text("正在加载远程会话…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .failed(let message):
                        sessionStatusRow {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("加载失败")
                                    .font(.system(size: 15, weight: .medium))
                                Text(message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Button("重试") {
                                    loader.load(service: service, filter: archiveFilter, force: true)
                                }
                                .font(.system(size: 14, weight: .medium))
                            }
                        }
                    case .loaded:
                        if showsAllSessions {
                            // 全部会话（AA 官方 flat 模式）：平铺卡堆。
                            ForEach(projectItems) { item in
                                sessionRow(item)
                            }
                        } else {
                            // 按项目（AA 官方默认）：项目小标题 + 组内卡堆；未分组殿后。
                            ForEach(groupedItems) { group in
                                projectGroupLabel(group.name)
                                ForEach(group.items) { item in
                                    sessionRow(item)
                                }
                            }
                        }
                        // P3-1（2026-09-21）：卡堆滚到页尾 → 按服务端游标续拉下一页。
                        // List 懒渲染使 onAppear 只在尾行可见时触发；isLoadingMore
                        // 短路重复请求。「正在加载…」为本仓风格文案（官方 iOS 端无
                        // 分页消费方，无官方对照串——差异字据见自审报告）。
                        if loader.hasMorePages {
                            sessionStatusRow {
                                HStack(spacing: 10) {
                                    ProgressView().controlSize(.small)
                                    Text("正在加载…")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onAppear {
                                Task { await loader.loadMore(service: service) }
                            }
                        }
                        if projectItems.isEmpty {
                            // 空态：有项目无会话 vs 没项目分开，保持诚实。
                            Text(archiveFilter == .archived
                                 ? "还没有归档的会话。"
                                 : (loader.projectNames.isEmpty ? "还没有项目。" : "还没有会话。点底部 tab 栏的新建按钮开始。"))
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            }   // if service.state == .ready（会话 Section）
        }
        .listStyle(.plain)
        // 方案 B：列表滚动背景让位给页面画布（画布挂在 body 级 background 上）
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await refresh() }
        // [去嵌套 2026-09-30] 原此处两条 `.navigationDestination(isPresented:)`
        // （设备详情 / 会话聊天）连同它们的 remoteAtRoot 栅栏整体退役，改由容器栈的
        // `navigationDestination(for: ChatRoute.self)` 统一承接（目的地视图 =
        // 本文件末尾 RemoteDeviceDestination / RemoteTreeChatDestination）。
        // 留档：当年「页切栅栏 + 顶栏齿轮共用一个 push 开关」解决的是
        // 「目的地渲染不出内容时 onAppear 不跑 → 标志卡死 → 齿轮压住返回箭头」
        // （pp 2026-09-21 白屏那次）；根治点已换成结构性的——顶栏只有一根且由容器栏
        // 独占，标志本身（remoteAtRoot）不再存在，没有可卡死的东西。
        // PAIRING-FULL 收尾（P2-B）：官方 ChatShellView:39-45/53-59 形状——配对就绪的
        // 设备弹 AgentSetupSheet（原「跳设备详情页」过渡移除）；关闭 = finish + 刷 dashboard。
        .sheet(item: agentSetupBinding) { facade in
            if let services = service.chat,
               let device = services.dashboardRepository.connectors.first(where: { $0.id == facade.id }) {
                AgentSetupSheet(connector: device, model: services.agents(on: device.id)) {
                    agentSetup.finish(device.id)
                    Task { await services.dashboardRepository.refresh() }
                    loader.load(service: service, filter: archiveFilter, force: true)
                }
            }
        }
        // [TG-TABBAR 2026-09-30] 此段原为 [TAB-RESTORE 2026-09-28] 的「系统 tab
        // 栏恢复原生渲染」说明——系统栏已整体退役；远端列表 = 远端树 root 页，
        // 自绘栏（ModeTabBar）在场且自带键盘豁免（不随键盘上浮，见 ModeTabBar）。
    }

    /// 官方 agentSetupBinding（ChatShellView:53-59；本仓 coordinator 为 app 层
    /// RemoteConnector 面，V2Connector 在 sheet 内容里按 id 映射）。
    private var agentSetupBinding: Binding<RemoteConnector?> {
        Binding(get: { agentSetup.presentedConnector }, set: { value in
            if value == nil, let connector = agentSetup.presentedConnector {
                agentSetup.finish(connector.id)
            }
        })
    }

    /// 终端卡对应的设备：官方侧栏按 connector 逐台列卡；本仓单终端卡定稿 →
    /// 优先在线、否则第一台（pp 已验收的单设备视角）。
    private var deviceConnector: V2Connector? {
        let connectors = service.chat?.dashboardRepository.connectors ?? []
        return connectors.first { $0.status == .online } ?? connectors.first
    }

    // [去嵌套 2026-09-30] 原 `deviceDetailPending`（设备身份未到位时的目的地空态，
    // 含重试按钮）随目的地迁到本文件末尾 RemoteDeviceDestination —— 它的唯一消费方
    // 就是那个 destination，留在列表里就成了死成员。文案与形状逐字保留。

    /// 会话区内的状态行（加载 / 错误）——保持页面骨架完整，不替换整页
    /// （pp 2026-09-20「这个页面没改？」：空态也不许把设备卡吞掉）。
    private func sessionStatusRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    // MARK: - 会话卡（方案 B：暖卡堆——白圆头像 + 标题/摘要 + 时间；状态语义化：
    // 等待批准=琥珀胶囊 / 运行中=teal 转圈+mono running / 未读=卡角珊瑚点；
    // pp 2026-09-20 定稿。字级走 App Base 缩放（scaledApp）。

    private func sessionRow(_ item: RemoteSessionItem) -> some View {
        Button {
            openSession(item)
        } label: {
            HStack(spacing: 11) {
                sessionAvatar(for: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: FontSettings.shared.scaledApp(15.5), weight: .semibold))
                        .foregroundStyle(RemotePalette.ink)
                        .lineLimit(1)
                    Text(item.previewText)
                        .font(.system(size: FontSettings.shared.scaledApp(13)))
                        .foregroundStyle(RemotePalette.body)
                        .lineLimit(1)
                }
                Spacer(minLength: 1)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.updatedAtText)
                        .font(.system(size: FontSettings.shared.scaledApp(12)))
                        .foregroundStyle(RemotePalette.timeFaint)
                    if item.indicator == .waitingApproval {
                        Text("待批准")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(RemotePalette.amber, in: Capsule())
                    } else if item.indicator == .running {
                        HStack(spacing: 4) {
                            RemoteSpinningRing(color: RemotePalette.runningTeal)
                                .frame(width: 9, height: 9)
                            Text("running")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(RemotePalette.runningTeal)
                        }
                    } else if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(RemotePalette.faint)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(RemotePalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if item.isUnread {
                    Circle()
                        .fill(RemotePalette.coral)
                        .frame(width: 10, height: 10)
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4.5, leading: 16, bottom: 4.5, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            RemoteSessionContextMenu(item: item) { action in
                handleMenuAction(action, for: item)
            }
        }
        // [SESSION-SWIPE-TO-LONGPRESS 2026-09-24] 原 .swipeActions（左：置顶；右：
        // 归档/删除）已整体迁入上方 contextMenu——行不再消费横滑，卡片区横滑让给
        // 页切手势（与 RootModeTabsView 撤销 RemoteRowsFence 同批，pp 原话见文件头）。
    }

    /// 头像：白圆底 + 裸 lucide；运行中 = teal 外圈转圈（方案 B 语义位）。
    @ViewBuilder
    private func sessionAvatar(for item: RemoteSessionItem) -> some View {
        RemoteSessionIcon(size: 20, color: RemotePalette.avatarInk)
            .frame(width: 40, height: 40)
            .background(RemotePalette.avatarWash, in: Circle())
            .overlay {
                if item.indicator == .running {
                    RemoteSpinningRing(color: RemotePalette.runningTeal)
                        .frame(width: 44, height: 44)
                }
            }
    }

    // MARK: - 设备（方案 B / REMOTE-REDESIGN-4：深色终端窗卡，pp 2026-09-20 定稿）

    /// 设备组头：大标题「远程Agent」（pp 2026-09-26「组头弄这样」：历史消息式 largeTitle
    /// 组头，34pt 粗体，左 16pt）。
    private var deviceSectionTitle: some View {
        Text("远程Agent")
            .font(.largeTitle)
            .bold()
            .foregroundStyle(RemotePalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// 终端窗卡 v2（pp 2026-09-27 定稿）：暖炭/暖纸深浅反色——浅色模式用深卡、
    /// 深色模式用浅卡；全 mono 排印；状态为 sans 半粗小字距；❯ + 呼吸块光标。
    /// 三态：未配置（空终端）/ 已连接（设备名+地址+会话数）/ 离线（降灰+重连提示）。
    private var deviceTerminalCard: some View {
        // 深浅反色：系统浅色→深卡，系统深色→浅卡
        let darkCard = colorScheme == .light
        let connected = service.state == .ready
        let configured = serverLabel != "—"
        // 配色
        let bgTop = darkCard ? Color(red: 38/255, green: 35/255, blue: 31/255)
                             : Color(red: 253/255, green: 252/255, blue: 249/255)
        let bgBottom = darkCard ? Color(red: 29/255, green: 27/255, blue: 23/255)
                                : Color(red: 245/255, green: 242/255, blue: 236/255)
        let ink = darkCard ? Color(red: 245/255, green: 241/255, blue: 232/255)
                           : Color(red: 28/255, green: 28/255, blue: 30/255)
        let subInk = darkCard ? Color(red: 163/255, green: 158/255, blue: 147/255)
                              : Color(red: 120/255, green: 113/255, blue: 108/255)
        let faint = darkCard ? Color(red: 110/255, green: 106/255, blue: 99/255)
                             : Color(red: 168/255, green: 162/255, blue: 158/255)
        let accent = darkCard ? Color(red: 125/255, green: 211/255, blue: 192/255)
                              : Color(red: 15/255, green: 118/255, blue: 110/255)
        let hairline = darkCard ? Color.white.opacity(0.08) : Color(red: 60/255, green: 52/255, blue: 40/255).opacity(0.09)
        // 状态
        let (statusText, statusColor): (String, Color) = {
            if !configured { return ("未配置", faint) }
            if connected { return ("已连接", accent) }
            return ("未连接", faint)
        }()
        return VStack(alignment: .leading, spacing: 0) {
            // 顶行：三色点 + 状态
            HStack(spacing: 7) {
                Circle().fill(Color(red: 1, green: 95/255, blue: 87/255)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 1, green: 188/255, blue: 46/255)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 40/255, green: 200/255, blue: 64/255)).frame(width: 10, height: 10)
                Spacer(minLength: 0)
                // [PP-2026-09-27] 状态指示：圆点灯 → 云图标（aa-Cloud 圆润版，template 渲染随状态变色）
                Image("aa-Cloud")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .padding(.bottom, 22)
            if !configured {
                // 未配置：空终端，只有 ❯ 和呼吸光标
                HStack(spacing: 10) {
                    Text("❯")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(faint.opacity(0.6))
                    blinkCursor(color: faint.opacity(0.6))
                }
                .padding(.bottom, 14)
                Text("尚未配置服务器，轻点开始配置 →")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(faint)
            } else {
                // 设备名行：❯ + 名 + 呼吸光标
                HStack(spacing: 10) {
                    Text("❯")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(connected ? accent : faint.opacity(0.6))
                    Text(deviceConnector?.name ?? hostLabel)
                        .font(.system(size: 19, design: .monospaced))
                        .foregroundStyle(connected ? ink : faint)
                        .lineLimit(1)
                    if connected { blinkCursor(color: accent) }
                }
                .padding(.bottom, 10)
                // 地址行
                HStack(spacing: 6) {
                    Text(hostLabel)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(connected ? subInk : faint)
                        .lineLimit(1)
                    if connected {
                        Text("· \(sessions.count) sessions")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(faint)
                    }
                }
                .padding(.bottom, connected ? 18 : 14)
                if connected {
                    Rectangle().fill(hairline).frame(height: 1)
                        .padding(.bottom, 14)
                    // 元信息：只有真实数据（会话数已在地址行，这里不再堆假数据）
                    Text("\(sessions.count) active sessions")
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(faint)
                } else {
                    Text("tap to reconnect →")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(faint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(darkCard ? 0.09 : 0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(darkCard ? 0.28 : 0.14), radius: 20, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // REMOTE-DEVICE-1：点按整卡进入设备详情页（pp 2026-09-21 改：原长按入口
        // 2026-09-20 版改单击——「现在是长按卡片才能进去 改为点一次就进入」）。
        // [PP-2026-09-27] 点按直进设备页，不再按配置状态分流弹登录（恢复 5863f33；
        // d20295d 的未配置分流未经 pp 确认，已 revert）。未配置时目的地显示
        // deviceDetailPending（「正在同步设备信息…」+ 重试，不白屏）——[去嵌套
        // 2026-09-30] 该空态随目的地迁到 RemoteDeviceDestination。
        // pp 2026-09-27：有 connector 直接进设备页；没有则弹「添加设备」表
        // （扫码登录/手动登录），登录成功后再进设备页。
        .onTapGesture {
            // [去嵌套 2026-09-30] 进设备详情 = 推容器栈（.remoteDevice）；没有设备
            // 身份时仍旧弹「添加设备」表（pp 2026-09-27 的分流，不动）。
            if deviceConnector != nil {
                pushDeviceDetail()
            } else {
                showsAddDevice = true
            }
        }
        .sheet(isPresented: $showsAddDevice, onDismiss: {
            // [FIX-auth-sheet-seq 2026-09-27 pp「连接aa的云刚弹出网站就退回来」]
            // 等 AddDeviceSheet 退场动画走完（onDismiss）再弹登录表。此前
            // dismiss() 与 presents 同一 tick 叠在三连 .sheet 链上，呈现宿主在
            // 退场期抖动，OAuth 网页（ASWebAuthenticationSession）锚上去即被
            // 取消——症状就是「刚弹出网站就退回来」。同类教训见 AddDeviceSheet
            // 注释（本表已是 sheet，内嵌再弹 sheet 会导致 OAuth 网页弹层消失）。
            let pending = pendingAuthSheet
            pendingAuthSheet = nil
            switch pending {
            case .qr: showsQRLogin = true
            case .manual: showsManualLogin = true
            case nil: break
            }
        }) {
            AddDeviceSheet(
                service: service,
                onLoginSucceeded: {
                    // 登录成功：dashboard 拉到 connector 后进设备页
                    pushDeviceDetail()
                },
                onQRLoginRequested: {
                    pendingAuthSheet = .qr
                },
                onManualLoginRequested: {
                    pendingAuthSheet = .manual
                }
            )
        }
        .sheet(isPresented: $showsQRLogin) {
            QRCodeLoginView(service: service) {
                showsQRLogin = false
                pushDeviceDetail()
            }
        }
        .sheet(isPresented: $showsManualLogin) {
            ManualLoginView(service: service) {
                showsManualLogin = false
                pushDeviceDetail()
            }
        }
        .accessibilityHint(Text(deviceConnector != nil ? "查看设备详情" : "添加设备"))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// 终端卡呼吸块光标（TimelineView 驱动，无需 @State）。
    private func blinkCursor(color: Color) -> some View {
        TimelineView(.animation(minimumInterval: 1.1)) { timeline in
            let visible = Int(timeline.date.timeIntervalSinceReferenceDate / 1.1) % 2 == 0
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 17)
                .opacity(visible ? 0.85 : 0)
        }
    }


    /// 待处理提醒行（方案 B：琥珀胶囊）。
    private var pendingNoticesRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RemotePalette.amber)
                .frame(width: 28, height: 28)
                .background(RemotePalette.amber.opacity(0.16), in: Circle())
            Text("需要你处理")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RemotePalette.ink)
            Spacer(minLength: 0)
            Text("\(pendingNotices)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RemotePalette.amber, in: Capsule())
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - 项目头（方案 B：✳ + 13pt tertiary 灰——对齐本机时间字级，pp 定稿；
    // 无计数；整行点击折叠（chevron 图标按定稿去掉）；＋ 新建圆钮）

    private var projectHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { projectsCollapsed.toggle() }
            } label: {
                HStack(spacing: 7) {
                    RemoteSpikeMark()
                    Text("项目")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.3)
                }
                .foregroundStyle(RemotePalette.faint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(projectsCollapsed ? "项目（已折叠）" : "项目（已展开）"))
            Spacer(minLength: 0)
            Button {
                showsProjectEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RemotePalette.ink)
                    .frame(width: 28, height: 28)
                    .background(RemotePalette.card, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 40)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// 按项目模式的项目小标题（AA「未分组会话」同款下标题字级）。
    private func projectGroupLabel(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(RemotePalette.faint)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    // MARK: - 操作

    private func openSession(_ item: RemoteSessionItem) {
        // 打开即标记已读（AA 官方语义；写失败不阻断查看）
        loader.markRead([item.id], service: service)
        // P1-CHAT：进入官方聊天页。[去嵌套 2026-09-30] push 落点从「本视图的
        // showsChat + navigationDestination」换成容器栈（数据面仍走组合根
        // sessionRepository，目的地 RemoteTreeChatDestination）。
        ContainerNav.shared.pushChat(.remoteTreeChat(sessionId: item.id))
    }

    private func togglePin(_ item: RemoteSessionItem) {
        loader.togglePin(item.id, service: service)
    }

    private func archive(_ item: RemoteSessionItem) {
        loader.archive([item.id], service: service)
    }

    // 删除：服务端会话只有归档/取消归档/标记已读，无删除端点（Staged，
    // 见 PATCHES 台账）；长按菜单入口已就位（2026-09-24 从行 swipeActions 迁入），
    // 接端点批接线前不假造成功态。
    private func delete(_ item: RemoteSessionItem) {
    }

    private func handleMenuAction(_ action: RemoteSessionMenuAction, for item: RemoteSessionItem) {
        switch action {
        case .open: openSession(item)
        case .rename:
            // 重命名 UI（AA RenameSheet）随写操作弹窗批接入；暂不假造。
            break
        case .togglePin: togglePin(item)
        case .archive: archive(item)
        case .delete:
            // [SESSION-SWIPE-TO-LONGPRESS] 删除从行 swipeActions 迁入；服务端无删除
            // 端点（Staged，与 rename 同款暂不假造成功态），接端点批接线。
            delete(item)
        case .copyId: UIPasteboard.general.string = item.id
        }
    }

    private func refresh() async {
        // 官方 ChatShellView:211：下拉刷新先 `await appState.refreshDashboard()`
        // 再回读 connectors —— 本仓原实现只刷会话 loader，connectors 永远停在首发
        // 那一发（或其失败后的空态），设备详情页身份源因此修不回来。
        await service.chat?.dashboardRepository.refresh()
        await loader.refresh(service: service, filter: archiveFilter)
    }

    // MARK: - 派生

    /// 项目板块的会话（置顶项排前）。
    /// 完整项目抽屉（文件夹行/逐项展开/按项目新建）随数据面批对齐官方。
    private var projectItems: [RemoteSessionItem] {
        sourceSessions.sorted { ($0.isPinned ? 0 : 1) < ($1.isPinned ? 0 : 1) }
    }

    /// 按项目分组的渲染单元（AA「项目」模式：项目小标题 + 组内会话；未分组殿后）。
    private struct ProjectGroup: Identifiable {
        let id: String
        let name: String
        let items: [RemoteSessionItem]
    }

    private var groupedItems: [ProjectGroup] {
        var buckets: [String: [RemoteSessionItem]] = [:]
        for item in projectItems {
            buckets[item.projectId ?? "", default: []].append(item)
        }
        var out: [ProjectGroup] = buckets
            .filter { !$0.key.isEmpty }
            .map { ProjectGroup(id: $0.key, name: projectDisplayName(for: $0.key), items: $0.value) }
            .sorted { $0.name < $1.name }
        if let unassigned = buckets[""] {
            out.append(ProjectGroup(id: "__unassigned", name: "未分组会话", items: unassigned))
        }
        return out
    }

    /// 项目名：远端项目列表的真实结果（缺失时回退 projectId 原值）。
    private func projectDisplayName(for projectId: String) -> String {
        loader.projectNames[projectId] ?? projectId
    }

    // 列表选项（归档/断开）= 页面级操作，挂顶栏右上角 …（本机同位；
    // REMOTE-REDESIGN-3 从项目头 … 迁回，项目头只留 ▾ 折叠与 ＋ 新建）。
    // [去嵌套 2026-09-30] 导航容器改由容器栈提供（顶栏胶囊已迁壳层；⋯ 的 toolbar
    // 件已按 tabRouter.mode == .remote 门控，见 body）。
    @ViewBuilder
    private var listOptionsMenuContent: some View {
        // pp 2026-09-26：＋ 配对新设备收进 ⋯ 菜单第一项，右上角只剩 🔍 + ⋯。
        Button("配对新设备", systemImage: "plus") { showsPairSheet = true }
        Divider()
        // AA 官方「侧栏显示」：按项目 / 全部会话（同 key 持久化，默认按项目）。
        Picker("侧栏显示", selection: $showsAllSessions) {
            Text("按项目").tag(false)
            Text("全部会话").tag(true)
        }
        // AA 官方：归档筛选只在按项目模式出现（filters() 注入点语义，本机同位不发明）。
        if !showsAllSessions {
            Picker("会话", selection: $archiveFilter) {
                Text("活跃").tag(RemoteSessionFilter.active)
                Text("已归档").tag(RemoteSessionFilter.archived)
                Text("全部").tag(RemoteSessionFilter.all)
            }
        }
        Divider()
        Button("归档会话", systemImage: "archivebox") { showsArchives = true }
        Divider()
        // 断开连接入口从 RemoteRootView 的状态卡迁移至此（接线时不丢）
        Button("断开连接", role: .destructive, action: onDisconnect)
    }

    /// 顶栏右上角 …——**原生工具栏样式**（pp 2026-09-20「没用苹果原生？」）：
    /// 裸 ellipsis 字形，不套自定义圆底；与本机 tab 同位置惯例一致
    /// （ContentView：TerminalCircle 24×24 / alarm 15pt 均为裸图标）。
    /// 系统提供标准热区与按压反馈；玻璃圆底版（☰ 同配方）已按 pp 意见移除。
    private var topBarOptionsButton: some View {
        Menu {
            listOptionsMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary)
        }
    }
}

// MARK: - 归档筛选三态（AA V2DeviceSessionFilter 的等价实现：active/archived/all）

enum RemoteSessionFilter: String, CaseIterable, Identifiable {
    case active, archived, all
    var id: String { rawValue }
}

// MARK: - 数据模型（远端会话条目；由 RemoteSessionLoader 从真实会话映射）

struct RemoteSessionItem: Identifiable, Equatable {
    let id: String
    var title: String
    var projectId: String?
    /// 该会话所属连接器（设备页按设备筛选用）。
    var connectorId: String = ""
    var isPinned: Bool = false
    /// 尾部指示器（等待批准 / running / 无）——与卡角未读点正交。
    var indicator: RemoteSessionIndicator = .none
    /// 卡角未读点（与尾部指示器正交，可同时出现）。
    var isUnread: Bool = false
    var updatedAtText: String = ""
    /// 摘要行：工作目录末段 / 运行时显示名（不假造消息内容）。
    var previewText: String = ""
    /// 排序键（时间戳原始值；不用于显示）。
    var sortDate: Date = .distantPast
}

enum RemoteSessionMenuAction {
    case open, rename, togglePin, archive, delete, copyId
}

// MARK: - [去嵌套 2026-09-30] 容器栈目的地（远端树深页）
//
// 原先这两页是 RemoteSessionListView 里的两条 `.navigationDestination(isPresented:)`
// + 本视图的 @State；树内层 NavigationStack 拆掉后没有栈可 push，改由 RootModeTabsView
// 的容器栈 `navigationDestination(for: ChatRoute.self)` 统一承接（.remoteTreeChat /
// .remoteDevice）。视图本体放在本文件末尾而不是新建文件：数据面全在 RemoteKit 组合根，
// 与 RemoteDeviceDetailView / SessionChatView 是同一族消费方，同文件便于对照搬运。
// ⚠️ 身份：`.id(route)` 由调用侧（RootModeTabsView）钉——navigationDestination 的视图
// 按**栈深度**识别、不按 path 值，同深度换路由会复用旧视图的 @StateObject。

/// 远端树会话聊天页目的地（原 `chatDestination`，逐字搬运 + 拆栈适配）。
struct RemoteTreeChatDestination: View {
    @ObservedObject var service: RemoteService
    let sessionId: String

    /// 官方 ChatShellView:198 `appState.connectors.first { $0.id == connectorID }?.name`
    /// 的本仓等价物：无常驻 connectors 镜像 → 就绪时拉一次，供聊天页副标题与文件页
    /// 标题（[去嵌套 2026-09-30] 从列表迁来——原镜像只为这一个消费方存在）。
    @State private var connectorNames: [String: String] = [:]

    /// [去嵌套 2026-09-30 · R4 审查修订] 全局 tint 数据源（同 RemoteRootView 的
    /// 官方 RootView.swift:52 语义——主文本色，把 Menu/Label/裸 Button 染黑/白）。
    @Environment(\.colorScheme) private var colorScheme

    /// P1-CHAT：聊天页目的地。`service.chat`（组合根）未就绪（未登录/未 bootstrap）
    /// 时列表本身不可点（state != .ready），此处仍做真实判空而非强解包。
    var body: some View {
        Group {
            if let services = service.chat {
                let session = services.sessionRepository.session(id: sessionId)
                // [R2 审查修订 2026-09-30] 设备名优先读 dashboardRepository 常驻镜像
                // （列表侧 onAppear/refresh 已维护、零网络）——旧实现名字在列表 onAppear
                // 已拉好；只靠下方 wrapper 自己的一次性拉取会让副标题首帧先闪 connectorId
                // 再跳设备名。镜像查不到才回退 connectorNames（一次性拉取的兜底）。
                let cid = session.metadata?.connectorId ?? ""
                let dashName = services.dashboardRepository.connectors.first { $0.id == cid }?.name
                SessionChatView(session: session, services: services,
                                deviceName: dashName ?? connectorNames[cid],
                                // [去嵌套 2026-09-30] onMenu 语义 = 「关掉本页」。
                                // 消费侧实测：SessionChatView 把它交给 ChatPageToolbar 的
                                // `showsSidebarButton: false` 分支，而该 toolbar 只在
                                // `showsSidebarButton == true` 时才渲染 ≡ → **本调用点上
                                // onMenu 根本不会被触发**（pp 2026-09-22 装机后刻意关掉
                                // 的：系统已有返回箭头，≡ 与之重复）。这里按「返回/出栈
                                // 类」实现成 `ContainerNav.shared.pop()`，等价且未来
                                // 若恢复 ≡ 键也是对的。
                                onMenu: { ContainerNav.shared.pop() })
                    // [TG-TABBAR 2026-09-30] 原 TABBAR-NATIVE 藏栏退役：系统栏不存在
                    // （自绘栏是远端 root 页内件，本页 push 即整页盖住含栏的 root 页）。
                    // （原注释：远端聊天页同为被 push 的目的地，声明式藏 tab。）
                    .task(id: sessionId) {
                        // 官方 AppState.makeV2Services → services.restoreCache(selection:)：
                        // 进页面先把本地缓存铺进仓库（离线可见），网络回来再覆盖。
                        await services.restoreCache(selection: .session(sessionId))
                        // 官方 AppState:372 sessionReads.setVisibleSession：
                        // local: 前缀的本地草稿不计已读，同官方判据。
                        services.sessionReads.setVisibleSession(
                            sessionId.hasPrefix("local:") ? nil : sessionId)
                        // [去嵌套 2026-09-30] 原链条里还有两条**根层**回调
                        // （sessionReads.onChange 投影回列表 / onReturnToNewSession 回新
                        // 会话页），二者都搬去了常驻根 RemoteSessionListView
                        // （registerRootChannels）——原因与等价性论证见那里的注释。
                    }
            } else {
                // [去嵌套 2026-09-30] 判空兜底注释沿用原 chatDestination：组合根未就绪
                // 时透明铺底。⚠️ 纯透明在系统底色上就是白屏（设备详情那边有
                // deviceDetailPending 兜底，聊天页这侧没有对应件）——保持原行为，不在本
                // 批造新的空态件；可点不进本页的状态判据在上游（列表 state != .ready
                // 不可点），这里只是防御。
                Color.clear
            }
        }
        // 设备名镜像与页面副作用链并行拉：官方形状是一次性拉取，失败静默（副标题
        // 按官方回退链使用 connectorId，见 SessionChatView 的 subtitle 组装）。
        // [R2 审查修订 2026-09-30] 现在只是 dashboard 常驻镜像（见 body 内解析）的
        // 兜底路径——首选解析不依赖本拉取，保留为镜像缺 id 时的补拉。
        .task {
            await refreshConnectorNames()
        }
        // [去嵌套 2026-09-30 · R4 审查修订] 补回全局 tint：原 `.tint(AppTheme.primaryText)`
        // 挂在 RemoteRootView 树内栈的**外侧**，覆盖栈内 push 的聊天页/设备详情页；
        // 拆壳后本页从容器栈 push、环境继承自容器层（无 tint）——不补则本页 toolbar/
        // Menu/裸 Button 回落系统 accent 蓝（pp 2026-09-21 截图定案过"系统蓝"回归）。
        // 挂在 destination 子树上，其 toolbar items（渲染于容器栏）随之继承。
        .tint(AppTheme.primaryText(colorScheme))
    }

    /// 设备名镜像（一次性；配对/改名后的刷新随设备页批走）。失败静默：
    /// 聊天页副标题按官方回退链使用 connectorId。
    private func refreshConnectorNames() async {
        guard let connectors = try? await service.listConnectors() else { return }
        connectorNames = Dictionary(connectors.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

/// 远端树设备详情页目的地（原列表 `.navigationDestination(isPresented: $showsDeviceDetail)`，
/// 逐字搬运 + 拆栈适配）。
struct RemoteDeviceDestination: View {
    @ObservedObject var service: RemoteService
    /// 目标 connector id。空串 = 登录/配对刚成功、数据未到（列表侧 pushDeviceDetail
    /// 的兜底载体），此时按「在线优先 → 第一台」再解析一次，仍解析不出落 pending 空态。
    let connectorId: String

    /// [去嵌套 2026-09-30 · R4 审查修订] 全局 tint 数据源（同 RemoteTreeChatDestination）。
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            // [去嵌套 2026-09-30 · R4 审查修订] 补回全局 tint：同 RemoteTreeChatDestination
            // （原挂 RemoteRootView 树内栈外侧，覆盖本页「全部项目/新设备/创建项目」等
            // 裸 Button/Menu；拆壳后不补即回落系统 accent 蓝——pp 2026-09-21 截图判据）。
            .tint(AppTheme.primaryText(colorScheme))
    }

    @ViewBuilder
    private var content: some View {
        // [去嵌套 2026-09-30] 解析判据同列表的 `deviceConnector`（在线优先、回退
        // 第一台），多出「精确 id」优先档——容器栈的 route 带 id，能对上就对上。
        if let services = service.chat {
            let connectors = services.dashboardRepository.connectors
            if let connector = connectors.first(where: { $0.id == connectorId })
                ?? connectors.first(where: { $0.status == .online })
                ?? connectors.first {
                // [TAB-RESTORE pp 拍板 ffd2d84] 终端卡进去的设备详情 = push 二级页，
                // 无底部 tab。[TG-TABBAR 2026-09-30] 原「系统栏恢复原生渲染后由目的地
                // 显式声明（hidesBottomBarWhenPushed 等价）」已退役——系统栏不存在，
                // 本页从容器栈 push 即整页盖住含栏的 root 页。
                // [BATCH-A/A3-同族][SEAM-LOSSLESS] 设备页四条归档写路径无损回传真实
                // 变更集（[RemoteSessionMeta]）：服务端与 dashboard 仓库在写路径内部
                // 已推进（setSessionsArchived/archiveProject/updateSessions 均回写
                // 仓库），这里只把变更集增量并入 loader 镜像——不再整表 force 重拉，
                // 因为 force 重拉把 phase 打到 .loading，返回列表页时闪一帧
                // 「正在加载远程会话…」骨架。「无损」的上游字据（archive-all 的
                // sessions 恒等于全量受影响集）见 V2RemoteChatServices.archiveProject
                // 注释；在途 load 与增量合并的竞态由 RemoteSessionLoader.changeLog
                // 的有界重放收敛（快照落地后把晚于请求起点、且仍在日志窗口内的
                // 变更集重新并入；超出 changeLogCap 被丢的条目不重放，其行由下
                // 一次全量拉取纠正）。
                RemoteDeviceDetailView(service: service, connector: connector,
                    onDeleted: { id in
                        // 官方 636-639 removeConnector + 出栈。顺序与原实现逐字相同
                        // （先写仓库再关页）；容器栈下「关页」= pop。闪帧风险评估：
                        // pop 只改 path，仓库已先行落地，目的地同帧退栈，无二次读。
                        services.removeConnector(connectorId: id)
                        ContainerNav.shared.pop()
                    },
                    onSessionsChanged: { changed in
                        RemoteSessionLoader.shared.applyRemoteChange(changed)
                    })
                    .id(connector.id)
            } else {
                deviceDetailPending
            }
        } else {
            deviceDetailPending
        }
    }

    /// 设备身份还没到位时的目的地可见态（替掉原 `Color.clear`——纯透明铺在
    /// 系统白底上就是 pp 看到的白屏，且没有任何可操作出口）。
    /// 空态诚实：直接读仓库的 error / isLoading，失败时显示失败原因并放开重试，
    /// 而不是无限转圈静默（本仓远端线空态惯例；读法同 RemoteDeviceDetailView 的
    /// `dashboard?.error`）。dashboard 未落地 / 首发放失败 / 失败后等待重试都走这里。
    private var deviceDetailPending: some View {
        let error = service.chat?.dashboardRepository.error
        let loading = service.chat?.dashboardRepository.isLoading == true
        return VStack(spacing: 14) {
            if loading { ProgressView() }
            Text(error ?? "正在同步设备信息…")
                .font(.system(size: 13))
                .foregroundStyle(RemotePalette.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("重试") {
                Task { await service.chat?.dashboardRepository.refresh() }
            }
            .font(.system(size: 14, weight: .medium))
            .disabled(loading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RemotePalette.canvas.ignoresSafeArea())
        // [DOCK-ON-PAGE 2026-09-28] 设备详情兜底页是二级页：不挂导航 dock。
    }
}

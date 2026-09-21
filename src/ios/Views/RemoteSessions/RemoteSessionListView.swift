// RemoteSessionListView.swift — 远端会话列表（R0，batch 8）
//
// 形态（pp 2026-09-20 定稿，REMOTE-REDESIGN-4 = 方案 B「Claude 设计语言」落地）：
// 暖奶油画布 → 深色终端窗卡（设备）→ 液态玻璃操作 → 13pt tertiary 项目头 → 暖卡堆
// 会话（琥珀待批准 / teal running / 珊瑚未读点）；冻结三件（顶栏/新会话/搜索栏）原样；
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
//   • 长按菜单：Open / Rename / Pin·Unpin / Archive·Restore / Copy Session ID
//   • 左滑动作：置顶 / 归档 / 删除
//   • 归档页（ArchivedSessionsSheet）+ 下拉刷新 + 空态诚实
//
// Staged with deadlines（完整性铁律 — 明示不藏）：
//   • DATA-1 已落地（2026-09-20）：列表读（listSessions 三态 + 项目名真实化）
//     与写（置顶 / 归档 / 取消归档 / 标记已读；乐观更新 + 失败回滚）全链路接通，
//     未读 / 运行 / 待批准指示器全部来自真实会话状态，预览假数据已全删。
//   • 删除会话：服务端无删除端点（仅归档/取消归档/标记已读）——Staged，不假造成功态。
//   • 重命名 UI（AA RenameSheet）：写端点 patchSessionMeta(title:) 已就绪，随弹窗批接入。
//   • 会话页聊天接线（timeline/snapshot）+ 分页加载（nextCursor）→ 下一批。

import SwiftUI

struct RemoteSessionListView: View {
    @ObservedObject var service: RemoteService
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

    /// 搜索过滤：标题/摘要本地过滤（本机搜索走 ChatStore 后端，远端数据面接通后再对齐）
    private var filteredSessions: [RemoteSessionItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sourceSessions }
        return sourceSessions.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.previewText.localizedCaseInsensitiveContains(query)
        }
    }


    @State private var showsArchives = false
    @State private var showsPairSheet = false
    @State private var showsProjectEditor = false
    @State private var showsNewSession = false
    /// P1-CHAT：会话聊天页 push（官方由 ChatShellView 的 selection 承担，本仓导航 =
    /// NavigationStack → navigationDestination）。
    @State private var showsChat = false
    @State private var chatSessionId: String?
    /// 官方 ChatShellView:198 `appState.connectors.first { $0.id == connectorID }?.name`
    /// 的本仓等价物：无常驻 connectors 镜像 → 就绪时拉一次，供聊天页副标题与文件页标题。
    @State private var connectorNames: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss
    /// 官方 AgentsAnywhereApp.swift:23 的后台钩子（方案 B：App 根属本机线，
    /// 死隔离禁动 → 挂远端线页面根；services 未就绪时短路）。
    @Environment(\.scenePhase) private var scenePhase
    // 底栏搜索（与本机同款交互：即时过滤标题、键盘收起三出口）
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    // 项目板块折叠（官方「项目 ▾」）
    @State private var projectsCollapsed = false
    /// 侧栏显示（AA 官方 ChatSidebarListMenu 同 key 持久化）：false = 按项目 / true = 全部会话。
    @AppStorage("aa.native.sidebar.session-list") private var showsAllSessions = false
    /// 归档筛选三态（AA V2DeviceSessionFilter 等价；仅按项目模式出现在菜单，同官方 filters()）。
    @State private var archiveFilter: RemoteSessionFilter = .active
    /// 设备详情页 push（长按终端卡；REMOTE-DEVICE-1，pp 2026-09-20 指定入口）。
    @State private var showsDeviceDetail = false
    /// 远端会话数据层（共享单例：列表页 / 设备页 / 弹窗同源）。
    @StateObject private var loader = RemoteSessionLoader.shared
    /// P3-3：页面级错误 toast 存储（官方一槽一错语义，AAV2 冻结件）。
    @State private var toasts = ChatToastStore()

    // 导航容器与 ModeTabPicker 顶栏由 RemoteRootView 的 NavigationStack 提供
    // （pp 定稿：胶囊切换位置不动）；列表选项菜单在板块结构的项目头 …，
    // 本视图不再另挂右上角菜单。
    var body: some View {
        content
            // 方案 B（REMOTE-REDESIGN-4）：整页暖奶油画布（深色 = 暖黑），列表背景让位
            .background(RemotePalette.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 顶栏右上角：＋ 配对新设备（pp 2026-09-20「把配对新设备的按钮放进
                // 右上角算了」——替代设备卡下方全宽玻璃胶囊）+ ⋯ 菜单（归档/断开）。
                ToolbarItem(placement: .topBarTrailing) { topBarTrailingControls }
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
                // 是这样的」）。创建成功 → 刷新列表；与项目头 + 是两个不同入口。
                RemoteNewSessionView(service: service) { _ in
                    loader.load(service: service, filter: archiveFilter, force: true)
                }
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
            .onAppear {
                guard service.state == .ready else { return }
                loader.load(service: service, filter: archiveFilter)
                loader.loadArchived(service: service)
                Task { await refreshConnectorNames() }
                // dashboard 兜底：RemoteService.syncState 只在跃迁到 .ready 时拉一次，
                // 那一发若因网络失败落地，connectors 仍是空 → 终端卡点进去没有设备身份。
                // repository.refresh 自带 isValid / !isLoading 守门，重复调用不会打串。
                Task { await service.chat?.dashboardRepository.refresh() }
            }
            .onChange(of: archiveFilter) { _, newFilter in
                loader.load(service: service, filter: newFilter, force: true)
            }
    }

    /// 设备名镜像（一次性；配对/改名后的刷新随设备页批走）。失败静默：
    /// 聊天页副标题按官方回退链使用 connectorId。
    private func refreshConnectorNames() async {
        guard let connectors = try? await service.listConnectors() else { return }
        connectorNames = Dictionary(connectors.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// P1-CHAT：聊天页目的地。`service.chat`（组合根）未就绪（未登录/未 bootstrap）
    /// 时列表本身不可点（state != .ready），此处仍做真实判空而非强解包。
    @ViewBuilder private var chatDestination: some View {
        if let id = chatSessionId, let services = service.chat {
            let session = services.sessionRepository.session(id: id)
            SessionChatView(session: session, services: services,
                            deviceName: connectorNames[session.metadata?.connectorId ?? ""],
                            onMenu: { dismiss() })
                .task(id: id) {
                    // 官方 AppState.makeV2Services → services.restoreCache(selection:)：
                    // 进页面先把本地缓存铺进仓库（离线可见），网络回来再覆盖。
                    await services.restoreCache(selection: .session(id))
                    // 官方 AppState:372 sessionReads.setVisibleSession：
                    // local: 前缀的本地草稿不计已读，同官方判据。
                    services.sessionReads.setVisibleSession(
                        id.hasPrefix("local:") ? nil : id)
                    // 官方 AppState:804 sessionReads.onChange：已读态变化投影回列表。
                    // 本仓列表项由 RemoteSessionLoader 持有（无单条 upsert API）→
                    // 已读变化触发一次列表刷新等价覆盖，refresh 内部自带节流。
                    services.sessionReads.onChange = { _ in
                        guard service.state == .ready else { return }
                        loader.load(service: service, filter: archiveFilter)
                    }
                    // 「返回编辑」跳页通道（官方 onSelectPage(.newSession) 的本仓等价物）：
                    // 聊天页 editCreation 暂存草稿后回调这里 → 关聊天页 + 开新会话页。
                    services.onReturnToNewSession = {
                        showsChat = false
                        showsNewSession = true
                    }
                }
        } else {
            Color.clear
        }
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
            // —— 设备（终端窗卡 = 页面主语；无板块头）——
            Section {
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
                                    .background(firstRowFenceReporter(for: item))
                            }
                        } else {
                            // 按项目（AA 官方默认）：项目小标题 + 组内卡堆；未分组殿后。
                            ForEach(groupedItems) { group in
                                projectGroupLabel(group.name)
                                ForEach(group.items) { item in
                                    sessionRow(item)
                                        .background(firstRowFenceReporter(for: item))
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
                            // 搜索无结果 ≠ 没数据——文案分开，保持诚实；
                            // 有项目无会话 vs 没项目 再分开（空态内嵌后）。
                            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? (archiveFilter == .archived
                                    ? "还没有归档的会话。"
                                    : (loader.projectNames.isEmpty ? "还没有项目。" : "还没有会话。点右下角「新对话」开始。"))
                                 : "没有匹配的会话。")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .onAppear {
                                    // [REMOTE-ROW-FENCE] 卡堆清空（搜索/无项目）→ 栅栏复位
                                    RemoteRowsFence.topY = .greatestFiniteMagnitude
                                }
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
        .safeAreaInset(edge: .bottom) { bottomBar }
        .refreshable { await refresh() }
        // REMOTE-DEVICE-1 + P2-A：设备详情页（单击终端卡进入）；per-connector 数据面
        // （官方 ChatShellView:107-143 形状：connector 从 dashboardRepository.connectors
        // 取、删除回调走组合根 removeConnector、.id(connectorId) 官方 190 行）。
        .navigationDestination(isPresented: $showsDeviceDetail) {
            if let connector = deviceConnector, let services = service.chat {
                RemoteDeviceDetailView(service: service, connector: connector) { id in
                    services.removeConnector(connectorId: id)
                    showsDeviceDetail = false
                }
                .id(connector.id)
            } else {
                deviceDetailPending
            }
        }
        // 页切栅栏 + 顶栏齿轮的归属从「详情页 onAppear 自报」改成「push 状态」：
        // 原写法把 remoteAtRoot 挂在 RemoteDeviceDetailView.onAppear 上，目的地
        // 一旦渲染不出内容（pp 2026-09-21 白屏那次根本没 appear），横滑漏切本机
        // 和外壳 topLeading 齿轮压住系统返回箭头这两个问题就一起复发。
        // 系统返回箭头与齿轮共用这一个开关：push 中 → 齿轮隐藏 → 导航栏露出返回键。
        .onChange(of: showsDeviceDetail) { _, pushed in
            RootTabRouter.shared.remoteAtRoot = !pushed
        }
        // P1-CHAT：会话聊天页（官方 ChatShell selection 的本仓导航等价物）
        .navigationDestination(isPresented: $showsChat) {
            chatDestination
        }
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
    }

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
        .swipeActions(edge: .leading) {
            Button { togglePin(item) } label: { Label("置顶", systemImage: "pin") }
                .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button { archive(item) } label: { Label("归档", systemImage: "archivebox") }
                .tint(.gray)
            Button(role: .destructive) { delete(item) } label: { Label("删除", systemImage: "trash") }
        }
    }

    /// [REMOTE-ROW-FENCE] 首卡上报卡堆区顶沿（窗口坐标）——页切手势在卡堆区让位给
    /// 行 swipeActions（pp 2026-09-20「卡片我往右滑怎么切换页了」）。
    /// 仅首卡挂 reporter（中间卡不报，零额外开销）。
    @ViewBuilder
    private func firstRowFenceReporter(for item: RemoteSessionItem) -> some View {
        if item.id == stackFirstItemId {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { RemoteRowsFence.topY = proxy.frame(in: .global).minY }
                    .onChange(of: proxy.frame(in: .global).minY) { _, y in
                        RemoteRowsFence.topY = y
                    }
            }
        }
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

    // MARK: - 底部栏（与本机同一套配方：BottomBarRecipe + SearchBarSurface +
    // BottomBarFadeView，值全部来自 ContentView 的逐像素实测批次，不再手搓）

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                newChatPill
            }
            searchBarCapsule
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(alignment: .bottom) { BottomBarFadeView() }
        .offset(y: searchFocused ? 0 : 30)
    }

    private var newChatPill: some View {
        AppGlassButton(
            AppLocalized("New chat"),
            systemImage: "plus",
            style: .prominent,
            maxWidth: nil,
            tintOverride: BottomBarRecipe.newChatTint,
            labelMinWidth: BottomBarRecipe.newChatLabelMinWidth,
            heightTightening: BottomBarRecipe.newChatHeightTightening,
            action: startNewSession
        )
    }

    private var searchBarCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ChatColors.inputIconFg)
            TextField("Search chats", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 47)
        .modifier(SearchBarSurface())
        .contentShape(.capsule)
    }

    // MARK: - 设备（方案 B / REMOTE-REDESIGN-4：深色终端窗卡，pp 2026-09-20 定稿）

    /// 终端窗卡：mac 三色点 + mono 地址 + CONNECTED 标（在线 teal 点）。
    private var deviceTerminalCard: some View {
        let connected = service.state == .ready
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(RemotePalette.trafficRed).frame(width: 9, height: 9)
                Circle().fill(RemotePalette.trafficYellow).frame(width: 9, height: 9)
                Circle().fill(RemotePalette.trafficGreen).frame(width: 9, height: 9)
                Spacer(minLength: 0)
                Circle()
                    .fill(connected ? RemotePalette.teal : RemotePalette.terminalFaint)
                    .frame(width: 6, height: 6)
                Text(connected ? "CONNECTED" : "OFFLINE")
                    .font(.system(size: 10.5, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(RemotePalette.terminalFaint)
            }
            .padding(.bottom, 10)
            HStack(spacing: 8) {
                Circle()
                    .fill(connected ? RemotePalette.teal : RemotePalette.terminalFaint)
                    .frame(width: 7, height: 7)
                Text(hostLabel)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(RemotePalette.terminalText)
                    .lineLimit(1)
            }
            Text(terminalSubLine)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(RemotePalette.terminalFaint)
                .lineLimit(1)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .background(RemotePalette.terminal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // REMOTE-DEVICE-1：点按整卡进入设备详情页（pp 2026-09-21 改：原长按入口
        // 2026-09-20 版改单击——「现在是长按卡片才能进去 改为点一次就进入」）。
        // 未连接时点按整卡 → 登录/配对（pp 2026-09-20「要提醒用户连接」）。
        .onTapGesture {
            if service.state == .ready {
                showsDeviceDetail = true
            } else {
                onOpenLogin()
            }
        }
        .accessibilityHint(Text(service.state == .ready ? "查看设备详情" : "点按登录并配对设备"))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// 终端副行：地址 — N sessions（预览数据期用真实计数，不假造）。
    /// 终端副行：已连接 = 地址 — N sessions；未连接 = 提醒登录配对（整卡可点）。
    private var terminalSubLine: String {
        guard service.state == .ready else {
            return "not connected — tap to log in & pair"
        }
        let base = serverLabel == "—" ? "not configured" : serverLabel
        return "\(base) — \(sessions.count) sessions"
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
                // [REMOTE-ROW-FENCE] 收起/展开后卡位变化——先复位，展开时首卡会重新上报
                RemoteRowsFence.topY = .greatestFiniteMagnitude
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
        // P1-CHAT：进入官方聊天页（push 目的地，数据面走组合根 sessionRepository）
        chatSessionId = item.id
        showsChat = true
    }

    private func startNewSession() {
        showsNewSession = true
    }

    private func togglePin(_ item: RemoteSessionItem) {
        loader.togglePin(item.id, service: service)
    }

    private func archive(_ item: RemoteSessionItem) {
        loader.archive([item.id], service: service)
    }

    // 删除：服务端会话只有归档/取消归档/标记已读，无删除端点（Staged，
    // 见 PATCHES 台账）；本按钮暂不假造成功态。
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

    /// 项目板块的会话 = 筛选+搜索后的会话（置顶项排前）。
    /// 完整项目抽屉（文件夹行/逐项展开/按项目新建）随数据面批对齐官方。
    private var projectItems: [RemoteSessionItem] {
        filteredSessions.sorted { ($0.isPinned ? 0 : 1) < ($1.isPinned ? 0 : 1) }
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

    /// 当前渲染顺序下的第一张卡（[REMOTE-ROW-FENCE] reporter 的门）。
    private var stackFirstItemId: String? {
        showsAllSessions ? projectItems.first?.id : groupedItems.first?.items.first?.id
    }

    // 列表选项（归档/断开）= 页面级操作，挂顶栏右上角 …（本机同位；
    // REMOTE-REDESIGN-3 从项目头 … 迁回，项目头只留 ▾ 折叠与 ＋ 新建）。
    // 导航容器与 ModeTabPicker 顶栏仍由 RemoteRootView 提供。
    @ViewBuilder
    private var listOptionsMenuContent: some View {
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

    /// 顶栏右上角控件组：＋ 配对新设备（pp 2026-09-20「把配对新设备的按钮放进
    /// 右上角算了」）+ ⋯ 菜单。均原生裸字形——与本机 tab 工具栏惯例一致，
    /// 系统提供标准热区与按压反馈。
    private var topBarTrailingControls: some View {
        HStack(spacing: 16) {
            Button {
                showsPairSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary)
            }
            .accessibilityLabel(Text("配对新设备"))
            topBarOptionsButton
        }
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
    case open, rename, togglePin, archive, copyId
}

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
//   • 会话行未读/审批角标的条目级来源 → RemoteService 的会话状态面（本批先接通列表骨架，
//     指示器按数据面就绪度逐项点亮，不做假数据）
//   • 项目/归档/重命名的服务端写操作 → RemoteService 的项目管理 public 面（同上）

import SwiftUI

struct RemoteSessionListView: View {
    @ObservedObject var service: RemoteService
    /// 审批计数与断开动作由 RemoteRootView 透传（本视图不持有连接生命周期）。
    var pendingNotices: Int = 0
    var onDisconnect: () -> Void = {}

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

    private var sessions: [RemoteSessionItem] {
        // 预览数据（接 RemoteService 后替换）
        RemoteSessionStore.shared.items
    }

    /// 归档筛选后的会话源（AA archiveScope 等价：活跃 / 已归档 / 全部）。
    private var sourceSessions: [RemoteSessionItem] {
        switch archiveFilter {
        case .active: return sessions
        case .archived: return RemoteSessionStore.shared.archived
        case .all: return sessions + RemoteSessionStore.shared.archived
        }
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

    // 预览用假数据（数据面接通后删除）；previewText = 本机卡摘要行的假摘要
    static let previewItems: [RemoteSessionItem] = [
        .init(id: "s1", title: "首页改版 · 数据看板", projectId: "p1", indicator: .waitingApproval, updatedAtText: "10:24", previewText: "把转化率卡片改成周环比"),
        .init(id: "s2", title: "周报自动化", projectId: "p1", indicator: .unread, updatedAtText: "09:12", previewText: "第 38 周周报草稿已生成"),
        .init(id: "s3", title: "API 网关迁移", indicator: .running, updatedAtText: "昨天", previewText: "灰度 5% 流量验证中"),
        .init(id: "s4", title: "Claude Code 接入评估", updatedAtText: "9-18", previewText: "整理了三家的报价对比"),
        .init(id: "s5", title: "服务器续费提醒", updatedAtText: "9-15", previewText: "证书 9-30 到期，记得续期"),
    ]


    @State private var showsArchives = false
    @State private var showsPairSheet = false
    @State private var showsProjectEditor = false
    @State private var showsNewSession = false
    @State private var showsSessionDetail = false
    @State private var selectedSessionId: String?
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
            .sheet(isPresented: $showsPairSheet) {
                PairDeviceSheet(service: service)
            }
            .sheet(isPresented: $showsProjectEditor) {
                // 项目编辑（AA 的 ProjectEditorSheet 视觉；数据面就绪前弹联动占位）
                RemoteProjectEditorSheet(service: service)
            }
            .sheet(isPresented: $showsNewSession) {
                // 新会话抽屉（AA 官方语义：设备 → 项目 → 运行时 → 任务；
                // 与项目头的 + （RemoteProjectEditorSheet）是两个不同入口）
                RemoteNewSessionSheet(service: service)
            }
            .sheet(isPresented: $showsArchives) {
                RemoteArchivedSessionsSheet(service: service)
            }
            .sheet(isPresented: $showsSessionDetail) {
                if let id = selectedSessionId {
                    RemoteSessionDetailSheet(service: service, sessionId: id)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            sessionList
        }
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
            Section {
                projectHeader
                if !projectsCollapsed {
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
                    if projectItems.isEmpty {
                        // 搜索无结果 ≠ 没有项目——文案分开，保持诚实
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? (archiveFilter == .archived ? "还没有归档的会话。" : "还没有项目。")
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
        .listStyle(.plain)
        // 方案 B：列表滚动背景让位给页面画布（画布挂在 body 级 background 上）
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .refreshable { await refresh() }
        // REMOTE-DEVICE-1：设备详情页（长按终端卡进入）
        .navigationDestination(isPresented: $showsDeviceDetail) {
            RemoteDeviceDetailView(service: service)
        }
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
                if item.indicator == .unread {
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

    // MARK: - 空态（诚实：没数据就说没数据）

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有远程会话")
                .font(.title3.bold())
            Text("连接工作区后，云端的会话会出现在这里。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("配对新设备") { showsPairSheet = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { bottomBar }
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
        // REMOTE-DEVICE-1：长按终端卡 → 设备详情页（pp 2026-09-20 指定入口）
        .onLongPressGesture { showsDeviceDetail = true }
        .accessibilityHint(Text("长按查看设备详情"))
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// 终端副行：地址 — N sessions（预览数据期用真实计数，不假造）。
    private var terminalSubLine: String {
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
        // 会话页接线在聊天页批；本批列表骨架 + 弹窗。
        selectedSessionId = item.id
        showsSessionDetail = true
    }

    private func startNewSession() {
        showsNewSession = true
    }

    private func togglePin(_ item: RemoteSessionItem) {
        RemoteSessionStore.shared.togglePin(item.id)
    }

    private func archive(_ item: RemoteSessionItem) {
        RemoteSessionStore.shared.archive(item.id)
    }

    private func delete(_ item: RemoteSessionItem) {
        RemoteSessionStore.shared.delete(item.id)
    }

    private func handleMenuAction(_ action: RemoteSessionMenuAction, for item: RemoteSessionItem) {
        switch action {
        case .open: openSession(item)
        case .rename: RemoteSessionStore.shared.startRename(item.id)
        case .togglePin: togglePin(item)
        case .archive: archive(item)
        case .copyId: UIPasteboard.general.string = item.id
        }
    }

    private func refresh() async {
        // 数据面刷新：RemoteService 的会话列表 public 面就绪后接这里。
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

    /// 预览期项目名别名表——数据面接通后由远端项目列表替换（Staged: 项目管理 public 面）。
    static let previewProjectNames: [String: String] = ["p1": "工作台"]

    private func projectDisplayName(for projectId: String) -> String {
        Self.previewProjectNames[projectId] ?? projectId
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

// MARK: - 数据模型（远端会话条目；数据面就绪前由 RemoteSessionStore 占位）

struct RemoteSessionItem: Identifiable, Equatable {
    let id: String
    var title: String
    var projectId: String?
    var isPinned: Bool = false
    var indicator: RemoteSessionIndicator = .none
    var updatedAtText: String = ""
    /// 本机卡摘要行（最后一条消息预览）；数据面就绪前由预览数据填充
    var previewText: String = ""
}

@MainActor
final class RemoteSessionStore: ObservableObject {
    static let shared = RemoteSessionStore()
    @Published private(set) var items: [RemoteSessionItem] = RemoteSessionListView.previewItems
    @Published private(set) var archived: [RemoteSessionItem] = []

    func title(for id: String) -> String? {
        items.first { $0.id == id }?.title
    }

    func togglePin(_ id: String) {}
    func archive(_ id: String) {}
    func delete(_ id: String) {}
    func startRename(_ id: String) {}
}

enum RemoteSessionMenuAction {
    case open, rename, togglePin, archive, copyId
}

// RemoteSessionListView.swift — 远端会话列表（R0，batch 8）
//
// 形态（pp 2026-09-20 定稿）：板块切分照官方两大模块——「设备」+「项目」；
// 会话行/底栏复用本机列表 UI；设备与项目两板块按大厂风重排（REMOTE-REDESIGN-1，
// pp 2026-09-20 拍板：设备行=图标+名称/地址两行+状态徽章，板块头=主色标题+淡色圆钮）；
// AA 视觉只出现在点进去的弹窗页（PairDeviceSheet / ProjectEditor / 详情 / 归档）。
// 数据源只走 RemoteKit 的 public facade（RemoteService / RemotePairingPayload），
// 不读 ChatStore、不碰 ContentView 的 stackList（死隔离：远端列表与本机列表文件级零交集）。
//
// 功能面（AA 官方移动端会话列表全量，不阉割）：
//   • 设备板块：设备行（44 圆底服务器图标 + 设备名/完整地址两行 + 已连接徽章）
//     +「配对新设备」入口行 → PairDeviceSheet
//   • 项目板块：折叠头（项目 + chevron 折叠 + 新建）→ ProjectEditorSheet；
//     页面级选项（归档/断开）在顶栏右上角 … 玻璃圆（REMOTE-REDESIGN-3）
//   • 会话行：本机 SessionRow 完整结构（无底裸 lucide 头像 + 标题 + 摘要 + 时间 +
//     置顶角标）；状态映射进头像槽位——运行中=外圈转圈 / 未读=右上红点 /
//     等待批准=右下 mint 角标（pp 2026-09-20 定稿：只换头像，其余与本机卡一致）
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

    /// 搜索过滤：标题/摘要本地过滤（本机搜索走 ChatStore 后端，远端数据面接通后再对齐）
    private var filteredSessions: [RemoteSessionItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter {
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

    // 导航容器与 ModeTabPicker 顶栏由 RemoteRootView 的 NavigationStack 提供
    // （pp 定稿：胶囊切换位置不动）；列表选项菜单在板块结构的项目头 …，
    // 本视图不再另挂右上角菜单。
    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 顶栏右上角选项（pp 2026-09-20：「顶栏右边是不是少了个按钮」——
                // 本机同位置有 … 工具菜单，TWOMODULE 曾把远端的删成空；归档/断开
                // 从项目头 … 迁回此处，页面级操作回到顶栏传统位）
                ToolbarItem(placement: .topBarTrailing) { topBarOptionsButton }
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

    // MARK: - 列表（官方两大板块：设备 / 项目；行视觉全部复用本机列表 UI）

    private var sessionList: some View {
        List {
            // —— 设备板块（板块头内联，与项目头同一套设计语言）——
            Section {
                deviceSectionHeader
                deviceRow
                if pendingNotices > 0 {
                    pendingNoticesRow
                }
                pairDeviceRow
            }

            // —— 项目板块（projectHeader 行自带标题 + 折叠 + 菜单 + 新建；
            // 不套 Section header 重复一遍） ——
            Section {
                projectHeader
                if !projectsCollapsed {
                    ForEach(projectItems) { item in
                        sessionRow(item)
                    }
                    if projectItems.isEmpty {
                        // 搜索无结果 ≠ 没有项目——文案分开，保持诚实
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "还没有项目。"
                             : "没有匹配的会话。")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color(.systemBackground))
                    }
                }
            }
        }
        .listStyle(.plain)
        // 不藏列表滚动背景：与本机列表同款平色 systemBackground（本机也不 hide，
        // 渐隐层由底栏的 background 挂载负责，见 BottomBarFadeView）
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .refreshable { await refresh() }
    }

    // MARK: - 会话行（REMOTE-REDESIGN-1：本机 ContentView.SessionRow 完整结构，
    // 唯一差异 = 头像为无底裸 lucide message-square-quote，pp 2026-09-20 定稿）
    // 无左缩进（pp 10:4x 装机反馈「卡片左边空一大截」）：36pt 项目缩进随旧板块结构一并移除，
    // 与本机卡同款对称 horizontal 16pt。
    // 状态映射进头像槽位：运行中 → 外圈转圈（SpinningRing 同款）；未读 → 头像右上
    // 红点；等待批准 → 头像右下 mint 角标。字级走 App Base 缩放（scaledApp）。

    private func sessionRow(_ item: RemoteSessionItem) -> some View {
        Button {
            openSession(item)
        } label: {
            HStack(spacing: 8) {
                sessionAvatar(for: item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: FontSettings.shared.scaledApp(16), weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(item.previewText)
                        .font(.system(size: FontSettings.shared.scaledApp(14)))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 1)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.updatedAtText)
                        .font(.system(size: FontSettings.shared.scaledApp(13)))
                        .foregroundStyle(.tertiary)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        // 行背景对齐本机：平色 systemBackground（RemoteRowCardBackground 已随之删除）
        .listRowBackground(Color(.systemBackground))
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

    /// 头像槽位：44×44 裸图标居中；三态 overlay 的几何（offset ±2 / 8pt 红点 /
    /// 16pt 角标）与本机 SessionRow 的角标位一致。
    @ViewBuilder
    private func sessionAvatar(for item: RemoteSessionItem) -> some View {
        RemoteSessionIcon(size: 24, color: .secondary)
            .frame(width: 44, height: 44)
            .overlay {
                if item.indicator == .running {
                    RemoteSpinningRing(color: .secondary)
                        .frame(width: 42, height: 42)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.indicator == .waitingApproval {
                    RemoteBadgeCircle(icon: "bell.fill", color: .mint, iconSize: 8)
                        .offset(x: 2, y: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.indicator == .unread {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: -1, y: 1)
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

    // MARK: - 设备板块（REMOTE-REDESIGN-1：大厂风重排，pp 2026-09-20）

    /// 板块头（内联行，与项目头同一套设计语言：主色标题）。
    private var deviceSectionHeader: some View {
        HStack(spacing: 6) {
            Text("设备")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(minHeight: 48)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
    }

    /// 设备行：左 44 圆底服务器图标（在线绿/离线灰）+ 设备名/完整地址两行 +
    /// 右侧「已连接/未连接」淡底状态徽章；连接判定沿用 service.state == .ready。
    private var deviceRow: some View {
        let connected = service.state == .ready
        let tint = connected ? Color.green : Color.secondary
        return HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(hostLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(connected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Text(serverLabel)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle()
                    .fill(connected ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text(connected ? "已连接" : "未连接")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
    }

    /// 待处理提醒行：bell 淡色圆底 + 橙色数字胶囊（Mail/提醒事项式）。
    private var pendingNoticesRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.12), in: Circle())
            Text("需要你处理")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Text("\(pendingNotices)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.orange, in: Capsule())
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
    }

    /// 「配对新设备」入口行：淡色 28 圆底 + 号 + chevron。
    /// 弹窗内容 PairDeviceSheet 保持 AA 视觉——pp 定稿：进按钮的 UI 才完全用 AA。
    private var pairDeviceRow: some View {
        Button {
            showsPairSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
                Text("配对新设备")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
    }

    // MARK: - 项目头（REMOTE-REDESIGN-1 重排：主色标题 + 会话数 + chevron 折叠 +
    // ＋ 新建淡色圆钮；REMOTE-REDESIGN-3 起 … 菜单迁顶栏右上角）

    private var projectHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { projectsCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("项目")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("\(projectItems.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(projectsCollapsed ? 0 : 90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                showsProjectEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(minHeight: 48)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
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

    /// 项目板块的会话 = 搜索过滤后的全部会话（两大板块结构下不再有独立「置顶/全部」段；
    /// 置顶项排前。按项目分组折叠的条目级呈现随数据面接通再对齐官方项目抽屉。）
    private var projectItems: [RemoteSessionItem] {
        filteredSessions.sorted { ($0.isPinned ? 0 : 1) < ($1.isPinned ? 0 : 1) }
    }

    // 列表选项（归档/断开）= 页面级操作，挂顶栏右上角 …（本机同位；
    // REMOTE-REDESIGN-3 从项目头 … 迁回，项目头只留 ▾ 折叠与 ＋ 新建）。
    // 导航容器与 ModeTabPicker 顶栏仍由 RemoteRootView 提供。
    @ViewBuilder
    private var listOptionsMenuContent: some View {
        Button("归档会话", systemImage: "archivebox") { showsArchives = true }
        Divider()
        // 断开连接入口从 RemoteRootView 的状态卡迁移至此（接线时不丢）
        Button("断开连接", role: .destructive, action: onDisconnect)
    }

    /// 顶栏右上角 …（玻璃圆，与 RootModeTabsView 固定栏 ☰ 同一配方：
    /// GlassEffectContainer + .regular.interactive() Circle——AA composer 配方；
    /// 44pt 对齐 gearDiameter；本机 toolbar … 菜单同位，pp 2026-09-20）
    private var topBarOptionsButton: some View {
        GlassEffectContainer(spacing: 12) {
            Menu {
                listOptionsMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
        }
    }
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

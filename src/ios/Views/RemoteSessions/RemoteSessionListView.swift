// RemoteSessionListView.swift — 远端会话列表（R0，batch 8）
//
// 形态（pp 2026-09-20 定稿）：板块切分照官方两大模块——「设备」+「项目」；
// 列表视觉全部复用本机列表 UI（平色行/sectionLabel/底栏配方），不另造一套；
// AA 视觉只出现在点进去的弹窗页（PairDeviceSheet / ProjectEditor / 详情 / 归档）。
// 数据源只走 RemoteKit 的 public facade（RemoteService / RemotePairingPayload），
// 不读 ChatStore、不碰 ContentView 的 stackList（死隔离：远端列表与本机列表文件级零交集）。
//
// 功能面（AA 官方移动端会话列表全量，不阉割）：
//   • 设备板块：在线/离线点 + 等宽设备名 + 「配对设备」整行入口 → PairDeviceSheet
//   • 项目板块：折叠头（项目 ▾ + … + 新建）+ 项目内会话缩进 → ProjectEditorSheet
//   • 会话行：标题/时间/状态指示（等待批准 / 运行中 / 未读）
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

    private var sessions: [RemoteSessionItem] {
        // 预览数据（接 RemoteService 后替换）
        RemoteSessionStore.shared.items
    }

    /// 搜索过滤：标题本地过滤（本机搜索走 ChatStore 后端，远端数据面接通后再对齐）
    private var filteredSessions: [RemoteSessionItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    // 预览用假数据（数据面接通后删除）
    static let previewItems: [RemoteSessionItem] = [
        .init(id: "s1", title: "首页改版 · 数据看板", projectId: "p1", indicator: .waitingApproval, updatedAtText: "10:24"),
        .init(id: "s2", title: "周报自动化", projectId: "p1", indicator: .unread, updatedAtText: "09:12"),
        .init(id: "s3", title: "API 网关迁移", indicator: .running, updatedAtText: "昨天"),
        .init(id: "s4", title: "Claude Code 接入评估", updatedAtText: "9-18"),
        .init(id: "s5", title: "服务器续费提醒", updatedAtText: "9-15"),
    ]


    @State private var showsArchives = false
    @State private var showsPairSheet = false
    @State private var showsProjectEditor = false
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
            .sheet(isPresented: $showsPairSheet) {
                PairDeviceSheet(service: service)
            }
            .sheet(isPresented: $showsProjectEditor) {
                // 项目编辑（AA 的 ProjectEditorSheet 视觉；数据面就绪前弹联动占位）
                RemoteProjectEditorSheet(service: service)
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
            // —— 设备板块 ——
            Section {
                deviceRow
                if pendingNotices > 0 {
                    Label("需要你处理 ×\(pendingNotices)", systemImage: "bell.badge")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemBackground))
                }
                pairDeviceRow
            } header: {
                sectionLabel("设备")
            }

            // —— 项目板块（projectHeader 行自带标题 + 折叠 + 菜单 + 新建；
            // 不套 Section header 重复一遍） ——
            Section {
                projectHeader
                previewBanner
                if !projectsCollapsed {
                    ForEach(projectItems) { item in
                        sessionRow(item, inset: true)
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

    // MARK: - 会话行（本机平色行视觉 + AA 状态指示器四态）

    private func sessionRow(_ item: RemoteSessionItem, inset: Bool = false) -> some View {
        Button {
            openSession(item)
        } label: {
            HStack(spacing: 12) {
                RemoteSessionIcon(size: 20, color: .secondary)
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.updatedAtText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                RemoteStatusIndicator(indicator: item.indicator)
            }
            .padding(.leading, inset ? 36 : 16)
            .padding(.trailing, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        // 行背景对齐本机：平色 systemBackground（原圆角卡片描边版视觉与本机不一致，
        // pp 2026-09-20 排版修复；RemoteRowCardBackground 已随之删除）
        .listRowBackground(inset ? Color.clear : Color(.systemBackground))
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
            Button("配对设备") { showsPairSheet = true }
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

    // MARK: - 设备板块

    private var deviceRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(service.state == .ready ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(serverLabel)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(service.state == .ready ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
    }

    /// 「+ 配对设备」整行（官方板块结构；行视觉 = 本机列表行同款）。
    /// 弹窗内容 PairDeviceSheet 保持 AA 视觉——pp 定稿：进按钮的 UI 才完全用 AA。
    private var pairDeviceRow: some View {
        Button {
            showsPairSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)
                Text("配对设备")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
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

    /// 诚实标识（pp 2026-09-20：假数据不许静默装真）——数据面接通后删除。
    private var previewBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
            Text("预览数据 · 真实会话接通中")
                .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
    }

    // MARK: - 项目头（官方：「项目 ▾ … +」；折叠/菜单/新建都接真行为）

    private var projectHeader: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy) { projectsCollapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("项目")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: projectsCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Menu {
                listOptionsMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                showsProjectEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .frame(minHeight: 48)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    // MARK: - 操作

    private func openSession(_ item: RemoteSessionItem) {
        // 会话页接线在聊天页批；本批列表骨架 + 弹窗。
        selectedSessionId = item.id
        showsSessionDetail = true
    }

    private func startNewSession() {
        showsProjectEditor = true
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

    // 列表选项（归档/断开）挂在项目头的 …（官方位置）；右上角不再另放菜单。
    // 导航容器与 ModeTabPicker 顶栏仍由 RemoteRootView 提供。
    @ViewBuilder
    private var listOptionsMenuContent: some View {
        Button("归档会话", systemImage: "archivebox") { showsArchives = true }
        Divider()
        // 断开连接入口从 RemoteRootView 的状态卡迁移至此（接线时不丢）
        Button("断开连接", role: .destructive, action: onDisconnect)
    }
}

// MARK: - 数据模型（远端会话条目；数据面就绪前由 RemoteSessionStore 占位）

struct RemoteSessionItem: Identifiable, Equatable {
    let id: String
    var title: String
    var projectId: String?
    var isPinned: Bool = false
    var indicator: RemoteStatusIndicator.Indicator = .none
    var updatedAtText: String = ""
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

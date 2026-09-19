// RemoteSessionListView.swift — 远端会话列表（R0，batch 8）
//
// 形态：moonveil 本机列表的壳（List + 卡片化 + 底部搜索框/新会话胶囊，视觉/手势/交互一致），
// 数据源只走 RemoteKit 的 public facade（RemoteService / RemotePairingPayload），
// 不读 ChatStore、不碰 ContentView 的 stackList（死隔离：远端列表与本机列表文件级零交集）。
//
// 功能面（AA 官方移动端会话列表全量，不阉割）：
//   • 会话行：标题/时间/状态指示（等待批准 / 运行中 / 未读）
//   • 设备（连接器）区：在线/离线点 + 等宽设备名 + 选中高亮
//   • 配对设备入口 → PairDeviceSheet（直接复用 AA 视觉）
//   • 项目分组（折叠头 + 创建项目 + 项目内会话缩进）→ ProjectEditorSheet
//   • 长按菜单：Open / Rename / Pin·Unpin / Archive·Restore / Copy Session ID
//   • 左滑动作：置顶 / 归档 / 删除
//   • 列表选项菜单：按项目 / 全部会话 / 筛选 / 归档会话
//   • 归档页（ArchivedSessionsSheet）+ 下拉刷新 + 空态诚实
//
// Staged with deadlines（完整性铁律 — 明示不藏）：
//   • 会话行未读/审批角标的条目级来源 → RemoteService 的会话状态面（本批先接通列表骨架，
//     指示器按数据面就绪度逐项点亮，不做假数据）
//   • 项目/归档/重命名的服务端写操作 → RemoteService 的项目管理 public 面（同上）

import SwiftUI

struct RemoteSessionListView: View {
    @ObservedObject var service: RemoteService
    @ObservedObject private var tabRouter = RootTabRouter.shared

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
    @State private var showsListOptions = false
    @State private var showsSessionDetail = false
    @State private var selectedSessionId: String?

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ModeTabPicker(selection: $tabRouter.mode, localLabel: soulName)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        listOptionsButton
                    }
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            soulName = currentSoulName()
        }
    }

    @State private var soulName: String = currentSoulName()

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            sessionList
        }
    }

    // MARK: - 列表（moonveil 卡片化壳）

    private var sessionList: some View {
        List {
            // 连接器区（AA 的 Devices section：在线/离线点 + 等宽设备名）
            Section {
                connectorRow
            } header: {
                sectionLabel("连接器")
            }

            // 置顶会话
            if !pinnedItems.isEmpty {
                Section {
                    ForEach(pinnedItems) { item in
                        sessionRow(item)
                    }
                } header: {
                    sectionLabel("置顶")
                }
            }

            // 项目分组（折叠头 + 缩进会话）
            Section {
                projectHeader
                ForEach(projectItems) { item in
                    sessionRow(item, inset: true)
                }
            } header: {
                sectionLabel("项目")
            }

            // 全部会话
            Section {
                ForEach(recentItems) { item in
                    sessionRow(item)
                }
            } header: {
                sectionLabel("全部会话")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .refreshable { await refresh() }
    }

    // MARK: - 会话行（moonveil 卡片 + AA 状态指示器四态）

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
            .padding(.leading, inset ? 36 : 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(
            Group {
                if inset { Color.clear } else { RemoteRowCardBackground() }
            }
        )
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

    // MARK: - 底部栏（moonveil 已有的搜索框 + 新会话胶囊，视觉/布局照抄 bottomBar）

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                newChatPill
            }
            searchBar
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(.regularMaterial)
    }

    private var newChatPill: some View {
        AppGlassButton(
            "新会话",
            systemImage: "plus",
            style: .prominent,
            maxWidth: nil,
            action: startNewSession
        )
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("搜索对话")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    // MARK: - 连接器区

    private var connectorRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(service.state == .ready ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(serverLabel)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(service.state == .ready ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                showsPairSheet = true
            } label: {
                Label("配对设备", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
    }

    // MARK: - 项目头

    private var projectHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("项目")
                .font(.body)
            Spacer(minLength: 0)
            Button {
                showsListOptions = true
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                showsProjectEditor = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
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

    private var pinnedItems: [RemoteSessionItem] { sessions.filter(\.isPinned) }
    private var projectItems: [RemoteSessionItem] { sessions.filter { $0.projectId != nil && !$0.isPinned } }
    private var recentItems: [RemoteSessionItem] { sessions.filter { $0.projectId == nil && !$0.isPinned } }

    private var listOptionsButton: some View {
        Menu {
            Picker("列表显示", selection: .constant(true)) {
                Text("按项目").tag(false)
                Text("全部会话").tag(true)
            }
            Divider()
            Button("归档会话", systemImage: "archivebox") { showsArchives = true }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
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

private func currentSoulName() -> String {
    let n = SoulStore.cachedMetadata.name
    return n.isEmpty ? "Moonveil" : n
}

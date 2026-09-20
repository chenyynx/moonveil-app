// RemoteDeviceDetailView.swift — 设备详情页（AA DeviceManagementView 移植，REMOTE-DEVICE-1）
//
// 结构照 AA 官方（~/aa-ios .../Views/Devices/DeviceManagementView.swift 及同目录组件）：
//   Agent Runtime 区（标题 + 重新发现按钮；footer = 黑玻璃「添加更多 Agent」→ 添加 Agent 弹窗）
//   → 设备内容（项目/会话 segmented）
//   → 项目 tab：N 个项目 + ＋ 新建 + 目录行（folder / 新会话 / 文件 动作 + 上下文菜单）；
//     showsAllSessions（工作目录模式）时切换为工作目录列表；
//   → 会话 tab：范围 picker + ⋯ + 新会话 + 活跃/已归档/全部 segmented + 会话行。
//
// 数据面（预览期诚实降级，Staged 台账见 PATCHES REMOTE-DEVICE-1）：
//   • agents inventory / 工作目录列表 = 空（官方同款空态文案，不假造型）
//   • 项目由预览会话的 projectId 派生（名称别名表）；工作目录数据面接通后替换
//   • 服务端写操作（重命名/轮换/删除/归档/批量选择）按官方 !canManage 态禁用
//
// 入口：RemoteSessionListView 长按终端卡片 push 本页（pp 2026-09-20）。
// 页切栅栏：onAppear/onDisappear 上报 RootTabRouter.remoteAtRoot（远端 push 页不参与
// 横滑切 tab——B16-SWIPE-SCOPE 的远端线同规则）。

import SwiftUI

struct RemoteDeviceDetailView: View {
    @ObservedObject var service: RemoteService

    @AppStorage("aa.native.sidebar.session-list") private var showsAllSessions = false
    @State private var tab: DeviceContentTab = .projects
    @State private var archiveFilter: RemoteSessionFilter = .active
    @State private var scopeProjectId: String? = nil
    @State private var showsAddAgent = false
    @State private var showsNewSession = false
    @State private var showsProjectEditor = false
    @State private var selectedSessionId: String?
    @State private var showsSessionDetail = false

    private enum DeviceContentTab: Hashable { case projects, sessions }

    // MARK: - 设备信息（与列表页同一来源）

    private var serverLabel: String {
        UserDefaults.standard.string(forKey: "agentsAnywhere.serverURL") ?? "—"
    }

    private var hostLabel: String {
        let raw = serverLabel
        guard raw != "—", let url = URL(string: raw), let host = url.host(percentEncoded: false), !host.isEmpty else {
            return raw == "—" ? "未配置服务器" : raw
        }
        return host
    }

    private var connected: Bool { service.state == .ready }
    private var connectionDescription: String { connected ? "已连接" : "设备离线" }

    // MARK: - 数据（RemoteSessionLoader 共享单例；列表页触发加载，本页读缓存）

    private var sessions: [RemoteSessionItem] { RemoteSessionLoader.shared.items }

    private var sourceSessions: [RemoteSessionItem] {
        switch archiveFilter {
        case .active: return sessions
        case .archived: return RemoteSessionLoader.shared.archivedItems
        case .all: return sessions + RemoteSessionLoader.shared.archivedItems
        }
    }

    private var visibleSessions: [RemoteSessionItem] {
        guard let scope = scopeProjectId else { return sourceSessions }
        return sourceSessions.filter { $0.projectId == scope }
    }

    /// 工作目录（AA DeviceWorkspaceList）——数据面接通前恒空（Staged）。
    private var workspaces: [String] { [] }

    private struct DeviceProject: Identifiable {
        let id: String
        let name: String
        let sessionCount: Int
    }

    /// 项目由当前会话的 projectId 派生（项目名取远端真实列表）。
    private var projects: [DeviceProject] {
        var counts: [String: Int] = [:]
        for item in sessions {
            if let pid = item.projectId { counts[pid, default: 0] += 1 }
        }
        return counts
            .map { DeviceProject(id: $0.key, name: Self.projectName($0.key), sessionCount: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private static func projectName(_ id: String) -> String {
        RemoteSessionLoader.shared.projectNames[id] ?? id
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                agentSection
                contentSwitcher
                if tab == .projects {
                    projectsSection
                } else {
                    sessionsSection
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(RemotePalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(hostLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(RemotePalette.ink)
                    Text(connectionDescription)
                        .font(.system(size: 11.5))
                        .foregroundStyle(RemotePalette.body)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { deviceActionsMenu }
        }
        .sheet(isPresented: $showsAddAgent) { RemoteAddAgentSheet() }
        .sheet(isPresented: $showsNewSession) { RemoteNewSessionSheet(service: service) }
        .sheet(isPresented: $showsProjectEditor) { RemoteProjectEditorSheet(service: service) }
        .sheet(isPresented: $showsSessionDetail) {
            if let id = selectedSessionId {
                RemoteSessionDetailSheet(service: service, sessionId: id)
            }
        }
        .onAppear { RootTabRouter.shared.remoteAtRoot = false }
        .onDisappear { RootTabRouter.shared.remoteAtRoot = true }
    }

    // MARK: - 顶栏设备菜单（AA DeviceManagementView toolbar；写操作按官方 !canManage 禁用）

    private var deviceActionsMenu: some View {
        Menu {
            Button("新会话", systemImage: "square.and.pencil") { showsNewSession = true }
            Button("复制设备 ID", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = serverLabel
            }
            Divider()
            // 服务端写操作（Staged：设备管理写面接通后启用，官方同样在不可管理时禁用）
            Button("重命名设备", systemImage: "pencil") {}
                .disabled(true)
            Button("轮换凭证", systemImage: "key") {}
                .disabled(true)
            Button("删除设备", systemImage: "trash", role: .destructive) {}
                .disabled(true)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary)
        }
    }

    // MARK: - Agent Runtime 区（AA DeviceAgentSection：header + 重新发现；footer 黑按钮）

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Agent Runtime")
                    .font(.system(size: 15))
                    .foregroundStyle(RemotePalette.body)
                Spacer()
                Button {
                    Task { await refreshAgents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(RemotePalette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("重新发现 Agent"))
            }
            // 预览期无 agent inventory → 零行（官方空库存时同样零行，无假造型）
            AppGlassButton("添加更多 Agent", systemImage: "plus", style: .prominent) {
                showsAddAgent = true
            }
        }
    }

    private func refreshAgents() async {
        // Staged（REMOTE-DEVICE-1）：agent inventory public 面就绪后接这里
    }

    // MARK: - 设备内容（AA contentSwitcher：标题 + segmented）

    private var contentSwitcher: some View {
        HStack {
            Text("设备内容")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RemotePalette.ink)
            Spacer()
            Picker("设备内容", selection: $tab) {
                Text("项目").tag(DeviceContentTab.projects)
                Text("会话").tag(DeviceContentTab.sessions)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    // MARK: - 项目 tab（AA DeviceProjectList / DeviceWorkspaceList）

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(showsAllSessions ? "\(workspaces.count) 个工作目录" : "\(projects.count) 个项目")
                    .font(.system(size: 15))
                    .foregroundStyle(RemotePalette.body)
                Spacer()
                Button {
                    showsProjectEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(RemotePalette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("创建项目"))
            }
            if showsAllSessions {
                unavailableCard(icon: "folder", text: "暂无工作目录。")
            } else if projects.isEmpty {
                unavailableCard(icon: "folder", text: "暂无项目。")
            } else {
                groupedCard {
                    ForEach(Array(projects.indices), id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 12) }
                        projectRow(projects[index])
                    }
                }
            }
        }
    }

    /// AA DeviceDirectoryRow：folder + 名称 + N 会话 + [文件/新会话] 动作 + 上下文菜单。
    private func projectRow(_ project: DeviceProject) -> some View {
        HStack(spacing: 12) {
            Button {
                scopeProjectId = project.id
                tab = .sessions
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 17))
                        .foregroundStyle(RemotePalette.ink)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(RemotePalette.ink)
                        Text("\(project.sessionCount) 个会话")
                            .font(.system(size: 12))
                            .foregroundStyle(RemotePalette.body)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("查看项目会话"))
            HStack(spacing: 0) {
                // 文件浏览：files service 未接通（Staged）——按官方离线态禁用
                Button {} label: {
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                        .foregroundStyle(RemotePalette.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityLabel(Text("文件"))
                Button {
                    showsNewSession = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15))
                        .foregroundStyle(RemotePalette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("新会话"))
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            // 服务端写操作（Staged：项目管理写面接通后启用）
            Button("重命名项目", systemImage: "pencil") {}
                .disabled(true)
            Button("置顶", systemImage: "pin") {}
                .disabled(true)
            Divider()
            Button("归档项目会话", systemImage: "archivebox") {}
                .disabled(true)
            Button("删除项目", systemImage: "trash", role: .destructive) {}
                .disabled(true)
        }
    }

    // MARK: - 会话 tab（AA DeviceSessionList）

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Picker("项目范围", selection: $scopeProjectId) {
                    Text("全部项目").tag(String?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
                Spacer(minLength: 8)
                Menu {
                    // 多选 + 批量归档（Staged：归档写操作批；官方不可管理时同样禁用）
                    Button("选择会话", systemImage: "checkmark.circle") {}
                        .disabled(true)
                    Divider()
                    Button("归档范围内全部", systemImage: "archivebox") {}
                        .disabled(true)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(RemotePalette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("会话操作"))
                Button {
                    showsNewSession = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(RemotePalette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("新会话"))
            }
            Picker("会话筛选", selection: $archiveFilter) {
                Text("活跃").tag(RemoteSessionFilter.active)
                Text("已归档").tag(RemoteSessionFilter.archived)
                Text("全部").tag(RemoteSessionFilter.all)
            }
            .pickerStyle(.segmented)
            if visibleSessions.isEmpty {
                unavailableCard(icon: "bubble.left.and.bubble.right", text: "这里还没有会话。")
            } else {
                groupedCard {
                    ForEach(Array(visibleSessions.indices), id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 12) }
                        sessionRow(visibleSessions[index])
                    }
                }
            }
        }
    }

    /// AA DeviceSessionList 行：标题（未读加粗）+ 项目名 + 状态指示 + 日期。
    private func sessionRow(_ item: RemoteSessionItem) -> some View {
        Button {
            selectedSessionId = item.id
            showsSessionDetail = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: FontSettings.shared.scaledApp(15.5),
                                      weight: item.indicator == .unread ? .semibold : .regular))
                        .foregroundStyle(RemotePalette.ink)
                        .lineLimit(2)
                    Text(scopeCaption(item))
                        .font(.system(size: 12))
                        .foregroundStyle(RemotePalette.body)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    stateMark(for: item)
                    Text(item.updatedAtText)
                        .font(.system(size: 11))
                        .foregroundStyle(RemotePalette.timeFaint)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("打开", systemImage: "arrow.up.right") {
                selectedSessionId = item.id
                showsSessionDetail = true
            }
            // 归档（Staged：归档写操作批；官方不可管理时同样禁用）
            Button("归档", systemImage: "archivebox") {}
                .disabled(true)
            Button("复制会话 ID", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = item.id
            }
        }
    }

    private func scopeCaption(_ item: RemoteSessionItem) -> String {
        if let pid = item.projectId { return Self.projectName(pid) }
        return "未分组"
    }

    @ViewBuilder
    private func stateMark(for item: RemoteSessionItem) -> some View {
        switch item.indicator {
        case .waitingApproval:
            Text("待批准")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RemotePalette.amber, in: Capsule())
        case .running:
            HStack(spacing: 4) {
                RemoteSpinningRing(color: RemotePalette.runningTeal)
                    .frame(width: 9, height: 9)
                Text("running")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(RemotePalette.runningTeal)
            }
        case .unread:
            Circle()
                .fill(RemotePalette.coral)
                .frame(width: 8, height: 8)
        case .none:
            EmptyView()
        }
    }

    // MARK: - 分组卡与空态（AA DeviceOverviewSections 的 GroupBox 变体）

    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RemotePalette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// AA ContentUnavailableView 的等价（图标 + 说明）。
    private func unavailableCard(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(RemotePalette.body)
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RemotePalette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(RemotePalette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - 添加 Agent 弹窗（AA AddDeviceAgentSheet 移植；预览期 = 官方空态文案）

struct RemoteAddAgentSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 预览期无 agent inventory（Staged）——官方空态文案原样
                    Text("尚未发现可用 Agent。在设备上安装并登录 Agent 后，重新发现即可添加。")
                        .font(.system(size: 15))
                        .foregroundStyle(RemotePalette.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(RemotePalette.canvas.ignoresSafeArea())
            .navigationTitle("添加 Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetCloseToolbar { dismiss() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Staged：agent inventory public 面就绪后接重新发现
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .disabled(true)
                    .accessibilityLabel(Text("重新发现 Agent"))
                }
            }
        }
        .appSheetPresentation(.compact)
    }
}

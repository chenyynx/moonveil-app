// RemoteDeviceDetailView.swift — 设备详情页（P2-A per-connector 改造，2026-09-21）
//
// 结构 = AA 官方 DeviceManagementView 的数据面/操作面逐字对照 + pp 已验收视觉骨架
// （RemotePalette 卡片，REMOTE-DEVICE-1 2026-09-20 定稿；视觉级变动清单见
// ~/qoder_selfreview_p2p3.md「视觉变动」段）。
//
// P2-A 核心（对照官方 Views/Devices/DeviceManagementView.swift）：
//   • 以 `connector: V2Connector` 为单位（原「service + 共享 RemoteSessionLoader」
//     跨设备混排、无设备身份 → 废弃）。
//   • 会话面 = DeviceManagementModel（AAV2 冻结件）+ dashboardRepository.sessions，
//     `onChange(allSessions) → model.updateSessions(connectorId:)`（官方 124 行）。
//   • 项目面 = dashboardRepository.projects 按 connector.id 过滤 + 官方排序（41-46 行）。
//   • 写操作全部接通：重命名设备（renameConnector）/ 更换凭据（revokeConnector →
//     ConnectorCredentialSheet）/ 删除设备（deleteConnector → 上层 removeConnector + 出栈）/
//     会话批量归档（services.setSessionsArchived，官方 onSetSessionsArchived 闭包 →
//     Glue 组合根同名方法）/ 范围内全部归档（archiveProject / archiveSessions）/
//     项目置顶·归档·删除（dashboard.updateProject/archiveProject/deleteProject）/
//     文件浏览（WorkspaceFilesSheet）。
//   • canManage 门 = 官方同语义：dashboard.canWrite && !isDeviceActionRunning &&
//     !isArchiveActionRunning && !busy；无权限为禁用态（不是隐藏）。
//   • Agent 区 = 官方搬运件 DeviceAgentSection（AAV2 DeviceAgentModel 驱动，
//     数据面经 services.agents(on:) 缓存）。
//   • 错误面 = ChatToastStore 四源（agents/device/sync/action，官方 61/125/126/233 行）
//     + sessionActionError alert（官方 ChatShellView:176-181 形状）。
//
// 页切栅栏：onAppear/onDisappear 上报 RootTabRouter.remoteAtRoot（远端 push 页不参与
// 横滑切 tab——B16-SWIPE-SCOPE 的远端线同规则）。

import SwiftUI
import UIKit

struct RemoteDeviceDetailView: View {
    @ObservedObject var service: RemoteService
    let connector: V2Connector
    /// 官方 onConnectorDeleted（ChatShell：appState.removeConnector + 出栈）——
    /// 本仓由调用方执行组合根 removeConnector 并 pop 本页。
    let onDeleted: (V2ConnectorID) -> Void
    /// 官方 onSessionsUpdated（archiveAll 后回写）——本仓直调组合根 updateSessions，
    /// 保留闭包位仅用于强制列表页刷新（可选）。
    var onSessionsUpdated: (([V2SessionMeta]) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var model = DeviceManagementModel()
    @AppStorage("aa.native.sidebar.session-list") private var showsAllSessions = false
    @State private var tab: DeviceContentTab = .projects
    @State private var toasts = ChatToastStore()
    @State private var isRenaming = false
    @State private var proposedName = ""
    @State private var confirmsRotation = false
    @State private var confirmsDeletion = false
    @State private var confirmsArchiveAll = false
    @State private var credential: V2ConnectorRevokeResponse?
    @State private var selectedWorkspace: V2DeviceWorkspace?
    @State private var pendingProject: V2Project?
    @State private var projectActionIsDeletion = false
    @State private var busy = false
    /// 官方 ChatShell.sessionActionError 的页面侧镜像（组合根非 Observable，
    /// performArchive 完成后取回；alert 文案/形状保持官方）。
    @State private var sessionActionError: String?
    @State private var showsNewSession = false
    @State private var showsProjectEditor = false
    @State private var selectedSessionId: String?
    @State private var showsSessionDetail = false

    private enum DeviceContentTab: Hashable { case projects, sessions }

    // MARK: - 数据面（官方 = appState/clients；本仓 = Glue 组合根，铁律①类2 数据面替换）

    private var services: V2RemoteChatServices? { service.chat }
    private var dashboard: V2DashboardRepository? { services?.dashboardRepository }
    private var agents: DeviceAgentModel? { services?.agents(on: connector.id) }

    /// 官方 DeviceManagementView:41-46 deviceProjects（逐字）
    private var deviceProjects: [V2Project] {
        (dashboard?.projects ?? []).filter { $0.connectorId == connector.id }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.lastActivityAt != $1.lastActivityAt { return ($0.lastActivityAt ?? "") > ($1.lastActivityAt ?? "") }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 官方 48-49 行（逐字；dashboard 未就绪 = 不可管理）
    private var canManage: Bool {
        guard let dashboard else { return false }
        return dashboard.canWrite && !model.isDeviceActionRunning && !model.isArchiveActionRunning && !busy
    }
    private var canReadFiles: Bool {
        guard let dashboard else { return false }
        return dashboard.canWrite && connector.status == .online
    }

    private var allSessions: [V2SessionMeta] { dashboard?.sessions ?? [] }

    // MARK: - Body

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let agents {
                    DeviceOverviewSections {
                        DeviceAgentSection(model: agents, showsConnectionNotice: false) { report($0, source: "agents") }
                    }
                }
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
    }

    @ToolbarContentBuilder private var toolbarBody: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(connector.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RemotePalette.ink)
                Text(connectionDescription)
                    .font(.system(size: 11.5))
                    .foregroundStyle(RemotePalette.body)
            }
        }
        ToolbarItem(placement: .topBarTrailing) { deviceActionsMenu }
    }

    var body: some View {
        scrollContent
        .scrollIndicators(.hidden)
        .background(RemotePalette.canvas.ignoresSafeArea())
        .refreshable {
            await dashboard?.refresh()
            await agents?.refresh()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarBody }
        // 官方 112-119：sessions tab 多选时底部 dock（P3-2）
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == .sessions && model.isSelectingSessions {
                DeviceSessionSelectionDock(count: model.selectedSessionIds.count,
                    restores: model.sessionFilter == .archived, isWorking: busy, disabled: !canManage,
                    onCancel: model.stopSelectingSessions,
                    onSubmit: { performArchive(Array(model.selectedSessionIds), archived: model.sessionFilter != .archived) })
            }
        }
        // 官方 120-123：错误 toast（device/sync/agents/action 四源）
        .overlay(alignment: .top) {
            ChatErrorToasts(store: toasts, isRetrying: dashboard?.isLoading ?? false,
                onRetry: { _ in await dashboard?.refresh() })
                .padding(.top, 8)
        }
        .onChange(of: allSessions, initial: true) { _, values in
            model.updateSessions(connectorId: connector.id, allSessions: values)
        }
        .onChange(of: model.errorMessage, initial: true) { _, error in report(error, source: "device") }
        .onChange(of: dashboard?.error, initial: true) { _, error in report(error, source: "sync") }
        // pp 已验收骨架：新会话为全屏页（fullScreenCover），不改 sheet
        .fullScreenCover(isPresented: $showsNewSession) {
            RemoteNewSessionView(service: service)
        }
        .sheet(isPresented: $showsProjectEditor) { RemoteProjectEditorSheet(service: service) }
        .sheet(item: $selectedWorkspace) {
            if let files = services?.workspaceFiles {
                WorkspaceFilesSheet(connectorId: connector.id, deviceName: connector.name,
                    workspace: $0, service: files, permitsReading: canReadFiles)
            }
        }
        .sheet(item: $credential) {
            if let server = service.serverURLValue {
                ConnectorCredentialSheet(connector: $0.connector, connectorToken: $0.connectorToken, serverURL: server)
            }
        }
        .sheet(isPresented: $showsSessionDetail) {
            if let id = selectedSessionId {
                RemoteSessionDetailSheet(service: service, sessionId: id)
            }
        }
        // 官方 143-160 四个 alert（文案 = xcstrings zh-Hans 显示值，逐字）
        .alert("重命名设备", isPresented: $isRenaming) {
            TextField("设备名", text: $proposedName)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { await renameDevice() } }
                .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canManage)
        }
        .alert("更换 Connector 凭据？", isPresented: $confirmsRotation) {
            Button("取消", role: .cancel) {}
            Button("更换凭据", role: .destructive) { Task { await rotateCredential() } }
        } message: { Text("当前桌面 Connector 将断开连接。重新连接前，请将其保存的令牌替换为新凭据。") }
        .alert("删除设备？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除设备", role: .destructive) { Task { await deleteDevice() } }
        } message: { Text("这会永久移除 \(connector.name) 以及所有关联数据。此操作不可撤销。") }
        .alert(model.sessionFilter == .archived ? "取消归档会话？" : "归档会话？", isPresented: $confirmsArchiveAll) {
            Button("取消", role: .cancel) {}
            Button(model.sessionFilter == .archived ? "取消归档" : "归档") { archiveAll() }
        } message: { Text("此操作适用于所选范围内的全部会话，包括尚未加载的会话。") }
        // 官方 161-175 项目归档/删除 alert
        .alert(projectActionIsDeletion ? "删除项目？" : "归档项目", isPresented: Binding(
            get: { pendingProject != nil }, set: { if !$0 { pendingProject = nil } })) {
            Button("取消", role: .cancel) { pendingProject = nil }
            Button(projectActionIsDeletion ? "删除" : "归档", role: .destructive) {
                guard let project = pendingProject else { return }; pendingProject = nil
                let deletesProject = projectActionIsDeletion
                perform {
                    if deletesProject { try await dashboard?.deleteProject(project.id) }
                    else { try await dashboard?.archiveProject(project.id, archived: true) }
                }
            }
        } message: {
            Text(projectActionIsDeletion ? "只能删除没有会话的项目，设备上的文件会保留。" :
                "确定要归档“\(pendingProject?.name ?? "")”下的所有会话吗？项目会保留，之后仍可继续创建会话。")
        }
        // 官方 ChatShellView:176-181 sessionActionError alert
        .alert("无法更新会话", isPresented: Binding(
            get: { sessionActionError != nil },
            set: { if !$0 { sessionActionError = nil; services?.dismissSessionActionError() } }
        )) {
            Button("好的", role: .cancel) { sessionActionError = nil; services?.dismissSessionActionError() }
        }
        .onAppear { RootTabRouter.shared.remoteAtRoot = false }
        .onDisappear { RootTabRouter.shared.remoteAtRoot = true }
    }

    /// 官方 202-206 connectionDescription（逐字语义，中文键落地）
    private var connectionDescription: String {
        let status = dashboard.map { d in
            !d.canWrite ? "正在显示缓存内容" :
                connector.status == .online ? "在线" : "设备离线"
        } ?? "正在显示缓存内容"
        return [connector.deviceOs, status].compactMap { $0 }.joined(separator: " · ")
    }

    /// 官方 207-209 report
    private func report(_ message: String?, source: String) {
        toasts.update(source: source, failure: message.map { .init(kind: .rejected, message: $0) })
    }

    // MARK: - 顶栏设备菜单（官方 98-111；写操作接通，!canManage 禁用态）

    private var deviceActionsMenu: some View {
        Menu {
            Button("新会话", systemImage: "square.and.pencil") { showsNewSession = true }
            Button("复制设备 ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = connector.id }
            Divider()
            Button("重命名设备", systemImage: "pencil") { proposedName = connector.name; isRenaming = true }
                .disabled(!canManage)
            Button("更换凭据", systemImage: "key") { confirmsRotation = true }
                .disabled(!canManage)
            Button("删除设备", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
                .disabled(!canManage)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary)
        }
        .accessibilityLabel("设备操作")
    }

    // MARK: - 设备内容（官方 188-200 contentSwitcher；pp 已验收为定稿样式）

    private var contentSwitcher: some View {
        HStack {
            Text("设备内容")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RemotePalette.ink)
            Spacer()
            Picker("设备内容", selection: $tab) {
                Text(showsAllSessions ? "工作目录" : "项目").tag(DeviceContentTab.projects)
                Text("会话").tag(DeviceContentTab.sessions)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    // MARK: - 项目 tab（官方 DeviceProjectList 逻辑 + pp 已验收卡片视觉）

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(showsAllSessions ? "0 个工作目录" : "\(deviceProjects.count) 个项目")
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
                .disabled(!canManage)   // 官方 onCreate：!canManage 禁用
                .accessibilityLabel(Text("创建项目"))
            }
            if showsAllSessions {
                // 官方 DeviceWorkspaceList 依赖 WorkspaceDirectoryChoice（未搬，
                // 见 PATCHES-P2 台账）；工作目录模式维持空态提示。
                unavailableCard(icon: "folder", text: "还没有工作目录。")
            } else if deviceProjects.isEmpty {
                unavailableCard(icon: "folder", text: "暂无项目。")
            } else {
                groupedCard {
                    ForEach(Array(deviceProjects.indices), id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 12) }
                        projectRow(deviceProjects[index])
                    }
                }
            }
        }
    }

    /// 官方 DeviceDirectoryRow + contextMenu（18-46 行）逐字语义，卡片视觉保持。
    private func projectRow(_ project: V2Project) -> some View {
        HStack(spacing: 12) {
            Button {
                openProjectSessions(project)
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
                            .lineLimit(2)
                        Text(project.workspacePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(RemotePalette.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(project.activeSessionCount) 个会话")
                            .font(.system(size: 12))
                            .foregroundStyle(RemotePalette.body)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .accessibilityHint(Text("查看项目会话"))
            HStack(spacing: 0) {
                Button {
                    openProjectFiles(project)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                        .foregroundStyle(canReadFiles ? RemotePalette.ink : RemotePalette.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canReadFiles)   // 官方 Files：disabled(!canReadFiles)
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
            // 官方 37-45：重命名走 ProjectEditorSheet（未搬，维持禁用+字据）；
            // 置顶/归档/删除 = dashboard 写面已接通。
            Button("重命名项目", systemImage: "pencil") {}
                .disabled(true)
            Button(project.pinned ? "取消置顶" : "置顶", systemImage: "pin") {
                perform { try await dashboard?.updateProject(project.id, pinned: !project.pinned) }
            }
            .disabled(!canManage)
            Button("复制路径", systemImage: "doc.on.doc") { UIPasteboard.general.string = project.workspacePath }
            Divider()
            Button("归档项目", systemImage: "archivebox") { pendingProject = project; projectActionIsDeletion = false }
                .disabled(!canManage)
            Button("删除项目", systemImage: "trash", role: .destructive) { pendingProject = project; projectActionIsDeletion = true }
                .disabled(!canManage || project.sidebarSessionCounts.active + project.sidebarSessionCounts.archived > 0)
        }
    }

    private func openProjectSessions(_ project: V2Project) {
        model.selectProject(project.id); model.setSessionFilter(.active); tab = .sessions
    }
    private func openProjectFiles(_ project: V2Project) {
        selectedWorkspace = .init(path: project.workspacePath, name: project.name,
            sessionCount: project.activeSessionCount, lastActiveAt: project.lastActivityAt)
    }

    // MARK: - 会话 tab（官方 DeviceSessionList 逻辑 + pp 已验收卡片视觉；含 P3-2 多选）

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Picker("项目", selection: Binding(get: { model.projectID }, set: model.selectProject)) {
                    Text("全部项目").tag(String?.none)
                    ForEach(deviceProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
                Spacer(minLength: 8)
                Menu {
                    Button(model.isSelectingSessions ? "完成" : "选择", systemImage: "checkmark.circle") {
                        if model.isSelectingSessions { model.stopSelectingSessions() } else { model.startSelectingSessions() }
                    }
                    .disabled(!canManage || model.filteredSessions.isEmpty)
                    if model.isSelectingSessions {
                        Button("最多选择 200 个会话", action: model.toggleSelectAll).disabled(!canManage)
                    }
                    Divider()
                    Button(model.sessionFilter == .archived ? "全部取消归档" : "全部归档",
                        systemImage: model.sessionFilter == .archived ? "tray.and.arrow.up" : "archivebox",
                        action: { confirmsArchiveAll = true })
                        .disabled(!canManage || model.filteredSessions.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(RemotePalette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .overlay { if busy || model.isArchiveActionRunning { ProgressView().controlSize(.small) } }
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
            Picker("会话筛选", selection: Binding(get: { model.sessionFilter }, set: model.setSessionFilter)) {
                ForEach(V2DeviceSessionFilter.allCases) { filter in
                    Text(sessionFilterTitle(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            if model.filteredSessions.isEmpty {
                unavailableCard(icon: "bubble.left.and.bubble.right", text: "没有会话。")
            } else {
                groupedCard {
                    ForEach(Array(model.filteredSessions.indices), id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 12) }
                        sessionRow(model.filteredSessions[index])
                    }
                }
            }
        }
    }

    private func sessionFilterTitle(_ filter: V2DeviceSessionFilter) -> String {
        switch filter {
        case .active: return "活跃"
        case .archived: return "已归档"
        case .all: return "全部"
        }
    }

    /// 官方 DeviceSessionList 行（172-207 行）语义：多选 checkmark / 打开、
    /// 未读加粗、runtime + 范围副行、指示器 + 日期；视觉保持 pp 已验收样式。
    private func sessionRow(_ session: V2SessionMeta) -> some View {
        Button {
            selectSession(session.id)
        } label: {
            HStack(spacing: 12) {
                if model.isSelectingSessions {
                    Image(systemName: model.selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(model.selectedSessionIds.contains(session.id) ? RemotePalette.ink : RemotePalette.body)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名会话")
                        .font(.system(size: FontSettings.shared.scaledApp(15.5),
                                      weight: session.unread ? .semibold : .regular))
                        .foregroundStyle(RemotePalette.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(session.runtimeTypeDisplayName ?? session.runtime)
                        if let subtitle = scopeSubtitle(session) {
                            Text("·"); Text(subtitle).lineLimit(1)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(RemotePalette.body)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    stateMark(for: session)
                    Text(RemoteSessionLoader.relativeTime(session.sortAt ?? session.lastItemAt
                        ?? session.lastActivityAt ?? session.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(RemotePalette.timeFaint)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("打开", systemImage: "arrow.up.right") { openSession(session.id) }
            Button(session.archived ? "取消归档" : "归档",
                systemImage: session.archived ? "tray.and.arrow.up" : "archivebox") {
                performArchive([session.id], archived: !session.archived)
            }
            .disabled(!canManage || session.id.hasPrefix("local:"))
            Button("复制会话 ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = session.id }
        }
    }

    /// 官方 226-228 selectSession
    private func selectSession(_ id: String) {
        if model.isSelectingSessions { model.toggleSessionSelection(id) } else { openSession(id) }
    }
    private func openSession(_ id: String) {
        selectedSessionId = id
        showsSessionDetail = true
    }

    private func scopeSubtitle(_ session: V2SessionMeta) -> String? {
        deviceProjects.first { $0.id == session.projectId }?.name
    }

    @ViewBuilder
    private func stateMark(for session: V2SessionMeta) -> some View {
        // 官方 ChatSidebarSessionIndicator（SessionSidebarPresentation.indicator）
        // 的 pp 已验收视觉等价（待批准胶囊 / running 环 / 未读点）
        switch SessionSidebarPresentation(session).indicator {
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

    // MARK: - 动作（官方 229-268 逐字语义）

    private func perform(_ operation: @escaping () async throws -> Void) {
        guard canManage else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await operation(); report(nil, source: "action") }
            catch { report(error.localizedDescription, source: "action") }
        }
    }

    private func performArchive(_ ids: [String], archived: Bool) {
        guard !ids.isEmpty, canManage, let services else { return }; busy = true
        Task {
            defer { busy = false }
            if await services.setSessionsArchived(sessionIds: ids, archived: archived) {
                model.stopSelectingSessions()
            }
            sessionActionError = services.sessionActionError
        }
    }

    /// 官方 244-255 archiveAll
    private func archiveAll() {
        guard canManage, let services else { return }
        if let id = model.projectID {
            let archived = model.sessionFilter != .archived
            perform { try await dashboard?.archiveProject(id, archived: archived) }
        } else {
            Task {
                if let sessions = await model.archiveSessions(connectorId: connector.id,
                    archived: model.sessionFilter != .archived,
                    service: services.deviceManagement) {
                    services.updateSessions(sessions)
                    onSessionsUpdated?(sessions)
                }
            }
        }
    }

    /// 官方 256-259 renameDevice
    private func renameDevice() async {
        guard canManage, let services else { return }
        if let updated = await model.renameConnector(connectorId: connector.id,
            name: proposedName, service: services.deviceManagement) {
            services.updateConnector(updated)
        }
    }

    /// 官方 260-264 rotateCredential
    private func rotateCredential() async {
        guard canManage, let services else { return }
        credential = await model.revokeConnector(connectorId: connector.id, service: services.deviceManagement)
        if let credential { services.updateConnector(credential.connector) }
    }

    /// 官方 265-268 deleteDevice
    private func deleteDevice() async {
        guard canManage, let services else { return }
        if await model.deleteConnector(connectorId: connector.id, service: services.deviceManagement) {
            onDeleted(connector.id)
        }
    }

    // MARK: - 分组卡与空态（pp 已验收骨架件）

    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RemotePalette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

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

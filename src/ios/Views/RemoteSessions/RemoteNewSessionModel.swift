// RemoteNewSessionModel.swift — 新会话页的数据模型（AA 官方 NewSessionModel
// 的等价物；数据面走 RemoteService public facade，零第二 schema）。
//
// 行为对齐此前的 Form 版弹窗（已验证过的加载/提交语义——并行拉设备与项目、
// 离线设备不发 runtimeTypes、默认选第一台在线设备 + recommended 运行时、
// gate = 设备在线 + 项目 + 运行时 + 内容非空）：
//   • refreshRuntimes 的代际令牌防快速切设备时后发先至串台（同旧实现）。
//   • 提交走 startSession；成功回调 sessionId（由页面 dismiss 回列表）。

import SwiftUI

@MainActor
final class RemoteNewSessionModel: ObservableObject {
    // 设备
    @Published private(set) var connectors: [RemoteConnector] = []
    @Published private(set) var connectorsLoaded = false
    @Published private(set) var connectorsError: String?
    @Published var selectedConnectorId: String?
    // 项目（listProjects 全量，按所选设备本地过滤）
    @Published private(set) var projects: [RemoteProject] = []
    @Published private(set) var projectsLoaded = false
    @Published private(set) var projectsError: String?
    @Published var selectedProjectId: String?
    // 运行时（按设备拉取，只列 available）
    @Published private(set) var runtimes: [RemoteRuntimeType] = []
    @Published private(set) var runtimesLoaded = false
    @Published private(set) var runtimesError: String?
    @Published var selectedRuntimeType: String?
    /// 运行时拉取代际令牌：快速切换设备时丢弃过期响应。
    private var runtimeLoadToken = 0
    // 家目录解析（官方 NewSessionModel.resolveHome 语义；files service 现接）
    @Published private(set) var homePaths: [String: String] = [:]
    @Published private(set) var loadingHomes: Set<String> = []
    private var resolvedHomes: Set<String> = []
    /// 手动选择的工作目录（官方 model.workspace：非项目路径，如 Home 目录）。
    @Published private(set) var manualWorkspacePath: String?

    /// 当前设备的家目录（解析后；官方 homePath）。
    var homePath: String? { selectedConnectorId.flatMap { homePaths[$0] } }

    /// 官方的 isPreparing（目标准备中）在本仓的等价：选中设备后正在拉取
    /// 运行时清单（targetButton 的转圈指示）。
    var isPreparing: Bool { selectedConnector != nil && !runtimesLoaded }

    /// 当前工作目录是否 = 家目录（官方 isHome）。
    var isHome: Bool {
        guard let homePath, !workspacePath.isEmpty else { return false }
        return workspacePath == homePath
    }
    // 草稿与提交（官方 ComposerDraft：编辑器持有 marked-text 状态，账号/会话持有草稿生命周期）
    let draft = ComposerDraft()
    @Published private(set) var isCreating = false
    @Published private(set) var error: String?

    // 对话选项（官方 ConversationSettings + prepareTarget 快照）
    let settings = ConversationSettings()
    @Published private(set) var settingsLoading = false
    @Published private(set) var settingsError: String?
    @Published private(set) var prepared = false
    @Published private(set) var allowsAttachment = false
    @Published private(set) var allowsModelCatalog = false
    @Published private(set) var allowsPermissionCatalog = false
    private var savedSelections: [V2RuntimeSelectionScope: V2SelectionID] = [:]
    private var prepareToken = 0

    // MARK: - 派生

    var selectedConnector: RemoteConnector? {
        connectors.first { $0.id == selectedConnectorId }
    }

    var availableProjects: [RemoteProject] {
        guard let connectorId = selectedConnectorId else { return [] }
        return projects.filter { $0.connectorId == connectorId }
    }

    var selectedProject: RemoteProject? {
        availableProjects.first { $0.id == selectedProjectId }
    }

    var selectedRuntime: RemoteRuntimeType? {
        runtimes.first { $0.runtimeType == selectedRuntimeType }
    }

    private var trimmedContent: String {
        draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 官方 gate（NewSessionModel:171-176 的 remote 等价，无 network 监视）：
    /// 设备在线 + 工作目录已定 + 运行时就绪 + 准备完成 + 选择有效 + 草稿可发。
    /// （项目在 create 时由 resolver 解析——官方语义：home/任意目录可直接开始。）
    var canCreate: Bool {
        (selectedConnector?.isOnline ?? false)
            && !workspacePath.isEmpty
            && selectedRuntime != nil
            && prepared
            && !isCreating
            && !settingsLoading
            && settings.hasValidSelections
            && draft.canAttemptSend
            && (draft.attachments.isEmpty || canAttach)
    }

    /// 官方 canAttach：runtime 能力允许附件（prepare 快照门控）。
    var canAttach: Bool { allowsAttachment }

    /// 工作目录行显示名（官方 workspaceName）：项目名 → Home 目录 → 路径末段。
    var workspaceName: String {
        if let project = selectedProject { return project.name }
        let path = workspacePath
        if path.isEmpty || path == homePath { return "Home 目录" }
        return ProjectWorkspacePath.name(path)
    }

    /// 工作目录路径：手动选择（Home/任意目录）→ 项目路径 → 空。
    var workspacePath: String {
        manualWorkspacePath ?? selectedProject?.workspacePath ?? ""
    }

    /// 顶栏目标胶囊：运行时显示名 · 设备名。
    var targetRuntimeName: String {
        selectedRuntime?.displayName ?? "运行目标"
    }
    var targetDeviceName: String {
        selectedConnector?.name ?? "新设备"
    }

    // MARK: - 状态行（官方 connectionStatus 等价，按可达性排序）

    enum ConnectionStatus {
        case loadingDevices
        case noDevices(error: String?)
        case deviceOffline
        case loadingAgent
        case noAgents
        case agentNotReady

        var title: String {
            // 全部为官方 zh-Hans 显示值（key ≠ 显示值的已按 xcstrings 实际值）。
            switch self {
            case .loadingDevices: "加载设备中..."
            case .noDevices: "当前没有在线设备"
            case .deviceOffline: "目标设备离线"
            case .loadingAgent: "正在发现…"
            case .noAgents: "还没有配置 Runtime。"
            case .agentNotReady: "选择代理"
            }
        }
        var detail: String {
            switch self {
            case .loadingDevices: ""
            case .noDevices(let error): error ?? "添加设备后才能选择项目或开始会话。"
            case .deviceOffline: "等待它重新连接，或选择其他在线设备。草稿会继续保留。"
            case .loadingAgent: ""
            case .noAgents: "可在设备管理中配置或启动实例。"
            case .agentNotReady: "可在设备管理中配置或启动实例。"
            }
        }
        var icon: String {
            switch self {
            case .loadingDevices: "desktopcomputer"
            case .noDevices: "desktopcomputer"
            case .deviceOffline: "bolt.horizontal.circle"
            case .loadingAgent: "desktopcomputer"
            case .noAgents: "sparkle"
            case .agentNotReady: "sparkle"
            }
        }
        var showsSpinner: Bool {
            switch self { case .loadingDevices, .loadingAgent: true; default: false }
        }
    }

    var connectionStatus: ConnectionStatus? {
        if !connectorsLoaded && connectors.isEmpty { return .loadingDevices }
        if connectors.isEmpty { return .noDevices(error: connectorsError) }
        if let c = selectedConnector, !c.isOnline { return .deviceOffline }
        if !runtimesLoaded { return .loadingAgent }
        if runtimes.isEmpty { return .noAgents }
        if let r = selectedRuntime, !r.available { return .agentNotReady }
        return nil
    }

    // MARK: - 加载（设备与项目并行；runtimes 挂默认选中链路）

    func load(service: RemoteService) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadConnectors(service: service) }
            group.addTask { await self.loadProjects(service: service) }
        }
    }

    /// 刷新（下拉刷新 / 「重新连接」）：重拉设备、项目与当前设备的运行时。
    func refresh(service: RemoteService) async {
        await load(service: service)
        if let id = selectedConnectorId,
           let connector = connectors.first(where: { $0.id == id }) {
            await refreshRuntimes(for: connector, service: service)
        }
    }

    private func loadConnectors(service: RemoteService) async {
        connectorsLoaded = false
        connectorsError = nil
        do {
            connectors = try await service.listConnectors()
            if selectedConnectorId == nil {
                // 默认选第一台在线设备（无在线则第一台，离线态有诚实提示）
                let preferred = connectors.first(where: { $0.isOnline }) ?? connectors.first
                if let preferred {
                    selectedConnectorId = preferred.id
                    await refreshRuntimes(for: preferred, service: service)
                }
            }
        } catch {
            connectorsError = error.localizedDescription
        }
        connectorsLoaded = true
        // 官方 load 链：async let home: Void = resolveHome()
        await resolveHome(service: service)
    }

    private func loadProjects(service: RemoteService) async {
        projectsLoaded = false
        projectsError = nil
        do {
            projects = try await service.listProjects()
        } catch {
            projectsError = error.localizedDescription
        }
        projectsLoaded = true
    }

    /// 离线设备不发 runtimeTypes（服务器必然报错）——置空态，提交 gate 本就锁离线。
    func refreshRuntimes(for connector: RemoteConnector, service: RemoteService) async {
        guard connector.isOnline else {
            runtimeLoadToken += 1   // 作废在途请求
            runtimes = []
            selectedRuntimeType = nil
            runtimesError = nil
            runtimesLoaded = true
            return
        }
        runtimeLoadToken += 1
        let token = runtimeLoadToken
        runtimesLoaded = false
        runtimesError = nil
        runtimes = []
        selectedRuntimeType = nil
        let fetched: [RemoteRuntimeType]
        do {
            fetched = try await service.runtimeTypes(connectorId: connector.id)
        } catch {
            if token == runtimeLoadToken {
                runtimesError = error.localizedDescription
                runtimesLoaded = true
            }
            return
        }
        guard token == runtimeLoadToken else { return }   // 过期响应丢弃
        runtimes = fetched.filter { $0.available }
        // 默认选 recommended；无 recommended 则第一个 available
        selectedRuntimeType = (runtimes.first(where: { $0.recommended }) ?? runtimes.first)?.runtimeType
        runtimesLoaded = true
        // 官方 load 链：选中 runtime 后 prepare（catalogs / capabilities）
        await prepareTarget(service: service)
    }

    /// 官方 NewSessionModel.prepareTarget 的 remote 等价：runtime 准备快照
    /// （状态 + capabilities + catalog）→ settings.replace。
    func prepareTarget(service: RemoteService) async {
        prepareToken += 1
        let version = prepareToken
        prepared = false
        if !isCreating { error = nil }
        guard let connector = selectedConnector, connector.isOnline,
              let runtimeType = selectedRuntimeType else { return }
        settingsLoading = true
        defer { if version == prepareToken { settingsLoading = false } }
        do {
            let value = try await service.prepareSession(connectorId: connector.id, runtimeType: runtimeType)
            guard version == prepareToken, !Task.isCancelled else { return }
            prepared = true
            allowsAttachment = value.allowsAttachment
            allowsModelCatalog = value.allowsModelCatalog
            allowsPermissionCatalog = value.allowsPermissionCatalog
            settingsError = value.isReadyForSession ? nil : value.unavailableReason
            settings.replace(ChatSettingsCatalog(value.catalog), selections: savedSelections)
        } catch {
            guard version == prepareToken else { return }
            settingsError = error.localizedDescription
        }
    }

    /// 官方 saveSelections：选择持久化（本批内存保存，persist 随后续批）。
    func saveSelections() {
        savedSelections = settings.selections
    }

    /// 官方 NewSessionModel.resolveHome：files.directory(root: "~", path: ".")
    /// 解析设备家目录；成功后作为默认工作目录（未选项目/无手动路径时兜底）。
    func resolveHome(service: RemoteService) async {
        guard let device = selectedConnectorId,
              let connector = selectedConnector, connector.isOnline,
              !resolvedHomes.contains(device) else { return }
        loadingHomes.insert(device)
        defer { loadingHomes.remove(device) }
        do {
            let directory = try await service.workspaceDirectory(connectorId: device, root: "~", path: ".")
            guard directory.targetType == nil || directory.targetType == "directory",
                  !directory.path.isEmpty else { return }
            homePaths[device] = directory.path
            resolvedHomes.insert(device)
            // 官方：workspace 无效时用 home 兜底（本仓：未选项目且无手动路径）。
            if manualWorkspacePath == nil, selectedProjectId == nil {
                manualWorkspacePath = directory.path
            }
        } catch {
            // 官方 homeErrors[device] 记录；homeRow 保持"正在解析"占位（不假造）。
        }
    }

    func selectConnector(_ connector: RemoteConnector, service: RemoteService) async {
        guard connector.id != selectedConnectorId else { return }
        selectedConnectorId = connector.id
        // 所选项目必须属于新设备，否则清空（含项目已删除的悬空 id）
        if let sid = selectedProjectId,
           projects.first(where: { $0.id == sid })?.connectorId != connector.id {
            selectedProjectId = nil
        }
        // 手动工作目录属于旧设备语义——清空后由新设备的 home 兜底
        manualWorkspacePath = nil
        await refreshRuntimes(for: connector, service: service)
        await resolveHome(service: service)
    }

    func selectProject(_ project: RemoteProject) {
        selectedProjectId = project.id
        manualWorkspacePath = nil
    }

    /// 官方 selectWorkspace：把工作目录设为任意路径（如 Home 目录）。
    @discardableResult
    func selectWorkspace(_ path: String) -> Bool {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        manualWorkspacePath = path
        selectedProjectId = nil
        return true
    }

    // MARK: - 目标选择（SessionTargetSheet 应用入口）

    /// 官方 selectTarget 等价的本地版：切设备 + 选 Agent，成功返回 true。
    func selectTarget(connectorId: String, runtimeType: String, service: RemoteService) async -> Bool {
        if let connector = connectors.first(where: { $0.id == connectorId }),
           connector.id != selectedConnectorId {
            await selectConnector(connector, service: service)
        }
        guard runtimes.contains(where: { $0.runtimeType == runtimeType && $0.available }) else {
            return false
        }
        selectedRuntimeType = runtimeType
        return true
    }

    // MARK: - 创建（官方 onSend 语义；成功返回 sessionId）

    /// 官方 `NewSessionModel.restoreCreationDraft` 的 facade 等价物：从已发回合
    /// 回填草稿（文本 + 附件），并把目标聚焦到原会话的设备/工作目录。
    ///
    /// 与官方的差异（全部留据）：
    ///   • 官方目标聚焦是 `focusDevice + selectProject + runtimeID` 同步设值；
    ///     本仓 facade 的 connector/runtime 清单是异步加载的，这里只先落
    ///     `selectedConnectorId`/`manualWorkspacePath`（同步可用部分），设备
    ///     清单到齐后 `refresh` 会自然收敛——跳页后用户看到的就是
    ///     已聚焦 + 草稿已回填的状态。
    ///   • 官方 `creationUncertain`（发送结果未定）分支：pending.delivery ==
    ///     .uncertain 时官方会提示先查会话列表；本仓 facade 无创建中态模型，
    ///     不实现该提示，草稿照常回填。
    func restoreCreationDraft(connectorId: String, workspacePath: String?,
                              projectId: String?, runtimeType: String?,
                              text: String, attachments: [ChatAttachment]) {
        // 官方草稿冲突守卫：已有其他草稿则保留原草稿并提示，不覆盖。
        if (!draft.text.isEmpty || !draft.attachments.isEmpty),
           draft.text != text || draft.attachments.map(\.id) != attachments.map(\.id) {
            error = String(localized: "新会话中已有其他草稿，已为你保留。请先处理该草稿，再返回这条发送记录。")
            return
        }
        // 目标聚焦（同步可落的部分；异步清单由 refresh 收敛）
        selectedConnectorId = connectorId
        if let projectId { selectedProjectId = projectId; manualWorkspacePath = nil }
        else if let workspacePath, !workspacePath.isEmpty { _ = selectWorkspace(workspacePath) }
        if let runtimeType { selectedRuntimeType = runtimeType }
        // 草稿回填
        draft.text = text
        draft.attachments = attachments
    }

    func create(text: String, service: RemoteService) async -> String? {
        guard canCreate,
              let connector = selectedConnector,
              let runtime = selectedRuntimeType
        else { return nil }
        draft.text = text
        guard draft.canAttemptSend else { return nil }
        let files = draft.attachments
        isCreating = true
        error = nil
        saveSelections()
        defer { isCreating = false }
        do {
            // 官方 V2WorkspaceProjectResolver：工作目录 resolve 成项目（没有即创建
            // ——home / 任意目录模式由此成立；服务端 projectId 必填非空）。
            let project = try await resolveProject(
                connectorId: connector.id, path: workspacePath,
                deviceOS: connector.deviceOs, service: service
            )
            let result = try await service.startSession(
                connectorId: connector.id,
                projectId: project.id,
                runtime: runtime,
                runtimeId: nil,
                title: nil,
                cwd: project.workspacePath.isEmpty ? nil : project.workspacePath,
                content: trimmedContent,
                clientMessageId: UUID().uuidString,
                selections: Dictionary(uniqueKeysWithValues: settings.selections.map { ($0.key.rawValue, $0.value) }),
                attachments: files.map { RemoteLocalAttachment(fileId: $0.id, name: $0.name, mediaType: $0.mediaType, data: $0.data) }
            )
            draft.clear()
            return result.sessionId
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// 官方 V2WorkspaceProjectResolver.resolve 的 remote 等价（本地匹配 → 拉新
    /// 列表匹配 → 创建；availableName 预避命名冲突）。
    private func resolveProject(connectorId: String, path: String, deviceOS: String?,
                                service: RemoteService) async throws -> RemoteProject {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !connectorId.isEmpty, ProjectWorkspacePath.key(trimmed, deviceOS: deviceOS) != nil else {
            throw RemoteServiceError.rejected(code: nil, message: "请输入设备上的完整绝对路径。")
        }
        if let existing = ProjectWorkspacePath.project(in: projects, connectorID: connectorId,
                                                       path: trimmed, deviceOS: deviceOS) {
            return existing
        }
        let fresh = (try? await service.listProjects()) ?? projects
        projects = fresh
        if let existing = ProjectWorkspacePath.project(in: fresh, connectorID: connectorId,
                                                       path: trimmed, deviceOS: deviceOS) {
            return existing
        }
        let created = try await service.createProject(
            connectorId: connectorId,
            workspacePath: trimmed,
            name: ProjectWorkspacePath.availableName(ProjectWorkspacePath.name(trimmed), projects: fresh),
            manuallyCreated: false
        )
        projects.append(created)
        return created
    }
}

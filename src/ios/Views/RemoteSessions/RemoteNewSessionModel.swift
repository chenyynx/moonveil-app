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
    // 草稿与提交
    @Published var text = ""
    @Published private(set) var isCreating = false
    @Published private(set) var error: String?

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
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 官方 gate：设备在线 + 选中项目 + 选中运行时 + 任务非空白；提交中锁死。
    var canCreate: Bool {
        (selectedConnector?.isOnline ?? false)
            && selectedProject != nil
            && selectedRuntime != nil
            && !trimmedContent.isEmpty
            && !isCreating
    }

    /// 工作目录行显示名：项目名 → 「Home 目录」（官方 workspaceName 语义）。
    var workspaceName: String {
        selectedProject?.name ?? "Home 目录"
    }

    /// 工作目录路径副行（未选项目 = 空，不假造）。
    var workspacePath: String {
        selectedProject?.workspacePath ?? ""
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
    }

    func selectConnector(_ connector: RemoteConnector, service: RemoteService) async {
        guard connector.id != selectedConnectorId else { return }
        selectedConnectorId = connector.id
        // 所选项目必须属于新设备，否则清空（含项目已删除的悬空 id）
        if let sid = selectedProjectId,
           projects.first(where: { $0.id == sid })?.connectorId != connector.id {
            selectedProjectId = nil
        }
        await refreshRuntimes(for: connector, service: service)
    }

    func selectProject(_ project: RemoteProject) {
        selectedProjectId = project.id
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

    func create(service: RemoteService) async -> String? {
        guard canCreate,
              let connector = selectedConnector,
              let project = selectedProject,
              let runtime = selectedRuntimeType
        else { return nil }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        isCreating = true
        error = nil
        defer { isCreating = false }
        do {
            let result = try await service.startSession(
                connectorId: connector.id,
                projectId: project.id,
                runtime: runtime,
                runtimeId: nil,
                title: nil,
                cwd: workspacePath.isEmpty ? nil : workspacePath,
                content: trimmedContent,
                clientMessageId: UUID().uuidString
            )
            return result.sessionId
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

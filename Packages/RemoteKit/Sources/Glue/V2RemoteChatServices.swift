import Foundation

/// Composition root for the remote chat line — verbatim mirror of official
/// `Business/V2ClientServices.swift` (origin-cache ios/…/Business/V2ClientServices.swift),
/// pruned to the members this app wires. Pruning ledger (each = official depends on a
/// construct this repo owns elsewhere, per 铁律①-class-2 "最小适配"):
/// - `newSession`/`onStaged`/`onBound`/`onFailed`/`onProjectResolved` callbacks:
///   new-session flow runs through app-layer RemoteNewSessionModel + facade
///   (NEWSESSION-* batches); no double owner for the same state.
/// - `agentSetup`/`agentModels`/`DeviceAgentModel`: pairing polling lives in
///   app-layer AgentSetupCoordinator; DeviceAgent wiring lands with P2.
/// - `sessionReads` (V2SessionReadCoordinator): wired via `setAppInBackground`
///   (official AppState:747-762); the scenePhase hook lives on the remote-line page
///   root (`RemoteSessionListView`) because the App root is the local line —
///   死隔离 forbids touching it. Same semantics, narrower host.
/// - `onSelectPage`/`editCreation`：navigation is NavigationStack-based here (no ChatShell
///   selection pages); `onReturnToNewSession` + `discardCreation` + `editCreation` together
///   carry what the chat page needs: `editCreation` hands the pending round's text +
///   attachments to the app-layer facade (`onEditCreation`), which restores the draft on
///   `RemoteNewSessionModel` and pops to the new-session page.
/// - `flushCache` + `setAppInBackground`: official calls these from
///   `AppState.setAppInBackground`, whose hook sits on the App root
///   (`AgentsAnywhereApp.swift:23` `.onChange(of: scenePhase)`). Our App root is
///   ContentView = 本机线, 死隔离 forbids touching it → the hook lives on the
///   remote-line page root (`RemoteSessionListView`) instead (2026-09-21 pp 方案 B).
///   Same semantics; agentSetup / accountSync / dashboardUpdatesTask are
///   AppState-owned elsewhere in this repo (pairing polling = AgentSetupCoordinator;
///   dashboard polling = RemoteSessionLoader), so this only carries the frozen
///   repo half: flushCache + sessionRepository suspend/resume + sessionReads.
/// Everything else (scope/localStore/repositories/services/connectivity wiring)
/// follows the official init verbatim.
@MainActor
final class V2RemoteChatServices {
    private let api: V2APIClient
    let connectivity = V2ConnectivityMonitor()
    var onConnectivityChange: ((V2NetworkStatus) -> Void)?
    let localStore: V2LocalStore
    let scope: V2ClientScope
    let sessionRepository: V2SessionRepository
    let sessionPreparation: V2SessionPreparationService
    let account: V2AccountService
    let dashboard: V2DashboardService
    let dashboardRepository: V2DashboardRepository
    let sessionDetail: V2SessionDetailService
    let sessionCreation: V2SessionCreationService
    let attachments: V2AttachmentService
    let interactions: V2RuntimeInteractionService
    let devicePairing: V2DevicePairingService
    let deviceManagement: V2DeviceManagementService
    let workspaceFiles: V2WorkspaceFilesService
    /// 官方 `services.sessionReads`（后台已读编排；setAppInBackground 的被管理方）。
    let sessionReads: V2SessionReadCoordinator
    /// 官方逐字（V2ClientServices:69）：per-connector 的 DeviceAgentModel 缓存。
    private var agentModels: [String: DeviceAgentModel] = [:]
    /// 官方 AppState:41（`@Published private(set) var sessionActionError`）——本仓
    /// 组合根即数据面宿主（AppState 的会话动作半段落这里，见 setSessionsArchived）。
    var sessionActionError: String?

    init(api: V2APIClient, accountID: String) {
        self.api = api
        scope = V2ClientScope(serverURL: api.serverURL, accountID: accountID)
        let cacheDirectory = URL.applicationSupportDirectory.appendingPathComponent("AgentsAnywhere/Offline/v1")
            .appendingPathComponent(V2RestorationStore.scopeKey(scope))
        localStore = V2LocalStore(directory: cacheDirectory)
        sessionPreparation = V2SessionPreparationService(connectorAPI: api.connectors)
        account = V2AccountService(accountAPI: api.account)
        dashboard = V2DashboardService(
            connectorAPI: api.connectors,
            projectAPI: api.projects,
            sessionAPI: api.sessions,
            realtimeAPI: api.realtime
        )
        dashboardRepository = V2DashboardRepository(service: dashboard, localStore: localStore, scope: scope)
        sessionDetail = V2SessionDetailService(
            sessionAPI: api.sessions,
            runtimeAPI: api.runtime,
            realtimeAPI: api.realtime
        )
        // 官方 V2ClientServices:44-48：构造时注入 markRead 发送闭包
        sessionReads = V2SessionReadCoordinator { id in
            let response = try await api.sessions.markRead(sessionIds: [id])
            guard let receipt = response.sessions.first(where: { $0.id == id }) else { throw HTTPError.invalidResponse }
            return receipt
        }
        sessionCreation = V2SessionCreationService(sessionAPI: api.sessions)
        attachments = V2AttachmentService(attachmentAPI: api.attachments)
        interactions = V2RuntimeInteractionService(runtimeAPI: api.runtime)
        sessionRepository = V2SessionRepository(scope: scope, detail: sessionDetail, interactions: interactions, localStore: localStore)
        devicePairing = V2DevicePairingService(connectorAPI: api.connectors)
        deviceManagement = V2DeviceManagementService(connectorAPI: api.connectors)
        workspaceFiles = V2WorkspaceFilesService(
            connectorAPI: api.connectors,
            serverURL: api.serverURL
        )
        // 官方 AppState:791 reconcile 钩子：dashboard 事件经 sessionReads 过滤
        dashboardRepository.reconcile = { [weak self] in self?.sessionReads.ingest($0) ?? $0 }
        connectivity.onChange = { [weak self] status in
            guard let self else { return }
            self.sessionRepository.updateConnectivity(status)
            self.dashboardRepository.updateNetwork(status)
            // P2：官方 V2ClientServices:97 —— 网络变化推给缓存的 DeviceAgentModel
            self.updateAgentConnections()
            // 官方 AppState:331：网络变化同步给已读编排
            self.sessionReads.updateConnectivity(status)
            self.onConnectivityChange?(status)
        }
        connectivity.start()
    }

    /// 官方逐字（Business/V2ClientServices.swift:125-128）。本仓调用点 = 进入会话页时
    /// （app 层 RemoteSessionListView 的 chatDestination .task，selection 即当前打开的会话）；
    /// 官方在 AppState 创建组合根后立刻调，语义相同：先把本地缓存铺进仓库再拉网络。
    func restoreCache(selection: ChatShellSelection) async {
        await dashboardRepository.restoreCache()
        if case .session(let id) = selection { await sessionRepository.restoreCachedSession(id: id) }
    }

    /// 官方 `onSelectPage(.newSession)` 的本仓等价物：回到「新会话」页由 app 层注入
    /// （本仓导航为 NavigationStack + fullScreenCover，无 ChatShell 选择页）。
    var onReturnToNewSession: (() -> Void)?

    // MARK: - P2 设备管理数据面（官方 V2ClientServices + AppState 的会话/连接器写回半段）

    /// 官方逐字（V2ClientServices:100-105）：per-connector 缓存 DeviceAgentModel。
    /// 本仓差异：官方 `agentSetup.updateConnectors` 半段宿主在 app 层
    /// AgentSetupCoordinator（配对轮询），此处只承载 agent 模型连接态刷新。
    func agents(on connectorID: String) -> DeviceAgentModel {
        if let model = agentModels[connectorID] { return model }
        let model = DeviceAgentModel(connectorID: connectorID, service: deviceManagement)
        agentModels[connectorID] = model
        updateAgentConnections()
        return model
    }

    /// 官方逐字（V2ClientServices:107-111）去掉 `agentSetup.updateConnectors` 半段
    /// （见上：宿主在 AgentSetupCoordinator）。connectivity.onChange 与 dashboard
    /// 刷新时调用，把连接器在线态推给每个缓存的 DeviceAgentModel。
    func updateAgentConnections() {
        let online = Set(dashboardRepository.connectors.filter { $0.status == .online }.map(\.id))
        for (id, model) in agentModels {
            model.updateConnection(dashboardRepository.isFresh && online.contains(id) && connectivity.status.availability != .offline)
        }
    }

    /// 官方 AppState.updateConnector（632）：连接器写回（rename/rotate 后）。
    func updateConnector(_ updated: V2Connector) {
        dashboardRepository.upsertConnector(updated)
        updateAgentConnections()
    }

    /// 官方 AppState.removeConnector（636-639）：删连接器 + 清该连接器会话。
    func removeConnector(connectorId: V2ConnectorID) {
        sessionRepository.remove(sessionIds: dashboardRepository.sessions.filter { $0.connectorId == connectorId }.map(\.id))
        dashboardRepository.removeConnector(connectorId)
        updateAgentConnections()
    }

    /// 官方 AppState.updateSessions（641）：批量会话写回 dashboard 仓库。
    func updateSessions(_ updated: [V2SessionMeta]) {
        dashboardRepository.upsert(updated)
    }

    /// 官方 AppState.setSessionsArchived（396-418）：批量归档/取消归档，
    /// 成功回写每个更新会话，失败落 sessionActionError。本仓组合根即数据面宿主，
    /// 无官方 `cachedServices === services` 换代守卫（单一组合根、无替换）。
    func setSessionsArchived(sessionIds: [V2SessionID], archived: Bool) async -> Bool {
        sessionActionError = nil
        do {
            let updatedSessions = if archived {
                try await dashboard.archive(sessionIds: sessionIds)
            } else {
                try await dashboard.unarchive(sessionIds: sessionIds)
            }
            for updated in updatedSessions {
                dashboardRepository.upsert([updated])
            }
            return true
        } catch {
            sessionActionError = error.localizedDescription
            return false
        }
    }

    func dismissSessionActionError() {
        sessionActionError = nil
    }


    /// 官方逐字（数据半段）：本地创建会话的发送记录被放弃 → 撤掉仓库里的临时会话。
    func discardCreation(_ id: String) {
        guard id.hasPrefix("local:") else { return }
        sessionRepository.remove(sessionIds: [id]); dashboardRepository.removeLocalSession(id)
        onReturnToNewSession?()
    }

    /// 官方 `editCreation`：把已发回合的待发内容回填到新会话草稿并跳页。
    /// 官方调 `newSession.restoreCreationDraft(meta, pending)` + `onSelectPage(.newSession)`；
    /// 本仓 new-session 是 app 层 facade（RemoteNewSessionModel），草稿回填由 app 层
    /// 注入的 `onEditCreation` 承担（meta + pending → facade.restoreCreationDraft），
    /// 跳页沿用官方的 `onReturnToNewSession`（discardCreation 同款通道）。
    func editCreation(_ session: V2SessionModel, pending: V2PendingMessage) {
        guard let meta = session.metadata else { return }
        // 官方 newSession 是长驻单例可直接调；本仓新会话页 model 是页面级
        // @StateObject，跳页后才创建 → 先暂存，RemoteNewSessionView 首帧 .task 消费。
        pendingEditCreation = (meta, pending)
        onReturnToNewSession?()
    }

    /// 官方 `newSession.restoreCreationDraft` 的待回填草稿暂存（facade 版的
    /// 「跨页面传递」通道：editCreation 存入 → 新会话页 .task 取出回填 → 清空）。
    /// 消费方：RemoteNewSessionView.task；RemoteSessionListView 负责打开该页。
    var pendingEditCreation: (V2SessionMeta, V2PendingMessage)?

    /// 官方 `AppState.setAppInBackground` 的本仓等价物（方案 B：钩子挂在远端线
    /// 页面根 RemoteSessionListView，不碰 App 根）。只承载冻结仓库半段：
    /// flushCache + sessionRepository suspend/resume + sessionReads。
    /// AppState 拥有的其余件（agentSetup / accountSync / dashboardUpdatesTask）
    /// 在本仓另有宿主（配对轮询=AgentSetupCoordinator；列表轮询=RemoteSessionLoader）。
    func setAppInBackground(_ background: Bool) {
        sessionReads.setActive(!background)
        if background {
            Task { await flushCache() }
            sessionRepository.suspend()
        } else {
            sessionRepository.resume()
        }
    }

    func flushCache() async {
        await dashboardRepository.flushCache()
        await sessionRepository.flushCache()
    }

    func shutdown(removingCache: Bool = false) {
        onConnectivityChange = nil
        dashboardRepository.invalidate()
        connectivity.stop()
        sessionRepository.reset()
        Task { await localStore.close(removing: removingCache) }
        api.cancelOutstandingRequests()
    }
}

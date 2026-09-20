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
    let sessionReads = V2SessionReadCoordinator()

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

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
/// - `sessionReads` (V2SessionReadCoordinator): official AppState-only consumer
///   (background read-marking); no app consumer yet — kept out until wired.
/// - `onSelectPage`/`editCreation`：navigation is NavigationStack-based here (no ChatShell
///   selection pages); `onReturnToNewSession` + `discardCreation` carry the half the chat page
///   needs (see below). `editCreation` stays unwired — see the 缺口 note.
/// - `flushCache` keeps the official shape but has no caller yet: upstream calls it from
///   `AppState.setAppInBackground`, whose hook sits on the App root (`AgentsAnywhereApp.swift:23`
///   `.onChange(of: scenePhase)`). Our App root is ContentView = 本机线, 死隔离 forbids touching
///   it. Cache durability in the meantime comes from the frozen repositories themselves
///   (500 ms debounce in `V2DashboardRepository.changed` / `V2SessionModel:178`) and the
///   `shutdown(removingCache:)` already wired on sign-out. Unfinished item, see PATCHES.md.
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
        connectivity.onChange = { [weak self] status in
            guard let self else { return }
            self.sessionRepository.updateConnectivity(status)
            self.dashboardRepository.updateNetwork(status)
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

    /// 官方 `editCreation` 依赖 `newSession.restoreCreationDraft`（官方 NewSessionModel
    /// 的草稿 + 目标回填 API）。本仓新会话页是 facade 版 RemoteNewSessionModel，没有等价的
    /// 草稿回填入口，只做「跳新会话页」会静默丢掉待发内容 → 不实现（不假接通）：
    /// SessionChatModel.onEditCreation 保持 nil，官方件对 nil 自然短路。
    /// 缺口与计划见 PATCHES.md P1-CHAT 批与自审报告「未完成项」。

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

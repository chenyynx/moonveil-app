// RemoteSessionLoader.swift — 远端会话列表数据层（DATA-1，2026-09-20）
//
// 只走 RemoteKit public facade（RemoteService）；不读 ChatStore、不碰
// ContentView 的 stackList（死隔离：远端数据层与本机列表文件级零交集）。
//
// 读：listSessions(archived:) 三态（.all = 活跃+已归档两路并发合并）+
//     listProjects() 项目名字典；归档页/设备页用 archivedItems（独立加载）。
// 写：patchSessionMeta（置顶/标题）+ archive/unarchive/markRead 批量——
//     乐观更新 + 服务端写回 + 失败回滚，错误进 writeError 供 UI 诚实展示；
//     写成功后另触发 dashboardRepository 重读回写（[BATCH-A/A3]，见
//     syncDashboardAfterWrite 字据）。
// 重命名与删除（服务端无删除端点）仍为占位，见 PATCHES 台账。

import SwiftUI

@MainActor
final class RemoteSessionLoader: ObservableObject {
    static let shared = RemoteSessionLoader()

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// 当前归档筛选下的会话（列表页数据源；预览假数据已移除）。
    @Published private(set) var items: [RemoteSessionItem] = []
    /// 已归档会话（归档页 / 设备页归档筛选；独立加载与刷新）。
    @Published private(set) var archivedItems: [RemoteSessionItem] = []
    /// 项目名字典：projectId → 远端项目名（listProjects() 真实结果）。
    @Published private(set) var projectNames: [String: String] = [:]
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var archivedPhase: Phase = .idle
    /// 最近一次写操作错误（乐观回滚时点亮，供 UI 诚实展示）。
    @Published private(set) var writeError: String?
    /// P3-3 错误分类（官方判据 = V2ClientFailure：网络中断/鉴权失效/数据不兼容——
    /// ChatToastStore 按 kind 出中文标题，源串保留原文）。写面与加载面各一。
    @Published private(set) var writeFailure: V2ClientFailure?
    /// P3-3：加载面最近一次失败（含 loadMore——分页失败不清已加载列表，只点亮这里）。
    @Published private(set) var loadFailure: V2ClientFailure?
    /// P3-1：当前筛选最近一次加载的游标状态（服务端 nextCursor 续拉）。
    @Published private(set) var isLoadingMore = false

    private var loadTask: Task<Void, Never>?
    private var archivedTask: Task<Void, Never>?
    /// 最近一次加载的筛选——变化时才重拉。
    private var lastFilter: RemoteSessionFilter?
    private var activeCursor: String?
    private var activeHasMore = false
    private var archivedCursor: String?
    private var archivedHasMore = false
    /// changeLog 条数上限。重放只取 gen > startGen（load 捕获的 startGen 单调
    /// 不减），触顶丢的最老条目通常已在所有在途窗口之外；代价边界：若某在途
    /// load 的 startGen 早于被丢条目，该变更不再被重放，其行可能被旧快照带回，
    /// 要到下一次全量拉取才与服务端一致。
    static let changeLogCap = 128
    /// 归档写回传变更集的单调序号（竞态检测用，字据见 changeLog 声明处）。
    private var changeGeneration = 0
    /// applyRemoteChange 的有界日志（generation + 变更集）。存在理由：列表在途
    /// 请求发出可能早于归档写入落地，其整表响应晚于 applyRemoteChange 到达时会
    /// 把已归档的行「复活」；旧 force 重拉靠再拉一次自愈，增量合并后必须由
    /// load/loadArchived 在响应落地后重放在途窗口内的变更集（重放语义见
    /// replayed(afterGen:...)；条数上限见 changeLogCap）。
    private var changeLog: [(generation: Int, sessions: [RemoteSessionMeta])] = []

    /// 列表页判据：当前筛选还有未到达的页（到页尾时触发 loadMore）。
    var hasMorePages: Bool {
        switch lastFilter {
        case .active: return activeHasMore
        case .archived: return archivedHasMore
        case .all: return activeHasMore || archivedHasMore
        case nil: return false
        }
    }

    // MARK: - 列表读

    /// 列表页主加载。force=false 且筛选未变、已加载时跳过（防重复请求）。
    func load(service: RemoteService, filter: RemoteSessionFilter, force: Bool = false) {
        if !force, lastFilter == filter, case .loaded = phase { return }
        lastFilter = filter
        loadTask?.cancel()
        phase = .loading
        writeError = nil
        writeFailure = nil
        let startGen = changeGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let active: [RemoteSessionMeta]
                let archived: [RemoteSessionMeta]
                switch filter {
                case .active:
                    let page = try await service.listSessions(archived: false)
                    active = page.sessions
                    archived = []
                    activeCursor = page.nextCursor; activeHasMore = page.hasMore
                    archivedCursor = nil; archivedHasMore = false
                case .archived:
                    let page = try await service.listSessions(archived: true)
                    archived = page.sessions
                    active = []
                    archivedCursor = page.nextCursor; archivedHasMore = page.hasMore
                    activeCursor = nil; activeHasMore = false
                case .all:
                    async let a = service.listSessions(archived: false)
                    async let b = service.listSessions(archived: true)
                    let activePage = try await a
                    let archivedPage = try await b
                    active = activePage.sessions
                    archived = archivedPage.sessions
                    activeCursor = activePage.nextCursor; activeHasMore = activePage.hasMore
                    archivedCursor = archivedPage.nextCursor; archivedHasMore = archivedPage.hasMore
                }
                // 项目名字典：失败不阻断会话列表（名字缺失时回退 projectId 原值）
                if let projects = try? await service.listProjects() {
                    projectNames = Dictionary(
                        projects.map { ($0.id, $0.name) },
                        uniquingKeysWith: { first, _ in first }
                    )
                }
                let merged = active + archived
                let mirror = replayed(afterGen: startGen,
                                      items: Self.sortedForList(merged).map(Self.map),
                                      archived: archivedItems,
                                      filter: filter,
                                      archivedLoaded: archivedPhase == .loaded)
                items = mirror.items
                archivedItems = mirror.archived
                phase = .loaded
                loadFailure = nil
            } catch {
                phase = .failed(error.localizedDescription)
                loadFailure = V2ClientFailure(error)
            }
        }
    }

    /// P3-1（2026-09-21）：列表到达页尾时按服务端游标拉下一页。
    /// 官方 iOS 客户端无常驻列表分页消费方（侧栏 = dashboard 全量快照，
    /// nextCursor 仅域层 V2SessionAPI 契约——查证记录见 ~/qoder_selfreview_p2p3.md），
    /// 本方法按服务端分页契约实现。失败不改 phase（已加载内容保持），
    /// 错误只点亮 loadFailure 供 toast 分类展示。
    func loadMore(service: RemoteService) async {
        guard case .loaded = phase, !isLoadingMore, let filter = lastFilter else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            if filter != .archived, activeHasMore, let cursor = activeCursor {
                let page = try await service.listSessions(archived: false, cursor: cursor)
                activeCursor = page.nextCursor; activeHasMore = page.hasMore
                appendSessions(page.sessions)
            } else if filter != .active, archivedHasMore, let cursor = archivedCursor {
                let page = try await service.listSessions(archived: true, cursor: cursor)
                archivedCursor = page.nextCursor; archivedHasMore = page.hasMore
                appendSessions(page.sessions)
            }
        } catch {
            loadFailure = V2ClientFailure(error)
        }
    }

    /// 新一页并入现有列表：按 id 去重（服务端游标窗口可能重叠），排序沿用 resort。
    private func appendSessions(_ new: [RemoteSessionMeta]) {
        for m in new.map(Self.map) where !items.contains(where: { $0.id == m.id }) {
            items.append(m)
        }
        resort()
    }

    /// 归档页 / 设备页归档筛选的数据源（独立于主筛选）。
    func loadArchived(service: RemoteService, force: Bool = false) {
        if !force, case .loaded = archivedPhase { return }
        archivedTask?.cancel()
        archivedPhase = .loading
        let startGen = changeGeneration
        archivedTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.listSessions(archived: true)
                let mirror = replayed(afterGen: startGen,
                                      items: items,
                                      archived: Self.sortedForList(page.sessions).map(Self.map),
                                      filter: lastFilter,
                                      archivedLoaded: true)
                items = mirror.items
                archivedItems = mirror.archived
                archivedPhase = .loaded
            } catch {
                archivedPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// 分页加载失败也回写 writeFailure 之外的加载面判据——统一入口（内部用）。
    private func markWriteFailure(_ error: Error) {
        writeError = error.localizedDescription
        writeFailure = V2ClientFailure(error)
    }

    /// 下拉刷新：强制重拉当前筛选（+归档页若已加载过）。
    func refresh(service: RemoteService, filter: RemoteSessionFilter) async {
        load(service: service, filter: filter, force: true)
        if case .loaded = archivedPhase {
            loadArchived(service: service, force: true)
        }
        // refreshable 需要 await 到加载落地
        while case .loading = phase {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// 归档页下拉刷新（只刷归档面，不动主筛选）。
    func refreshArchived(service: RemoteService) async {
        loadArchived(service: service, force: true)
        while case .loading = archivedPhase {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - 映射（RemoteSessionMeta → RemoteSessionItem）

    static func map(_ s: RemoteSessionMeta) -> RemoteSessionItem {
        RemoteSessionItem(
            id: s.id,
            title: (s.title?.isEmpty == false) ? s.title! : "未命名会话",
            projectId: s.projectId,
            connectorId: s.connectorId,
            isPinned: s.pinned,
            indicator: tailIndicator(status: s.status),
            isUnread: s.unread,
            updatedAtText: relativeTime(s.sortAt ?? s.lastItemAt ?? s.lastActivityAt ?? s.createdAt),
            previewText: previewText(cwd: s.cwd, runtimeName: s.runtimeTypeDisplayName),
            sortDate: parseISO(s.sortAt ?? s.lastItemAt ?? s.lastActivityAt ?? s.createdAt ?? "") ?? .distantPast
        )
    }

    /// 尾部指示器（等待批准 / running / 无）——与卡角未读点正交，方案 B 渲染位。
    static func tailIndicator(status: String) -> RemoteSessionIndicator {
        switch status {
        case "waiting_approval": return .waitingApproval
        case "running", "pending", "stopping": return .running
        default: return .none
        }
    }

    /// 摘要行：工作目录末段（Claude Code 语义）→ 运行时显示名 → 空串（不假造消息）。
    static func previewText(cwd: String?, runtimeName: String?) -> String {
        if let cwd, !cwd.isEmpty {
            let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
            if let last = trimmed.split(separator: "/").last { return String(last) }
            return trimmed
        }
        if let runtimeName, !runtimeName.isEmpty { return runtimeName }
        return ""
    }

    /// 置顶优先，再按时间倒序（无时间戳的排末尾）。
    static func sortedForList(_ list: [RemoteSessionMeta]) -> [RemoteSessionMeta] {
        list.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return sortKey(lhs) > sortKey(rhs)
        }
    }

    static func sortKey(_ s: RemoteSessionMeta) -> Date {
        parseISO(s.sortAt ?? s.lastItemAt ?? s.lastActivityAt ?? s.createdAt ?? "") ?? .distantPast
    }

    /// 解析服务端 ISO8601（utc_now() = isoformat().replace("+00:00","Z")，
    /// 可能带小数秒）。两试：带/不带 fractionalSeconds。
    static func parseISO(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    /// ISO8601 → 相对时间（刚刚 / N 分钟前 / HH:mm / 昨天 / M月d日 / yyyy-M-d）。
    static func relativeTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty, let date = parseISO(iso) else { return "" }
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 0 { return "" }          // 未来时间（时钟漂移）不显示
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) 分钟前" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return timeFmt.string(from: date) }
        if cal.isDateInYesterday(date) { return "昨天" }
        if cal.isDate(date, equalTo: now, toGranularity: .year) { return monthFmt.string(from: date) }
        return fullFmt.string(from: date)
    }

    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月d日"; return f
    }()
    static let fullFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-M-d"; return f
    }()

    // MARK: - 写（乐观更新 + 服务端写回 + 失败回滚）

    /// 置顶 / 取消置顶。
    func togglePin(_ id: String, service: RemoteService) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let newValue = !items[idx].isPinned
        items[idx].isPinned = newValue
        resort()
        Task {
            do {
                let updated = try await service.patchSessionMeta(sessionId: id, pinned: newValue)
                replaceItem(Self.map(updated))
                syncDashboardAfterWrite(service)
            } catch {
                if let ridx = items.firstIndex(where: { $0.id == id }) {
                    items[ridx].isPinned = !newValue
                    resort()
                }
                markWriteFailure(error)
            }
        }
    }

    /// 归档（可批量）。乐观移出 items，服务端确认后把回传变更集交给
    /// applyRemoteChange 并入（changeLog + 增量合并，语义见该方法注释）。
    /// 不再手写 append archivedItems：绕过 changeLog 的写回会被「发出更早、
    /// 落地更晚」的在途全量快照复活，replayed 无条目可重放，滞后到下次全量。
    /// 日志只记服务端已确认的变更是有意取舍：乐观条目若也记入，失败回滚就没有
    /// 对应的撤销条目；而「确认先到」或「快照先到」两种时序都经 changeLog 收敛。
    func archive(_ ids: [String], service: RemoteService) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        Task {
            do {
                let r = try await service.archive(sessionIds: ids)
                applyRemoteChange(r.sessions)
                syncDashboardAfterWrite(service)
            } catch {
                items.append(contentsOf: removed)
                resort()
                markWriteFailure(error)
            }
        }
    }

    /// 取消归档（归档页「恢复」）。成功路径与归档对称，理由见 archive 注释。
    func unarchive(_ ids: [String], service: RemoteService) {
        let removed = archivedItems.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        archivedItems.removeAll { ids.contains($0.id) }
        Task {
            do {
                let r = try await service.unarchive(sessionIds: ids)
                applyRemoteChange(r.sessions)
                syncDashboardAfterWrite(service)
            } catch {
                archivedItems.append(contentsOf: removed)
                resortArchived()
                markWriteFailure(error)
            }
        }
    }

    /// 标记已读（打开会话时调用；本地乐观清除未读，写失败不回滚 UI）。
    func markRead(_ ids: [String], service: RemoteService) {
        for i in items.indices where ids.contains(items[i].id) {
            items[i].isUnread = false
        }
        Task {
            if (try? await service.markRead(sessionIds: ids)) != nil {
                syncDashboardAfterWrite(service)
            }
        }
    }

    /// 服务端已确认的归档变更集 → 按 id 增量并入 items / archivedItems，不动
    /// phase（整表 force 重拉会把 phase 打到 .loading，返回列表页闪一帧加载骨架；
    /// 服务端与仓库已在写路径内推进，这里只需修 loader 这份镜像）。
    /// 调用方两条：设备详情页写路径经 RemoteSessionListView.onSessionsChanged；
    /// 列表页 archive/unarchive 经 facade RemoteSessionWriteResult.sessions。
    /// 归属判定与幂等性由 merged() 纯函数单点承担；这里同时把变更集记进
    /// changeLog，供「请求发出早于本次写入」的在途 load 落地时重放（见 changeLog）。
    /// items 归属按当前筛选判定：.active 只留未归档、.archived 只留已归档、
    /// .all 两者都留；lastFilter 为 nil（列表还没加载过）时不注入，交给下次
    /// load() 的全量结果。archivedItems 仅在归档面已加载时增量维护（未加载时
    /// 部分并入反而制造「归档面就这些」的假象）。
    func applyRemoteChange(_ sessions: [RemoteSessionMeta]) {
        guard !sessions.isEmpty else { return }
        changeGeneration += 1
        changeLog.append((generation: changeGeneration, sessions: sessions))
        if changeLog.count > Self.changeLogCap {
            changeLog.removeFirst(changeLog.count - Self.changeLogCap)
        }
        let merged = Self.merged(sessions, filter: lastFilter,
                                 intoItems: items, intoArchived: archivedItems,
                                 archivedLoaded: archivedPhase == .loaded)
        items = merged.items
        archivedItems = merged.archived
    }

    // MARK: - 增量合并纯函数（无副作用，可独立推演）

    /// 行序判据：置顶优先，再按 sortDate 倒序。注意判据在本类里有两份——本函数
    /// 作用于 RemoteSessionItem（resort / resortArchived / merged 消费），
    /// sortedForList 作用于 RemoteSessionMeta（load / loadArchived 全量拉取的
    /// pre-map 路径），两种类型不共享字段，无法直接复用同一函数。两份判据等价
    /// 的依据：map 把 s.pinned 原样传给 isPinned，sortKey 的时间回退链与 map 的
    /// sortDate 逐字相同。改一侧判据必须同步另一侧，否则置顶的已归档会话会在
    /// 「增量合并后」与「下次刷新后」行序跳变。
    static func listOrder(_ lhs: RemoteSessionItem, _ rhs: RemoteSessionItem) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        return lhs.sortDate > rhs.sortDate
    }

    /// 把变更集并入两份行镜像，返回新数组。幂等：同一变更集重复并入结果不变
    /// （命中 id 即整行覆写，未命中才追加），这是「先 live 应用、在途 load 再
    /// 重放一遍」不会打串的前提。archivedLoaded=false 时归档面原样返回（部分
    /// 并入会制造「归档面就这些」的假象，交给下次 loadArchived 全量）。
    static func merged<S: Sequence>(
        _ sessions: S,
        filter: RemoteSessionFilter?,
        intoItems items: [RemoteSessionItem],
        intoArchived archived: [RemoteSessionItem],
        archivedLoaded: Bool
    ) -> (items: [RemoteSessionItem], archived: [RemoteSessionItem]) where S.Element == RemoteSessionMeta {
        var nextItems = items
        var nextArchived = archived
        for meta in sessions {
            let item = Self.map(meta)
            let keepInItems: Bool
            switch filter {
            case .all: keepInItems = true
            case .active: keepInItems = !meta.archived
            case .archived: keepInItems = meta.archived
            case nil: keepInItems = false
            }
            if keepInItems {
                upsert(item, into: &nextItems)
            } else {
                nextItems.removeAll { $0.id == item.id }
            }
            guard archivedLoaded else { continue }
            if meta.archived {
                upsert(item, into: &nextArchived)
            } else {
                nextArchived.removeAll { $0.id == item.id }
            }
        }
        nextItems.sort(by: listOrder)
        nextArchived.sort(by: listOrder)
        return (nextItems, nextArchived)
    }

    private static func upsert(_ item: RemoteSessionItem, into list: inout [RemoteSessionItem]) {
        if let idx = list.firstIndex(where: { $0.id == item.id }) { list[idx] = item }
        else { list.append(item) }
    }

    /// 把 startGen 之后的变更集重放进刚落地的全量快照。根因：在途请求发出早于
    /// 归档写入，它的响应可能仍带着已被移走/改归档态的行；不重放则整表覆写会
    /// 复活该行，而增量合并设计里返回列表页不再 force 重拉，没有别的自愈点。
    /// 取 gen > startGen 是保守方向：即便快照其实已含该变更，幂等并入也无害。
    private func replayed(afterGen startGen: Int,
                          items: [RemoteSessionItem], archived: [RemoteSessionItem],
                          filter: RemoteSessionFilter?, archivedLoaded: Bool)
        -> (items: [RemoteSessionItem], archived: [RemoteSessionItem]) {
        var result: (items: [RemoteSessionItem], archived: [RemoteSessionItem]) = (items, archived)
        for entry in changeLog where entry.generation > startGen {
            result = Self.merged(entry.sessions, filter: filter,
                                 intoItems: result.items, intoArchived: result.archived,
                                 archivedLoaded: archivedLoaded)
        }
        return result
    }

    /// [BATCH-A/A3] 写面 REST 成功后的仓库回写。根因：本仓写面此前只改
    /// loader.items/archivedItems，不回写 dashboardRepository——
    /// RemoteChatView / RemoteDeviceDetailView 读的是 repository → 双事实源，
    /// 列表页归档/置顶/已读后，设备页/聊天页滞后到下次 refresh
    /// （官方 AppState.setSessionsArchived 是 REST + 回写 repository 两件事一起做）。
    /// 为什么是「写成功后重读一发」而不是官方逐条 upsert：facade 写面
    /// （RemoteService.patchSessionMeta/archive/unarchive/markRead）回传的
    /// RemoteSessionMeta 是 V2SessionMeta 的有损公开镜像（丢 updatedSeq/takeover/
    /// sourceAvailability 等参与 mergeSessions revision fence 的字段），且
    /// V2SessionMeta.pinned/archived 为 let，无法就地翻旗；拿有损镜像 upsert 会
    /// 覆盖仓库权威字段或被 fence 错拒。修根需要改 seam 层 facade 的写面回传
    /// （seam 归属文件，本批不动）→ 已写进交付报告交回决策。
    /// repository.refresh() 与官方 dashboard 事件流同一落地通道，自带 isValid / offline
    /// 守门；组合根未就绪（未登录）时整体 no-op。
    /// 「重复触发安全」要说准：安全指不会崩、不会打串，不指必然收敛——refresh() 的
    /// !isLoading 是**丢弃式**守门（V2DashboardRepository.swift:56-57），若写之前发起的
    /// 一发还在途，本次回写信号会被无声吞掉，滞后窗口延续到下一次触发（列表 onAppear /
    /// 手动下拉都有兜底）。不排队不合并是有意取舍：这几条路径的正确性要求是"最终会一致"
    /// 而非"这一发必到"，加队列的复杂度换不到用户可感知的收益。
    private func syncDashboardAfterWrite(_ service: RemoteService) {
        guard service.chat?.dashboardRepository != nil else { return }
        Task { await service.chat?.dashboardRepository.refresh() }
    }

    /// 详情页标题（缓存命中即返回，不阻塞、不假造）。
    func cachedTitle(for id: String) -> String? {
        items.first { $0.id == id }?.title
            ?? archivedItems.first { $0.id == id }?.title
    }

    // MARK: - 内部

    private func resort() {
        items.sort(by: Self.listOrder)
    }

    /// 归档面行序——与 resort 共用 listOrder（置顶优先），判据见 listOrder 注释。
    private func resortArchived() {
        archivedItems.sort(by: Self.listOrder)
    }

    private func replaceItem(_ item: RemoteSessionItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        }
        resort()
    }
}

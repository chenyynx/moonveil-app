// RemoteSessionLoader.swift — 远端会话列表数据层（DATA-1，2026-09-20）
//
// 只走 RemoteKit public facade（RemoteService）；不读 ChatStore、不碰
// ContentView 的 stackList（死隔离：远端数据层与本机列表文件级零交集）。
//
// 读：listSessions(archived:) 三态（.all = 活跃+已归档两路并发合并）+
//     listProjects() 项目名字典；归档页/设备页用 archivedItems（独立加载）。
// 写：patchSessionMeta（置顶/标题）+ archive/unarchive/markRead 批量——
//     乐观更新 + 服务端写回 + 失败回滚，错误进 writeError 供 UI 诚实展示。
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
                items = Self.sortedForList(merged).map(Self.map)
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
        archivedTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await service.listSessions(archived: true)
                archivedItems = Self.sortedForList(page.sessions).map(Self.map)
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
            } catch {
                if let ridx = items.firstIndex(where: { $0.id == id }) {
                    items[ridx].isPinned = !newValue
                    resort()
                }
                markWriteFailure(error)
            }
        }
    }

    /// 归档（可批量）。乐观移出 items，成功后并入 archivedItems。
    func archive(_ ids: [String], service: RemoteService) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        Task {
            do {
                let r = try await service.archive(sessionIds: ids)
                for m in r.sessions.map(Self.map) where !archivedItems.contains(where: { $0.id == m.id }) {
                    archivedItems.append(m)
                }
                archivedItems.sort { $0.sortDate > $1.sortDate }
            } catch {
                items.append(contentsOf: removed)
                resort()
                markWriteFailure(error)
            }
        }
    }

    /// 取消归档（归档页「恢复」）。
    func unarchive(_ ids: [String], service: RemoteService) {
        let removed = archivedItems.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        archivedItems.removeAll { ids.contains($0.id) }
        Task {
            do {
                let r = try await service.unarchive(sessionIds: ids)
                for m in r.sessions.map(Self.map) where !items.contains(where: { $0.id == m.id }) {
                    items.append(m)
                }
                resort()
            } catch {
                archivedItems.append(contentsOf: removed)
                archivedItems.sort { $0.sortDate > $1.sortDate }
                markWriteFailure(error)
            }
        }
    }

    /// 标记已读（打开会话时调用；本地乐观清除未读，写失败不回滚 UI）。
    func markRead(_ ids: [String], service: RemoteService) {
        for i in items.indices where ids.contains(items[i].id) {
            items[i].isUnread = false
        }
        Task { _ = try? await service.markRead(sessionIds: ids) }
    }

    /// 详情页标题（缓存命中即返回，不阻塞、不假造）。
    func cachedTitle(for id: String) -> String? {
        items.first { $0.id == id }?.title
            ?? archivedItems.first { $0.id == id }?.title
    }

    // MARK: - 内部

    private func resort() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.sortDate > rhs.sortDate
        }
    }

    private func replaceItem(_ item: RemoteSessionItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        }
        resort()
    }
}

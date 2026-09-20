// AgentSetupCoordinator.swift — AA 官方 Models/Chat/AgentSetupCoordinator.swift
// 逐字搬运（观察器语义/轮询/代际令牌/pause-resume 全保真）。
//
// 适配点：
// - @Observable → ObservableObject（本仓主流模式；行为不变）。
// - V2DevicePairingService.connector(connectorId:) → service.connector(connectorId:)。
// - V2ClientFailure 分类 → RemoteServiceError 分类（rejected = 明确拒绝：记录并
//   停止；transport/notReady = 暂时性：3 秒后续轮询。官方 .unavailable→finish
//   分支在本仓无直接对等物，静默中止条件按 rejected 处理）。

import Foundation

/// Pairing observation belongs to the account, not the lifetime of a sheet.
/// Background/offline transitions pause reads and retain the pending devices.
@MainActor
final class AgentSetupCoordinator: ObservableObject {
    struct Request: Identifiable {
        var connector: RemoteConnector
        var ready = false
        var error: String?
        var id: String { connector.id }
    }
    @Published private(set) var requests: [Request] = []
    @Published private(set) var selectedSetupID: String?
    @Published var pairingFormPresented = false
    var onOnline: ((RemoteConnector) -> Void)?
    private let service: RemoteService
    private let sleep: (Duration) async throws -> Void
    private var tasks: [String: Task<Void, Never>] = [:]
    private var isActive = true
    private var isOnline = true
    private var isValid = true
    private var generation = 0

    init(service: RemoteService, sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.service = service; self.sleep = sleep
    }
    var presentedConnector: RemoteConnector? {
        guard !pairingFormPresented else { return nil }
        return requests.first { $0.ready && $0.id == selectedSetupID }?.connector
    }
    func watch(_ connector: RemoteConnector) {
        guard isValid else { return }
        if !requests.contains(where: { $0.id == connector.id }) { requests.append(.init(connector: connector)) }
        if connector.isOnline { markReady(connector) }
        resume()
    }
    func updateConnectors(_ connectors: [RemoteConnector]) {
        for connector in connectors where connector.isOnline {
            if requests.contains(where: { $0.id == connector.id && !$0.ready }) { markReady(connector) }
        }
    }
    func configure(_ id: String) {
        guard isValid, requests.contains(where: { $0.id == id && $0.ready }) else { return }
        selectedSetupID = id
    }
    func finish(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel(); requests.removeAll { $0.id == id }
        if selectedSetupID == id { selectedSetupID = nil }
    }
    func retry(_ id: String) {
        if let index = requests.firstIndex(where: { $0.id == id }) { requests[index].error = nil }
        resume()
    }
    func setActive(_ active: Bool) { isActive = active; restart() }
    func invalidate() {
        isValid = false; pause(); requests = []; selectedSetupID = nil; onOnline = nil
    }
    private func restart() { pause(); resume() }
    private func pause() {
        generation += 1
        tasks.values.forEach { $0.cancel() }; tasks = [:]
    }
    private func resume() {
        guard isValid, isOnline, isActive else { return }
        for request in requests where !request.ready && request.error == nil && tasks[request.id] == nil {
            let version = generation
            tasks[request.id] = Task { [weak self] in await self?.poll(request.id, version: version) }
        }
    }
    private func poll(_ id: String, version: Int) async {
        defer { if version == generation { tasks[id] = nil } }
        while current(id, version) {
            do {
                let connector = try await service.connector(connectorId: id)
                guard current(id, version) else { return }
                if connector.isOnline {
                    markReady(connector); onOnline?(connector); return
                }
                try await sleep(.seconds(2))
            } catch {
                guard current(id, version) else { return }
                if case RemoteServiceError.rejected = error {
                    if let index = requests.firstIndex(where: { $0.id == id }) { requests[index].error = error.localizedDescription }
                    return
                }
                do { try await sleep(.seconds(3)) } catch { return }
            }
        }
    }
    private func current(_ id: String, _ version: Int) -> Bool {
        isValid && isActive && isOnline && version == generation && !Task.isCancelled
            && requests.contains { $0.id == id && !$0.ready }
    }
    private func markReady(_ connector: RemoteConnector) {
        guard let index = requests.firstIndex(where: { $0.id == connector.id }) else { return }
        requests[index].connector = connector; requests[index].ready = true; requests[index].error = nil
        tasks.removeValue(forKey: connector.id)?.cancel()
    }
}

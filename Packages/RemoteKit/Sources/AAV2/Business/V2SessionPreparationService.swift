// V2SessionPreparationService.swift — AA 官方 Business/V2SessionPreparationService.swift
// 逐字搬运。另含官方两处依赖的同步搬运（注明来源）：
// - Models/Chat/NewSessionModel.swift 底部的 extension V2DeviceRuntime
//   （isReadyForSession / sessionUnavailableReason / sessionDisplayName）——
//   官方在 app 层与模型同文件；此处置于 RemoteKit 供 facade 与 app 共用（单模块同可见性）。
// - Models/Chat/ConversationSettings.swift 里的 extension V2RuntimeCapabilitySnapshot.allows
//   ——本服务（及 facade/app 层）用它按 capability 门控 catalog 请求。

import Foundation

struct V2PreparedSession: Hashable {
    let runtime: V2DeviceRuntime
    let capabilities: V2RuntimeCapabilitySnapshot
    let catalogs: V2SessionCatalogs
}

struct V2SessionPreparationService {
    let connectorAPI: any V2ConnectorAPIProtocol

    /// New-session catalogs are Connector/instance resources; no session is created here.
    func prepare(connectorId: V2ConnectorID, runtimeId: V2RuntimeID) async throws -> V2PreparedSession {
        async let runtime = connectorAPI.runtime(connectorId: connectorId, runtimeId: runtimeId)
        let capabilities = try await connectorAPI.runtimeCapabilities(connectorId: connectorId, runtimeId: runtimeId).capabilitySet
        async let model = capabilities.allows("catalog.model")
            ? connectorAPI.modelCatalog(connectorId: connectorId, runtimeId: runtimeId).catalog
            : V2ModelCatalog(runtime: runtimeId, revision: 0, models: [])
        async let permission = capabilities.allows("catalog.permission")
            ? connectorAPI.permissionCatalog(connectorId: connectorId, runtimeId: runtimeId).catalog
            : V2PermissionCatalog(runtime: runtimeId, revision: 0, permissions: [])
        return try await V2PreparedSession(
            runtime: runtime,
            capabilities: capabilities,
            catalogs: V2SessionCatalogs(model: model, permission: permission)
        )
    }

    func commands(connectorId: V2ConnectorID, runtimeId: V2RuntimeID) async throws -> [V2RuntimeCommand] {
        try await connectorAPI.commands(connectorId: connectorId, runtimeId: runtimeId).commands
    }
}

// Source: AA Models/Chat/NewSessionModel.swift:399-409 (verbatim).
extension V2DeviceRuntime {
    var isReadyForSession: Bool { configured && active && available && status == .running }
    var sessionUnavailableReason: String? {
        if !configured { return String(localized: "尚未配置") }
        if !active { return String(localized: "未启用，请在设备管理中启动") }
        if let reason, !reason.isEmpty { return reason }
        if status != .running { return String(localized: "尚未就绪 · \(status.displayName)") }
        return available ? nil : String(localized: "当前不可用")
    }
    var sessionDisplayName: String { name.isEmpty ? displayName : name }
}

// Source: AA Models/Chat/ConversationSettings.swift (verbatim extension).
extension V2RuntimeCapabilitySnapshot {
    func allows(_ id: V2CapabilityID) -> Bool {
        guard let value = capability(id: id) else { return false }
        return value.supported && value.available && value.allowed
    }
}

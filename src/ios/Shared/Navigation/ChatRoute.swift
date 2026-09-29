import Foundation

/// [NAV-ROOT-FIX 2026-09-29] 单一导航通道的类型化路由：`navigationPath` 的
/// 元素类型，替代 raw String。`local` = 本地会话（含草稿 `__new__…`）；
/// `remote` = 远端设备会话（替代 `"remote:\(deviceId):\(sessionId)"` 字符串
/// 拼接——旧格式 id 含冒号即解析错位）。
enum ChatRoute: Hashable {
    case local(id: String)
    case remote(deviceId: String, sessionId: String)

    /// 聊天页 vm / badge / stack 追踪沿用的会话 id。
    var sessionId: String {
        switch self {
        case .local(let id): return id
        case .remote(_, let sessionId): return sessionId
        }
    }

    /// 导航日志用短标签（完整 id 不进日志）。
    var logTag: String {
        switch self {
        case .local(let id): return "local:\(id.prefix(8))"
        case .remote(let deviceId, let sessionId):
            return "remote:\(deviceId.prefix(4)):\(sessionId.prefix(8))"
        }
    }

    /// 兼容旧调用点传入的 `"remote:\(deviceId):\(sessionId)"` 字符串
    /// （远端行点击已直接产出 `.remote`，此处仅作防御）。
    init(legacyId: String) {
        if legacyId.hasPrefix("remote:") {
            let parts = legacyId.split(separator: ":", maxSplits: 2)
            if parts.count == 3 {
                self = .remote(deviceId: String(parts[1]), sessionId: String(parts[2]))
                return
            }
        }
        self = .local(id: legacyId)
    }
}

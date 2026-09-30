import Foundation

/// [NAV-ROOT-FIX 2026-09-29] 单一导航通道的类型化路由：`navigationPath` 的
/// 元素类型，替代 raw String。`local` = 本地会话（含草稿 `__new__…`）；
/// `remote` = 远端设备会话（替代 `"remote:\(deviceId):\(sessionId)"` 字符串
/// 拼接——旧格式 id 含冒号即解析错位）。
enum ChatRoute: Hashable {
    case local(id: String)
    case remote(deviceId: String, sessionId: String)
    /// [去嵌套 2026-09-30] 远端树（bridge 线）自己的聊天页——渲染 SessionChatView
    /// （V2 组合根数据面）。与 `.remote` 区分：`.remote` 渲染 AIChatView（本机线
    /// iCloud 只读视图），不得混用（去嵌套手术：远端列表的聊天 push 改走本 case，
    /// 由容器栈目的地 RemoteTreeChatDestination 承接）。
    case remoteTreeChat(sessionId: String)
    /// [去嵌套 2026-09-30] 远端树设备详情页（RemoteDeviceDetailView）。connectorId
    /// 为空串 = 数据未到时的兜底请求（目的地按「精确 id ?? online 优先 ?? 第一台」
    /// 解析；解析不出 → pending 空态）。
    case remoteDevice(connectorId: String)

    /// 聊天页 vm / badge / stack 追踪沿用的会话 id——**本机线独占语义**。
    /// [去嵌套 2026-09-30] 改可选；[R2 审查修订 2026-09-30] 两个远端树 case 均返回
    /// nil：本值的消费方（ContentView 的 vm 悬挂账 :1997-2011、分享 bufferTarget
    /// :2068）都按「栈上本机会话」解读——远端 id 混入会让分享内容被静默丢弃
    /// （bufferTarget 钉到远端 id、唯一消费者 AIChatView 永不注入；R2 实锤链）。
    /// `.local`/`.remote` 旧值语义逐字保留，未动。
    var sessionId: String? {
        switch self {
        case .local(let id): return id
        case .remote(_, let sessionId): return sessionId
        case .remoteTreeChat: return nil
        case .remoteDevice: return nil
        }
    }

    /// 导航日志用短标签（完整 id 不进日志）。
    var logTag: String {
        switch self {
        case .local(let id): return "local:\(id.prefix(8))"
        case .remote(let deviceId, let sessionId):
            return "remote:\(deviceId.prefix(4)):\(sessionId.prefix(8))"
        case .remoteTreeChat(let sessionId):
            return "rtree:\(sessionId.prefix(8))"
        case .remoteDevice(let connectorId):
            return "rdev:\(connectorId.prefix(4))"
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

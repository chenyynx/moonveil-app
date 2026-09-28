// Route.swift — 单通道 NavigationStack path 的路由值。
// path 里放"路由值"，不是裸 sessionId。草稿没有 sessionId 没关系：用稳定的 draftId 当身份。
// 草稿"转正"为真实会话时，不要改 path 里的元素（元素变了 = destination 被重建），
// 真实 sessionId 由聊天页 VM 内部持有。

enum Route: Hashable {
    case session(id: String)
    case draft(id: String)
    /// 列表内嵌的远端设备会话（原 "remote:{deviceId}:{sessionId}" 字符串路由值）。
    /// 单通道改造必须保留这条既有目的地，故按类型显式建模，不再靠字符串前缀解析。
    case remoteSession(deviceId: String, id: String)
}

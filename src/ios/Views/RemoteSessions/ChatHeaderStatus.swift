// ChatHeaderStatus.swift — AA 官方 Models/Chat/ChatHeaderStatus.swift 逐字搬运，
// 含官方文件尾部的 extension SessionChatModel { headerStatus }。
//
// 搬运历史字据：518ae29 首批只搬了 enum 本体，把 extension 记为「随聊天页批次
// 一并搬运」。SessionChatView 的 ChatPageToolbar(status: model.headerStatus) 调用点
// 早已存在，于是 run 35552014610 报 'SessionChatModel' has no member 'headerStatus'
// —— 该错误此前被 SessionChatView:72 的 type-check 超时压在下一层，超时消除后才显形。
// 官方 8 个表达式在本仓冻结模型上逐一同构（V2SessionModel:76-82,245 /
// V2SessionRuntimeModel:16-19 / SessionNoticeStore:31,129 / V2RuntimeState:43,45 /
// V2SessionMeta:28 / V2SessionConnectionState / V2NetworkStatus.Availability /
// V2SessionID = String），故整段逐字搬，无适配、冻结区零改动。

import Foundation

/// Transient session feedback belongs to the header, outside message geometry.
enum ChatHeaderStatus: Equatable {
    case networkOffline, deviceOffline, syncing, working, waitingForResponse, stopping
    case information(String)

    var title: String {
        switch self {
        case .networkOffline: String(localized: "网络已断开")
        case .deviceOffline: String(localized: "设备离线")
        case .syncing: String(localized: "正在同步会话状态…")
        case .working: String(localized: "正在处理任务")
        case .waitingForResponse: String(localized: "等待回应")
        case .stopping: String(localized: "正在停止…")
        case .information(let message): message
        }
    }
    var detail: String {
        switch self {
        case .networkOffline: String(localized: "网络已断开，草稿和已加载的消息已保留")
        case .deviceOffline: String(localized: "设备离线，等待重新连接")
        default: title
        }
    }
    var symbol: String {
        switch self {
        case .networkOffline: "wifi.slash"
        case .deviceOffline: "desktopcomputer"
        case .waitingForResponse: "hand.raised"
        default: "info.circle"
        }
    }
    var isProgress: Bool { self == .syncing || self == .working || self == .stopping }
}

extension SessionChatModel {
    var headerStatus: ChatHeaderStatus? {
        if session.isLocalCreation { return nil }
        if session.network.availability == .offline || session.connection == .offline { return .networkOffline }
        if session.metadata?.connectorStatus == .offline { return .deviceOffline }
        if !session.runtime.isFresh || session.connection == .reconnecting {
            // A decoding/action error is already a toast. It does not establish
            // an offline connection, nor justify showing stale runtime activity.
            return session.failure == nil ? .syncing : nil
        }
        if session.notices.notices.contains(where: { $0.blocks(session.id) })
            || session.runtime.state?.status == .waitingApproval { return .waitingForResponse }
        if session.runtime.state?.status == .stopping { return .stopping }
        if let reason = session.runtime.state?.statusReason, !reason.isEmpty { return .information(reason) }
        return nil
    }
}

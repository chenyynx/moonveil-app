// ChatHeaderStatus.swift — AA 官方 Models/Chat/ChatHeaderStatus.swift 逐字搬运。
//
// 唯一适配：官方文件对 SessionChatModel 的 extension（headerStatus 计算属性）
// 属于会话聊天页模型，本批不搬（随聊天页批次接入模型时一并搬运）。
// enum 本体逐字（含全部 title/detail/symbol/isProgress）。

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

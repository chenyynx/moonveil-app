// AddDeviceSheet.swift — 「添加设备」表。终端卡在没有可用 connector 时弹出；
// 用户选「扫码登录」/「手动登录」，由调用方接 QRCodeLoginView / ManualLoginView。
//
// [TEMPLATE-SWAP 2026-09-27] 按 pp 指示（「图二的文字和排版有问题，参照图一的
// 模版调整／直接把图一的模版 ui 套过来改内容」）整体套用本仓 PairDeviceSheet 的
// connectionMethod 模版——那套即 AA 官方 PairDeviceSheet 的逐字搬运：同款导航壳
// （inline 标题 + SheetCloseToolbar 圆形 X）、`.title2.bold()` 大标题、正文级
// secondary 说明、AppGlassButton（prominent 黑玻璃 + 默认灰玻璃）双钮、
// `VStack(spacing: 22)` + `.padding(22)` + `.frame(maxWidth: 560)`。
// 原手绘胶囊版（28pt 标题 / 15pt 说明 / 56pt 自绘底 / 深色反色分支）整体废弃。

import SwiftUI

struct AddDeviceSheet: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss

    /// 登录成功后调用（调用方负责关表并进设备页）。
    var onLoginSucceeded: () -> Void = {}
    /// 用户点了「扫码登录」/「手动登录」：调用方先关本表，再弹对应登录页。
    /// （本表已是 sheet，内嵌再弹 sheet 会导致 OAuth 网页弹层消失。）
    var onQRLoginRequested: () -> Void = {}
    var onManualLoginRequested: () -> Void = {}

    var body: some View {
        NavigationStack {
            instructionsPage
                .frame(maxWidth: .infinity)
                .navigationTitle("添加设备")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { SheetCloseToolbar { dismiss() } }
        }
        .appSheetPresentation(.compact)
    }

    /// 模版同形（PairDeviceSheet.instructionsPage(.connectionMethod)）：
    /// 大标题 → 说明 → 主钮 → 说明 → 次钮 → 说明，仅内容替换。
    private var instructionsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("连接您的设备").font(.title2.bold())
                Text("您可以通过扫码或手动登录连接您的设备。").foregroundStyle(.secondary)
                AppGlassButton("扫码登录", systemImage: "qrcode", style: .prominent) {
                    dismiss()
                    onQRLoginRequested()
                }
                Text("扫描设备或服务器上的二维码，快速完成连接。").foregroundStyle(.secondary)
                AppGlassButton("手动登录", systemImage: "keyboard") {
                    dismiss()
                    onManualLoginRequested()
                }
                Text("手动输入服务器地址和登录凭证进行连接。").foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: 560)
        }
    }
}

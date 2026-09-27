import SwiftUI

/// 「添加设备」表。终端卡在没有可用 connector 时弹出。
///
/// 视觉 1:1 复用官方 App 的 Add Device sheet（pp 2026-09-27 截图）：
/// 抓手 + 左上 X + 居中标题「添加设备」+ 左对齐大标题「连接您的设备」+
/// 灰色描述 + 黑色胶囊主按钮 + 灰色说明 + 浅灰胶囊次按钮 + 灰色说明。
/// 按钮按 pp 要求为「扫码登录」/「手动登录」，接现有 QRCodeLoginView / ManualLoginView。
/// 登录成功后由调用方接线到设备页。
struct AddDeviceSheet: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 登录成功后调用（调用方负责关表并进设备页）。
    var onLoginSucceeded: () -> Void = {}
    /// 用户点了「扫码登录」/「手动登录」：调用方先关本表，再弹对应登录页。
    /// （本表已是 sheet，内嵌再弹 sheet 会导致 OAuth 网页弹层消失。）
    var onQRLoginRequested: () -> Void = {}
    var onManualLoginRequested: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：X + 标题（图二样式：X 在浅灰圆里，标题居中）
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
                Spacer()
                Text("添加设备")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 大标题
                    Text("连接您的设备")
                        .font(.system(size: 28, weight: .bold))
                        .padding(.top, 28)

                    // 描述
                    Text("您可以通过扫码或手动输入连接您的设备。")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)

                    // 主按钮：扫码登录（深浅反色胶囊）
                    // [FIX-qr-btn-gray 2026-09-27] 背景不用 Color.primary（语义色在
                    // sheet medium 高度下解析成灰），用明确黑白。
                    Button {
                        dismiss()
                        onQRLoginRequested()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 18, weight: .medium))
                            Text("扫码登录")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(colorScheme == .light ? Color.black : Color.white)
                        .foregroundStyle(colorScheme == .light ? .white : .black)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)

                    // 说明
                    Text("扫描设备或服务器上的二维码，快速完成连接。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    // 次按钮：手动登录（浅灰胶囊，跟随深浅）
                    Button {
                        dismiss()
                        onManualLoginRequested()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 18, weight: .medium))
                            Text("手动登录")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)

                    // 说明
                    Text("手动输入服务器地址和登录凭证进行连接。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

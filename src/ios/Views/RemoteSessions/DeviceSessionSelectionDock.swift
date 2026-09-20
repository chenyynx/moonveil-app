// DeviceSessionSelectionDock.swift — AA 官方逐字搬运（P3-2 底部批量归档 dock，2026-09-21）
//
// 官方源：Views/Devices/DeviceOverviewContent.swift 内 `DeviceSessionSelectionDock`
// （同文件其余列表组件本仓保留 pp 已验收骨架，见 RemoteDeviceDetailView，不搬）。
// 合法差异：
// - 文案落地（铁律①类2 先例）：Cancel→取消；dashboard.device.archiveSelected→归档已选择；
//   unarchiveSelected→取消归档已选择。`Text("\(count) selected")`：官方键
//   '%lld selected' 未注册 zh-Hans，官方中文运行时显示即源串 "N selected"，
//   搬运件以同形插值保持显示一致。
// - iOS 26 版本守卫（铁律①类1）：`.glassEffect(.regular, in: .rect(cornerRadius: 24))`
//   → `remoteGlassCard()`（RemoteGlassIfAvailable.swift，低版本回退材质卡）。

import SwiftUI

struct DeviceSessionSelectionDock: View {
    let count: Int
    let restores: Bool
    let isWorking: Bool
    let disabled: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) selected").font(.subheadline).monospacedDigit()
            Spacer(minLength: 0)
            Button("取消", action: onCancel).disabled(isWorking)
            AppGlassButton(restores ? "取消归档已选择" : "归档已选择", systemImage: restores ? "tray.and.arrow.up" : "archivebox",
                style: .prominent, isLoading: isWorking, disabled: disabled || count == 0, maxWidth: nil, action: onSubmit)
        }
        .padding(14).remoteGlassCard()
        .padding(.horizontal, 24).padding(.bottom, 12).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
}

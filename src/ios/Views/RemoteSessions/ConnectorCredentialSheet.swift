// ConnectorCredentialSheet.swift — AA 官方逐字搬运（P2-B，2026-09-21）
//
// 官方源：Views/Devices/ConnectorCredentialSheet.swift（v2.0.0-27-g1bc11f45）。
// 合法差异（铁律①类2·文案落地，先例 P1 app 搬运件）：
// - `String(localized: "…")` → xcstrings zh-Hans 显示值（对照表见 ~/qoder_selfreview_p2p3.md）。
// - `ConnectorCredentialValue.title: LocalizedStringResource` → `String`：文案落地后
//   插值 `String(localized: title)` 无键可查，官方 zh-Hans 运行时显示即源串
//   "Copy Server URL"，搬运件以 `"Copy " + title` 保持同一显示结果。
// SheetCloseToolbar / appSheetPresentation 为本仓既有等价组件（P1 已搬）。

import SwiftUI
import UIKit

struct ConnectorCredentialSheet: View {
    @Environment(\.dismiss) private var dismiss

    let connector: V2Connector
    let connectorToken: String
    let serverURL: URL

    @State private var copiedField: ConnectorCredentialField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("Connector 已断开", appSymbol: "key.horizontal")
                        .font(.title2.weight(.semibold))

                    Text("原凭据已失效。重新连接前，请使用以下信息更新桌面 Connector。")
                        .foregroundStyle(.secondary)

                    ConnectorCredentialValue(
                        title: "服务器地址",
                        value: serverURL.absoluteString,
                        copied: copiedField == .serverURL,
                        onCopy: { copy(serverURL.absoluteString, field: .serverURL) }
                    )
                    ConnectorCredentialValue(
                        title: "Connector ID",
                        value: connector.id,
                        copied: copiedField == .connectorId,
                        onCopy: { copy(connector.id, field: .connectorId) }
                    )
                    ConnectorCredentialValue(
                        title: "Connector 令牌",
                        value: connectorToken,
                        copied: copiedField == .connectorToken,
                        onCopy: { copy(connectorToken, field: .connectorToken) }
                    )

                    Label(
                        "此令牌仅展示一次。请将其保存到 Connector 配置中，不要分享给他人。",
                        appSymbol: "exclamationmark.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("新凭据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetCloseToolbar { dismiss() }
            }
        }
        .appSheetPresentation(.expanded)
    }

    private func copy(_ value: String, field: ConnectorCredentialField) {
        UIPasteboard.general.string = value
        copiedField = field
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private enum ConnectorCredentialField: Hashable {
    case serverURL
    case connectorId
    case connectorToken
}

private struct ConnectorCredentialValue: View {
    let title: String
    let value: String
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 10) {
                Text(value)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onCopy) {
                    AppSymbol(copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(copied ? "已复制" : "Copy " + title)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

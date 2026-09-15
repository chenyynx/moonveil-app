// RemoteRootView.swift — 远程 tab 三态壳（U1 终案；pp 2026-09-15 定稿：顶栏标题位
// 与本机侧渲染同一个 ModeTabPicker，切换时胶囊位置不动）。
//
// Consumes ONLY RemoteKit's public facade (RemoteService / RemoteServiceState).
// Staged with deadlines (完整性铁律 — 明示不藏):
//   • QR camera pairing → batch 8（manual bootstrap(url, token) 现在就是活路）
//   • R0 会话列表       → batch 8（timeline/snapshot public 面）
//   • notice 交互 UI    → batch 8（数据面 noticeSnapshot 已 public）
// 不装成功态：没连上就显示没连上。

import SwiftUI
import RemoteKit

struct RemoteRootView: View {
    @ObservedObject var service: RemoteService
    @ObservedObject private var tabRouter = RootTabRouter.shared

    /// 与本机侧标题同源（SOUL.md name，回退 Moonveil）——同一真源，非平行命名通道。
    @State private var soulName: String = {
        let n = SoulStore.cachedMetadata.name
        return n.isEmpty ? "Moonveil" : n
    }()

    @State private var serverURLText: String = UserDefaults.standard.string(forKey: "remote.serverURL") ?? ""
    @State private var accessTokenText: String = ""
    @State private var lastError: String?
    @State private var pendingNotices = 0

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ModeTabPicker(
                            selection: $tabRouter.mode,
                            localLabel: soulName
                        )
                        .frame(maxWidth: 220)
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            soulName = n.isEmpty ? "Moonveil" : n
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .idle, .degraded: guide
        case .pairing:         pairingPending
        case .ready:           connected
        }
    }

    // MARK: State 1 — 未配置引导（服务器地址 + 访问令牌 → bootstrap）

    private var guide: some View {
        VStack(spacing: 14) {
            if case .degraded(let reason) = service.state {
                Label(reason, systemImage: "wifi.exclamationmark")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("连接远程服务器").font(.title3.bold())
            Text("填入服务器地址与访问令牌。扫码配对将在下一批上线。")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                TextField("https://cloud.example.com", text: $serverURLText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                SecureField("访问令牌", text: $accessTokenText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
            }
            .frame(maxWidth: 320)

            if let lastError {
                Text(lastError).font(.caption).foregroundStyle(.red)
            }

            Button { connect() } label: {
                Label("连接", systemImage: "bolt.horizontal")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverURLText.isEmpty || accessTokenText.isEmpty)
            .padding(.top, 4)

            Spacer().frame(height: 40)
        }
        .padding(20)
    }

    private func connect() {
        guard let url = URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.hasPrefix("http") == true else {
            lastError = "服务器地址无效（需 http(s)://…）"
            return
        }
        lastError = nil
        UserDefaults.standard.set(url.absoluteString, forKey: "remote.serverURL")
        let token = accessTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        accessTokenText = ""   // 令牌不在视图状态里过夜
        service.bootstrap(serverURL: url, accessToken: token)
    }

    // MARK: State 2 — 已配置待配对

    private var pairingPending: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("等待配对完成…").font(.callout)
            Button("取消，回到引导") { service.reset() }.font(.callout)
        }
    }

    // MARK: State 3 — 已连接（列表=批8；本批=真实状态+审批计数+断开）

    private var connected: some View {
        VStack(spacing: 14) {
            Label("已连接", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
            Text(UserDefaults.standard.string(forKey: "remote.serverURL") ?? "—")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)

            if pendingNotices > 0 {
                Label("需要你处理 ×\(pendingNotices)", systemImage: "bell.badge")
                    .font(.callout).foregroundStyle(.red)
            }

            Text("会话列表与消息将在下一批上线")
                .font(.footnote).foregroundStyle(.tertiary)

            Button("断开连接", role: .destructive) {
                service.reset()
                pendingNotices = 0
            }
            .font(.callout)
        }
        .padding(20)
    }
}

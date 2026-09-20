// PairDeviceSheet.swift — AA 官方 Views/Pairing/PairDeviceSheet.swift 逐字搬运
// （步骤机/校验/交互/控件全保真；文案为官方 xcstrings 的 zh-Hans 显示值）。
//
// 适配点（数据面 AppState → RemoteService facade + AgentSetupCoordinator）：
// - appState.createDevicePairing(name:) → service.createConnector(name:)
// - appState.claimDevicePairing(...) → service.claimPairing(...)
// - services.deviceManagement.renameConnector(...) → service.renameConnector(...)
// - appState.nativeChatServices?.agentSetup → AgentSetupCoordinator（列表页持有）
// - appState.serverURL → service.serverURLValue
// - V2ClientFailure.isDefiniteWriteRejection → RemoteServiceError 分类等价
// - nativeChatServices 实例一致性守卫（账号切换防陈旧）→ 单例 service 下无需

import SwiftUI
import UIKit

struct PairDeviceSheet: View {
    @ObservedObject var service: RemoteService
    @ObservedObject var setup: AgentSetupCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var path: [Step] = []
    @State private var name = "新设备"
    @State private var code = ""
    @State private var credential: RemoteConnectorCreateResponse?
    @State private var isWorking = false
    @State private var creationUncertain = false
    @State private var error: String?
    @State private var copied = false
    private enum Step: Hashable { case connectionMethod, desktop, cliConfirm, name, cliMethod, pairCode, token }

    var body: some View {
        NavigationStack(path: $path) {
            page(.connectionMethod)
                .navigationDestination(for: Step.self) { page($0) }
        }
        .appSheetPresentation(.compact)
        .disabled(isWorking)
        .interactiveDismissDisabled(isWorking)
        .onChange(of: path) { _, _ in error = nil; copied = false }
    }

    private func page(_ step: Step) -> some View {
        Group {
            if step == .name { nameForm }
            else if step == .pairCode { pairCodeForm }
            else { instructionsPage(step) }
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(title(for: step))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetCloseToolbar(disabled: isWorking) { dismiss() } }
        .onAppear {
            if step == .token, let credential {
                setup.watch(credential.connector)
            }
        }
    }

    private func instructionsPage(_ step: Step) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if step == .desktop { desktopInstructions }
                else if step == .cliConfirm { cliConfirmation }
                else if step != .connectionMethod { cliInstructions(step) }
                else {
                    Text("连接您的设备").font(.title2.bold())
                    Text("您可以通过桌面程序或 CLI 连接您的设备。").foregroundStyle(.secondary)
                    AppGlassButton("使用桌面程序连接", systemImage: "desktopcomputer", style: .prominent) {
                        path.append(.desktop)
                    }
                    Text("如果您使用 Windows 或 macOS，搭配桌面程序连接可以获得最佳体验。").foregroundStyle(.secondary)
                    AppGlassButton("使用命令行连接", systemImage: "terminal") {
                        path.append(.cliConfirm)
                    }
                    Text("使用一行命令连接您的设备，建议用于 Linux。").foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(22).frame(maxWidth: 560)
        }
    }

    private var nameForm: some View {
        Form {
            Section {
                TextField("例如 amber-finch", text: $name)
                    .textFieldStyle(.plain).autocorrectionDisabled()
                    .submitLabel(.continue).onSubmit(continuePairing)
            } header: {
                Text("设备名").textCase(nil)
            } footer: {
                Text("为您的设备起一个容易辨认的名字，然后选择配对方式。")
            }
            Section {
                AppGlassButton("继续", systemImage: "arrow.right", style: .prominent,
                    isLoading: isWorking, action: continuePairing)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || !canConnect || creationUncertain)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if creationUncertain {
                Text("服务器是否已创建设备尚未确认。请先关闭此页并刷新设备列表，确认结果后再创建。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            pairingMessages
        }
        .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
    }

    @ViewBuilder private var pairCodeForm: some View {
        if let credential, let server = service.serverURLValue {
            Form {
                if !isReady(credential) {
                    Section {
                        Text("运行命令后，将终端显示的 6 位配对码输入下方。")
                            .foregroundStyle(.secondary)
                        commandBlock(V2PairingCommand.pair(server: server))
                    } header: {
                        Text(credential.connector.name).textCase(nil)
                    }.listRowBackground(Color.clear)
                    Section {
                        OneTimeCodeField(code: $code, title: "设备上的配对码")
                    }
                    Section {
                        AppGlassButton("认领", systemImage: "link", style: .prominent, isLoading: isWorking) {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            Task { await claim(credential) }
                        }.disabled(code.count != 6 || isWorking || !canConnect)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                pairingStatus(credential)
                pairingMessages
            }
            .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var pairingMessages: some View {
        if !canConnect {
            Text("连接恢复后可以继续，已填写的内容会保留。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
    }

    private func continuePairing() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { await Task.yield(); await prepare() }
    }

    private func title(for step: Step) -> String {
        switch step {
        case .connectionMethod: "添加设备"
        case .desktop: "使用桌面程序连接"
        case .cliConfirm: "使用命令行连接"
        case .name: "命名设备"
        case .cliMethod: "选择配对方式"
        case .pairCode: "使用配对码配对"
        case .token: "使用 Token 连接"
        }
    }

    private var desktopInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Agents Anywhere 桌面应用", appSymbol: "desktopcomputer").font(.title2.bold())
            Text("打开桌面程序，连接到您当前使用的服务，并使用同一个账号登录。")
            Text(service.serverURLValue?.absoluteString ?? "").font(.callout.monospaced()).textSelection(.enabled)
            AppGlassButton("前往官网下载", style: .prominent) {
                openURL(URL(string: "https://agents-anywhere.com/")!)
            }
        }
    }

    private var cliConfirmation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确定要使用命令行吗？").font(.title2.bold())
            Text("此方式需要一定的计算机基础，您需要会使用终端以及 uv / uvx 命令行工具。")
            Text("如果您使用 Windows 或 macOS，更推荐使用桌面程序，连接和日常使用会更方便。")
                .foregroundStyle(.secondary)
            AppGlassButton("继续使用命令行", style: .prominent) {
                path.append(.name)
            }
            AppGlassButton("使用桌面程序") {
                path.append(.desktop)
            }
        }
    }

    @ViewBuilder private func cliInstructions(_ step: Step) -> some View {
        if let credential, let server = service.serverURLValue {
            Text(credential.connector.name).font(.title2.bold())
            if !isReady(credential) {
                if step == .cliMethod {
                    Text("选择一种方式，将 \(credential.connector.name) 连接到您的账号。").foregroundStyle(.secondary)
                    AppGlassButton("使用配对码", systemImage: "number", style: .prominent) {
                        path.append(.pairCode)
                    }
                    Text("在设备终端运行命令，将生成的 6 位配对码填回这里。")
                        .font(.footnote).foregroundStyle(.secondary)
                    AppGlassButton("使用 Token", systemImage: "key") {
                        path.append(.token)
                    }
                    Text("在设备终端运行包含 Token 的命令，直接完成连接。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("在 \(credential.connector.name) 的终端中运行下方命令，设备会自动连接到您的账号。")
                        .foregroundStyle(.secondary)
                    commandBlock(V2PairingCommand.start(server: server, credential: credential))
                }
            }
            pairingStatus(credential)
        }
        if !canConnect { Text("连接恢复后可以继续，已填写的内容会保留。")
            .font(.footnote).foregroundStyle(.secondary) }
    }

    private func isReady(_ credential: RemoteConnectorCreateResponse) -> Bool {
        setup.requests.first(where: { $0.id == credential.connector.id })?.ready == true
    }

    @ViewBuilder private func pairingStatus(_ credential: RemoteConnectorCreateResponse) -> some View {
        if let request = setup.requests.first(where: { $0.id == credential.connector.id }) {
            if request.ready {
                Label("设备已配对", appSymbol: "checkmark.circle").font(.headline)
                Text("\(credential.connector.name) 已上线。你可以选择要配置并启动的 Agent，也可以不添加直接完成。")
                    .font(.footnote).foregroundStyle(.secondary)
                AppGlassButton("为这台设备选择 Agent", style: .prominent) { setup.configure(request.id); dismiss() }
                AppGlassButton("暂不添加") { setup.finish(request.id); dismiss() }
            } else {
                HStack {
                    if request.error == nil { ProgressView() }
                    Text(request.error ?? "等待设备上线...")
                }.font(.subheadline)
            }
        }
    }

    private func commandBlock(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(command).font(.footnote.monospaced()).textSelection(.enabled)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            AppGlassButton(copied ? "已复制" : "复制命令", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = command; copied = true
            }
        }.onChange(of: command) { _, _ in copied = false }
    }

    private var canConnect: Bool { service.state == .ready }

    private func prepare() async {
        guard !isWorking, !creationUncertain, canConnect else { return }
        let submittedPath = path
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            if let previous = credential {
                if name.trimmingCharacters(in: .whitespacesAndNewlines) != previous.connector.name {
                    let connector = try await service.renameConnector(connectorId: previous.connector.id, name: name)
                    credential = .init(connector: connector, connectorToken: previous.connectorToken, tokenPrefix: previous.tokenPrefix)
                }
            } else { credential = try await service.createConnector(name: name) }
            if path == submittedPath { path.append(.cliMethod) }
        } catch {
            creationUncertain = credential == nil && !isDefiniteWriteRejection(error)
            self.error = error.localizedDescription
        }
    }

    /// 官方 V2ClientFailure.isDefiniteWriteRejection 的等价：服务端明确拒绝
    /// （rejected）= 确定未创建；transport（网络/超时）= 可能已创建，转未确认态。
    private func isDefiniteWriteRejection(_ error: Error) -> Bool {
        if case RemoteServiceError.rejected = error { return true }
        return false
    }

    private func claim(_ credential: RemoteConnectorCreateResponse) async {
        guard !isWorking, canConnect else { return }
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            guard let server = service.serverURLValue else { throw RemoteServiceError.notConfigured }
            let connector = try await service.claimPairing(code: code, name: credential.connector.name,
                serverUrl: server.absoluteString, connectorId: credential.connector.id, connectorToken: credential.connectorToken)
            setup.watch(connector)
            code = ""
        } catch { self.error = error.localizedDescription }
    }
}

// PairDeviceSheet.swift — 添加设备（AA 视觉 1:1，数据层换 RemoteService）
//
// 照抄 AA 的 PairDeviceSheet 结构：NavigationStack + Step 流程
// （connectionMethod → desktop / cliConfirm → name → cliMethod → pairCode），
// 视觉/文案/控件（AppGlassButton、命令块、SheetCloseToolbar、appSheetPresentation）
// 全部沿用 AA；唯一替换是把 AA 的 AppState/V2DashboardRepository 数据面
// 换成 moonveil 的 RemoteService public facade。

import SwiftUI

struct PairDeviceSheet: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var path: [Step] = []
    @State private var name = "New device"
    @State private var code = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var copied = false

    private enum Step: Hashable {
        case connectionMethod, desktop, cliConfirm, name, cliMethod, pairCode
    }

    private var serverLabel: String {
        UserDefaults.standard.string(forKey: "agentsAnywhere.serverURL") ?? "—"
    }

    var body: some View {
        NavigationStack(path: $path) {
            page(.connectionMethod)
                .navigationDestination(for: Step.self) { page($0) }
        }
        .appSheetPresentation(.compact)
        .disabled(isWorking)
        .interactiveDismissDisabled(isWorking)
        .onChange(of: path) { _, _ in
            error = nil
            copied = false
        }
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
    }

    private func instructionsPage(_ step: Step) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if step == .desktop {
                    desktopInstructions
                } else if step == .cliConfirm {
                    cliConfirmation
                } else if step != .connectionMethod {
                    cliInstructions
                } else {
                    Text("选择设备的连接方式")
                        .font(.title2.bold())
                    Text("您可以通过桌面程序或 CLI 连接您的设备。")
                        .foregroundStyle(.secondary)
                    AppGlassButton("桌面应用", systemImage: "desktopcomputer", style: .prominent) {
                        path.append(.desktop)
                    }
                    Text("在电脑上安装桌面应用，并登录同一账号。设备会自动显示在侧栏。")
                        .foregroundStyle(.secondary)
                    AppGlassButton("命令行", systemImage: "terminal") {
                        path.append(.cliConfirm)
                    }
                    Text("适合通过 CLI 连接远程主机或无界面的设备。")
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(22)
            .frame(maxWidth: 560)
        }
    }

    private var nameForm: some View {
        Form {
            Section {
                TextField("例如 Mac Studio", text: $name)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit(continuePairing)
            } header: {
                Text("设备名称").textCase(nil)
            } footer: {
                Text("这个名字只用于在列表里区分设备，之后可以改。")
            }
            Section {
                AppGlassButton("继续", systemImage: "arrow.right", style: .prominent,
                               isLoading: isWorking, action: continuePairing)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || !canConnect)
            } header: { EmptyView() }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var desktopInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Agents Anywhere Desktop", systemImage: "desktopcomputer")
                .font(.title2.bold())
            Text("在电脑上安装桌面应用，使用以下服务器地址登录当前账号。连接后，可以在设备管理中添加 Agent。")
            Text(serverLabel)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            AppGlassButton("下载桌面应用", style: .prominent) {
                if let url = URL(string: "https://agents-anywhere.com/") { openURL(url) }
            }
        }
    }

    private var cliConfirmation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确定要使用命令行吗？")
                .font(.title2.bold())
            Text("此方式需要会使用终端以及 uv / uvx 命令行工具。")
            Text("如果使用 Windows 或 macOS，桌面程序的连接和日常使用更方便。")
                .foregroundStyle(.secondary)
            AppGlassButton("继续使用命令行", style: .prominent) {
                path.append(.name)
            }
            AppGlassButton("使用桌面程序") {
                path.append(.desktop)
            }
        }
    }

    private var cliInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(name.isEmpty ? "New device" : name)
                .font(.title2.bold())
            Text("在目标设备上运行以下命令，把它连接到当前账号。")
                .foregroundStyle(.secondary)
            commandBlock(pairCommand)
            Text("运行后会显示一个六位配对码，把它填回这里。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            AppGlassButton("我已运行，填写配对码", systemImage: "number", style: .prominent) {
                path.append(.pairCode)
            }
        }
    }

    private var pairCodeForm: some View {
        Form {
            Section {
                Text("在目标设备运行上面的命令，把显示的六位配对码填进来。")
                    .foregroundStyle(.secondary)
                commandBlock(pairCommand)
            } header: {
                Text(name).textCase(nil)
            }
            .listRowBackground(Color.clear)
            Section {
                OneTimeCodeField(code: $code, title: "配对码")
            }
            Section {
                AppGlassButton("连接设备", systemImage: "link", style: .prominent,
                               isLoading: isWorking) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                    Task { await claim() }
                }
                .disabled(code.count != 6 || isWorking || !canConnect)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func commandBlock(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(command)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            AppGlassButton(copied ? "已复制" : "复制命令",
                           systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = command
                copied = true
            }
        }
        .onChange(of: command) { _, _ in copied = false }
    }

    // MARK: - 数据面（RemoteService public facade）

    private var canConnect: Bool { service.state == .ready || service.state == .pairing }

    private var pairCommand: String {
        "aa pair --server \(serverLabel)"
    }

    private func title(for step: Step) -> String {
        switch step {
        case .connectionMethod: "添加设备"
        case .desktop: "桌面应用"
        case .cliConfirm: "命令行"
        case .name: "设备名称"
        case .cliMethod: "选择配对方式"
        case .pairCode: "填写配对码"
        }
    }

    private func continuePairing() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        Task { await Task.yield(); await prepare() }
    }

    private func prepare() async {
        guard !isWorking, canConnect else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            // 数据面：RemoteService 的配对入口就绪后接这里（B8-AUTH 的 manual
            // bootstrap(url, token) 已是活路；本批先走流程骨架，不假造结果）。
            try await Task.sleep(for: .seconds(0))
            if path.last != .cliMethod { path.append(.cliMethod) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func claim() async {
        guard !isWorking, canConnect else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        // 数据面：RemoteService.completePairing(payload:) 就绪后接这里。
        code = ""
    }
}

// DeviceAgentSection.swift — AA 官方逐字搬运（P2-B，2026-09-21）
//
// 官方源：Views/Devices/DeviceAgentSection.swift（v2.0.0-27-g1bc11f45，含
// AgentRediscoveryButton + AgentSetupSheet）。
// 合法差异（铁律①类2·文案落地）：dashboard.device.agentRuntimes→Agent Runtime；
// 启用 %@→激活 %@（官方 zh fmt）；删除这个 Agent 的配置？→删除 Runtime 配置？；
// 重命名 Agent→重命名 Runtime 实例；Agent 操作未完成→无法更新 Runtime 状态。；
// 正在刷新 Agent→正在发现…；重新发现 Agent→刷新；
// 添加你要使用的 Agent→为这台设备选择 Agent；
// 「设备已连接。…」→「快速添加会自动生成名称并使用默认配置，之后可在设备页面调整。」
// （均为官方 xcstrings zh-Hans 注册值）。源串本已是中文的（离线提示等）原样保留。
// 依赖：DeviceAgentModel（AAV2 冻结件）；AddDeviceAgentSheet / RuntimeConfigurationSheet /
// DeviceOverviewSections（本批 app 搬运件）。

import SwiftUI

struct DeviceAgentSection: View {
    @Bindable var model: DeviceAgentModel
    var showsConnectionNotice = true
    var onError: ((String?) -> Void)?
    @State private var configuration: Configuration?
    @State private var showsAddAgents = false
    @State private var deleting: V2DeviceRuntime?
    @State private var renaming: V2DeviceRuntime?
    @State private var proposedName = ""
    @State private var schemaError: String?

    private struct Configuration: Identifiable {
        let runtime: V2DeviceRuntime
        let schema: V2RuntimeConfigSchema
        var id: String { runtime.id }
    }
    var body: some View {
        Section {
            if showsConnectionNotice && !model.connected {
                Label("设备或网络已离线，连接恢复后可继续。", appSymbol: "wifi.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.inventory.configuredInstances) { runtime in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(runtime.sessionDisplayName).font(.headline)
                        Text("\(runtime.typeDisplayName) · \(runtime.status.displayName)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        AppGlassButton(systemImage: "slider.horizontal.3", isLoading: model.busyID == runtime.id,
                            disabled: !model.connected || model.busyID != nil, maxWidth: nil) {
                            do { configuration = .init(runtime: runtime, schema: try model.schema(runtime)) }
                            catch { schemaError = error.localizedDescription }
                        }
                        .accessibilityLabel(Text("配置 \(runtime.sessionDisplayName)"))
                        Toggle("激活 \(runtime.sessionDisplayName)", isOn: Binding(get: { runtime.active }, set: { active in
                            Task { try? await model.setActive(runtime, active) }
                        }))
                        .labelsHidden().toggleStyle(.switch).tint(.green).fixedSize()
                        .disabled(!model.connected || model.busyID != nil)
                    }
                }
                .padding(.vertical, 6)
                .contextMenu {
                    Button("重命名", systemImage: "pencil") { proposedName = runtime.name; renaming = runtime }
                        .disabled(!model.connected || model.busyID != nil)
                    Button("删除配置", systemImage: "trash", role: .destructive) { deleting = runtime }
                        .disabled(!model.connected || model.busyID != nil)
                }
            }
        } header: {
            HStack {
                Text("Agent Runtime")
                Spacer()
                AgentRediscoveryButton(model: model)
            }
        } footer: {
            AppGlassButton("添加更多 Agent", systemImage: "plus", style: .prominent) {
                showsAddAgents = true
            }
            .font(.body).textCase(nil).padding(.top, 8)
        }
        .task(id: model.connected) { await model.refresh() }
        .sheet(isPresented: $showsAddAgents) { AddDeviceAgentSheet(model: model) }
        .sheet(item: $configuration, onDismiss: model.dismissError) { item in
            RuntimeConfigurationSheet(runtime: item.runtime, schema: item.schema, startAfterSaving: false, canSave: model.connected) {
                try await model.save(item.runtime, config: $0)
            }
        }
        .alert("删除 Runtime 配置？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除配置", role: .destructive) {
                guard let runtime = deleting else { return }; deleting = nil
                Task { try? await model.remove(runtime) }
            }
        } message: {
            Text("\(deleting?.sessionDisplayName ?? "") 会停止并从已配置列表移除，其关联的所有会话、消息记录和附件将被永久删除。之后仍可重新配置 Runtime，本机安装会保留。")
        }
        .alert("重命名 Runtime 实例", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("实例名称", text: $proposedName)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                guard let runtime = renaming else { return }; renaming = nil
                Task { try? await model.rename(runtime, proposedName) }
            }.disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("无法更新 Runtime 状态。", isPresented: Binding(
            get: { onError == nil && currentError != nil },
            set: { if !$0 { schemaError = nil; model.dismissError() } }
        )) {
            Button("好的", role: .cancel) { schemaError = nil; model.dismissError() }
        } message: { Text(schemaError ?? model.error ?? "") }
        .onChange(of: currentError, initial: true) { _, error in onError?(error) }
    }
    private var currentError: String? {
        !showsAddAgents && configuration == nil ? schemaError ?? model.error : nil
    }
}

struct AgentRediscoveryButton: View {
    let model: DeviceAgentModel

    var body: some View {
        Button { Task { await model.refresh(discover: true) } } label: {
            AppSymbol("arrow.clockwise")
                .opacity(model.isLoading ? 0 : 1)
                .overlay {
                    if model.isLoading { ProgressView().controlSize(.small).tint(.primary) }
                }
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!model.connected || model.isLoading || model.busyID != nil)
        .accessibilityLabel(model.isLoading ? "正在发现…" : "刷新")
    }
}

struct AgentSetupSheet: View {
    let connector: V2Connector
    let model: DeviceAgentModel
    let onFinish: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("为这台设备选择 Agent").font(.title2.bold())
                        Text("快速添加会自动生成名称并使用默认配置，之后可在设备页面调整。")
                            .foregroundStyle(.secondary)
                    }
                    DeviceOverviewSections { DeviceAgentSection(model: model) }
                }
                .padding(22).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .navigationTitle(connector.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetCloseToolbar(disabled: model.busyID != nil, action: onFinish)
            }
        }
        .appSheetPresentation(.compact).interactiveDismissDisabled(model.busyID != nil)
    }
}

// AddDeviceAgentSheet.swift — AA 官方逐字搬运（P2-B，2026-09-21）
//
// 官方源：Views/Devices/AddDeviceAgentSheet.swift（v2.0.0-27-g1bc11f45）。
// 合法差异（铁律①类2·文案落地）：均为官方 xcstrings zh-Hans 注册值——
// 添加 Agent→添加 Agent；dashboard.pairDevice.quickAdd→快速添加；
// dashboard.device.configure→配置；无法添加 Agent→无法创建 Runtime 实例。；
// 好→好的。中文源串（离线提示/空态两条）原样保留。
// 依赖：DeviceAgentModel / V2RuntimeType（AAV2）；RuntimeConfigurationSheet（本批搬运件）。

import SwiftUI

struct AddDeviceAgentSheet: View {
    @Bindable var model: DeviceAgentModel
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: Configuration?
    @State private var schemaError: String?

    private struct Configuration: Identifiable {
        let type: V2RuntimeType
        let schema: V2RuntimeConfigSchema
        var id: String { type.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.connected {
                        Label("设备或网络已离线，连接恢复后可继续。", appSymbol: "wifi.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(model.addableTypes) { type in
                        agentCard(type)
                    }
                    if model.addableTypes.isEmpty && !model.isLoading {
                        Text(model.inventory.types.isEmpty
                             ? "尚未发现可用 Agent。在设备上安装并登录 Agent 后，重新发现即可添加。"
                             : "当前可用的 Agent 都已添加。安装其他 Agent 后，可以重新发现。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            .navigationTitle("添加 Agent").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AgentRediscoveryButton(model: model) }
                SheetCloseToolbar(disabled: model.busyID != nil) { dismiss() }
            }
        }
        .appSheetPresentation(.compact)
        .interactiveDismissDisabled(model.busyID != nil)
        .sheet(item: $configuration, onDismiss: model.dismissError) { item in
            RuntimeConfigurationSheet(type: item.type, schema: item.schema, suggestedName: suggestedName(item.type), canSave: model.connected) { name, config in
                try await model.add(item.type, name: name, config: config, newInstance: true)
            }
        }
        .alert("无法创建 Runtime 实例。", isPresented: Binding(
            get: { configuration == nil && (schemaError != nil || model.error != nil) },
            set: { if !$0 { schemaError = nil; model.dismissError() } }
        )) {
            Button("好的", role: .cancel) { schemaError = nil; model.dismissError() }
        } message: { Text(schemaError ?? model.error ?? "") }
    }

    private func agentCard(_ type: V2RuntimeType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(type.displayName).font(.headline)
                if type.recommended { Text("推荐").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            if let description = type.reason ?? type.description, !description.isEmpty {
                Text(description).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                AppGlassButton("快速添加", systemImage: "plus", style: .prominent,
                    isLoading: model.busyID == type.id, disabled: !model.connected || model.busyID != nil) {
                    Task { try? await model.add(type, name: nil, config: [:]) }
                }
                AppGlassButton("配置", disabled: !model.connected || model.busyID != nil) { configure(type) }
            }
        }.padding(16).background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 18))
    }

    private func configure(_ type: V2RuntimeType) {
        do { configuration = .init(type: type, schema: try model.schema(type).forNamedInstance()) }
        catch { schemaError = error.localizedDescription }
    }

    private func suggestedName(_ type: V2RuntimeType) -> String {
        let names = Set(model.inventory.instances.map { $0.name.lowercased() })
        var name = type.displayName
        var suffix = 2
        while names.contains(name.lowercased()) { name = "\(type.displayName) \(suffix)"; suffix += 1 }
        return name
    }
}

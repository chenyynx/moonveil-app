// RemoteNewSessionSheets.swift — 新会话页的两个选择 sheet。
//
//   • RemoteNewSessionTargetSheet — 目标选择（AA 官方 Views/Chat/SessionTargetSheet.swift
//     移植：设备列表 → 展开设备看 Agent → 选择即应用并关闭；在线优先排序）。
//   • RemoteNewSessionWorkspaceSheet — 工作目录选择（官方 ProjectSelectionSheet 的
//     本仓数据面等价：项目列表选择；文件系统浏览随文件批次）。
//
// 数据面：设备/运行时 inventory 走 RemoteService（runtimeTypes）；选择应用走
// RemoteNewSessionModel.selectTarget（切设备 + 选 Agent）。

import SwiftUI

struct RemoteNewSessionTargetSheet: View {
    @ObservedObject var model: RemoteNewSessionModel
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss
    @State private var expandedDeviceId: String?
    @State private var applying: RemoteTargetSelection?
    @State private var selectionError: String?
    /// 每设备 Agent inventory（runtimeTypes 缓存；展开时拉取）。
    @State private var inventories: [String: [RemoteRuntimeType]] = [:]
    @State private var loadingDevices: Set<String> = []
    @State private var inventoryErrors: [String: String] = [:]

    private struct RemoteTargetSelection: Equatable {
        let connectorId: String
        let runtimeType: String
    }

    private var devices: [RemoteConnector] {
        model.connectors.sorted {
            ($0.isOnline ? 0 : 1, $0.name, $0.id) < ($1.isOnline ? 0 : 1, $1.name, $1.id)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if devices.isEmpty {
                    ContentUnavailableView("没有设备", appSymbol: "desktopcomputer")
                }
                Section {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
                if let error = selectionError ?? model.error {
                    Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("运行目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar(disabled: applying != nil) { dismiss() } }
            .refreshable {
                if let id = expandedDeviceId { await loadInventory(id) }
            }
        }
        .appSheetPresentation(.compact)
        .interactiveDismissDisabled(applying != nil)
        .disabled(applying != nil)
    }

    // MARK: - 设备行（官方 InlineSelectionGroup 等价：行 + 展开 agents）

    @ViewBuilder
    private func deviceRow(_ device: RemoteConnector) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) {
                    expandedDeviceId = expandedDeviceId == device.id ? nil : device.id
                }
                if expandedDeviceId == device.id {
                    Task { await loadInventory(device.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(device.isOnline ? .primary : .secondary)
                            .lineLimit(1)
                        Text(deviceDetail(device))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if model.selectedConnectorId == device.id {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    AppSymbol("chevron.down", size: 12)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expandedDeviceId == device.id ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedDeviceId == device.id {
                agentRows(on: device)
                    .padding(.leading, 17)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func agentRows(on device: RemoteConnector) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if loadingDevices.contains(device.id) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在检查 Agent…").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if let error = inventoryErrors[device.id] {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重新加载") { Task { await loadInventory(device.id) } }
                    .disabled(!device.isOnline)
            } else {
                let inventory = (inventories[device.id] ?? []).sorted {
                    ($0.available ? 0 : 1, $0.displayName, $0.runtimeType)
                        < ($1.available ? 0 : 1, $1.displayName, $1.runtimeType)
                }
                if inventory.isEmpty, device.isOnline {
                    Text("这台设备尚无已配置的 Agent。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                ForEach(inventory, id: \.runtimeType) { runtime in
                    Button {
                        apply(device: device, runtime: runtime)
                    } label: {
                        HStack(spacing: 8) {
                            Text(runtime.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(runtime.available ? .primary : .secondary)
                            if runtime.recommended {
                                Text("推荐").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if applying == RemoteTargetSelection(connectorId: device.id, runtimeType: runtime.runtimeType) {
                                ProgressView().controlSize(.small)
                            } else if model.selectedConnectorId == device.id,
                                      model.selectedRuntimeType == runtime.runtimeType {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!device.isOnline || !runtime.available)
                }
                if !device.isOnline {
                    Text("目标设备离线").font(.footnote).foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func deviceDetail(_ device: RemoteConnector) -> String {
        let status = device.isOnline ? "Online" : "Offline"
        return [device.deviceOs, status].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - inventory 与选择

    private func loadInventory(_ id: String) async {
        guard !loadingDevices.contains(id) else { return }
        loadingDevices.insert(id)
        inventoryErrors[id] = nil
        do {
            let types = try await service.runtimeTypes(connectorId: id)
            if !Task.isCancelled { inventories[id] = types }
        } catch {
            if !Task.isCancelled { inventoryErrors[id] = error.localizedDescription }
        }
        loadingDevices.remove(id)
    }

    private func apply(device: RemoteConnector, runtime: RemoteRuntimeType) {
        guard applying == nil, device.isOnline, runtime.available else { return }
        let target = RemoteTargetSelection(connectorId: device.id, runtimeType: runtime.runtimeType)
        applying = target
        selectionError = nil
        Task { @MainActor in
            let accepted = await model.selectTarget(
                connectorId: target.connectorId,
                runtimeType: target.runtimeType,
                service: service
            )
            applying = nil
            if accepted { dismiss() }
            else { selectionError = "当前设置未保存，请稍后重试。" }
        }
    }
}

// MARK: - 工作目录选择（官方 ProjectSelectionSheet 的本仓等价）

struct RemoteNewSessionWorkspaceSheet: View {
    @ObservedObject var model: RemoteNewSessionModel
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(model.selectedConnector?.name ?? "选择设备", appSymbol: "desktopcomputer")
                    if let connector = model.selectedConnector, !connector.isOnline {
                        Label("设备或网络已离线，已保存的项目仍可选择。", appSymbol: "wifi.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("这台设备上的项目") {
                    ForEach(model.availableProjects) { project in
                        Button {
                            model.selectProject(project)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(project.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(project.workspacePath)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                if model.selectedProjectId == project.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if model.availableProjects.isEmpty {
                        Text(model.projectsLoaded ? "还没有项目。用项目头的 + 先创建一个。" : "正在加载项目…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = model.projectsError {
                    Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("选择项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { dismiss() } }
            .refreshable { await model.refresh(service: service) }
        }
        .appSheetPresentation(.compact)
    }
}

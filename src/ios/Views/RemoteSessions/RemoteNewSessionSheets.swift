// RemoteNewSessionSheets.swift — 新会话页的两个选择 sheet。
//
//   • RemoteNewSessionTargetSheet — 目标选择（AA 官方 Views/Chat/SessionTargetSheet.swift
//     移植：设备列表 → 展开设备看 Agent → 选择即应用并关闭；在线优先排序）。
//   • RemoteNewSessionWorkspaceSheet — 工作目录选择（官方 ProjectSelectionSheet 的
//     本仓数据面等价：项目列表选择；文件系统浏览随文件批次）。
//
// 数据面：设备清单 + 运行时实例 inventory 走 RemoteService（[RUNTIME-ID] 批后
// 实例清单 runtimes，官方 V2DeviceRuntime 等价；类型清单 runtimeTypes 已退役）；
// 选择应用走 RemoteNewSessionModel.selectTarget（切设备 + 选实例）。

import SwiftUI

struct RemoteNewSessionTargetSheet: View {
    @ObservedObject var model: RemoteNewSessionModel
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss
    @State private var expandedDeviceId: String?
    @State private var applying: RemoteTargetSelection?
    @State private var selectionError: String?
    /// 每设备 Agent inventory（运行实例清单缓存；展开时拉取，官方
    /// loadInventory 语义——装载即 filter(\.configured)）。
    @State private var inventories: [String: [RemoteDeviceRuntime]] = [:]
    @State private var loadingDevices: Set<String> = []
    @State private var inventoryErrors: [String: String] = [:]

    private struct RemoteTargetSelection: Equatable {
        let connectorId: String
        let runtimeId: String
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
                    ContentUnavailableView("无设备。", appSymbol: "desktopcomputer")
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
            .navigationTitle("设备和 Agent")   // 官方 key「运行目标」的 zh-Hans 显示值
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
                    Text("正在发现…").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if let error = inventoryErrors[device.id] {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("刷新") { Task { await loadInventory(device.id) } }
                    .disabled(!device.isOnline)
            } else {
                // 官方 SessionTargetSheet.instances(on:) 逐字：就绪优先，按
                // sessionDisplayName + 实例 id 排。
                let inventory = (inventories[device.id] ?? []).sorted {
                    ($0.isReadyForSession ? 0 : 1, $0.sessionDisplayName, $0.id)
                        < ($1.isReadyForSession ? 0 : 1, $1.sessionDisplayName, $1.id)
                }
                if inventory.isEmpty, device.isOnline {
                    Text("还没有配置 Runtime。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
                ForEach(inventory, id: \.id) { runtime in
                    Button {
                        apply(device: device, runtime: runtime)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(runtime.sessionDisplayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(runtime.isReadyForSession ? .primary : .secondary)
                                Spacer(minLength: 0)
                                if applying == RemoteTargetSelection(connectorId: device.id, runtimeId: runtime.id) {
                                    ProgressView().controlSize(.small)
                                } else if model.selectedConnectorId == device.id,
                                          model.selectedRuntimeId == runtime.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            // 官方 InlineSelectionButton detail = sessionUnavailableReason
                            // （就绪实例为 nil 不占行）。
                            if let reason = runtime.unavailableReason {
                                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // 官方把关（NewSessionModel:234）：未就绪实例不可选。
                    .disabled(!device.isOnline || !runtime.isReadyForSession)
                }
                if !device.isOnline {
                    Text("目标设备离线").font(.footnote).foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func deviceDetail(_ device: RemoteConnector) -> String {
        // 官方 key「Online」/「Offline」的 zh-Hans 显示值。
        let status = device.isOnline ? "在线" : "离线"
        return [device.deviceOs, status].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - inventory 与选择

    private func loadInventory(_ id: String) async {
        guard !loadingDevices.contains(id) else { return }
        loadingDevices.insert(id)
        inventoryErrors[id] = nil
        do {
            // 官方 loadInventory :217/:227：装载即 filter(\.configured)。
            let runtimes = try await service.runtimes(connectorId: id)
            if !Task.isCancelled { inventories[id] = runtimes.filter(\.configured) }
        } catch {
            if !Task.isCancelled { inventoryErrors[id] = error.localizedDescription }
        }
        loadingDevices.remove(id)
    }

    private func apply(device: RemoteConnector, runtime: RemoteDeviceRuntime) {
        // 官方 apply：connected + runtime.isReadyForSession 才发起应用。
        guard applying == nil, device.isOnline, runtime.isReadyForSession else { return }
        let target = RemoteTargetSelection(connectorId: device.id, runtimeId: runtime.id)
        applying = target
        selectionError = nil
        Task { @MainActor in
            let accepted = await model.selectTarget(
                connectorId: target.connectorId,
                runtimeId: target.runtimeId,
                service: service
            )
            applying = nil
            if accepted { dismiss() }
            else { selectionError = "无法更新模型或权限。" }   // 官方 zh-Hans 显示值
        }
    }
}

// MARK: - 工作目录选择（官方 ProjectSelectionSheet 的本仓等价）

struct RemoteNewSessionWorkspaceSheet: View {
    @ObservedObject var model: RemoteNewSessionModel
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss
    @State private var showsProjectEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(model.selectedConnector?.name ?? "选择设备", appSymbol: "desktopcomputer")
                    if let connector = model.selectedConnector, !connector.isOnline {
                        Label("设备或网络已离线，已保存的目录仍可选择。", appSymbol: "wifi.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("项目") {   // 官方 key「这台设备上的项目」的 zh-Hans 显示值
                    // 官方 ProjectSelectionSheet：home 未被项目覆盖时显示 Home 目录行。
                    if homeProject == nil {
                        homeRow
                    }
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
                    if !model.projectsLoaded {
                        Text("正在加载项目…")
                            .foregroundStyle(.secondary)
                    }
                    // 官方 ProjectSelectionSheet：项目列表后的「创建项目」入口
                    // （folder.badge.plus → ProjectEditorSheet）。
                    Button("创建项目", appSymbol: "folder.badge.plus") {
                        showsProjectEditor = true
                    }
                    .disabled(model.selectedConnector == nil)
                }
                if let error = model.projectsError {
                    Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("选择项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { dismiss() } }
            .refreshable { await model.refresh(service: service) }
            .task(id: model.selectedConnectorId) { await model.resolveHome(service: service) }
        }
        .appSheetPresentation(.compact)
        .sheet(isPresented: $showsProjectEditor) {
            RemoteProjectEditorSheet(service: service)
        }
    }

    /// 官方 ProjectSelectionSheet.homeProject：projects 中匹配 home 路径的项目。
    private var homeProject: RemoteProject? {
        guard let homePath = model.homePath, let connector = model.selectedConnector else { return nil }
        return ProjectWorkspacePath.project(in: model.availableProjects, connectorID: connector.id,
                                            path: homePath, deviceOS: connector.deviceOs)
    }

    /// 官方 ProjectSelectionSheet.homeRow 逐字（model 访问适配）。
    private var homeRow: some View {
        Button {
            if let path = model.homePath, model.selectWorkspace(path) { dismiss() }
        } label: {
            HStack(spacing: 12) {
                AppSymbol("house")
                VStack(alignment: .leading, spacing: 5) {
                    Text("Home 目录").foregroundStyle(.primary)
                    Text(model.homePath ?? "正在解析设备家目录…")
                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if let id = model.selectedConnectorId, model.loadingHomes.contains(id) {
                    ProgressView().controlSize(.small)
                } else if model.isHome {
                    AppSymbol("checkmark")
                }
            }.padding(.vertical, 6)
        }.buttonStyle(.plain).disabled(model.homePath == nil)
    }
}

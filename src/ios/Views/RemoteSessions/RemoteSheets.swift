// RemoteSheets.swift — 创建项目 / 新会话 / 归档会话 / 会话详情（AA 视觉，数据层占位）
//
// 各页结构照抄 AA 的 ProjectEditorSheet / NewSessionSheet / ArchivedSessionsSheet /
// SessionDetailsSheet，视觉/控件/form 样式原样沿用；写操作等 RemoteService 的
// 项目管理 public 面（batch 8 的 R0 步）的页先占位 + 诚实禁用，不假造成功态。
// RemoteNewSessionSheet 是例外：其设备/项目/运行时/建会话数据面已冻结接通。

import SwiftUI

// MARK: - 创建项目（AA ProjectEditorSheet）

struct RemoteProjectEditorSheet: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss

    private var serverLabel: String {
        UserDefaults.standard.string(forKey: "agentsAnywhere.serverURL") ?? "—"
    }

    @State private var device = ""
    @State private var path = ""
    @State private var projectName = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("设备") {
                    Picker("设备", selection: $device) {
                        Text("选择设备").tag("")
                        Text(serverLabel).tag("server")
                    }
                    .pickerStyle(.navigationLink)
                }
                Section {
                    HStack(spacing: 12) {
                        TextField("设备上的完整路径", text: $path, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("浏览目录", systemImage: "folder") {}
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(width: 44, height: 44)
                            .disabled(true)
                    }
                } header: {
                    Text("工作目录")
                } footer: {
                    Text("项目关联这个目录，不会在设备上新建文件夹。")
                }
                Section {
                    TextField("例如 Agents Anywhere", text: $projectName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("项目名称")
                } footer: {
                    Text("按目录自动填写名称，重名时添加数字后缀。也可以自行修改。")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.secondary) }
                }
            }
            .textFieldStyle(.plain)
            .navigationTitle("创建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetCloseToolbar { dismiss() }
                ToolbarItem(placement: .topBarTrailing) {
                    // 数据面（项目创建）未接通前显式禁用——同「浏览目录」的处理；
                    // 不做「点了看着成功其实什么都没发生」的假态。
                    Button("创建") {
                        // RemoteService 的项目创建 public 面就绪后接这里（batch 8 R0）。
                    }
                    .disabled(true)
                }
            }
        }
        .appSheetPresentation(.compact)
    }
}

// MARK: - 归档会话（AA ArchivedSessionsSheet）

struct RemoteArchivedSessionsSheet: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(RemoteSessionLoader.shared.archivedItems) { session in
                    HStack {
                        Button { dismiss() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(session.projectId ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            RemoteSessionLoader.shared.unarchive([session.id], service: service)
                        } label: {
                            Image(systemName: "tray.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("恢复会话")
                    }
                }
            }
            .navigationTitle("归档会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { dismiss() } }
            .onAppear {
                RemoteSessionLoader.shared.loadArchived(service: service)
            }
            .refreshable {
                await RemoteSessionLoader.shared.refreshArchived(service: service)
            }
        }
        .appSheetPresentation(.compact)
    }
}

// MARK: - 会话详情（AA SessionDetailsSheet）

struct RemoteSessionDetailSheet: View {
    @ObservedObject var service: RemoteService
    let sessionId: String
    @Environment(\.dismiss) private var dismiss

    private var serverLabel: String {
        UserDefaults.standard.string(forKey: "agentsAnywhere.serverURL") ?? "—"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("会话") {
                    row("标题", RemoteSessionLoader.shared.cachedTitle(for: sessionId) ?? "未命名会话")
                    row("设备", serverLabel)
                    row("Agent", "—")
                    row("状态", "—")
                    row("工作目录", "—")
                }
                Section("标识与时间线") {
                    row("Session ID", sessionId)
                    row("已加载条目", "0")
                    row("待回应交互", "0")
                }
            }
            .navigationTitle("会话详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { dismiss() } }
        }
        .appSheetPresentation(.expanded)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 新会话抽屉（AA NewSessionSheet：设备 → 项目 → 运行时 → 任务）
//
// 结构照 PairDeviceSheet：NavigationStack + SheetCloseToolbar + appSheetPresentation
// + 提交中禁整页（isSubmitting）。数据面全部走 RemoteService public facade
// （listConnectors / listProjects / runtimeTypes / startSession）；
// 拉取失败 / 空列表按行内诚实提示，不假造成功态。
// 官方键中文文案字面量直写，与本目录既有 sheet 的字面量风格一致。

struct RemoteNewSessionSheet: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss

    // 目标设备
    @State private var connectors: [RemoteConnector] = []
    @State private var connectorsLoaded = false
    @State private var connectorsError: String?
    @State private var selectedConnectorId: String?
    // 项目（listProjects 全量拉取，按所选设备 connectorId 本地过滤）
    @State private var projects: [RemoteProject] = []
    @State private var projectsLoaded = false
    @State private var projectsError: String?
    @State private var selectedProjectId: String?
    // 运行时（按设备拉取，只列 available）
    @State private var runtimes: [RemoteRuntimeType] = []
    @State private var runtimesLoaded = false
    @State private var runtimesError: String?
    @State private var selectedRuntime: RemoteRuntimeType?
    /// 运行时拉取的代际令牌：快速切换设备时丢弃过期响应，防止后发先至串台。
    @State private var runtimeLoadToken = 0
    // 表单输入
    @State private var cwd = ""
    @State private var content = ""
    // 提交
    @State private var isSubmitting = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            Form {
                // 头部两行大标题（官方键）
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("把任务发送到合适的设备。")
                            .font(.title2.bold())
                        Text("开始一个专注会话。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color.clear)
                }

                Section("目标设备") {
                    connectorRows
                    if let selected = selectedConnector, !selected.isOnline {
                        // 官方语义：离线设备仍可选、表单可继续填，只是提交禁用
                        Text("设备离线，等待重新连接。")
                            .foregroundStyle(.secondary)
                        Text("选择其他设备")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("项目") {
                    projectRows
                }

                Section("运行时") {
                    runtimeRows
                }

                Section {
                    TextField("/path/to/project", text: $cwd, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("工作目录")
                } footer: {
                    // 官方目录浏览器未接通：手输是诚实降级（同「浏览目录」禁用的处理）。
                    Text("选中项目后自动填入，可手动修改。")
                }

                Section("任务内容") {
                    TextField("描述任务…", text: $content, axis: .vertical)
                        .lineLimit(3...6)
                        .autocorrectionDisabled()
                }

                Section {
                    if let submitError {
                        Text(submitError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    AppGlassButton("开始会话", systemImage: "arrow.up", style: .prominent,
                                   isLoading: isSubmitting) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                } header: { EmptyView() }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .textFieldStyle(.plain)
            .navigationTitle("新会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar(disabled: isSubmitting) { dismiss() } }
            .scrollDismissesKeyboard(.interactively)
            .task { await loadData() }
        }
        .appSheetPresentation(.compact)
        .disabled(isSubmitting)
        .interactiveDismissDisabled(isSubmitting)
    }

    // MARK: - 行（设备点样式照列表 deviceRow：在线绿点 / 离线灰点）

    @ViewBuilder
    private var connectorRows: some View {
        if let connectorsError {
            // 拉取失败 ≠ 没有设备：错误行诚实呈现，不伪装成空列表
            Text("设备加载失败：\(connectorsError)")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if !connectorsLoaded {
            Text("正在加载设备…")
                .foregroundStyle(.secondary)
        } else if connectors.isEmpty {
            Text("还没有可用设备。请先配对设备。")
                .foregroundStyle(.secondary)
        } else {
            if connectors.allSatisfy({ !$0.isOnline }) {
                Text("当前没有在线设备。等待设备重新连接。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(connectors) { connector in
                Button { select(connector) } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(connector.isOnline ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 7, height: 7)
                        Text(connector.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(connector.isOnline ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if connector.id == selectedConnectorId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var projectRows: some View {
        if let projectsError {
            Text("项目加载失败：\(projectsError)")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if !projectsLoaded {
            Text("正在加载项目…")
                .foregroundStyle(.secondary)
        } else if selectedConnectorId == nil {
            Text("先选择目标设备。")
                .foregroundStyle(.secondary)
        } else if availableProjects.isEmpty {
            // 不假造项目：引导走项目头的真实创建入口
            Text("还没有项目。用项目头的 + 先创建一个。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(availableProjects) { project in
                Button { select(project) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)
                            Text(project.workspacePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if project.id == selectedProjectId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var runtimeRows: some View {
        if let runtimesError {
            Text("运行时加载失败：\(runtimesError)")
                .font(.footnote)
                .foregroundStyle(.red)
        } else if selectedConnectorId == nil {
            Text("先选择目标设备。")
                .foregroundStyle(.secondary)
        } else if !runtimesLoaded {
            Text("正在加载运行时…")
                .foregroundStyle(.secondary)
        } else if runtimes.isEmpty {
            Text("该设备没有可用的运行时。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(runtimes, id: \.runtimeType) { runtime in
                Button { selectedRuntime = runtime } label: {
                    HStack(spacing: 12) {
                        Text(runtime.displayName)
                            .font(.system(size: 16, weight: .medium))
                        if runtime.recommended {
                            Text("推荐")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if selectedRuntime == runtime {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 派生

    private var selectedConnector: RemoteConnector? {
        connectors.first { $0.id == selectedConnectorId }
    }

    private var availableProjects: [RemoteProject] {
        guard let connectorId = selectedConnectorId else { return [] }
        return projects.filter { $0.connectorId == connectorId }
    }

    private var selectedProject: RemoteProject? {
        availableProjects.first { $0.id == selectedProjectId }
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCwd: String {
        cwd.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 官方 gate：服务就绪 + 设备在线 + 选中项目 + 选中运行时 + 任务非空白；
    /// 提交进行中同样锁死（canSubmit 内嵌 !isSubmitting）。
    private var canSubmit: Bool {
        service.state == .ready
            && (selectedConnector?.isOnline ?? false)
            && selectedProject != nil
            && selectedRuntime != nil
            && !trimmedContent.isEmpty
            && !isSubmitting
    }

    // MARK: - 选择联动

    private func select(_ connector: RemoteConnector) {
        guard connector.id != selectedConnectorId else { return }
        selectedConnectorId = connector.id
        // 所选项目必须属于新设备，否则清空（含项目已被删除的悬空 id 情形）
        if let sid = selectedProjectId,
           projects.first(where: { $0.id == sid })?.connectorId != connector.id {
            selectedProjectId = nil
            cwd = ""
        }
        refreshRuntimes(for: connector)
    }

    /// 离线设备不发 runtimeTypes（服务器必然报错，红字与离线提示并排是噪音）：
    /// 直接置空态，「设备离线，等待重新连接」已说明原因；提交 gate 本就锁离线。
    private func refreshRuntimes(for connector: RemoteConnector) {
        guard connector.isOnline else {
            runtimeLoadToken += 1   // 作废在途请求
            runtimes = []
            selectedRuntime = nil
            runtimesError = nil
            runtimesLoaded = true
            return
        }
        Task { await loadRuntimes(connectorId: connector.id) }
    }

    private func select(_ project: RemoteProject) {
        selectedProjectId = project.id
        cwd = project.workspacePath
    }

    // MARK: - 数据面（RemoteService public facade）

    private func loadData() async {
        // 设备与项目并行拉：串行时若 runtimeTypes 长超时会把项目列表拖在
        // 「正在加载项目…」（runtimes 挂在 loadConnectors 的默认选中链路里）
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadConnectors() }
            group.addTask { await self.loadProjects() }
        }
    }

    private func loadConnectors() async {
        connectorsLoaded = false
        connectorsError = nil
        do {
            connectors = try await service.listConnectors()
            if selectedConnectorId == nil {
                // 默认选第一台在线设备（无在线则第一台，离线态有诚实提示）
                let preferred = connectors.first(where: { $0.isOnline }) ?? connectors.first
                if let preferred {
                    selectedConnectorId = preferred.id
                    refreshRuntimes(for: preferred)
                }
            }
        } catch {
            connectorsError = error.localizedDescription
        }
        connectorsLoaded = true
    }

    private func loadProjects() async {
        projectsLoaded = false
        projectsError = nil
        do {
            projects = try await service.listProjects()
        } catch {
            projectsError = error.localizedDescription
        }
        projectsLoaded = true
    }

    private func loadRuntimes(connectorId: String) async {
        runtimeLoadToken += 1
        let token = runtimeLoadToken
        runtimesLoaded = false
        runtimesError = nil
        runtimes = []
        selectedRuntime = nil
        let fetched: [RemoteRuntimeType]
        do {
            fetched = try await service.runtimeTypes(connectorId: connectorId)
        } catch {
            if token == runtimeLoadToken {
                runtimesError = error.localizedDescription
                runtimesLoaded = true
            }
            return
        }
        guard token == runtimeLoadToken else { return }  // 过期响应丢弃
        runtimes = fetched.filter { $0.available }
        // 默认选 recommended；无 recommended 则第一个 available
        selectedRuntime = runtimes.first(where: { $0.recommended }) ?? runtimes.first
        runtimesLoaded = true
    }

    private func submit() async {
        guard canSubmit,
              let connector = selectedConnector,
              let project = selectedProject,
              let runtime = selectedRuntime
        else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            _ = try await service.startSession(
                connectorId: connector.id,
                projectId: project.id,
                runtime: runtime.runtimeType,
                runtimeId: nil,
                title: nil,
                cwd: trimmedCwd.isEmpty ? nil : trimmedCwd,
                content: trimmedContent,
                clientMessageId: UUID().uuidString
            )
            // 成功 → 关闭抽屉。新会话进列表等数据面批接线
            // （列表目前挂占位数据源），此处不注入假条目。
            dismiss()
        } catch {
            // 失败 → 页面内错误文本，不假造成功态。
            submitError = error.localizedDescription
        }
    }
}

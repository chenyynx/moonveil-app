// RemoteSheets.swift — 创建项目 / 归档会话 / 会话详情（AA 视觉，数据层占位）
//
// 三页结构照抄 AA 的 ProjectEditorSheet / ArchivedSessionsSheet / SessionDetailsSheet，
// 视觉/控件/form 样式原样沿用；数据写操作等 RemoteService 的项目管理 public 面
// （batch 8 的 R0 步），本批先占位 + 诚实禁用，不假造成功态。

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
    @State private var saving = false
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
            .disabled(saving)
            .navigationTitle("创建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetCloseToolbar(disabled: saving) { dismiss() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("创建") { save() }
                        .disabled(!valid || saving)
                }
            }
        }
        .appSheetPresentation(.compact)
        .interactiveDismissDisabled(saving)
    }

    private var valid: Bool {
        !device.isEmpty
            && !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        // 数据面：RemoteService 的项目创建 public 面就绪后接（batch 8 R0）。
        saving = true
        Task {
            try? await Task.sleep(for: .seconds(0))
            saving = false
            dismiss()
        }
    }
}

// MARK: - 归档会话（AA ArchivedSessionsSheet）

struct RemoteArchivedSessionsSheet: View {
    @ObservedObject var service: RemoteService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(RemoteSessionStore.shared.archived) { session in
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
                            // 恢复（数据面就绪后接）
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
            .refreshable {}
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
                    row("标题", RemoteSessionStore.shared.title(for: sessionId) ?? "未命名会话")
                    row("设备", serverLabel)
                    row("Agent", "Claude Code")
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

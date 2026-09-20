// RemoteSheets.swift — 创建项目 / 归档会话 / 会话详情（AA 视觉）
//
// 各页结构照抄 AA 的 ProjectEditorSheet / ArchivedSessionsSheet /
// SessionDetailsSheet，视觉/控件/form 样式原样沿用；写操作等 RemoteService 的
// 项目管理 public 面（batch 8 的 R0 步）的页先占位 + 诚实禁用，不假造成功态。
// 新会话页已迁至 RemoteNewSessionView（全屏，AA NewSessionView 形态，2026-09-20）。

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

// RemoteNewSessionView.swift — 新会话全屏页（AA 官方
// Views/Chat/NewSessionView.swift 形态移植；数据面走 RemoteNewSessionModel）。
//
// 形态（官方对齐）：顶栏 [关闭] … [目标胶囊]；内容 = 欢迎区（glyph 揭示动画 +
// 随机大标题 + 两行副标题）→ 工作目录行（下划线）→ 状态行（设备/网络/Agent）；
// 底部 composer（+ / 描述任务… / 发送）。
//
// 批次占位（诚实，不假造；见 PATCHES 台账）：
//   • composer 的 + （附件与对话选项）与模型/权限设置 → 随附件与设置批次接通，
//     当前禁用呈现（不产生假成功态）。
//   • 工作目录行的文件系统浏览 → 目录选择 sheet 走项目列表（数据面已有）。
//   • 草稿持久化（官方 ComposerDraft）→ 后续批次。

import SwiftUI

struct RemoteNewSessionView: View {
    @ObservedObject var service: RemoteService
    /// 创建成功回调（sessionId）——列表页据此刷新。
    var onCreated: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = RemoteNewSessionModel()
    @State private var showsTarget = false
    @State private var showsWorkspace = false

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 28) {
                            RemoteNewSessionWelcomeView { workspaceButton }
                            statusContent
                        }
                        .padding(24)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: viewport.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.refresh(service: service) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { closeButton }
                ToolbarItem(placement: .topBarTrailing) { targetButton }
            }
        }
        .sheet(isPresented: $showsTarget) {
            RemoteNewSessionTargetSheet(model: model, service: service)
        }
        .sheet(isPresented: $showsWorkspace) {
            RemoteNewSessionWorkspaceSheet(model: model, service: service)
        }
        .task { await model.load(service: service) }
    }

    // MARK: - 状态内容（官方 statusContent：连接状态 / 创建中 / 错误）

    @ViewBuilder
    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let status = model.connectionStatus {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if status.showsSpinner {
                            ProgressView().controlSize(.small)
                        } else {
                            AppSymbol(status.icon, size: 18)
                        }
                        Text(status.title).font(.subheadline.weight(.medium))
                    }
                    if !status.detail.isEmpty {
                        Text(status.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    if case .deviceOffline = status {
                        Button("选择其他设备") { showsTarget = true }
                    }
                    if case .agentNotReady = status {
                        Button("选择 Agent") { showsTarget = true }
                    }
                }
                .multilineTextAlignment(.leading)
            }
            if model.isCreating {
                Label("正在创建会话…", appSymbol: "arrow.up.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("重新连接") { Task { await model.refresh(service: service) } }
                }
            }
        }
        .multilineTextAlignment(.leading)
    }

    // MARK: - 工作目录行（官方 workspaceButton：名称 + 路径 + 下划线）

    private var workspaceButton: some View {
        Button { showsWorkspace = true } label: {
            HStack(spacing: 6) {
                Text(model.workspaceName)
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).layoutPriority(1)
                if !model.workspacePath.isEmpty {
                    Text(model.workspacePath)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                AppSymbol("chevron.down", size: 12).foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.secondary.opacity(0.35)).frame(height: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(model.selectedConnector == nil || model.isCreating)
    }

    // MARK: - 顶栏（关闭 + 目标胶囊）

    private var closeButton: some View {
        Button { dismiss() } label: {
            AppSymbol("xmark", size: 15)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color(.secondarySystemBackground), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }

    /// 目标胶囊：官方 targetButton ——「设备和 Agent · 设备名 ˅」。
    private var targetButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            showsTarget = true
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(model.targetRuntimeName)
                        .fontWeight(.semibold).layoutPriority(1)
                    Text(verbatim: "·").foregroundStyle(.secondary)
                    Text(verbatim: model.targetDeviceName)
                        .foregroundStyle(.secondary).truncationMode(.middle)
                }
                .font(.subheadline)
                .lineLimit(1)
                AppSymbol("chevron.down", size: 12).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isCreating)
        .accessibilityLabel("选择设备和 Agent")
        .accessibilityValue([model.targetRuntimeName, model.targetDeviceName].joined(separator: " · "))
    }

    // MARK: - Composer（官方 ChatComposerDock 形态的基础版）

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // 附件与对话选项：随附件批次接通（当前禁用，不假造入口）。
            Button {} label: {
                AppSymbol("plus", size: 22)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel("附件与对话选项")

            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("描述任务...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 7)
                        .allowsHitTesting(false)
                }
                TextField("", text: $model.text, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .padding(.vertical, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { send() } label: {
                AppSymbol("arrow.up", size: 17)
                    .foregroundStyle(AppTheme.primaryControlForeground(colorScheme))
                    .frame(width: 32, height: 32)
                    .background(
                        AppTheme.primaryControlBackground(colorScheme)
                            .opacity(model.canCreate && !model.isCreating ? 1 : 0.42),
                        in: Circle()
                    )
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canCreate)
            .accessibilityLabel("发送消息")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func send() {
        Task {
            if let id = await model.create(service: service) {
                onCreated(id)
                dismiss()
            }
        }
    }
}

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var bodyLineHeight: CGFloat = 22

    private var controls: ChatControlMetrics { .init(bodyLineHeight: bodyLineHeight) }
    @StateObject private var model = RemoteNewSessionModel()
    @State private var showsTarget = false
    @State private var showsWorkspace = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                GeometryReader { viewport in
                    ScrollView {
                        RemoteNewSessionContentLayout(viewportHeight: max(0, viewport.size.height - 48)) {
                            RemoteNewSessionWelcomeView { workspaceButton }
                            statusContent
                        }
                        .padding(24)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable { await model.refresh(service: service) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // 官方 NewSessionView 同款调用（ChatComposerDock 完整搬运，2026-09-20）。
                    ChatComposerDock(draft: model.draft, settings: model.settings,
                        maximumEditorHeight: min(160, max(72, geometry.size.height * 0.30)), controls: controls,
                        canSend: model.canCreate, canAttach: model.canAttach && model.prepared,
                        canSelectModel: model.allowsModelCatalog,
                        canSelectPermission: model.allowsPermissionCatalog,
                        isBusy: model.isCreating, isLoadingSettings: model.settingsLoading,
                        settingsError: model.settingsError,
                        onSend: { text in
                            if let id = await model.create(text: text, service: service) {
                                onCreated(id)
                                dismiss()
                            }
                        },
                        onLoadSettings: { await model.prepareTarget(service: service) },
                        onApplySettings: { model.saveSelections(); return true },
                        applyError: { model.settingsError })
                }
            }
            // 顶栏：左上角 = 本机页面同款系统返回标（chevron，pp 2026-09-21
            // 「这个页面的左上角那个图标应该是跟本地页面一样的那个返回标」——
            // 官方此处是 SidebarMenuIcon ≡，本仓按 pp 拍板换返回箭头，动作 = dismiss
            // 与原 onMenu 语义一致）。ChatPageToolbar(title: "") 在此仅贡献左侧键，
            // 改用原生 toolbar 等价替换（title 本就为空，无 subtitle/status 面），
            // 共享件 ChatPageToolbar 保持官方逐字不动（SessionChatView 仍在用 ≡）。
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .accessibilityLabel(String(localized: "返回"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { targetButton }
            }
        }
        // 官方 ChatDetailNavigation 非 drawer 分支的两个视觉点（drawer 宿主逻辑
        // 依赖官方侧栏体系，本仓无侧栏不搬）：systemBackground 背景 +
        // primaryControl tint（黑/白）——系统玻璃与控件据此呈中性色。
        .background(Color(uiColor: .systemBackground))
        .tint(AppTheme.primaryControlBackground(colorScheme))
        .sheet(isPresented: $showsTarget) {
            RemoteNewSessionTargetSheet(model: model, service: service)
        }
        .sheet(isPresented: $showsWorkspace) {
            RemoteNewSessionWorkspaceSheet(model: model, service: service)
        }
        .task {
            await model.load(service: service)
            // 官方 NewSessionModel.restoreCreationDraft 的本仓消费点：聊天页
            // 「返回编辑」→ services.pendingEditCreation 暂存 → 此处回填草稿并聚焦
            // 原会话目标（设备/工作目录/项目/runtime），然后清空暂存。
            if let services = service.chat,
               let pending = services.pendingEditCreation {
                services.pendingEditCreation = nil
                model.restoreCreationDraft(
                    connectorId: pending.0.connectorId,
                    workspacePath: pending.0.cwd,
                    projectId: pending.0.projectId,
                    runtimeType: pending.0.runtimeType,
                    text: pending.1.content,
                    attachments: pending.1.attachments)
            }
        }
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
                        Button("选择代理") { showsTarget = true }
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

    /// 目标胶囊：官方 targetButton 逐字（remote 适配仅两处：model.draft.isFocused
    /// → resignFirstResponder；model.runtime/model.connector → 本仓 model 字段。
    /// 含官方的 maxWidth/fixedSize/Group 尺寸细节——胶囊交给系统工具栏玻璃）。
    private var targetButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            showsTarget = true
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    // 官方 key「运行目标」的 zh-Hans 显示值 = 「设备和 Agent」
                    Text(model.selectedRuntime?.displayName ?? String(localized: "设备和 Agent"))
                        .fontWeight(.semibold).layoutPriority(1)
                    if let device = model.selectedConnector {
                        Text(verbatim: "·").foregroundStyle(.secondary)
                        Text(verbatim: device.name).foregroundStyle(.secondary)
                            .truncationMode(.middle)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: horizontalSizeClass == .regular ? 280 : 210, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                Group {
                    if model.isPreparing { ProgressView().controlSize(.mini) }
                    else { AppSymbol("chevron.down", size: 12) }
                }.frame(width: 14, height: 14)
            }
        }
        .disabled(model.isCreating)
        .accessibilityLabel(String(localized: "选择设备和 Agent"))
        .accessibilityValue([model.selectedRuntime?.displayName, model.selectedConnector?.name].compactMap { $0 }.joined(separator: " · "))
        .accessibilityIdentifier("chat.new.target")
    }

}

/// Center the welcome and workspace alone. Notices flow below that anchor and
/// extend the scrollable page when needed, rather than recentering the welcome.
/// （AA 官方 NewSessionView.swift 底部 NewSessionContentLayout 逐字，改名。）
private struct RemoteNewSessionContentLayout: Layout {
    let viewportHeight: CGFloat
    private let spacing: CGFloat = 28

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let childProposal = ProposedViewSize(width: width, height: nil)
        let welcome = subviews[0].sizeThatFits(childProposal)
        let status = subviews[1].sizeThatFits(childProposal)
        let top = max(0, (viewportHeight - welcome.height) / 2)
        let statusHeight = status.height > 0 ? spacing + status.height : 0
        return CGSize(width: width, height: max(viewportHeight, top + welcome.height + statusHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        let welcome = subviews[0].sizeThatFits(childProposal)
        let top = max(0, (viewportHeight - welcome.height) / 2)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + top), anchor: .topLeading, proposal: childProposal)
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + top + welcome.height + spacing),
            anchor: .topLeading, proposal: childProposal)
    }
}

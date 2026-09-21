// 差异/落地说明补充：
//   • 文案：本文件 String(localized:) 键为官方源键，取值已按官方 Localizable.xcstrings
//     的 zh-Hans 显示值落地（先例 COMPOSER-FULL / NEWSESSION-COPY；官方源键与其 en/zh
//     条目见 origin-cache/Resources/Localization/Localizable.xcstrings）。
import SwiftUI

/// 会话时间线入口（官方 Views/Chat/ChatTimelineView.swift 的滚动编排骨架）。
///
/// 版本分派（铁律④）：官方编排整体建立在 iOS 18 滚动 API 上
/// （`ScrollPosition` / `onScrollPhaseChange` / `onScrollGeometryChange` /
/// `onScrollVisibilityChange` / `onGeometryChange` / `scrollEdgeEffectStyle` /
/// `defaultScrollAnchor(for:)`），且 `@State var position = ScrollPosition()` 这类
/// iOS 18 类型无法在 17 target 上声明，故 18+ 走官方编排
/// （`ChatTimelineOrchestrationView`，逐字），17 走降级壳
/// （`ChatTimelineLegacyView`，内容渲染与官方同源）。
/// 17 降级差异（不是裁剪，是系统能力缺位）：
/// ①拖拽到边缘即拉页 → 无（改用官方页内「加载较早/更新的记录」按钮，功能等价、需点击）；
/// ②实时尾随的 interactiveSpring 边缘动画 → ScrollViewReader 无动画跟尾；
/// ③历史页位置精确恢复（TimelineHistoryPosition）→ 不做，读者停在页首。
/// 「到底部」胶囊按钮两版都在（17 版按自测几何判定）。
struct ChatTimelineView: View {
    let model: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    let onFile: (String) -> Void

    var body: some View {
        if #available(iOS 18.0, *) {
            ChatTimelineOrchestrationView(model: model, onAttachment: onAttachment, onFile: onFile)
        } else {
            ChatTimelineLegacyView(model: model, onAttachment: onAttachment, onFile: onFile)
        }
    }
}

@available(iOS 18.0, *)
private struct ChatTimelineOrchestrationView: View {
    let model: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    let onFile: (String) -> Void
    @State private var historyLayout: TimelineHistoryLayout?
    @State private var historyPosition: TimelineHistoryPosition?
    @State private var hasRequestedOlder = false
    @State private var position = ScrollPosition()
    @State private var scrolling = TimelineScrollState()
    @State private var viewportSample = ChatViewportSample()
    @State private var viewportUpdates = ChatLayoutUpdate<TimelineViewport>()
    @State private var historyUpdates = ChatLayoutUpdate<TimelineHistoryLayout>()
    @State private var latestPull = TimelineHistoryPull()
    @State private var olderPull = TimelineHistoryPull(edge: .older)
    @State private var olderPromptVisible = false
    @State private var olderLoadRequest: Int?
    @State private var latestPromptVisible = false
    @State private var latestLoadRequest: Int?
    @State private var nativePhase = TimelineScrollState.Phase.idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.sidebarDrawerIsTransitioning) private var sidebarIsTransitioning
    @Environment(\.sidebarDrawerObscuresDetail) private var sidebarObscuresDetail
    @ScaledMetric(relativeTo: .caption) private var returnPillHeight: CGFloat = 32

    private var hasInteractions: Bool {
        model.session.notices.notices.contains { $0.isVisible && $0.notice.type == "interaction" }
    }
    private var viewport: TimelineViewport { viewportSample.value ?? scrolling.viewport }
    private var navigationIsSuspended: Bool { sidebarIsTransitioning || sidebarObscuresDetail }
    var body: some View {
        // A sibling overlay receives taps independently of the scroll view's
        // deceleration recognizer. The explicit return intent survives its callbacks.
        ZStack(alignment: .bottom) {
            ScrollView {
                ChatTimelineContent(model: model, onAttachment: onAttachment, onFile: onFile,
                    latestPullReady: latestPull.isReady, isLoadingLatest: latestLoadRequest != nil,
                    olderPullReady: olderPull.isReady, isLoadingOlder: olderLoadRequest != nil,
                    keepsOlderPrompt: hasRequestedOlder, historyAnchor: historyPosition?.origin,
                    onLoadOlder: loadOlder, onLoadLatest: loadLatest,
                    onHistoryLayout: historyDidLayOut,
                    onPromptVisibility: { latestPromptVisible = $0 },
                    onOlderPromptVisibility: { olderPromptVisible = $0 },
                    onTailVisibility: { region, visible in scrolling.tailVisibilityChanged(region, visible: visible) })
                    .equatable()
                    .background { ChatPageScrollEdge() }
            }
            .scrollPosition($position)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
            .aaScrollEdgeSoft()
            .defaultScrollAnchor(.top, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.top, for: .sizeChanges)
            .allowsHitTesting(model.isOpeningReady)
            .accessibilityHidden(!model.isOpeningReady)
            .onScrollPhaseChange { _, phase, context in
                // A phase callback carries a newer authoritative sample.
                viewportUpdates.cancel()
                let mapped: TimelineScrollState.Phase
                switch phase {
                case .idle: mapped = .idle
                case .tracking: mapped = .tracking
                case .interacting: mapped = .interacting
                case .decelerating: mapped = .decelerating
                case .animating: mapped = .animating
                @unknown default: mapped = .idle
                }
                let current = TimelineViewport(geometry: context.geometry)
                let wasInteracting = scrolling.phase == .interacting
                viewportSample.value = current
                scrolling.geometryChanged(current)
                nativePhase = mapped
                // The drawer owns horizontal navigation. Do not interpret its
                // interrupted scroll callbacks as a fresh vertical reading intent.
                if navigationIsSuspended { return }
                if scrolling.phaseChanged(mapped, viewport: current) {
                    // Release ScrollPosition's persistent edge target as soon
                    // as the user takes over, including interrupted animations.
                    releaseScrollPosition()
                    historyPosition?.cancelRestoration()
                    olderPull.begin(at: current, promptVisible: olderPromptVisible,
                        canLoad: model.session.hasOlderItems && !model.session.isLoadingHistory && olderLoadRequest == nil && latestLoadRequest == nil)
                    latestPull.begin(at: current, promptVisible: latestPromptVisible,
                        canLoad: model.session.hasNewerItems && !model.session.isLoadingHistory && latestLoadRequest == nil && olderLoadRequest == nil)
                }
                if mapped == .interacting { latestPull.update(current); olderPull.update(current) }
                if mapped == .idle || mapped == .decelerating {
                    let shouldLoadLatest = latestPull.end(), shouldLoadOlder = olderPull.end()
                    if wasInteracting {
                        if shouldLoadOlder { loadOlder() }
                        else if shouldLoadLatest { loadLatest() }
                    }
                } else if mapped == .animating { latestPull.cancel(); olderPull.cancel() }
            }
            .onScrollGeometryChange(for: TimelineViewport.self) { geometry in
                TimelineViewport(geometry: geometry)
            } action: { _, value in
                viewportUpdates.submit(value) { value in
                    // Offset samples are needed for restoration, but do not change
                    // the rendered page. Publish only dimensions used by following.
                    viewportSample.value = value
                    let previous = scrolling.viewport
                    if previous.contentHeight != value.contentHeight || previous.visibleHeight != value.visibleHeight
                        || previous.topInset != value.topInset {
                        scrolling.geometryChanged(value)
                    }
                    if !navigationIsSuspended && scrolling.phase == .interacting {
                        var latest = latestPull, older = olderPull
                        latest.update(value); older.update(value)
                        if latest != latestPull { latestPull = latest }
                        if older != olderPull { olderPull = older }
                    }
                }
            }
            .onChange(of: navigationIsSuspended, initial: true) { _, suspended in
                viewportUpdates.cancel()
                scrolling.setNavigationSuspended(suspended)
                if suspended {
                    releaseScrollPosition()
                    latestPull.cancel(); olderPull.cancel()
                } else {
                    scrolling.phaseChanged(nativePhase, viewport: viewport)
                    if let historyLayout { historyDidLayOut(historyLayout) }
                }
            }
            .onChange(of: model.session.pendingMessages.last?.id) { _, id in
                if model.isOpeningReady, id != nil && !hasInteractions { scrolling.requestBottom() }
            }
            .onChange(of: model.responseRevision) { _, _ in
                if model.isOpeningReady { scrolling.requestBottom() }
            }
            .onChange(of: hasInteractions, initial: true) { _, presented in
                scrolling.setInteractionPresented(presented)
            }
            .onChange(of: model.isOpeningReady, initial: true) { _, ready in
                if ready { scrolling.open(interactionPresented: hasInteractions) }
            }
            .onChange(of: scrolling.navigationGeneration) { _, _ in
                releaseScrollPosition()
            }
            .task(id: scrolling.pendingBottomRequest) {
                guard let request = scrolling.pendingBottomRequest, !navigationIsSuspended else { return }
                // Coalesce actual layout changes. Scrolling through the same
                // layout cannot restart this animation on every offset callback.
                do { try await Task.sleep(for: .milliseconds(24)) } catch { return }
                guard !Task.isCancelled, !navigationIsSuspended, let command = scrolling.begin(request) else { return }
                scrollToBottom(command)
            }
            .task(id: UserScrollSettlement(needed: scrolling.needsUserScrollSettlement,
                tail: scrolling.tail, generation: scrolling.navigationGeneration)) {
                guard scrolling.needsUserScrollSettlement else { return }
                // Reconcile visibility after the native phase callback. This
                // never holds opening behind a spinner or repeats a scroll.
                do { try await Task.sleep(for: .milliseconds(64)) } catch { return }
                guard !Task.isCancelled else { return }
                scrolling.settleUserScroll()
            }
            .task(id: olderLoadRequest) {
                guard let request = olderLoadRequest else { return }
                await model.session.loadOlder()
                guard !Task.isCancelled, historyPosition?.id == request else { return }
                if !model.session.isValid { historyPosition = nil; olderLoadRequest = nil; return }
                historyPosition?.receivedPage(firstRowID: model.session.timeline.first { $0.value.isVisibleInChat }?.id)
            }
            .task(id: HistorySettlement(id: historyPosition?.id, ready: historyPosition?.isReadyToFinish == true,
                offset: historyPosition?.restoredOffset)) {
                guard let request = historyPosition?.id, historyPosition?.isReadyToFinish == true else { return }
                // Let the point correction reach native layout before releasing
                // its target or ending the spinner. A new measurement restarts this.
                do { try await Task.sleep(for: .milliseconds(64)) } catch { return }
                guard !Task.isCancelled, historyPosition?.id == request else { return }
                if scrolling.navigationGeneration == request, historyPosition?.restoredOffset != nil {
                    position.isPositionedByUser = true
                }
                historyPosition = nil; olderLoadRequest = nil
            }
            .task(id: latestLoadRequest) {
                guard let generation = latestLoadRequest else { return }
                await model.session.loadLatest()
                guard !Task.isCancelled else { return }
                // A drag during the fetch must not be undone when it finishes.
                if scrolling.navigationGeneration == generation { scrolling.requestBottom() }
                latestLoadRequest = nil
            }
            if scrolling.showsBottomButton() {
                Button {
                    latestPull.cancel(); olderPull.cancel()
                    historyPosition?.cancelRestoration()
                    scrolling.requestBottom()
                } label: {
                    Label(String(localized: "到底部"), appSymbol: "arrow.down").font(.caption.weight(.medium)).foregroundStyle(.primary)
                        .padding(.horizontal, 12).frame(height: returnPillHeight)
                        .remoteGlassCapsule(interactive: true)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("chat.timeline.bottom")
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { viewportUpdates.cancel(); historyUpdates.cancel() }
    }
    private func loadOlder() {
        guard model.session.isValid, model.session.hasOlderItems,
              !model.session.isLoadingHistory, olderLoadRequest == nil, latestLoadRequest == nil else { return }
        olderPull.cancel(); latestPull.cancel()
        scrolling.browseHistory()
        position.isPositionedByUser = true
        let layout = historyLayout.flatMap { $0.firstRowID == model.timeline.rows.first?.id ? $0 : nil }
        historyPosition = TimelineHistoryPosition(id: scrolling.navigationGeneration, layout: layout,
            offsetY: viewport.offsetY, topInset: viewport.topInset)
        hasRequestedOlder = true
        olderLoadRequest = scrolling.navigationGeneration
    }
    private func loadLatest() {
        guard model.session.isValid, model.session.hasNewerItems,
              !model.session.isLoadingHistory, latestLoadRequest == nil, olderLoadRequest == nil else { return }
        olderPull.cancel(); latestPull.cancel()
        historyPosition?.cancelRestoration()
        scrolling.requestBottom()
        latestLoadRequest = scrolling.navigationGeneration
    }
    private func scrollToBottom(_ command: TimelineScrollState.BottomCommand) {
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 1, blendDuration: 0.12),
            completionCriteria: .removed) {
            // Let the scroll view resolve its own safe-area/inset coordinate
            // system. The edge target is released when this animation finishes
            // or as soon as a gesture/drawer/approval cancels the command.
            position.scrollTo(edge: .bottom)
        } completion: {
            if scrolling.complete(command) { releaseScrollPosition() }
        }
    }
    private func releaseScrollPosition() {
        guard position.edge != nil || position.point != nil else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { position.isPositionedByUser = true }
    }
    private func historyDidLayOut(_ layout: TimelineHistoryLayout) {
        historyUpdates.submit(layout) { layout in
            if historyLayout != layout { historyLayout = layout }
            guard !navigationIsSuspended, var restoration = historyPosition else { return }
            let offset = restoration.laidOut(layout, generation: scrolling.navigationGeneration)
            if historyPosition != restoration { historyPosition = restoration }
            guard let offset else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { position.scrollTo(y: offset) }
        }
    }
    private struct HistorySettlement: Equatable {
        let id: Int?
        let ready: Bool
        let offset: CGFloat?
    }
    private struct UserScrollSettlement: Equatable {
        let needed: Bool
        let tail: TimelineTailVisibility
        let generation: Int
    }
}

/// Keep the latest measurement without publishing View state inside a layout
/// callback. One main-queue delivery handles a burst; removal invalidates it.
@MainActor private final class ChatLayoutUpdate<Value> {
    private var pending: (() -> Void)?
    private var scheduled = false
    private var generation = 0

    func submit(_ value: Value, apply: @escaping (Value) -> Void) {
        pending = { apply(value) }
        guard !scheduled else { return }
        scheduled = true
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            let update = self.pending
            self.pending = nil
            self.scheduled = false
            update?()
        }
    }

    func cancel() {
        generation &+= 1
        pending = nil
        scheduled = false
    }
}

private struct ChatTimelineContent: View, Equatable {
    let model: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    let onFile: (String) -> Void
    let latestPullReady: Bool
    let isLoadingLatest: Bool
    let olderPullReady: Bool
    let isLoadingOlder: Bool
    let keepsOlderPrompt: Bool
    let historyAnchor: TimelineHistoryLayout?
    let onLoadOlder: () -> Void
    let onLoadLatest: () -> Void
    let onHistoryLayout: (TimelineHistoryLayout) -> Void
    let onPromptVisibility: (Bool) -> Void
    let onOlderPromptVisibility: (Bool) -> Void
    let onTailVisibility: (TimelineTailVisibility.Region, Bool) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.latestPullReady == rhs.latestPullReady && lhs.isLoadingLatest == rhs.isLoadingLatest
            && lhs.olderPullReady == rhs.olderPullReady && lhs.isLoadingOlder == rhs.isLoadingOlder
            && lhs.keepsOlderPrompt == rhs.keepsOlderPrompt && lhs.historyAnchor == rhs.historyAnchor
    }
    var body: some View {
        // [STREAMING-LOOP-FIX] 一次 body 求值内只对 notices 遍历一遍：三个 filter
        // （interactionTargets / 可见通知卡 / 分组去重）合并到开头的两个局部常量。
        // 旧实现对每个 ForEach 各 filter 一次，blocks()/isVisible 访问 @Observable
        // 属性注册依赖；SSE 高频投递时 update() 的 notice=next 赋值（@Observable
        // 不做相等性短路）反复使依赖失效 → body 重算 → 循环（pp 2026-09-22 装机：
        // agent 流式回复时主线程 hang 2.7s、内存 57→520MB、前台被杀）。
        let visibleNotices = model.session.notices.notices.filter(\.isVisible)
        let groups = TimelineGrouping.groups(model.timeline.rows,
            interactionTargets: Set(visibleNotices.compactMap(\.timelineTargetID)))
        let actions = TimelineTurnActions.build(groups: groups, suppressLatest: model.isRunning || model.session.hasNewerItems,
            hasPendingUserMessage: !model.session.hasNewerItems && (!model.timeline.pendingMessages.isEmpty || !model.session.pendingMessages.isEmpty))
        // Prefer a message whose start cannot move into a prefixed tool group.
        // For an all-tools page, retain the existing group's trailing edge.
        let anchorGroup = historyAnchor.flatMap { anchor in groups.first { $0.rows.contains { $0.id == anchor.anchorRowID } } }
            ?? groups.first { $0.rows.first?.structure.groupKind == .single } ?? groups.last
        let anchorEdge = historyAnchor?.edge ?? (anchorGroup?.rows.first?.structure.groupKind == .single ? .top : .bottom)
        // Keep actual row geometry available as Markdown grows and tool groups
        // change height. Hidden tool details own their deferred work separately.
        VStack(alignment: .leading, spacing: 20) {
            if model.session.hasOlderItems || keepsOlderPrompt {
                Group {
                    if isLoadingOlder {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(.circular).controlSize(.small)
                            Text(String(localized: "正在加载较早的消息…"))
                        }.accessibilityElement(children: .combine)
                    } else if model.session.hasOlderItems {
                        Button(action: onLoadOlder) {
                            Text(olderPullReady ? String(localized: "松开加载较早的消息") : String(localized: "加载更早消息"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.disabled(model.session.isLoadingHistory || isLoadingLatest)
                    } else {
                        // Retain the prompt's footprint on the final page; removing
                        // it after restoring would move the reader by another row.
                        Text(String(localized: "已到达会话开头")).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
                .aaScrollVisibility(threshold: 0.9) { onOlderPromptVisibility($0) }
            }
            ForEach(groups) { group in
                SessionTimelineGroupView(group: group, chat: model, onAttachment: onAttachment, onFile: onFile,
                    turnAction: actions[group.id])
                    .id(group.id)
                    .background {
                        // onGeometryChange 是 iOS 18 API；探针只服务 18+ 的历史位置
                        // 恢复（17 回退壳不消费），故 17 上不挂载。
                        if #available(iOS 18.0, *), group.id == anchorGroup?.id, let firstRowID = model.timeline.rows.first?.id {
                            Color.clear.onGeometryChange(for: TimelineHistoryLayout.self) { geometry in
                                let frame = geometry.frame(in: .named("chat.timeline.content"))
                                return TimelineHistoryLayout(firstRowID: firstRowID,
                                    anchorRowID: historyAnchor?.anchorRowID ?? group.id, edge: anchorEdge,
                                    y: anchorEdge == .top ? frame.minY : frame.maxY)
                            } action: { onHistoryLayout($0) }
                        }
                    }
            }
            // [STREAMING-LOOP-FIX] 复用开头的 visibleNotices，不再二次 filter。
            ForEach(visibleNotices.filter { notice in
                !notice.blocks(model.session.id)
                    && !model.timeline.rows.contains(where: { $0.id == notice.timelineTargetID })
            }) { item in SessionInteractionCard(item: item, chat: model) }
            ForEach(model.timeline.pendingMessages) { pending in
                PendingMessageRow(pending: pending, chat: model, onAttachment: onAttachment,
                    onDismiss: { model.session.dismissPendingMessage(id: pending.id) })
                    .id(pending.id)
            }
            if model.session.hasNewerItems {
                Button(action: onLoadLatest) {
                    Group {
                        if isLoadingLatest { ProgressView(String(localized: "正在加载更新的记录…")) }
                        else { Text(latestPullReady ? String(localized: "松开加载更新的记录") : String(localized: "继续上拉加载更新的记录")) }
                    }.font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(model.session.isLoadingHistory || isLoadingLatest || isLoadingOlder)
                .aaScrollVisibility { onPromptVisibility($0) }
            }
            // Constant breathing room: status text and card counts cannot
            // change this spacer or create a spurious follow request.
            Group {
                if let text = model.sendingPlaceholder {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                } else { Color.clear }
            }.frame(height: 32)
                .overlay(alignment: .bottom) {
                    Color.clear.frame(height: 96)
                        .aaScrollVisibility(threshold: 0.01) { onTailVisibility(.near, $0) }
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .overlay(alignment: .bottom) {
                    Color.clear.frame(height: 2)
                        .aaScrollVisibility(threshold: 0.5) { onTailVisibility(.end, $0) }
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .id("tail")
        }
        .modifier(ChatPageContentColumn())
        .coordinateSpace(name: "chat.timeline.content")
    }

}

@available(iOS 18.0, *)
private extension TimelineViewport {
    init(geometry: ScrollGeometry) {
        self.init(contentHeight: geometry.contentSize.height, containerHeight: geometry.containerSize.height,
            topInset: geometry.contentInsets.top, bottomInset: geometry.contentInsets.bottom, offsetY: geometry.contentOffset.y)
    }
}

/// Native offset storage deliberately does not invalidate the SwiftUI view tree.
@MainActor private final class ChatViewportSample {
    var value: TimelineViewport?
}

/// iOS 17 降级壳（差异清单见 ChatTimelineView 头部字据）。内容仍由官方同源的
/// `ChatTimelineContent` 渲染；分页按钮 / 尾随占位 / 交互卡全部保留。
private struct ChatTimelineLegacyView: View {
    let model: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    let onFile: (String) -> Void
    @State private var olderLoadRequest = false
    @State private var latestLoadRequest = false
    @State private var hasRequestedOlder = false
    @State private var viewport = TimelineViewport()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var returnPillHeight: CGFloat = 32

    /// 官方 18+ 用 TimelineTailVisibility 探针判定；17 上以几何自测等价物代替。
    private var atBottom: Bool {
        guard viewport.isMeasured else { return true }
        return viewport.offsetY + viewport.visibleHeight >= viewport.contentHeight - 24
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    ChatTimelineContent(model: model, onAttachment: onAttachment, onFile: onFile,
                        latestPullReady: false, isLoadingLatest: latestLoadRequest,
                        olderPullReady: false, isLoadingOlder: olderLoadRequest,
                        keepsOlderPrompt: hasRequestedOlder, historyAnchor: nil,
                        onLoadOlder: loadOlder, onLoadLatest: loadLatest,
                        onHistoryLayout: { _ in },
                        onPromptVisibility: { _ in },
                        onOlderPromptVisibility: { _ in },
                        onTailVisibility: { _, _ in })
                        .equatable()
                        .background { ChatPageScrollEdge() }
                }
                .background {
                    // onScrollGeometryChange 的 17 等价采样（PreferenceKey + scrollView 坐标）。
                    GeometryReader { reader in
                        Color.clear.preference(key: LegacyViewportKey.self, value: TimelineViewport(
                            contentHeight: reader.frame(in: .scrollView(axis: .vertical)).height,
                            containerHeight: reader.size.height,
                            offsetY: -reader.frame(in: .scrollView(axis: .vertical)).minY))
                    }
                }
                .onPreferenceChange(LegacyViewportKey.self) { viewport = $0 }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.always, axes: .vertical)
                .onAppear { scrollToTail(proxy) }
                .onChange(of: model.responseRevision) { _, _ in followIfAtTail(proxy) }
                .onChange(of: model.timeline.rows.count) { _, _ in followIfAtTail(proxy) }
                .onChange(of: model.session.pendingMessages.count) { _, _ in followIfAtTail(proxy) }
                if !atBottom {
                    Button {
                        scrollToTail(proxy)
                    } label: {
                        Label(String(localized: "到底部"), appSymbol: "arrow.down").font(.caption.weight(.medium)).foregroundStyle(.primary)
                            .padding(.horizontal, 12).frame(height: returnPillHeight)
                            .remoteGlassCapsule(interactive: true)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("chat.timeline.bottom")
                    .padding(.bottom, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func followIfAtTail(_ proxy: ScrollViewProxy) {
        guard atBottom else { return }
        scrollToTail(proxy)
    }
    private func scrollToTail(_ proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo("tail", anchor: .bottom) }
        else { withAnimation(.smooth(duration: 0.24)) { proxy.scrollTo("tail", anchor: .bottom) } }
    }
    private func loadOlder() {
        guard model.session.isValid, model.session.hasOlderItems,
              !model.session.isLoadingHistory, !olderLoadRequest, !latestLoadRequest else { return }
        hasRequestedOlder = true
        olderLoadRequest = true
        Task {
            await model.session.loadOlder()
            olderLoadRequest = false
        }
    }
    private func loadLatest() {
        guard model.session.isValid, model.session.hasNewerItems,
              !model.session.isLoadingHistory, !latestLoadRequest, !olderLoadRequest else { return }
        latestLoadRequest = true
        Task {
            await model.session.loadLatest()
            latestLoadRequest = false
        }
    }
}

private struct LegacyViewportKey: PreferenceKey {
    static var defaultValue = TimelineViewport()
    static func reduce(value: inout TimelineViewport, nextValue: () -> TimelineViewport) { value = nextValue() }
}

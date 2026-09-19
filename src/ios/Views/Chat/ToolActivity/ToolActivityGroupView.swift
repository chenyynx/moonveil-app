import SwiftUI
import Combine

// MARK: - Tool Activity Group View (new-skin chat slot, Grok-style)
//
// [A1-A8, 报告§八/§动画清单] One Grok-style activity stage, rendered whole
// inside its anchor block's cell. State machine (one-way, 铁律: 入口行永留):
//
//   running ── slot: ThinkingDotIcon + "Thinking · N秒" + event rows suffix(2)
//   done    ── entry row: "Thinking ›" (tap → 汇聚页, batch B N6)
//
// Timing is per-segment [A3]: no counter for the first ~0.7s, then "·1秒"
// stepping at 1 Hz from the segment start. The start instant lives in a
// view-layer cache keyed by anchor id (block model is untouched [H4]).

/// 入口行 / Thinking 行统一墨色 [Claude photo_25B6FFE9 实测核心墨色]。
/// [pp 09-18] 运行中「Thinking · N秒」与完成态入口行同色同字重 → 常量上提为
/// 文件级（原先挂在 ToolActivityGroupView 上，同文件的 ThinkingElapsedText 拿不到，
/// 计时那半行会留在 medium + secondary → 一行字两种粗细/冷暖）。
private enum ThinkingRowStyle {
    static let headlineGray = Color(red: 0.478, green: 0.475, blue: 0.455)  // #7A7974
}

struct ToolActivityGroupView: View {
    /// TOOLSPACING-1: user-adjustable gap between tool activity rows (Settings > Tool Status Bar).
    @AppStorage("toolRowSpacing") private var toolRowSpacing: Double = 18
    @ObservedObject var message: ChatMessage
    let segment: TurnActivitySegment
    let isActiveMessage: Bool
    /// [T-ios-coldstart-interrupted-slot] 「中断待恢复」回合（冷启动/重开时
    /// load 检测到的未完成尾巴，非进程内 Stop）。true 时本段按运行槽渲染 +
    /// 计时冻结；仅作用于未被正文收口的段（见 `running`）。
    let interruptedPendingResume: Bool
    /// Batch C: wiring to the aggregation sheet (N6). Nil in mock contexts.
    var onOpenDetail: ((TurnActivitySegment) -> Void)?
    /// Batch C: shell in-flight stop passthrough (feature parity [H6]).
    var onStop: (() -> Void)?

    /// [T-ios-slot-fresh-measure] 首帧即带事件行：`carouselIds` 原先从空数组启动，
    /// 单元格"首次自测量"若发生在 onAppear 播种之前，只量到标题行（≈24pt）并被写
    /// 进布局高度缓存（heightCache 只接受真实测量值）；此后工具运行期间既无
    /// segment 变化、也无流式 flush → 补测通道全静默 → 错误高度一直挂到下一次
    /// 工具事件（pp 09-19 装机实锤：退出聊天页重进必现；
    /// [ThinkingCollapse] HIT frameH=24.0 → POST 125.0 delta=+101.0，距
    /// req#8/#9 DISPATCH 4ms/1ms；气泡与「Thinking」同行、工具行探进玻璃工具条）。
    /// init 预置 = 首帧内容即完整运行槽（≈125pt），首测不再可能量到空槽。
    init(message: ChatMessage,
         segment: TurnActivitySegment,
         isActiveMessage: Bool,
         interruptedPendingResume: Bool = false,
         onOpenDetail: ((TurnActivitySegment) -> Void)? = nil,
         onStop: (() -> Void)? = nil) {
        self.message = message
        self.segment = segment
        self.isActiveMessage = isActiveMessage
        self.interruptedPendingResume = interruptedPendingResume
        self.onOpenDetail = onOpenDetail
        self.onStop = onStop
        // [T-ios-slot-fresh-measure-2] 首帧数据可能尚未就绪（重挂载首 config 时
        // segment/message 仍在换血）→ 实时为空时用"上次成功渲染的行"缓存兜底，
        // 保证首帧带行、首测即 ≈ 真实高度（否则帧级闪塌：24 → 91）。
        let liveRows = segment.toolIds.suffix(3).compactMap { id in
            message.blocks.first { $0.id == id }
        }
        let seedRows = liveRows.isEmpty ? (Self.lastRowsCache[segment.anchorId] ?? []) : liveRows
        _carouselIds = State(initialValue: seedRows.map(\.id))
    }

    // MARK: State

    /// Segment start instant (view-layer cache survives cell rebuilds).
    @State private var startedAt: Date?

    private static var startCache: [UUID: Date] = [:]

    /// [T-ios-slot-fresh-measure-latch] 重测量补发冷却门闩（09-19 审查修正）。
    /// config 替换会重置 @State 并重跑 onAppear（本文件 [pp 09-18 根因②] 自述），
    /// 若 onAppear 无条件补发即形成"通知 → reconfigure → 新子树 onAppear → 再通知"
    /// 的**无界回环**（hosting-graph 重入 = 仓内登记崩溃面）。@State 不能当门闩
    /// （它正是被重建重置的东西），故用视图外 static 记录各 anchor 上次补发时刻：
    /// 每次重测量链最多一发，回环单次收敛。
    private static var lastRemountPing: [UUID: TimeInterval] = [:]
    /// [T-ios-slot-loop-breaker] 修复重配抑制窗（09-19 #162 循环实证修复）。
    /// 列表侧 `.thinkingBlockToggled` 修复会 reconfigure 本格 → 重建 → 新子树
    /// onAppear → 若再补发 ping 即形成 [ping→reconfigure→onAppear→ping] 的
    /// **自动循环**（pp 11:19–11:34 全量日志实证：约 1.3s/圈、后台悬挂也持续、
    /// 每圈闪现一次 24pt 塌陷相位；原门闩只限速未截断）。修复侧调用
    /// noteProgrammaticReconfigure 登记抑制窗，窗内 onAppear 补发直接跳过 →
    /// 循环终止；用户真实重进在窗外观测，照常补发。
    private static var repairSuppressUntil: [UUID: TimeInterval] = [:]
    static func noteProgrammaticReconfigure(_ anchorId: UUID) {
        repairSuppressUntil[anchorId] = ProcessInfo.processInfo.systemUptime + 2.5
    }
    private static func allowRemountPing(_ anchorId: UUID) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        // [T-ios-slot-loop-breaker] 修复重配抑制窗（见 noteProgrammaticReconfigure）。
        if let until = repairSuppressUntil[anchorId], now < until { return false }
        if let last = lastRemountPing[anchorId], now - last < 1.0 { return false }
        lastRemountPing[anchorId] = now
        return true
    }

    /// [T-ios-slot-fresh-measure-2] 最近一次成功渲染过的事件行（按 anchor 缓存引用）。
    /// 重挂载/重建的首帧竞态兜底：首次 config 时 segment/message 数据可能尚未就绪，
    /// 首帧只渲染标题行 ≈24pt 被自测量写进布局缓存，下一帧数据到达又长回 ≈91/125pt
    /// → 帧级闪烁（pp 09-19 完整日志 [SlotMeasure] 实证：commit 40→24.0 后 ~25ms
    /// 才被自愈链修回 91.3，共 14 次）。缓存引用保持实时状态，仅作兜底；
    /// 实时数据非空时不使用缓存。/ 上限 64 个 anchor，FIFO 裁剪。
    private static var lastRowsCache: [UUID: [AssistantBlock]] = [:]
    private static var lastRowsCacheOrder: [UUID] = []
    private static func rememberRows(_ rows: [AssistantBlock], anchor: UUID) {
        guard !rows.isEmpty else { return }
        lastRowsCache[anchor] = rows
        lastRowsCacheOrder.removeAll { $0 == anchor }
        lastRowsCacheOrder.append(anchor)
        if lastRowsCacheOrder.count > 64, let oldest = lastRowsCacheOrder.first {
            lastRowsCacheOrder.removeFirst()
            lastRowsCache.removeValue(forKey: oldest)
        }
    }

    /// [pp 09-18 Grok 轮播 1:1] 队列弹簧：0.42s 无回弹。Grok 逐帧实测（60fps）：
    /// 位移 t=0.2→41%、0.4→83%、0.6→99%，峰值速度 t≈20%，无过冲 → smooth(bounce=0)。
    static let carouselSpring: Animation = .smooth(duration: 0.42)

    /// Event window: chat shows the last three event lines [A4, pp 定 2026-09-17：最多排三个].
    private var eventBlocks: [AssistantBlock] {
        segment.toolIds.suffix(3).compactMap { id in
            message.blocks.first { $0.id == id }
        }
    }

    /// [T-ios-slot-fresh-measure-2] 行渲染统一数据源：实时优先、缓存兜底。
    private var displayRows: [AssistantBlock] {
        let live = eventBlocks
        return live.isEmpty ? (Self.lastRowsCache[segment.anchorId] ?? []) : live
    }

    /// [T-ios-slot-height-floor] 运行槽"高度地板"（09-19 #162 循环实证修复）。
    /// 只要该段"已知有行"（实时或缓存），运行槽的渲染身高不得低于
    /// 标题(24pt)+行数×行距(33.7pt)。治"重建过渡帧被自测量成 24pt → 提交错高
    /// → 与随后渲染出的行内容错位（气泡撞行/内容溢出）"——地板挂在 displayRows
    /// （含缓存）而非 carouselIds（@State，恰是重建时会被重置/晚到的那个），
    /// 因此不依赖任何首帧时序：冷启动/重配/重建的任意一帧都量不到 <地板 的值。
    /// 运行中 toolIds 单调增长（suffix(3) 窗口只换不缩）→ 地板单调不误伤收缩；
    /// 完成态走 entryRow 分支不设地板；无行段（新段起步）照旧 24pt 合法。
    private var slotFloor: CGFloat {
        let n = min(displayRows.count, 3)
        guard n > 0 else { return 0 }
        return 24 + 33.7 * CGFloat(n)
    }

    /// 是否按运行槽渲染。[T-ios-coldstart-interrupted-slot] 追加一条：load 检测的
    /// "中断待恢复"回合里未被正文收口的段 = 信息上未完成 → 保持运行槽（计时冻结）。
    /// closedByContent 段不在列——标志是消息级，同消息内已收口的历史阶段不得复活。
    private var running: Bool {
        !segment.isDone || (interruptedPendingResume && !segment.closedByContent)
    }
    /// 该段是否"已经在干活"——「Thinking」文字与计时出现/起算的判定 [pp 09-18 二改]。
    /// 上游 09-18 版只看 thinking 块有没有内容；但 **thinking 块只在收到 `.thinkingDelta`
    /// 时创建**（SSEStream.swift 该分支），那是 Anthropic 系专有——接 OpenAI/Gemini 等
    /// 不出思考流的模型时该条件恒为假：点阵在转、工具行在长，「Thinking」与秒数却永不
    /// 出现（pp 装机：「明明都在做任务了、都在调用工具，有时候 thinking 都不出现」）。
    /// 故补上"工具已在跑"这一路：工具调用一出现就证明模型在干活。
    /// 计时起点 = 本条件首次成立的时刻（等待模型响应那段仍不计入 [09-18 决定]）。
    /// [pp 09-18 根因①判定双读] 流式增量只写 thinkingContentBuffer（非 @Published），
    /// @Published content 要等节流 flush（0.3~1.5s 自适应）才落地——双读消除该滞后。
    private var workHasStarted: Bool {
        if !segment.toolIds.isEmpty { return true } // 已在调工具 = 在干活（无 thinking 块的模型走这里）
        return segment.thinkingIds.contains { id in
            guard let b = message.blocks.first(where: { $0.id == id }) else { return false }
            return !b.content.isEmpty || !b.thinkingContentBuffer.isEmpty
        }
    }
    /// 思考要点句 [pp 09-18 Claude 对照实锤：消息流入口行句子 = Summary 弹窗最后一条
    /// 思考叙述句（同源同数据）；Claude 的句子由其「摘要思考」层生成，moonveil 无此层，
    /// 以启发式对齐——取该段思考最后一个有意义句（≥8 字，跳过「好的。」类应答短句）。
    /// 仍取不到 → 该段最后一条 toolSummary（聚合页重点内容）→「思考结果」（entryRow 侧兜底）。
    private var thinkingHeadline: String? {
        let merged = segment.thinkingIds
            .compactMap { id in message.blocks.first { $0.id == id } }
            .map(\.content)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
        let sentences = merged
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = sentences.reversed().first(where: { $0.count >= 8 }) else { return nil }
        return last.count > 80 ? String(last.prefix(80)) + "…" : last
    }

    /// 兜底摘要：该段最后一条工具的 LLM 语义摘要 [pp 09-18：取不到思考句时取聚合页重点]。
    private var lastToolSummary: String? {
        for id in segment.toolIds.reversed() {
            if let b = message.blocks.first(where: { $0.id == id }),
               let s = b.toolSummary, !s.isEmpty {
                return s
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if running {
                runningSlot
                    .transition(.opacity)
            } else {
                entryRow
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: segment.isDone) // A1 ③ 交叉淡变 ~0.25s
        .onAppear {
            ensureStarted()
            // [T-ios-coldstart-interrupted-slot] 中断待恢复 → 计时冻结：复用既有
            // ThinkingRunClock.pause（「错误冻结」先例同机制），续走在下方 onChange。
            // 置于 ensureStarted 之后：startedAt 已定，冻结基准 = 首帧时刻。
            if interruptedPendingResume { ThinkingRunClock.pause(anchorId: segment.anchorId) }
            withAnimation(.easeOut(duration: 0.34)) { dotsAppeared = true } // [pp 09-18] 点阵出现动画
            // [pp 09-18 根因②] cell 重建（滚动回收/高度刷新/config 替换）会重置
            // @State，而 onChange 只监听「变化」（true→true 不触发）——onAppear 必须
            // 补查当前值，否则已开始的思考永远只剩点阵（textAppeared 恒 false）。
            // [pp 09-18 触感修复] 补查路径 haptic: false —— 这里只是恢复状态，
            // 不是"思考刚开始"，发触感会让点进页面/滚动回看都震一下。
            markThinkingStartedIfNeeded(haptic: false)
            // [pp 09-18 根因③] 首渲染历史行直接落位（无动画事务 → 无插入动画）；
            // 后续增删走 onChange 显式事务。
            // [T-ios-slot-fresh-measure-2] 缓存实时行 + 统一数据源（缓存兜底）。
            Self.rememberRows(eventBlocks, anchor: segment.anchorId)
            carouselIds = displayRows.map(\.id)
            // [T-ios-slot-fresh-measure] 重进/重建自愈（保险丝）：播种后对运行中的段
            // 补发一次既有重测通道（.thinkingBlockToggled → 列表侧清双层缓存 +
            // 单格 reconfigure 重测），不再"等下一个工具事件"。仅运行中的段补发，
            // 历史格（done）与滚动回看不打扰布局。
            // [T-ios-slot-fresh-measure-latch] 补发前过冷却门闩（见 allowRemountPing）：
            // 防"通知 → reconfigure → 新子树 onAppear → 再通知"的无界回环；本链每
            // 收敛为单次重测。
            // [T-ios-coldstart-interrupted-slot] 补发条件从 !isDone 放宽为 `running`：
            // 中断待恢复段也按运行槽渲染、同样需要首测自愈；冷却门闩（每 anchor
            // ≥1s 一发）原样保留，回环仍单次收敛。
            if running, Self.allowRemountPing(segment.anchorId) {
                let anchorId = segment.anchorId
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .thinkingBlockToggled, object: anchorId)
                }
            }
        }
        .onChange(of: workHasStarted) { _ in
            // [pp 09-18] 首个思考内容到达那一刻起表 + 「Thinking」/计时出现动画
            // + 触屏反馈（与发送消息同款轻档；Claude app 无公开逆向，装机对比可调）。
            // [pp 09-18 触感修复] 真事件路径 → haptic: true。
            markThinkingStartedIfNeeded(haptic: true)
        }
        .onChange(of: eventBlocks.map(\.id)) { _ in
            // [pp 09-18 根因③] 工具事件增删 → withAnimation 显式事务驱动 ForEach
            // 结构变化 + 存量行布局位移。cell 宿主挂 `.transaction { disablesAnimations
            // = true }`（CollectionViewMessageListV3 防 ViewGraph use-after-free 护栏，
            // 4 处）会吞掉一切隐式动画（.animation(_:value:)/.transition 默认事务，
            // 仓内 ToolSheetPresenter 注释为证）——显式事务放行（两段式 D 出现动画
            // 同管线，装机实证可用）。
            // [T-ios-slot-fresh-measure-2] 统一数据源：实时优先、缓存兜底；实时瞬空时不清行。
            Self.rememberRows(eventBlocks, anchor: segment.anchorId)
            let targetIds = displayRows.map(\.id)
            guard targetIds != carouselIds else { return }
            withAnimation(Self.carouselSpring) {
                carouselIds = targetIds
            }
        }
        // [pp 09-18 根因①] thinking block flush 传导：flush 只发
        // AssistantBlock.objectWillChange，本视图只订阅 message（blocks 数组是引用，
        // 引用不变 → message 不发通知）→ workHasStarted 没有重估时机 → 文字
        // 永不出现。watcher 显式订阅段内首个 thinking block（flush 时发，0.3~1.5s）。
        .overlay {
            ThinkingFlushWatcher(
                block: message.blocks.first(where: { $0.id == segment.thinkingIds.first }),
                onFlush: { markThinkingStartedIfNeeded(haptic: true) } // 真事件路径（思考内容落地）
            )
        }
        // [C2] Any segment change (event rows inserted / state flipped) can
        // change the cell height — reuse the existing thinking-toggle
        // invalidation channel (object = anchor block id).
        .onChange(of: segment) { _ in
            NotificationCenter.default.post(name: .thinkingBlockToggled, object: segment.anchorId)
        }
        // [pp 09-18] 错误冻结 / 重试续走：失败等待不计入思考秒数。
        .onChange(of: message.error) { err in
            if err != nil {
                ThinkingRunClock.pause(anchorId: segment.anchorId)
            } else {
                ThinkingRunClock.resume(anchorId: segment.anchorId)
            }
        }
        // [T-ios-coldstart-interrupted-slot] 中断标记双向变更的处理：
        // → true：补冻结（覆盖"视图已挂载、bridge 晚到才置真"的时序——首帧
        //   置真走 onAppear 那条，两者对 pause 幂等无冲突）；
        // → false（点「继续」/新回合清除）：计时续走。error 非空时不动表，
        //   让位给既有错误冻结链，避免两机制互相解锁。
        .onChange(of: interruptedPendingResume) { pending in
            if pending {
                ThinkingRunClock.pause(anchorId: segment.anchorId)
                // 兜底（装机日志证明正常时序是"检测早于首帧"，此路罕见）：标记
                // 晚于挂载到达时，格高是按入口行量出来的 → 走既有重测链纠高，
                // 复用冷却门闩防回环。
                if Self.allowRemountPing(segment.anchorId) {
                    let anchorId = segment.anchorId
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .thinkingBlockToggled, object: anchorId)
                    }
                }
            } else if message.error == nil {
                ThinkingRunClock.resume(anchorId: segment.anchorId)
            }
        }
        // [pp 09-18] 阶段完成 → 落定时长（供汇聚页「Thought for Ns」）。
        .onChange(of: segment.isDone) { done in
            if done {
                ThinkingRunClock.settle(anchorId: segment.anchorId, start: startedAt)
            }
        }
    }

    // MARK: Running slot

    private var runningSlot: some View {
        // [pp 09-17] 运行中的槽整体可点 → 汇聚页（实时进度），与完成态入口行
        // 同一 onOpenDetail 通道；stop 是嵌套内层 Button，点击优先级高于外层。
        Button {
            onOpenDetail?(segment)
        } label: {
            // [pp 09-18 Grok 对照 photo_CCA700E4] 行距对齐：Thinking→首事件 34.7pt /
            // 事件行间 36pt（Grok 实测）→ VStack 4→18（现值实测 19.7/22pt 偏紧）。
            VStack(alignment: .leading, spacing: CGFloat(toolRowSpacing)) {
                // [pp 09-18 真机] 点阵与 Thinking 间距对齐入口行 clock→摘要（spacing 10），
                // 原 6 视觉仅 ~8.7pt 偏近。
                HStack(spacing: 10) {
                    ThinkingDotIcon(size: 18)
                        .opacity(dotsAppeared ? 1 : 0) // [pp 09-18] 两段式 D 出现动画
                        .offset(x: dotsAppeared ? 0 : -10)
                    // [pp 09-18 真机] 模型实际开始思考（首个思考内容到达）才出现
                    // 「Thinking」与计时；等待响应阶段只有点阵动画（启动槽同）。
                    Group {
                        // [v12 09-19] 扫光改 FB 机制 ShimmerLabel（UILabel 自持颜色 +
                        // 白亮带文字 alpha 掩膜，见 ShimmerText.swift）。字体/颜色沿用
                        // pp 09-18 两轮点名：14pt regular + 与 entryRow 同色 headlineGray。
                        ShimmerLabel(text: "Thinking", // [pp 09-17] 固定英文（非本地化）
                                     uiFont: .systemFont(ofSize: 14),
                                     baseColor: ThinkingRowStyle.headlineGray)
                            .fixedSize()
                        elapsedCounter
                    }
                    .opacity(textAppeared ? 1 : 0)
                    .offset(x: textAppeared ? 0 : -10)
                    .accessibilityHidden(!textAppeared)
                    Spacer(minLength: 0)
                    if showsStop {
                        Button(action: { onStop?() }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalized("Stop"))
                    }
                }
                ForEach(carouselIds, id: \.self) { id in
                    // [pp 09-18 根因③] 数据源 = carouselIds（@State，onChange 显式
                    // 事务更新）；block 从 eventBlocks 现查——离场行 id 已出 suffix(3)
                    // 窗口 → if let 失败 → 视图移除 → removal transition（跟队上滑）。
                    if let block = displayRows.first(where: { $0.id == id }),
                       let item = ToolEventRowFactory.item(for: block) {
                        ToolEventRow(
                            item: item,
                            accentColor: ToolActivityIcon.accentColor(for: block.kind),
                            status: block.toolStatus
                        )
                        // [pp 09-18 Grok 对照] 事件行图标列与点阵同列（Grok 三行图标
                        // 中心同 x≈27pt）——删 21pt 缩进；列对齐由 ToolEventRow 内部
                        // 18pt 图标 frame + spacing 10 保证。
                        .transition(.toolRowCarousel) // [pp 09-18 Grok 轮播 1:1] 进场=+pitch 滑入淡入由糊变锐 / 离场=-pitch 跟队上滑淡出（取代旧 opacity 淡入）
                    }
                }
            }
            .padding(.vertical, 3)
            // [T-ios-slot-height-floor] 高度地板：已知有行时任何测量不得低于
            // 标题+行数×行距（见 slotFloor 注释）。
            .frame(minHeight: slotFloor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLocalized("Thinking"))
    }

    /// [A3] 计时文字（与启动槽共用同一组件，0.7s 规则 + 1Hz）。
    private var elapsedCounter: some View {
        ThinkingElapsedText(start: startedAt, anchorId: segment.anchorId)
    }

    /// Shell stop affordance only while a shell tool is in flight
    /// (mirrors classic ToolCapsuleView's stop visibility).
    private var showsStop: Bool {
        guard let onStop else { return false }
        return message.blocks.contains { block in
            guard segment.toolIds.contains(block.id) else { return false }
            guard case .shellTool = block.kind else { return false }
            if case .streaming = block.toolStatus { return true }
            if case .running = block.toolStatus { return true }
            return false
        }
    }

    // MARK: Entry row (永留)

    private var entryRow: some View {
        Button {
            onOpenDetail?(segment)
        } label: {
            HStack(spacing: 12) {
                // [pp 09-18 1:1 复刻 Claude photo_25B6FFE9 实测] ⏱16pt + 摘要 14pt regular
                // #7A7974 + chevron 紧跟文字后 21pt（未满行随文字收尾，非贴右缘）。
                ClaudeClockIcon(size: 16, color: ThinkingRowStyle.headlineGray) // [pp 09-18 二次校准] 缺口环+等大三点自绘时钟（photo_8E721157 拟合参数）
                Text(thinkingHeadline ?? lastToolSummary ?? AppLocalized("Thinking result")) // [pp 09-18] 思考要点句 → 聚合页重点（toolSummary）→ 思考结果
                    .font(.system(size: 14)) // [pp 09-18] 14pt regular（Claude 同档，轻质感；1:1 实测）
                    .foregroundStyle(ThinkingRowStyle.headlineGray)
                    .lineLimit(1)
                AppSymbol("chevron.right", size: 20) // [pp 09-17] Lucide 官方 chevron-right（视觉 ~6×11pt = Claude 同尺寸）
                    .foregroundStyle(ThinkingRowStyle.headlineGray)
                    .padding(.leading, 9) // 文字→chevron 总距 21pt [Claude 实测]
            }
            .frame(maxWidth: .infinity, alignment: .leading) // 热区全宽（Spacer 推挤改随文布局）
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppLocalized("Thinking"))
    }

    // MARK: 出现动画状态 [pp 09-18] 点阵/文字两段式 D 动画（左滑入+淡入 0.34s）
    @State private var dotsAppeared = false
    @State private var textAppeared = false

    /// [pp 09-18 根因③] 轮播显式驱动队列（id 列表）。由 onChange(of: eventBlocks ids)
    /// 在 withAnimation(Self.carouselSpring) 事务里更新——cell 的 disablesAnimations
    /// 只吞隐式动画，显式事务放行（两段式 D 同管线装机实证）。
    @State private var carouselIds: [UUID] = []

    // MARK: Helpers

    /// [pp 09-18] 思考开始的统一置位入口（幂等，三路汇合）：
    /// ① onChange(of: workHasStarted)——segment/message 变化路径；
    /// ② ThinkingFlushWatcher——thinking block flush 路径（content 落地即重估）；
    /// ③ onAppear——cell 重建后补查路径（@State 重置，onChange 不触发 true→true）。
    ///
    /// [pp 09-18 装机反馈「点进聊天页就有触屏反馈」→ 修复] 触感只走**事件**路径：
    /// ③ onAppear 是"补记已经发生的事实"（历史消息 cell 重建 / 进页面重现），
    /// 不是思考刚开始——它跟着发触感会把每个已完成回合都震一遍，用户感知即
    /// "点进聊天页就震"。状态置位三路照旧（断的是 @State，不是事实），
    /// 触感收进 `haptic`，只有 ①② 传 true。
    private func markThinkingStartedIfNeeded(haptic: Bool) {
        guard !textAppeared, workHasStarted else { return }
        withAnimation(.easeOut(duration: 0.34)) { textAppeared = true }
        if haptic { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        ensureStarted()
    }

    private func ensureStarted() {
        // [pp 09-18] 计时起点 = 思考实际开始（首个思考内容到达），不再从发送
        // 时刻接力（启动槽已不再 seed）——等待响应不计入思考时长。
        guard workHasStarted else { return }
        if startedAt == nil {
            if let cached = Self.startCache[segment.anchorId] {
                startedAt = cached
            } else {
                let start = Date.now
                Self.startCache[segment.anchorId] = start
                startedAt = start
            }
        }
    }
}

// MARK: - Thinking flush watcher [pp 09-18 根因①]

/// 订阅段内首个 thinking block 的 objectWillChange（= 节流 flush 落地时刻）。
/// 数据流：SSE delta → thinkingContentBuffer（非 @Published，零通知）→ 节流 flush
/// → @Published content（发 AssistantBlock.objectWillChange）。本视图只订阅
/// message，而 blocks 数组持有的是引用、引用不变 → message 永不发通知 → 没有
/// watcher 时 workHasStarted 在纯思考阶段没有任何重估时机（「明明在写但只有
/// 点阵」的根因）。block 实例稳定 → publisher 实例稳定 → onReceive 不重复订阅；
/// flush 频率 0.3~1.5s，成本可忽略。零尺寸不参与布局。
/// [pp 09-18] 由 ToolActivityGroupView 与 ThinkingDetailOverlay（汇聚页思考详情）
/// 共用 → 去掉 private（汇聚页同样只订阅 message，需要它才能拿到 flush）。
struct ThinkingFlushWatcher: View {
    let block: AssistantBlock?
    let onFlush: () -> Void

    var body: some View {
        if let block {
            Color.clear
                .frame(width: 0, height: 0)
                .onReceive(block.objectWillChange) { _ in
                    onFlush()
                }
        }
    }
}

// MARK: - Aggregation adapter + notifications [C1]

extension Notification.Name {
    /// New-skin entry row → 汇聚页 request. userInfo: ["segment":
    /// TurnActivitySegment, "messageId": UUID]. Received by AIChatView
    /// (single host for both local and remote sessions) [H5].
    static let toolActivityDetailRequested = Notification.Name("toolActivityDetailRequested")
}

extension TurnActivityAggregator {
    /// AssistantBlock stream → normalized aggregation input.
    /// isActiveThinking mirrors ThinkingBlockView's streaming flag
    /// (isActiveMessage && message.blocks.last?.id == block.id).
    static func adapt(_ blocks: [AssistantBlock], isActiveMessage: Bool) -> [TurnActivityBlock] {
        let lastId = blocks.last?.id
        return blocks.map { b in
            let kind: TurnActivityBlockKind
            switch b.kind {
            case .text: kind = .text
            case .thinking: kind = .thinking
            case .info: kind = .info
            case .shellTool, .fileReadTool, .fileWriteTool, .fileEditTool,
                 .browserTool, .readImageTool, .memoryTool:
                kind = .tool
            }
            var state: TurnActivityToolState?
            if kind == .tool {
                switch b.toolStatus {
                case .streaming, .running: state = .active
                case .success: state = .finished
                case .failed, .cancelled: state = .failed
                case .none: state = .unknown
                }
            }
            return TurnActivityBlock(
                id: b.id,
                kind: kind,
                toolState: state,
                isActiveThinking: kind == .thinking && b.id == lastId && isActiveMessage
            )
        }
    }
}

// MARK: - Grok 工具行轮播转场 [pp 09-18 逐帧拆解 video_CDFAF826.mov 1:1]
//
// 实测（60fps 3x）：行距 pitch=108px=36pt；全程 ~25 帧=0.42s 前载 ease-in-out
// 无过冲；进场行从下方一个行距处上滑，opacity 0→1 ≈0.25s、blur ~2.7pt→0
// ≈0.35s（清晰化比淡入晚收尾）；离场行跟队上滑一个行距同时淡出+变糊，到
// 头部区前已近透明。单条 spring 统一驱动 = 确定性逐帧一致。

/// 轮播三态：进场激活（藏在目标位下一个行距）/ 离场激活（跟队上滑一个行距）/
/// 落定（正常渲染）。internal：被 AnyTransition 扩展跨类型引用（禁 private）。
struct ToolRowCarouselTransition: ViewModifier {
    enum Phase { case enteringActive, exitingActive, settled }
    let phase: Phase

    /// 行距 = 行高(~20pt) + VStack spacing（Tool Row Spacing 设置可调，默认 18pt）≈ 38pt（Grok 实测 36pt）。
    private static let pitch: CGFloat = 38
    /// 实测 blur ~8px@3x≈2.7pt σ；SwiftUI radius 取 4 观感对齐（装机可调）。
    private static let blurRadius: CGFloat = 4

    func body(content: Content) -> some View {
        let y: CGFloat = phase == .enteringActive ? Self.pitch
            : phase == .exitingActive ? -Self.pitch : 0
        return content
            .opacity(phase == .settled ? 1 : 0)
            .blur(radius: phase == .settled ? 0 : Self.blurRadius)
            .offset(y: y)
    }
}

extension AnyTransition {
    /// Grok 工具行轮播：insertion 从下滑入、removal 向上跟队滑出；位移/淡变/
    /// 模糊全部由容器 `.animation(Self.carouselSpring, value: ids)` 同轨驱动。
    static var toolRowCarousel: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ToolRowCarouselTransition(phase: .enteringActive),
                identity: ToolRowCarouselTransition(phase: .settled)),
            removal: .modifier(
                active: ToolRowCarouselTransition(phase: .exitingActive),
                identity: ToolRowCarouselTransition(phase: .settled)))
    }
}

// MARK: - 新皮肤启动槽 + 计时衔接 [pp 09-17 装机反馈]

/// 计时衔接：发送 → 首个块 期间由 PendingThinkingIndicator 起表；消息内组视图
/// 接管同一段计时（消费起点），保证计数连续不重数、不跳回。
enum ThinkingRunClock {

    // [pp 09-18] 三态计时：运行 → 冻结（错误/完成）→ 续走（重试不跳回）。
    // 冻结/续走按 segment 锚点（anchorId 全局唯一）；错误等待不计入时长。
    private static var pauseAt: [UUID: Date] = [:]              // 暂停时刻（冻结显示基准）
    private static var pausedOffset: [UUID: TimeInterval] = [:] // 累计暂停时长（resume 平移）
    private static var frozen: [UUID: TimeInterval] = [:]       // 终值（完成/错误冻结后查询）

    /// 显示时长：终值优先；暂停中冻结在暂停时刻；否则实时。
    static func elapsed(anchorId: UUID, start: Date, now: Date) -> TimeInterval {
        if let f = frozen[anchorId] { return f }
        let effectiveNow = pauseAt[anchorId] ?? now
        return max(0, effectiveNow.timeIntervalSince(start) - (pausedOffset[anchorId] ?? 0))
    }

    /// 错误出现 → 冻结（仅从运行态进入一次）；重试前秒数停住不涨。
    static func pause(anchorId: UUID, now: Date = .now) {
        guard frozen[anchorId] == nil, pauseAt[anchorId] == nil else { return }
        pauseAt[anchorId] = now
    }

    /// 错误清除/重试 → 续走（暂停时长折入 offset，数字连续不跳回）。
    static func resume(anchorId: UUID, now: Date = .now) {
        guard frozen[anchorId] == nil, let pa = pauseAt[anchorId] else { return }
        pausedOffset[anchorId, default: 0] += now.timeIntervalSince(pa)
        pauseAt[anchorId] = nil
    }

    /// 阶段完成 → 落定终值（供汇聚页「Thought for Ns」）。
    static func settle(anchorId: UUID, start: Date?, now: Date = .now) {
        guard frozen[anchorId] == nil, let start else { return }
        frozen[anchorId] = elapsed(anchorId: anchorId, start: start, now: now)
        pauseAt[anchorId] = nil
    }

    /// 汇聚页查询：完成态时长（nil = 无数据，旧消息/未落定）。
    static func frozenValue(anchorId: UUID) -> TimeInterval? {
        frozen[anchorId]
    }
}

/// [A3 共用] 计时文字：前 ~0.7s 不显示，随后 "· Ns" 1Hz。
struct ThinkingElapsedText: View {
    let start: Date?
    /// [pp 09-18] 三态计时锚点（错误冻结 / 重试续走 / 完成落定）。
    var anchorId: UUID? = nil

    var body: some View {
        if let start {
            TimelineView(.periodic(from: start, by: 1)) { timeline in
                let elapsed: TimeInterval = anchorId
                    .map { ThinkingRunClock.elapsed(anchorId: $0, start: start, now: timeline.date) }
                    ?? timeline.date.timeIntervalSince(start)
                if elapsed >= 0.7 {
                    Text("• \(max(1, Int(ceil(elapsed - 0.7))))秒") // [帧01] Grok 格式
                        // [pp 09-18 字体/颜色对齐] 与同一行的 "Thinking" 及完成态入口行
                        // 同档：14pt regular + headlineGray（原先 medium + secondary
                        // 会让 "Thinking • 2秒" 半粗半细、半冷半暖）。
                        .font(.system(size: 14))
                        .foregroundStyle(ThinkingRowStyle.headlineGray)
                }
            }
        }
    }
}

/// [pp 09-17→09-18 改版] 新皮肤启动槽：发送后、模型响应前显示 —— 只有点阵
/// 动画 [pp 09-18：「Thinking」文字与计时在思考实际开始（运行槽侧）才出现，
/// 计时不再从发送起虚走]。只在 blocks 为空时被调用（否则组视图已承担指示）。
struct PendingThinkingIndicator: View {
    let messageId: UUID
    @State private var appeared = false // [pp 09-18] D 出现动画（与运行槽同款）

    var body: some View {
        HStack(spacing: 6) {
            ThinkingDotIcon(size: 18)
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : -10)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.34)) { appeared = true }
        }
    }
}


// MARK: - Claude Clock Icon (入口行) [pp 09-18 参数替换：photo_8E721157 拟合版]
//
// 形状来源：photo_8E721157.png 像素级拟合（参数坐标下降优化，软 IoU 0.951，
// 存档 shared/claude-clock-svg/fitted2.json）。24 画布归一（外缘=12，撑满）：
// 环中径 10.6438 / 线宽 2.7123；缺口弧 264.7046°→527.6624°（顺时针跨 0°，圆头）；
// 三点等大 @ 190.356°/215.060°/239.836°（R 10.2809）；指针折线
// [光学代偿] 点径 φ3.67u（素材 2.93u/12.2% → 15.3% 上限）：16pt 真机下素材比例
// 仅 5.9px 与线同粗不可辨，放大后可辨（SVG 大图与真机小图的观感差异来源）。
// (11.2483,6.9451)→(11.4659,12.4278)→(16.0784,14.3009)。颜色/尺寸与文字同灰。
// 覆盖 photo_25B6FFE9 初版参数（递进三点/66°缺口/线宽2.0）——以新版拟合为准 [pp 09-18 拍板]。

struct ClaudeClockIcon: View {
    var size: CGFloat = 16
    var color: Color

    var body: some View {
        Canvas { ctx, sz in
            let u = sz.width / 24 // 设计画布 24
            let c = CGPoint(x: 12 * u, y: 12 * u)
            let lw = 2.7123 * u

            // 缺口圆环：264.7046°→527.6624°（=167.6624°+360）顺时针，缺口左上 [拟合]
            // [CC 09-18 修复] SwiftUI 的 clockwise 与直觉相反：false = 角度递增路线。
            // 原 true 让 264.7°→527.66° 走递减（264.7°→167.66°），只画出 97° 的缺口弧，
            // 主弧（顶→右→底→左下）整段丢失 —— pp 装机截图实测缺口段被画成主弧即此因。
            // 旁证：FolderSegmentBorder（同文件族，圆角矩形装机正确）用 false 画 180°→270° 的 90° 角。
            var arc = Path()
            arc.addArc(center: c, radius: 10.6438 * u,
                       startAngle: .degrees(264.7046), endAngle: .degrees(527.6624),
                       clockwise: false)
            ctx.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round))

            // 缺口区三点：等大 φ2.9256 @ 190.356/215.060/239.836° [拟合]
            let dots: [Double] = [190.356, 215.060, 239.836]
            for deg in dots {
                let rad = deg * Double.pi / 180
                let px = c.x + CGFloat(cos(rad)) * 10.2809 * u
                let py = c.y + CGFloat(sin(rad)) * 10.2809 * u
                let d = CGFloat(3.67) * u // [pp 09-18 光学代偿] 素材比例 12.2% 在 16pt 仅 5.9px 不可辨；放大至不粘连上限 15.3%
                ctx.fill(Path(ellipseIn: CGRect(x: px - d / 2, y: py - d / 2, width: d, height: d)),
                         with: .color(color))
            }

            // 指针：竖针+右下臂折线 [拟合]（与环同宽，拟合差 0.6% 噪声内）
            var hands = Path()
            hands.move(to: CGPoint(x: 11.2483 * u, y: 6.9451 * u))
            hands.addLine(to: CGPoint(x: 11.4659 * u, y: 12.4278 * u))
            hands.addLine(to: CGPoint(x: 16.0784 * u, y: 14.3009 * u))
            ctx.stroke(hands, with: .color(color),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

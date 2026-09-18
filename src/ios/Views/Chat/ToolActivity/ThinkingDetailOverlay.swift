import SwiftUI

// MARK: - Thinking Detail Sheet (汇聚页, Summary 时间线列表版)
//
// 2026-09-17 pp 两连改判：① 弹窗用【原生 sheet】——grabber/圆角/dimming/拖拽
//   吸附/下拉关闭全交系统，弃用自绘 overlay 壳。② 排版标题居中。
// 2026-09-18 pp 第三轮改判（Grok photo_353E81A2 / photo_2F211FE1 逐像素实测 +
// Claude 纯思考弹窗截图）：sheet 底 #F5F5F5；timeline 短竖线段；计时三态。
// 2026-09-18 pp 第四轮改判（Claude Summary 弹窗 photo_7D322C95 / photo_225E7A7A /
// photo_805DB84A + 指令「汇聚页改成这种…调用了工具有输出就再设一个入口，点击就切页」）：
//   - 有工具的段 = 【Summary 时间线列表】：思考圆点句 + 工具图标行按消息时间序
//     交错，行间短竖线连接，可点行右侧 chevron ›（Claude 图三每行都有）
//   - 思考项 / 有输出的工具项点击 = NavigationStack push 切页：
//     思考 → 原文衬线页；工具 → Input/Output 详情页
//   - 工具详情页 Input = toolInputArgs pretty JSON（无则 factory 输入摘要），
//     Output = block.content；代码卡复用 SelectableMarkdownView fenced block
//     （语言标签 + 语法高亮 + 23pt 圆角卡 = Claude photo_805DB84A 同构，免费）
//   - 运行中当前项 = 灰字（photo_225E7A7A：已完成黑句 + 运行中灰 "Thinking…"）
//   - 无输出的完成工具 = 无 chevron 不可点（pp：「有输出就再设一个入口」）
//   - 纯思考段保持原文衬线直展（photo_6422F7B6 对照，已拍板）
//   - 详情页顶栏 = 白圆底返回钮 + 左对齐大标题（photo_805DB84A）；系统
//     navigationBar 无此形态（inline 居中 17pt / large 34pt 左对齐均不符），
//     故自绘头部；push/pop 转场仍走系统 NavigationStack（原生转场免费）
// ToolCardView 描边卡随本改退役（唯一引用点被列表式替代，struct 已删；
// CometSpinner 仍被运行态使用，保留在本文件）。
//
// 2026-09-18 pp 第五轮：① 暗色适配（原先三份写死的 #F5F5F5 等浅色，暗色下
// 整张 sheet 仍是近白、而正文走语义色变白 → 白底白字）；② 思考详情页渲染
// （4 处 AttributedString(markdown:) → 纯 Text）；③ 思考详情页流式（补 block 订阅）。

// MARK: - 汇聚页配色（三个页面共用一份）
//
// [pp 09-18 暗色适配] 浅色档全部是 Claude Summary 的实测值（逐像素，勿动）；
// 深色档按设计规范的中性暖灰（禁蓝调）。正文/标题一律用 Color.primary /
// Color(uiColor: .label) 这类语义色（浅=黑/深=白），本表只放"语义色没有对应物"
// 的装饰色（页底、圆点、连线、圆钮底）——语义色压在动态页底上才对。
// 原先三个 struct 各写一份 sheetBg（同一值抄三遍），改一处要改三处 → 合并为单一来源。
private enum SummaryPalette {
    /// 页底 #F5F5F5（Claude 实测） / 深色 #181818
    static let sheetBg = dynamic(light: rgb(0.961, 0.961, 0.961), dark: rgb(0.094, 0.094, 0.094))
    /// 列表句 #1D1D1D / 深色 #EDEDED
    static let rowInk = dynamic(light: rgb(0.114, 0.114, 0.114), dark: rgb(0.929, 0.929, 0.929))
    /// 圆点/图标/chevron #888681 / 深色 #A0A0A0
    static let muted = dynamic(light: rgb(0.533, 0.525, 0.506), dark: rgb(0.627, 0.627, 0.627))
    /// 时间线短竖线 #DCDCDC / 深色 #2E2E2E
    static let connector = dynamic(light: rgb(0.863, 0.863, 0.863), dark: rgb(0.180, 0.180, 0.180))
    /// 左上圆钮底（X / 返回）白 / 深色 #2E2E2E（比页底亮一档 = 与浅色下"白比 #F5F5F5 亮"同关系）
    static let circleButton = dynamic(light: rgb(1, 1, 1), dark: rgb(0.180, 0.180, 0.180))

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct ThinkingDetailOverlay: View {
    @ObservedObject var message: ChatMessage
    let segment: TurnActivitySegment
    let isActiveMessage: () -> Bool
    /// [pp 09-19 灰尾修复] 原为 `Bool` 快照且全文件零引用（死参数）。改闭包现读
    /// vm.isProcessing —— segment 是打开瞬间的值快照，消息完成后 `!segment.isDone`
    /// 永远停在 true → 思考尾巴灰渐显冻结（pp 截图：Thought for 30s 已完成仍灰）。
    /// [pp 09-18 三改] 回原生 sheet：关闭走左上 X + 系统下拉关闭 → 回调。
    var onClose: (() -> Void)? = nil

    // [pp 09-18 装机 #117] 嵌套 NavigationStack 打爆外壳 stackNav → 详情页改
    // ZStack 自绘栈：page 非 nil 时从右推入，返回钮推回（转场视觉不变）。
    @State private var page: SummaryRoute?

    /// [pp 09-18 流式修复] 本页只订阅了 message，而思考增量落地在 AssistantBlock
    /// **自己的** @Published content 上：ChatMessage 不转发子对象通知，blocks 数组
    /// 引用不变也不发通知 → 没有这个 tick 时，sheet 打开那一刻的画面就冻住，
    /// 后面思考继续流也一个字不动（pp：「汇聚页里面的 thinking 没有流式输出」）。
    /// tick 只用于强制重算 body，文字仍从块里现读（与聊天流同一套 flush 节奏）。
    @State private var flushTick = 0

    // MARK: Colors
    // [pp 09-18 暗色适配] 原先本页四个写死浅色 → 改用文件顶部的 SummaryPalette
    // （三个页面共用的动态色，单一来源）。

    // MARK: Route / Timeline model

    enum SummaryRoute: Hashable {
        case thinking
        case tool(UUID)
    }

    private enum ItemKind { case thinking, tool }

    private struct TimelineItem: Identifiable {
        let kind: ItemKind
        let block: AssistantBlock
        var id: UUID { block.id }
    }

    /// 段内全部块按消息时间序交错 [Claude Summary：思考句/工具行混排时间线]。
    private var timelineItems: [TimelineItem] {
        let ids = Set(segment.thinkingIds).union(segment.toolIds)
        return message.blocks
            .filter { ids.contains($0.id) }
            .map { TimelineItem(kind: $0.kind == .thinking ? .thinking : .tool, block: $0) }
    }

    private var thinkingBlocks: [AssistantBlock] {
        segment.thinkingIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    private var toolBlocks: [AssistantBlock] {
        segment.toolIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    /// [pp 09-19 灰尾修复] 运行态现读，不再信打开瞬间的 segment.isDone 快照。
    /// 语义与 TurnActivitySegment.isDone（聚合器 67-70 行）逐条对齐：
    ///   ① closedByContent = 段块之后出现 text/info 块（正文已回复）→ done；
    ///   ② 消息终态（!isActiveMessage()）→ done；
    ///   ③ 段内工具仍 active（streaming/running）→ 运行中（正文未到、槽继续转）。
    /// 现读值随 message @Published / flushTick 重估 → 完成瞬间尾巴灰转黑。
    private var isSegmentRunning: Bool {
        if segmentClosedByContent { return false }
        let hasActiveTool = segment.toolIds.contains { id in
            guard let b = message.blocks.first(where: { $0.id == id }) else { return false }
            switch b.toolStatus {
            case .streaming, .running: return true
            default: return false
            }
        }
        if hasActiveTool { return true }
        return isActiveMessage()
    }

    /// 段后是否已出现正文（text/info）——正文才是分段点 [聚合器 8-11 行同一语义]。
    private var segmentClosedByContent: Bool {
        let segIds = Set(segment.thinkingIds).union(segment.toolIds)
        guard let lastIdx = message.blocks.lastIndex(where: { segIds.contains($0.id) }) else { return false }
        return message.blocks.dropFirst(lastIdx + 1).contains {
            $0.kind == .text || $0.kind == .info
        }
    }

    /// 纯思考段 = 无任何工具调用 [pp 09-18 Claude 对照：原文直展]。
    private var isPureThinking: Bool { toolBlocks.isEmpty }

    /// 落定思考时长（秒）；nil = 无数据（旧消息/未落定）。
    private var settledSeconds: Int? {
        guard let t = ThinkingRunClock.frozenValue(anchorId: segment.anchorId) else { return nil }
        return max(1, Int(t.rounded()))
    }

    /// 语义标题：LLM 摘要优先（对齐 classic 胶囊 displayTitle），fallback 类型名。
    private func displayTitle(for block: AssistantBlock, fallback: String) -> String {
        if let s = block.toolSummary, !s.isEmpty { return s }
        return fallback
    }

    /// 思考块要点句（Claude Summary 每步一句；取句规则对齐入口行：末句优先 ≥8 字）。
    private func summaryLine(_ text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
        let sentences = cleaned
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = sentences.reversed().first(where: { $0.count >= 8 }) else { return nil }
        return last.count > 80 ? String(last.prefix(80)) + "…" : last
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                if isPureThinking {
                    // [pp 09-18] 纯思考：原文衬线直展（无列表 / 无 timeline）。
                    ScrollView {
                        thinkingMergedText(size: 15.5, serif: true)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                            .padding(.bottom, 30)
                    }
                } else {
                    summaryList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let page {
                detailPage(page)
                    .transition(.move(edge: .trailing))
                    .zIndex(10)
            }
        }
        .background(SummaryPalette.sheetBg)
        // [pp 09-18 流式修复] 段内每个思考块各挂一个零尺寸 flush 订阅：任一块的
        // @Published content 落地（0.3~1.5s 自适应节流）就 tick 一次 → 整页重算。
        // 零尺寸、不参与布局也不吃点击。
        .overlay {
            ZStack {
                let _ = flushTick // 显式建立依赖：tick 变化 → body 重算
                ForEach(thinkingBlocks) { block in
                    ThinkingFlushWatcher(block: block) { flushTick &+= 1 }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func pushPage(_ p: SummaryRoute) {
        withAnimation(.easeOut(duration: 0.28)) { page = p }
    }

    private func popPage() {
        withAnimation(.easeOut(duration: 0.28)) { page = nil }
    }

    @ViewBuilder
    private func detailPage(_ page: SummaryRoute) -> some View {
        switch page {
        case .thinking:
            ThinkingDetailPage(
                message: message,
                segment: segment,
                isSegmentRunning: isSegmentRunning,
                settledSeconds: settledSeconds,
                onBack: popPage
            )
        case .tool(let blockId):
            ToolSummaryDetailPage(message: message, blockId: blockId, onBack: popPage)
        }
    }

    // MARK: Header（列表页标题，17pt 黑 semibold）

    @ViewBuilder
    private var header: some View {
        // [pp 09-18 三改] 回原生 sheet：头部左上白圆底 X 关闭钮（Claude
        // photo_32363DEB 同构，行心距顶边 ~38pt）；标题保持居中 [32228f2 拍板]。
        ZStack {
            Group {
                if isPureThinking, isSegmentRunning {
                    Text(AppLocalized("Thinking…"))
                } else if isPureThinking, let secs = settledSeconds {
                    Text(verbatim: "Thought for \(secs)s") // [pp 09-18] Claude 式
                } else {
                    Text(AppLocalized("Thinking result")) // 思考结果
                }
            }
            .font(.system(size: 17, weight: .semibold)) // [pp 09-18 Claude Summary 实测：~17.5pt 近黑，与正文同级]
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .sweepShimmer(base: .primary) // [pp 09-18] 呼吸式换 Claude 扫光

            if let onClose {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 44, height: 44) // 热区 [同 Claude 白圆钮]
                            .background(Circle().fill(SummaryPalette.circleButton))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.leading, 16)
            }
        }
        .padding(.top, 16) // [pp 09-18 三改] 行心距顶 ~38pt（参考图实测）
    }

    // MARK: Summary 时间线列表 [Claude photo_7D322C95 实测：
    //        圆点中心 x≈36pt / 文字 x≈64pt / 行距 ~41pt / chevron 灰]

    private var summaryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        connectorRow
                    }
                    timelineRow(item)
                }
            }
            .padding(.leading, 28) // 圆点中心 = 28 + 16/2 = 36pt [实测 x107/3]
            .padding(.trailing, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 项目间连接短线段 [1.33pt #DCDCDC，居中于圆点列；Claude 竖线 ~30pt]。
    private var connectorRow: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(SummaryPalette.connector)
                .frame(width: 1.33, height: 22)
                .frame(width: 16, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(.leading, 0)
        .frame(height: 26)
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineItem) -> some View {
        let isLast = item.block.id == timelineItems.last?.id
        let isCurrent = isSegmentRunning && isLast // 运行中段的最后一块 = 当前活动项 → 灰 [photo_225E7A7A]

        let route: SummaryRoute? = {
            switch item.kind {
            case .thinking:
                return .thinking
            case .tool:
                let inFlight: Bool = {
                    switch item.block.toolStatus {
                    case .streaming, .running: return true
                    default: return false
                    }
                }()
                // [pp 09-18] 有输出（或运行中）才设入口；纯完成无输出不可点。
                if inFlight || !item.block.content.isEmpty { return .tool(item.block.id) }
                return nil
            }
        }()

        Button {
            if let route { pushPage(route) }
        } label: {
            HStack(alignment: .center, spacing: 20) {
                Group {
                    switch item.kind {
                    case .thinking:
                        // [pp 09-18 三改] 运行中当前项 = 同款灰点（Claude
                        // photo_32363DEB 底部 Thinking… 行实测）；文字仍灰。
                        Circle()
                            .fill(SummaryPalette.muted)
                            .frame(width: 7.3, height: 7.3) // [Claude 实测圆点 7.3pt]
                    case .tool:
                        toolIcon(item.block)
                    }
                }
                .frame(width: 16)

                Text(rowText(for: item, isCurrent: isCurrent))
                    .font(.system(size: 16)) // [Claude 列表句实测 ~16pt]
                    .foregroundStyle(isCurrent ? SummaryPalette.muted : SummaryPalette.rowInk)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)

                // [pp 09-18 三改] chevron 仅「有输出/运行中的工具行」（参考图：
                // 思考行无箭头）；思考行保留点开全文（无箭头 affordance）。
                if route != nil, case .tool = item.kind {
                    AppSymbol("chevron.right", size: 16)
                        .foregroundStyle(SummaryPalette.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(route == nil)
    }

    private func rowText(for item: TimelineItem, isCurrent: Bool) -> String {
        switch item.kind {
        case .thinking:
            if isCurrent { return AppLocalized("Thinking…") }
            if let line = summaryLine(item.block.content) { return line }
            if let secs = settledSeconds { return "Thought for \(secs)s" }
            return "Thought"
        case .tool:
            if let row = ToolEventRowFactory.item(for: item.block) {
                return displayTitle(for: item.block, fallback: row.title)
            }
            return item.block.toolDescription
        }
    }

    @ViewBuilder
    private func toolIcon(_ block: AssistantBlock) -> some View {
        if let item = ToolEventRowFactory.item(for: block) {
            if item.usesSFSymbol {
                Image(systemName: item.iconName)
                    .font(.system(size: 15))
                    .foregroundStyle(SummaryPalette.muted)
            } else {
                AppSymbol(item.iconName, size: 17) // Lucide 内边距补偿：视觉 ≈16 [同 classic 行]
                    .foregroundStyle(SummaryPalette.muted)
            }
        }
    }

    // MARK: 纯思考原文（含流式尾渐显 [A6]）

    @ViewBuilder
    private func thinkingMergedText(size: CGFloat, serif: Bool) -> some View {
        let merged = thinkingBlocks.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !merged.isEmpty {
            let text = merged
            let tailCount = min(24, text.count)
            let settled = String(text.dropLast(tailCount))
            let tail = String(text.suffix(tailCount))
            let font: Font = serif ? .system(size: size, design: .serif) : .system(size: size)
            // [pp 09-18 渲染修复] 原先两半各自 `AttributedString(markdown:)`，三个害处：
            // ① 跨 24 字边界的 markdown 结构（**粗体**/`代码`/链接）被劈开 → 两半都
            //    解析失败 → 记号（星号/反引号）原样露在屏幕上；流式时边界每帧后移 →
            //    记号闪现；
            // ② 全仓只有本文件用 AttributedString(markdown:)，渲染结果与聊天流里的
            //    思考正文（AssistantBlockView 直接 Text(displayContent)，零解析）不一致；
            // ③ 默认 full 语法把软换行（单个 \n）当空格 → 分行丢失、整段挤成一坨。
            // 改纯 Text：换行原样保留、零解析歧义。衬线/字号/配色全不动。
            (Text(settled)
            .font(font)
            .foregroundStyle(Color(uiColor: .label))
            +
            Text(tail)
            .font(font)
            .foregroundStyle(isSegmentRunning ? Color(uiColor: .lightGray) : Color(uiColor: .label)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 详情页共享头部 [pp 09-18 拍板：标题整行居中，返回钮浮左（覆盖 photo_805DB84A 左对齐版）]
//
// 系统 navigationBar 无此形态（inline 居中 17pt / large 34pt），自绘头部；
// push/pop 转场与返回手势语义仍走系统 NavigationStack（dismiss = pop）。

private struct SummaryDetailHeader: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity) // [pp 09-18] 整行居中（返回钮浮左不挤占标题位）

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44) // 热区 [Claude 白圆钮 ≈44pt]
                        .background(Circle().fill(SummaryPalette.circleButton))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

// MARK: - 思考详情页（push：原文衬线直展）

private struct ThinkingDetailPage: View {
    @ObservedObject var message: ChatMessage
    let segment: TurnActivitySegment
    let isSegmentRunning: Bool
    let settledSeconds: Int?
    var onBack: () -> Void

    private var thinkingBlocks: [AssistantBlock] {
        segment.thinkingIds.compactMap { id in message.blocks.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            SummaryDetailHeader(
                title: settledSeconds.map { "Thought for \($0)s" } ?? "Thought",
                onBack: onBack
            )
            ScrollView {
                thinkingMergedText
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SummaryPalette.sheetBg)
    }

    @ViewBuilder
    private var thinkingMergedText: some View {
        let merged = thinkingBlocks.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !merged.isEmpty {
            let text = merged
            let tailCount = min(24, text.count)
            let settled = String(text.dropLast(tailCount))
            let tail = String(text.suffix(tailCount))
            let font = Font.system(size: 15.5, design: .serif)
            // [pp 09-18 渲染修复] 同 ThinkingDetailOverlay.thinkingMergedText：去 markdown
            // 解析，纯 Text 直出（换行保留、记号不外露）。见该处详注。
            (Text(settled)
            .font(font)
            .foregroundStyle(Color(uiColor: .label))
            +
            Text(tail)
            .font(font)
            .foregroundStyle(isSegmentRunning ? Color(uiColor: .lightGray) : Color(uiColor: .label)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 工具详情页（push：Input / Output 代码卡）[Claude photo_805DB84A]

private struct ToolSummaryDetailPage: View {
    @ObservedObject var message: ChatMessage
    let blockId: UUID
    var onBack: () -> Void

    private var block: AssistantBlock? {
        message.blocks.first { $0.id == blockId }
    }

    var body: some View {
        Group {
            if let block {
                content(block)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func content(_ block: AssistantBlock) -> some View {
        let title: String = {
            if let item = ToolEventRowFactory.item(for: block) {
                if let s = block.toolSummary, !s.isEmpty { return s }
                return item.title
            }
            return block.toolDescription
        }()

        VStack(spacing: 0) {
            SummaryDetailHeader(title: title, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(AppLocalized("Input"))
                    codeCard(languageTag(block), inputText(block))

                    let output = block.content
                    if !output.isEmpty {
                        sectionLabel(AppLocalized("Output"))
                            .padding(.top, 20)
                        codeCard(languageTag(block), output)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SummaryPalette.sheetBg)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(verbatim: title) // [CI #114 修复] AppLocalized 只收字面量 key，变量传参编译不过
            .font(.system(size: 15))
            .foregroundStyle(SummaryPalette.muted)
            .padding(.bottom, 10)
    }

    /// 代码卡 = SelectableMarkdownView fenced block（语言标签 + 语法高亮 + 圆角卡）。
    private func codeCard(_ lang: String, _ text: String) -> some View {
        SelectableMarkdownView(markdown: "```\(lang)\n\(text)\n```")
    }

    /// Input：完整参数 JSON（pretty）优先，factory 输入摘要兜底。
    private func inputText(_ block: AssistantBlock) -> String {
        if let raw = block.toolInputArgs, !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: pretty, encoding: .utf8), !s.isEmpty {
            return s
        }
        if let item = ToolEventRowFactory.item(for: block), !item.detail.isEmpty {
            return item.detail
        }
        return block.toolDescription
    }

    private func languageTag(_ block: AssistantBlock) -> String {
        switch block.kind {
        case .shellTool: return "shell"
        case .browserTool: return "browser"
        case .memoryTool: return "text"
        case .fileReadTool(let p), .fileWriteTool(let p), .fileEditTool(let p), .readImageTool(let p):
            return Self.extLang(p)
        case .text, .thinking, .info: return "text"
        }
    }

    private static func extLang(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "ts": return "typescript"
        case "js", "mjs", "cjs": return "javascript"
        case "py": return "python"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "shell"
        case "yml": return "yaml"
        case "md": return "markdown"
        case "swift", "json", "html", "css", "go", "rs", "java", "c", "cpp", "xml":
            return ext
        default:
            return ext.isEmpty ? "text" : ext
        }
    }
}

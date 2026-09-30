// TGLensHost.swift — TG 透镜岛的 SwiftUI 桥接层（本仓自研，非 TG 搬运件）
//
// [TG-LENS-PORT 2026-09-30] 职责：把移植的 LiquidLensView（TG 液态透镜）以
// UIViewRepresentable 形式桥进 ModeTabBar 的胶囊区：
//   · 图标（同 ModeTabBar 的 aa-Tabler 27pt 栅格化资产）装入透镜的
//     contentView（常态副本）/ selectedContentView（选中副本）——TG 原结构，
//     透镜的 punchout/warp 由私有类自行处理；
//   · **交互按 TG 原样放在岛内**（对抗复审 2026-09-30 阻断项②修正）：岛保持
//     可交互（玻璃 UIGlassEffect.isInteractive 的「拉缩+发光」需要真实触摸命中），
//     本岛挂一枚 0 延迟 UILongPressGestureRecognizer 跟踪按压（cancelsTouchesInView
//     = false，与玻璃的触摸响应并行；TG TabSelectionRecognizer 同理，
//     shouldRecognizeSimultaneously = true）。手势结果经 onCommit 回调 SwiftUI
//     （第 4 格设置齿轮另走 onSettings，见 iconAssets 下注释）。
//   · 透镜跟手 = TG 精确模型（TabBarComponent:538-545）：按下瞬间起点 = 被按槽位
//     的透镜 minX，其后 lensX = 起点 + 指尖位移增量（保留抓取偏移），钳制栏内。
//   · 松手落位 = TG 原样单跳（TabBarComponent:555-604）：TG 先清手势态、再以手指
//     下最后跟踪的 item 为目标做一次 spring——不存在「先弹回旧选中再回推」。
//     本岛 .ended 同步预置 selectionIndex 使推送直达提交槽；紧随的
//     apply(selectedIndex:) 同值短路不再二次推（旧实现两段弹簧竞速，第二推的
//     removeAllAnimations 会把透镜瞬打回旧槽模型位再重滑，2026-09-30 pp 装机实锤）。
//   · 跨树提交交接（本仓「每树一栏 + ZStack 瞬切」架构的桥，TG 单栏无此需求）：
//     跨树松手会换栏，出发岛把「松手瞬间透镜可见位 + 选中图标实际缩放」寄存
//     commitHandoff，目标树的岛在紧随的 apply() 里先瞬时落到该位、再续簧到提交槽
//     ——否则目标栏会从旧槽位整段重滑一遍（pp 装机「滑动 tab 落点/动画不对」的
//     另一半根因）。交接改「续实数」（带图标实际缩放，不一步补满）见 CommitHandoff
//     处的 [交接续实数 v3 2026-09-30]。
//
// 数值对齐 TG：innerInset 4；槽宽 = (宽-8)/4（TG 4 格布局：本 app 3 实 tab +
// 第 4 格设置齿轮，pp 2026-09-30 装机要求「加一个图标占位保持和tg一致大小」）；
// 第 4 格设置齿轮（pp 同日「把那个空白占位的 tab 加一个图标」）：动作位，点按开
// 设置（onSettings）、透镜永不驻留/提交该格（拖过钳回 works）；
// 透镜宽 = 槽宽+8、高 = 栏高；
// 按下的选中副本放大 1.15（:835），弹簧 0.4（:540/:599）。

import SwiftUI
import UIKit

/// 透镜岛：26+ 且私有类可选器形态完备时渲染 TG 移植透镜栏。
struct TGLensBar: UIViewRepresentable {
    /// 私有类可用性（调用方据此决定走岛还是回退玻璃版）。
    /// ⚠️ 探针清单只允许收「TG 原件里**无守卫直调**的选择器」（缺失即 unrecognized
    /// selector 崩溃，故必须探）；2026-09-30 装机实锤「永远回退、看起来什么也没搬」
    /// 的三重探针 bug，勿重蹈：
    ///   ① 幽灵选择器 `setRestingBackgroundColor:`——TG 全源码无此调用，凭空写进探针；
    ///   ② 把 TG 自身用 `method(for:)` 守卫的可选项当硬要求（setLiftedContentMode:
    ///      LiquidLensView.swift:231 / setStyle: :240 / setWarpsContentBelow: :249 /
    ///      setLifted:animated:alongsideAnimations:completion: :332——缺失只是少效果，
    ///      TG 原样容忍）；
    ///   ③ `alloc` 用 class_respondsToSelector 判（查实例方法，类方法恒 false）——
    ///      类方法不进探针（alloc 万类皆有）。
    /// 硬性集 = initWithRestingBackground:（:201）/ setLiftedContainerView:（:223,225,298）/
    /// setLiftedContentView:（:227）/ setOverridePunchoutView:（:228）。
    static var isSupported: Bool {
        guard let cls = NSClassFromString("_UILiquidLensView") else { return false }
        for name in [
            "initWithRestingBackground:", "setLiftedContainerView:",
            "setLiftedContentView:", "setOverridePunchoutView:",
        ] where class_getInstanceMethod(cls, NSSelectorFromString(name)) == nil {
            return false
        }
        return true
    }

    /// 栏内边距（TG innerInset）。
    static let innerInset: CGFloat = 4

    var selectedIndex: Int
    var isDark: Bool
    /// 本岛所属 tab 树的槽位序（0=local/1=remote/2=works，与 ModeTabBar.selectableTabs
    /// 同序）。用途 = 提交交接过滤：只有「刚被切进来的目标树」的岛才消费交接。
    var ownSlot: Int
    /// [第 4 格] 设置齿轮提交（动作位：开设置 sheet；调用方带跨树 guard）。
    var onSettings: () -> Void
    /// 手势提交（index = 0..2，对应 ModeTabBar.selectableTabs 次序）。
    var onCommit: (Int) -> Void

    func makeUIView(context: Context) -> TGLensBarView {
        // addAnimation swizzle 幂等安装（弹簧覆盖机制的前提；TG VC+Nav.m:557 同位）。
        installTGLensSwizzlesIfNeeded()
        let view = TGLensBarView()
        view.onCommit = onCommit
        view.onSettings = onSettings
        view.ownSlot = ownSlot
        // [探针 2026-10-01] 渲染路径判定：岛已创建（「硬落点」定位；判读后可删）。
        NavTrace.log("[LENS#\(view.instanceId)] island-created ownSlot=\(ownSlot)")
        return view
    }

    func updateUIView(_ view: TGLensBarView, context: Context) {
        view.onCommit = onCommit
        view.onSettings = onSettings
        view.ownSlot = ownSlot
        view.apply(selectedIndex: selectedIndex, isDark: isDark)
    }
}

/// 岛的 UIKit 实现：LiquidLensView + 图标副本装载 + 岛内手势（TG 模型）。
final class TGLensBarView: UIView, UIGestureRecognizerDelegate {
    var onCommit: ((Int) -> Void)?
    /// [第 4 格] 设置齿轮提交（见 TGLensBar.onSettings）。
    var onSettings: (() -> Void)?
    /// 本岛所属 tab 树的槽位序（0=local/1=remote/2=works）。见 TGLensBar.ownSlot。
    var ownSlot: Int = 0

    /// [硬落点修复 v3 2026-10-01] 实例编号（日志身份；岛会被反复重建，无编号时日志
    /// 无法把事件归到具体实例——上一轮判读的教训）。纯日志用途，无行为；判读后与
    /// 探针一并删。
    private static var instanceCounter = 0
    private(set) var instanceId: Int = 0

    /// [提交交接 2026-09-30] 「每树一栏 + ZStack 瞬切」架构的桥：跨树提交时可见栏
    /// 瞬切，出发岛的 .ended 把「松手瞬间透镜的可见位」寄存于此，目标树的岛在紧随
    /// 的 apply() 里先瞬时落到该位、再弹簧到提交槽——拼出 TG 单栏的连续落位。
    /// 消费规则（apply 内）：仅「目标树岛」（ownSlot == 新选中位）且交接来自别岛
    /// （fromSlot != ownSlot，防同岛复读）、槽位吻合、≤0.5s 新鲜时消费，消费即清空。
    /// 同槽提交写出的交接因 fromSlot == ownSlot == slot 永不被消费，残留无害。
    /// [交接续实数 v3 2026-09-30] iconScale = 松手瞬间被提交槽位选中图标的**实际**
    /// 缩放（按下弹簧在途时的屏上真值，非模型满值）。旧交接只带位置，消费端把图标
    /// 连同拉缩/光晕一步补满 = pp build 431 装机反馈「点击 tab 切换 放大和发亮
    /// 太快了；同页连点正常」——同树路径不经交接，故只有跨树复现。带实数后消费端
    /// 从真值续簧，跨树与同树的节奏一致（消费侧见 apply 内的 [交接续实数 v3]）。
    struct CommitHandoff {
        let slot: Int
        let fromSlot: Int
        let x: CGFloat
        /// 松手瞬间的选中图标缩放（1.0..~1.15 的在途值；读取失败兜底 1.15 = 旧行为）。
        let iconScale: CGFloat
        let at: CFTimeInterval
    }
    static var commitHandoff: CommitHandoff?

    /// 与 ModeTabBar.tabIcon 同源（注意：次序须与 ModeTabBar.selectableTabs
    /// [.local, .remote, .works] 保持一致）。
    private static let iconAssets = ["aa-Tabler-MessageCircle", "aa-Tabler-Cloud", "aa-Tabler-Puzzle"]

    /// [4 格对齐·第 4 格 2026-09-30 pp「把那个空白占位的 tab 加一个图标」]
    /// 设置齿轮：TG 第 4 tab 语义 = 设置（TelegramRootController 的 settings 位）；
    /// 本仓设置是全局 sheet（B16 单通道 router.showSettings，≡ 齿轮同款入口），
    /// 故为**动作位**（同 compose 圆钮）：点按开设置、透镜永不驻留该格
    /// （拖过该格的钳制语义不变，仍归 works）。文案 ="Settings"（沿用 ≡ 齿轮的
    /// localize key，勿自创）。资产 aa-Tabler-Settings 与 ContentView:7437 同源。
    private static let settingsAsset = "aa-Tabler-Settings"

    /// 槽位数 = 4（TG 4 格布局对齐：3 实图标 + 第 4 格设置齿轮，见上 settingsAsset；
    /// pp 2026-09-30 装机「加一个图标占位保持和tg一致大小」——TG 是其 4 tab 布局，
    /// 按 3 格算每格偏大）。
    /// 与 ModeTabBar.slotCount 同值，两岛/胶囊两处渲染路径几何一致。
    private static let slotCount = 4

    private let lens = LiquidLensView(kind: .externalContainer)
    private var normalIcons: [UIImageView] = []
    private var selectedIcons: [UIImageView] = []
    /// [第 4 格] 设置齿轮双副本（常态层 + 透镜下选中层，与三 tab 同构：透镜
    /// 拖过第 4 格时穿透窗下也有内容可显，不至镂空）。不进按下/提交逻辑。
    private let settingsNormal = UIImageView()
    private let settingsSelected = UIImageView()

    private var selectionIndex: Int = 0
    private var isDark: Bool = false

    // 岛内交互态（TG selectionGestureState 的等价物）
    private var interactionPressed: Int?
    private var interactionLensX: CGFloat?
    private var interactionStartLensX: CGFloat = 0
    private var interactionStartFingerX: CGFloat = 0
    /// [第 4 格·设置齿轮] 按住在齿轮上（动作位不进透镜手势；见 handleSelectionGesture）。
    private var gearPressActive = false
    /// [硬落点修复 v3 2026-10-01] 跨树复播收口：apply 消费/兜底时登记「起点 + 光晕槽 +
    /// 图标交接值」，由 runPendingReplay() 两段式执行（段 1 = 瞬时落位 + 图标续实数；
    /// 段 2 = 次 tick 起簧到提交槽）。旧实现（内联落位 + 一 tick 后补簧）在岛刚创建、
    /// bounds 未就绪时会把两段拆散吞掉（上一轮日志实锤的事故形态之一）；v3 起对
    /// bounds 时序免疫：就绪即跑，未就绪由 layoutSubviews/async 补驱。
    private struct PendingReplay {
        var startX: CGFloat
        var glowSlot: Int?
        var iconOverride: (Int, CGFloat)?
        /// 段 1 已执行标记（等段 2 起簧）。
        var placed: Bool = false
    }
    private var pendingReplay: PendingReplay?

    /// [硬落点修复 v3 2026-10-01] 推去重键（目标位/抬升态/岛尺寸；见 pushLens）。
    private struct PushKey: Equatable {
        var x: CGFloat
        var lifted: Bool
        var width: CGFloat
        var height: CGFloat
    }
    private var lastPushKey: PushKey?

    private static var tabImageCache: [String: UIImage] = [:]
    private static func tabImage(_ asset: String) -> UIImage {
        if let cached = tabImageCache[asset] {
            return cached
        }
        let side: CGFloat = 27
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            UIImage(named: asset)?.draw(in: CGRect(origin: .zero, size: CGSize(width: side, height: side)))
        }.withRenderingMode(.alwaysTemplate)
        tabImageCache[asset] = image
        return image
    }

    init() {
        super.init(frame: .zero)
        Self.instanceCounter += 1
        instanceId = Self.instanceCounter
        lens.instanceTag = "#\(instanceId)"
        lens.frame = bounds
        lens.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(lens)

        for asset in Self.iconAssets {
            let image = Self.tabImage(asset)
            let normal = UIImageView(image: image)
            normal.tintColor = .secondaryLabel
            normal.contentMode = .center
            normal.isUserInteractionEnabled = false
            lens.contentView.addSubview(normal)
            normalIcons.append(normal)

            let selected = UIImageView(image: image)
            selected.tintColor = .label
            selected.contentMode = .center
            selected.isUserInteractionEnabled = false
            lens.selectedContentView.addSubview(selected)
            selectedIcons.append(selected)
        }

        // [第 4 格] 设置齿轮双副本（常态/透镜下；着色同未选中件）。
        let settingsImage = Self.tabImage(Self.settingsAsset)
        settingsNormal.image = settingsImage
        settingsNormal.tintColor = .secondaryLabel
        settingsNormal.contentMode = .center
        settingsNormal.isUserInteractionEnabled = false
        lens.contentView.addSubview(settingsNormal)
        settingsSelected.image = settingsImage
        settingsSelected.tintColor = .label
        settingsSelected.contentMode = .center
        settingsSelected.isUserInteractionEnabled = false
        lens.selectedContentView.addSubview(settingsSelected)

        // TG TabSelectionRecognizer 的等价物：0 延迟长按追踪，不吞触摸（与玻璃的
        // isInteractive 触摸响应并行）。minimumPressDuration 0 = 按下即 began。
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.handleSelectionGesture(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        let slotWidth = self.slotWidth()
        let iconSide: CGFloat = 27
        for i in 0..<Self.iconAssets.count {
            let centerX = TGLensBar.innerInset + slotWidth * (CGFloat(i) + 0.5)
            let frame = CGRect(
                x: centerX - iconSide * 0.5,
                y: (height - iconSide) * 0.5,
                width: iconSide,
                height: iconSide
            )
            normalIcons[i].frame = frame
            selectedIcons[i].frame = frame
        }
        // [第 4 格] 设置齿轮：同栅格落位（槽位 3 中心）。
        let settingsCenterX = TGLensBar.innerInset + slotWidth * 3.5
        let settingsFrame = CGRect(
            x: settingsCenterX - iconSide * 0.5,
            y: (height - iconSide) * 0.5,
            width: iconSide,
            height: iconSide
        )
        settingsNormal.frame = settingsFrame
        settingsSelected.frame = settingsFrame
        // [硬落点修复 v3 2026-10-01] 复播在途 → 由本次布局驱动收口（bounds 现已
        // 就绪）；否则维持即时推（pushLens 内部同参去重，重复推不再杀在途弹簧）。
        if pendingReplay != nil {
            runPendingReplay()
        } else {
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: false)
        }
    }

    /// [硬落点修复 v3 2026-10-01] 复播两段式收口（见 PendingReplay 注释）：
    /// 段 1 = 瞬时落位（旧岛松手位/兜底起点，无动画）+ 图标续实数；段 2 = 次 tick
    /// 起簧（目标 = 提交槽；pushLens 去重保证与落位同参时不会重复下发）。bounds 未
    /// 就绪则原样保留，等 layoutSubviews（或下一次 apply 复播）再驱。幂等：任一
    /// 调度源先到者执行、后到者 guard 空转。
    private func runPendingReplay() {
        guard var replay = pendingReplay else { return }
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        if !replay.placed {
            // 段 1：落位 + 图标交接值（图标须在落位 pushLens 的图标循环之后写，
            // 否则被其 1.0/1.15 目标覆盖）。
            replay.placed = true
            pendingReplay = replay
            // [探针 v2 2026-10-01] 复播落位打点（「硬落点」判读；判读后可删）。
            let probeX = String(format: "%.1f", replay.startX)
            NavTrace.log("[LENS#\(instanceId)] replay place x=\(probeX) glow=\(replay.glowSlot != nil)")
            pushLens(pressed: replay.glowSlot, lensX: replay.startX, animated: false)
            if let iconOverride = replay.iconOverride {
                selectedIcons[iconOverride.0].transform = CGAffineTransform(
                    scaleX: iconOverride.1, y: iconOverride.1
                )
            }
            // 段 2：次 tick 起簧（等段 1 的这一帧提交后，与树硬切首帧渲染错开）。
            DispatchQueue.main.async { [weak self] in
                self?.runPendingReplay()
            }
        } else {
            // 段 2：起簧到提交槽。
            pendingReplay = nil
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: true)
        }
    }

    /// SwiftUI 侧状态下发（选中项 / 深色模式）；不做提前返回短路——pushLens 内部
    /// 的 Equatable 参数判重（LiquidLensView.update）已避免重复动画。
    func apply(selectedIndex: Int, isDark: Bool) {
        let indexChanged = selectionIndex != selectedIndex
        let changed = indexChanged || self.isDark != isDark
        // [硬落点修复 2026-10-01] 兜底起点所需的旧选中位（更新前取）。
        let previousSelectionIndex = selectionIndex
        selectionIndex = selectedIndex
        self.isDark = isDark
        if changed {
            if overrideUserInterfaceStyle != (isDark ? .dark : .light) {
                overrideUserInterfaceStyle = isDark ? .dark : .light
            }
            // [硬落点修复 2026-10-01] 目标岛进场的起点/光晕槽/图标交接值（消费或
            // 兜底路径写入，下方统一落位 + 推迟起簧）。
            var startX: CGFloat?
            var glowSlot: Int?
            var iconOverride: (Int, CGFloat)?
            // [提交交接] 本岛 = 刚被切进的目标树（ownSlot == 新选中位）且存有新鲜
            // 交接、且本岛无在途手势（interactionPressed == nil 且非齿轮按压——
            // 齿轮手势不置 interactionPressed，需 gearPressActive 另行排除，
            // 对抗复审 2026-09-30 低危项）→ 先瞬时落到交接位，再经下方同一套松手
            // 序列播放 setLifted(false) 收束 + 位置弹簧。消费即清空。
            if indexChanged, ownSlot == selectedIndex, interactionPressed == nil, !gearPressActive,
               let handoff = Self.commitHandoff,
               handoff.slot == selectedIndex,
               handoff.fromSlot != ownSlot,
               CACurrentMediaTime() - handoff.at <= 0.5 {
                Self.commitHandoff = nil
                // [探针 2026-10-01] 交接消费打点（「硬落点」定位；判读后可删）。
                NavTrace.log("[LENS#\(instanceId)] consume own=\(ownSlot) from=\(handoff.fromSlot) x=\(String(format: "%.1f", handoff.x)) iScale=\(String(format: "%.3f", handoff.iconScale))")
                // [交接续实数 v3 2026-09-30] 交接从「快照补满」改为「续真实进度」。
                // 旧实现在此一步把透镜补到满态（isLifted 拉缩 + 光晕，图标 1.15），
                // 而出发栏松手时弹簧通常只走到中途（快点按约半程）——补满那一步
                // 就成了「放大和发亮瞬间到位」= pp build 431 装机反馈「点击 tab
                // 切换 放大和发亮太快了；同页连点正常」（同树不经交接，故不复现）。
                // 改法：交接携带 handoff.iconScale（松手瞬间的屏上真值），快按时
                // 就在交接位保持半途、只把透镜落位，剩下进度交给下方同一条 release
                // 弹簧收尾——跨树与同树的观感节奏由此对齐。
                //
                // 光晕（isLifted）只能二值：TG 透镜的 lift 是私有类的一次性
                // setLifted:animated:，没有可寻的中间态，故用 iconScale 阈值近似
                // 「按得够不够久」——1.08 ≈ 按压 ≥0.15-0.3s（damping 0.8 的弹簧
                // 从 1.0 走到 1.15 约 0.3s）。够久 = 图标本已接近满态，维持今天带
                // 光晕的交接；不够久 = 快速点击，光晕此刻炸开比图标更突兀，故不吃
                // lift。阈值可按装机反馈微调（只动这一个数）。
                // [硬落点修复 v3 2026-10-01] 消费成功：只登记起点/光晕/图标交接值，
                // 落位与起簧走下方 runPendingReplay 两段式收口（对 bounds 时序免疫）。
                startX = handoff.x
                if handoff.iconScale > 1.08 { glowSlot = handoff.slot }
                iconOverride = (handoff.slot, handoff.iconScale)
            } else if indexChanged, ownSlot == selectedIndex {
                // [硬落点修复 2026-10-01] 无交接兜底：从本岛上一选中位整段滑入
                // （保证任何情况下都有整段可见滑动，不再出现「已在终点」的硬落点）。
                let fallbackX = CGFloat(previousSelectionIndex) * slotWidth()
                startX = fallbackX
                // [探针 2026-10-01] 兜底路径打点（判读后可删；显式分支拆链，规避
                // Swift 6.0.3 求解器病理）。
                let probeH: String
                if let h = Self.commitHandoff {
                    let age = String(format: "%.2f", CACurrentMediaTime() - h.at)
                    probeH = "slot=\(h.slot) from=\(h.fromSlot) age=\(age)"
                } else {
                    probeH = "nil"
                }
                let probeFX = String(format: "%.1f", fallbackX)
                NavTrace.log("[LENS#\(instanceId)] NO-CONSUME own=\(ownSlot) h=\(probeH) pressed=\(interactionPressed != nil) gear=\(gearPressActive) fallbackX=\(probeFX)")
            }
            if let startX {
                // [硬落点修复 v3 2026-10-01] 复播收口：登记起点/光晕/图标交接值 →
                // 走 runPendingReplay 两段式（段 1 同帧落位——与树硬切同事务、首帧
                // 无缝；段 2 次 tick 起簧到提交槽）。旧实现（内联落位 + 无条件补簧
                // + deferredSpringPending 保险）在岛刚创建、bounds 未就绪时会把
                // 落位/弹簧拆散吞掉——上一轮日志实锤的事故形态；v3 起对 bounds 时序
                // 免疫。bounds 未就绪时 runPendingReplay 原样保留，下面这枚 async 与
                // layoutSubviews 双驱（幂等，先到者执行）。
                pendingReplay = PendingReplay(startX: startX, glowSlot: glowSlot, iconOverride: iconOverride)
                runPendingReplay()
                DispatchQueue.main.async { [weak self] in
                    self?.runPendingReplay()
                }
            } else {
                pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: true)
            }
        }
    }

    // MARK: - 手势（TG TabBarComponent:525-604 的等价物）

    @objc private func handleSelectionGesture(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            // [第 4 格·设置齿轮] 动作位不进透镜手势：按下态给齿轮，松手开设置
            // （同 compose 圆钮语义；拖过第 4 格的钳制归属不变）。
            if rawSlotIndex(forX: location.x) >= Self.iconAssets.count {
                gearPressActive = true
                setSettingsPressed(true)
                return
            }
            // TG began：起点 = 被按槽位的透镜 minX（按下即弹簧吸到指尖槽位）。
            let slot = slotIndex(forX: location.x)
            interactionPressed = slot
            interactionStartFingerX = location.x
            interactionStartLensX = CGFloat(slot) * slotWidth()
            interactionLensX = interactionStartLensX
            pushLens(pressed: slot, lensX: interactionStartLensX, animated: true)
            // [探针 2026-10-01] 按压打点（判读后可删）。
            NavTrace.log("[LENS#\(instanceId)] press slot=\(slot) x0=\(String(format: "%.1f", interactionStartLensX))")
        case .changed:
            if gearPressActive {
                // 齿轮按压中移回 tab 区 = 撤销本次按压（不启动透镜手势）。
                if rawSlotIndex(forX: location.x) < Self.iconAssets.count {
                    gearPressActive = false
                    setSettingsPressed(false)
                }
                return
            }
            guard interactionPressed != nil else { return }
            // TG changed：lensX = 起点 + 指尖位移增量（保留抓取偏移），即时跟手。
            interactionLensX = interactionStartLensX + (location.x - interactionStartFingerX)
            let slot = slotIndex(forX: location.x)
            if slot != interactionPressed {
                interactionPressed = slot
            }
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: false)
        case .ended:
            if gearPressActive {
                gearPressActive = false
                setSettingsPressed(false)
                if rawSlotIndex(forX: location.x) >= Self.iconAssets.count {
                    onSettings?()
                }
                return
            }
            guard interactionPressed != nil else { return }
            let commitSlot = slotIndex(forX: location.x)
            // 交接位置必须在推动画之前读：push 一发出，透镜模型位置即指向提交槽。
            let handoffX = lens.currentSelectionOriginXForHandoff
            // [交接续实数 v3 2026-09-30] 同理读图标的实际缩放，且必须在推动画之前
            // （与 handoffX 同一时刻）：push 一发出，被按图标即被弹向 1.0，
            // presentation 就不再是松手瞬间的屏上值了。
            let handoffIconScale = currentSelectedIconScale(ofSlot: commitSlot)
            // [探针 2026-10-01] 松手打点（判读后可删）。Swift 6.0.3 求解器病理规避：
            // 链式 map+?? 拆为显式解包（判例见 Bug 库「求解器误诊」条）。
            let probeHX: String
            if let hx = handoffX { probeHX = String(format: "%.1f", hx) } else { probeHX = "nil" }
            NavTrace.log("[LENS#\(instanceId)] release slot=\(commitSlot) hx=\(probeHX) iScale=\(String(format: "%.3f", handoffIconScale))")
            interactionPressed = nil
            interactionLensX = nil
            // [TG 对齐 :555-604] TG 先清 selectionGestureState、再以提交 item 为目标
            // 做一次 spring——没有「先弹回旧选中」。同步预置 selectionIndex 使本推
            // 直达提交槽；紧随的 apply(selectedIndex:) 因同值短路，不再二次推
            // （旧实现：先推旧槽、再由 SwiftUI 回推新槽——第二推的 removeAllAnimations
            // 把透镜瞬打回旧槽模型位再重滑 = pp 装机实锤「落点/动画不对」的主半）。
            selectionIndex = commitSlot
            pushLens(pressed: nil, lensX: nil, animated: true)
            // 跨树提交交接：寄存松手瞬间的透镜可见位，供目标树的岛续簧（见 CommitHandoff）。
            if let handoffX {
                Self.commitHandoff = CommitHandoff(
                    slot: commitSlot, fromSlot: ownSlot, x: handoffX,
                    iconScale: handoffIconScale, at: CACurrentMediaTime()
                )
            }
            onCommit?(commitSlot)
        case .cancelled, .failed:
            if gearPressActive {
                gearPressActive = false
                setSettingsPressed(false)
                return
            }
            interactionPressed = nil
            interactionLensX = nil
            pushLens(pressed: nil, lensX: nil, animated: true)
        default:
            break
        }
    }

    /// 容器内坐标 → 槽位（TG item(at:) 的 ClosestItem 语义：越界钳制）。
    private func slotIndex(forX x: CGFloat) -> Int {
        return min(max(rawSlotIndex(forX: x), 0), Self.iconAssets.count - 1)
    }

    /// 未钳制槽位（≥3 = 第 4 格设置齿轮；.began/.changed/.ended 的动作位判别用）。
    private func rawSlotIndex(forX x: CGFloat) -> Int {
        let slotWidth = max(1.0, self.slotWidth())
        return Int(floor((x - TGLensBar.innerInset) / slotWidth))
    }

    /// [交接续实数 v3 2026-09-30] 被提交槽位的选中图标「松手瞬间」的实际缩放。
    /// 读 presentation 层：按下弹簧在途时模型 transform 已是满值 1.15，屏上真值
    /// 则按压时长停在 1.0→1.15 之间——正是要交给目标栏续弹簧的进度；无在途动画
    /// （presentation 返回 nil）退回模型层。两层都取不到 / 读出非正数或非有限值时
    /// 兜底 1.15 = 旧行为（补满）。读法与 LiquidLensView
    /// .currentSelectionOriginXForHandoff 同源（同一 .ended 时刻取屏上真值）。
    private func currentSelectedIconScale(ofSlot slot: Int) -> CGFloat {
        guard selectedIcons.indices.contains(slot) else { return 1.15 }
        // [CI 修复 2026-09-30] 刻意不用 `a()?.b.m11 ?? c.d.m11` 一条链的写法：
        // 该形态在 iOS target（default-isolation MainActor）下被 Swift 6.0.3 求解器
        // 误诊——第四轮构建实锤 TGLensHost.swift:420 报「no exact matches in call to
        // subscript」（把 Array 的 Int 下标判失败），而本文件他处同款下标正常、
        // Linux 等价复现器通过 ⇒ 纯求解器病理。拆成显式解包 + 单层读取，语义不变
        // （presentation 优先、模型层兜底）。`.a` 与 `.m11` 同义（CGAffineTransform
        // 的 1,1 位），此处用 `.a` 与本文件既有写法（pushLens/setSettingsPressed）一致。
        let icon: UIImageView = selectedIcons[slot]
        let scale: CGFloat
        if let presented: CALayer = icon.layer.presentation() {
            scale = presented.transform.m11
        } else {
            scale = icon.transform.a
        }
        return scale > 0 && scale.isFinite ? scale : 1.15
    }

    /// [第 4 格] 齿轮按压态（放大 1.15，同三 tab 的按压语言）。
    private func setSettingsPressed(_ pressed: Bool) {
        let target: CGAffineTransform = pressed
            ? CGAffineTransform(scaleX: 1.15, y: 1.15)
            : .identity
        for icon in [settingsNormal, settingsSelected] where abs(icon.transform.a - target.a) > 0.001 {
            UIView.animate(
                withDuration: 0.4,
                delay: 0.0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: { icon.transform = target },
                completion: nil
            )
        }
    }

    /// 槽宽 = (宽-8)/4（TG 4 格布局；pp 2026-09-30 装机：按 3 格算每格偏大）。
    private func slotWidth() -> CGFloat {
        return (bounds.width - TGLensBar.innerInset * 2) / CGFloat(Self.slotCount)
    }

    /// 透镜几何 + 按压放大（对照 TG TabBarComponent:868-887 / :835）。
    private func pushLens(pressed: Int?, lensX: CGFloat?, animated: Bool) {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        let slotWidth = self.slotWidth()
        let lensWidth = slotWidth + TGLensBar.innerInset * 2

        let x: CGFloat
        if let lensX {
            x = min(max(0.0, lensX), max(0.0, width - lensWidth))
        } else if let pressed {
            x = CGFloat(pressed) * slotWidth
        } else {
            x = CGFloat(selectionIndex) * slotWidth
        }

        // [硬落点修复 v3 2026-10-01] 推去重（治「tab 硬落点」病根）：与上次完全同参
        // （目标位/抬升态/岛尺寸全同）的推不再下发——这类「目标未变」的静默重复推
        // （layoutSubviews 每轮即推、apply 旁路推、复播后紧随的同参推）会走
        // LiquidLensView 非抬升分支的 removeAllAnimations，把刚起播的滑动弹簧当场
        // 杀停（上一轮日志实锤：62 条 move 动画全建了、46 次松手读数全为终值 = 动画
        // 建后被重复推杀掉）。去重后杀链从源头消失；尺寸变化（旋转等）会使 key
        // 变化 → 照常重算落位。
        let pushKey = PushKey(x: x, lifted: pressed != nil, width: width, height: height)
        if pushKey == lastPushKey {
            // 判读用：仅「带意图的动画推」被归并才打点（静默重复推归并不打，防噪）。
            if animated {
                let probeSkipX = String(format: "%.1f", x)
                NavTrace.log("[LENS#\(instanceId)] dedup-skip x=\(probeSkipX) (keeps in-flight spring)")
            }
            return
        }
        lastPushKey = pushKey

        // [探针 2026-10-01] 推动作与目标位（「硬落点」定位；判读后可删）。
        if animated {
            NavTrace.log("[LENS#\(instanceId)] push→ x=\(String(format: "%.1f", x)) lifted=\(pressed != nil)")
        }
        lens.update(
            size: CGSize(width: width, height: height),
            cornerRadius: nil,
            selectionOrigin: CGPoint(x: x, y: 0.0),
            selectionSize: CGSize(width: lensWidth, height: height),
            inset: TGLensBar.innerInset,
            isDark: isDark,
            isLifted: pressed != nil,
            isCollapsed: false,
            transition: animated ? .spring(duration: 0.4) : .immediate
        )

        // 按下的项：选中副本放大 1.15（TG :835，selectionGestureState != nil 期间）。
        // 缩放随帧过渡：began/ended = spring（:540/:604）、changed = immediate（:550）
        // ——跟手扫过槽位时放大要瞬时；旧实现恒 0.4s 弹簧，拖过槽位图标放大滞后
        // （2026-09-30 装机回归修正）。
        for (index, icon) in selectedIcons.enumerated() {
            let targetScale: CGFloat = (pressed == index) ? 1.15 : 1.0
            guard abs(icon.transform.a - targetScale) > 0.001 else { continue }
            let targetTransform: CGAffineTransform = targetScale == 1.0
                ? .identity
                : CGAffineTransform(scaleX: targetScale, y: targetScale)
            if animated {
                UIView.animate(
                    withDuration: 0.4,
                    delay: 0.0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.0,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: {
                        icon.transform = targetTransform
                    },
                    completion: nil
                )
            } else {
                icon.transform = targetTransform
            }
        }
    }
}

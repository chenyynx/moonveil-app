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
//
// [拉伸 v4 2026-10-01 · pp「tab切换流体没有被拉伸的感觉」] 拉伸机制解码（TG 真值，
// 逐条已核对上游源码，勿再猜）：
//   · TG 底栏**没有**任何主动拉伸代码。TouchEffect.swift 的 stretchVector 系统
//     在 TG 里只服务「可按压玻璃控件」，且**在底栏根本不挂**——GlassBackgroundView
//     的那枚 GlassHighlightGestureRecognizer 只在 legacy（<26）分支构造
//     （GlassBackgroundComponent.swift:552-556），iOS 26 走 nativeView 分支时
//     legacyView/legacyHighlightContainerView 皆 nil，识别器压根不存在。
//   · TG 底栏的「液态拉伸」= 私有 _UILiquidLensView 的渲染器随几何弹簧自形变：
//     TabBarComponent:868-887 逐帧算 lensSelection → LiquidLensView:409-457 逐帧
//     setPosition/bounds（iOS 26 上 `.spring(0.4)` 落到 bezier(0.38,0.7,0.125,1)，
//     CAAnimationUtils.swift:210-227）+ :450 那条无 key 的 additive 前缘钉位 +
//     抬升时 liftedInset 4↔−4 的尺寸变化（LiquidLensView:353/:410）。
//   · 观感为何退化：私有形变不可观测，且本仓同一份代码照搬时，弹簧在途被
//     双岛 + 杀链反复打断，形变随之归零 → 只剩刚体平移。
// 本文件的 v4 对策：①渲染侧单岛收口（同槽位后来者接管、先到者退场静止）；
//   ②LiquidLensView 侧撤掉看门狗与 removeAllAnimations（在途弹簧活着飞完，
//     见 LiquidLensView 适配 ⑧）；③透镜拉伸显式化——移动距离 × 0.28 增益、
//     以槽宽封顶（量级取 TouchEffect.swift:229-231 的 additionalMaxScale），
//     锚在飞行方向的前缘，衰减曲线与位置动画同款 → 拉伸量随剩余距离同步衰减。
//   ④TG 的 stretchVector 系统接线：按下/拖动时给「透镜下的选中副本」挂一枚
//     TouchEffect，按指尖位移喂 setStretchVector（TG 原件零改写）。

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
        // [单岛收口 v4] 同槽位的旧岛（若还活着）立即退场——见 slotOwners 注释。
        view.claimSlotOwner()
        // [探针 v4 2026-10-01] 渲染路径判定：岛已创建 + 是否顶替了旧岛（「双岛」
        // 定位；v4 目标 = island-created 反复出现时紧跟一条 retire）。
        NavTrace.log("[LENS#\(view.instanceId)] island-created ownSlot=\(ownSlot)")
        return view
    }

    func updateUIView(_ view: TGLensBarView, context: Context) {
        let previousSlot = view.ownSlot
        view.onCommit = onCommit
        view.onSettings = onSettings
        view.ownSlot = ownSlot
        // 槽位变了 = 换了归属的树，重新认领（否则会占着旧槽位的活岛身份）。
        if previousSlot != ownSlot {
            view.claimSlotOwner()
        }
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
    /// [拉伸 v4] 选中副本的承载容器（TG TouchEffect 的作用对象——TG 那枚
    /// TouchEffect 作用在「被按压的玻璃控件」上，用 `layer.sublayerTransform`
    /// 做方向性拉缩：TouchEffect.swift:192-251）。本仓被按压的玻璃控件 = 透镜下
    /// 那一枚选中副本，故给它加一层容器承载，图标自身的 transform（:835 的
    /// 1.15 / 交接续实数）不受影响、两者相乘。
    private var selectedIconHosts: [UIView] = []
    /// [第 4 格] 设置齿轮双副本（常态层 + 透镜下选中层，与三 tab 同构：透镜
    /// 拖过第 4 格时穿透窗下也有内容可显，不至镂空）。不进按下/提交逻辑。
    private let settingsNormal = UIImageView()
    private let settingsSelected = UIImageView()

    private var selectionIndex: Int = 0
    private var isDark: Bool = false

    // MARK: [单岛收口 v4 2026-10-01] 同槽位活岛注册表

    /// 装机日志实锤「每次切树新建一只岛、实例号递增、与常驻岛并存」
    /// （`[LENS#n] island-created ownSlot=1` 反复出现）——SwiftUI 在切树时会重建
    /// safeAreaInset 的内容，UIViewRepresentable 的身份随之重置；**身份根因在挂载
    /// 侧**（RootModeTabsView 的 tabTree / 各树 safeAreaInset 链，不在本文件域）。
    /// 本仓在渲染侧做等价收口：**同一槽位同一时刻只有一只活岛**，后来者接管、
    /// 先到者立即退场（retire = 静止、不接受任何下发、不参与动画、不被杀）。
    /// 于是「同一动作下发两次」「出场岛还在动/被杀」两类事故从结构上消失。
    private final class IslandRef {
        weak var value: TGLensBarView?
        init(_ value: TGLensBarView) { self.value = value }
    }
    private static var slotOwners: [Int: IslandRef] = [:]
    /// [v5 接力真值 2026-10-01] 槽位级「在途真值」寄存器：同槽位岛被顶替的
    /// **瞬间**，把旧岛透镜的屏上位置（presentation 优先）寄存于此——下只岛
    /// 落位的第一优先数据源。它比 CommitHandoff（.ended 采样，快击时弹簧未
    /// 起步 = 离散槽位值）晚一整段采样：连点/动画途中被顶替时，它就是弹簧的
    /// 当前帧（连续真值），透镜落位-续滑不再跳回离散槽位。
    private static var slotInFlightX: [Int: (x: CGFloat, at: CFTimeInterval)] = [:]
    /// 在途真值的新鲜窗（超窗弃用，防陈旧值把落点带偏）。
    private static let inFlightFreshWindow: CFTimeInterval = 0.6
    /// 「上一次提交发生前，提交方岛的选中位」= 这次切页**是从哪儿出发的**。
    /// 跨树新建目标岛、又恰好拿不到交接时，这就是唯一正确的兜底起点（旧实现用
    /// 新岛自己的 previousSelectionIndex——跨树新建时它恒为默认 0，是假起点）。
    /// 在 .ended 里「改写 selectionIndex 之前」取快照，见 handleSelectionGesture。
    private static var selectionBeforeLastCommit: Int = 0
    /// 陈旧交接的宽限窗（新鲜窗 0.5s 之外再给一段，只为「刚过窗就整段弹回」）。
    private static let staleHandoffGrace: CFTimeInterval = 3.0

    /// 拉伸增益与衰减时长（见文件头 [拉伸 v4]）：移动距离 × 0.28 得额外宽度，
    /// 以槽宽封顶；衰减 0.4s 与位置动画同曲线同长度（LiquidLensView 适配 ⑦）。
    private static let stretchGain: CGFloat = 0.28
    private static let stretchReleaseDuration: Double = 0.4

    /// 本岛是否已退场（被同槽位的新岛接管）。退场后所有下发入口空转。
    private var isRetired = false
    /// 上一次推动的目标 x（拉伸方向/距离的基准；nil = 还没推过）。
    private var lastStretchX: CGFloat?
    /// 拉伸锚在前缘还是后缘（= 上一次移动方向；向右为 true）。
    private var lastStretchLeading: Bool = true
    /// [拉伸 v4] 岛内手势期的 TouchEffect（TG 原件，按下时建、松手时丢）。
    private var touchEffect: TouchEffect?
    private var interactionStartFingerY: CGFloat = 0

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
        /// [v5] 屏上像素起点（在途真值/交接真值）——与 bounds 无关，直接可用。
        var startX: CGFloat?
        /// [v5] 槽位起点（prev-commit/prev-index 的兜底表达）——**绝不提前换算
        /// 像素**：新建岛 bounds 未就绪时换算曾产出负值（fallbackX=-4.0），
        /// 一律推迟到 runPendingReplay（bounds 就绪后）再乘 slotWidth()。
        var startSlot: Int?
        var glowSlot: Int?
        var iconOverride: (Int, CGFloat)?
        /// 段 1 已执行标记（等段 2 起簧）。
        var placed: Bool = false
    }
    private var pendingReplay: PendingReplay?

    /// [硬落点修复 v3 2026-10-01] 推去重键（目标位/抬升态/岛尺寸；见 pushLens）。
    /// [静止零重推 · 补漏 2026-10-01] 增 deep：`isDark` 是 LiquidLensView.Params 的
    /// 一等字段，不带它会把「切深浅色」误判成静默重复推（透镜停在旧材质）。
    private struct PushKey: Equatable {
        var x: CGFloat
        var lifted: Bool
        var width: CGFloat
        var height: CGFloat
        var dark: Bool
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
            // [拉伸 v4] 承载容器（TouchEffect 的作用对象，见 selectedIconHosts 注释）。
            let host = UIView()
            host.isUserInteractionEnabled = false
            host.addSubview(selected)
            lens.selectedContentView.addSubview(host)
            selectedIcons.append(selected)
            selectedIconHosts.append(host)
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

    deinit {
        if Self.slotOwners[ownSlot]?.value === self {
            Self.slotOwners[ownSlot] = nil
        }
    }

    // MARK: - [单岛收口 v4] 接管 / 退场

    private static func adoptSlotOwner(_ island: TGLensBarView) {
        let slot = island.ownSlot
        if let current = Self.slotOwners[slot]?.value, current !== island {
            // [v5 接力真值] 顶替瞬间采样旧岛透镜的屏上位置（presentation 优先，
            // 在途弹簧时 = 弹簧当前帧）——此值优先于交接/兜底被新岛消费。
            if let x = current.lens.currentSelectionOriginXForHandoff {
                Self.slotInFlightX[slot] = (x: x, at: CACurrentMediaTime())
            }
            current.retire(replacedBy: island)
        }
        Self.slotOwners[slot] = IslandRef(island)
    }

    /// [单岛收口 v4] 认领本槽位的活岛身份。**幂等**：重复调用只是把同一个引用
    /// 重新写回（不会误伤自己）。调用点 = 宿主在 makeUIView/updateUIView 写完
    /// ownSlot 之后——ownSlot 由宿主注入，init 里还是默认值 0，故不能在 init 认领。
    fileprivate func claimSlotOwner() {
        if isRetired, Self.slotOwners[ownSlot]?.value === self {
            return
        }
        Self.adoptSlotOwner(self)
        isRetired = false
    }

    /// 退场（被同槽位的新岛接管 / SwiftUI 摘下本岛）：清空一切在途与待办，
    /// 之后本岛的所有下发入口空转。**不清任何在途动画**——让弹簧自己飞完，
    /// 落点即静止，正是「出场岛静止、不参与动画、不被杀」的字面实现。
    fileprivate func retire(replacedBy next: TGLensBarView? = nil) {
        guard !isRetired else { return }
        isRetired = true
        pendingReplay = nil
        interactionPressed = nil
        interactionLensX = nil
        gearPressActive = false
        touchEffect?.setIsTracking(false, animated: false)
        touchEffect = nil
        let nextId = next?.instanceId ?? -1
        NavTrace.log("[LENS#\(instanceId)] retire ownSlot=\(ownSlot) → #\(nextId)")
        // [v5 残骸修复 2026-10-01] 退场即归位 + 摘除。装机截图实锤：底栏槽位
        // 出现「灰色的圆 + 黑色半弧」叠画残影，且随时间累积（08:18 只有黑弧、
        // 08:22 两样都有）——退休岛被 SwiftUI 顶替后未必当场回收其 UIView，
        // 而它又不再被任何人驱动（透镜定格在拉伸/错位态），两层同屏叠画即残影。
        // 摘除是安全的：retire 的全部场景 = 同槽位已有新岛接管（该位置此后由
        // 新岛唯一渲染）。归位（拉伸清零）是第二道保险：万一它被系统某处短暂
        // 引用，也不再以拉伸态示人。
        lens.setLensStretch(scaleX: 1.0, leadingIsAnchor: true)
        if superview != nil {
            removeFromSuperview()
        }
    }

    /// 复活判定：只有当本槽位**当前无主**（持有者已被释放）时才重新夺回；
    /// 否则保持退场（这样「同一动作两次下发」不可能再发生）。
    private func ensureActive() {
        guard isRetired else { return }
        guard Self.slotOwners[ownSlot]?.value == nil else { return }
        // [v5 摘除配套] 若本岛在退休时已被摘出视图树（v5 残骸修复），复活它
        // 会在 representable 位置上留空——弃权，等下一条新岛接管（该路径只在
        // 异常时序可达；正常路径退休岛不会再收到 apply）。
        if superview == nil {
            NavTrace.log("[LENS#\(instanceId)] re-adopt 弃权（已摘除）ownSlot=\(ownSlot)")
            return
        }
        isRetired = false
        Self.slotOwners[ownSlot] = IslandRef(self)
        NavTrace.log("[LENS#\(instanceId)] re-adopt ownSlot=\(ownSlot)")
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
            // [拉伸 v4] TouchEffect 作用在承载容器上：容器与图标同框（容器尺寸即
            // TouchEffect 的参考尺寸——它的拉伸公式吃 view.bounds，见 TouchEffect
            // :192-231）。
            selectedIconHosts[i].frame = frame
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
        // [单岛收口 v4] 退场岛不再参与任何下发（出场树的岛在 ZStack 里仍活着，
        // 若继续推就是在隐藏树上跑弹簧）。
        guard !isRetired else { return }
        // [硬落点修复 v3 2026-10-01] 复播在途 → 由本次布局驱动收口（bounds 现已
        // 就绪）；否则维持即时推（pushLens 内部同参去重，重复推不再杀在途弹簧）。
        if pendingReplay != nil {
            runPendingReplay()
        } else {
            // [v5 拉伸分层] 布局维持推不碰拉伸（旧式在松手衰减期间被 layout 轮
            // 推 setLensStretch(1.0) 砍断 = 「拉伸一闪就没」的直接机制）。
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: false, allowStretch: false)
        }
    }

    /// [硬落点修复 v3 2026-10-01] 复播两段式收口（见 PendingReplay 注释）：
    /// 段 1 = 瞬时落位（旧岛松手位/兜底起点，无动画）+ 图标续实数；段 2 = 次 tick
    /// 起簧（目标 = 提交槽；pushLens 去重保证与落位同参时不会重复下发）。bounds 未
    /// 就绪则原样保留，等 layoutSubviews（或下一次 apply 复播）再驱。幂等：任一
    /// 调度源先到者执行、后到者 guard 空转。
    private func runPendingReplay() {
        guard !isRetired, var replay = pendingReplay else { return }
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        if !replay.placed {
            // 段 1：落位 + 图标交接值（图标须在落位 pushLens 的图标循环之后写，
            // 否则被其 1.0/1.15 目标覆盖）。
            replay.placed = true
            pendingReplay = replay
            // [v5] 起点解算：像素真值优先；槽位表达在此刻（bounds 已就绪）换算。
            let resolvedX: CGFloat
            if let px = replay.startX {
                resolvedX = px
            } else {
                resolvedX = CGFloat(replay.startSlot ?? 0) * slotWidth()
            }
            // [探针 v2 2026-10-01] 复播落位打点（「硬落点」判读；判读后可删）。
            let probeX = String(format: "%.1f", resolvedX)
            NavTrace.log("[LENS#\(instanceId)] replay place x=\(probeX) glow=\(replay.glowSlot != nil)")
            // [v5 拉伸分层] 落位 = 摆位（不是飞行）——不碰拉伸：形变交给段 2 的
            // 起簧推（其 distance=落位点到目标，衰减与滑动同步起跑）。
            pushLens(pressed: replay.glowSlot, lensX: resolvedX, animated: false, allowStretch: false)
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
        // [单岛收口 v4] 退场岛不接受任何下发；槽位无主时先复活再走正常路径。
        ensureActive()
        guard !isRetired else { return }
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
            // [单岛收口 v4 · 离场树闸] 保活 ZStack 里三棵树的岛都活着，但只有
            // 「刚被切进来的那一棵」（ownSlot == 新选中位）该驱动透镜——离场树继续
            // 按 apply 推 = 在 opacity 0 的树上跑一整条弹簧（装机日志「同一动作
            // 下发两次」的另一半来源，也是隐藏树动画互相打断的源头）。
            // 本闸只关**位移/复播**，深色等外观更新照旧（pushLens 在闸外，见下）。
            if indexChanged, ownSlot != selectedIndex {
                NavTrace.log("[LENS#\(instanceId)] idle-gate own=\(ownSlot) target=\(selectedIndex)")
                // 无动画地把模型位对齐（保模型状态自洽，也让深浅色之类的外观字段
                // 落到透镜上），**不起任何弹簧**——隐藏树上不该有动画在跑。
                // [v5 拉伸分层] 对齐推不碰拉伸：旧式会按「跨槽距离」把 1.251 形变
                // **钉死**在隐藏树透镜上（装机日志 `LENS-GEO … m11=1.251` 无衰减），
                // 该树再进场时以拉伸态示人 = 残影来源之一。
                pushLens(pressed: nil, lensX: nil, animated: false, allowStretch: false)
                return
            }
            // [硬落点修复 2026-10-01] 目标岛进场的起点/光晕槽/图标交接值（消费或
            // 兜底路径写入，下方统一落位 + 推迟起簧）。
            // [v5] 起点双表达：像素真值（startX，随存随用）或槽位（startSlot，
            // bounds 就绪后再换算）——二者至多一个非 nil。
            var startX: CGFloat?
            var startSlot: Int?
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
                // [v5 接力真值] 槽位在途真值采样更晚（顶替瞬间 vs 松手瞬间）、
                // 「重建竞赛」与连点途中它就是簧的当前帧——新鲜时覆盖交接位。
                if let flight = Self.slotInFlightX[ownSlot],
                   CACurrentMediaTime() - flight.at <= Self.inFlightFreshWindow {
                    startX = flight.x
                }
                if handoff.iconScale > 1.08 { glowSlot = handoff.slot }
                iconOverride = (handoff.slot, handoff.iconScale)
            } else if indexChanged, ownSlot == selectedIndex {
                // [v5 接力真值 2026-10-01] 无新鲜交接时的**四级固定兜底**（顺序
                // 不变、日志打出命中级，杜绝「有时从 0 弹、有时从上一槽弹」）：
                //   ⓪ 槽位在途真值（≤0.6s）——同槽位岛刚被顶替瞬间采样的屏上位置
                //      （连点/重建竞赛途中 = 弹簧当前帧）；旧三级兜底全是**离散槽位**
                //      或**松手瞬间**采样，动画途中的位置连续性由此保证；
                //   ① 指向本槽位的陈旧交接（≤3s）——刚过 0.5s 新鲜窗时用它；
                //   ② 提交方岛「提交前」的选中位（跨树**新建**岛时本岛
                //      previousSelectionIndex 恒为默认 0 = 假起点）；
                //   ③ 本岛自己的上一选中位。
                // ⓪① 是屏上像素真值（与 bounds 无关，直接可用）；②③ 是槽位表达，
                // 像素换算一律推迟到 runPendingReplay（bounds 就绪后）——新建岛
                // bounds=0 时提前换算曾产出负数（fallbackX=-4.0 的出处）。
                var fallbackSource = "prev-index(\(previousSelectionIndex))"
                var fallbackSlot: Int? = previousSelectionIndex
                var fallbackPixel: CGFloat?
                let now = CACurrentMediaTime()
                if let flight = Self.slotInFlightX[ownSlot], now - flight.at <= Self.inFlightFreshWindow {
                    fallbackPixel = flight.x
                    fallbackSlot = nil
                    fallbackSource = "in-flight(\(String(format: "%.2f", now - flight.at))s)"
                } else if let handoff = Self.commitHandoff,
                   handoff.slot == selectedIndex,
                   handoff.fromSlot != ownSlot,
                   now - handoff.at <= Self.staleHandoffGrace {
                    fallbackPixel = handoff.x
                    fallbackSlot = nil
                    fallbackSource = "stale-handoff"
                } else if Self.selectionBeforeLastCommit != selectedIndex {
                    fallbackSlot = Self.selectionBeforeLastCommit
                    fallbackSource = "prev-commit(\(Self.selectionBeforeLastCommit))"
                }
                startX = fallbackPixel
                startSlot = fallbackSlot
                // [探针 v4 2026-10-01] 兜底路径打点（判读后可删；显式分支拆链，规避
                // Swift 6.0.3 求解器病理）。[v5] fallbackX 打「将要用的值」——像素
                // 级直显、槽位级注名（避免 bounds 未就绪期打假数误判）。
                let probeH: String
                if let h = Self.commitHandoff {
                    let age = String(format: "%.2f", CACurrentMediaTime() - h.at)
                    probeH = "slot=\(h.slot) from=\(h.fromSlot) age=\(age)"
                } else {
                    probeH = "nil"
                }
                let probeFX: String
                if let px = fallbackPixel {
                    probeFX = String(format: "%.1f", px)
                } else {
                    probeFX = "slot\(fallbackSlot ?? 0)"
                }
                NavTrace.log("[LENS#\(instanceId)] NO-CONSUME own=\(ownSlot) h=\(probeH) pressed=\(interactionPressed != nil) gear=\(gearPressActive) via=\(fallbackSource) fallbackX=\(probeFX)")
            }
            if startX != nil || startSlot != nil {
                // [硬落点修复 v3 2026-10-01] 复播收口：登记起点/光晕/图标交接值 →
                // 走 runPendingReplay 两段式（段 1 同帧落位——与树硬切同事务、首帧
                // 无缝；段 2 次 tick 起簧到提交槽）。旧实现（内联落位 + 无条件补簧
                // + deferredSpringPending 保险）在岛刚创建、bounds 未就绪时会把
                // 落位/弹簧拆散吞掉——上一轮日志实锤的事故形态；v3 起对 bounds 时序
                // 免疫。bounds 未就绪时 runPendingReplay 原样保留，下面这枚 async 与
                // layoutSubviews 双驱（幂等，先到者执行）。
                pendingReplay = PendingReplay(startX: startX, startSlot: startSlot, glowSlot: glowSlot, iconOverride: iconOverride)
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
        // [单岛收口 v4] 退场岛的手势整段空转（出场树不该还能点得动透镜）。
        guard !isRetired else { return }
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
            interactionStartFingerY = location.y
            interactionStartLensX = CGFloat(slot) * slotWidth()
            interactionLensX = interactionStartLensX
            // [拉伸 v4] 接线 TG 的 stretchVector 系统（TG 原件零改写）：作用对象 =
            // 透镜下被按压的那枚选中副本的承载容器。TG 侧这枚识别器只挂在 legacy
            // 玻璃控件上、iOS 26 的底栏压根不构造它（GlassBackgroundComponent
            // .swift:552-556），本仓把它接到语义最贴近的位置——「手指按着的那块玻璃
            // 里的东西」，其 :192-251 的方向性拉缩（按 stretchVector 的方向与长度
            // 决定压扁/拉长比与位移）即拖拽时的图标拖尾。
            // pressedSizeIncrease 取 0：按压放大已由 TG :835 的 1.15 提供，
            // 两处都开会叠成 ~1.5 倍（TG 那 20.0 是给 56pt 高的 tab 项调的）。
            if selectedIconHosts.indices.contains(slot) {
                let effect = TouchEffect(view: selectedIconHosts[slot], highlightContainerView: nil)
                effect.parameters.pressedSizeIncrease = 0.0
                effect.setStretchVector(.zero, animated: false)
                effect.setIsTracking(true, animated: false)
                touchEffect = effect
            }
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
                // 拖过槽位 = 换了被按的图标，TouchEffect 跟着换宿主（TG 语义：拉缩
                // 始终作用于「当前被按住的那块玻璃」）。
                if let effect = touchEffect, selectedIconHosts.indices.contains(slot) {
                    effect.setIsTracking(false, animated: false)
                    let next = TouchEffect(view: selectedIconHosts[slot], highlightContainerView: nil)
                    next.parameters.pressedSizeIncrease = 0.0
                    next.setStretchVector(.zero, animated: false)
                    next.setIsTracking(true, animated: false)
                    touchEffect = next
                }
            }
            // [拉伸 v4] 喂 TG 的拉伸向量：指尖相对按下点的位移（未归一化，TG 公式
            // 自己在 TouchEffect:217-231 里按视口尺寸归一）。
            touchEffect?.setStretchVector(
                CGPoint(x: location.x - interactionStartFingerX, y: location.y - interactionStartFingerY),
                animated: false
            )
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: false)
        case .ended:
            if gearPressActive {
                gearPressActive = false
                setSettingsPressed(false)
                touchEffect?.setIsTracking(false, animated: true)
                touchEffect = nil
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
            // [拉伸 v4] 松手 = 抬落弹簧（TG TouchEffect 的 liftOff 弹簧，:125-130 /
            // :253-262 / :306-318）——图标方向性形变自然回弹。
            touchEffect?.setIsTracking(false, animated: true)
            touchEffect = nil
            // [单岛收口 v4 · 确定性兜底] 快照「出发选中位」——必须在本行改写
            // selectionIndex 之前取，否则记下的是提交槽（= 目标位），兜底时又变成
            // 「已在终点」的硬落点。
            Self.selectionBeforeLastCommit = selectionIndex
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
            // [拉伸 v4] 同 .ended：中断也走一次抬落弹簧（与 TG 的 touchesCancelled
            // 同款，TouchEffect.swift:76-81）。
            touchEffect?.setIsTracking(false, animated: true)
            touchEffect = nil
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
    /// [v5 防负 2026-10-01] 新建岛的 bounds 未就绪时，旧式会算出 (0−8)/4 = −2.0，
    /// 兜底 fallbackX = 槽位×(−2.0) = 负值——装机日志 `fallbackX=-4.0` 的出处，
    /// 透镜被摆到负坐标再滑（「闪跳」观感）。钳到 0：未就绪期的一切像素换算
    /// 统一交给 runPendingReplay 的 bounds guard（届时才是真几何）。
    private func slotWidth() -> CGFloat {
        return max(0, bounds.width - TGLensBar.innerInset * 2) / CGFloat(Self.slotCount)
    }

    /// 透镜几何 + 按压放大 + [拉伸 v4] 飞行中的横向拉伸（对照 TG TabBarComponent:868-887 / :835）。
    /// [v5 拉伸分层] allowStretch=false 的推（落位/对齐/维持）不施加形变——
    /// 见下方拉伸段注释。
    private func pushLens(pressed: Int?, lensX: CGFloat?, animated: Bool, allowStretch: Bool = true) {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        // [单岛收口 v4] 退场岛不推（出场树的岛仍活着的话就是隐藏树上的空跑）。
        guard !isRetired else { return }
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
        // （目标位/抬升态/岛尺寸/深色全同）的推不再下发——这类「目标未变」的静默重复推
        // （layoutSubviews 每轮即推、apply 旁路推、复播后紧随的同参推）会走
        // LiquidLensView 非抬升分支的清键支路，把刚起播的滑动弹簧打断（上一轮日志
        // 实锤：62 条 move 动画全建了、46 次松手读数全为终值 = 动画建后被重复推杀掉）。
        // 去重后静默重复推从源头消失；尺寸变化（旋转等）会使 key 变化 → 照常重算落位。
        // [静止零重推 · 补漏 2026-10-01] key 增列 isDark：原 key 不含深色，切深浅色
        // 时「目标位/抬升态/尺寸全同」→ 被误判为静默重复推 → 透镜停在旧深浅的
        // 材质（LiquidLensView.Params.isDark 不再被下发）。这是 G4 的唯一漏网项。
        let pushKey = PushKey(x: x, lifted: pressed != nil, width: width, height: height, dark: isDark)
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

        // [拉伸 v4 2026-10-01] 飞行中的横向拉伸（TG 观感的显式化，机制取真值见
        // 文件头 [拉伸 v4]）。形变量 = 本次目标 x 与上次目标 x 的距离 × 0.28，
        // 以槽宽封顶（跨两格时不再继续拉长 = 液态的饱和感），换算成透镜视图的
        // 横向 scale；锚在**飞行方向的前缘**（向右飞 → 前缘在左），于是视觉上
        // 是「被拖着走、后缘被抹开」，而不是整体横向涨一圈。
        //   · 带动画的推（按下吸附 / 松手落位 / 复播起簧）→ 起一次衰减动画，时长
        //     曲线与位置动画同款 → 拉伸量随剩余距离同步衰减到 0；
        //   · 即时推（拖拽跟手帧）→ 直接落形变，指尖到哪形变到哪；
        //   · 形变量 ≈ 0 的带动画推（典型：.began 吸附后 .ended 又推同一格）→
        //     **不动**，否则会把 .began 的衰减从半路掐断（观感上的「回弹一抖」）。
        // [v5 拉伸分层 2026-10-01] allowStretch=false 的推（复播段 1 落位 /
        // idle-gate 对齐 / layoutSubviews 维持）**完全不碰形变**。旧式它们
        // distance≈0 时 setLensStretch(1.0) 会把在途衰减**瞬时砍断**（「拉伸感
        // 一闪就没」的直接机制）；idle-gate 更会按跨槽距离把 1.251 形变**钉死**
        // 在隐藏树上（装机日志 `LENS-GEO … m11=1.251` 无衰减）。基准
        // （lastStretchX/leading）照常更新——它描述「透镜在谁手上」，与是否
        // 施加形变无关；下一根起簧推的 distance 由此永远正确。
        let previousX = self.lastStretchX
        if let previousX, abs(x - previousX) > 0.5 {
            lastStretchLeading = (x - previousX) > 0
        }
        lastStretchX = x
        if allowStretch {
            let distance = previousX.map { abs($0 - x) } ?? 0
            let extra = min(distance, slotWidth) * Self.stretchGain
            let stretchScaleX = 1.0 + extra / max(1.0, lensWidth)
            if animated {
                if stretchScaleX > 1.02 {
                    lens.animateLensStretchRelease(
                        fromScaleX: stretchScaleX,
                        leadingIsAnchor: lastStretchLeading,
                        duration: Self.stretchReleaseDuration
                    )
                }
            } else if extra > 0.5 {
                // [v5] 即时推只在「真的有位移」时落形变——distance≈0 的维持推
                // 若落 setLensStretch(1.0) 会把在途衰减瞬时砍断（观感一闪）。
                lens.setLensStretch(scaleX: stretchScaleX, leadingIsAnchor: lastStretchLeading)
            }
        }

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

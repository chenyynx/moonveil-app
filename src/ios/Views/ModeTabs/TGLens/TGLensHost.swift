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
//     跨树松手会换栏，出发岛把「松手瞬间透镜可见位」寄存 commitHandoff，目标树的
//     岛在紧随的 apply() 里先瞬时落到该位、再续簧到提交槽——否则目标栏会从旧槽位
//     整段重滑一遍（pp 装机「滑动 tab 落点/动画不对」的另一半根因）。
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

    /// [提交交接 2026-09-30] 「每树一栏 + ZStack 瞬切」架构的桥：跨树提交时可见栏
    /// 瞬切，出发岛的 .ended 把「松手瞬间透镜的可见位」寄存于此，目标树的岛在紧随
    /// 的 apply() 里先瞬时落到该位、再弹簧到提交槽——拼出 TG 单栏的连续落位。
    /// 消费规则（apply 内）：仅「目标树岛」（ownSlot == 新选中位）且交接来自别岛
    /// （fromSlot != ownSlot，防同岛复读）、槽位吻合、≤0.5s 新鲜时消费，消费即清空。
    /// 同槽提交写出的交接因 fromSlot == ownSlot == slot 永不被消费，残留无害。
    struct CommitHandoff {
        let slot: Int
        let fromSlot: Int
        let x: CGFloat
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
        pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: false)
    }

    /// SwiftUI 侧状态下发（选中项 / 深色模式）；不做提前返回短路——pushLens 内部
    /// 的 Equatable 参数判重（LiquidLensView.update）已避免重复动画。
    func apply(selectedIndex: Int, isDark: Bool) {
        let indexChanged = selectionIndex != selectedIndex
        let changed = indexChanged || self.isDark != isDark
        selectionIndex = selectedIndex
        self.isDark = isDark
        if changed {
            if overrideUserInterfaceStyle != (isDark ? .dark : .light) {
                overrideUserInterfaceStyle = isDark ? .dark : .light
            }
            // [提交交接] 本岛 = 刚被切进的目标树（ownSlot == 新选中位）且存有新鲜
            // 交接、且本岛无在途手势（interactionPressed == nil 且非齿轮按压——
            // 齿轮手势不置 interactionPressed，需 gearPressActive 另行排除，
            // 对抗复审 2026-09-30 低危项）→ 先瞬时以
            // 「按压态」落到交接位——拉缩/光晕/放大图标与出发栏松手瞬间同像素
            // （换栏连续），再经下方同一套松手序列播放 setLifted(false) 收束 +
            // 位置弹簧。旧实现只交接位置、换栏即熄发亮 = pp「发亮也很快」
            // （2026-09-30 第二轮装机判定）。消费即清空。
            if indexChanged, ownSlot == selectedIndex, interactionPressed == nil, !gearPressActive,
               let handoff = Self.commitHandoff,
               handoff.slot == selectedIndex,
               handoff.fromSlot != ownSlot,
               CACurrentMediaTime() - handoff.at <= 0.5 {
                Self.commitHandoff = nil
                pushLens(pressed: handoff.slot, lensX: handoff.x, animated: false)
            }
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: true)
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
                    slot: commitSlot, fromSlot: ownSlot, x: handoffX, at: CACurrentMediaTime()
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

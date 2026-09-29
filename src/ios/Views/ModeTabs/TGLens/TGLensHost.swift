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
//     shouldRecognizeSimultaneously = true）。手势结果经 onCommit 回调 SwiftUI。
//   · 透镜跟手 = TG 精确模型（TabBarComponent:538-545）：按下瞬间起点 = 被按槽位
//     的透镜 minX，其后 lensX = 起点 + 指尖位移增量（保留抓取偏移），钳制栏内。
//
// 数值对齐 TG：innerInset 4；槽宽 = (宽-8)/3；透镜宽 = 槽宽+8、高 = 栏高；
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
    /// 手势提交（index = 0..2，对应 ModeTabBar.selectableTabs 次序）。
    var onCommit: (Int) -> Void

    func makeUIView(context: Context) -> TGLensBarView {
        // addAnimation swizzle 幂等安装（弹簧覆盖机制的前提；TG VC+Nav.m:557 同位）。
        installTGLensSwizzlesIfNeeded()
        let view = TGLensBarView()
        view.onCommit = onCommit
        return view
    }

    func updateUIView(_ view: TGLensBarView, context: Context) {
        view.onCommit = onCommit
        view.apply(selectedIndex: selectedIndex, isDark: isDark)
    }
}

/// 岛的 UIKit 实现：LiquidLensView + 图标副本装载 + 岛内手势（TG 模型）。
final class TGLensBarView: UIView, UIGestureRecognizerDelegate {
    var onCommit: ((Int) -> Void)?

    /// 与 ModeTabBar.tabIcon 同源（注意：次序须与 ModeTabBar.selectableTabs
    /// [.local, .remote, .works] 保持一致）。
    private static let iconAssets = ["aa-Tabler-MessageCircle", "aa-Tabler-Cloud", "aa-Tabler-Puzzle"]

    private let lens = LiquidLensView(kind: .externalContainer)
    private var normalIcons: [UIImageView] = []
    private var selectedIcons: [UIImageView] = []

    private var selectionIndex: Int = 0
    private var isDark: Bool = false

    // 岛内交互态（TG selectionGestureState 的等价物）
    private var interactionPressed: Int?
    private var interactionLensX: CGFloat?
    private var interactionStartLensX: CGFloat = 0
    private var interactionStartFingerX: CGFloat = 0

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
        pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: false)
    }

    /// SwiftUI 侧状态下发（选中项 / 深色模式）；不做提前返回短路——pushLens 内部
    /// 的 Equatable 参数判重（LiquidLensView.update）已避免重复动画。
    func apply(selectedIndex: Int, isDark: Bool) {
        let changed = selectionIndex != selectedIndex || self.isDark != isDark
        selectionIndex = selectedIndex
        self.isDark = isDark
        if changed {
            if overrideUserInterfaceStyle != (isDark ? .dark : .light) {
                overrideUserInterfaceStyle = isDark ? .dark : .light
            }
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: true)
        }
    }

    // MARK: - 手势（TG TabBarComponent:525-604 的等价物）

    @objc private func handleSelectionGesture(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            // TG began：起点 = 被按槽位的透镜 minX（按下即弹簧吸到指尖槽位）。
            let slot = slotIndex(forX: location.x)
            interactionPressed = slot
            interactionStartFingerX = location.x
            interactionStartLensX = CGFloat(slot) * slotWidth()
            interactionLensX = interactionStartLensX
            pushLens(pressed: slot, lensX: interactionStartLensX, animated: true)
        case .changed:
            guard interactionPressed != nil else { return }
            // TG changed：lensX = 起点 + 指尖位移增量（保留抓取偏移），即时跟手。
            interactionLensX = interactionStartLensX + (location.x - interactionStartFingerX)
            let slot = slotIndex(forX: location.x)
            if slot != interactionPressed {
                interactionPressed = slot
            }
            pushLens(pressed: interactionPressed, lensX: interactionLensX, animated: false)
        case .ended:
            guard interactionPressed != nil else { return }
            let commitSlot = slotIndex(forX: location.x)
            interactionPressed = nil
            interactionLensX = nil
            // 落位（spring 回当前选中槽；提交引发的选中变化会再驱动一次到新槽）。
            pushLens(pressed: nil, lensX: nil, animated: true)
            onCommit?(commitSlot)
        case .cancelled, .failed:
            interactionPressed = nil
            interactionLensX = nil
            pushLens(pressed: nil, lensX: nil, animated: true)
        default:
            break
        }
    }

    /// 容器内坐标 → 槽位（TG item(at:) 的 ClosestItem 语义：越界钳制）。
    private func slotIndex(forX x: CGFloat) -> Int {
        let slotWidth = max(1.0, self.slotWidth())
        let raw = Int(floor((x - TGLensBar.innerInset) / slotWidth))
        return min(max(raw, 0), Self.iconAssets.count - 1)
    }

    private func slotWidth() -> CGFloat {
        return (bounds.width - TGLensBar.innerInset * 2) / CGFloat(Self.iconAssets.count)
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
        for (index, icon) in selectedIcons.enumerated() {
            let targetScale: CGFloat = (pressed == index) ? 1.15 : 1.0
            if abs(icon.transform.a - targetScale) > 0.001 {
                UIView.animate(
                    withDuration: 0.4,
                    delay: 0.0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.0,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: {
                        icon.transform = targetScale == 1.0
                            ? .identity
                            : CGAffineTransform(scaleX: targetScale, y: targetScale)
                    },
                    completion: nil
                )
            }
        }
    }
}

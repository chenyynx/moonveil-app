// LiquidLensView.swift — [TG-LENS-PORT 2026-09-30] 搬运自 Telegram-iOS
// submodules/TelegramUI/Components/LiquidLens/Sources/LiquidLensView.swift
// （GPLv2-or-later 声明；本仓 GPLv3 衍生工程，合规与适配记录见 docs/tg-lens-port.md）。
// 适配记录（共 3 处，其余逐字搬运）：
//   ① import 收敛：删 Display/ComponentFlow/GlassBackgroundComponent（模块边界
//      消失；ComponentTransition/SharedDisplayLinkDriver 等已本地化）。
//   ② 删 <26 遗留 blob-mask 分支（init 的 else 支与 4 个属性；本集成 iOS 26+ 专用，
//      私有类取不到时优雅空转，兜底在上层 SwiftUI）。
//   ③ 删 update() 内 legacy 蒙版更新块（同 ②）。
//   ④ 追加 currentSelectionOriginXForHandoff 读取口（本仓「每树一栏 + 瞬切」架构
//      的跨树提交交接用；上游单栏架构无此需求。见 TGLensHost.CommitHandoff 注释）。
//   ⑤ [探针 2026-10-01 · v2 同日] updateLens/update 内 [LENS-LLV] 只读打点（lifted
//      同步态 / move 前后值 / displaylink 开关 / 卡死窗口排队 / 位置动画被清除），
//      全部带宿主注入实例号——「底栏点击硬落点」定位用；判读后随其它探针一并删除。
//   ⑥ [本仓适配 2026-10-01 · v4 退役] v3 的「沉降看门狗」**整块撤销**（含 updateLens
//      里的 shouldScheduleUpdate/一帧 flush）：看门狗是 removeAllAnimations 后快照
//      落位，装机日志两次 `[LENS-LLV] move … killed=true posAnim=false` 紧跟它出现
//      ——它正是 pp 装机「硬落点」的凶手之一。替代方案见 ⑧（就地收口 + 不杀在途）。
//   ⑦ [本仓适配 2026-10-01 · v4 · 拉伸] 追加 setLensStretch / animateLensStretchRelease：
//      把「飞行中的黏性拖尾」显式建模为透镜视图的横向 scale（锚在飞行方向的前缘）。
//      TG 侧无此入口——它的拉伸来自私有 _UILiquidLensView 随几何弹簧自形变
//      （TG TabBarComponent:868-887 逐帧算几何 → LiquidLensView:410-457 逐帧
//      setPosition/bounds + :450 无 key 的 additive 前缘钉位），本仓同一份代码照搬，
//      但私有形变不可观测、且在杀链下形变随弹簧被反复清零 → 观感退化成刚体滑动。
//      拉伸量公式取 TouchEffect.swift:229-231 的量级（拉伸饱和 ≈ 25~30% 额外宽度）。
//   ⑧ [本仓适配 2026-10-01 · v4 · 杀链] ①updateLens 的 lift 切换支路不再把位置
//      更新挂到私有 setLifted 的 alongside 回调（该回调对 T→F 恒迟到，最坏秒级；
//      上游在此等 alongside，本仓改为**就地**走「非抬升」那条同款收口，与 v3 看门狗
//      的目标序列逐行同源但不再杀任何在途动画）；②几何支路的 removeAllAnimations()
//      收窄为「只清 TG :450 那条无 key 的 additive 之外的键」——TG 写 removeAllAnimations
//      是为清 :450 那条 **forKey:nil** 的 additive 动画（CAAnimationUtils.swift:254/
//      371 对 additive 一律走 nil 键，无法按键移除），但它连同在途的 "position"
//      主弹簧一起清掉 = 装机日志 killed=true 的直接来源。现改为按键排除法。
//      除本块外 updateLens 与 TG 逐字一致。
// 内容：TG 液态透镜的本体——iOS 26 走苹果私有 _UILiquidLensView（运行时反射），
// 驱动 resting 背景/lifted 容器/内容穿透（punchout）与升起弹跳。⚠️ 私有 API，
// 与 TG App Store 版同款用法；见 docs/ 风险记录。
import Foundation
import UIKit

private final class RestingBackgroundView: UIVisualEffectView {
    var isDark: Bool?

    static func colorMatrix(isDark: Bool) -> [Float32] {
        if isDark {
            return [1.082, -0.113, -0.011, 0.0, 0.135, -0.034, 1.003, -0.011, 0.0, 0.135, -0.034, -0.113, 1.105, 0.0, 0.135, 0.0, 0.0, 0.0, 1.0, 0.0]
        } else {
            return [1.185, -0.05, -0.005, 0.0, -0.2, -0.015, 1.15, -0.005, 0.0, -0.2, -0.015, -0.05, 1.195, 0.0, -0.2, 0.0, 0.0, 0.0, 1.0, 0.0]
        }
    }

    init() {
        let effect = UIBlurEffect(style: .light)
        super.init(effect: effect)
        
        for subview in self.subviews {
            if subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        
        self.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isDark: Bool) {
        if self.isDark == isDark {
            return
        }
        self.isDark = isDark
        
        if let sublayer = self.layer.sublayers?[0], let _ = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            
            if let classValue = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol {
                let makeSelector = NSSelectorFromString("filterWithName:")
                let filter = classValue.perform(makeSelector, with: "colorMatrix").takeUnretainedValue() as? NSObject
                
                if let filter {
                    var matrix: [Float32] = RestingBackgroundView.colorMatrix(isDark: isDark)
                    filter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: "inputColorMatrix")
                    sublayer.filters = [filter]
                    sublayer.setValue(1.0, forKey: "scale")
                }
            }
        }
    }
}

public final class LiquidLensView: UIView {
    public final class TransitionInfo {
        public let disableAnimationWorkarounds: Bool
        
        public init(disableAnimationWorkarounds: Bool) {
            self.disableAnimationWorkarounds = disableAnimationWorkarounds
        }
    }
    
    public enum Kind {
        case externalContainer
        case builtinContainer
        case noContainer
    }
    
    private struct Params: Equatable {
        var size: CGSize
        var cornerRadius: CGFloat?
        var selectionOrigin: CGPoint
        var selectionSize: CGSize
        var inset: CGFloat
        var liftedInset: CGFloat
        var isDark: Bool
        var isLifted: Bool
        var isCollapsed: Bool

        init(size: CGSize, cornerRadius: CGFloat?, selectionOrigin: CGPoint, selectionSize: CGSize, inset: CGFloat, liftedInset: CGFloat, isDark: Bool, isLifted: Bool, isCollapsed: Bool) {
            self.size = size
            self.cornerRadius = cornerRadius
            self.selectionOrigin = selectionOrigin
            self.selectionSize = selectionSize
            self.inset = inset
            self.liftedInset = liftedInset
            self.isLifted = isLifted
            self.isDark = isDark
            self.isCollapsed = isCollapsed
        }
    }

    private struct LensParams: Equatable {
        var baseFrame: CGRect
        var inset: CGFloat
        var liftedInset: CGFloat
        var isLifted: Bool

        init(baseFrame: CGRect, inset: CGFloat, liftedInset: CGFloat, isLifted: Bool) {
            self.baseFrame = baseFrame
            self.inset = inset
            self.liftedInset = liftedInset
            self.isLifted = isLifted
        }
    }

    private let containerView: UIView
    private let backgroundContainer: GlassBackgroundContainerView?
    private let genericBackgroundContainer: UIView?
    private let backgroundView: GlassBackgroundView?
    private var lensView: UIView?
    private let liftedContainerView: UIView
    public let contentView: UIView
    private let restingBackgroundView: RestingBackgroundView
    
    // [TG-LENS-PORT 适配] 原 4 个 legacy blob-mask 属性随 <26 分支一并移除
    // （legacySelectionView / legacyContentMaskView / legacyContentMaskBlobView /
    //  legacyLiftedContentBlobMaskView）。

    public var selectedContentView: UIView {
        return self.liftedContainerView
    }

    private var params: Params?
    private var appliedLensParams: LensParams?
    private var isApplyingLensParams: Bool = false
    private var pendingLensParams: LensParams?

    private var liftedDisplayLink: SharedDisplayLinkDriver.Link?

    /// [探针 v2 2026-10-01] 宿主（TGLensHost）注入的实例编号——岛会被反复重建，
    /// 日志无身份时无法把事件归到具体实例（上一轮判读的教训）。纯日志，无行为；
    /// 判读后随批删。
    var instanceTag: String = ""

    /// [探针 v4 2026-10-01] 上一次记录过的拉伸系数（仅用于 [LENS-GEO] 的降噪阈值判定；
    /// 判读后随批删）。1.0 = 无拉伸。
    private var lastStretchProbe: CGFloat = 1.0

    public var selectionOrigin: CGPoint? {
        return self.params?.selectionOrigin
    }

    public var selectionSize: CGSize? {
        return self.params?.selectionSize
    }

    /// [TG-LENS-PORT 本仓适配 ④] 提交交接读取：透镜当前**可见**位置换算回选中
    /// 坐标系 x（selectionOrigin 空间）。presentation 优先——按下弹簧在途时屏上
    /// 真实位置 ≠ 模型位置；无在途动画则退回模型。仅供 TGLensHost 跨树交接。
    public var currentSelectionOriginXForHandoff: CGFloat? {
        guard let lensView = self.lensView, let params = self.appliedLensParams else {
            return nil
        }
        let centerX = lensView.layer.presentation()?.position.x ?? lensView.center.x
        return centerX - params.baseFrame.width * 0.5
    }
    
    public private(set) var isAnimating: Bool = false {
        didSet {
            if self.isAnimating != oldValue {
                self.onUpdatedIsAnimating?(self.isAnimating)
            }
        }
    }
    public var onUpdatedIsAnimating: ((Bool) -> Void)?
    public var isLiftedAnimationCompleted: (() -> Void)?

    public init(kind: Kind) {
        self.containerView = UIView()
        
        switch kind {
        case .builtinContainer:
            self.backgroundContainer = GlassBackgroundContainerView()
            self.genericBackgroundContainer = nil
        case .externalContainer, .noContainer:
            self.backgroundContainer = nil
            self.genericBackgroundContainer = UIView()
        }
        
        if case .noContainer = kind {
            self.backgroundView = nil
        } else {
            self.backgroundView = GlassBackgroundView()
        }
        
        self.contentView = UIView()
        self.liftedContainerView = UIView()

        self.restingBackgroundView = RestingBackgroundView()

        super.init(frame: CGRect())
        
        if let backgroundContainer = self.backgroundContainer {
            self.addSubview(backgroundContainer)
            if let backgroundView = self.backgroundView {
                backgroundContainer.contentView.addSubview(backgroundView)
                backgroundView.contentView.addSubview(self.containerView)
            }
        } else if let genericBackgroundContainer = self.genericBackgroundContainer {
            self.addSubview(genericBackgroundContainer)
            if let backgroundView = self.backgroundView {
                genericBackgroundContainer.addSubview(backgroundView)
                backgroundView.contentView.addSubview(self.containerView)
            } else {
                genericBackgroundContainer.addSubview(self.containerView)
            }
        }
        self.containerView.isUserInteractionEnabled = false
        
        if #available(iOS 26.0, *) {
            if let viewClass = NSClassFromString("_UILiquidLensView") as AnyObject as? NSObjectProtocol {
                let allocSelector = NSSelectorFromString("alloc")
                let initSelector = NSSelectorFromString("initWithRestingBackground:")
                let objcAlloc = viewClass.perform(allocSelector).takeUnretainedValue()
                let instance = objcAlloc.perform(initSelector, with: UIView()).takeUnretainedValue()
                self.lensView = instance as? UIView
            }
        }
        
        if let lensView = self.lensView {
            if let backgroundContainer = self.backgroundContainer {
                backgroundContainer.layer.zPosition = 1
            } else if let genericBackgroundContainer = self.genericBackgroundContainer{
                genericBackgroundContainer.layer.zPosition = 1
            }
            lensView.layer.zPosition = 10.0
            
            self.liftedContainerView.addSubview(self.restingBackgroundView)
            
            self.containerView.addSubview(self.liftedContainerView)
            self.containerView.addSubview(lensView)
            self.containerView.addSubview(self.contentView)
            
            if let backgroundContainer = self.backgroundContainer {
                lensView.perform(NSSelectorFromString("setLiftedContainerView:"), with: backgroundContainer.contentView)
            } else if let genericBackgroundContainer = self.genericBackgroundContainer {
                lensView.perform(NSSelectorFromString("setLiftedContainerView:"), with: genericBackgroundContainer)
            }
            lensView.perform(NSSelectorFromString("setLiftedContentView:"), with: self.liftedContainerView)
            lensView.perform(NSSelectorFromString("setOverridePunchoutView:"), with: self.contentView)
            
            do {
                let selector = NSSelectorFromString("setLiftedContentMode:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setStyle:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setWarpsContentBelow:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, true)
                }
            }
            
            lensView.setValue(UIColor(white: 0.0, alpha: 0.1), forKey: "restingBackgroundColor")
        }
        // [TG-LENS-PORT 适配] <26 遗留蒙版分支（blob mask 族）未随批移植——本集成
        // iOS 26+ 专用；且 _UILiquidLensView 取不到时 lensView=nil 即空转优雅退场，
        // 视觉兜底由上层 SwiftUI（ModeTabBar 的玻璃版）承担。
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setLiftedContainer(view: UIView) {
        guard let lensView = self.lensView else {
            return
        }
        lensView.perform(NSSelectorFromString("setLiftedContainerView:"), with: view)
    }

    // MARK: - [本仓适配 ⑦] 透镜拉伸（TG 观感的显式化）

    /// 拉伸动画键（与 TG 的位置动画互不相干：TG 全程不碰 lensView.transform，
    /// 已逐行核对上游 LiquidLensView 无任何 transform 写入）。
    private static let lensStretchAnimationKey = "tg-lens-stretch"

    /// 横向缩放 + 前缘钉位的仿射矩阵。锚在半宽处：m41 = ±(w/2)*(s−1)，
    /// 令 锚点 经变换后原地不动（推导见方法注释；显式写分量而非链式
    /// CATransform3DScale/Translate，规避本仓 Swift 6.0.3 求解器病理）。
    private func lensStretchTransform(scaleX: CGFloat, referenceWidth: CGFloat, leadingIsAnchor: Bool) -> CATransform3D {
        var transform = CATransform3DIdentity
        let s = max(1.0, scaleX)
        transform.m11 = s
        let halfWidth = max(0.0, referenceWidth) * 0.5
        // 飞行方向为 +x（向右）时「前缘」= 左缘 → 锚左缘，m41 取正。
        transform.m41 = (leadingIsAnchor ? halfWidth : -halfWidth) * (s - 1.0)
        return transform
    }

    /// [本仓适配 ⑦] 即时拉伸（拖拽跟手帧用；TG 侧无对应入口——TG 拖拽只跟手不拉伸，
    /// 见头注 ⑦ 的取真值结论）。scaleX ≤ 1 视为归位（identity）。
    /// - Parameters:
    ///   - scaleX: 横向拉伸系数（1 = 不拉伸）。
    ///   - leadingIsAnchor: 锚在飞行方向的前缘（向右飞 → true）。
    public func setLensStretch(scaleX: CGFloat, leadingIsAnchor: Bool) {
        guard let lensView = self.lensView else {
            return
        }
        lensView.layer.removeAnimation(forKey: Self.lensStretchAnimationKey)
        let referenceWidth = lensView.bounds.width
        if scaleX <= 1.0001 {
            lensView.transform = CATransform3DIdentity
            return
        }
        lensView.transform = self.lensStretchTransform(
            scaleX: scaleX, referenceWidth: referenceWidth, leadingIsAnchor: leadingIsAnchor
        )
        // [探针 v4 2026-10-01] 拉伸只在「形变量真的动了」时打点（拖拽逐帧不刷屏）。
        // 同时回读 model transform 的 m11——若它与 sx 不等，说明私有渲染器自己也在
        // 写 transform 把我们的拉伸吃掉了（装机日志一眼可判，勿凭观感猜）。
        let previous = self.lastStretchProbe
        if abs(previous - scaleX) > 0.05 {
            self.lastStretchProbe = scaleX
            NavTrace.log("[LENS-GEO\(self.instanceTag)] w=\(String(format: "%.1f", referenceWidth)) sx=\(String(format: "%.3f", scaleX)) m11=\(String(format: "%.3f", lensView.transform.m11))")
        }
    }

    /// [本仓适配 ⑦] 拉伸回弹：一次 CAAnimation 把 scaleX 衰减回 1。
    /// 曲线/时长与位置动画**同款**（TG 的 `.spring(duration: 0.4)` 在 iOS 26 落到
    /// CAAnimationUtils.makeAnimation 的 bezier(0.380, 0.700, 0.125, 1.000) 分支——
    /// 见 CAAnimationUtils.swift:210-227 与 Transition.swift:33-73 的 curve→timingFunction
    /// 映射；0.4 ≠ 0.3832 且 ≠ 0.5 故不进原生弹簧）——于是「拉伸量随剩余距离衰减」
    /// 是几何上的严格同相，而不是两条曲线各走各的近似。
    public func animateLensStretchRelease(fromScaleX: CGFloat, leadingIsAnchor: Bool, duration: Double) {
        guard let lensView = self.lensView else {
            return
        }
        guard fromScaleX > 1.0001, duration > 0.0 else {
            self.setLensStretch(scaleX: 1.0, leadingIsAnchor: leadingIsAnchor)
            return
        }
        let referenceWidth = lensView.bounds.width
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: self.lensStretchTransform(
            scaleX: fromScaleX, referenceWidth: referenceWidth, leadingIsAnchor: leadingIsAnchor
        ))
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.380, 0.700, 0.125, 1.000)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = true
        // 模型层即刻归位：拉伸是「只在飞行途中存在」的观感，落位必须回到恒等变换，
        // 否则下一次 setBounds/命中计算会被 model transform 污染。
        lensView.transform = CATransform3DIdentity
        lensView.layer.add(animation, forKey: Self.lensStretchAnimationKey)
        // [探针 v4 2026-10-01] 每次回弹一条（每手势 ≤ 1 条，噪声可控）。
        NavTrace.log("[LENS-GEO\(self.instanceTag)] w=\(String(format: "%.1f", referenceWidth)) sx=\(String(format: "%.3f", fromScaleX)) → 1.000")
    }

    public func update(size: CGSize, cornerRadius: CGFloat? = nil, selectionOrigin: CGPoint, selectionSize: CGSize, inset: CGFloat, liftedInset: CGFloat = 4.0, isDark: Bool, isLifted: Bool, isCollapsed: Bool = false, transition: ComponentTransition) {
        let params = Params(size: size, cornerRadius: cornerRadius, selectionOrigin: selectionOrigin, selectionSize: selectionSize, inset: inset, liftedInset: liftedInset, isDark: isDark, isLifted: isLifted, isCollapsed: isCollapsed)
        if self.params == params {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func update(transition: ComponentTransition) {
        guard let params = self.params else {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func updateLens(params: LensParams, transition: ComponentTransition) {
        guard let lensView = self.lensView else {
            return
        }

        if self.isApplyingLensParams {
            // [本仓适配 ⑥ 退役后的残留保险] v3 的看门狗撤销后，本分支在正常路径下
            // 永不再命中（isApplyingLensParams 只在本次调用内存活，见下方两处复位）。
            // 保留 TG 原样的排队语义作为兜底，日志留给判读（应为 0 次）。
            NavTrace.log("[LENS-LLV\(instanceTag)] queued (stall window)")
            self.pendingLensParams = params
            return
        }
        self.isApplyingLensParams = true
        let previousParams = self.appliedLensParams
        self.appliedLensParams = params

        if previousParams?.isLifted != params.isLifted {
            self.isAnimating = true

            let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
            var didProcessUpdate = false
            self.pendingLensParams = params
            if let method = lensView.method(for: selector) {
                typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, (() -> Void)?) -> Void
                let function = unsafeBitCast(method, to: ObjCMethod.self)
                function(lensView, selector, params.isLifted, !transition.animation.isImmediate, {
                    // TG 原位（:353-354）：alongside 块只负责把抬起后的 bounds 落位。
                    let liftedInset: CGFloat = params.isLifted ? params.liftedInset : (-params.inset)
                    lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                    didProcessUpdate = true
                }, { [weak self] in
                    guard let self else {
                        return
                    }
                    if !self.isApplyingLensParams {
                        self.isAnimating = false
                    }
                    self.isLiftedAnimationCompleted?()
                })
            }
            if didProcessUpdate {
                // TG 原样（:376-381）：私有类同步收口 → center 走 UIView 弹簧。
                transition.animateView {
                    lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
                }
            } else {
                // [本仓适配 ⑧·① 2026-10-01 · v4] 上游此刻置 shouldScheduleUpdate，
                // 把整个几何收口挂在 alongside 回调之后的 DispatchQueue.main.async 上
                // —— 实测该回调对 T→F **恒迟到**（装机日志 44/44，最坏秒级），滑动
                // 整段搁浅；v3 的看门狗（同一 async，只是提前一帧）兜底时又会
                // removeAllAnimations 把在途主弹簧杀掉（装机日志两次
                // `move … killed=true posAnim=false` 紧跟 `watchdog-flush`）。
                // 现改为**就地**走「非抬升」那条同款收口（下方 applyLensGeometry：
                // bounds + setPosition + :450 的 additive 前缘钉位，逐行同源），
                // 不等 alongside、不杀任何在途动画。alongside 真迟到时它把同一组
                // bounds 再写一遍（幂等），completion 只负责 isAnimating 收尾。
                self.applyLensGeometry(params: params, transition: transition)
            }
            self.pendingLensParams = nil
            self.isApplyingLensParams = false
            // [探针 v4 2026-10-01] lifted 切换同步态 + 位置动画材料化（判读后可删；
            // 显式局部量，规避 Swift 6.0.3 求解器病理）。
            let probeFromLifted = previousParams?.isLifted == true
            let probeHasPosAnim = lensView.layer.animation(forKey: "position") != nil
            NavTrace.log("[LENS-LLV\(instanceTag)] lifted \(probeFromLifted ? "T" : "F")→\(params.isLifted ? "T" : "F") didSync=\(didProcessUpdate) posAnim=\(probeHasPosAnim)")
        } else {
            self.applyLensGeometry(params: params, transition: transition)
            self.isApplyingLensParams = false
        }
    }

    /// [本仓适配 ⑧·①] 「非抬升」几何收口（TG 原 :409-457 的整段，本仓抽成共用函数：
    /// 抬升切换支路的迟到兜底与常规移动支路走**完全同一套**收口序列）。
    private func applyLensGeometry(params: LensParams, transition: ComponentTransition) {
        guard let lensView = self.lensView else {
            return
        }
        let liftedInset: CGFloat = params.isLifted ? params.liftedInset : (-params.inset)
        let lensBounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
        let lensCenter = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
        // [探针 v4 2026-10-01] 移动前可见位置捕获（必须在 setPosition/清键之前；
        // 显式 if-let，规避 Swift 6.0.3 求解器病理）。
        let probePreviousPosition: CGPoint
        if lensView.layer.animation(forKey: "position") != nil, let presentation = lensView.layer.presentation() {
            probePreviousPosition = presentation.position
        } else {
            probePreviousPosition = lensView.layer.position
        }

        let previousBounds: CGRect = lensView.bounds
        transition.animateView {
            lensView.bounds = lensBounds
        }

        if let info = transition.userData(TransitionInfo.self), info.disableAnimationWorkarounds {
        } else {
            // [本仓适配 ⑧·② 2026-10-01 · v4] TG 原样是 `lensView.layer.removeAllAnimations()`
            // 再把 bounds 钉到终值（:431-436）。它的用意只有一条：清掉上一帧 :450 那条
            // **additive 位置动画**——而 TG 的 CALayer.animate 对 additive 一律
            // `add(_:forKey: nil)`（CAAnimationUtils.swift:254/371），无键、按键删不掉，
            // TG 才被迫 removeAllAnimations。代价是把在途的 "position" 主弹簧一起
            // 清掉 = 本仓装机实锤的「硬落点 / killed=true」。
            // 现改为按键排除法：**保留 "position" 与本仓的拉伸键**，其余（陈旧的
            // bounds/transform 等）照旧清掉。position 主弹簧由下方 setPosition 按
            // 在途 presentation 续接（Transition.swift:445-455），不会跳变。
            for key in lensView.layer.animationKeys() where key != "position" && key != Self.lensStretchAnimationKey {
                lensView.layer.removeAnimation(forKey: key)
            }
            lensView.bounds = lensBounds
        }

        if !transition.animation.isImmediate {
            self.isAnimating = true
        }
        transition.setPosition(view: lensView, position: lensCenter, completion: { [weak self] flag in
            guard let self, flag else {
                return
            }
            if !self.isApplyingLensParams {
                self.isAnimating = false
            }
        })
        // No idea why
        transition.animatePosition(layer: lensView.layer, from: CGPoint(x: (lensBounds.width - previousBounds.width) * 0.5, y: 0.0), to: CGPoint(), additive: true)
        // [探针 v4 2026-10-01] 位置移动前值→目标 + 动画材料化 + 杀链归档（判读后可删；
        // v4 目标：killed 恒 false）。
        let probePrevX = String(format: "%.1f", probePreviousPosition.x)
        let probeToX = String(format: "%.1f", lensCenter.x)
        let probePosAnim = lensView.layer.animation(forKey: "position") != nil
        NavTrace.log("[LENS-LLV\(instanceTag)] move prev=\(probePrevX) → \(probeToX) anim=\(!transition.animation.isImmediate) killed=false posAnim=\(probePosAnim)")
    }

    private func updateLiftedLensPosition() {
        // Without this, the lens won't update its bouncing animations unless it's being moved
        if self.isApplyingLensParams {
            return
        }
        guard let lensView = self.lensView else {
            return
        }
        guard let params = self.appliedLensParams else {
            return
        }
        lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
    }

    private func update(params: Params, transition: ComponentTransition) {
        let isFirstTime = self.params == nil
        let transition: ComponentTransition = isFirstTime ? .immediate : transition

        self.params = params

        transition.setFrame(view: self.containerView, frame: CGRect(origin: CGPoint(), size: params.size))

        if let backgroundContainer = self.backgroundContainer {
            transition.setFrame(view: backgroundContainer, frame: CGRect(origin: CGPoint(), size: params.size))
            backgroundContainer.update(size: params.size, isDark: params.isDark, transition: transition)
        } else if let genericBackgroundContainer = self.genericBackgroundContainer {
            transition.setFrame(view: genericBackgroundContainer, frame: CGRect(origin: CGPoint(), size: params.size))
        }
        
        if let backgroundView = self.backgroundView {
            transition.setFrame(view: backgroundView, frame: CGRect(origin: CGPoint(), size: params.size))
            backgroundView.update(size: params.size, cornerRadius: params.cornerRadius ?? (params.size.height * 0.5), isDark: params.isDark, tintColor: GlassBackgroundView.TintColor.init(kind: .panel), isInteractive: true, transition: transition)
        }
        
        if self.contentView.bounds.size != params.size {
            self.contentView.clipsToBounds = true
            transition.setFrame(view: self.contentView, frame: CGRect(origin: CGPoint(), size: params.size), completion: { [weak self] completed in
                guard let self, completed else {
                    return
                }
                self.contentView.clipsToBounds = false
            })
            transition.setCornerRadius(layer: self.contentView.layer, cornerRadius: params.cornerRadius ?? (params.size.height * 0.5))

            self.liftedContainerView.clipsToBounds = true
            transition.setFrame(view: self.liftedContainerView, frame: CGRect(origin: CGPoint(), size: params.size), completion: { [weak self] completed in
                guard let self, completed else {
                    return
                }
                self.liftedContainerView.clipsToBounds = false
            })
            transition.setCornerRadius(layer: self.liftedContainerView.layer, cornerRadius: params.cornerRadius ?? (params.size.height * 0.5))
        }

        
        let baseLensFrame = CGRect(origin: params.selectionOrigin, size: params.selectionSize)
        self.updateLens(params: LensParams(baseFrame: baseLensFrame, inset: params.inset, liftedInset: params.liftedInset, isLifted: params.isLifted), transition: transition)
        

        transition.setFrame(view: self.restingBackgroundView, frame: CGRect(origin: CGPoint(), size: params.size))
        self.restingBackgroundView.update(isDark: params.isDark)
        transition.setAlpha(view: self.restingBackgroundView, alpha: (params.isLifted || params.isCollapsed) ? 0.0 : 1.0)

        if params.isLifted {
            if self.liftedDisplayLink == nil {
                // [探针 2026-10-01] 弹跳驱动开关（按压路径生死；判读后可删）。
                NavTrace.log("[LENS-LLV\(instanceTag)] displaylink ON")
                self.liftedDisplayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.updateLiftedLensPosition()
                })
            }
        } else if let liftedDisplayLink = self.liftedDisplayLink {
            NavTrace.log("[LENS-LLV\(instanceTag)] displaylink OFF")
            self.liftedDisplayLink = nil
            liftedDisplayLink.invalidate()
        }
    }
}

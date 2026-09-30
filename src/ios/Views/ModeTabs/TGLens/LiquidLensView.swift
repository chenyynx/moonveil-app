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
//   ⑤ [探针 2026-10-01] updateLens/update 内追加 [LENS-LLV] 只读打点四处（lifted
//      切换同步态 / 位置移动前值→目标 / position 动画是否材料化 / displaylink 开关）
//      ——「底栏点击硬落点」定位用；判读后随其它探针一并删除。
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
            self.pendingLensParams = params
            return
        }
        self.isApplyingLensParams = true
        let previousParams = self.appliedLensParams
        self.appliedLensParams = params

        if previousParams?.isLifted != params.isLifted {
            self.isAnimating = true
            
            let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
            var shouldScheduleUpdate = false
            var didProcessUpdate = false
            self.pendingLensParams = params
            if let lensView = self.lensView, let method = lensView.method(for: selector) {
                typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, (() -> Void)?) -> Void
                let function = unsafeBitCast(method, to: ObjCMethod.self)
                function(lensView, selector, params.isLifted, !transition.animation.isImmediate, { [weak self] in
                    guard let self else {
                        return
                    }
                    let liftedInset: CGFloat = params.isLifted ? params.liftedInset : (-params.inset)
                    lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                    didProcessUpdate = true
                    if shouldScheduleUpdate {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, let pendingLensParams = self.pendingLensParams else {
                                return
                            }
                            self.isApplyingLensParams = false
                            self.pendingLensParams = nil
                            self.updateLens(params: pendingLensParams, transition: transition)
                        }
                    }
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
                transition.animateView {
                    lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
                }
                self.pendingLensParams = nil
                self.isApplyingLensParams = false
            } else {
                shouldScheduleUpdate = true
            }
            // [探针 2026-10-01] lifted 切换同步态 + 位置动画材料化（判读后可删；
            // 显式局部量，规避 Swift 6.0.3 求解器病理）。
            let probeFromLifted = previousParams?.isLifted == true
            let probeHasPosAnim = lensView.layer.animation(forKey: "position") != nil
            NavTrace.log("[LENS-LLV] lifted \(probeFromLifted ? "T" : "F")→\(params.isLifted ? "T" : "F") didSync=\(didProcessUpdate) posAnim=\(probeHasPosAnim)")
        } else {
            let liftedInset: CGFloat = params.isLifted ? params.liftedInset : (-params.inset)
            let lensBounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
            let lensCenter = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
            // [探针 2026-10-01] 移动前可见位置捕获（必须在 setPosition/
            // removeAllAnimations 之前；显式 if-let，规避 Swift 6.0.3 求解器病理）。
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
                lensView.layer.removeAllAnimations()
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
            // [探针 2026-10-01] 位置移动前值→目标 + 动画材料化（判读后可删）。
            let probePrevX = String(format: "%.1f", probePreviousPosition.x)
            let probeToX = String(format: "%.1f", lensCenter.x)
            let probePosAnim = lensView.layer.animation(forKey: "position") != nil
            NavTrace.log("[LENS-LLV] move prev=\(probePrevX) → \(probeToX) anim=\(!transition.animation.isImmediate) posAnim=\(probePosAnim)")

            self.isApplyingLensParams = false
        }
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
                NavTrace.log("[LENS-LLV] displaylink ON")
                self.liftedDisplayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.updateLiftedLensPosition()
                })
            }
        } else if let liftedDisplayLink = self.liftedDisplayLink {
            NavTrace.log("[LENS-LLV] displaylink OFF")
            self.liftedDisplayLink = nil
            liftedDisplayLink.invalidate()
        }
    }
}

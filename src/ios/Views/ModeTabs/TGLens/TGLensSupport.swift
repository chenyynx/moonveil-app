// TGLensSupport.swift — TG 透镜移植批次的支撑件（ObjC → Swift 转写）
//
// [TG-LENS-PORT 2026-09-30 pp 拍板「B：真·移植 TG」] 本文件是 TG 分散在若干
// ObjC/Swift 文件里的弹簧 / 滤镜 / 行为覆盖小件的**语义逐行转写**（非逐字搬运；
// 每个函数头注明出处行数）。出处（Telegram-iOS, GPLv2-or-later 声明，
// 本仓为其 GPLv3 衍生工程，合规声明见 docs/tg-lens-port.md）：
//   · submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIKitUtils.m
//       - animationDurationFactorImpl / makeSpring*Impl / springAnimationValueAtImpl /
//         CASpringAnimation(_solveForInput: 动态调用) / makeLuminanceToAlphaFilter /
//         setMonochromaticEffectImpl（及 Invocation 参数辅助）
//   · submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIViewController+Navigation.{h,m}
//       - CALayerSpringParametersOverride 族 / push/pop / CALayer.addAnimation swizzle
//       - EffectSettingsContainerView
//   · submodules/Display/Source/UIKitUtils.swift（Swift 包装层：makeSpringAnimation 等）
//   · submodules/Display/Source/ListViewAnimation.swift（springAnimationSolver + 曲线常量）
//   · submodules/Display/Source/DisplayUIKitUtils.swift（按需摘录：UIColor.mixedWith /
//     CALayer.layerTintColor / CALayer.blur——CI 第二轮补齐，行号见各定义处注释）
//
// 适配记录（全批次统一，见 docs/tg-lens-port.md）：
//   1. ObjC → Swift 转写；Bazel 模块边界消失（本仓单模块），import 全部去除。
//   2. UIKitRuntimeUtils 的 NSInvocation 辅助（setBoolField/setLongLongField）改为
//      method IMP 直调（语义等价）。
//   3. 私有 API 使用与 TG 一致（CAFilter / _solveForInput: / swizzle）。运行时缺失
//      一律安全降级（返回 nil / 保持原动画），永不让地基炸掉 UI。
//
// ⚠️ 本文件内 `CALayer.add(_:forKey:)` 是**全局 swizzle**（TG 原样行为）：仅当
//    push/pop 覆盖栈非空（= 仅本移植件的动画路径）时改变行为，栈空时完全透传。

import UIKit

// MARK: - animationDurationFactorImpl（UIKitUtils.m:11-16）

// [TG-LENS-PORT 适配] 上游此 @_silgen_name 声明在 Display / ComponentFlow 两模块
// 各有一份；单模块合并须去重——保留 Transition.swift 逐字搬运件中的声明，
// 本文件不再重复（模拟器构建下由 Transition.swift 提供，真机分支不使用）。

/// 模拟器下跟随 UIAnimationDragCoefficient，真机恒 1.0。
func animationDurationFactorImpl() -> Double {
    #if targetEnvironment(simulator)
    return Double(UIAnimationDragCoefficient())
    #else
    return 1.0
    #endif
}

// MARK: - CASpringAnimation 私有曲线求值（UIKitUtils.m:18-51）

/// TG 的 `CASpringAnimation (AnimationUtils).valueAt:` 转写：动态调用 UIKit 私有的
/// `_solveForInput:`（不改写它，只是取实现直调）；签名 float/double 双兼容。
extension CASpringAnimation {
    private static let solveImpls: (float: (@convention(c) (AnyObject, Selector, Float) -> Float)?, double: (@convention(c) (AnyObject, Selector, Double) -> Double)?) = {
        guard let method = class_getInstanceMethod(CASpringAnimation.self, NSSelectorFromString("_" + "solveForInput:")) else {
            return (nil, nil)
        }
        // 实参类型判定：上游 ObjC 用 NSMethodSignature（Swift 不可用——NSInvocation
        // 家族在 SDK 里被显式屏蔽），语义等价改用 objc/runtime 的
        // method_getArgumentType 读第 3 个实参（index 2，前两个是 self/_cmd）的
        // 类型字符：'f' = float、'd' = double。
        var argType: [CChar] = [0, 0, 0, 0, 0, 0, 0, 0]
        method_getArgumentType(method, 2, &argType, argType.count)
        // 该 API 无返回值（void——SDK 头文件逐字核对）；index 越界时 dst 被填
        // 空串（argType[0] == 0），与 'f'/'d' 均不匹配，自然落穿到 (nil, nil)。
        let imp: IMP = method_getImplementation(method)
        let typeChar = UInt8(bitPattern: argType[0])
        // ⚠️ 必须是 @convention(c)（瘦函数指针，8B）；漏标注会得到 16B 厚函数值，
        // unsafeBitCast 运行时尺寸检查直接 fatal（对抗复审 2026-09-30 阻断项①）。
        if typeChar == UInt8(ascii: "f") {
            return (unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector, Float) -> Float).self), nil)
        } else if typeChar == UInt8(ascii: "d") {
            return (nil, unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector, Double) -> Double).self))
        }
        return (nil, nil)
    }()

    /// valueAt: 等价物（UIKitUtils.m:24-49）。
    func tgValueAt(_ t: CGFloat) -> CGFloat {
        let sel = NSSelectorFromString("_" + "solveForInput:")
        let impls = CASpringAnimation.solveImpls
        if let impl = impls.float {
            return CGFloat(impl(self, sel, Float(t)))
        } else if let impl = impls.double {
            return CGFloat(impl(self, sel, Double(t)))
        }
        return t
    }
}

// MARK: - 弹簧动画构造（UIKitUtils.m:53-108）

/// makeSpringAnimationImpl（UIKitUtils.m:53-66）：iOS 26 走 26 版曲线。
/// 参数位置式（对齐 ObjC 原版 `makeSpringAnimationImpl(keyPath, duration)`，
/// CAAnimationUtils.swift 逐字搬运件按位置调用）。
func makeSpringAnimationImpl(_ keyPath: String, _ duration: Double) -> CABasicAnimation {
    if #available(iOS 26.0, *) {
        return make26SpringAnimationImpl(keyPath, duration)
    }
    let springAnimation = CASpringAnimation(keyPath: keyPath)
    springAnimation.mass = 3.0
    springAnimation.stiffness = 1000.0
    springAnimation.damping = 500.0
    springAnimation.duration = 0.5
    springAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
    return springAnimation
}

/// make26SpringAnimationImpl（UIKitUtils.m:68-84）：iOS 26 的原生手感弹簧参数。
/// 参数位置式（对齐 ObjC 原版；CAAnimationUtils.swift:127 按位置调用）。
func make26SpringAnimationImpl(_ keyPath: String, _ duration: Double) -> CABasicAnimation {
    let springAnimation = CASpringAnimation(keyPath: keyPath)
    springAnimation.mass = 1.0
    springAnimation.stiffness = 555.027
    springAnimation.damping = 47.118
    springAnimation.duration = duration
    springAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
    if #available(iOS 17.0, *) {
        springAnimation.allowsOverdamping = false
    }
    if #available(iOS 15.0, *) {
        springAnimation.setValue(1048619, forKey: "highFrameRateReason")
        springAnimation.preferredFrameRateRange = CAFrameRateRange(minimum: 80.0, maximum: 120.0, preferred: 120.0)
    }
    return springAnimation
}

/// makeSpringBounceAnimationImpl（UIKitUtils.m:86-104）。
func makeSpringBounceAnimationImpl(_ keyPath: String, _ initialVelocity: CGFloat, _ damping: CGFloat) -> CASpringAnimation {
    let springAnimation = CASpringAnimation(keyPath: keyPath)
    springAnimation.mass = 5.0
    springAnimation.stiffness = 900.0
    springAnimation.damping = damping
    if #available(iOS 9.0, *) {
        springAnimation.initialVelocity = initialVelocity
        springAnimation.duration = springAnimation.settlingDuration
    } else {
        springAnimation.duration = 0.1
    }
    springAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
    return springAnimation
}

/// springAnimationValueAtImpl（UIKitUtils.m:106-108）。
func springAnimationValueAtImpl(_ animation: CABasicAnimation, _ t: CGFloat) -> CGFloat {
    return (animation as? CASpringAnimation)?.tgValueAt(t) ?? t
}

// MARK: - Swift 包装层（Display/Source/UIKitUtils.swift:5-20）

func makeSpringAnimation(_ keyPath: String, duration: Double) -> CABasicAnimation {
    return makeSpringAnimationImpl(keyPath, duration)
}

func makeSpringBounceAnimation(_ keyPath: String, _ initialVelocity: CGFloat, _ damping: CGFloat) -> CASpringAnimation {
    return makeSpringBounceAnimationImpl(keyPath, initialVelocity, damping)
}

func springAnimationValueAt(_ animation: CABasicAnimation, _ t: CGFloat) -> CGFloat {
    return springAnimationValueAtImpl(animation, t)
}

// MARK: - 系统曲线弹簧求解器（Display/Source/ListViewAnimation.swift:90-123）

/// 0.5s 弹簧动画的采样器（springAnimationSolver）。
let springAnimationSolver: (CGFloat) -> CGFloat = {
    let springAnimationIn = makeSpringAnimation("", duration: 0.5)
    return { t in
        return springAnimationValueAt(springAnimationIn, t)
    }
}()

let listViewAnimationCurveSystem: (CGFloat) -> CGFloat = { t in
    return springAnimationSolver(t)
}

let listViewAnimationCurveLinear: (CGFloat) -> CGFloat = { t in
    return t
}

let listViewAnimationCurveEaseInOut: (CGFloat) -> CGFloat = { t in
    return bezierPoint(0.42, 0.0, 0.58, 1.0, t)
}

let listViewAnimationCurveEaseIn: (CGFloat) -> CGFloat = { t in
    return bezierPoint(0.42, 0.0, 1.0, 1.0, t)
}

// MARK: - CAFilter 滤镜（UIKitUtils.m:259-295）

/// CAFilter 运行时工厂（UIKitUtils.m 的 GraphicsFilterProtocol 直译）。
private func makeGraphicsFilter(_ name: String) -> NSObject? {
    guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol else {
        return nil
    }
    let selector = NSSelectorFromString("filterWithName:")
    guard filterClass.responds(to: selector) else {
        return nil
    }
    return filterClass.perform(selector, with: name)?.takeUnretainedValue() as? NSObject
}

extension CALayer {
    /// CALayer.luminanceToAlpha()（Display/Source/UIKitUtils.swift:899 → UIKitUtils.m:273）。
    static func luminanceToAlpha() -> NSObject? {
        return makeGraphicsFilter("luminanceToAlpha")
    }

    /// CALayer.blur()（Display/Source/DisplayUIKitUtils.swift:891 → UIKitUtils.m:265）：
    /// gaussianBlur 滤镜（Transition.swift 毛玻璃过渡 animateBlur 使用；
    /// inputRadius 经 setValue KVC 配置，与 TG 同款 CAFilter 用法）。
    static func blur() -> NSObject? {
        return makeGraphicsFilter("gaussianBlur")
    }
}

// MARK: - UIColor 混色（Display/Source/DisplayUIKitUtils.swift:308，按需摘录）

extension UIColor {
    /// UIColor.mixedWith(_:alpha:)（DisplayUIKitUtils.swift:308-331，逐字语义转写）：
    /// 按 alpha 线性混合两色；任一色取不出 RGBA（如解析态动态色）时原样返回 self（上游行为）。
    func mixedWith(_ other: UIColor, alpha: CGFloat) -> UIColor {
        let alpha = min(1.0, max(0.0, alpha))
        let oneMinusAlpha = 1.0 - alpha

        var r1: CGFloat = 0.0
        var r2: CGFloat = 0.0
        var g1: CGFloat = 0.0
        var g2: CGFloat = 0.0
        var b1: CGFloat = 0.0
        var b2: CGFloat = 0.0
        var a1: CGFloat = 0.0
        var a2: CGFloat = 0.0
        if self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) &&
            other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        {
            let r = r1 * oneMinusAlpha + r2 * alpha
            let g = g1 * oneMinusAlpha + g2 * alpha
            let b = b1 * oneMinusAlpha + b2 * alpha
            let a = a1 * oneMinusAlpha + a2 * alpha
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
        return self
    }
}

// MARK: - CALayer 着色（Display/Source/DisplayUIKitUtils.swift:921，按需摘录）

extension CALayer {
    /// CALayer.layerTintColor（DisplayUIKitUtils.swift:921-933，判型/取值逐字）：
    /// KVC 私有键 contentsMultiplyColor（CGColor）——Transition.swift 的 tint 过渡使用。
    /// 注意：Any→CF 的条件降转（`is CGColor` / `as? CGColor`）在 Swift 6 是错误
    /// （"conditional downcast to CoreFoundation type will always succeed"，CI 三轮
    /// 实报），必须照上游用 CFGetTypeID 判型 + 强桥接取值。键缺失时 KVC 抛异常——
    /// 与 TG 上游同款暴露。
    var layerTintColor: CGColor? {
        get {
            if let value = self.value(forKey: "contentsMultiplyColor"), CFGetTypeID(value as CFTypeRef) == CGColor.typeID {
                return value as! CGColor
            }
            return nil
        }
        set {
            self.setValue(newValue, forKey: "contentsMultiplyColor")
        }
    }
}

// MARK: - 单色化（UIKitUtils.m:355-377 + DisplayUIKitUtils.swift:990-1012）

/// iOS 26 私有单色处理字段（名称分段拼接 = TG 原样，规避静态扫描）。
func setMonochromaticEffectImpl(_ view: UIView, _ isEnabled: Bool) {
    if #available(iOS 26.0, *) {
        let key1 = "_setAllows" + "MonochromaticTreatment:"
        let key2 = "_setEnable" + "MonochromaticTreatment:"
        let key3 = "_set" + "MonochromaticTreatment:"
        if isEnabled {
            tgCallSelectorBool(view, key1, true)
            tgCallSelectorBool(view, key2, true)
            tgCallSelectorLongLong(view, key3, 2)
        } else {
            tgCallSelectorBool(view, key1, false)
            tgCallSelectorBool(view, key2, false)
            tgCallSelectorLongLong(view, key3, 0)
        }
    }
}

/// NSInvocation-式字段写入的 Swift 直调（对应 UIKitUtils.m 的 setBoolField/setLongLongField）。
private func tgCallSelectorBool(_ object: NSObject, _ name: String, _ value: Bool) {
    let selector = NSSelectorFromString(name)
    guard object.responds(to: selector), let method = object.method(for: selector) else {
        return
    }
    typealias Impl = @convention(c) (AnyObject, Selector, Bool) -> Void
    unsafeBitCast(method, to: Impl.self)(object, selector, value)
}

private func tgCallSelectorLongLong(_ object: NSObject, _ name: String, _ value: Int64) {
    let selector = NSSelectorFromString(name)
    guard object.responds(to: selector), let method = object.method(for: selector) else {
        return
    }
    typealias Impl = @convention(c) (AnyObject, Selector, Int64) -> Void
    unsafeBitCast(method, to: Impl.self)(object, selector, value)
}

extension UIView {
    /// setMonochromaticEffect(tintColor:)（DisplayUIKitUtils.swift:990-1012）。
    func setMonochromaticEffect(tintColor: UIColor?) {
        var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 1.0
        if let tintColor {
            if tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                if red == 0.0 && green == 0.0 && blue == 0.0 && alpha == 1.0 {
                    overrideUserInterfaceStyle = .light
                }
            } else {
                if red == 1.0 && green == 1.0 && blue == 1.0 && alpha == 1.0 {
                    overrideUserInterfaceStyle = .dark
                }
            }
        }

        if self.overrideUserInterfaceStyle != overrideUserInterfaceStyle {
            self.overrideUserInterfaceStyle = overrideUserInterfaceStyle
            setMonochromaticEffectImpl(self, overrideUserInterfaceStyle != .unspecified)
        }
    }
}

// MARK: - generateImage（Display/Source/GenerateImage.swift:102-127 的等价转写）

/// TG 原版走 Display 的 DrawingContext（字节级 CGContext 封装，`withContext` =
/// 未翻转的原始 CG 坐标系）；此处用 UIGraphicsImageRenderer（cgContext 为 UIKit
/// 翻转系）**手动翻回 y-up** 后转交，保证与 TG 的 rotatedContext 朝向一致
/// （对抗复审 2026-09-30 中项⑤）。仅 <26 遗留绘制路径调用（本集成 iOS 26+ 恒
/// 不可达；语义对齐以防未来有人打开 useCustomGlassImpl）。
func generateImage(_ size: CGSize, opaque: Bool = false, scale: CGFloat? = nil, rotatedContext: (CGSize, CGContext) -> Void) -> UIImage? {
    if size.width.isZero || size.height.isZero {
        return nil
    }
    let format = UIGraphicsImageRendererFormat()
    format.opaque = opaque
    if let scale = scale, scale != 0.0 {
        format.scale = scale
    }
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { ctx in
        let cg = ctx.cgContext
        cg.translateBy(x: 0.0, y: size.height)
        cg.scaleBy(x: 1.0, y: -1.0)
        rotatedContext(size, cg)
    }
}

// MARK: - EffectSettingsContainerView（VC+Nav.h:102 / .m:908-918）

/// 亮度范围控制容器（iOS 26+ 玻璃用途；luma 消费 swizzle 属 TG 全局性能件，
/// 未随本批移植——属性为下游兼容保留，默认 0/0 时无行为）。
final class EffectSettingsContainerView: UIView {
    var lumaMin: Double = 0.0
    var lumaMax: Double = 0.0
}

// MARK: - Spring 参数覆盖族（VC+Nav.h:30-100 / .m:117-186）

class CALayerSpringParametersOverrideParameters: NSObject {
}

final class CALayerSpringParametersOverrideParametersSpring: CALayerSpringParametersOverrideParameters {
    let stiffness: CGFloat
    let damping: CGFloat
    let duration: Double

    init(stiffness: CGFloat, damping: CGFloat, duration: Double) {
        self.stiffness = stiffness
        self.damping = damping
        self.duration = duration
        super.init()
    }
}

final class CALayerSpringParametersOverrideParametersCustomCurve: CALayerSpringParametersOverrideParameters {
    let cp1: CGPoint
    let cp2: CGPoint

    init(cp1: CGPoint, cp2: CGPoint) {
        self.cp1 = cp1
        self.cp2 = cp2
        super.init()
    }
}

final class CALayerSpringParametersOverride: NSObject {
    let parameters: CALayerSpringParametersOverrideParameters?

    init(parameters: CALayerSpringParametersOverrideParameters?) {
        self.parameters = parameters
        super.init()
    }
}

/// 覆盖栈（VC+Nav.m:174-183）。主线程语义（TG 原样，不做锁）。
private var currentSpringParametersOverrideStack: [CALayerSpringParametersOverride] = []

extension CALayer {
    /// pushSpringParametersOverride（VC+Nav.m:186-190）。
    static func push(_ springParametersOverride: CALayerSpringParametersOverride) {
        currentSpringParametersOverrideStack.append(springParametersOverride)
    }

    /// popSpringParametersOverride（VC+Nav.m:192-196）。
    static func popSpringParametersOverride() {
        if !currentSpringParametersOverrideStack.isEmpty {
            currentSpringParametersOverrideStack.removeLast()
        }
    }

    // MARK: addAnimation swizzle（VC+Nav.m:191-287，逐行对应）

    /// 原 `-addAnimation:forKey:` 的实现体（swizzle 后由 ObjC runtime 指向这里）。
    @objc fileprivate dynamic func tgLens_swizzled_addAnimation(_ anim: CAAnimation, forKey key: String?) {
        var updatedAnimation: CAAnimation = anim
        if !currentSpringParametersOverrideStack.isEmpty, let springAnim = anim as? CASpringAnimation {
            let overrideData = currentSpringParametersOverrideStack.last!
            if let parameters = overrideData.parameters as? CALayerSpringParametersOverrideParametersSpring {
                let animation = makeSpringBounceAnimationImpl(springAnim.keyPath ?? "", 0.0, parameters.damping)
                animation.stiffness = parameters.stiffness
                animation.fromValue = springAnim.fromValue
                animation.toValue = springAnim.toValue
                animation.byValue = springAnim.byValue
                animation.isAdditive = springAnim.isAdditive
                animation.isRemovedOnCompletion = springAnim.isRemovedOnCompletion
                animation.fillMode = springAnim.fillMode
                animation.beginTime = springAnim.beginTime
                animation.timeOffset = springAnim.timeOffset
                animation.repeatCount = springAnim.repeatCount
                animation.autoreverses = springAnim.autoreverses

                animation.speed = springAnim.speed * Float(animation.duration / parameters.duration)

                updatedAnimation = animation
            } else if let parameters = overrideData.parameters as? CALayerSpringParametersOverrideParametersCustomCurve {
                let animation = CABasicAnimation(keyPath: springAnim.keyPath)
                animation.fromValue = springAnim.fromValue
                animation.toValue = springAnim.toValue
                animation.byValue = springAnim.byValue
                animation.isAdditive = springAnim.isAdditive
                animation.duration = springAnim.duration
                animation.timingFunction = CAMediaTimingFunction(controlPoints: Float(parameters.cp1.x), Float(parameters.cp1.y), Float(parameters.cp2.x), Float(parameters.cp2.y))
                animation.isRemovedOnCompletion = springAnim.isRemovedOnCompletion
                animation.fillMode = springAnim.fillMode
                animation.speed = springAnim.speed
                animation.beginTime = springAnim.beginTime
                animation.timeOffset = springAnim.timeOffset
                animation.repeatCount = springAnim.repeatCount
                animation.autoreverses = springAnim.autoreverses

                var speed: Float = 1.0
                let k = Float(animationDurationFactorImpl())
                if k != 0.0 && k != 1.0 {
                    speed = 1.0 / k
                }
                animation.speed = speed * springAnim.speed

                updatedAnimation = animation
            } else {
                // 无参覆盖（.spring 曲线路径）：iOS 26 原生玻璃时长(0.3832)与标准 0.5
                // 时长原样放行，其余统一重定到 TG 贝塞尔(0.380,0.700,0.125,1.000)。
                var isNativeGlass = false
                if #available(iOS 26.0, *) {
                    isNativeGlass = true
                }
                if isNativeGlass && abs(springAnim.duration - 0.3832) <= 0.0001 {
                } else if abs(springAnim.duration - 0.5) <= 0.0001 {
                } else {
                    let animation = CABasicAnimation(keyPath: springAnim.keyPath)
                    animation.fromValue = springAnim.fromValue
                    animation.toValue = springAnim.toValue
                    animation.byValue = springAnim.byValue
                    animation.isAdditive = springAnim.isAdditive
                    animation.duration = springAnim.duration
                    animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.380, 0.700, 0.125, 1.000)
                    animation.isRemovedOnCompletion = springAnim.isRemovedOnCompletion
                    animation.fillMode = springAnim.fillMode
                    animation.speed = springAnim.speed
                    animation.beginTime = springAnim.beginTime
                    animation.timeOffset = springAnim.timeOffset
                    animation.repeatCount = springAnim.repeatCount
                    animation.autoreverses = springAnim.autoreverses

                    var speed: Float = 1.0
                    let k = Float(animationDurationFactorImpl())
                    if k != 0.0 && k != 1.0 {
                        speed = 1.0 / k
                    }
                    animation.speed = speed * springAnim.speed

                    updatedAnimation = animation
                }
            }
        }
        self.tgLens_swizzled_addAnimation(updatedAnimation, forKey: key)
    }
}

/// 安装 swizzle（VC+Nav.m:557 的等价物；幂等）。调用点 = 透镜岛首次创建。
private let installTGLensSwizzlesOnce: Void = {
    guard let original = class_getInstanceMethod(CALayer.self, NSSelectorFromString("addAnimation:forKey:")),
          let swizzled = class_getInstanceMethod(CALayer.self, NSSelectorFromString("tgLens_swizzled_addAnimation:forKey:")) else {
        return
    }
    method_exchangeImplementations(original, swizzled)
}()

func installTGLensSwizzlesIfNeeded() {
    _ = installTGLensSwizzlesOnce
}

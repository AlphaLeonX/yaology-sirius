import Foundation
import CoreGraphics
import AppKit

/// 负责精准驱动 MacBook 内建屏幕色彩（独占内建屏，绝不影响外接大屏）
/// 基于 macOS 原生 CoreGraphics Display LUT 硬件查找表，严格限定仅对内建显示器 (DisplayBridge.getBuiltinDisplayID()) 生效。
public final class ColorTemperatureEngine: @unchecked Sendable {
    public static let shared = ColorTemperatureEngine()

    private let queue = DispatchQueue(label: "com.yaology.sirius.color-engine", qos: .userInteractive)
    private let lock = NSLock()
    private var animationTimer: DispatchSourceTimer?

    // 缓存内建显示器基准原始 Gamma 表 (256 采样点)
    private var sampleCount: UInt32 = 0
    private var baselineRed: [CGGammaValue] = []
    private var baselineGreen: [CGGammaValue] = []
    private var baselineBlue: [CGGammaValue] = []

    // 当前渲染状态
    private(set) var isCurrentlyWarm: Bool = false
    private var currentWarmthProgress: Float = 0.0 // 0.0 (原生) ~ 1.0 (目标暖色)

    private init() {
        // 清理可能残留的系统级全局 Night Shift，确保外接大屏保持纯白自然色
        disableSystemWideNightShiftIfAny()

        // 捕获内建显示屏原生基准色彩表
        captureBaseline()
    }

    /// 确保关闭任何系统级全局 Night Shift（避免外置大屏受影响）
    private func disableSystemWideNightShiftIfAny() {
        Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework")?.load()
        if let clientClass = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
            let instance = clientClass.init()
            let sel = NSSelectorFromString("setEnabled:")
            if instance.responds(to: sel) {
                typealias SetEnabledFunc = @convention(c) (AnyObject, Selector, Bool) -> Bool
                let fn = unsafeBitCast(instance.method(for: sel), to: SetEnabledFunc.self)
                _ = fn(instance, sel, false)
            }
        }
    }

    /// 捕获并记录当前内建屏幕未被修改的原生色彩基准表
    public func captureBaseline() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let displayID = DisplayBridge.getBuiltinDisplayID() else { return }

            self.lock.lock()
            defer { self.lock.unlock() }

            if self.isCurrentlyWarm && !self.baselineRed.isEmpty {
                return
            }

            self.captureBaselineInternal(displayID: displayID)
        }
    }

    /// 计算给定色温（Kelvin）下的 RGB 衰减乘数
    /// 5500K 对应轻微温和 (R 1.0, G 1.0, B 0.80)；3200K 对应经典琥珀 (R 1.0, G 0.83, B 0.30)；2500K 对应极致烛光 (R 1.0, G 0.78, B 0.15)
    public static func multipliers(for kelvin: Double) -> (r: Float, g: Float, b: Float) {
        let clampedK = max(2500.0, min(5500.0, kelvin))
        let w = Float((5500.0 - clampedK) / 3000.0) // 0.0 (5500K) ~ 1.0 (2500K)
        let r: Float = 1.0
        let g: Float = 1.0 - 0.22 * w
        let b: Float = 0.80 - 0.65 * w
        return (r, g, b)
    }

    /// 实时预览色温（供设置面板滑块拖拽时即时响应，零延时无动画，仅作用于内建 Mac 屏）
    public func previewTemperature(kelvin: Double) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let displayID = DisplayBridge.getBuiltinDisplayID() else { return }

            self.lock.lock()
            self.animationTimer?.cancel()
            self.animationTimer = nil

            if self.baselineRed.isEmpty {
                self.captureBaselineInternal(displayID: displayID)
            }

            let (rMult, gMult, bMult) = Self.multipliers(for: kelvin)
            self.applyGammaMultipliers(displayID: displayID, rMult: rMult, gMult: gMult, bMult: bMult)

            self.isCurrentlyWarm = true
            self.currentWarmthProgress = 1.0
            self.lock.unlock()
        }
    }

    /// 平滑渐变至目标暖光色温（仅作用于内建 Mac 屏）
    public func transitionToWarm(kelvin: Double, duration: TimeInterval, completion: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let displayID = DisplayBridge.getBuiltinDisplayID() else {
                completion?()
                return
            }

            self.lock.lock()
            self.animationTimer?.cancel()
            self.animationTimer = nil

            if self.baselineRed.isEmpty {
                self.captureBaselineInternal(displayID: displayID)
            }

            let (targetR, targetG, targetB) = Self.multipliers(for: kelvin)
            let startProgress = self.currentWarmthProgress

            if duration <= 0.03 {
                self.applyGammaMultipliers(displayID: displayID, rMult: targetR, gMult: targetG, bMult: targetB)
                self.currentWarmthProgress = 1.0
                self.isCurrentlyWarm = true
                self.lock.unlock()
                completion?()
                return
            }

            let fps: Double = 60.0
            let totalSteps = max(1, Int(duration * fps))
            let interval = duration / Double(totalSteps)
            var currentStep = 0

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: interval)

            timer.setEventHandler { [weak self] in
                guard let self = self else {
                    timer.cancel()
                    return
                }

                currentStep += 1
                let progress = Double(currentStep) / Double(totalSteps)
                let eased = Float(1.0 - pow(1.0 - progress, 3.0))
                let currentFactor = startProgress + (1.0 - startProgress) * eased

                let curR = 1.0 + (targetR - 1.0) * currentFactor
                let curG = 1.0 + (targetG - 1.0) * currentFactor
                let curB = 1.0 + (targetB - 1.0) * currentFactor

                self.applyGammaMultipliers(displayID: displayID, rMult: curR, gMult: curG, bMult: curB)
                self.currentWarmthProgress = currentFactor

                if currentStep >= totalSteps {
                    self.applyGammaMultipliers(displayID: displayID, rMult: targetR, gMult: targetG, bMult: targetB)
                    self.currentWarmthProgress = 1.0
                    self.isCurrentlyWarm = true
                    timer.cancel()
                    self.lock.lock()
                    self.animationTimer = nil
                    self.lock.unlock()
                    completion?()
                }
            }

            self.animationTimer = timer
            self.lock.unlock()
            timer.resume()
        }
    }

    /// 恢复内建屏幕原生色彩（仅作用于内建 Mac 屏）
    public func restoreSystemColor(duration: TimeInterval = 0.0, completion: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let displayID = DisplayBridge.getBuiltinDisplayID() else {
                completion?()
                return
            }

            self.lock.lock()
            self.animationTimer?.cancel()
            self.animationTimer = nil

            if !self.isCurrentlyWarm && self.currentWarmthProgress <= 0.01 {
                self.lock.unlock()
                completion?()
                return
            }

            if duration <= 0.03 || self.baselineRed.isEmpty {
                self.forceRestoreNativeSync(displayID: displayID)
                self.isCurrentlyWarm = false
                self.currentWarmthProgress = 0.0
                self.lock.unlock()
                completion?()
                return
            }

            let startProgress = self.currentWarmthProgress
            let fps: Double = 60.0
            let totalSteps = max(1, Int(duration * fps))
            let interval = duration / Double(totalSteps)
            var currentStep = 0

            let kelvin = SiriusPreferences.shared.amberTemperatureK
            let (targetR, targetG, targetB) = Self.multipliers(for: kelvin)

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: interval)

            timer.setEventHandler { [weak self] in
                guard let self = self else {
                    timer.cancel()
                    return
                }

                currentStep += 1
                let progress = Double(currentStep) / Double(totalSteps)
                let eased = Float(1.0 - pow(1.0 - progress, 3.0))
                let currentFactor = startProgress * (1.0 - eased)

                let curR = 1.0 + (targetR - 1.0) * currentFactor
                let curG = 1.0 + (targetG - 1.0) * currentFactor
                let curB = 1.0 + (targetB - 1.0) * currentFactor

                self.applyGammaMultipliers(displayID: displayID, rMult: curR, gMult: curG, bMult: curB)
                self.currentWarmthProgress = currentFactor

                if currentStep >= totalSteps {
                    self.forceRestoreNativeSync(displayID: displayID)
                    self.isCurrentlyWarm = false
                    self.currentWarmthProgress = 0.0
                    timer.cancel()
                    self.lock.lock()
                    self.animationTimer = nil
                    self.lock.unlock()
                    completion?()
                }
            }

            self.animationTimer = timer
            self.lock.unlock()
            timer.resume()
        }
    }

    /// 强制瞬时复原内建屏幕色彩（硬件自愈与退出兜底）
    public func forceRestoreNative(displayID: CGDirectDisplayID? = nil) {
        lock.lock()
        defer { lock.unlock() }
        animationTimer?.cancel()
        animationTimer = nil

        let id = displayID ?? DisplayBridge.getBuiltinDisplayID()
        forceRestoreNativeSync(displayID: id)
        self.isCurrentlyWarm = false
        self.currentWarmthProgress = 0.0
        print("[Sirius] ColorEngine: Builtin screen color completely restored to native state.")
    }

    /// 紧急复原内建屏幕色彩并重置系统 ColorSync（供用户一键排障与容灾自愈）
    public func emergencyReset() {
        lock.lock()
        animationTimer?.cancel()
        animationTimer = nil
        baselineRed.removeAll()
        baselineGreen.removeAll()
        baselineBlue.removeAll()
        sampleCount = 0
        isCurrentlyWarm = false
        currentWarmthProgress = 0.0
        lock.unlock()

        if let displayID = DisplayBridge.getBuiltinDisplayID() {
            let capacity: UInt32 = 256
            var linear = [CGGammaValue](repeating: 0, count: Int(capacity))
            for i in 0..<Int(capacity) {
                linear[i] = CGGammaValue(i) / CGGammaValue(capacity - 1)
            }
            CGSetDisplayTransferByTable(displayID, capacity, linear, linear, linear)
        }
        CGDisplayRestoreColorSyncSettings()

        disableSystemWideNightShiftIfAny()
        captureBaseline()

        print("[Sirius] ColorEngine: Emergency reset performed. Display color restored to standard factory profile.")
    }

    // MARK: - 内部私有方法

    private func forceRestoreNativeSync(displayID: CGDirectDisplayID? = nil) {
        guard let id = displayID ?? DisplayBridge.getBuiltinDisplayID() else { return }
        if !baselineRed.isEmpty && sampleCount > 0 {
            CGSetDisplayTransferByTable(id, sampleCount, baselineRed, baselineGreen, baselineBlue)
        } else {
            // 生成标准 256 点线性表还原
            let capacity: UInt32 = 256
            var linear = [CGGammaValue](repeating: 0, count: Int(capacity))
            for i in 0..<Int(capacity) {
                linear[i] = CGGammaValue(i) / CGGammaValue(capacity - 1)
            }
            CGSetDisplayTransferByTable(id, capacity, linear, linear, linear)
        }
    }

    private func captureBaselineInternal(displayID: CGDirectDisplayID) {
        let capacity: UInt32 = 256
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = [CGGammaValue](repeating: 0, count: Int(capacity))
        var b = [CGGammaValue](repeating: 0, count: Int(capacity))
        var count: UInt32 = 0

        let status = CGGetDisplayTransferByTable(displayID, capacity, &r, &g, &b, &count)
        if status == .success && count > 0 {
            self.sampleCount = count
            self.baselineRed = Array(r.prefix(Int(count)))
            self.baselineGreen = Array(g.prefix(Int(count)))
            self.baselineBlue = Array(b.prefix(Int(count)))
            print("[Sirius] ColorEngine: Captured native baseline Gamma table (\(count) samples) for display \(displayID).")
        }
    }

    private func applyGammaMultipliers(displayID: CGDirectDisplayID, rMult: Float, gMult: Float, bMult: Float) {
        let count = sampleCount > 0 ? sampleCount : 256
        let n = Int(count)

        var newR = [CGGammaValue](repeating: 0, count: n)
        var newG = [CGGammaValue](repeating: 0, count: n)
        var newB = [CGGammaValue](repeating: 0, count: n)

        let hasBaseline = !baselineRed.isEmpty && baselineRed.count == n

        for i in 0..<n {
            let baseR = hasBaseline ? baselineRed[i] : (CGGammaValue(i) / CGGammaValue(n - 1))
            let baseG = hasBaseline ? baselineGreen[i] : (CGGammaValue(i) / CGGammaValue(n - 1))
            let baseB = hasBaseline ? baselineBlue[i] : (CGGammaValue(i) / CGGammaValue(n - 1))

            newR[i] = max(0.0, min(1.0, baseR * rMult))
            newG[i] = max(0.0, min(1.0, baseG * gMult))
            newB[i] = max(0.0, min(1.0, baseB * bMult))
        }

        CGSetDisplayTransferByTable(displayID, count, newR, newG, newB)
    }
}

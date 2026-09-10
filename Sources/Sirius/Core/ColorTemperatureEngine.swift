import Foundation
import CoreGraphics
import AppKit

/// 负责通过 macOS 原生 CoreGraphics Gamma LUT 显卡查找表，直接驱动内建屏幕色温与低蓝光护眼
public final class ColorTemperatureEngine: @unchecked Sendable {
    public static let shared = ColorTemperatureEngine()

    private let queue = DispatchQueue(label: "com.yaology.sirius.color-engine", qos: .userInteractive)
    private let lock = NSLock()
    private var animationTimer: DispatchSourceTimer?

    // 缓存显示器基准原始 Gamma 表 (256 采样点)
    private var sampleCount: UInt32 = 0
    private var baselineRed: [CGGammaValue] = []
    private var baselineGreen: [CGGammaValue] = []
    private var baselineBlue: [CGGammaValue] = []

    // 当前渲染状态
    private(set) var isCurrentlyWarm: Bool = false
    private var currentWarmthProgress: Float = 0.0 // 0.0 (原生) ~ 1.0 (目标暖色)

    private init() {
        captureBaseline()
    }

    /// 捕获并记录当前屏幕未被修改的原生色彩基准表
    public func captureBaseline() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let displayID = DisplayBridge.getBuiltinDisplayID() else { return }

            self.lock.lock()
            defer { self.lock.unlock() }

            // 如果当前已经处于暖色态，不应覆盖真实的冷基准表
            if self.isCurrentlyWarm && !self.baselineRed.isEmpty {
                return
            }

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
                print("[Sirius] ColorEngine: Captured native baseline Gamma table (\(count) samples).")
            }
        }
    }

    /// 计算给定色温（Kelvin）下的 RGB 衰减乘数
    public static func multipliers(for kelvin: Double) -> (r: Float, g: Float, b: Float) {
        let clampedK = max(2500.0, min(5500.0, kelvin))
        let w = Float((5500.0 - clampedK) / 3000.0) // 0.0 (5500K) ~ 1.0 (2500K)
        let r: Float = 1.0
        let g: Float = 1.0 - 0.20 * w
        let b: Float = 0.82 - 0.62 * w
        return (r, g, b)
    }

    /// 实时预览色温（供设置面板滑块拖拽时即时响应）
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
            self.lock.unlock()
        }
    }

    /// 平滑渐变至目标暖光色温
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
                // Ease-out cubic curve
                let eased = Float(1.0 - pow(1.0 - progress, 3.0))
                let currentFactor = startProgress + (1.0 - startProgress) * eased

                // 插值当前乘数
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

    /// 恢复系统原生色彩
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
                self.forceRestoreNative(displayID: displayID)
                self.lock.unlock()
                completion?()
                return
            }

            let startProgress = self.currentWarmthProgress
            let fps: Double = 60.0
            let totalSteps = max(1, Int(duration * fps))
            let interval = duration / Double(totalSteps)
            var currentStep = 0

            // 获取当期暖色目标（从偏好设置读取）
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
                    self.forceRestoreNative(displayID: displayID)
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

    /// 强制瞬时复原系统默认色彩（硬件自愈与退出兜底）
    public func forceRestoreNative(displayID: CGDirectDisplayID? = nil) {
        if let id = displayID ?? DisplayBridge.getBuiltinDisplayID(), !baselineRed.isEmpty {
            CGSetDisplayTransferByTable(id, sampleCount, baselineRed, baselineGreen, baselineBlue)
        } else {
            CGDisplayRestoreColorSyncSettings()
        }
        self.isCurrentlyWarm = false
        self.currentWarmthProgress = 0.0
        print("[Sirius] ColorEngine: Color profile completely restored to native system state.")
    }

    // MARK: - 内部私有方法

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
        }
    }

    private func applyGammaMultipliers(displayID: CGDirectDisplayID, rMult: Float, gMult: Float, bMult: Float) {
        guard sampleCount > 0, !baselineRed.isEmpty else { return }

        let n = Int(sampleCount)
        var newR = [CGGammaValue](repeating: 0, count: n)
        var newG = [CGGammaValue](repeating: 0, count: n)
        var newB = [CGGammaValue](repeating: 0, count: n)

        for i in 0..<n {
            newR[i] = max(0.0, min(1.0, baselineRed[i] * rMult))
            newG[i] = max(0.0, min(1.0, baselineGreen[i] * gMult))
            newB[i] = max(0.0, min(1.0, baselineBlue[i] * bMult))
        }

        CGSetDisplayTransferByTable(displayID, sampleCount, newR, newG, newB)
    }
}

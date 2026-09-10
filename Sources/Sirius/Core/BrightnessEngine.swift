import Foundation
import CoreGraphics

/// 负责处理平滑贝塞尔插值调光、硬件亮度追踪与防撕裂动画
public final class BrightnessEngine: @unchecked Sendable {
    public static let shared = BrightnessEngine()

    private var animationTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.yaology.sirius.brightness-engine", qos: .userInteractive)
    private let lock = NSLock()

    /// 用户在 MacBook 屏幕上工作时的正常偏好亮度（动态记录与持久化存储）
    public var userActiveBrightness: Float {
        SiriusPreferences.shared.userActiveBrightness
    }

    /// 当前正在渲染的目标亮度
    private var currentTargetBrightness: Float = 0.80

    private init() {
        let prefs = SiriusPreferences.shared
        if let builtinID = DisplayBridge.getBuiltinDisplayID(),
           let current = DisplayBridge.getBrightness(displayID: builtinID) {
            let floor = prefs.ambientFloor
            // 仅当当前硬件背光显著高于底噪时，才同步初始偏好设置
            if current > floor + 0.15 && current >= 0.35 {
                prefs.userActiveBrightness = current
            } else if current <= floor + 0.05 {
                // 启动防黑屏自愈：当前物理亮度异常偏低（<= 底噪），立即恢复至正常工作偏好亮度
                let safeBrightness = max(0.60, prefs.userActiveBrightness)
                DisplayBridge.setBrightness(displayID: builtinID, brightness: safeBrightness)
                print("[Sirius] Startup Self-Healing: Restored dimmed hardware backlight to safe level: \(String(format: "%.1f%%", safeBrightness * 100))")
            }
        }
        self.currentTargetBrightness = prefs.userActiveBrightness
    }

    /// 在用户处于内置屏幕活跃工作态时，捕获当前真实的背光亮度作为基准
    public func captureUserActiveBrightness() {
        // 严格限制：仅在全亮活跃态时捕获，绝不于渐暗、暗光、唤醒中或冷却期捕获！
        guard case .active = SiriusStateMachine.shared.currentState else { return }

        guard let builtinID = DisplayBridge.getBuiltinDisplayID(),
              let current = DisplayBridge.getBrightness(displayID: builtinID) else { return }
        
        let floor = SiriusPreferences.shared.ambientFloor
        // 必须显著高于底噪（至少高出 0.10，且绝对值不能低于 0.25）才视为主观工作偏好
        if current <= floor + 0.10 || current < 0.25 {
            return
        }
        
        let old = SiriusPreferences.shared.userActiveBrightness
        if abs(old - current) > 0.02 {
            SiriusPreferences.shared.userActiveBrightness = current
            print("[Sirius] Captured updated user active brightness: \(String(format: "%.1f%%", current * 100)) (was \(String(format: "%.1f%%", old * 100)))")
        }
    }

    /// 实时预览微光底噪（临时调光，不打乱用户基准亮度）
    public func previewFloor(brightness: Float) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.animationTimer?.cancel()
            self.animationTimer = nil
            self.lock.unlock()

            if let displayID = DisplayBridge.getBuiltinDisplayID() {
                let clamped = max(0.0, min(1.0, brightness))
                DisplayBridge.setBrightness(displayID: displayID, brightness: clamped)
            }
        }
    }

    /// 设定新的基准工作亮度
    public func setUserActiveBrightness(_ value: Float) {
        SiriusPreferences.shared.userActiveBrightness = max(0.20, min(1.0, value))
    }

    /// 平滑渐变到目标亮度
    /// - Parameters:
    ///   - target: 目标亮度 (0.0 ~ 1.0)
    ///   - duration: 动画持续时间（秒）
    ///   - completion: 完成回调
    public func transition(to target: Float, duration: TimeInterval, completion: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let displayID = DisplayBridge.getBuiltinDisplayID() else {
                completion?()
                return
            }

            self.lock.lock()
            // 停止之前的动画定时器
            self.animationTimer?.cancel()
            self.animationTimer = nil

            let startBrightness = DisplayBridge.getBrightness(displayID: displayID) ?? self.userActiveBrightness
            let clampedTarget = max(0.0, min(1.0, target))
            self.currentTargetBrightness = clampedTarget
            self.lock.unlock()

            // 如果距离极小或时长极短，直接一步到位
            if abs(startBrightness - clampedTarget) < 0.005 || duration <= 0.02 {
                DisplayBridge.setBrightness(displayID: displayID, brightness: clampedTarget)
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

                // 缓动曲线 (Ease-Out Cubic: 1 - (1 - t)^3)
                // 确保视觉初始响应极快，末端平滑贴合
                let eased = Float(1.0 - pow(1.0 - progress, 3.0))
                let currentVal = startBrightness + (clampedTarget - startBrightness) * eased

                DisplayBridge.setBrightness(displayID: displayID, brightness: currentVal)

                if currentStep >= totalSteps {
                    DisplayBridge.setBrightness(displayID: displayID, brightness: clampedTarget)
                    timer.cancel()
                    self.lock.lock()
                    self.animationTimer = nil
                    self.lock.unlock()
                    completion?()
                }
            }

            self.lock.lock()
            self.animationTimer = timer
            self.lock.unlock()
            timer.resume()
        }
    }

    /// 立即停止动画并锁定到指定亮度
    public func immediateSet(brightness: Float) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.animationTimer?.cancel()
            self.animationTimer = nil
            self.lock.unlock()

            if let displayID = DisplayBridge.getBuiltinDisplayID() {
                DisplayBridge.setBrightness(displayID: displayID, brightness: brightness)
            }
        }
    }
}

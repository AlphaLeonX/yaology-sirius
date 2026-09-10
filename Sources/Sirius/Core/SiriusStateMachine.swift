import AppKit
import Foundation

/// Sirius 核心双星状态机
public final class SiriusStateMachine: ObservableObject, @unchecked Sendable {
    public static let shared = SiriusStateMachine()

    public enum State: Equatable, CustomStringConvertible {
        case dormant(reason: String)
        case active
        case cooldown(startedAt: Date)
        case dimming
        case dimmed
        case waking
        case paused(until: Date?)

        public var description: String {
            switch self {
            case .dormant(let reason):
                return "待机 (\(reason))"
            case .active:
                return "伴星全亮 (焦点在 Mac)"
            case .cooldown:
                return "离开冷静期 (等待暗下)"
            case .dimming:
                return "平滑暗下中"
            case .dimmed:
                if SiriusPreferences.shared.ambientFloor >= 0.999 {
                    return "双星恒亮 (100% 伴星不暗下)"
                }
                return "微光潜航 (焦点在外接屏)"
            case .waking:
                return "瞬时唤醒中"
            case .paused(let until):
                if let until = until {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    return "已暂停 (至 \(formatter.string(from: until)))"
                }
                return "已手动暂停"
            }
        }
    }

    @Published public private(set) var currentState: State = .dormant(reason: "初始化")

    private let preferences = SiriusPreferences.shared
    private let engine = BrightnessEngine.shared
    private let autoBrightness = AutoBrightnessManager.shared
    private let cursorTracker = CursorTracker()
    private let hotKeyManager = HotKeyManager.shared

    private var cooldownTimer: DispatchSourceTimer?
    private var activeSyncTimer: DispatchSourceTimer?
    private var pauseTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.yaology.sirius.state-machine", qos: .userInteractive)
    private let lock = NSLock()

    private init() {
        setupObservers()
    }

    /// 启动引擎与所有子系统
    public func start() {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 注册全局快捷键
            if self.preferences.hotKeyEnabled {
                self.hotKeyManager.registerConfiguredHotKey()
                self.hotKeyManager.onHotKeyTriggered = { [weak self] in
                    self?.togglePause()
                }
            }

            // 监听光标屏幕归属
            self.cursorTracker.onCursorLocationChanged = { [weak self] isOnBuiltin, screenCount in
                self?.handleCursorEvent(isOnBuiltin: isOnBuiltin, screenCount: screenCount)
            }
            self.cursorTracker.start()
        }
    }

    /// 切换手动暂停/恢复
    public func togglePause() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.preferences.isPaused {
                self.resumeInternal()
            } else {
                self.preferences.pause(for: 0) // 无限期暂停
                self.enterPausedState(until: nil)
            }
        }
    }

    /// 临时暂停特定时长（秒）
    public func pauseTemporarily(duration: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.preferences.pause(for: duration)
            self.enterPausedState(until: self.preferences.pauseUntil)

            self.cancelPauseTimer()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + duration)
            timer.setEventHandler { [weak self] in
                self?.resumeInternal()
            }
            self.pauseTimer = timer
            timer.resume()
        }
    }

    /// 恢复正常调光
    public func resume() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.resumeInternal()
        }
    }

    private func resumeInternal() {
        cancelPauseTimer()
        preferences.resume()

        let screens = NSScreen.screens
        guard screens.count > 1 else {
            stopActiveSyncTimer()
            cancelCooldown()
            autoBrightness.restoreAutoBrightnessAfterWaking()
            engine.immediateSet(brightness: engine.userActiveBrightness)
            updateState(.dormant(reason: "单屏幕独立工作"))
            return
        }

        guard let builtinScreen = screens.first(where: { $0.isBuiltinScreen }) else {
            updateState(.dormant(reason: "未检测到内建屏幕"))
            return
        }

        let mousePoint = NSEvent.mouseLocation
        let isOnBuiltin = builtinScreen.frame.contains(mousePoint)

        if isOnBuiltin {
            // 光标当前停在 MacBook 屏幕上：即刻唤醒并恢复全亮工作态
            cancelCooldown()
            wakeUpImmediately()
        } else {
            // 光标在外接大屏上：用户显式恢复调光，即刻平滑压暗到底噪
            cancelCooldown()
            executeDimming()
        }
    }

    private var previewRestoreWorkItem: DispatchWorkItem?

    /// 用户拖动微光底噪时实时预览
    public func previewAmbientFloor(value: Float) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.previewRestoreWorkItem?.cancel()
            self.previewRestoreWorkItem = nil

            // 冻结自动亮度以防干扰
            self.autoBrightness.freezeAutoBrightnessForDimming()
            self.engine.previewFloor(brightness: value)
        }
    }

    /// 用户松开微光底噪滑块，如果是活跃工作态则短暂延迟后平滑恢复
    public func endPreviewAmbientFloor() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.previewRestoreWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if case .active = self.currentState {
                    // 仍在活跃工作态：恢复原工作亮度
                    self.autoBrightness.restoreAutoBrightnessAfterWaking()
                    self.engine.transition(to: self.engine.userActiveBrightness, duration: self.preferences.fadeInDuration)
                } else if case .dimmed = self.currentState {
                    // 已经在暗光态：直接维持设置的新底噪
                    let target = min(self.preferences.ambientFloor, self.engine.userActiveBrightness)
                    self.engine.immediateSet(brightness: target)
                }
            }

            self.previewRestoreWorkItem = workItem
            // 停留 0.6 秒供用户观察效果后平滑复原
            self.queue.asyncAfter(deadline: .now() + 0.6, execute: workItem)
        }
    }

    // MARK: - 内部状态调度

    private func enterPausedState(until: Date?) {
        cancelPauseTimer()
        stopActiveSyncTimer()
        cancelCooldown()
        autoBrightness.restoreAutoBrightnessAfterWaking()
        engine.transition(to: engine.userActiveBrightness, duration: preferences.fadeInDuration)
        updateState(.paused(until: until))
    }

    private func cancelPauseTimer() {
        pauseTimer?.cancel()
        pauseTimer = nil
    }

    private func handleCursorEvent(isOnBuiltin: Bool, screenCount: Int) {
        preferences.checkPauseExpiration()

        // 1. 如果处于手动暂停状态，保持原样
        if preferences.isPaused {
            stopActiveSyncTimer()
            return
        }

        // 2. 如果只有单块屏幕（如拔掉外接屏），自动转入 Dormant 待机
        if screenCount <= 1 {
            stopActiveSyncTimer()
            cancelCooldown()
            autoBrightness.restoreAutoBrightnessAfterWaking()
            engine.immediateSet(brightness: engine.userActiveBrightness)
            updateState(.dormant(reason: "单屏幕独立工作"))
            return
        }

        // 3. 双屏/多屏模式
        if isOnBuiltin {
            // 光标回到 MacBook 屏幕：即刻唤醒！
            cancelCooldown()
            wakeUpImmediately()
        } else {
            // 光标移到了外置大屏：进入离开冷静期
            startCooldown()
        }
    }

    private func wakeUpImmediately() {
        switch currentState {
        case .active:
            // 已经是全亮活跃态，记录最新基准并保持后台同步
            engine.captureUserActiveBrightness()
            startActiveSyncTimer()
            return
        case .cooldown:
            // 在冷静期内又移回了鼠标，取消冷静期，无感保持并同步亮度
            cancelCooldown()
            updateState(.active)
            startActiveSyncTimer()
            return
        case .waking:
            // 已经在唤醒过渡中，静候完成即可
            return
        case .dimmed, .dimming, .dormant, .paused:
            // 从暗光或渐暗过程中唤醒，或从单屏/暂停恢复
            updateState(.waking)
            let target = max(preferences.userActiveBrightness, preferences.ambientFloor + 0.20, 0.60)
            engine.transition(to: target, duration: preferences.fadeInDuration) { [weak self] in
                guard let self = self else { return }
                self.autoBrightness.restoreAutoBrightnessAfterWaking()
                self.updateState(.active)
                self.startActiveSyncTimer()
            }
        }
    }

    private func startCooldown() {
        switch currentState {
        case .dimmed, .dimming, .cooldown:
            // 已经在暗光或已经在倒计时中
            return
        case .active, .paused, .dormant:
            // 离开 MacBook 的瞬间，或从暂停/待机中重新进入多屏外置大屏工作态
            engine.captureUserActiveBrightness()
            stopActiveSyncTimer()
            cancelCooldown()
            updateState(.cooldown(startedAt: Date()))

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + preferences.cooldownDelay)
            timer.setEventHandler { [weak self] in
                self?.executeDimming()
            }
            self.cooldownTimer = timer
            timer.resume()
        case .waking:
            // 唤醒未完成时又移出：严禁捕获未到位的过渡亮度！
            stopActiveSyncTimer()
            cancelCooldown()
            updateState(.cooldown(startedAt: Date()))

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + preferences.cooldownDelay)
            timer.setEventHandler { [weak self] in
                self?.executeDimming()
            }
            self.cooldownTimer = timer
            timer.resume()
        }
    }

    private func startActiveSyncTimer() {
        stopActiveSyncTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if case .active = self.currentState {
                self.engine.captureUserActiveBrightness()
            }
        }
        self.activeSyncTimer = timer
        timer.resume()
    }

    private func stopActiveSyncTimer() {
        activeSyncTimer?.cancel()
        activeSyncTimer = nil
    }

    private func cancelCooldown() {
        cooldownTimer?.cancel()
        cooldownTimer = nil
    }

    private func executeDimming() {
        cancelCooldown()
        guard !preferences.isPaused else { return }

        let floor = preferences.ambientFloor
        // 如果底噪设为 1.0 (100%)，视为双星恒亮，不压暗物理背光
        if floor >= 0.999 {
            updateState(.dimmed)
            return
        }

        updateState(.dimming)

        // 待机暗光前冻结系统自动亮度，避免环境光波动引起的频闪
        autoBrightness.freezeAutoBrightnessForDimming()

        let duration = preferences.fadeOutDuration
        let targetBrightness = floor // 直接平滑暗化到底噪设定值

        engine.transition(to: targetBrightness, duration: duration) { [weak self] in
            guard let self = self else { return }
            self.updateState(.dimmed)
        }
    }

    private func evaluateCurrentEnvironment() {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            stopActiveSyncTimer()
            cancelCooldown()
            autoBrightness.restoreAutoBrightnessAfterWaking()
            engine.immediateSet(brightness: engine.userActiveBrightness)
            updateState(.dormant(reason: "单屏幕独立工作"))
            return
        }

        guard let builtinScreen = screens.first(where: { $0.isBuiltinScreen }) else {
            updateState(.dormant(reason: "未检测到内建屏幕"))
            return
        }

        let isOnBuiltin = builtinScreen.frame.contains(NSEvent.mouseLocation)
        handleCursorEvent(isOnBuiltin: isOnBuiltin, screenCount: screens.count)
    }

    private func updateState(_ newState: State) {
        DispatchQueue.main.async { [weak self] in
            self?.currentState = newState
        }
    }

    // MARK: - 系统休眠与唤醒

    private func setupObservers() {
        let ws = NSWorkspace.shared.notificationCenter

        // 系统即将休眠：复原亮度与自动亮度
        ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.cancelCooldown()
            self.autoBrightness.restoreAutoBrightnessAfterWaking()
            self.engine.immediateSet(brightness: self.engine.userActiveBrightness)
        }

        // 系统从休眠中唤醒：延迟 1 秒后重新评估双星状态
        ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.queue.asyncAfter(deadline: .now() + 1.0) {
                self.evaluateCurrentEnvironment()
            }
        }
    }
}

import Foundation
import Combine
import AppKit
import ServiceManagement

/// 用户偏好与持久化配置 (v1.1.1)
public final class SiriusPreferences: ObservableObject {
    public static let shared = SiriusPreferences()

    public enum Keys {
        public static let ambientFloor = "sirius.ambientFloor"
        public static let userActiveBrightness = "sirius.userActiveBrightness"
        public static let cooldownDelay = "sirius.cooldownDelay"
        public static let fadeOutDuration = "sirius.fadeOutDuration"
        public static let fadeInDuration = "sirius.fadeInDuration"
        public static let hotKeyEnabled = "sirius.hotKeyEnabled"
        public static let hotKeyCode = "sirius.hotKeyCode"
        public static let hotKeyModifiers = "sirius.hotKeyModifiers"
        public static let hotKeyDisplayString = "sirius.hotKeyDisplayString"
        public static let launchAtLogin = "sirius.launchAtLogin"
        public static let isPaused = "sirius.isPaused"
        public static let showInDock = "sirius.showInDock"
    }

    private let defaults = UserDefaults.standard

    /// 暗光底噪亮度 (0.00 ~ 1.00，默认 0.12 即 12%)
    @Published public var ambientFloor: Float {
        didSet {
            let clamped = max(0.0, min(1.0, ambientFloor))
            defaults.set(clamped, forKey: Keys.ambientFloor)
        }
    }

    /// 用户在 MacBook 屏幕上工作时的正常偏好亮度 (0.20 ~ 1.00，默认 0.80 即 80%)
    @Published public var userActiveBrightness: Float {
        didSet {
            let clamped = max(0.20, min(1.0, userActiveBrightness))
            defaults.set(clamped, forKey: Keys.userActiveBrightness)
        }
    }

    /// 离开 MacBook 屏幕后的静默等待时间（秒，默认 3.0，支持自定义 0.0 ~ 30.0）
    @Published public var cooldownDelay: TimeInterval {
        didSet {
            let clamped = max(0.0, min(60.0, cooldownDelay))
            defaults.set(clamped, forKey: Keys.cooldownDelay)
        }
    }

    /// 平滑变暗持续时间（秒，默认 0.40）
    @Published public var fadeOutDuration: TimeInterval {
        didSet {
            defaults.set(fadeOutDuration, forKey: Keys.fadeOutDuration)
        }
    }

    /// 划入唤醒快速平滑渐亮时间（秒，默认 0.15）
    @Published public var fadeInDuration: TimeInterval {
        didSet {
            defaults.set(fadeInDuration, forKey: Keys.fadeInDuration)
        }
    }

    /// 是否启用全局快捷键
    @Published public var hotKeyEnabled: Bool {
        didSet {
            defaults.set(hotKeyEnabled, forKey: Keys.hotKeyEnabled)
        }
    }

    /// 自定义全局快捷键 KeyCode (默认 1 = 'S')
    @Published public var hotKeyCode: UInt32 {
        didSet {
            defaults.set(hotKeyCode, forKey: Keys.hotKeyCode)
        }
    }

    /// 自定义全局快捷键 Carbon 修饰符 (默认 2048 = optionKey / 0x0800)
    @Published public var hotKeyModifiers: UInt32 {
        didSet {
            defaults.set(hotKeyModifiers, forKey: Keys.hotKeyModifiers)
        }
    }

    /// 自定义快捷键显示文本 (例如 "⌥S", "⌃⌥S")
    @Published public var hotKeyDisplayString: String {
        didSet {
            defaults.set(hotKeyDisplayString, forKey: Keys.hotKeyDisplayString)
        }
    }

    /// 开机自启动
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            syncLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    /// 手动禁用/暂停状态
    @Published public var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: Keys.isPaused)
        }
    }

    /// 是否在程序坞 (Dock) 显示应用图标（默认 true）
    @Published public var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: Keys.showInDock)
            updateActivationPolicy()
        }
    }

    /// 定时恢复时间（如果设置了临时暂停 30m / 1h）
    @Published public var pauseUntil: Date?

    private init() {
        self.defaults.register(defaults: [
            Keys.ambientFloor: Float(0.12),
            Keys.userActiveBrightness: Float(0.80),
            Keys.cooldownDelay: TimeInterval(3.0),
            Keys.fadeOutDuration: TimeInterval(0.40),
            Keys.fadeInDuration: TimeInterval(0.15),
            Keys.hotKeyEnabled: true,
            Keys.hotKeyCode: UInt32(1), // 'S'
            Keys.hotKeyModifiers: UInt32(2048), // optionKey
            Keys.hotKeyDisplayString: "⌥S",
            Keys.launchAtLogin: false,
            Keys.isPaused: false,
            Keys.showInDock: true
        ])

        self.ambientFloor = defaults.float(forKey: Keys.ambientFloor)
        let savedActive = defaults.float(forKey: Keys.userActiveBrightness)
        self.userActiveBrightness = savedActive > 0.05 ? savedActive : 0.80
        self.cooldownDelay = defaults.double(forKey: Keys.cooldownDelay)
        self.fadeOutDuration = defaults.double(forKey: Keys.fadeOutDuration)
        self.fadeInDuration = defaults.double(forKey: Keys.fadeInDuration)
        self.hotKeyEnabled = defaults.bool(forKey: Keys.hotKeyEnabled)
        self.hotKeyCode = UInt32(defaults.integer(forKey: Keys.hotKeyCode))
        self.hotKeyModifiers = UInt32(defaults.integer(forKey: Keys.hotKeyModifiers))
        self.hotKeyDisplayString = defaults.string(forKey: Keys.hotKeyDisplayString) ?? "⌥S"
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        self.showInDock = defaults.object(forKey: Keys.showInDock) as? Bool ?? true

        // 校验系统真实自启状态
        checkSystemLaunchAtLoginStatus()
    }

    /// 更新 macOS 应用激活策略（Dock 图标显示/隐藏）
    public func updateActivationPolicy() {
        let targetPolicy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
            if NSApp.windows.contains(where: { $0.isVisible }) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// 暂停指定秒数
    public func pause(for duration: TimeInterval) {
        self.pauseUntil = Date().addingTimeInterval(duration)
        self.isPaused = true
    }

    /// 恢复运行
    public func resume() {
        self.pauseUntil = nil
        self.isPaused = false
    }

    /// 检查并清理过期的定时暂停
    public func checkPauseExpiration() {
        if let until = pauseUntil, Date() >= until {
            resume()
        }
    }

    /// 同步真正的系统级开机自启 (macOS 13+ SMAppService)
    public func syncLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notRegistered || service.status == .requiresApproval {
                    try service.register()
                    print("[Sirius] SMAppService successfully registered launch at login.")
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                    print("[Sirius] SMAppService successfully unregistered launch at login.")
                }
            }
        } catch {
            print("[Sirius] Failed to update launchAtLogin: \(error)")
        }
    }

    private func checkSystemLaunchAtLoginStatus() {
        let service = SMAppService.mainApp
        let isRegistered = (service.status == .enabled)
        if self.launchAtLogin != isRegistered {
            self.launchAtLogin = isRegistered
        }
    }

    /// 重置所有配置为出厂默认值
    public func resetToDefaults() {
        self.ambientFloor = 0.12
        self.userActiveBrightness = 0.80
        self.cooldownDelay = 3.0
        self.fadeOutDuration = 0.40
        self.fadeInDuration = 0.15
        self.hotKeyEnabled = true
        self.hotKeyCode = 1
        self.hotKeyModifiers = 2048
        self.hotKeyDisplayString = "⌥S"
        self.showInDock = true
        self.launchAtLogin = false
        self.isPaused = false
        self.pauseUntil = nil
    }
}

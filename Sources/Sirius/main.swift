import AppKit
import Foundation

// MARK: - CLI 自检与诊断模式 (--check / --test)
if CommandLine.arguments.contains("--check") || CommandLine.arguments.contains("--test") {
    print("======================================================")
    print("  Sirius (天狼星) 双星调光引擎 · 运行环境与自检诊断")
    print("======================================================")

    // 1. 用户偏好配置测试
    let prefs = SiriusPreferences.shared
    assert(prefs.ambientFloor >= 0.0 && prefs.ambientFloor <= 1.0, "ambientFloor 超出安全范围")
    print("  ✓ [Preferences] 默认参数有效: 底噪 \(Int(prefs.ambientFloor * 100))%, 冷静期 \(prefs.cooldownDelay)s")

    // 2. 物理屏幕与 DisplayServices 接口测试
    let builtinID = DisplayBridge.getBuiltinDisplayID()
    if let id = builtinID {
        let currentB = DisplayBridge.getBrightness(displayID: id)
        let bString = currentB != nil ? String(format: "%.1f%%", currentB! * 100) : "无法读取"
        print("  ✓ [Hardware] 检测到内建屏幕 (Display ID: \(id)), 物理背光当前亮度: \(bString)")
    } else {
        print("  ! [Hardware] 未检测到内建显示屏 (可能为外接纯桌面机模式或合盖中)")
    }

    // 3. 多屏拓扑测试
    let screens = NSScreen.screens
    print("  ✓ [Screens] 当前在线屏幕数量: \(screens.count)")
    for (idx, sc) in screens.enumerated() {
        print("      - 屏幕 #\(idx + 1): \(Int(sc.frame.width))x\(Int(sc.frame.height)) @ (\(Int(sc.frame.origin.x)), \(Int(sc.frame.origin.y)))")
    }

    // 4. 自动亮度管理 (CoreBrightness ALS)
    let autoBrightness = AutoBrightnessManager.shared
    let isAutoEnabled = autoBrightness.isAutoBrightnessEnabled()
    print("  ✓ [AutoBrightness] 系统自动亮度检测: \(isAutoEnabled ? "已启用 (支持智能待机托管)" : "未启用/手动")")

    // 5. Carbon 全局热键测试（若已有实例在运行则跳过实际注册，避免抢占它正在使用的 ⌥S）
    let bundleID = Bundle.main.bundleIdentifier ?? "com.yaology.sirius.app"
    let myPID = ProcessInfo.processInfo.processIdentifier
    let otherInstanceRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .contains { $0.processIdentifier != myPID }

    if otherInstanceRunning {
        print("  ! [HotKey] 检测到已有 Sirius 实例在运行，跳过实际注册/注销（避免影响其 ⌥S 全局热键）")
    } else {
        let hotKeyOK = HotKeyManager.shared.registerDefaultHotKey()
        HotKeyManager.shared.unregister()
        print("  ✓ [HotKey] Carbon ⌥+S 全局热键系统注册与注销: \(hotKeyOK ? "正常" : "失败 (可能被其它 App 占用)")")
    }

    // 6. 状态机初始状态
    let sm = SiriusStateMachine.shared
    print("  ✓ [StateMachine] 状态机就绪, 初始状态: \(sm.currentState.description)")

    print("======================================================")
    print("  🎉 所有核心硬件接口与状态机自检测试均已通过！")
    print("======================================================")
    exit(0)
}

// MARK: - CLI 应急复原色彩 (--reset-color)
if CommandLine.arguments.contains("--reset-color") {
    print("[Sirius] 正在执行内建显示器色彩应急复原与 ColorSync 重置...")
    SiriusPreferences.shared.amberAmbientEnabled = false
    ColorTemperatureEngine.shared.emergencyReset()
    print("[Sirius] 屏幕原生色彩与硬件 LUT 表已完全复原。")
    exit(0)
}

// MARK: - 应用主代理
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动自愈：
        // 1) 上次运行在暖色 LUT 生效时异常退出（崩溃 / 强杀）→ 先彻底复原色彩，避免屏幕持续偏暖；
        // 2) 未开启实验室微光 → 复原任何异常偏色残留。
        if UserDefaults.standard.bool(forKey: ColorTemperatureEngine.amberLutAppliedKey) {
            print("[Sirius] Detected stale amber LUT from previous session — performing full color recovery.")
            ColorTemperatureEngine.shared.emergencyReset()
        } else if !SiriusPreferences.shared.amberAmbientEnabled {
            ColorTemperatureEngine.shared.forceRestoreNative()
        }

        // 启动自愈：若上次异常退出时关闭了系统自动亮度，先恢复用户原本的开启状态
        AutoBrightnessManager.shared.performStartupSelfHealing()

        // 根据用户偏好设置激活策略（默认显示在 Dock 栏）
        SiriusPreferences.shared.updateActivationPolicy()

        // 初始化菜单栏
        MenuBarManager.shared.setup()

        // 启动核心双星调度状态机
        SiriusStateMachine.shared.start()

        // 打开 APP 时，窗口正处于当前屏幕窗口正中央
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MenuBarManager.shared.openFloatingPanel(origin: .centerScreen)
        }

        print("[Sirius] Binary Display Governor started successfully.")
    }

    // 点击 Dock 图标时重新激活并唤起控制中心悬浮面板（屏幕正中央）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let settingsWin = SettingsWindowController.shared.window, settingsWin.isVisible {
            settingsWin.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        MenuBarManager.shared.openFloatingPanel(origin: .centerScreen)
        return true
    }

    // 关闭偏好设置窗口后，确保应用继续在后台守护运行，绝不退出
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let prefs = SiriusPreferences.shared

        // 1. 如果用户已选择“下次不再询问”，直接执行已记录策略
        if prefs.suppressResetOnQuitPrompt {
            if prefs.resetOnQuitChoice {
                prefs.resetToDefaults()
            }
            return .terminateNow
        }

        // 2. 弹出原生确认提示弹窗
        let alert = NSAlert()
        alert.messageText = loc("退出 Sirius", "Quit Sirius")
        alert.informativeText = loc(
            "是否需要在退出前将所有调光、色温与快捷键配置重置为出厂默认值？",
            "Do you want to reset all dimming, color temperature, and shortcut settings to factory defaults before quitting?"
        )
        alert.alertStyle = .informational

        let keepBtn = alert.addButton(withTitle: loc("保留当前设置并退出", "Keep Settings and Quit"))
        keepBtn.keyEquivalent = "\r"

        let resetBtn = alert.addButton(withTitle: loc("重置为默认值并退出", "Reset to Defaults and Quit"))

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = loc("下次不再询问 (记住我的选择)", "Do not ask again (Remember choice)")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let shouldRemember = alert.suppressionButton?.state == .on

        // 破坏性操作必须由“真实鼠标点击”触发：
        // 登出 / 关机 / 脚本等非交互式退出时，模态可能被系统中断并返回意料之外的按钮响应，
        // 因此额外校验鼠标是否确实落在「重置」按钮上；否则一律走“保留设置”安全分支。
        let resetButtonFrame = alert.window.convertToScreen(resetBtn.convert(resetBtn.bounds, to: nil))
        let userConfirmedReset = response == .alertSecondButtonReturn && resetButtonFrame.contains(NSEvent.mouseLocation)

        if userConfirmedReset {
            // 重置为默认值
            prefs.resetToDefaults()
            if shouldRemember {
                prefs.suppressResetOnQuitPrompt = true
                prefs.resetOnQuitChoice = true
            }
        } else if shouldRemember {
            // 保留当前设置
            prefs.suppressResetOnQuitPrompt = true
            prefs.resetOnQuitChoice = false
        }

        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出前安全复原硬件与色彩
        HotKeyManager.shared.unregister()
        AutoBrightnessManager.shared.restoreAutoBrightnessAfterWaking()
        ColorTemperatureEngine.shared.forceRestoreNative()
        if let builtinID = DisplayBridge.getBuiltinDisplayID() {
            DisplayBridge.setBrightness(displayID: builtinID, brightness: BrightnessEngine.shared.userActiveBrightness)
        }
        print("[Sirius] Binary Display Governor safely terminated.")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 捕获系统终止信号，确保进程被 kill 时依然能复原物理屏幕背光与自动亮度
signal(SIGTERM) { _ in
    DispatchQueue.main.async {
        NSApp.terminate(nil)
    }
}
signal(SIGINT) { _ in
    DispatchQueue.main.async {
        NSApp.terminate(nil)
    }
}

app.run()

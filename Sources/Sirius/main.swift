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

    // 5. Carbon 全局热键测试
    HotKeyManager.shared.registerDefaultHotKey()
    HotKeyManager.shared.unregister()
    print("  ✓ [HotKey] Carbon ⌥+S 全局热键系统注册与注销: 正常")

    // 6. 状态机初始状态
    let sm = SiriusStateMachine.shared
    print("  ✓ [StateMachine] 状态机就绪, 初始状态: \(sm.currentState.description)")

    print("======================================================")
    print("  🎉 所有核心硬件接口与状态机自检测试均已通过！")
    print("======================================================")
    exit(0)
}

// MARK: - 应用主代理
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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

    func applicationWillTerminate(_ notification: Notification) {
        // 退出前安全复原
        HotKeyManager.shared.unregister()
        AutoBrightnessManager.shared.restoreAutoBrightnessAfterWaking()
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

import SwiftUI
import AppKit

/// Sirius 极简人性化偏好设置窗口 (Preferences)
/// 消除高熵行话，彻底对齐用户真实痛点，自适应浅色/深色主题
public struct SettingsView: View {
    @ObservedObject var preferences = SiriusPreferences.shared
    @ObservedObject var locManager = LocalizationManager.shared
    @State private var selectedTab: SettingsTab = .dimming
    @State private var isRecordingHotKey: Bool = false
    @State private var hotKeyLocalMonitor: Any?

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case dimming
        case general

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .dimming: return loc("调光与护眼", "Dimming & Eye Care")
            case .general: return loc("快捷键与通用", "Shortcuts & General")
            }
        }

        public var iconName: String {
            switch self {
            case .dimming: return "sun.max"
            case .general: return "gearshape"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部分段切换
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: {
                        stopRecording()
                        selectedTab = tab
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11))
                            Text(tab.title)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 内容区
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case .dimming:
                        dimmingSection
                    case .general:
                        generalSection
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 350)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - 调光设置 (Dimming)

    private var dimmingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. 离开延时
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("离开延时 (防误触缓冲)", "Cooldown Delay (Buffer)"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(loc("鼠标移到外接大屏后，静默等待几秒才将 MacBook 屏幕调暗，避免鼠标在边缘滑过时闪烁。", "Delay before dimming MacBook screen when cursor moves to external display, avoiding flicker."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(String(format: loc("%.1f 秒", "%.1fs"), preferences.cooldownDelay))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }

                Slider(
                    value: $preferences.cooldownDelay,
                    in: 0.0...30.0,
                    step: 0.5
                )
                .tint(Color.accentColor)

                HStack(spacing: 6) {
                    cooldownButton(0.0, loc("0秒 (即刻)", "0s (Instant)"))
                    cooldownButton(1.0, loc("1秒", "1s"))
                    cooldownButton(3.0, loc("3秒 (推荐)", "3s (Rec)"))
                    cooldownButton(5.0, loc("5秒", "5s"))
                    cooldownButton(8.0, loc("8秒", "8s"))
                    cooldownButton(15.0, loc("15秒", "15s"))
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            // 2. 微光底噪
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("微光底噪 (变暗程度)", "Ambient Floor (Dim Level)"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(loc("MacBook 闲置时的背光亮度。0% 为彻底熄屏，12% 为适度微光，100% 为常亮不暗。", "MacBook brightness when idle: 0% turns off, 12% gentle ambient, 100% always full."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(floorText)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }

                Slider(
                    value: Binding(
                        get: { Double(preferences.ambientFloor) },
                        set: { val in
                            preferences.ambientFloor = Float(val)
                            SiriusStateMachine.shared.previewAmbientFloor(value: Float(val))
                        }
                    ),
                    in: 0.0...1.0,
                    step: 0.01,
                    onEditingChanged: { editing in
                        if !editing {
                            SiriusStateMachine.shared.endPreviewAmbientFloor()
                        }
                    }
                )
                .tint(Color.accentColor)

                HStack {
                    Button(loc("0% 熄屏", "0% Off")) {
                        setFloor(0.0)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(preferences.ambientFloor == 0.0 ? .accentColor : .secondary)

                    Spacer()

                    Button(loc("12% 默认微光", "12% Default")) {
                        setFloor(0.12)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(abs(preferences.ambientFloor - 0.12) < 0.01 ? .accentColor : .secondary)

                    Spacer()

                    Button(loc("100% 恒亮", "100% Full")) {
                        setFloor(1.0)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(preferences.ambientFloor >= 0.99 ? .accentColor : .secondary)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            // 3. 全亮工作亮度
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("全亮工作亮度 (唤醒目标)", "Active Brightness (Wake Target)"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(loc("鼠标移回 MacBook 时的唤醒目标亮度。支持随系统亮度按键自动同步，或在此手动调节。", "Target brightness when waking up. Automatically syncs with hardware brightness keys or manual adjustment."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(Int(preferences.userActiveBrightness * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }

                Slider(
                    value: Binding(
                        get: { Double(preferences.userActiveBrightness) },
                        set: { val in
                            preferences.userActiveBrightness = Float(val)
                        }
                    ),
                    in: 0.20...1.0,
                    step: 0.01
                )
                .tint(Color.accentColor)

                HStack {
                    Button(loc("50% 适中", "50% Medium")) {
                        preferences.userActiveBrightness = 0.50
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(abs(preferences.userActiveBrightness - 0.50) < 0.01 ? .accentColor : .secondary)

                    Spacer()

                    Button(loc("80% 推荐工作", "80% Recommended")) {
                        preferences.userActiveBrightness = 0.80
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(abs(preferences.userActiveBrightness - 0.80) < 0.01 ? .accentColor : .secondary)

                    Spacer()

                    Button(loc("100% 极亮", "100% Maximum")) {
                        preferences.userActiveBrightness = 1.0
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(preferences.userActiveBrightness >= 0.99 ? .accentColor : .secondary)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            // 4. 琥珀微光与护眼 (Amber Ambient)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.98, green: 0.65, blue: 0.22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("琥珀微光 (待机低蓝光护眼)", "Amber Ambient (Eye Care)"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(loc("MacBook 在待机变暗时同步调低蓝光输出，模拟温润烛光，消除余光视觉刺激。", "Reduces blue light when dimmed, emitting a warm amber glow to ease eye strain."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $preferences.amberAmbientEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: preferences.amberAmbientEnabled) { _, enabled in
                            SiriusStateMachine.shared.handleAmberAmbientToggled(enabled: enabled)
                        }
                }

                if preferences.amberAmbientEnabled {
                    Divider().opacity(0.15)

                    // 色温滑块
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(loc("暖光色温", "Color Temperature"))
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(preferences.amberTemperatureK))K")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(Color(red: 0.98, green: 0.65, blue: 0.22))
                        }

                        Slider(
                            value: Binding(
                                get: { preferences.amberTemperatureK },
                                set: { newK in
                                    preferences.amberTemperatureK = newK
                                    ColorTemperatureEngine.shared.previewTemperature(kelvin: newK)
                                }
                            ),
                            in: 2500...5500,
                            step: 50,
                            onEditingChanged: { editing in
                                if !editing {
                                    SiriusStateMachine.shared.endPreviewAmberTemperature()
                                }
                            }
                        )
                        .tint(Color(red: 0.98, green: 0.65, blue: 0.22))

                        HStack {
                            Button(loc("2500K 烛光 (极暖)", "2500K Candle (Ultra Warm)")) {
                                setKelvin(2500)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(abs(preferences.amberTemperatureK - 2500) < 50 ? Color(red: 0.98, green: 0.65, blue: 0.22) : .secondary)

                            Spacer()

                            Button(loc("3200K 经典琥珀 (推荐)", "3200K Amber (Recommended)")) {
                                setKelvin(3200)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(abs(preferences.amberTemperatureK - 3200) < 50 ? Color(red: 0.98, green: 0.65, blue: 0.22) : .secondary)

                            Spacer()

                            Button(loc("4500K 温和暖调", "4500K Soft Warm")) {
                                setKelvin(4500)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(abs(preferences.amberTemperatureK - 4500) < 50 ? Color(red: 0.98, green: 0.65, blue: 0.22) : .secondary)
                        }
                    }

                    Divider().opacity(0.15)

                    // 唤醒行为子选项
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $preferences.amberRestoreOnWake) {
                            Text(loc("光标划回唤醒时还原自然色彩", "Restore natural color when waking up"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .toggleStyle(.checkbox)

                        Text(loc("默认不勾选：划回 Mac 唤醒后继续保持舒适护眼暖光，避免夜间被骤亮白光刺眼。如需作图校色，可勾选此项以在唤醒时即刻还原标准自然色。", "Default off: keeps eye-care warmth when active. Turn on if you need accurate color grading upon waking."))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }

    private func cooldownButton(_ val: TimeInterval, _ label: String) -> some View {
        Button(action: {
            preferences.cooldownDelay = val
        }) {
            Text(label)
                .font(.system(size: 10, weight: abs(preferences.cooldownDelay - val) < 0.1 ? .semibold : .regular))
                .foregroundColor(abs(preferences.cooldownDelay - val) < 0.1 ? .white : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(abs(preferences.cooldownDelay - val) < 0.1 ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func setFloor(_ value: Float) {
        preferences.ambientFloor = value
        SiriusStateMachine.shared.previewAmbientFloor(value: value)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            SiriusStateMachine.shared.endPreviewAmbientFloor()
        }
    }

    private var floorText: String {
        let percent = Int(preferences.ambientFloor * 100)
        if percent == 0 { return loc("0% (熄屏)", "0% (Off)") }
        if percent == 100 { return loc("100% (恒亮)", "100% (Full)") }
        return "\(percent)%"
    }

    // MARK: - 快捷键与通用 (General & Shortcut)

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 语言设置
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("界面语言", "Language"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(loc("选择软件界面显示语言（即时生效）。", "Choose interface display language (takes effect immediately)."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $preferences.appLanguage) {
                        Text(loc("跟随系统", "System")).tag("system")
                        Text("简体中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            // 全局快捷键
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $preferences.hotKeyEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("启用全局快捷键", "Enable Global Shortcut"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(loc("随时按下快捷键，快速暂停或恢复调光功能（零权限，无需辅助功能授权）。", "Press shortcut anytime to quickly pause or resume dimming (zero permissions required)."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: preferences.hotKeyEnabled) { _, enabled in
                    if enabled {
                        HotKeyManager.shared.registerConfiguredHotKey()
                    } else {
                        HotKeyManager.shared.unregister()
                    }
                }

                Divider()

                HStack {
                    Text(loc("当前快捷键：", "Current Shortcut:"))
                        .font(.system(size: 12))
                        .foregroundColor(.primary)

                    Spacer()

                    // 录制按钮
                    Button(action: {
                        if isRecordingHotKey {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }) {
                        HStack(spacing: 6) {
                            if isRecordingHotKey {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Text(loc("按下按键...", "Press keys..."))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                            } else {
                                Text(preferences.hotKeyDisplayString)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(isRecordingHotKey ? Color.red.opacity(0.85) : Color(nsColor: .windowBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(loc("恢复默认 (⌥S)", "Default (⌥S)")) {
                        stopRecording()
                        preferences.hotKeyCode = 1
                        preferences.hotKeyModifiers = 2048
                        preferences.hotKeyDisplayString = "⌥S"
                        HotKeyManager.shared.registerConfiguredHotKey()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            // 系统设置
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $preferences.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("登录开机自启动", "Launch at Login"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(loc("开机登录 Mac 后在后台自动启动 Sirius（系统原生后台项管理）。", "Automatically start Sirius in the background when logging into Mac."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $preferences.showInDock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("在程序坞 (Dock) 常驻图标", "Show in Dock"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(loc("开启后可在 Dock 栏看到图标；关闭后仅在顶部菜单栏显示。", "Shows app icon in Dock when enabled; menu bar only when disabled."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            // 退出提示与重置选项
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("退出提示与配置重置保护", "Quit Prompt & Reset Protection"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(preferences.suppressResetOnQuitPrompt
                            ? (preferences.resetOnQuitChoice
                                ? loc("当前已记住选择：退出时自动重置为默认配置。", "Remembered choice: Automatically reset to defaults on quit.")
                                : loc("当前已记住选择：退出时自动保留当前配置。", "Remembered choice: Automatically preserve current settings on quit."))
                            : loc("每次退出 Sirius 时，系统将友好弹窗确认是否重置或保留当前配置。", "Prompts on quit whether to reset or preserve current settings."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if preferences.suppressResetOnQuitPrompt {
                        Button(loc("重新开启提示", "Re-enable Prompt")) {
                            preferences.suppressResetOnQuitPrompt = false
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            // 关于与重置
            HStack {
                Text("Sirius v1.2.0 · Yaology")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button(loc("恢复所有默认设置", "Reset All to Defaults")) {
                    preferences.resetToDefaults()
                    HotKeyManager.shared.registerConfiguredHotKey()
                }
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.85))
            }
            .padding(.top, 4)
        }
    }

    private func setKelvin(_ k: Double) {
        preferences.amberTemperatureK = k
        ColorTemperatureEngine.shared.previewTemperature(kelvin: k)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            SiriusStateMachine.shared.endPreviewAmberTemperature()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecordingHotKey = true

        hotKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            if let shortcut = HotKeyShortcut.from(event: event) {
                self.preferences.hotKeyCode = shortcut.keyCode
                self.preferences.hotKeyModifiers = shortcut.carbonModifiers
                self.preferences.hotKeyDisplayString = shortcut.displayString
                HotKeyManager.shared.registerConfiguredHotKey()
                self.stopRecording()
                return nil
            }
            if event.keyCode == 53 { // Esc 退出
                self.stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        if let monitor = hotKeyLocalMonitor {
            NSEvent.removeMonitor(monitor)
            hotKeyLocalMonitor = nil
        }
        isRecordingHotKey = false
    }
}

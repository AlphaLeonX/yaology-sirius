import SwiftUI
import AppKit

/// Sirius 极简人性化偏好设置窗口 (Preferences)
/// 消除高熵行话，彻底对齐用户真实痛点，自适应浅色/深色主题
public struct SettingsView: View {
    @ObservedObject var preferences = SiriusPreferences.shared
    @State private var selectedTab: SettingsTab = .dimming
    @State private var isRecordingHotKey: Bool = false
    @State private var hotKeyLocalMonitor: Any?

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case dimming = "调光设置"
        case general = "快捷键与通用"

        public var id: String { rawValue }

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
                            Text(tab.rawValue)
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
                        Text("离开延时 (防误触缓冲)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("鼠标移到外接大屏后，静默等待几秒才将 MacBook 屏幕调暗，避免鼠标在边缘滑过时闪烁。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f 秒", preferences.cooldownDelay))
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
                    cooldownButton(0.0, "0秒 (即刻)")
                    cooldownButton(1.0, "1秒")
                    cooldownButton(3.0, "3秒 (推荐)")
                    cooldownButton(5.0, "5秒")
                    cooldownButton(8.0, "8秒")
                    cooldownButton(15.0, "15秒")
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
                        Text("微光底噪 (变暗程度)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("MacBook 闲置时的背光亮度。0% 为彻底熄屏，12% 为适度微光，100% 为常亮不暗。")
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
                    Button("0% 熄屏") {
                        setFloor(0.0)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(preferences.ambientFloor == 0.0 ? .accentColor : .secondary)

                    Spacer()

                    Button("12% 默认微光") {
                        setFloor(0.12)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(abs(preferences.ambientFloor - 0.12) < 0.01 ? .accentColor : .secondary)

                    Spacer()

                    Button("100% 恒亮") {
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
                        Text("全亮工作亮度 (唤醒目标)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("鼠标移回 MacBook 时的唤醒目标亮度。支持随系统亮度按键自动同步，或在此手动调节。")
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
                    Button("50% 适中") {
                        preferences.userActiveBrightness = 0.50
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(abs(preferences.userActiveBrightness - 0.50) < 0.01 ? .accentColor : .secondary)

                    Spacer()

                    Button("80% 推荐工作") {
                        preferences.userActiveBrightness = 0.80
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(abs(preferences.userActiveBrightness - 0.80) < 0.01 ? .accentColor : .secondary)

                    Spacer()

                    Button("100% 极亮") {
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
                            Text("琥珀微光 (待机低蓝光护眼)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("MacBook 在待机变暗时同步调低蓝光输出，模拟温润烛光，消除余光视觉刺激。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $preferences.amberAmbientEnabled)
                        .toggleStyle(.switch)
                }

                if preferences.amberAmbientEnabled {
                    Divider().opacity(0.15)

                    // 色温滑块
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("暖光色温")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(preferences.amberTemperatureK))K")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(Color(red: 0.98, green: 0.65, blue: 0.22))
                        }

                        Slider(
                            value: $preferences.amberTemperatureK,
                            in: 2500...5500,
                            step: 100,
                            onEditingChanged: { editing in
                                if editing {
                                    SiriusStateMachine.shared.previewAmberTemperature(kelvin: preferences.amberTemperatureK)
                                } else {
                                    SiriusStateMachine.shared.endPreviewAmberTemperature()
                                }
                            }
                        )
                        .tint(Color(red: 0.98, green: 0.65, blue: 0.22))

                        HStack {
                            Button("2500K 烛光 (极暖)") {
                                setKelvin(2500)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(abs(preferences.amberTemperatureK - 2500) < 50 ? Color(red: 0.98, green: 0.65, blue: 0.22) : .secondary)

                            Spacer()

                            Button("3200K 经典琥珀 (推荐)") {
                                setKelvin(3200)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(abs(preferences.amberTemperatureK - 3200) < 50 ? Color(red: 0.98, green: 0.65, blue: 0.22) : .secondary)

                            Spacer()

                            Button("4500K 温和暖调") {
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
                            Text("光标划回唤醒时还原自然色彩")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .toggleStyle(.checkbox)

                        Text("默认不勾选：划回 Mac 唤醒后继续保持舒适护眼暖光，避免夜间被骤亮白光刺眼。如需作图校色，可勾选此项以在唤醒时即刻还原标准自然色。")
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
        if percent == 0 { return "0% (熄屏)" }
        if percent == 100 { return "100% (恒亮)" }
        return "\(percent)%"
    }

    // MARK: - 快捷键与通用 (General & Shortcut)

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 全局快捷键
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $preferences.hotKeyEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用全局快捷键")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("随时按下快捷键，快速暂停或恢复调光功能（零权限，无需辅助功能授权）。")
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
                    Text("当前快捷键：")
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
                                Text("按下按键...")
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

                    Button("恢复默认 (⌥S)") {
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
                        Text("登录开机自启动")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("开机登录 Mac 后在后台自动启动 Sirius（系统原生后台项管理）。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $preferences.showInDock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("在程序坞 (Dock) 常驻图标")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("开启后可在 Dock 栏看到图标；关闭后仅在顶部菜单栏显示。")
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
                        Text("退出提示与配置重置保护")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(preferences.suppressResetOnQuitPrompt
                            ? "当前已记住选择：退出时\(preferences.resetOnQuitChoice ? "自动重置为默认配置" : "自动保留当前配置")。"
                            : "每次退出 Sirius 时，系统将友好弹窗确认是否重置或保留当前配置。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if preferences.suppressResetOnQuitPrompt {
                        Button("重新开启提示") {
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

                Button("恢复所有默认设置") {
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
        SiriusStateMachine.shared.previewAmberTemperature(kelvin: k)
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

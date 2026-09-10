import SwiftUI
import AppKit

/// 遵循 Yaology 极简美学的悬浮控制面板 (v1.2.0)
/// 完美自适应 macOS 浅色/深色主题，全界面支持中英双语与即时护眼预览
public struct TasteSkillPopOverView: View {
    @ObservedObject var stateMachine = SiriusStateMachine.shared
    @ObservedObject var preferences = SiriusPreferences.shared
    @ObservedObject var locManager = LocalizationManager.shared

    private let cooldownPresets: [TimeInterval] = [1.0, 3.0, 5.0, 8.0]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - 顶栏：标题与设置入口
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sirius")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                        .tracking(-0.3)
                    Text(loc("Mac 多屏引力调光 · α CMa", "Mac Dual-Display Dimmer · α CMa"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 设置按钮
                Button(action: {
                    SettingsWindowController.shared.showSettings()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(loc("打开设置 (⌘,)", "Open Settings (⌘,)"))
            }

            // MARK: - 动态双星引力状态图
            BinaryOrbitView()

            // MARK: - 快捷启闭行
            HStack(spacing: 8) {
                Button(action: {
                    stateMachine.togglePause()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: preferences.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10, weight: .medium))
                        Text(preferences.isPaused ? loc("恢复调光", "Resume") : loc("快捷暂停", "Pause"))
                            .font(.system(size: 11, weight: .medium))
                        Text(preferences.hotKeyDisplayString)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(preferences.isPaused ? Color.white.opacity(0.2) : Color.primary.opacity(0.08))
                            .cornerRadius(3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                }
                .buttonStyle(.plain)
                .background(preferences.isPaused ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(preferences.isPaused ? .white : .primary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(preferences.isPaused ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
                )

                Menu {
                    Button(loc("暂停 30 分钟", "Pause for 30 min")) { stateMachine.pauseTemporarily(duration: 30 * 60) }
                    Button(loc("暂停 1 小时", "Pause for 1 hour")) { stateMachine.pauseTemporarily(duration: 60 * 60) }
                    Button(loc("暂停至明天 9:00", "Pause until 9:00 AM tomorrow")) { stateMachine.pauseTemporarily(duration: 12 * 60 * 60) }
                } label: {
                    HStack(spacing: 4) {
                        Text(loc("定时暂停", "Timer"))
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.65)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            // MARK: - 微光底噪调节滑块 (0%~100%)
            OpticalFloorSlider()

            // MARK: - 琥珀微光低蓝光护眼
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.98, green: 0.65, blue: 0.22))
                        Text(loc("琥珀微光 (低蓝光护眼)", "Amber Ambient (Eye Care)"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Toggle("", isOn: $preferences.amberAmbientEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.65)
                        .frame(height: 18)
                        .onChange(of: preferences.amberAmbientEnabled) { _, enabled in
                            stateMachine.handleAmberAmbientToggled(enabled: enabled)
                        }
                }

                if preferences.amberAmbientEnabled {
                    VStack(spacing: 3) {
                        HStack {
                            Text(loc("色温强度", "Warmth Intensity"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(preferences.amberTemperatureK))K")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                                    stateMachine.endPreviewAmberTemperature()
                                }
                            }
                        )
                        .tint(Color(red: 0.98, green: 0.65, blue: 0.22))

                        HStack {
                            Text(loc("2500K 烛光", "2500K Candle"))
                                .font(.system(size: 8.5))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(loc("5500K 温和", "5500K Mild"))
                                .font(.system(size: 8.5))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // MARK: - 离开冷静期快捷预设
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                            .foregroundColor(Color.accentColor)
                        Text(loc("离开延时 (防抖缓冲)", "Cooldown Delay (Buffer)"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Text(String(format: "%.1fs", preferences.cooldownDelay))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color.accentColor)
                }

                HStack(spacing: 5) {
                    ForEach(cooldownPresets, id: \.self) { seconds in
                        Button(action: {
                            preferences.cooldownDelay = seconds
                        }) {
                            Text("\(Int(seconds))s\(seconds == 3.0 ? loc(" (推)", " (Rec)") : "")")
                                .font(.system(size: 10, weight: abs(preferences.cooldownDelay - seconds) < 0.1 ? .bold : .medium))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(abs(preferences.cooldownDelay - seconds) < 0.1 ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .foregroundColor(abs(preferences.cooldownDelay - seconds) < 0.1 ? .white : .primary)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // 自定义时长胶囊
                    if !cooldownPresets.contains(where: { abs($0 - preferences.cooldownDelay) < 0.1 }) {
                        Button(action: {
                            SettingsWindowController.shared.showSettings()
                        }) {
                            Text(String(format: loc("%.1fs (自定)", "%.1fs (Custom)"), preferences.cooldownDelay))
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Divider()
                .opacity(0.2)

            // MARK: - 底部栏：版本信息 & 退出
            HStack(alignment: .center) {
                Text("Sirius v1.2.0 · α CMa")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.secondary.opacity(0.7))

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 9, weight: .semibold))
                        Text(loc("退出 Sirius", "Quit Sirius"))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

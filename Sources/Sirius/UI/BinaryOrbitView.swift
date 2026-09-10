import SwiftUI

/// 动态双星引力星轨仪 (The Binary Orbit Radar)
/// 自适应 macOS 浅色/深色主题，直观呈现主星（外接大屏）与伴星（MacBook 屏幕）的联动状态
public struct BinaryOrbitView: View {
    @ObservedObject var stateMachine = SiriusStateMachine.shared
    @ObservedObject var preferences = SiriusPreferences.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // 恒星引力场域与星轨微视窗
            ZStack {
                // 自适应背景（浅色下为温润白透，深色下为黑曜石深透）
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                // 引力微网格与轨道几何
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    // 1. 倾斜引力轨道矢量弧 (Orbital Vector Arc)
                    Path { path in
                        path.move(to: CGPoint(x: 18, y: h * 0.72))
                        path.addQuadCurve(
                            to: CGPoint(x: w - 24, y: h * 0.32),
                            control: CGPoint(x: w * 0.48, y: h * 0.60)
                        )
                    }
                    .stroke(
                        isPaused ? Color.secondary.opacity(0.2) : Color.accentColor.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: isPaused ? [2, 4] : [4, 4])
                    )

                    // 2. 主星 Sirius A (外接大屏 · 恒亮主星)
                    let primaryPos = CGPoint(x: 44, y: h * 0.62)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.accentColor.opacity(0.35),
                                    Color.accentColor.opacity(0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 18
                            )
                        )
                        .frame(width: 32, height: 32)
                        .position(primaryPos)

                    Circle()
                        .fill(Color.primary)
                        .frame(width: 8, height: 8)
                        .position(primaryPos)

                    Text("外接大屏 (主星)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.75))
                        .position(x: primaryPos.x + 4, y: primaryPos.y + 18)

                    // 3. 伴星 Sirius B (MacBook 内建屏 · 动态引力伴星)
                    let companionPos = CGPoint(x: w - 54, y: h * 0.36)

                    if isCompanionActive {
                        // 活跃全亮状态
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.45),
                                        Color.accentColor.opacity(0.15),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 16
                                )
                            )
                            .frame(width: 28, height: 28)
                            .position(companionPos)

                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .position(companionPos)
                    } else if isPaused {
                        // 暂停状态
                        Circle()
                            .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .frame(width: 8, height: 8)
                            .position(companionPos)
                    } else {
                        // 微光底噪状态
                        let floorPercent = Int(preferences.ambientFloor * 100)
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 14, height: 14)
                            .position(companionPos)

                        Circle()
                            .fill(Color.primary.opacity(max(0.25, Double(preferences.ambientFloor))))
                            .frame(width: 5, height: 5)
                            .position(companionPos)

                        Text("\(floorPercent)%")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Color.accentColor)
                            .position(x: companionPos.x + 14, y: companionPos.y - 7)
                    }

                    Text(companionLabel)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(companionColor)
                        .position(x: companionPos.x, y: companionPos.y + 16)
                }
            }
            .frame(height: 86)

            // 下方状态与物理遥测条
            HStack(spacing: 8) {
                Circle()
                    .fill(statusGlowColor)
                    .frame(width: 6, height: 6)

                Text(statusHeadline)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                Text(telemetryBadgeText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .frame(minWidth: 58, alignment: .center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusBadgeBackground)
                    .foregroundColor(statusBadgeForeground)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(statusBadgeBorder, lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Computed Properties

    private var isPaused: Bool {
        if case .paused = stateMachine.currentState { return true }
        return preferences.isPaused
    }

    private var isCompanionActive: Bool {
        switch stateMachine.currentState {
        case .active, .waking:
            return true
        default:
            return false
        }
    }

    private var companionLabel: String {
        switch stateMachine.currentState {
        case .active: return "MacBook (全亮)"
        case .cooldown: return "MacBook (等待)"
        case .dimming: return "MacBook (渐暗)"
        case .dimmed:
            if preferences.ambientFloor >= 0.999 {
                return "MacBook (恒亮)"
            }
            return "MacBook (微光)"
        case .waking: return "MacBook (唤醒)"
        case .paused: return "MacBook (暂停)"
        case .dormant: return "MacBook (单屏)"
        }
    }

    private var companionColor: Color {
        switch stateMachine.currentState {
        case .active, .waking: return .blue
        case .cooldown: return .orange
        case .dimming, .dimmed: return .green
        case .paused: return .red
        case .dormant: return .secondary
        }
    }

    private var statusHeadline: String {
        switch stateMachine.currentState {
        case .active: return "鼠标在 Mac 屏幕上"
        case .cooldown: return "鼠标已离开，等待暗下..."
        case .dimming: return "平滑变暗中..."
        case .dimmed:
            if preferences.ambientFloor >= 0.999 {
                return "常亮模式 · 屏幕不暗下"
            }
            return "MacBook 处于微光待机"
        case .waking: return "鼠标移回 · 即刻唤醒"
        case .paused: return "调光引擎已暂停"
        case .dormant(let r): return "待机中 (\(r))"
        }
    }

    private var telemetryBadgeText: String {
        switch stateMachine.currentState {
        case .active: return "ACTIVE"
        case .cooldown: return String(format: "%.0fs HOLD", preferences.cooldownDelay)
        case .dimming: return "DIMMING"
        case .dimmed:
            if preferences.ambientFloor >= 0.999 {
                return "100% 恒亮"
            }
            return "\(Int(preferences.ambientFloor * 100))% 微光"
        case .waking: return "WAKING"
        case .paused: return "PAUSED"
        case .dormant: return "STANDBY"
        }
    }

    private var statusGlowColor: Color {
        switch stateMachine.currentState {
        case .active: return .blue
        case .cooldown: return .orange
        case .dimming, .dimmed: return .green
        case .waking: return .purple
        case .paused: return .red
        case .dormant: return .gray
        }
    }

    private var statusBadgeBackground: Color {
        statusGlowColor.opacity(0.18)
    }

    private var statusBadgeForeground: Color {
        statusGlowColor
    }

    private var statusBadgeBorder: Color {
        statusGlowColor.opacity(0.38)
    }
}

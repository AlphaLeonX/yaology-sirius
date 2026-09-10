import SwiftUI

/// 光学精密微光底噪调节杆 (Optical Graticule Slider)
/// 带有精准几何刻度标尺与实时硬件背光预览响应，自适应 macOS 浅色/深色模式
public struct OpticalFloorSlider: View {
    @ObservedObject var preferences = SiriusPreferences.shared
    @State private var isDragging: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶栏：标题与实时背光读数 (固定宽度与等宽数字防抖)
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sun.min.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.accentColor)
                    Text("微光底噪 (变暗程度)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                HStack(spacing: 4) {
                    if isDragging {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                            Text("预览")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.accentColor)
                        }
                    }

                    HStack(spacing: 2) {
                        Text("\(Int(round(preferences.ambientFloor * 100)))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Color.accentColor)

                        if preferences.ambientFloor <= 0.001 {
                            Text("(熄屏)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        } else if preferences.ambientFloor >= 0.999 {
                            Text("(恒亮)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        } else if abs(preferences.ambientFloor - 0.12) < 0.008 {
                            Text("(推荐)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color.accentColor.opacity(0.85))
                        }
                    }
                    .frame(minWidth: 62, alignment: .trailing)
                }
            }

            // 物理滑块
            Slider(
                value: Binding(
                    get: { Double(preferences.ambientFloor) },
                    set: { newValue in
                        let val = Float(newValue)
                        preferences.ambientFloor = val
                        SiriusStateMachine.shared.previewAmbientFloor(value: val)
                    }
                ),
                in: 0.0...1.0,
                step: 0.01,
                onEditingChanged: { editing in
                    self.isDragging = editing
                    if !editing {
                        SiriusStateMachine.shared.endPreviewAmbientFloor()
                    }
                }
            )
            .tint(Color.accentColor)

            // 精密光学几何刻度线 (精确对应物理滑块轨道)
            GeometryReader { geo in
                let thumbInset: CGFloat = 8
                let trackWidth = max(0, geo.size.width - thumbInset * 2)

                ZStack(alignment: .topLeading) {
                    // 标尺基底微线
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: trackWidth, height: 1)
                        .offset(x: thumbInset, y: 0)

                    // 精密刻度锚点：0%(纯黑), 12%(推荐黄金底噪), 25%, 50%, 75%, 100%(恒亮)
                    ForEach([0.0, 0.12, 0.25, 0.50, 0.75, 1.0], id: \.self) { mark in
                        let isDefault = abs(mark - 0.12) < 0.005
                        let isSelected = abs(Double(preferences.ambientFloor) - mark) < 0.012
                        let markX = thumbInset + CGFloat(mark) * trackWidth

                        Rectangle()
                            .fill(isSelected || isDefault ? Color.accentColor : Color.primary.opacity(0.25))
                            .frame(width: isDefault ? 2 : 1, height: isDefault ? 6 : (mark == 0.0 || mark == 1.0 || mark == 0.5 ? 5 : 3))
                            .offset(x: markX - (isDefault ? 1 : 0.5), y: 0)
                    }
                }
            }
            .frame(height: 7)

            // 快捷档位预设胶囊
            HStack(spacing: 5) {
                presetButton(title: "0% 熄屏", value: 0.0)
                presetButton(title: "12% 推荐微光", value: 0.12)
                presetButton(title: "100% 恒亮", value: 1.0)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func presetButton(title: String, value: Float) -> some View {
        let isSelected = abs(preferences.ambientFloor - value) < 0.012
        return Button(action: {
            setFloor(value)
        }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
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
}

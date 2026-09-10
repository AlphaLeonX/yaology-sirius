import AppKit

/// 动态生成符合天狼星双星系统的矢量菜单栏图标
public enum StarIconGenerator {
    /// 渲染天狼星双星图标
    /// - Parameters:
    ///   - isDimmed: 伴星是否处于微光暗化状态
    ///   - isPaused: 系统是否处于暂停状态
    public static func createIcon(isDimmed: Bool = false, isPaused: Bool = false) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.clear(rect)

            // 主星 Sirius A: 中心偏左下 (x: 7.5, y: 9.0, r: 4.2)
            let primaryCenter = CGPoint(x: 7.5, y: 9.0)
            let primaryRadius: CGFloat = 4.2

            // 伴星 Sirius B: 右上方轨道 (x: 15.5, y: 12.0, r: 2.3)
            let companionCenter = CGPoint(x: 15.5, y: 12.0)
            let companionRadius: CGFloat = 2.3

            // 绘制主星 Sirius A
            ctx.addArc(center: primaryCenter, radius: primaryRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // 绘制伴星 Sirius B
            ctx.addArc(center: companionCenter, radius: companionRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            if isPaused {
                // 暂停时伴星仅画轮廓
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
                ctx.setLineWidth(1.2)
                ctx.strokePath()
            } else if isDimmed {
                // 暗光状态时伴星半透明微光 (alpha 0.35)
                ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
                ctx.fillPath()
            } else {
                // 活跃状态两星皆亮
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillPath()
            }

            // 如果暂停，画一条极简斜杠穿过
            if isPaused {
                ctx.move(to: CGPoint(x: 3.5, y: 3.5))
                ctx.addLine(to: CGPoint(x: 18.5, y: 14.5))
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(1.4)
                ctx.strokePath()
            }

            return true
        }
        image.isTemplate = true // 完美自适应 macOS 浅色/深色菜单栏
        return image
    }
}

import Foundation
import CoreGraphics
import AppKit

/// 负责通过 macOS 私有 DisplayServices 框架与物理背光硬件通信
public enum DisplayBridge {
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let dylibHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    private static let getBrightnessFn: GetBrightnessFunc? = {
        guard let handle = dylibHandle,
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessFunc.self)
    }()

    private static let setBrightnessFn: SetBrightnessFunc? = {
        guard let handle = dylibHandle,
              let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetBrightnessFunc.self)
    }()

    /// 获取 MacBook 内建显示屏的 CGDirectDisplayID
    public static func getBuiltinDisplayID() -> CGDirectDisplayID? {
        // 1. 优先从在线 NSScreen 的设备属性中读取
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let id = CGDirectDisplayID(num.uint32Value)
                if CGDisplayIsBuiltin(id) != 0 {
                    return id
                }
            }
        }

        // 2. 备选：从 CoreGraphics 在线显示器列表中遍历
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &activeDisplays, &displayCount) == .success else { return nil }
        for i in 0..<Int(displayCount) {
            let id = activeDisplays[i]
            if CGDisplayIsBuiltin(id) != 0 {
                return id
            }
        }
        return nil
    }

    /// 获取当前物理背光实际亮度 (0.0 ~ 1.0)
    public static func getBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard let fn = getBrightnessFn else { return nil }
        var val: Float = 0
        let status = fn(displayID, &val)
        return status == 0 ? val : nil
    }

    /// 设置物理背光实际亮度 (0.0 ~ 1.0)
    @discardableResult
    public static func setBrightness(displayID: CGDirectDisplayID, brightness: Float) -> Bool {
        guard let fn = setBrightnessFn else { return false }
        let clamped = max(0.0, min(1.0, brightness))
        let status = fn(displayID, clamped)
        return status == 0
    }
}

import Foundation

/// 智能管理 macOS 系统自动亮度（corebrightnessd / ALS）
/// 避免待机微光时，外部环境光线波动导致系统强行调高背光引发频闪
public final class AutoBrightnessManager: @unchecked Sendable {
    public static let shared = AutoBrightnessManager()

    private typealias MsgSendNoArgBool = @convention(c) (AnyObject, Selector) -> Bool
    private typealias MsgSendCopyProperty = @convention(c) (AnyObject, Selector, CFString) -> Unmanaged<CFTypeRef>?
    private typealias MsgSendSetProperty = @convention(c) (AnyObject, Selector, CFTypeRef, CFString) -> Bool

    private let client: AnyObject?
    private var isAlsSupported: Bool = false
    private var savedAutoBrightnessState: Bool?
    private let lock = NSLock()

    private let msgSendCopy: MsgSendCopyProperty?
    private let msgSendSet: MsgSendSetProperty?
    private let msgSendBool: MsgSendNoArgBool?

    private init() {
        // 动态加载 CoreBrightness 私有框架
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)

        if let objcHandle = dlopen("/usr/lib/libobjc.A.dylib", RTLD_LAZY),
           let sym = dlsym(objcHandle, "objc_msgSend") {
            self.msgSendCopy = unsafeBitCast(sym, to: MsgSendCopyProperty.self)
            self.msgSendSet = unsafeBitCast(sym, to: MsgSendSetProperty.self)
            self.msgSendBool = unsafeBitCast(sym, to: MsgSendNoArgBool.self)
        } else {
            self.msgSendCopy = nil
            self.msgSendSet = nil
            self.msgSendBool = nil
        }

        if let clientClass = NSClassFromString("BrightnessSystemClient") as? NSObject.Type {
            let instance = clientClass.init()
            self.client = instance

            let selAls = NSSelectorFromString("isAlsSupported")
            if let msgBool = self.msgSendBool, instance.responds(to: selAls) {
                self.isAlsSupported = msgBool(instance, selAls)
            }
        } else {
            self.client = nil
        }
    }

    /// 查询系统当前是否启用了自动亮度
    public func isAutoBrightnessEnabled() -> Bool {
        guard let client = client, let msgCopy = msgSendCopy else { return false }
        let sel = NSSelectorFromString("copyPropertyForKey:")
        guard client.responds(to: sel) else { return false }

        for key in ["DisplayAutoBrightness", "AutoBrightness"] as [CFString] {
            if let unmanaged = msgCopy(client, sel, key) {
                let val = unmanaged.takeRetainedValue()
                if let num = val as? NSNumber {
                    return num.boolValue
                }
            }
        }
        return false
    }

    /// 设置系统自动亮度开关
    @discardableResult
    public func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        guard let client = client, let msgSet = msgSendSet else { return false }
        let sel = NSSelectorFromString("setProperty:forKey:")
        guard client.responds(to: sel) else { return false }

        let val = (enabled ? kCFBooleanTrue : kCFBooleanFalse)!
        for key in ["DisplayAutoBrightness", "AutoBrightness"] as [CFString] {
            let res = msgSet(client, sel, val, key)
            if res {
                return true
            }
        }
        return false
    }

    /// 在进入暗光前冻结自动亮度，防止环境光突变引发抢占频闪
    public func freezeAutoBrightnessForDimming() {
        lock.lock()
        defer { lock.unlock() }

        guard savedAutoBrightnessState == nil else { return } // 已经处于冻结状态
        let current = isAutoBrightnessEnabled()
        if current {
            savedAutoBrightnessState = true
            setAutoBrightnessEnabled(false)
        } else {
            savedAutoBrightnessState = false
        }
    }

    /// 划入唤醒后，无缝恢复原本的自动亮度配置
    public func restoreAutoBrightnessAfterWaking() {
        lock.lock()
        defer { lock.unlock() }

        guard let originalState = savedAutoBrightnessState else { return }
        if originalState {
            setAutoBrightnessEnabled(true)
        }
        savedAutoBrightnessState = nil
    }
}

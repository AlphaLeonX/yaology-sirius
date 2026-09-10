import Carbon
import Foundation

/// 纯原生 Carbon 全局快捷键管理器（零权限、无需输入监视/辅助功能权限）
public final class HotKeyManager: @unchecked Sendable {
    public static let shared = HotKeyManager()

    public var onHotKeyTriggered: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID: UInt32 = 1001

    private init() {}

    deinit {
        unregister()
    }

    /// 根据用户偏好配置注册当前全局热键
    public func registerConfiguredHotKey() {
        let prefs = SiriusPreferences.shared
        guard prefs.hotKeyEnabled else {
            unregister()
            return
        }
        register(keyCode: prefs.hotKeyCode, modifiers: prefs.hotKeyModifiers)
    }

    /// 注册指定的全局快捷键
    public func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if status == noErr && hotKeyID.id == manager.hotKeyID {
                    DispatchQueue.main.async {
                        manager.onHotKeyTriggered?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else { return }

        let gHotKeyID = EventHotKeyID(signature: OSType(0x53495249), id: hotKeyID) // 'SIRI'
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            gHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus != noErr {
            hotKeyRef = nil
            print("[Sirius] Failed to register HotKey: keyCode=\(keyCode), modifiers=\(modifiers)")
        } else {
            print("[Sirius] HotKey registered: keyCode=\(keyCode), modifiers=\(modifiers)")
        }
    }

    /// 注册默认全局快捷键（⌥ + S）
    public func registerDefaultHotKey() {
        register(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey))
    }

    /// 注销快捷键
    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}

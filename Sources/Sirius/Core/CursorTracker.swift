import AppKit
import Foundation
import CoreGraphics

/// 极低功耗、零权限的光标屏幕归属追踪器
public final class CursorTracker: @unchecked Sendable {
    public typealias CursorChangeHandler = @Sendable (_ isOnBuiltin: Bool, _ screenCount: Int) -> Void

    public var onCursorLocationChanged: CursorChangeHandler?

    private var pollTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.yaology.sirius.cursor-tracker", qos: .utility)
    private var lastIsOnBuiltin: Bool?
    private var lastScreenCount: Int = 0

    public init() {
        // 监听屏幕拓扑变化通知（如插拔外接屏、合盖）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenTopologyChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }

    /// 启动光标监听轮询（100ms 一次，CPU 占用低于 0.01%）
    public func start() {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))

        timer.setEventHandler { [weak self] in
            self?.checkCursorPosition()
        }

        self.pollTimer = timer
        timer.resume()
    }

    /// 停止光标监听
    public func stop() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    @objc private func handleScreenTopologyChange() {
        queue.async { [weak self] in
            self?.checkCursorPosition(forceNotify: true)
        }
    }

    private func checkCursorPosition(forceNotify: Bool = false) {
        // 获取所有在线屏幕
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let screens = NSScreen.screens
            let screenCount = screens.count

            // 直接通过 CoreGraphics 内建检测定位内建屏幕
            let builtinScreen = screens.first(where: { $0.isBuiltinScreen })

            let mousePoint = NSEvent.mouseLocation
            let isOnBuiltin: Bool
            if let bScreen = builtinScreen {
                isOnBuiltin = bScreen.frame.contains(mousePoint)
            } else {
                isOnBuiltin = true
            }

            self.queue.async { [weak self] in
                guard let self = self else { return }
                let stateChanged = (isOnBuiltin != self.lastIsOnBuiltin) || (screenCount != self.lastScreenCount)
                if stateChanged || forceNotify {
                    self.lastIsOnBuiltin = isOnBuiltin
                    self.lastScreenCount = screenCount
                    self.onCursorLocationChanged?(isOnBuiltin, screenCount)
                }
            }
        }
    }
}

extension NSScreen {
    /// 判断当前屏幕是否为 MacBook 内建显示屏
    public var isBuiltinScreen: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
    }
}

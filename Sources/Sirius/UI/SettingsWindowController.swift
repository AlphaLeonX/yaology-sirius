import AppKit
import SwiftUI

/// Sirius 独立偏好设置窗口控制器
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    public private(set) var window: NSWindow?

    private override init() {
        super.init()
    }

    /// 显示并聚焦偏好设置窗口
    public func showSettings() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        win.title = "Sirius 偏好设置"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.contentViewController = hostingController
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        // 关闭时清理引用
        self.window = nil
    }
}

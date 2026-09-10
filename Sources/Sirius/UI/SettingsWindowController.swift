import AppKit
import SwiftUI
import Combine

/// Sirius 独立偏好设置窗口控制器
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    public private(set) var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        SiriusPreferences.shared.$appLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateWindowTitle()
            }
            .store(in: &cancellables)
    }

    private func updateWindowTitle() {
        window?.title = loc("Sirius 偏好设置", "Sirius Preferences")
    }

    /// 显示并聚焦偏好设置窗口
    public func showSettings() {
        if let existing = window {
            updateWindowTitle()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        win.title = loc("Sirius 偏好设置", "Sirius Preferences")
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

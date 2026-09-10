import AppKit
import SwiftUI
import Combine

/// 负责维护 macOS 系统顶部菜单栏状态项与现代悬浮岛交互 (Option B)
public final class MenuBarManager: NSObject {
    public static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var floatingPanel: SiriusFloatingPanel?
    private var cancellables = Set<AnyCancellable>()
    private var globalMouseDownMonitor: Any?

    private override init() {
        super.init()
    }

    /// 弹出或聚焦控制中心悬浮面板（点击 Dock 图标时调用）
    public enum PanelOrigin {
        case centerScreen   // 打开 App 时屏幕窗口正中央
        case statusItem     // 从顶部小图标点击吸附于顶部栏（留出呼吸空间）
    }

    public func showControlPanel() {
        openFloatingPanel(origin: .centerScreen)
    }

    public func setup() {
        if statusItem == nil {
            // 确保有安全默认位置（250pt，靠近右侧控制中心，避免被刘海屏或第三方菜单栏管理工具隐藏）
            UserDefaults.standard.register(defaults: [
                "NSStatusItem Preferred Position Sirius": 250.0,
                "NSStatusItem Visible Sirius": 1
            ])

            // 使用 variableLength 保证随矢量图标尺寸自适应，显式设置 autosaveName 与 isVisible
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "Sirius"
            item.isVisible = true
            self.statusItem = item

            if let button = item.button {
                button.image = StarIconGenerator.createIcon(isDimmed: false, isPaused: false)
                button.imagePosition = .imageOnly
                button.target = self
                button.action = #selector(handleStatusItemClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
        }

        // 初始化现代悬浮岛无三角面板 (Option B)
        if floatingPanel == nil {
            let panel = SiriusFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 440))
            let hostingController = NSHostingController(rootView: TasteSkillPopOverView())
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentViewController = hostingController
            self.floatingPanel = panel

            // 监听面板失去焦点自动关闭
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePanelDidResignKey),
                name: NSWindow.didResignKeyNotification,
                object: panel
            )
        }

        // 订阅状态机变化以更新图标与 Tooltip
        SiriusStateMachine.shared.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateAppearance(for: state)
            }
            .store(in: &cancellables)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        // Option + 点击 或 右键：直接一键切换 暂停/运行
        let isOptionClick = event.modifierFlags.contains(.option)
        let isRightClick = event.type == .rightMouseUp

        if isOptionClick || isRightClick {
            SiriusStateMachine.shared.togglePause()
            return
        }

        // 普通左键点击：展开或收起吸附于顶部栏的悬浮岛面板（留出呼吸空间）
        toggleFloatingPanel(origin: .statusItem)
    }

    public func toggleFloatingPanel(origin: PanelOrigin = .statusItem) {
        guard let panel = floatingPanel else { return }
        if panel.isVisible {
            closeFloatingPanel()
        } else {
            openFloatingPanel(origin: origin)
        }
    }

    public func openFloatingPanel(origin: PanelOrigin = .statusItem) {
        guard let panel = floatingPanel, let hostingView = panel.contentViewController?.view else { return }

        // 1. 获取 SwiftUI 视图真实固有尺寸，确保计算高度与实际渲染严丝合缝
        let fittingSize = hostingView.fittingSize
        let panelWidth: CGFloat = max(300, fittingSize.width)
        let panelHeight: CGFloat = max(420, fittingSize.height)
        let panelSize = NSSize(width: panelWidth, height: panelHeight)

        // 2. 捕捉屏幕
        let mouseLoc = NSEvent.mouseLocation
        let screen: NSScreen
        if origin == .statusItem, let btnWindow = statusItem?.button?.window, let btnScreen = btnWindow.screen {
            screen = btnScreen
        } else {
            screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main ?? NSScreen.screens[0]
        }

        var targetX: CGFloat
        var targetY: CGFloat

        switch origin {
        case .centerScreen:
            // 打开 APP 时：处于屏幕窗口正中央
            targetX = screen.visibleFrame.midX - (panelWidth / 2.0)
            targetY = screen.visibleFrame.midY - (panelHeight / 2.0)

        case .statusItem:
            // 从顶部小图标点击打开：吸附在顶部栏（留出 8pt 呼吸空间）
            let menuBarBottom: CGFloat
            if let button = statusItem?.button, let buttonWindow = button.window {
                let bRect = button.convert(button.bounds, to: nil)
                let sRect = buttonWindow.convertToScreen(bRect)
                menuBarBottom = sRect.minY
                targetX = sRect.midX - (panelWidth / 2.0)
            } else {
                let diff = screen.frame.maxY - screen.visibleFrame.maxY
                menuBarBottom = screen.frame.maxY - (diff > 10 ? diff : 26.0)
                targetX = mouseLoc.x - (panelWidth / 2.0)
            }

            // 吸附在顶部状态栏正下方，留出 8pt 黄金呼吸空隙
            targetY = menuBarBottom - panelHeight - 8.0

            // 屏幕边缘防溢出
            targetX = max(screen.frame.minX + 10, min(targetX, screen.frame.maxX - panelWidth - 10))
        }

        panel.setFrame(NSRect(origin: CGPoint(x: targetX, y: targetY), size: panelSize), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        setupClickOutsideMonitor()
    }

    public func closeFloatingPanel() {
        guard let panel = floatingPanel, panel.isVisible else { return }
        removeClickOutsideMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    @objc private func handlePanelDidResignKey(_ notification: Notification) {
        // 如果正在录制快捷键或正在显示设置，不强行关闭
        DispatchQueue.main.async { [weak self] in
            self?.closeFloatingPanel()
        }
    }

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.floatingPanel, panel.isVisible else { return }
            let mouseLoc = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLoc) {
                if let button = self.statusItem?.button, let buttonWin = button.window {
                    let bRect = buttonWin.convertToScreen(button.convert(button.bounds, to: nil))
                    if bRect.contains(mouseLoc) {
                        return
                    }
                }
                DispatchQueue.main.async {
                    self.closeFloatingPanel()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = globalMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseDownMonitor = nil
        }
    }

    private func updateAppearance(for state: SiriusStateMachine.State) {
        guard let button = statusItem?.button else { return }

        let isDimmed: Bool
        let isPaused: Bool

        switch state {
        case .dimmed:
            isDimmed = true
            isPaused = false
        case .paused:
            isDimmed = false
            isPaused = true
        default:
            isDimmed = false
            isPaused = false
        }

        button.image = StarIconGenerator.createIcon(isDimmed: isDimmed, isPaused: isPaused)
        button.toolTip = "\(loc("Sirius (天狼星双星调光 · v1.2.0)", "Sirius (Dual-Display Dimmer · v1.2.0)"))\n\(state.localizedDescription)\n\(loc("⌥-点击可快速暂停/恢复", "⌥-Click to pause or resume"))"
    }
}

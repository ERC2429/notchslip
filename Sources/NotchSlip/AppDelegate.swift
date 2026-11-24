import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var statusItem: NSStatusItem?
    private let hotKey = HotKeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[NotchSlip] didFinishLaunching")
        buildMainMenu()

        guard let geometry = NotchGeometry.current() else {
            let alert = NSAlert()
            alert.messageText = "NotchSlip 无法启动"
            alert.informativeText = "没有找到可用的屏幕。"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let controller = PanelController(geometry: geometry)
        self.controller = controller
        installStatusItem()

        hotKey.onTrigger = { [weak self] in self?.controller?.showAndFocus() }
        hotKey.register()

        controller.renderSnapshotIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu bar icon

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "NotchSlip") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "N"
            }
            button.toolTip = "NotchSlip — 鼠标移到刘海可展开"
        }

        let menu = NSMenu()
        menu.addItem(makeItem("打开记事本", #selector(openNotepad)))
        menu.addItem(makeItem("在 Finder 中显示笔记", #selector(revealNotes)))
        menu.addItem(.separator())

        let login = makeItem("开机时启动", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(makeItem("退出 NotchSlip", #selector(quitApp), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openNotepad() {
        controller?.showAndFocus()
    }

    @objc private func revealNotes() {
        guard let url = controller?.notesURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.toggle(sender)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - App menu

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "关于 NotchSlip",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "退出 NotchSlip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")

        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = main
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Toggles the login item and keeps the menu item's checkmark in sync.
    /// Shared by the menu bar menu and the panel's right-click menu.
    static func toggle(_ item: NSMenuItem) {
        let enable = item.state != .on
        do {
            try set(enabled: enable)
            item.state = enable ? .on : .off
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = enable ? "无法开启开机启动" : "无法关闭开机启动"
            alert.informativeText = "把 NotchSlip.app 放到「应用程序」文件夹后再试。\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
}

import AppKit

final class PanelController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    enum State {
        case collapsed, expanding, expanded, collapsing
    }

    let panel: NotchPanel
    let card: EditorCard
    let store = NotesStore()

    private var geo: NotchGeometry
    private var panelSize: NSSize
    private var host: HostView
    private var state: State = .collapsed

    private var ticker: Timer?
    private var hideWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var lastKeyAt = Date.distantPast
    private var isResizing = false
    private var resizeStartSize: NSSize?
    private var holdOpen = false
    /// True while a context menu is tracking: the mouse legitimately leaves the
    /// panel to reach the menu, so auto-hiding must pause.
    private var menuOpen = false

    private var lastExternalApp: NSRunningApplication?
    private let debug = ProcessInfo.processInfo.environment["NOTCHSLIP_DEBUG"] != nil
    private var tickCount = 0
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    var notesURL: URL { store.url }

    init(geometry: NotchGeometry) {
        geo = geometry
        panelSize = PanelController.storedSize(for: geometry)
        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        card = EditorCard(frame: NSRect(origin: .zero, size: panelSize))
        host = HostView(card: card, cardSize: panelSize)
        super.init()
        configure()
    }

    deinit {
        ticker?.invalidate()
        NotificationCenter.default.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSMenu.didEndTrackingNotification, object: nil)
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - Setup

    private func configure() {
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.acceptsMouseMovedEvents = false
        panel.contentView = host
        panel.initialFirstResponder = card.textView
        panel.ignoresMouseEvents = true

        // Must be the last level-related setting: isFloatingPanel/other options
        // reset the level. Above the menu bar (24) and status items (25), so the
        // black strip reads as the notch widening instead of icons on top.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        card.topBarHeight = geo.topInset
        card.onResizeBegan = { [weak self] in self?.beginResize() }
        card.onResize = { [weak self] dx, dy in self?.applyResize(dx, dy) }
        card.onResizeEnded = { [weak self] in self?.endResize() }
        card.onEscape = { [weak self] in self?.collapse() }
        card.onKey = { [weak self] in self?.lastKeyAt = Date() }
        card.textView.delegate = self
        card.menu = appContextMenu()

        // Pause auto-hide while a menu is tracking. The mouse has to leave the
        // panel to reach the menu, which would otherwise collapse it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )

        card.textView.string = store.load()
        card.updatePlaceholder()

        panel.setFrame(geo.notch, display: false)
        panel.orderOut(nil)
        if debug {
            print("[NotchSlip] notch=\(geo.notch) topInset=\(geo.topInset) size=\(panelSize) screen=\(geo.screen.frame)")
        }

        lastExternalApp = NSWorkspace.shared.frontmostApplication
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            self.lastExternalApp = app
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenParametersChanged()
        }

        _ = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Notch hover detection"
        )
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: - Geometry

    private var expandedFrame: NSRect {
        NSRect(
            x: geo.notch.midX - panelSize.width / 2,
            y: geo.screenTop - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    /// Hover target when collapsed: the notch itself, a little wider and a few
    /// points taller so approaching it from below still counts as touching it.
    private var hoverZone: NSRect {
        let width = geo.notch.width + 30
        return NSRect(
            x: geo.notch.midX - width / 2,
            y: geo.notch.minY - 6,
            width: width,
            height: geo.notch.height + 6
        )
    }

    /// Mouse is "still inside" a little outside the panel, to avoid flicker at the edges.
    private var hitZone: NSRect {
        expandedFrame.insetBy(dx: -10, dy: -10)
    }

    private var topBarFrame: NSRect {
        NSRect(
            x: expandedFrame.minX,
            y: geo.notch.minY,
            width: panelSize.width,
            height: geo.topInset
        )
    }

    // MARK: - Context menu

    private enum MenuTag {
        static let app = 0x4E53 // 'NS'
    }

    /// Right-click menu on the panel. This is the reliable quit path: macOS parks
    /// status-bar items under the notch when the menu bar runs out of room, so the
    /// pencil icon is not always reachable.
    private func appContextMenu() -> NSMenu {
        let menu = NSMenu()
        appMenuItems().forEach { menu.addItem($0) }
        return menu
    }

    private func appMenuItems() -> [NSMenuItem] {
        let reveal = NSMenuItem(
            title: "在 Finder 中显示笔记",
            action: #selector(revealNotes),
            keyEquivalent: ""
        )
        reveal.target = self
        reveal.tag = MenuTag.app

        let login = NSMenuItem(
            title: "开机时启动",
            action: #selector(toggleLoginItem(_:)),
            keyEquivalent: ""
        )
        login.target = self
        login.tag = MenuTag.app
        login.state = LoginItem.isEnabled ? .on : .off

        let quit = NSMenuItem(
            title: "退出 NotchSlip",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        quit.tag = MenuTag.app

        return [reveal, login, quit]
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        // AppKit may reuse its default menu; only append our items once.
        guard !menu.items.contains(where: { $0.tag == MenuTag.app }) else { return menu }
        menu.addItem(.separator())
        appMenuItems().forEach { menu.addItem($0) }
        return menu
    }

    @objc private func revealNotes() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        LoginItem.toggle(sender)
    }

    @objc private func quitApp() {
        saveNow()
        NSApp.terminate(nil)
    }

    @objc private func menuDidBeginTracking() { menuOpen = true }
    @objc private func menuDidEndTracking() { menuOpen = false }

    // MARK: - Hover tracking

    private func tick() {
        let mouse = NSEvent.mouseLocation
        if debug {
            tickCount += 1
            if tickCount % 30 == 0 {
                print("[NotchSlip] tick mouse=\(mouse) state=\(state) hover=\(hoverZone.contains(mouse))")
            }
        }
        switch state {
        case .collapsed:
            if hoverZone.contains(mouse) {
                expand()
            }
        case .expanded:
            guard !menuOpen else { return }
            if holdOpen {
                if hitZone.contains(mouse) { holdOpen = false }
                return
            }
            guard !isResizing else { return }
            if hitZone.contains(mouse) {
                cancelHide()
            } else if hideWork == nil {
                scheduleHide(after: 0.15)
            }
        case .expanding, .collapsing:
            break
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .expanded else { return }
            self.hideWork = nil
            if self.menuOpen { return }
            if self.holdOpen { return }
            if self.hitZone.contains(NSEvent.mouseLocation) { return }

            // Typing grace: while keys are coming in, let the note finish itself.
            let typing = self.panel.isKeyWindow && Date().timeIntervalSince(self.lastKeyAt) < 1.5
            if typing {
                self.scheduleHide(after: 0.25)
                return
            }
            self.collapse()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    // MARK: - Show / hide

    func expand() {
        guard state == .collapsed || state == .collapsing else { return }
        cancelHide()
        state = .expanding
        lastKeyAt = .distantPast

        host.cardSize = panelSize
        host.needsLayout = true

        // Width jumps instantly while the panel is still 32pt tall (invisible
        // against the notch), then only the height animates: no text reflow.
        panel.setFrame(topBarFrame, display: false)
        panel.ignoresMouseEvents = false
        panel.orderFront(nil)
        panel.displayIfNeeded()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.05
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(expandedFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.state == .expanding else { return }
            self.state = .expanded
            print("[NotchSlip] expanded")
        })
    }

    func collapse() {
        guard state == .expanded || state == .expanding else { return }
        cancelHide()
        saveNow()
        state = .collapsing
        holdOpen = false
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.05
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(topBarFrame, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.state == .collapsing else { return }
            // The bar is invisible against the notch, so just snap and disappear.
            self.panel.setFrame(self.geo.notch, display: false)
            self.panel.orderOut(nil)
            self.state = .collapsed
            self.restoreFocus()
            print("[NotchSlip] collapsed")
        })
    }

    /// Open from the menu bar or the global hotkey, and take keyboard focus.
    func showAndFocus() {
        guard state != .collapsing else { return }
        if state == .collapsed {
            holdOpen = true
            expand()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.makeFirstResponder(self.card.textView)
            let length = (self.card.textView.string as NSString).length
            self.card.textView.setSelectedRange(NSRange(location: length, length: 0))
            self.card.textView.scrollRangeToVisible(NSRange(location: length, length: 0))
        }
    }

    private func restoreFocus() {
        guard NSApp.isActive else { return }
        guard let app = lastExternalApp, !app.isTerminated else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        app.activate(options: [])
    }

    // MARK: - Resize

    private func beginResize() {
        isResizing = true
        resizeStartSize = panelSize
        cancelHide()
    }

    private func applyResize(_ dx: CGFloat, _ dy: CGFloat) {
        guard let start = resizeStartSize else { return }
        let maxWidth = min(geo.screen.frame.width - 80, 720)
        let maxHeight = geo.screen.frame.height - 120
        var width = start.width + dx * 2
        var height = start.height - dy
        width = min(max(width, 280), maxWidth)
        height = min(max(height, 150), maxHeight)
        applySize(NSSize(width: round(width), height: round(height)))
    }

    private func applySize(_ size: NSSize) {
        panelSize = size
        host.cardSize = size
        panel.setFrame(expandedFrame, display: false)
        card.needsDisplay = true
        panel.displayIfNeeded()
    }

    private func endResize() {
        isResizing = false
        resizeStartSize = nil
        let defaults = UserDefaults.standard
        defaults.set(Double(panelSize.width), forKey: "panelWidth")
        defaults.set(Double(panelSize.height), forKey: "panelHeight")
        print("[NotchSlip] resized \(Int(panelSize.width))x\(Int(panelSize.height))")
    }

    private static func storedSize(for geometry: NotchGeometry) -> NSSize {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.double(forKey: "panelWidth")
        let storedHeight = defaults.double(forKey: "panelHeight")
        let width = storedWidth > 0 ? storedWidth : 408
        let height = storedHeight > 0 ? storedHeight : 295
        let maxWidth = min(geometry.screen.frame.width - 80, 720)
        let maxHeight = geometry.screen.frame.height - 120
        return NSSize(
            width: min(max(width, 280), maxWidth),
            height: min(max(height, 150), maxHeight)
        )
    }

    // MARK: - Saving

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        store.save(card.textView.string)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWork = nil
            self.store.save(self.card.textView.string)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func textDidChange(_ notification: Notification) {
        card.updatePlaceholder()
        scheduleSave()
    }

    // MARK: - Window / screen events

    func windowDidResignKey(_ notification: Notification) {
        guard state == .expanded, !isResizing else { return }
        collapse()
    }

    private func screenParametersChanged() {
        guard let geometry = NotchGeometry.current() else { return }
        geo = geometry
        card.topBarHeight = geometry.topInset
        panelSize = PanelController.storedSize(for: geometry)
        host.cardSize = panelSize
        if state == .expanded || state == .expanding {
            panel.setFrame(expandedFrame, display: true)
        } else {
            panel.setFrame(geometry.notch, display: false)
            panel.orderOut(nil)
            state = .collapsed
        }
    }


    // MARK: - Offscreen render (verification aid)

    func renderSnapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["NOTCHSLIP_RENDER"] else { return }
        holdOpen = true
        state = .expanded
        panel.ignoresMouseEvents = true
        panel.setFrame(expandedFrame, display: true)
        panel.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let view = self.panel.contentView else { return }
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                    print("[NotchSlip] snapshot \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
                }
            } else {
                print("[NotchSlip] snapshot failed")
            }
            NSApp.terminate(nil)
        }
    }
}
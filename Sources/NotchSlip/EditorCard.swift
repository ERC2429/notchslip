import AppKit

/// Rounded black card that hosts the text editor and the resize grip.
/// Only the two bottom corners are rounded: the top edge is flush with the
/// screen's top edge and visually merges with the notch.
final class EditorCard: NSView {
    let textView = KeyTextView(frame: .zero)
    let scrollView = NSScrollView()
    private let grip = ResizeGrip(frame: .zero)
    private let placeholder = PassThroughLabel(labelWithString: "写点什么…")

    var topBarHeight: CGFloat = 32 {
        didSet { if oldValue != topBarHeight { needsLayout = true } }
    }

    var onResizeBegan: (() -> Void)?
    var onResize: ((CGFloat, CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?
    var onEscape: (() -> Void)?
    var onKey: (() -> Void)?

    private let font = NSFont.systemFont(ofSize: 15.5, weight: .regular)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupText()
        setupPlaceholder()
        setupGrip()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    /// A window resize only repaints what AppKit thinks is new. Because the card
    /// is pinned to the top edge, its old border used to survive as ghost
    /// outlines — repaint the whole card on every size change instead.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    // MARK: - Setup

    private func setupText() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        let tv = textView
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = NSColor.clear
        tv.textColor = NSColor(white: 0.93, alpha: 1)
        tv.insertionPointColor = NSColor(white: 0.95, alpha: 1)
        tv.font = font

        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 5.5
        ps.paragraphSpacing = 0
        ps.lineBreakMode = .byWordWrapping
        tv.defaultParagraphStyle = ps

        tv.textContainerInset = NSSize(width: 16, height: 12)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize.zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = NSView.AutoresizingMask.width
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true

        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.usesFindBar = false

        tv.onEscape = { [weak self] in self?.onEscape?() }
        tv.onAnyKey = { [weak self] in self?.onKey?() }
        tv.onQuit = { NSApp.terminate(nil) }

        tv.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        scrollView.documentView = tv
        addSubview(scrollView)
    }

    private func setupPlaceholder() {
        placeholder.font = font
        placeholder.textColor = NSColor(white: 1, alpha: 0.22)
        placeholder.isEditable = false
        placeholder.isSelectable = false
        addSubview(placeholder)
    }

    private func setupGrip() {
        grip.onBegan = { [weak self] in self?.onResizeBegan?() }
        grip.onDrag = { [weak self] dx, dy in self?.onResize?(dx, dy) }
        grip.onEnded = { [weak self] in self?.onResizeEnded?() }
        addSubview(grip)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let textHeight = max(0, h - topBarHeight)

        scrollView.frame = NSRect(x: 0, y: 0, width: w, height: textHeight)
        grip.frame = NSRect(x: w - 26, y: 0, width: 26, height: 26)

        let contentSize = scrollView.contentSize
        var f = textView.frame
        var changed = false
        if f.width != contentSize.width {
            f.size.width = contentSize.width
            changed = true
        }
        if f.height < contentSize.height {
            f.size.height = contentSize.height
            changed = true
        }
        if changed { textView.frame = f }

        placeholder.sizeToFit()
        placeholder.frame.origin = NSPoint(
            x: 16,
            y: h - topBarHeight - 12 - placeholder.frame.height + 1
        )
    }

    func updatePlaceholder() {
        placeholder.isHidden = !textView.string.isEmpty
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 18
        let b = bounds
        let path = NSBezierPath()
        path.move(to: NSPoint(x: b.minX, y: b.maxY))
        path.line(to: NSPoint(x: b.maxX, y: b.maxY))
        path.line(to: NSPoint(x: b.maxX, y: b.minY + radius))
        path.appendArc(
            withCenter: NSPoint(x: b.maxX - radius, y: b.minY + radius),
            radius: radius, startAngle: 0, endAngle: -90, clockwise: true
        )
        path.line(to: NSPoint(x: b.minX + radius, y: b.minY))
        path.appendArc(
            withCenter: NSPoint(x: b.minX + radius, y: b.minY + radius),
            radius: radius, startAngle: 270, endAngle: 180, clockwise: true
        )
        path.close()

        NSColor.black.setFill()
        path.fill()

        NSColor(white: 1, alpha: 0.07).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Label that never intercepts mouse events, so clicking the empty editor still
/// lands on the text view.
final class PassThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The little grip in the bottom-right corner. Drag it to resize the panel.
final class ResizeGrip: NSView {
    var onBegan: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onEnded: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        NSColor(white: 1, alpha: 0.30).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineCapStyle = .round
        for i in 0..<2 {
            let offset = CGFloat(5 + i * 5)
            path.move(to: NSPoint(x: bounds.maxX - 3, y: offset))
            path.line(to: NSPoint(x: offset, y: bounds.maxY - 3))
        }
        path.stroke()
    }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onBegan?()
        var last = NSEvent.mouseLocation
        var total = NSPoint.zero
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let now = NSEvent.mouseLocation
            total.x += now.x - last.x
            total.y += now.y - last.y
            last = now
            onDrag?(total.x, total.y)
        }
        onEnded?()
    }
}

/// Text view that reports key presses (for the typing grace period) and Esc.
final class KeyTextView: NSTextView {
    var onEscape: (() -> Void)?
    var onAnyKey: (() -> Void)?
    var onQuit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // ⌘Q is a second quit path: the menu bar icon can be hidden by macOS
        // when the bar is crowded, so quitting must not depend on it.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "q" {
            onQuit?()
            return
        }
        onAnyKey?()
        if event.keyCode == 53 { // Esc
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// The panel appears on hover without activating; the first click should
    /// still place the caret instead of only activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        super.mouseDown(with: event)
    }
}

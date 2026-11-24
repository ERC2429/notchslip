import AppKit

/// Borderless panel that can become key (needed for typing) but never main.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit normally pushes windows below the menu bar. This panel has to sit
    /// at the very top of the screen, merged with the notch, so opt out.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The panel's content view. Its subview (`card`) keeps a fixed size while the
/// window animates, so text never re-wraps during expand/collapse. The card is
/// pinned to the top edge and horizontally centred, and gets clipped by the window.
final class HostView: NSView {
    let card: EditorCard
    var cardSize: NSSize {
        didSet {
            if oldValue != cardSize { needsLayout = true }
        }
    }

    init(card: EditorCard, cardSize: NSSize) {
        self.card = card
        self.cardSize = cardSize
        super.init(frame: NSRect(origin: .zero, size: cardSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        card.frame = NSRect(origin: .zero, size: cardSize)
        addSubview(card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        card.frame = NSRect(
            x: round((bounds.width - cardSize.width) / 2),
            y: bounds.height - cardSize.height,
            width: cardSize.width,
            height: cardSize.height
        )
    }
}
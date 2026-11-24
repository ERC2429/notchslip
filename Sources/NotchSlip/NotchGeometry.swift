import AppKit

/// Where the notch is, in global screen coordinates (origin bottom-left).
struct NotchGeometry {
    let screen: NSScreen
    /// The physical notch rect. Its top edge is the top edge of the screen.
    let notch: NSRect
    /// Height of the menu bar strip, i.e. the notch height.
    let topInset: CGFloat

    var screenTop: CGFloat { screen.frame.maxY }

    static func current() -> NotchGeometry? {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? NSScreen.main ?? NSScreen.screens.first else { return nil }

        let frame = screen.frame
        let inset = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
        var x = frame.midX - 90
        var width: CGFloat = 180

        // The two areas beside the camera housing give us the exact notch width.
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            x = left.maxX
            width = right.minX - left.maxX
        }

        let notch = NSRect(x: x, y: frame.maxY - inset, width: width, height: inset)
        return NotchGeometry(screen: screen, notch: notch, topInset: inset)
    }
}
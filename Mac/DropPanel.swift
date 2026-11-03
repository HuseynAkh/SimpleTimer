import AppKit

/// A borderless drop-down under the menu bar. It is placed once and never attached to the status item,
/// so a menu bar manager hiding the item again cannot move it. Tiling window managers leave it alone:
/// it is a non-activating panel in an app with no Dock icon.
final class DropPanel: NSPanel {
    var onClose: (() -> Void)?
    var onSpace: (() -> Void)?
    /// Content changes grow the panel down from this edge instead of up into the menu bar.
    private var top: CGFloat?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Pop-up menu level also tells Ice and Thaw that a revealed item has opened something.
        isFloatingPanel = true; level = .popUpMenu; hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false; backgroundColor = .clear; hasShadow = true; isMovable = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); onClose?() }
    override func cancelOperation(_ sender: Any?) { onClose?() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Esc closes even while the name field is editing. Space acts unless text is being typed.
            if event.keyCode == 53 { onClose?(); return }
            if event.keyCode == 49, !(firstResponder is NSText), event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                if !event.isARepeat { onSpace?() }
                return
            }
        }
        super.sendEvent(event)
    }
    func place(_ frame: CGRect) { top = frame.maxY; setFrame(frame, display: false) }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let top { frame.origin.y = top - frame.height }
        super.setFrame(frame, display: flag); invalidateShadow()
    }
}

/// One display's menu bar, reduced to the geometry the panel needs.
struct MenuBarScreen {
    var frame: CGRect
    var visible: CGRect
    var barHeight: CGFloat
    var notch: CGRect?
}
extension MenuBarScreen {
    init(_ screen: NSScreen) {
        frame = screen.frame; visible = screen.visibleFrame
        // The visible frame excludes a shown menu bar. When it hides (automatically or in full screen), use its usual height.
        let reserved = frame.maxY - visible.maxY
        barHeight = reserved > 0 ? reserved : max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX {
            let local = !frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: left.midX, y: left.midY))
            notch = CGRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
                .offsetBy(dx: local ? frame.minX : 0, dy: local ? frame.minY : 0)
        }
    }
    func contains(_ point: CGPoint) -> Bool { frame.insetBy(dx: -1, dy: -1).contains(point) }
    /// A visible status item sits along the top of the screen, clear of the camera housing. Ice, Thaw and
    /// Bartender hide items by pushing them off screen, and macOS drops items that don't fit behind the notch.
    func shows(_ item: CGRect) -> Bool {
        item.width > 0 && frame.insetBy(dx: -1, dy: -1).contains(item) && item.maxY >= frame.maxY - 2
            && (notch.map { $0.intersection(item).width < 1 } ?? true)
    }
}

enum PanelPlacement {
    static let gap: CGFloat = 6, margin: CGFloat = 8
    /// Under the status item when it is visible on the pointer's screen. Otherwise (hidden by a manager, behind
    /// the notch, an auto-hidden menu bar, or macOS 27 reporting a mirrored item on another display) under the
    /// menu bar at the pointer. Either way the panel stays inside that screen's visible frame.
    static func frame(size: CGSize, item: CGRect?, mouse: CGPoint, screens: [MenuBarScreen]) -> CGRect {
        guard let screen = screens.first(where: { $0.contains(mouse) }) ?? screens.first else { return CGRect(origin: mouse, size: size) }
        let anchor = item.flatMap { screen.shows($0) ? $0 : nil }
        let bar = screen.frame.maxY - screen.barHeight
        let top = min(anchor?.minY ?? bar, bar) - gap
        let x = (anchor?.midX ?? mouse.x) - size.width / 2
        let left = min(max(x, screen.visible.minX + margin), screen.visible.maxX - size.width - margin)
        return CGRect(x: left, y: max(top - size.height, screen.visible.minY), width: size.width, height: size.height)
    }
}

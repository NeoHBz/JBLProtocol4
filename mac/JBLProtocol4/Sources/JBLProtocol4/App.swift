import SwiftUI
import Combine
import JBLKit

/// Plain AppKit entry point. A SwiftUI `App` needs at least one scene, and recent macOS opens even an empty
/// `Settings` scene as a blank window; a menu bar app has no window, so it skips the SwiftUI lifecycle entirely.
@main
enum JBLProtocol4App {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Menu bar icon plus the A1 panel. Click the icon to open, click it again (or anywhere else, or press Esc) to close.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let device = Device()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: Panel?
    private var outsideClick: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "JBL Protocol4")
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(toggle)

        // While released for the phone, the last reading stays up; it is minutes old at most when the panel was in use.
        Publishers.CombineLatest3(device.$link, device.$battery, device.$showPercent)
            .receive(on: RunLoop.main)
            .sink { [weak button] link, battery, show in
                let live = link == .ready || link == .released
                button?.title = (show && live ? battery.map { " \($0)%" } : nil) ?? ""
            }
            .store(in: &cancellables)
    }


    @objc private func toggle() {
        panel == nil ? open() : close()
    }

    private func open() {
        let icon = iconFrame()
        let screen = item.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let right = min(max(icon.maxX, screen.minX + Theme.width + 6), screen.maxX - 6)
        let p = Panel(device: device, topRight: NSPoint(x: right, y: icon.minY - 4))
        p.onEscape = { [weak self] in self?.close() }
        panel = p
        device.panelOpened()
        p.makeKeyAndOrderFront(nil)
        // Nothing focused at first; the first Tab lands on the noise control.
        DispatchQueue.main.async { p.makeFirstResponder(nil) }

        // The status icon belongs to a system process, so a click on it also arrives here; leave that one to toggle().
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.iconFrame().insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }
    }

    private func close() {
        guard let p = panel else { return }
        p.orderOut(nil)
        panel = nil
        device.panelClosed()
        if let m = outsideClick { NSEvent.removeMonitor(m) }
        outsideClick = nil
    }

    private func iconFrame() -> NSRect {
        guard let b = item.button, let w = b.window else { return .zero }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }
}

/// Borderless glass panel hanging from a fixed top-right corner.
///
/// How it avoids jumping when "More settings" folds: the SwiftUI view lives in a tall canvas pinned to the top of a
/// clipping card. The window only changes how much of that canvas shows, so the content never moves. The window
/// animates its height with the same curve and duration SwiftUI uses for the rows, so the bottom edge follows them.
final class Panel: NSPanel {
    var onEscape: (() -> Void)?
    private let topRight: NSPoint
    private static let canvasHeight: CGFloat = 2000

    init(device: Device, topRight: NSPoint) {
        self.topRight = topRight
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Natural height of the collapsed panel, so the first frame on screen is already the right size.
        let startHeight = NSHostingView(rootView: PanelView().environmentObject(device)).fittingSize.height
        let bounds = NSRect(x: 0, y: 0, width: Theme.width, height: startHeight)

        let clip = NSView(frame: bounds)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = Theme.corner
        clip.layer?.masksToBounds = true
        clip.autoresizingMask = [.width, .height]

        var setHeight: (CGFloat) -> Void = { _ in }
        let canvas = NSHostingView(rootView:
            PanelView(onHeight: { setHeight($0) })
                .environmentObject(device)
                .frame(width: Theme.width, height: Self.canvasHeight, alignment: .top)
        )
        canvas.sizingOptions = []
        canvas.frame = NSRect(x: 0, y: startHeight - Self.canvasHeight, width: Theme.width, height: Self.canvasHeight)
        canvas.autoresizingMask = [.minYMargin]   // glued to the top edge while the window resizes
        clip.addSubview(canvas)

        contentView = Self.glass(around: clip, frame: bounds)
        setFrame(NSRect(x: topRight.x - Theme.width, y: topRight.y - startHeight, width: Theme.width, height: startHeight), display: false)

        // The height arrives in the middle of SwiftUI's layout pass; resizing the window there makes AppKit move the
        // window now and its contents later. Start the resize right after the pass instead.
        setHeight = { [weak self] h in DispatchQueue.main.async { self?.fit(height: h) } }
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// Liquid Glass on macOS 26 and later, the classic translucent popover material before that.
    private static func glass(around content: NSView, frame: NSRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = Theme.corner
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView(frame: frame)
        blur.material = .popover
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Theme.corner
        blur.layer?.masksToBounds = true
        blur.addSubview(content)
        return blur
    }

    /// Animate to `height`, keeping the top-right corner fixed.
    private func fit(height: CGFloat) {
        guard height > 0, abs(frame.height - height) > 0.5 else { return }
        let target = NSRect(x: topRight.x - Theme.width, y: topRight.y - height, width: Theme.width, height: height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.foldDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(target, display: true)
        }
    }
}

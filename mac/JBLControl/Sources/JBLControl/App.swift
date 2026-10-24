import SwiftUI
import Combine
import JBLKit

@main
struct JBLControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
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
        button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "JBL Control")
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(toggle)

        Publishers.CombineLatest(device.$link, device.$battery)
            .receive(on: RunLoop.main)
            .sink { [weak button] link, battery in
                button?.title = (link == .ready ? battery.map { " \($0)%" } : nil) ?? ""
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
        panel?.orderOut(nil)
        panel = nil
        if let m = outsideClick { NSEvent.removeMonitor(m) }
        outsideClick = nil
    }

    private func iconFrame() -> NSRect {
        guard let b = item.button, let w = b.window else { return .zero }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }
}

/// Borderless panel hanging from a fixed top-right corner.
///
/// How it avoids jumping when "More settings" folds: the SwiftUI view lives in a tall canvas pinned to the top of a
/// clipping card. The window only changes how much of that canvas shows, so the content never moves; at worst, for
/// one frame, the bottom edge is a little short or long.
final class Panel: NSPanel {
    var onEscape: (() -> Void)?
    private let topRight: NSPoint
    private var card: NSView!
    private var canvas: NSView!
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

        let card = NSView(frame: NSRect(x: 0, y: 0, width: Theme.width, height: startHeight))
        card.wantsLayer = true
        card.layer?.cornerRadius = Theme.corner
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1

        var setHeight: (CGFloat) -> Void = { _ in }
        let canvas = NSHostingView(rootView:
            PanelView(onHeight: { setHeight($0) })
                .environmentObject(device)
                .frame(width: Theme.width, height: Self.canvasHeight, alignment: .top)
                .background(Theme.pop)
        )
        canvas.sizingOptions = []
        canvas.frame = NSRect(x: 0, y: card.bounds.height - Self.canvasHeight, width: Theme.width, height: Self.canvasHeight)
        card.addSubview(canvas)
        contentView = card
        self.card = card
        self.canvas = canvas

        setFrame(NSRect(x: topRight.x - Theme.width, y: topRight.y - startHeight, width: Theme.width, height: startHeight), display: false)
        // The height arrives in the middle of SwiftUI's layout pass; resizing there makes AppKit move the window now and
        // its contents later. Resize right after the pass instead, window and contents together.
        setHeight = { [weak self] h in DispatchQueue.main.async { self?.fit(height: h) } }
        updateBorder()
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    private func updateBorder() {
        contentView?.layer?.borderColor = NSColor(Theme.line).cgColor
    }

    /// Resize to `height`, keeping the top-right corner fixed.
    private func fit(height: CGFloat) {
        guard height > 0, abs(frame.height - height) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            setFrame(NSRect(x: topRight.x - Theme.width, y: topRight.y - height, width: Theme.width, height: height), display: false)
            card.frame = NSRect(x: 0, y: 0, width: Theme.width, height: height)
            canvas.frame.origin.y = height - Self.canvasHeight   // canvas top = card top
            card.display()
        }
    }
}

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

/// Borderless window that can take keyboard focus (Tab, arrows) and closes on Esc.
final class PanelWindow: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Owns the menu bar item and its panel. Not MenuBarExtra (its panel closes itself when the icon is clicked, then the
/// same click reopens it) and not NSPopover (it resizes badly when "More settings" folds). The panel is a plain window
/// whose top edge stays under the icon while its height follows the content.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let device = Device()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: PanelWindow?
    private var outsideClick: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "JBL Control")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
        }
        Publishers.CombineLatest(device.$link, device.$battery)
            .receive(on: RunLoop.main)
            .sink { [weak self] link, battery in
                guard let button = self?.item.button else { return }
                button.title = (link == .ready ? battery.map { " \($0)%" } : nil) ?? ""
            }
            .store(in: &cancellables)
    }

    @objc private func toggle() {
        panel == nil ? open() : close()
    }

    private func open() {
        // A fresh panel each time, so "More settings" always starts collapsed.
        let host = NSHostingController(rootView: PanelView(onHeight: { [weak self] h in
            MainActor.assumeIsolated { self?.resize(height: h) }   // same frame as the layout change, no hop
        }).environmentObject(device))
        host.sizingOptions = []
        let size = host.sizeThatFits(in: NSSize(width: 320, height: 0))   // zero height: the panel answers with its natural height
        host.view.frame.size = size

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: background.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let w = PanelWindow(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.contentView = background
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .popUpMenu
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.onEscape = { [weak self] in self?.close() }
        panel = w

        place(w, size: size)
        w.makeKeyAndOrderFront(nil)
        // Start with nothing focused; the first Tab then lands on the first control (ANC).
        DispatchQueue.main.async { w.makeFirstResponder(nil) }

        // The menu bar icon is drawn by the system, so its clicks look like "another app" too: skip them here and let toggle() close.
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.iconContains(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }
    }

    /// Top edge just under the icon, right edge level with the icon's right edge, kept on screen.
    private func place(_ w: NSWindow, size: NSSize) {
        guard let b = item.button, let bw = b.window else { return }
        let icon = bw.convertToScreen(b.convert(b.bounds, to: nil))
        let screen = bw.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(icon.maxX - size.width, screen.minX + 6), screen.maxX - size.width - 6)
        let top = icon.minY - 4
        w.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true, animate: false)
    }

    private func resize(height: CGFloat) {
        guard let w = panel, height > 0, abs(w.frame.height - height) > 0.5 else { return }
        // Keep the top-right corner where it is; only the bottom edge moves.
        let f = w.frame
        w.setFrame(NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height), display: true, animate: false)
    }

    private func iconContains(_ p: NSPoint) -> Bool {
        guard let b = item.button, let w = b.window else { return false }
        return w.convertToScreen(b.convert(b.bounds, to: nil)).insetBy(dx: -4, dy: -4).contains(p)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        if let m = outsideClick { NSEvent.removeMonitor(m); outsideClick = nil }
    }
}

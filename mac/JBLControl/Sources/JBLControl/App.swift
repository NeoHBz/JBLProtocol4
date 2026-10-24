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

/// Owns the menu bar item and its panel. SwiftUI's MenuBarExtra could not be used here: its panel closes itself the
/// moment the icon is clicked (the click takes focus away), and the same click then reopens it, so the second click
/// never closed anything. Here the icon click toggles, and only clicks in other apps close the panel by themselves.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let device = Device()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var outsideClick: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PanelView().environmentObject(device))

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
        popover.isShown ? close() : open()
    }

    private func open() {
        guard let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        window?.makeKey()
        // Start with nothing focused; the first Tab then lands on the first control (ANC).
        DispatchQueue.main.async { window?.makeFirstResponder(nil) }
        // Clicks inside this app (including on the icon) never reach a global monitor, so the icon's own action stays in charge.
        // The menu bar icon is drawn by the system, so its clicks look like "another app" too: skip them here and let toggle() close.
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.iconContains(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }
    }

    private func iconContains(_ p: NSPoint) -> Bool {
        guard let b = item.button, let w = b.window else { return false }
        return w.convertToScreen(b.convert(b.bounds, to: nil)).insetBy(dx: -4, dy: -4).contains(p)
    }

    private func close() {
        popover.performClose(nil)
        if let m = outsideClick { NSEvent.removeMonitor(m); outsideClick = nil }
    }
}

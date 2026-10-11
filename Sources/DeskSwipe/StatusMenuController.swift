import AppKit
import Combine
import DeskSwipeCore

/// The menu bar icon and its menu. Rebuilt every time it opens so the status
/// lines are always current.
final class StatusMenuController: NSObject, NSMenuDelegate {
    var onOpenSettings: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: AppSettings
    private let status: SystemStatus
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, status: SystemStatus) {
        self.settings = settings
        self.status = status
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Keep the icon in sync with state that matters at a glance.
        settings.$enabled.combineLatest(status.$accessibilityGranted)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, granted in self?.updateIcon(enabled: enabled, granted: granted) }
            .store(in: &cancellables)
    }

    private func updateIcon(enabled: Bool, granted: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = granted ? "macwindow.on.rectangle" : "exclamationmark.triangle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DeskSwipe")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !enabled
        button.toolTip = granted ? "DeskSwipe" : "DeskSwipe: Accessibility permission needed"
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        status.refreshAccessibility()
        status.refreshConflicts()
        menu.removeAllItems()

        // Accessibility status line.
        if status.accessibilityGranted {
            menu.addItem(info("Accessibility: granted", symbol: "checkmark.circle"))
        } else {
            let item = action("Accessibility permission needed — Open Settings…",
                              #selector(openAccessibility), symbol: "exclamationmark.triangle")
            menu.addItem(item)
        }

        // Gesture input status.
        if let error = status.multitouchError {
            menu.addItem(info("Gesture input unavailable: \(error)", symbol: "exclamationmark.triangle"))
        } else if status.trackpadCount == 0 {
            menu.addItem(info("No trackpad detected", symbol: "exclamationmark.triangle"))
        }

        for conflict in status.conflicts {
            menu.addItem(action("\(conflict.summary) — Fix…", #selector(showConflictHelp(_:)),
                                symbol: "exclamationmark.triangle", represented: conflict))
        }

        if status.hiddenWindowCount > 0 {
            let n = status.hiddenWindowCount
            menu.addItem(info("\(n) window\(n == 1 ? "" : "s") hidden by DeskSwipe", symbol: nil))
        }

        menu.addItem(.separator())

        let enabledItem = action("Enabled", #selector(toggleEnabled))
        enabledItem.state = settings.enabled ? .on : .off
        menu.addItem(enabledItem)

        let settingsItem = action("Settings…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit DeskSwipe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openAccessibility() {
        status.requestAccessibilityIfNeeded()
        SystemStatus.openAccessibilitySettings()
    }

    @objc private func showConflictHelp(_ sender: NSMenuItem) {
        guard let conflict = sender.representedObject as? GestureConflict else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = conflict.summary
        alert.informativeText = """
            macOS and DeskSwipe would both react to the same three-finger swipe.

            \(conflict.fix)
            """
        if conflict == .systemThreeFingerSwipe {
            alert.addButton(withTitle: "Open Trackpad Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                SystemStatus.openTrackpadSettings()
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: Helpers

    private func info(_ title: String, symbol: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func action(_ title: String, _ selector: Selector, symbol: String? = nil, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }
}

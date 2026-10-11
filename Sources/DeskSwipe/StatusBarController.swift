import AppKit
import Combine
import DeskSwipeCore

/// The menu bar icon. Clicking it opens a popover panel with status and a
/// toggle per feature.
final class StatusBarController: NSObject {
    var onOpenSettings: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let panel: StatusPanelViewController
    private let status: SystemStatus
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, status: SystemStatus) {
        self.status = status
        panel = StatusPanelViewController(settings: settings, status: status)
        super.init()

        popover.behavior = .transient
        popover.contentViewController = panel
        panel.onOpenSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.onOpenSettings?()
        }
        panel.onDismiss = { [weak self] in self?.popover.performClose(nil) }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

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

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        status.refreshAccessibility()
        status.refreshConflicts()
        panel.reload()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

// MARK: - Panel

/// Content of the popover: header, status card, feature toggles, footer.
final class StatusPanelViewController: NSViewController {
    var onOpenSettings: (() -> Void)?
    var onDismiss: (() -> Void)?

    private static let width: CGFloat = 320
    private static let inset: CGFloat = 16

    private let settings: AppSettings
    private let status: SystemStatus
    private let stack = NSStackView()
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, status: SystemStatus) {
        self.settings = settings
        self.status = status
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        view = root

        // Rebuild on any change; objectWillChange fires before the new value
        // is stored, so hop to the next run loop turn first.
        settings.objectWillChange.merge(with: status.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.reload() }
            .store(in: &cancellables)
        reload()
    }

    func reload() {
        guard isViewLoaded else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        add(header(), spacingAfter: 14)
        add(sectionTitle("Status"))
        add(card(statusRows()), spacingAfter: 14)
        add(sectionTitle("Features", trailing: featureCount()))
        add(card([showDesktopRow()]), spacingAfter: 14)
        add(footer())

        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    // MARK: Sections

    private func header() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let title = label("DeskSwipe", size: 15, weight: .semibold)
        let subtitle = label("Trackpad gestures for your windows", size: 11, color: .secondaryLabelColor)
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let row = NSStackView(views: [icon, text])
        row.spacing = 10
        return row
    }

    private func statusRows() -> [NSView] {
        var rows: [NSView] = []

        if status.accessibilityGranted {
            rows.append(row(symbol: "checkmark.shield.fill", tint: .systemGreen,
                            title: "Accessibility", subtitle: "Permission granted"))
        } else {
            rows.append(row(symbol: "exclamationmark.shield.fill", tint: .systemOrange,
                            title: "Accessibility needed", subtitle: "Required to minimize windows",
                            accessory: button("Grant…", action: #selector(openAccessibility))))
        }

        if let error = status.multitouchError {
            rows.append(row(symbol: "exclamationmark.triangle.fill", tint: .systemOrange,
                            title: "Gesture input unavailable", subtitle: error))
        } else if status.trackpadCount == 0 {
            rows.append(row(symbol: "exclamationmark.triangle.fill", tint: .systemOrange,
                            title: "No trackpad detected", subtitle: "Connect a trackpad to use gestures"))
        } else {
            let n = status.trackpadCount
            rows.append(row(symbol: "hand.point.up.left.fill", tint: .systemGreen,
                            title: "Trackpad", subtitle: n == 1 ? "1 trackpad connected" : "\(n) trackpads connected"))
        }

        for conflict in status.conflicts {
            let fix = button("Fix…", action: #selector(showConflictHelp(_:)))
            fix.tag = GestureConflict.allCases.firstIndex(of: conflict) ?? 0
            rows.append(row(symbol: "exclamationmark.triangle.fill", tint: .systemOrange,
                            title: "Gesture conflict", subtitle: conflict.summary, accessory: fix))
        }
        return rows
    }

    private func featureCount() -> String {
        settings.enabled ? "1/1" : "0/1"
    }

    private func showDesktopRow() -> NSView {
        let toggle = NSSwitch()
        toggle.state = settings.enabled ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleShowDesktop(_:))
        toggle.setAccessibilityLabel("Swipe to Show Desktop")

        let hidden = status.hiddenWindowCount
        let subtitle: String
        if hidden > 0 {
            subtitle = "\(hidden) window\(hidden == 1 ? "" : "s") hidden · swipe \(settings.invertDirection ? "down" : "up") to restore"
        } else if settings.invertDirection {
            subtitle = "3 fingers up hides all windows, down restores"
        } else {
            subtitle = "3 fingers down hides all windows, up restores"
        }
        return row(symbol: "macwindow.on.rectangle",
                   tint: settings.enabled ? .controlAccentColor : .secondaryLabelColor,
                   title: "Swipe to Show Desktop", subtitle: subtitle, accessory: toggle)
    }

    private func footer() -> NSView {
        let settingsButton = footerButton("Settings", symbol: "gearshape", action: #selector(openSettings))
        settingsButton.keyEquivalent = ","
        settingsButton.keyEquivalentModifierMask = .command

        let quitButton = footerButton("Quit", symbol: "power", action: #selector(quit))
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = .command

        let row = NSStackView(views: [settingsButton, quitButton])
        row.distribution = .fillEqually
        row.spacing = 10
        return row
    }

    // MARK: Actions

    @objc private func toggleShowDesktop(_ sender: NSSwitch) {
        settings.enabled = sender.state == .on
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openAccessibility() {
        onDismiss?()
        status.requestAccessibilityIfNeeded()
        SystemStatus.openAccessibilitySettings()
    }

    @objc private func showConflictHelp(_ sender: NSButton) {
        guard GestureConflict.allCases.indices.contains(sender.tag) else { return }
        let conflict = GestureConflict.allCases[sender.tag]
        onDismiss?()
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

    // MARK: Building blocks

    /// Adds a full-width arranged subview.
    private func add(_ view: NSView, spacingAfter spacing: CGFloat? = nil) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.inset).isActive = true
        if let spacing { stack.setCustomSpacing(spacing, after: view) }
    }

    private func sectionTitle(_ text: String, trailing: String? = nil) -> NSView {
        let title = label(text.uppercased(), size: 11, weight: .semibold, color: .secondaryLabelColor)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [title, spacer]
        if let trailing {
            views.append(label(trailing, size: 11, weight: .semibold, color: .controlAccentColor))
        }
        let row = NSStackView(views: views)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return row
    }

    private func card(_ rows: [NSView]) -> NSView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 4
        content.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        let rowWidth = Self.width - 2 * Self.inset - 24
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                content.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            }
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
        }
        return CardView(content: content)
    }

    private func row(symbol: String, tint: NSColor, title: String, subtitle: String?, accessory: NSView? = nil) -> NSView {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage())
        icon.contentTintColor = tint
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = label(title, size: 13, weight: .semibold)
        var textViews: [NSView] = [titleLabel]
        if let subtitle {
            let sub = label(subtitle, size: 11, color: .secondaryLabelColor)
            sub.maximumNumberOfLines = 2
            sub.lineBreakMode = .byWordWrapping
            sub.preferredMaxLayoutWidth = accessory == nil ? 230 : 170
            textViews.append(sub)
        }
        let text = NSStackView(views: textViews)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [icon, text]
        if let accessory {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(accessory)
        }
        let row = NSStackView(views: views)
        row.distribution = .fill
        row.spacing = 10
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        return row
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isSelectable = false
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .push
        button.controlSize = .small
        return button
    }

    private func footerButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .push
        button.controlSize = .large
        return button
    }
}

/// Rounded, subtly filled container that follows light/dark appearance.
private final class CardView: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.5
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // Dynamic colors resolve against the current appearance here.
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

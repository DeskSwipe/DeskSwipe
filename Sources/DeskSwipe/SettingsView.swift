import AppKit
import DeskSwipeCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var status: SystemStatus

    /// Higher sensitivity = shorter swipe. Maps onto the threshold range inverted.
    private var sensitivity: Binding<Double> {
        let range = AppSettings.thresholdRange
        return Binding(
            get: { range.upperBound + range.lowerBound - settings.threshold },
            set: { settings.threshold = range.upperBound + range.lowerBound - $0 }
        )
    }

    var body: some View {
        Form {
            Section("Gestures") {
                Toggle("Enabled", isOn: $settings.enabled)

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: sensitivity, in: AppSettings.thresholdRange) {
                        Text("Sensitivity")
                    } minimumValueLabel: {
                        Text("Low")
                    } maximumValueLabel: {
                        Text("High")
                    }
                    Text("Swipe about \(Int((settings.threshold * 100).rounded()))% of the trackpad height to trigger.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Invert direction", isOn: $settings.invertDirection)
                Text(settings.invertDirection
                     ? "Swipe up to show the desktop, swipe down to restore."
                     : "Swipe down to show the desktop, swipe up to restore.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { status.launchAtLogin },
                    set: { status.setLaunchAtLogin($0) }
                ))
                if status.launchAtLoginNeedsApproval {
                    HStack {
                        Text("Approve DeskSwipe in Login Items to finish.")
                            .font(.caption)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = status.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Status") {
                if status.accessibilityGranted {
                    Label("Accessibility permission granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Accessibility permission missing", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("DeskSwipe needs it to minimize and restore windows. Enable DeskSwipe under Privacy & Security > Accessibility.")
                            .font(.caption)
                        Button("Open Accessibility Settings") { SystemStatus.openAccessibilitySettings() }
                    }
                }

                if let error = status.multitouchError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label(status.trackpadCount == 0
                          ? "No trackpad detected"
                          : "Trackpads detected: \(status.trackpadCount)",
                          systemImage: "hand.point.up.left")
                }

                ForEach(status.conflicts, id: \.self) { conflict in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(conflict.summary, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(conflict.fix).font(.caption)
                        if conflict == .systemThreeFingerSwipe {
                            Button("Open Trackpad Settings") { SystemStatus.openTrackpadSettings() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hosts `SettingsView` in a plain AppKit window.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let status: SystemStatus

    init(settings: AppSettings, status: SystemStatus) {
        self.status = status
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, status: status))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "DeskSwipe Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        status.refreshAll()
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // The user may have just changed System Settings.
        status.refreshAll()
    }
}

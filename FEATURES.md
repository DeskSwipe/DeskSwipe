# DeskSwipe: Features & Capabilities

Living record of what DeskSwipe can do, what it relies on, and what's next.
Update it in the same commit as any feature change.

**Status legend:** ✅ Shipped · 🚧 In progress · 💡 Idea · ❌ Dropped

---

## Features

Each feature gets a row in the menu bar panel's **Features** card with its own on/off switch.

| Feature | Status | Since | Trigger | Panel toggle | Settings |
|---|---|---|---|---|---|
| [Swipe to Show Desktop](#swipe-to-show-desktop) | ✅ | 1.0.0 | 3-finger swipe down / up | **Swipe to Show Desktop** (`enabled`) | Sensitivity, Invert direction |

### Swipe to Show Desktop

Windows-style "show desktop" on the trackpad.

- **Swipe down (3 fingers):** minimizes every window of every regular app on the current Space, and remembers exactly which windows it minimized.
- **Swipe up (3 fingers):** restores only those windows. Windows you minimized yourself stay minimized.
- **Repeated swipe down:** merges newly minimized windows into the remembered list; never overwrites it.
- **Dock thumbnail click** restores one window (macOS behavior). DeskSwipe notices and forgets that window.
- **Manual restore, window closed, or app quit:** the window is dropped from the list quietly.
- **Restore order:** back to front, so the window that was in front ends up in front.
- **Skipped:** full-screen windows, floating panels, windows without a minimize control, DeskSwipe's own windows.

| Setting | Key (UserDefaults) | Default | Range |
|---|---|---|---|
| Enabled | `enabled` | `true` | on/off |
| Sensitivity (swipe distance) | `swipeThreshold` | `0.18` (18% of trackpad height) | 0.08–0.40 |
| Invert direction | `invertDirection` | `false` | on/off |

**Gesture rules:** exactly 3 fingers; vertical travel within 0.6 s ≥ threshold; vertical > 1.5× horizontal; fires once per gesture; a gesture that ever reaches 4+ fingers is ignored until all fingers lift.

**Code:** `SwipeRecognizer` and `ShowDesktopController` (DeskSwipeCore, unit tested); `WindowManager` and `MultitouchService` (app).

---

## App capabilities

| Capability | Status | Notes |
|---|---|---|
| Menu bar app, no Dock icon | ✅ | `LSUIElement = true` |
| Status panel (popover) | ✅ | Status card, feature toggles, Settings / Quit |
| Settings window | ✅ | SwiftUI; sensitivity, invert, launch at login, status |
| Launch at login | ✅ | `SMAppService.mainApp`; may need approval in Login Items |
| Accessibility permission flow | ✅ | Prompts on launch, polls until granted, **Grant…** button |
| Conflicting-gesture detection | ✅ | Warns if macOS 3-finger swipes or three-finger drag are on |
| Trackpad hot-plug | ✅ | Re-enumerates on connect/disconnect and after wake |
| Multiple trackpads | ✅ | One recognizer per device |
| App icon | ✅ | `Resources/AppIcon.svg` → `scripts/make-icon.sh` |
| Stable code signature | ✅ | `scripts/setup-signing.sh`, so permissions survive rebuilds |

## Platform & permissions

| Requirement | Why |
|---|---|
| macOS 14+, Apple Silicon | Build target |
| Accessibility permission | Minimize/restore other apps' windows (AXUIElement) |
| Private `MultitouchSupport` framework | Raw trackpad touches; loaded at runtime with `dlopen` |
| No Screen Recording permission needed | Window order uses owner PIDs only |

## Known limits

- **Current Space only.** The Accessibility API only sees windows on the active Space.
- **Full-screen windows** cannot be minimized; they are skipped.
- **Private framework:** a macOS update could break gesture input. The panel then shows "Gesture input unavailable".
- **System gestures:** macOS's own 3-finger swipes must be moved to 4 fingers or turned off.
- The auto-hiding Dock doesn't reveal while the panel is open. This is the same as Apple's Wi-Fi and Battery panels.

---

## Ideas / backlog

Add ideas here as 💡. Move to 🚧 when work starts, then into **Features** when shipped.

| Idea | Status | Notes |
|---|---|---|
| _(add yours)_ | 💡 | |

---

## Adding a new feature: checklist

1. **Core logic** in `Sources/DeskSwipeCore/` as a pure, testable type, with tests in `Tests/DeskSwipeCoreTests/`.
2. **Setting** in `AppSettings` (a UserDefaults key with a registered default) for its on/off switch and any options.
3. **Panel row:** add a row to the Features card in `StatusPanelViewController` (`StatusBarController.swift`) with an `NSSwitch`, and update the `x/y` count in `featureCount()`.
4. **Settings UI** (if it has options) in `SettingsView.swift`.
5. **Docs:** a row in the Features table and a section above; README if setup changes.
6. `./build.sh` (runs tests), then reinstall.

## Changelog

| Version | Date | Changes |
|---|---|---|
| 1.0.0 | 2026-10-11 | Swipe to Show Desktop; status panel with feature toggles; settings window; app icon; stable local signing |

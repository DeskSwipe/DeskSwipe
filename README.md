# DeskSwipe

Windows-style "show desktop" for macOS, driven by trackpad gestures.

- **3-finger swipe down**: minimize every window of every regular app, and remember exactly which windows this swipe minimized.
- **3-finger swipe up**: restore only those windows. Windows you minimized yourself stay minimized.
- After swiping down, clicking a window's Dock thumbnail restores just that window (standard macOS behavior). DeskSwipe notices and forgets that window.

DeskSwipe is a menu bar app with no Dock icon. It is free to build and run with Apple's Command Line Tools, and has no third-party dependencies.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon
- Xcode **or** just the Command Line Tools (`xcode-select --install`), with Swift 5.10 or newer
- A built-in trackpad or Magic Trackpad

## Build

```sh
./build.sh
```

This runs the unit tests, builds a release binary for arm64, assembles `build/DeskSwipe.app` with its `Info.plist` (`LSUIElement = true`), and ad-hoc signs it with `codesign -s -`. Set `SKIP_TESTS=1` to skip the tests.

Install and launch:

```sh
ditto build/DeskSwipe.app /Applications/DeskSwipe.app
open /Applications/DeskSwipe.app
```

For development:

```sh
swift build
swift test
swift run DeskSwipe     # runs unbundled; prefer the .app for real use
```

## First-run setup

### 1. Accessibility permission (required)

DeskSwipe minimizes and restores windows through the Accessibility API. On first launch macOS shows a prompt:

1. Click **Open System Settings**, or use the menu bar item **Accessibility permission needed — Open Settings…**.
2. In **Privacy & Security > Accessibility**, switch on **DeskSwipe**.

The menu's first line shows whether permission is granted. DeskSwipe checks every couple of seconds and picks up the change without a restart.

### 2. Move macOS's own 3-finger swipes out of the way (strongly recommended)

By default macOS uses 3-finger swipe up/down for Mission Control and App Exposé, so both would fire at once. DeskSwipe detects this and shows a warning in the menu and in Settings. To fix it:

**System Settings > Trackpad > More Gestures**: set **Mission Control** and **App Exposé** to **Swipe Up/Down with Four Fingers**, or **Off**.

If you use **three-finger drag** (System Settings > Accessibility > Pointer Control > Trackpad Options), it also turns 3-finger movement into drags. DeskSwipe warns about that too.

DeskSwipe does not change these settings for you.

## Settings

Open from the menu bar: **Settings…**

| Setting | What it does |
|---|---|
| Enabled | Turns gesture handling on or off (also in the menu). |
| Sensitivity | How far you must swipe: from ~40% of trackpad height (Low) to ~8% (High). The default is 18%. |
| Invert direction | Swipe up to show the desktop, swipe down to restore. |
| Launch at login | Registers the app with `SMAppService.mainApp`. macOS may ask you to approve it under General > Login Items. |

Settings are stored in UserDefaults (`defaults read local.deskswipe.DeskSwipe`).

## How gestures are recognized

A swipe fires **once per gesture**, when all of these hold:

- exactly 3 fingers are on the surface;
- vertical travel within the last 0.6 s reaches the sensitivity threshold;
- vertical travel is more than 1.5× horizontal travel.

Lifting fingers or changing the finger count starts a new gesture. If a gesture ever reaches 4+ fingers, it is ignored until every finger has lifted. Slow drift never fires, because travel is measured over a short sliding window.

## Known limits

- **Current Space only.** The Accessibility API only reports windows on the active Space, so DeskSwipe minimizes (and later restores) only those. Windows on other Spaces are left alone. This is by design.
- **Full-screen windows are skipped.** macOS cannot minimize them this way. The same goes for floating panels and windows without a minimize control.
- **Only regular apps** (apps with a Dock icon) are affected. DeskSwipe never touches its own windows.
- **Private framework.** Trackpad input comes from Apple's private `MultitouchSupport` framework, loaded at runtime. A future macOS update could change or remove it. If that happens, the menu shows "Gesture input unavailable" and the app keeps running.
- Swiping down again while windows are still hidden adds the new windows to the remembered list; the next swipe up restores all of them.
- Restore order: windows come back in their original stacking order as far as possible, with the frontmost last.

## Troubleshooting

**Nothing happens when I swipe.**
- Check the menu: is Accessibility **granted**? Is **Enabled** checked? Is a trackpad detected?
- **After every rebuild**, macOS may treat the ad-hoc-signed app as a new app, and the old Accessibility entry stops working even though it still looks enabled. Remove DeskSwipe from the list with **−** and add it again, or reset it:
  ```sh
  tccutil reset Accessibility local.deskswipe.DeskSwipe
  ```
  Then relaunch DeskSwipe and grant permission again.
- Try a higher sensitivity in Settings.

**Mission Control / App Exposé opens as well.** See *First-run setup, step 2*.

**Gestures stop after connecting a Magic Trackpad, or after sleep.** DeskSwipe re-enumerates devices about a second after a trackpad connects or disconnects, and after wake. If gestures still don't work, toggle **Enabled**, or quit and relaunch.

**Some windows were not minimized.** They may be full screen, on another Space, a floating panel, or in an app that doesn't respond to Accessibility requests (DeskSwipe waits at most 1 s per request).

**A window I restored by hand came back minimized/restored unexpectedly.** It shouldn't: restoring a window yourself (Dock thumbnail, Cmd-Tab, etc.) removes it from DeskSwipe's list. If you can reproduce this, please capture logs (below).

**Launch at login doesn't stick.** Approve DeskSwipe in **System Settings > General > Login Items**. Keep the app in one place (e.g. `/Applications`); moving it breaks the registration.

**Logs.**

```sh
/usr/bin/log stream --info --predicate 'subsystem == "DeskSwipe"'
```

(Use the full path `/usr/bin/log`, because zsh has a built-in `log` command.)

**`swift test` fails with "plugin for module 'TestingMacros' not found".** Some Command Line Tools releases don't pass the Swift Testing macro plugin path to every compile step. `Package.swift` adds it automatically when `/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` exists. If your tools live elsewhere, pass it yourself:
`swift test -Xswiftc -plugin-path -Xswiftc <toolchain>/usr/lib/swift/host/plugins/testing`.

## Project layout

```
Sources/DeskSwipeCore/          Pure logic, unit tested
  SwipeRecognizer.swift         Frames -> .swipeDown / .swipeUp
  MTTouch.swift                 Typed 96-byte MTTouch struct + frame reduction
  ShowDesktopController.swift   Which windows we minimized; merge/forget/restore
  GestureConflicts.swift        Detects conflicting system gesture settings
Sources/DeskSwipe/              The app
  MultitouchService.swift       dlopen/dlsym MultitouchSupport, hot-plug, wake
  WindowManager.swift           AXUIElement backend, AXObservers, app-quit cleanup
  StatusMenuController.swift    Menu bar item and menu
  SettingsView.swift            SwiftUI settings window
  AppSettings.swift             UserDefaults-backed preferences
  SystemStatus.swift            Accessibility, conflicts, devices, login item
  AppDelegate.swift, main.swift
Tests/DeskSwipeCoreTests/       Swift Testing suites
Resources/Info.plist
build.sh
reference/main.swift            Original single-file prototype
```

## Uninstall

Quit DeskSwipe from its menu, turn off Launch at login first if you enabled it, then:

```sh
rm -rf /Applications/DeskSwipe.app
defaults delete local.deskswipe.DeskSwipe
tccutil reset Accessibility local.deskswipe.DeskSwipe
```

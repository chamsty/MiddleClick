# Contributing to MiddleClick

Thanks for your interest in contributing! This project is maintained in spare time, so community help is genuinely appreciated.

## What's valued most

Working code. A pull request that fixes a bug or implements a feature is worth more than any amount of discussion. If you see an open issue you'd like to tackle — go for it.

## Getting started

### Prerequisites

- Xcode with Command Line Tools
- Optional: `brew bundle` to install [SwiftLint](https://github.com/realm/SwiftLint) (runs as a build phase; if missing, the build just warns)

### Build & run

```sh
make run
```

This builds in Debug mode and launches the app, killing any running instance first.

### Logs

MiddleClick uses `os_log`. To see logs in real time:

```sh
log stream --predicate 'subsystem == "art.ginzburg.MiddleClick"' --style compact --level debug
```

See [docs/dev.md](./docs/dev.md) for filtering by category.

## Project structure

```
MiddleClick/
  main.swift              — Entry point
  Controller.swift        — Lifecycle: start, restart on wake/device changes, session handling
  Controller+Mouse.swift  — Mouse event (click) callback
  TouchHandler.swift      — Multitouch callback: finger counting, tap detection, middle-click emulation
  Config.swift            — User defaults (fingers, maxTimeDelta, etc.)
  TrayMenu.swift          — Status bar menu UI
  FingerCountControl.swift — The finger count stepper in the menu
  SystemPermissions.swift — Reading system trackpad settings
  GlobalState.swift       — Shared state between touch and mouse callbacks
  Helpers/
    CGEventController.swift     — CGEvent tap for mouse events
    IOMultitouchManager.swift   — Listens for multitouch device connect/disconnect
    AccessibilityMonitor.swift  — Accessibility permission monitoring
MoreTouch/                — Swift package wrapping the private MultitouchSupport framework
  Sources/MultitouchSupport/MultitouchSupport.h  — C header for Apple's private multitouch API
  Sources/MoreTouchCore/Core.swift               — Swift extensions on MTDevice
ConfigCore/               — Swift package for the @UserDefault property wrapper
```

### How it works (briefly)

1. `TouchHandler` registers a callback on every connected multitouch device (`MTDevice`).
2. When fingers touch the surface, the callback tracks finger count, positions, and timing.
3. If the touch matches the configured gesture (N fingers, within time/distance thresholds), it emits a `CGEvent` middle-click.
4. `Controller+Mouse` handles the click-based path (as opposed to tap-based) using a `CGEvent` tap.

## Pull request guidelines

- Keep changes focused. One fix or feature per PR.
- Test on your hardware. State what you tested on (trackpad? Magic Mouse? macOS version?) in the PR description.
- Keep SwiftLint happy. If you install it via `brew bundle`, it runs automatically during builds.
- Don't bump the version number — that's done at release time.

## Attaching a test build to your PR

Since this project lacks regular Magic Mouse testers (and sometimes trackpad testers with specific macOS versions), attaching a build to your PR lets reviewers try your change without cloning and compiling. Strongly encouraged for UI or hardware-dependent changes.

```sh
# 1. Build
make build-debug

# 2. Ask Xcode where it put the .app
APP="$(xcodebuild -project MiddleClick.xcodeproj -scheme MiddleClick -configuration Debug -showBuildSettings 2>/dev/null | awk -F ' = ' '/ BUILT_PRODUCTS_DIR =/ {print $2}')/MiddleClick.app"

# 3. Zip it into the repo's build/ dir
mkdir -p build && ditto -c -k --keepParent "$APP" build/MiddleClick-test.zip
```

Then drag `build/MiddleClick-test.zip` into the PR comment field on GitHub and link testers to [#running-a-test-build](#running-a-test-build).

## Running a test build

> This section is for testers trying a build attached to a PR.

Debug builds aren't signed with a distribution certificate, so macOS Gatekeeper will block them. After unzipping the attached archive:

```sh
# Remove the quarantine attribute, then run
xattr -cr MiddleClick.app
open MiddleClick.app
```

Grant Accessibility permission to this specific build in System Settings → Privacy & Security → Accessibility. If you already have a production MiddleClick installed, quit it first.

## Don't have a Magic Mouse?

Neither does the maintainer. If you're implementing something you can't fully test, open a draft PR, attach a test build (see above), and note what needs verification — other contributors with the hardware can pitch in.

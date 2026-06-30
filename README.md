# ScrollDolmeng

ScrollDolmeng is a macOS utility experiment for turning a trackpad gesture plus modifier-key trigger into synthetic scroll events.

The packaged app display name is `울트라돌멩의원핑거스크롤`.

## What It Does

- Listens to multitouch trackpad movement through macOS private MultitouchSupport APIs
- Converts the latest one-finger movement snapshot into synthetic scroll events
- Lets the user tune scroll gain, direction, trigger keys, and menu bar visibility
- Keeps a small preferences UI for trigger and direction settings
- Includes focused tests for scroll physics, modifier-key matching, lifecycle state, and settings migration

## Why It Exists

The project explores whether a lightweight local macOS utility can make trackpad scrolling feel more direct and customizable without becoming a large productivity app.

It is not a polished App Store product. It is a local-first macOS utility prototype that requires the usual Accessibility/Input Monitoring permissions for this class of tool.

## Tech

- Swift Package Manager
- AppKit
- CoreGraphics event taps
- Private `MultitouchSupport` framework bridge
- Swift Testing

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Package Local App

```bash
./scripts/build_app.sh
```

The script builds a local `.app` bundle into `dist/`, strips common Finder/iCloud metadata, and ad-hoc signs the bundle for local launch.

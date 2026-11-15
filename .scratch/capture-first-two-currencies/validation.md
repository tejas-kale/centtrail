# Integration validation

Branch: `capture-first-two-currencies`.

The owner approved these local Markdown tickets as the tracker. Completed criteria are checked in each ticket. Device-only criteria remain unchecked until observed on a device.

## Baseline

Before implementation: 96 Ledger-target tests and 6 Shell-target tests passed using:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --skip appleFoundationModelLiveSmokeAndTimingWhenAvailable
```

Log: `/private/tmp/centtrail-capture-baseline.log`.

## Environment limits

Simulator discovery (`xcrun simctl list devices available`, with Xcode selected) returned no devices. iPhone Air Action button, Lock Screen, Siri, microphone behavior and visual Dynamic Type/dark-mode checks require device validation. Build validation does not establish those outcomes.

## Final checks

Pending integration completion.

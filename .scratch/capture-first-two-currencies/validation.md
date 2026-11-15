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

## Platform build setup

Ask-removal integration iOS app build passed using Xcode destination-based SDK selection:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Apps/Centtrail.xcodeproj -scheme CenttrailIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath build/v2-ios -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
```

Log: `/private/tmp/centtrail-capture-ios-destination.log`. Omit the explicit `-sdk iphonesimulator` argument: it incorrectly forces third-party macro executables to target iOS rather than their Mac host.

## Final checks

All 13 tickets are implemented on `capture-first-two-currencies` (with tickets `08`, `09`, `10`, `11`, `13` pending device/manual verification).

- `xcode swift test`: 117 `LedgerTests` + 13 `SystemEntryPointsTests` passed (130 total).
- `xcode xcodebuild -project Apps/Centtrail.xcodeproj -scheme CenttrailIOS -destination "generic/platform=iOS Simulator" -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED**.
- `xcode xcodebuild -project Apps/Centtrail.xcodeproj -scheme CenttrailMac -destination "platform=macOS" -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED** (verified).
- Code review (Standards + Spec): 2 Spec Review bugs fixed in `b4b215f` (INR Siri confirmation formatting; hiding empty EUR total on Home) along with missing Ticket 06 (`received_amount_cents`, `transfers_with_rate`).

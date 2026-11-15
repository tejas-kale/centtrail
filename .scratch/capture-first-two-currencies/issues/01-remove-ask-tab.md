# 01: Remove the Ask tab and report interpreter

**What to build:** The app no longer has an Ask tab. On-device natural-language reporting is removed: the report half of the Interpreter (operation selection, question periods, report follow-ups) goes, while capture parsing stays and still works with Apple's on-device model or the keyword fallback. This is a prefactor that shrinks Home, Reports and the Interpreter before they are reshaped. Spec: `../spec.md`.

**Blocked by:** None (can start immediately)

**Status:** complete

- [x] The tab bar / Mac sidebar has no Ask destination, on iPhone and Mac.
- [x] Report-interpretation code and its tests (Ask chat, Ask evaluation, report follow-up, question period) are deleted.
- [x] Voice capture still fills the capture form; the existing voice capture tests pass.
- [x] Ledger report calculations still used by Home remain and their tests pass.
- [x] The package builds for iOS and macOS with no unused Interpreter report types left.

Validation: macOS package tests passed (81 Ledger/Interpreter and 6 Shell tests). iOS app build passed with destination-based SDK selection; explicit `-sdk iphonesimulator` incorrectly targeted third-party macro executables at iOS. Log: `/private/tmp/centtrail-capture-ios-destination.log`.

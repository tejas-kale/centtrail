# 01: Remove the Ask tab and report interpreter

**What to build:** The app no longer has an Ask tab. On-device natural-language reporting is removed: the report half of the Interpreter (operation selection, question periods, report follow-ups) goes, while capture parsing stays and still works with Apple's on-device model or the keyword fallback. This is a prefactor that shrinks Home, Reports and the Interpreter before they are reshaped. Spec: `../spec.md`.

**Blocked by:** None (can start immediately)

**Status:** implemented; awaiting iOS integration build

- [x] The tab bar / Mac sidebar has no Ask destination, on iPhone and Mac.
- [x] Report-interpretation code and its tests (Ask chat, Ask evaluation, report follow-up, question period) are deleted.
- [x] Voice capture still fills the capture form; the existing voice capture tests pass.
- [x] Ledger report calculations still used by Home remain and their tests pass.
- [ ] The package builds for iOS and macOS with no unused Interpreter report types left.

Validation: macOS `swift test --skip-update` passed, including voice capture and Ledger report calculations. iOS app compile was attempted but blocked in dependency macro targets by unresolved SwiftSyntax/SwiftCompilerPlugin modules before application compilation; its final acceptance checkbox stays open until an integration build succeeds. Log: `/private/tmp/centtrail-01-ios.log`.

# 01: Walking skeleton

**What to build:** The owner records an expense on iPhone or Mac with the short form (amount, kind, counterparty, reporting date, category), sees it in the transaction list, and sees this month's spending total. This sets up the Ledger core package on an app-owned SQLite schema and the shared SwiftUI app shell, so every later ticket only adds behavior.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] The Ledger core is a Swift package whose public interface is the only seam tests use; tests run against a real in-memory SQLite database
- [x] Amounts are stored as integer EUR cents; the reporting date is a calendar date that does not shift with the device's time zone
- [x] Every record has a globally unique stable identity
- [x] Saving is blocked until amount, kind, counterparty, reporting date and category are set
- [x] The 26 owner categories are seeded, with names trimmed of surrounding spaces
- [x] The current-month spending total equals the hand-computed sum of a fixture, to the cent
- [ ] The app builds and runs on iOS 26 (iPhone Air) and macOS 26

## Comments

iOS was not built because there is no iOS SDK.

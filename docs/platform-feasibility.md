# Platform feasibility notes

Research date: 2026-11-11. These are constraints and candidates, not architecture decisions.

## Capture

- A normal iOS app cannot intercept another app's notifications. An [Apple Developer Forums answer](https://developer.apple.com/forums/thread/758584) explicitly states this restriction. Direct Revolut/N26 push-notification parsing is therefore not a supported app capability.
- A user-configured Shortcuts automation is a separate possibility, but notification triggers and their available fields have not been verified for the target OS. Do not promise this route. An inconsistent search result about a WWDC26 notification trigger was excluded as evidence of shipping iOS 26 support.
- Apple Pay transaction automation also needs verification on the target device, including which fields it supplies. It would not by itself cover all bank transactions.

## On-device model candidate

- Apple's Foundation Models framework exposes the on-device language model used by Apple Intelligence. Its [SystemLanguageModel documentation](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) describes runtime availability checks.
- [Unavailable reasons](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason) include an ineligible device, Apple Intelligence not enabled, and the model not ready. Compatible hardware alone does not guarantee availability.
- The owner's iPhone Air and M-series MacBook Pro are in the Apple Intelligence hardware families: [iPhone Air](https://www.apple.com/iphone-air/) and [Apple Intelligence](https://www.apple.com/apple-intelligence/). Region and configuration still matter.
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels) supports structured generation and [tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling). These are candidates for extracting capture fields or query intent. Schema conformance does not guarantee correct financial interpretation.
- No model has been evaluated on the owner's queries. SQL accuracy, latency, and capture accuracy remain untested.

Research used Kagi. SystemLanguageModel content was returned as a full page; other framework capabilities and hardware support were corroborated through indexed Apple documentation/product extracts.

## SQL reporting and iCloud persistence

- The [Core Data FAQ](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/FrequentlyAskedQuestions.html) describes its SQLite format as private and explicitly prohibits manipulating a Core Data-created store through native SQLite APIs. Do not build reporting against its internal schema.
- SwiftData's documented query surface uses [FetchDescriptor](https://developer.apple.com/documentation/swiftdata/fetchdescriptor) and ModelContext fetches. No public raw SQL query interface was found.
- [NSPersistentCloudKitContainer](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer) and [SwiftData CloudKit configuration](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct) provide managed sync. They do not provide an app-owned SQL reporting schema.
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5) provides a lower-level sync building block. Pairing it with an app-owned SQLite database is an architectural option, not a turnkey Apple integration: the app must implement persistence, record mapping, and conflict handling.
- A separate SQL reporting projection beside a managed store is another architectural option, with additional consistency and rebuild work. Neither option is selected yet.
- [SwiftData sync documentation](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) describes CloudKit restrictions on unique constraints and nonoptional relationships. These must not be confused with the product requirement that every saved entry has a category; enforcing that requirement is application work.
- Apple's [Core Data/CloudKit session](https://developer.apple.com/videos/play/wwdc2019/202/) describes last-writer-wins sync conflict handling. Custom conflict workflows require architectural evaluation. Direct CloudKit exposes [serverRecordChanged](https://developer.apple.com/documentation/cloudkit/ckerror/code/serverrecordchanged) for application resolution.

The FAQ and FetchDescriptor content were returned as page extracts; the remaining persistence findings came mainly from indexed Apple documentation/video extracts. Architectural combinations above are synthesis, not claims of packaged Apple functionality.

## Packaged SQLite and CloudKit candidate

- [Point-Free SQLiteData](https://github.com/pointfreeco/sqlite-data), formerly SharingGRDB, describes SQL queries over a GRDB-backed database with built-in CloudKit synchronization. The repository identifies an MIT license; its [release history](https://github.com/pointfreeco/sqlite-data/releases) shows ongoing sync-related maintenance. This is a candidate, not a selected dependency.
- Its [SyncEngine source](https://github.com/pointfreeco/sqlite-data/blob/main/Sources/SQLiteData/CloudKit/SyncEngine.swift) declares support from iOS 17/macOS 14, below the target OS versions. Exact current package/toolchain requirements need verification before implementation.
- Maintainer discussions describe [field-wise last-edit-wins merging](https://github.com/pointfreeco/sqlite-data/discussions/272), which could preserve independent edits while resolving conflicting edits to the same field. Verify against the chosen release before relying on it.
- Synced tables require globally unique identities; cross-device uniqueness and relationships need careful schema validation. [Uniqueness](https://github.com/pointfreeco/sqlite-data/discussions/117) and [relationship](https://github.com/pointfreeco/sqlite-data/discussions/344) discussions are signals to test the proposed vendor/category/refund schema, not a definitive current compatibility matrix.
- [GRDB](https://github.com/groue/GRDB.swift) plus custom CKSyncEngine integration is an alternative with more application-owned synchronization work. SQLiteData may avoid that work if its behavior satisfies this app's requirements.

These findings came from Kagi's indexed repository, source, and maintainer-discussion excerpts. No dependency has been installed and no sync prototype has been run.

## SQLiteData + CloudKit evaluation (2026-11-14)

- **Package & toolchain compatibility**: `pointfreeco/sqlite-data` supports Swift 6 (`Package@swift-6.0.swift` / `Package@swift-6.1.swift`) and declares support from iOS 17 / macOS 14, which is compatible with Centtrail's `.macOS("26.0")` and `.iOS("26.0")` package targets.
- **Schema limits for `SyncEngine`**:
  - **Globally unique primary keys**: Every synced table requires a globally unique primary key (`UUID` / `UUIDv7`, `TEXT PRIMARY KEY NOT NULL`).
  - **No non-PK `UNIQUE` constraints**: `SyncEngine` inspects table pragmas and rejects any `UNIQUE` index/constraint on non-primary-key columns (*"Uniqueness constraints are not supported for synchronized tables."*). In Centtrail's current `Ledger` schema, `category.name`, `counterparty.name` (Payee), and `counterparty_alias.name` have `UNIQUE` constraints that must be dropped from synced DDL and handled at the application layer (e.g., deterministic UUIDs for seeded categories and merge/deduplication on lookup).
  - **Foreign keys & `ON DELETE` actions**: Foreign keys are supported—`SyncEngine` topologically sorts batches and caches/retries child records that arrive before their parent—but `ON DELETE RESTRICT` and `ON DELETE NO ACTION` are rejected (*"Foreign key action not supported. Must be 'CASCADE', 'SET DEFAULT' or 'SET NULL'."*). Synced foreign keys (e.g., `entry.counterparty_id`, `entry.category_id`, `counterparty_alias.counterparty_id`, `proposed_payee_default`) must specify `ON DELETE CASCADE`, `ON DELETE SET NULL`, or `ON DELETE SET DEFAULT`.
  - **Required fields & defaults**: Synced `NOT NULL` columns should carry safe `DEFAULT` values or be populated prior to insert so out-of-order or migrated records remain valid, and column names must avoid CloudKit-reserved metadata fields.
- **Conflict resolution & domain sync behavior**:
  - **Field-wise last-edit-wins (LWW)**: `SyncEngine` tracks per-column edit timestamps and merges concurrent edits column-by-column, preserving independent edits to different fields on the same row while resolving same-field conflicts to the latest edit without prompting.
  - **Trash/restore**: Because `entry.trashed_on` is an independent column, trashing or restoring an entry syncs via field-wise LWW without clobbering unrelated fields.
  - **Payee default + per-entry override**: Because `counterparty.default_category_id` and `entry.category_id` / `entry.category_provenance` live on separate tables/columns, changing a payee's default category on one device while setting a per-entry `override` on another device preserves both the new default (for inherited entries) and the explicit override.

### Manual two-device verification checklist (iPhone Air & Mac)

Live CloudKit sync requires signed app targets with iCloud/CloudKit entitlements, the Remote Notifications background mode, and two physical devices under the same iCloud account. None of these manual steps were executed in this CLI session; the owner should verify them on iPhone Air and Mac once ticket 04 wires `SyncEngine` into the app:

- [ ] **Minimal schema sync**: Launch the signed build on both iPhone Air and Mac under the same iCloud account; create a category, payee, and entry on one device and confirm they appear on the other.
- [ ] **Offline create, edit, and delete**: Put one device offline; create a new entry, edit an existing entry's amount or note, and delete another entry; reconnect and confirm all three changes appear on the other device.
- [ ] **Same-field conflict (field-wise LWW)**: With both devices offline, edit the same field (e.g., `note` or `amount_cents`) on the same entry on both devices at different times; reconnect both and confirm the latest edit wins without prompting, while edits to different fields on the same entry are both preserved.
- [ ] **Trash and restore**: Trash an entry on iPhone Air and confirm it leaves active lists/reports on Mac; restore it from Trash on Mac and confirm it returns on iPhone Air.
- [ ] **Payee default + per-entry override**: Change a payee's default category on Mac while setting a per-entry category override on one of that payee's entries on iPhone Air; sync both and confirm inherited entries adopt the new default while the overridden entry keeps its override.

### Ledger on the synced store (ticket 04): owner's two-device steps

Ticket 04 moved the `Ledger` onto SQLiteData and wired `SyncEngine` into the app targets. The Ledger test suite runs against the new store (including with the sync engine attached, using SQLiteData's test CloudKit stand-in), but live CloudKit was not exercised: these steps are for the owner and have not been run.

How sync is switched on:

- `Apps/project.yml` gives both apps the iCloud (CloudKit) capability for container `iCloud.com.tejaskale.centtrail`, push (`aps-environment`), the iOS `remote-notification` background mode, and outgoing network access in the Mac sandbox.
- Both apps carry the Info.plist key `CenttrailCloudKitContainer`. The shell opens the ledger with sync only when that key is present, so `swift run Centtrail` and the tests stay local.
- Open screens refresh whenever the ledger changes, including changes pulled in from the other device.

Before the first run:

1. In the Apple Developer portal, create the CloudKit container `iCloud.com.tejaskale.centtrail` and enable iCloud (CloudKit) and Push Notifications on the `com.tejaskale.centtrail` App ID. Xcode's automatic signing can do this on the first signed build.
2. `cd Apps && xcodegen generate`. On the first build, Xcode asks you to trust the SQLiteData macro packages (swift-structured-queries, swift-perception); trust them. Command-line builds need `-skipMacroValidation`. Then build and run the signed `CenttrailIOS` scheme on the iPhone Air and the `CenttrailMac` scheme on the Mac. Both must be signed into the same iCloud account with iCloud Drive on.
3. Delete any 1.0 install first: v2 starts from an empty ledger and does not migrate 1.0 data.

Checks:

- [ ] **Fresh install**: On each device, the first launch shows an empty ledger. Settings → Categories lists the owner's 26 categories once, with no duplicates after both devices have synced.
- [ ] **iPhone → Mac**: With both apps open, add an expense on the iPhone. Within about a minute it appears on the Mac's Home (last five, this month's total) without relaunching.
- [ ] **Mac → iPhone**: Add an income on the Mac (Cmd-N). It appears on the iPhone's Home.
- [ ] **Offline capture**: Turn on Airplane Mode on the iPhone. Add one transaction, edit another's category, and delete a third. All three work immediately offline. Turn Airplane Mode off; within a minute the Mac shows all three changes.
- [ ] **Offline on the Mac**: Repeat the step above with Wi-Fi off on the Mac and check the iPhone.
- [ ] **Last edit wins**: Put both devices offline, change the same transaction's category on each (iPhone first, then Mac), reconnect both. Both devices settle on the Mac's choice with no prompt.
- [ ] **Trash and restore**: Delete a transaction on the iPhone; it disappears from the Mac's lists and totals. Restore it from Recently deleted on the Mac; it returns on the iPhone.
- [ ] **Categories, payees and defaults**: Add a category on the Mac, change a payee's default category on the iPhone, and merge two payees on the Mac. Each change shows on the other device.
- [ ] **CSV import**: Import the owner's CSV on one device. All transactions appear on the other device; the totals for one past month match on both.

Known limit: seeded categories use the same ID on every device, so a fresh install never duplicates them. But a device installed later seeds each category again with its original name. That re-seed can revert a rename of a seeded category, or bring back a removed one, made on another device. If that happens, rename or remove the category again.

## Ask on Apple Foundation Models evaluation (2026-11-14)

- **Runtime availability & fallback**: `AppleFoundationModelBackend` reads `SystemLanguageModel.default.availability` at runtime (`.available`, `.unavailable(.deviceNotEligible)`, `.unavailable(.appleIntelligenceNotEnabled)`, `.unavailable(.modelNotReady)`). When unavailable, `Interpreter` falls back to `KeywordLanguageModelBackend` and `AskScreen` displays a reason-specific note alongside the preset chips; when available, no unavailable note is shown.
- **Guided generation & validation**: `AppleFoundationModelBackend` uses `LanguageModelSession` with `@Generable` (`GeneratedReportIntent` and `GeneratedCaptureDraft`). Every generated intent is validated before execution: inverted or incomplete date ranges, negative/invalid amounts, and unknown categories or payees become plain explanations (`.unsupported`), ambiguous names trigger `.clarification`, and mutation requests are refused.
- **Evaluation set results (`Tests/LedgerTests/AskEvaluationTests.swift`)**:
  - **12 representative questions** covering totals (spending/income, current/last month), breakdowns (`category`, `month`, `monthAndCategory`), comparisons, searches with amount filters, ambiguous payee clarification (`Amazon` vs `Amazon Fresh`), out-of-scope questions (`what is my net worth?`), and mutation refusals (`delete all my transactions`).
  - **Keyword fallback (`KeywordLanguageModelBackend`)**: 12/12 operation accuracy, 12/12 argument accuracy.
  - **Foundation Models schema + validator (`AppleFoundationModelBackend` with injected `@Generable` fixtures)**: 12/12 operation accuracy, 12/12 argument accuracy, plus verified rejection of invalid date ranges, negative amounts, and unknown categories.
  - **Host environment**: On this macOS build host, `SystemLanguageModel.default.availability` reports `.unavailable(.deviceNotEligible)`, so live on-device model inference did not execute here.

### Physical iPhone Air timing & accuracy checklist (5–7 second target)

Physical iPhone Air timings (cold and warm end-to-end latency) and live on-device Apple Intelligence accuracy must be measured on device:

- [ ] **Availability check on device**: With Apple Intelligence enabled on iPhone Air, open Ask and confirm the unavailable note is hidden (`unavailableNote == nil`). Toggle Apple Intelligence off in Settings and confirm the unavailable note appears with the expected reason and preset chips still work.
- [ ] **Cold end-to-end timing (5–7 s target)**: Force-quit and relaunch Centtrail on iPhone Air; submit a representative Ask question (e.g. `"how much did I spend this month?"`) and record wall-clock time from send tap to rendered answer card. Target: `<= 5–7 s`.
- [ ] **Warm end-to-end timing (5–7 s target)**: Immediately submit a second question in the same session (e.g. `"spent on restaurants compared with last month"`) and record wall-clock time from send tap to rendered answer card. Target: `<= 5–7 s`.
- [ ] **Live evaluation set run**: Run `appleFoundationModelLiveSmokeAndTimingWhenAvailable` (and the 12-question evaluation set against `AppleFoundationModelBackend()`) on an Apple Intelligence-enabled device and record observed operation/argument accuracy and cold/warm timings here.

## Local validation boundary

The local `swift test` suite runs and passes on macOS in this workspace, but live CloudKit two-device sync and on-device Foundation Models behavior require signed Apple app targets and physical hardware (iPhone Air and Mac) and were not run in this session.

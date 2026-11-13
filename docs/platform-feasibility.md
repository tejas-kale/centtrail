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

## Local validation boundary

The local `swift test` suite runs and passes on macOS in this workspace, but live CloudKit two-device sync and on-device Foundation Models behavior require signed Apple app targets and physical hardware (iPhone Air and Mac) and were not run in this session.

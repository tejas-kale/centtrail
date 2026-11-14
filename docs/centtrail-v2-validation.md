# Centtrail v2 review and validation

The integration branch is `centtrail-v2`; the review covers changes since `main` at `4d254c1`. The approved spec and local ticket tracker are `.scratch/centtrail-v2/spec.md` and `.scratch/centtrail-v2/issues/`. All findings below have implementation fixes. Device acceptance checks remain separate from automated results.

## Standards review: 5 findings

| Finding | Disposition and evidence |
| --- | --- |
| Synced account foreign keys used `RESTRICT`, contrary to ADR 0004 | Fresh v2 entry DDL uses `SET NULL`; the Ledger refuses removing referenced accounts. SQLiteData 1.13.0's `validateSchema` only rejects restrictive actions on single-foreign-key parent tables, explaining the earlier passing stand-in checks. [ADR 0004](adr/0004-sync-first-with-sqlitedata.md) now records the precise library limit and Centtrail's stricter rule. |
| Generated finite amounts could overflow integer conversion | Checked [Cents conversion](../Sources/Ledger/Models.swift) returns nil for nonfinite, negative or unrepresentable euro values. Report validation refuses those filters; capture leaves the amount for correction. [Regression](../Tests/LedgerTests/AmountValidationTests.swift). |
| Generated comparison dates were validated then discarded | Explicit comparison ranges are refused with a clear supported-period explanation. The keyword and generated paths share the period check. [Regression](../Tests/LedgerTests/ComparisonPeriodTests.swift). |
| Merged inherited entries retained the source category | Merging follows the survivor's default for inherited entries, preserves explicit overrides and keeps aliases. When the survivor has no accepted default, source classification becomes explicit. [Regression](../Tests/LedgerTests/PayeeMergeTests.swift). |
| Duplicate unchecked model amount conversion | Both report filter variants and generated capture use the checked `Cents(roundedEuros:)` initializer. CSV uses the same exact text parser as manual entry. |

## Spec review: 6 findings

| Finding | Disposition and evidence |
| --- | --- |
| Full transaction editing missing | [Ledger.update](../Sources/Ledger/Ledger.swift) shares capture validation and upserts editable fields while retaining the ID, import identity and trash state. The detail's Edit button opens the shared form for amount, kind, payee, category, accounts, date and existing notes. Inherited/override provenance is retained. [Regression](../Tests/LedgerTests/UpdateEntryTests.swift). |
| Typed and CSV amount overflow could terminate the app | Exact parsing checks multiplication and addition overflow; the shared generated conversion checks integer representability. Invalid input produces disabled Save, CSV correction or an Interpreter refusal. [Regression](../Tests/LedgerTests/AmountValidationTests.swift). |
| Duplicate CSV headers crashed import | The importer validates unique/nonempty/required headers, column counts and closed quotation marks before classification. It preserves escaped quotes and commas in quoted fields. [Regressions](../Tests/LedgerTests/ImportTests.swift). |
| Deleted seed categories reappeared; late seeds could reset customization | Stable immutable seed records are combined with a separate synced customization/removal overlay. Bootstrap never writes those choices; effective views supply names to transactions and reports. [Repeated-bootstrap regression and sync schema checks](../Tests/LedgerTests/SyncedStoreTests.swift). Physical late-install convergence remains unchecked. |
| Explicit comparison periods silently became current/previous month | Unsupported explicit periods are refused in both backends; current month versus the same days of last month remains available. [Regression](../Tests/LedgerTests/ComparisonPeriodTests.swift). |
| Ordinary tests performed stochastic live inference | Live evaluation is opt-in with `CENTTRAIL_LIVE_MODEL_EVALUATION=1`; normal tests use fixtures and keywords. [Evaluation tests](../Tests/LedgerTests/AskEvaluationTests.swift) and [Mac observations](platform-feasibility.md). |

## Additional integration findings

- **Clean v2 start:** The app now uses `Centtrail/ledger-v2.sqlite`, leaving the v1 `ledger.sqlite` untouched for the owner's clean re-import. The old host path would have attempted to open a v1 schema with v2 migrations.
- **App Shortcut metadata:** The initial iOS build included `AddExpenseIntent` but advertised no automatic shortcuts. The shared package and each host now declare `AppIntentsPackage` dependencies, following [Apple's framework/host bridging instructions](https://developer.apple.com/documentation/appintents/appintentspackage). Final app build metadata must confirm that the shared `CenttrailShortcuts` provider and Siri phrases are discovered; this is separate from tests that invoke the intent directly.

## Automated evidence

Focused red/green checks reproduced and fixed each behavioral review finding at the public Ledger or Interpreter boundary. The default suite includes update identity/import/provenance, checked amounts, malformed/quoted import, repeated bootstrap, comparison refusal and merge classification regressions. Live inference is disabled by default through a test trait, not a manual test-name skip.

Command used on this host:

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
```

The plugin path is required by the installed Command Line Tools/SDK combination for SwiftUI's macros. The final review-fix default run succeeded: **96 executed tests passed and 1 opt-in live evaluation was skipped** (91 registered Ledger tests plus 6 shell tests). `git diff --check` passed. Baseline integrated iOS simulator app plus Control extension and Mac app builds passed at `374adfb`; final review-fix app rebuild and shortcut metadata verification remain for root integration.

## Manual checks still pending

The [platform feasibility checklists](platform-feasibility.md) remain authoritative for physical iPhone Air/Mac sync convergence (offline, conflict, edit, trash, restore, defaults, late installation), microphone/speech permissions and recognition, Siri/Action button/Control Center/Lock Screen interactions, and iPhone Foundation Models accuracy and 5–7 second latency. No physical-device result is inferred from a successful build, stand-in CloudKit schema validation or generated fixture.

The Mac model was available in the 2026-11-14 diagnostic run: cold 2.5395 s, warm 1.4433 s. Its invented category on one total query was safely refused. Those observations are not an iPhone measurement or an accuracy benchmark.

# 01: Sync spike: SQLiteData + CloudKit

**What to build:** A throwaway two-device spike that proves (or disproves) SQLiteData with CloudKit for Centtrail's records, on the owner's iPhone Air and Mac under one iCloud account. Time-box: half a day. The outcome decides the storage for ticket 04.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] A minimal transaction/payee/category/account schema syncs between iPhone and Mac
- [ ] Create, edit and delete made offline on one device appear on the other after reconnecting
- [ ] Same-field edits on both devices resolve to the latest edit without prompting
- [ ] Trash and restore sync; a payee default change with a per-entry override syncs correctly
- [ ] Schema limits found (unique constraints, relationships, required fields) are listed
- [ ] Findings are written to the platform-feasibility doc, including which manual steps were run
- [ ] ADR 0004 records the decision: adopt SQLiteData, or fall back to SwiftData and why

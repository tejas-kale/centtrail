# 04: Ledger on SQLiteData with iCloud sync

**What to build:** The Ledger keeps its public API but stores data in the synced store chosen in 01, so transactions, payees, categories and trash sync between the owner's iPhone and Mac. Reports stay app-built SQL from typed operations (ADR 0001); with the SwiftData fallback, report rules stay behind the same API. The ledger starts empty; no migration from 1.0.

**Blocked by:** 01, 02

**Status:** done

- [ ] The full Ledger test suite passes against the new store
- [ ] A transaction added on the iPhone appears on the Mac with the current screens, and vice versa
- [ ] Capture and edits work offline and sync after reconnecting
- [ ] A fresh install opens an empty ledger with the owner's category list
- [ ] Manual two-device check steps are noted in the platform-feasibility doc

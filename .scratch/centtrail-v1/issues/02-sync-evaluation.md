# 02: Sync evaluation

**What to build:** Entries recorded on one device appear on the other through the owner's iCloud account using SQLiteData. Each device shows when changes are waiting to sync. The ticket ends with a recorded decision to adopt SQLiteData or to fall back to custom sync on CKSyncEngine.

**Blocked by:** 01

**Status:** claimed

- [ ] Create and edit on one device appear on the other, both signed in to the same iCloud account
- [ ] Capture while offline saves locally and syncs once the device is back online
- [ ] A pending-sync indicator shows while local changes have not yet synced
- [ ] Same-field conflicting edits resolve with the latest edit winning, and edits to different fields both survive; observed behavior is written down
- [ ] Schema constraints for the planned category, counterparty, alias and refund relationships are checked against the library and gaps written down
- [ ] An ADR records adopt SQLiteData or fall back to CKSyncEngine, with the evidence

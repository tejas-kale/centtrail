# 05: Trash and restore

**What to build:** The owner deletes an entry, which moves it to trash, and can restore it within 30 days. After 30 days it is purged. Trashed entries are excluded from every report.

**Blocked by:** 01

**Status:** ledger implemented

- [x] Deleting an entry moves it to trash with a trashed-on date
- [x] Restoring an entry from trash returns it to reports unchanged
- [x] Purging with an injected date removes entries trashed more than 30 days earlier and keeps the rest
- [x] Trashed entries never count in totals, breakdowns, comparisons or search
- [ ] A trash screen lists trashed entries with their days remaining

## Comments

The trash screen lists trashed entries and their days remaining. It has not been checked on a device.

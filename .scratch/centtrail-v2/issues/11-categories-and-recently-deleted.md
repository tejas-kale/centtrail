# 11: Editable categories and Recently deleted

**What to build:** Settings lets the owner add, rename and remove categories, with removal refused while transactions use the category. Settings › Recently deleted lists deleted transactions with days remaining and a Restore action; entries older than 30 days are purged automatically.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] A new category appears in the + form and in Ask on both devices
- [ ] Renaming keeps every transaction's classification
- [ ] Removing a category in use is refused with a message naming how many transactions use it
- [ ] Restoring a deleted transaction brings it back into totals
- [ ] Entries deleted more than 30 days ago are gone without manual purging
- [ ] Ledger tests cover the removal refusal and the 30-day purge

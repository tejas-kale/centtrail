# 09: Import CSV from a file

**What to build:** Settings › Import opens a file picker for the owner's CSV export. A preview shows counts of ready rows, rows needing a fix, definite repeats and uncertain matches, with keep/skip for uncertain ones and one-time acceptance of proposed payee defaults. `Source Account` becomes the transaction's account (creating unknown accounts); positive amounts, refunds included, are income. A summary confirms the result.

**Blocked by:** 06

**Status:** done

- [ ] Importing the sample export creates transactions with N26, Revolut and Cash accounts
- [ ] Positive rows import as income; non-EUR rows are rejected with a reason
- [ ] Re-importing the same file skips every row as a definite repeat
- [ ] Each proposed payee default is offered once, not once per row
- [ ] The summary reports imported and skipped counts; failures show a message
- [ ] Import tests cover account mapping and positive-amount income

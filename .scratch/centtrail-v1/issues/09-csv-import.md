# 09: CSV import

**What to build:** The owner imports the existing CSV export. A preview shows the column mapping, reporting dates, amounts and categories before anything is committed. Rows that need correction stay visible, definite repeats are skipped, and uncertain matches are shown for the owner to decide. The 29-row sample export imports end to end.

**Blocked by:** 04

**Status:** resolved

- [x] Default mapping follows the CSV import mapping doc: Date → reporting date in the row's own offset, Amount sign → kind, Category and Payee trimmed and matched
- [x] The owner can choose a different column as the reporting date
- [x] Rows with an unknown category or non-EUR currency are held for correction, never dropped
- [x] Positive amounts in an expense category are held for review until the refund and transfer format is confirmed
- [x] Definite repeats (same timestamp to the second, amount, payee and source account) are skipped on re-import
- [x] Same date, amount and payee with a different time is shown as an uncertain match for the owner to decide
- [x] A new payee proposes the row's category as its default category
- [x] Importing the sample export twice yields 29 entries, not 58

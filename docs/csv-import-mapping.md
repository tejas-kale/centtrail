# CSV import mapping

Status: derived from a 29-row sample export (2025-01-29 to 2025-02-20). Open questions are listed at the end; nothing here is implemented.

## Category list (v1)

Names are trimmed of surrounding whitespace on import (the source list has trailing spaces, e.g. `"Bureaucracy "`).

Anagha, Bureaucracy, Electronics, Entertainment, Flight, Friend, Hotel, Household Requirements, Ishwa, Kindergeld, Kita, Medicine, Reading, Rent, Restaurant, Salary, Savings, Self Care, Shopping, Software, Study, Supermarket, Taxi, Train, Utilities, Vacation.

Income categories seen in the sample: Salary, Kindergeld.

`Savings` rows are imported but excluded from spending, like transfers. Savings tracking itself stays in v2.

## Column mapping

| CSV column | Maps to | Rule |
| --- | --- | --- |
| `Date` | Reporting date (default) | ISO timestamp with offset, e.g. `2025-02-12T19:28:43+0100`. Use the calendar date in the row's own offset; drop the time. The import preview still lets the owner pick a different date column. |
| `Amount` | Amount + kind | Decimal EUR. Negative → expense, positive → income. Store absolute value in integer cents. |
| `Category` | Category | Must match the list above after trimming. Unknown names stop the row for correction. |
| `Payee` | Counterparty (vendor or payer) | Trim whitespace (`"REWE "`, `"WinSIM "`, `"Budgetflow "`). Match against confirmed aliases; a new payee takes this row's category as its proposed default. |
| `Notes` | Transaction note | Free text, e.g. `For the stay on April 29-30`. |
| `Source Account` | Duplicate-detection input only | Values seen: N26, Revolut, Cash. Balances are out of v1 scope. |
| `Source Currency`, `Target Currency`, `Exchange Rate` | Validation only | Reject rows that are not EUR→EUR at 1.0 (INR is v2). |
| `Budget Book` | Validation only | Only `Germany` seen. |
| `Folder` | Not mapped yet | Category group (Income, Groceries, Free time, Living, Mobility). See open questions. |
| `Target Account`, `Tags`, `Pending` | Ignored | Empty or always `False` in the sample. |

## Duplicate detection

The export has no row ID. A definite repeat is an exact match on timestamp (to the second), amount, payee and source account. Matching date, amount and payee with a different time is uncertain and goes to review.

## Observations from the sample

- Amazon appears under Supermarket three times; a vendor whose purchases span categories will rely on per-purchase overrides.
- Notes sometimes give a service date different from the payment date (Booking, DB). The reporting date stays the payment date unless the owner changes it.
- The sample has no transfers, refunds or pending rows, so their mapping is unconfirmed.

## Open questions

1. Should `Folder` become a category group in v1?
2. How does the source app export refunds and transfers between accounts?

# Personal expense tracking

The owner's recorded income, expenses and movements between accounts, kept in euros and rupees.

## Language

**Category**:
A label from the owner's editable list used to group income or expenses, such as utilities, restaurants, software or groceries.

**Payee**:
The person or organization on the other side of an expense or income, such as a retailer, service provider or employer. A payee may have one default category.
_Avoid_: Counterparty, Vendor, Payer, Merchant

**Default category**:
The category applied through a payee unless an entry has an explicit override. Changing it also changes the classification of past entries that inherited the previous default.

**Category override**:
An entry-specific category choice that takes precedence over its payee's default category.

**Payee alias**:
An alternative name for the same payee, kept when the owner merges two payees. For example, “AMZN MKTP” may be an alias of “Amazon.”

**Account**:
A place the owner's money sits and is paid from, such as N26, Revolut, Cash or an Indian bank account. Each account has one currency.

**Currency**:
The denomination of an account's money: EUR (euros) or INR (Indian rupees). An expense or income uses its account's currency.

**Spending**:
The total of active expenses in spending categories during a period, including entries awaiting review, kept separately in EUR and INR. Refunds, internal transfers, trashed entries and non-spending categories such as savings do not reduce or add to it.

**Refund**:
Money returned for an earlier expense, recorded as income. It does not reduce spending.

**Reporting date**:
The date selected by the owner to determine which period contains an entry. It need not be the bank posting date or the date the entry was created.

**Internal transfer**:
A movement of money between accounts owned by the same person, with a sent amount in the source currency and a received amount in the destination currency. It is neither income nor an expense; historical transfers may have only a sent amount.
_Avoid_: Remittance (as a separate concept)

**Sent amount**:
The money leaving an internal transfer's source account, expressed in that account's currency.

**Received amount**:
The money arriving in an internal transfer's destination account, expressed in that account's currency. It equals the sent amount for a same-currency transfer.

**Budget**:
An optional fixed monthly spending allowance for one category in one currency. It resets each calendar month with no rollover.

**Review inbox**:
The collection of entries saved with incomplete classification and awaiting correction by the owner.

**Uncategorised**:
The reserved category for entries awaiting review. It counts as spending but is never a payee default or a budgeted category.

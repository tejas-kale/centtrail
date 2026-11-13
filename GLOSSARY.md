# Personal expense tracking

The owner's recorded income and expenses.

## Language

**Category**:
A label from the owner's predefined list used to group income or expenses for reporting. Examples include utilities, restaurants, software, and groceries.

**Counterparty**:
A named person or organization on the other side of a recorded payment. A vendor receives an expense payment; a payer provides income.

**Vendor**:
The counterparty receiving an expense payment, such as a retailer or service provider. Each vendor has one default category, which an individual purchase may override.
_Avoid_: Merchant (as a separate domain concept)

**Payer**:
The counterparty providing income, such as an employer. Payers follow the same default-category, alias, and category-override rules as vendors.

**Default category**:
The category applied through a vendor or payer unless an entry has an explicit override. Changing it also changes the classification of past entries that used the previous default.

**Category override**:
A transaction-specific category choice that takes precedence over its vendor's or payer's default category.

**Counterparty alias**:
An explicitly confirmed alternative name for the same vendor or payer. For example, “AMZN MKTP” may be an alias of “Amazon.”

**Spending**:
Expenses less refunds received during the reporting period. Moving money between the owner's accounts and repaying a credit-card balance do not constitute spending.

**Refund**:
Money returned for an earlier expense. It reduces spending in that expense's category in the period when the refund is received.

**Reporting date**:
The date selected by the owner to determine which reporting period contains a transaction. It need not be the bank posting date or the date the entry was created.

**Internal transfer**:
A movement of money between accounts owned by the same person. It is neither income nor an expense.

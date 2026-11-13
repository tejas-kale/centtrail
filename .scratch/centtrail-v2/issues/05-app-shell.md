# 05: Home, Ask and Settings shell with a basic + form

**What to build:** The new app layout: Home, Ask and Settings as tabs on iPhone and a sidebar on Mac, in native iOS 26 style. Home shows this month's spending against the same days of last month (with last month's full total smaller and unequal lengths labelled), the last five transactions and a See all list with search, edit and swipe-to-delete. A prominent + opens a sheet with Expense/Income, amount (focused, decimal keypad), payee with autocomplete, category prefilled from the payee's default, and a date picker defaulting to today. Ask is a placeholder. Settings temporarily hosts the old payee, trash and import screens. Every failure shows a message.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] The five old tabs and the sentence box are gone
- [ ] On 13 November, Home compares 1–13 Nov with 1–13 Oct and shows the change as amount and percentage (no percentage when October is zero)
- [ ] A Ledger home-summary capability returns these figures and is tested at mid-month, on the 31st after a shorter month, and with an empty previous month
- [ ] Saving from the + form closes the sheet and updates Home; Save shows which field is missing
- [ ] A category changed in the form overrides that entry only
- [ ] Amounts use locale currency formatting; income is green
- [ ] Mac shows the same three sections in a sidebar

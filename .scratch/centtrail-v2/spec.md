# Centtrail v2: synced, simple redesign

Status: ready-for-agent

## Problem Statement

Centtrail 1.0 runs on the owner's iPhone Air and Mac, but it confuses them. Five tabs expose every engine feature as a form: Capture, Reports, People, Trash, Import. Adding an expense means scrolling a long form, typing a date as `YYYY-MM-DD`, choosing between five transaction kinds, and typing the payee from memory. Voice capture exists only as a "sentence" box; the Siri shortcut exists only on the Mac. The "Ask" box never uses Apple Intelligence: it always says the model is unavailable and matches keywords. The landing screen shows a single number, this month's spending, with no comparison. Import means pasting CSV text into a box. The two devices do not share data.

The owner also changed several rules. A refund is ordinary income rather than a reduction of spending. "Transfer" means sending euros to their own Indian bank account. Each transaction should name the account it was paid from. "Payee" is the one word for the other side of any transaction.

The owner wants an app with one clear purpose: record spending in seconds, see this month against last month at a glance, and ask questions in plain words. It must stay small enough to grow later into custom charts, INR and savings.

## Solution

Centtrail becomes a three-section app, **Home · Ask · Settings**: tabs on iPhone, a sidebar on Mac. It is native iOS/macOS 26 in style (Liquid Glass, SF type, one accent colour, Swift Charts, locale currency formatting). Both devices sync through the owner's iCloud account.

- **Home** shows this month's spending against the same days of last month, the top categories with last month's same-days value beside each, and the last five transactions with "See all". A prominent **+** opens the capture form.
- **The + form** offers Expense | Income | Transfer. For expenses and income, eight frequent-payee chips fill payee, category and last-used account in one tap. Amount takes focus, and the date defaults to today. Transfers ask for amount, from-account, to-account and date. A mic button fills the fields from speech. The same form opens from a Siri/Shortcuts phrase, the Action button, a Control Center/Lock Screen control, and Cmd-N on the Mac.
- **Ask** is a read-only chat backed by Apple's on-device model. Each answer is one line of text plus, where useful, a chart or transaction-list card showing the date range used. Without the model, Ask offers preset question chips. History clears on each launch.
- **Settings** holds Import CSV (file picker), Payees (default category, merge), editable Categories and Accounts, and Recently deleted (30 days).

Sync is built first: a half-day spike proves SQLiteData + CloudKit on two devices, with SwiftData as the fallback. The owner then starts clean and re-imports their CSV.

## User Stories

### Sync and data

1. As the owner, I want transactions I add on my iPhone to appear on my Mac, so that I can review spending on either device.
2. As the owner, I want to add and edit transactions while offline, so that capture never waits for the network.
3. As the owner, I want offline changes to sync automatically when I'm back online, so that I never resolve conflicts by hand.
4. As the owner, I want the latest edit to win when both devices changed the same transaction, so that sync stays invisible.
5. As the owner, I want edits, deletions and restores to sync, so that both devices always show the same ledger.
6. As the owner, I want to start v2 with an empty ledger and re-import my CSV, so that no migration from 1.0 is needed.
7. As the owner, I want categories, accounts and payee defaults to sync too, so that suggestions match on both devices.

### Capture

8. As the owner, I want a prominent + button on Home, so that adding a transaction is always one tap away.
9. As the owner, I want to choose Expense, Income or Transfer with a segmented control defaulting to Expense, so that the common case needs no choice.
10. As the owner, I want chips for my eight most frequent payees, so that I can pick a regular shop with one tap.
11. As the owner, I want tapping a payee chip to fill the payee, its default category and the account I last used with it, so that only the amount is left.
12. As the owner, I want the amount field focused with a decimal keypad when the form opens or a chip is tapped, so that I can type straight away.
13. As the owner, I want the payee field to autocomplete from known payees, so that I don't create near-duplicate payees.
14. As the owner, I want a new payee name to be accepted and to take the category I choose as its default, so that the next entry for it fills in.
15. As the owner, I want the category to fill from the payee's default and stay editable, so that I can override it for one purchase.
16. As the owner, I want a category I change at capture to affect only this entry, so that one Amazon electronics purchase doesn't reclassify Amazon.
17. As the owner, I want to pick the account (N26, Revolut, Cash, …) from a short list, so that I know where the money went.
18. As the owner, I want the date to default to today and use a standard date picker, so that I never type `YYYY-MM-DD`.
19. As the owner, I want Save to be disabled until required fields are filled, and to see which field is missing, so that I never get a silent failure.
20. As the owner, I want the form to close and Home to update after saving, so that I see the new spending straight away.
21. As the owner, I want to record a refund as Income with a payee and a category, so that money returned to me is captured simply.
22. As the owner, I want a Transfer form with amount, from-account, to-account and date, so that sending money to my Indian account is quick.
23. As the owner, I want transfers kept out of spending, so that moving my own money doesn't look like an expense.
24. As the owner, I want a mic button in the form, so that I can say "20 euros at Middle Eats with Revolut" and check the filled fields.
25. As the owner, I want spoken drafts to fill only the fields they mention and leave the rest as defaults, so that I can correct quickly.
26. As the owner, I want nothing saved from speech until I tap Save, so that a misheard amount never enters my ledger.
27. As the owner, I want the mic to keep working when Apple Intelligence is off, using a simpler parser for amount, payee and date, so that voice capture never vanishes.
28. As the owner, I want a Siri/Shortcuts phrase "Add expense in Centtrail" that opens the form, so that I can capture hands-free.
29. As the owner, I want to assign that shortcut to the Action button, so that one press starts a new entry.
30. As the owner, I want a Control Center and Lock Screen control that opens the form, so that I can capture without finding the app.
31. As the owner on Mac, I want Cmd-N to open the same form as a sheet, so that capture works the same on both devices.

### Home

32. As the owner, I want Home to show this month's spending as the main figure, so that I know where I stand.
33. As the owner, I want it compared with the same days of last month (on 13 November: 1–13 Nov vs 1–13 Oct), so that the comparison is fair mid-month.
34. As the owner, I want the change shown as an amount and a percentage, with no percentage when last month was zero, so that I never see a misleading number.
35. As the owner, I want last month's full total shown smaller, so that I also know where last month ended.
36. As the owner, I want unequal comparison lengths labelled (31 March vs 1–28 February), so that I don't misread end-of-month figures.
37. As the owner, I want the top categories this month with last month's same-days value beside each, so that I see which categories moved.
38. As the owner, I want the last five transactions on Home, so that I can confirm what I just added.
39. As the owner, I want "See all" to open the full transaction list, newest first, with search, so that I can find any transaction.
40. As the owner, I want to tap a transaction to edit any of its fields, so that I can fix mistakes.
41. As the owner, I want to swipe to delete a transaction, so that removing a mistake is quick.
42. As the owner, I want Home to show a clear empty state with an Add button when there's no data this month, so that a blank screen never looks broken.
43. As the owner, I want income in green and expenses in the primary text colour, formatted in my locale's currency, so that amounts read naturally.
44. As the owner, I want refunds, transfers and savings left out of the Home spending figures, so that the headline shows only real spending.

### Ask

45. As the owner, I want an Ask section where I type a question about my transactions, so that I don't build reports by hand.
46. As the owner, I want answers as a chat thread, so that I can ask follow-ups and see earlier answers in the session.
47. As the owner, I want each answer to start with one plain sentence, so that I get the number straight away.
48. As the owner, I want a chart card for breakdowns and comparisons and a list card for searches, so that rows are easy to read.
49. As the owner, I want every answer to state the date range used, so that I know what was counted.
50. As the owner, I want a question with no period to use the current calendar month, so that short questions just work.
51. As the owner, I want Ask to ask me to choose when a name matches several payees or categories, so that it never guesses.
52. As the owner, I want Ask to tell me plainly what it can't answer, so that it never invents a figure.
53. As the owner, I want Ask never to change my data, so that a misunderstood question can't damage my ledger.
54. As the owner, I want Ask to run on-device with Apple's model, so that my finances never leave my devices.
55. As the owner, I want preset question chips (this month by category, vs last month, biggest expenses) when the model is unavailable, so that Ask is still useful.
56. As the owner, I want a short note saying why the model is unavailable only when it really is, so that I'm not told something false.
57. As the owner, I want the chat cleared each time I launch the app, so that no old conversation clutters it.
58. As the owner, I want an answer within about 5–7 seconds on my iPhone, so that asking feels faster than filtering.

### Settings

59. As the owner, I want Import CSV in Settings to open a file picker, so that I import my export file directly.
60. As the owner, I want an import preview showing counts of ready rows, rows needing a fix, definite repeats and uncertain matches, so that I know what will happen.
61. As the owner, I want the CSV's Source Account imported as the transaction's account, so that history carries accounts too.
62. As the owner, I want positive amounts, refunds included, imported as income, so that imports follow the refund rule.
63. As the owner, I want definite repeats skipped and uncertain matches shown for a keep/skip decision, so that re-importing never duplicates.
64. As the owner, I want new payees from the import to take their row's category as a proposed default, accepted once per payee, so that I'm not asked twice.
65. As the owner, I want a summary after import ("412 imported, 3 skipped"), so that I know it worked.
66. As the owner, I want a Payees list showing each payee's default category, so that I can review how they're classified.
67. As the owner, I want to change a payee's default category, with past entries that used the old default following it, so that history stays consistent (ADR 0002).
68. As the owner, I want explicit per-entry overrides kept when a payee's default changes, so that deliberate choices survive.
69. As the owner, I want to merge two payees, with the merged name kept as an alias, so that "AMZN MKTP" and "Amazon" become one payee.
70. As the owner, I want to add, rename and remove categories, so that the list fits my life.
71. As the owner, I want removal of a category that's in use to be refused until its transactions are reassigned, so that no transaction loses its category.
72. As the owner, I want to add, rename and remove accounts (including "India"), so that transfers and payments name real places.
73. As the owner, I want Recently deleted to show deleted transactions with days remaining, so that I can restore a mistake within 30 days.
74. As the owner, I want deleted transactions purged automatically after 30 days, so that I never manage the trash.

### Quality

75. As the owner, I want every failed action to show a message with what to do, so that nothing fails silently.
76. As the owner, I want the app to support Dynamic Type and VoiceOver, so that it stays readable and usable.
77. As the owner, I want the same layout and behaviour on Mac in a sidebar, so that I learn the app once.

## Implementation Decisions

- **Order of work:** sync spike → storage migration behind the Ledger API → domain changes → new app shell → Ask with Apple's model → system entry points. The 1.0 app stays usable until the new shell replaces it.
- **Sync spike:** half a day with SQLiteData + CloudKit on the iPhone Air and the Mac under one iCloud account. Check: create/edit/delete offline then sync; last-edit-wins on the same field; trash and restore; payee default change with overrides; unique-constraint and relationship limits. Write the result to the platform-feasibility doc. If it fails, switch to SwiftData and record why. Record the adoption decision as an ADR.
- **Ledger stays the single domain module and the main test seam.** Its public API keeps its shape; storage moves underneath. Reports remain app-built SQL from typed operations (ADR 0001).
- **Domain vocabulary changes** (see the glossary): Counterparty/Vendor/Payer become **Payee** across the Ledger API and UI. **Account** is new: a synced, editable list seeded with N26, Revolut, Cash and India.
- **Transaction kinds:** expense, income, transfer. Repayment is removed. Refund is no longer a kind: a refund is income. The refund-to-purchase link and the refund-reduces-spending calculation are removed.
- **Transaction shape:** amount (integer cents, EUR), kind, reporting date, account, plus payee and category for expense/income, or a destination account for transfer. Category provenance (inherited vs override) stays.
- **Spending** = expenses in the period, excluding the Savings category, transfers and trashed entries. Income is reported separately.
- **New Ledger capabilities:**
  - a home summary for a given day: this month's spending, last month's same-days spending, last month's full total, an unequal-length flag, and per-category current vs previous figures
  - frequent payees: the top N by entry count, each with its default category and last-used account
  - merge payees, keeping the merged name as an alias
  - category and account create/rename/remove, refusing removal while in use
  - automatic purge of trash older than 30 days
- **CSV import:** a file URL replaces pasted text. `Source Account` maps to Account and creates unknown accounts. Positive amounts are income. Duplicate rules and proposed payee defaults are unchanged. Import still rejects non-EUR rows.
- **Interpreter** takes an injected language-model dependency with three implementations:
  - Apple Foundation Models via guided generation into the existing typed report operations and capture drafts
  - the existing keyword parser as the fallback
  - a test fake

  It keeps returning operation / clarification / unsupported for reports, and a draft for capture. Ask never receives write operations.
- **Model availability** comes from the system's availability API; the hard-coded "unavailable" notice is removed.
- **App shell** is rewritten: three sections, the + form as a sheet, standard pickers, locale currency formatting, and empty states. Errors are surfaced, never swallowed.
- **System entry points:** one App Intent that opens the + form, shared by iOS and macOS. It is exposed as an App Shortcut (Siri phrase, Action button) and as a Control Center/Lock Screen control. The voice path uses on-device speech recognition.
- **Mac** uses the adaptable tab view as a sidebar; Cmd-N opens the form.
- **Removed UI:** the People, Trash, Import and Reports tabs; the sentence box; the transaction detail's provenance and refund-link sections.

## Testing Decisions

- A good test drives the public Ledger or Interpreter API with fixtures and checks visible results: totals to the cent, rows, refusals. It never inspects SQL, tables or sync internals.
- **Ledger tests** (Swift Testing) cover:
  - spending excluding refunds-as-income, transfers and Savings
  - the home summary on the 13th, on the 31st after a shorter month, and with a zero previous month
  - frequent payees and last-used account
  - payee merge and alias resolution
  - default-category change with overrides
  - category/account removal refusals
  - import of accounts and positive amounts as income
  - trash purge at 30 days

  Existing tests are updated for Payee naming and the new refund rule, and refund-link tests are deleted.
- **Interpreter tests** use the fake model and the keyword fallback. They check the selected operation and every argument, clarification for ambiguous names, unsupported questions, and capture drafts from sentences such as "20 euros at Middle Eats with Revolut".
- **Prior art:** the current LedgerTests suite (record, spending, report, import, classification, refusal tests) and its shared test-support helpers.
- **Manual, on device:** the sync spike checklist, Foundation Models accuracy and latency against the 5–7 s target, the + form, Home, Ask, Settings, the Siri phrase, the Action button, the Control Center control and the Mac sidebar. Results are written to the platform-feasibility doc.

## Out of Scope

- INR amounts, multi-currency, exchange rates (transfers are recorded in EUR only)
- Savings tracking, account balances, budgets
- Custom charts and saved views
- Ask changing data; persisted or synced chat history
- Bank-triggered or automatic capture
- Migrating data from 1.0 installs
- Credit-card repayments
- iPad layout
- Mapping the CSV `Folder` column (category groups)

## Further Notes

- The glossary and the product-scope doc already reflect these decisions; the old v1 design doc is superseded on capture, refunds and UI.
- Proposed ADRs: refund counts as income (reverses the earlier rule); sync-first with SQLiteData, SwiftData as fallback. Both await the owner's yes.
- A mockup of the 1.0 screens, for reference, is at https://claude.ai/artifact/H772SeHEC4qfZUyLyD7gQm

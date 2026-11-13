# 12: Ask chat with the keyword parser

**What to build:** The Ask section becomes a read-only chat. Each answer is one plain sentence plus a chart card for breakdowns and comparisons or a list card for searches, always showing the date range used. Questions without a period use the current month; ambiguous names prompt a choice; unsupported questions get a plain explanation. Preset question chips run without any model. The Interpreter takes its language model as a dependency, with the keyword parser and a test fake as implementations. History clears on launch.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] "Restaurants this month vs last month" returns a comparison card with both date ranges
- [ ] A name matching two payees asks which one before running
- [ ] Preset chips (this month by category, vs last month, biggest expenses) work with no model
- [ ] Ask never offers or performs a data change
- [ ] Interpreter tests use the fake model and check the operation and every argument
- [ ] The hard-coded "Apple Intelligence is unavailable" notice is removed

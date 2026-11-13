# 11: Natural-language reports

**What to build:** The owner types a question such as "restaurants this month vs last month" and gets the right report. Ambiguous names get a short clarification first, unsupported requests get a plain explanation of what is supported, and when the model is unavailable the preset reports remain available (ADR 0001).

**Blocked by:** 10

**Status:** ready-for-agent

- [ ] The model selects one operation and its parameters; the Ledger core validates them and builds the SQL
- [ ] An ambiguous vendor or category name triggers a short clarification before the report runs
- [ ] An unsupported request explains the four supported operations and runs nothing
- [ ] The result shows the filters and date range used
- [ ] When the model is unavailable, the owner is told and the preset reports stay usable
- [ ] Required fixture requests from ticket 10 produce the correct report

---
status: accepted
---

# The model selects operations; the app builds reporting SQL

V1 natural-language reporting covers totals, monthly/category breakdowns, period comparisons, and transaction search, so we choose model-selected operations and validated parameters with app-built SQL instead of model-written SQL. This keeps financial calculations and query construction under explicit application rules while allowing natural-language requests. New kinds of analysis require extending the supported operations; schema-valid model output still needs semantic validation and evaluation against expected results.

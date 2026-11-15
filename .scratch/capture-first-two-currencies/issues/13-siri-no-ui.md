# 13: Siri phrase saves with no UI

**What to build:** The owner says a Siri phrase such as "Centtrail 12.50 Lidl" and the entry is saved without opening the app. The phrase goes through the same parsing and Ledger draft completion as voice capture. A known payee with a default is saved fully classified; a new payee or one without a default is saved to the review inbox. Siri confirms what it saved. Spec: `../spec.md`.

**Blocked by:** 10 (Voice overlay filling amount, payee and date), 12 (Review inbox)

**Status:** ready-for-agent

- [ ] An App Intent with a Siri phrase takes the spoken text and never opens the app.
- [ ] It saves a complete entry when draft completion fills every field, otherwise saves for review.
- [ ] Siri's spoken confirmation states amount, currency, payee and category (or "to review").
- [ ] An amount that cannot be parsed saves nothing and Siri says so.
- [ ] Ledger behaviour (complete vs review save from completed drafts) is tested through the Ledger public API; the Siri flow is verified by hand.

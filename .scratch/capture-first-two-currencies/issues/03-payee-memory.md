# 03: Payees remember their category

**What to build:** When the owner types or picks a payee, its category prefills, including payees that came from the CSV import. A payee with no default category adopts the category of the first entry saved for it. Import proposals become real defaults instead of waiting to be accepted, and a migration applies every outstanding proposal in the existing ledger. Choosing a different category on one entry still changes only that entry (ADR 0002 stays). Spec: `../spec.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Recording an expense or income for an existing payee with no default sets that payee's default to the entry's category, with inherited provenance.
- [ ] Recording for a payee whose default differs from the chosen category is an override; the default is unchanged.
- [ ] CSV import sets new payees' defaults directly; no new proposals are created.
- [ ] A migration turns all outstanding proposed defaults into defaults (and recategorises nothing that was explicitly overridden).
- [ ] The Import screen's proposal-acceptance UI is removed or hidden once no proposals can exist.
- [ ] Typing an imported payee's name (or alias) in capture prefills its category.
- [ ] All of the above are tested through the Ledger public API on an in-memory ledger.

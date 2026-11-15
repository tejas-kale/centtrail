# 10: Voice overlay filling amount, payee and date

**What to build:** A mic button on the capture card opens a listening overlay that shows the live transcript and closes when the owner stops speaking or taps outside. Voice fills only amount, payee and date; the payee is matched against known payees and aliases, and category and account then come from payee memory. Unmentioned fields keep their values. Parsing stays on-device with the keyword fallback. Spec: `../spec.md`.

**Blocked by:** 09 (Redesigned capture card)

**Status:** ready-for-agent

- [ ] The Interpreter extracts only amount, payee text and date (including relative dates like "yesterday").
- [ ] A Ledger draft-completion step takes amount, payee text and date, resolves the payee by name or alias, fills default category and account, and reports which fields could not be filled.
- [ ] Saying "12.50 Lidl" for a known payee yields a complete card ready to save.
- [ ] Fields not mentioned keep their current values.
- [ ] A clear message appears when voice could not fill the card.
- [ ] Draft completion is tested through the Ledger public API; the overlay is verified by hand on device.

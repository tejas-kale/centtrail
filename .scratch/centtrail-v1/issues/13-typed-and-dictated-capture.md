# 13: Typed and dictated capture

**What to build:** The owner types or dictates a sentence such as "20 at Middle Eats yesterday" and gets an editable draft with the fields filled in, which they confirm before saving.

**Blocked by:** 10, 12

**Status:** ready-for-agent

- [ ] Typed text and system dictation feed the same parsing flow
- [ ] The draft fills amount, kind, counterparty, reporting date and category where the text gives them
- [ ] Counterparty names resolve against existing counterparties and confirmed aliases; the category comes from the default category unless the text says otherwise
- [ ] An unresolved suggestion cannot be saved until the owner picks a valid category
- [ ] When the model is unavailable, the short form opens instead
- [ ] Parsing accuracy on a capture fixture set is recorded

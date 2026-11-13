# 03: Default categories and overrides

**What to build:** A new counterparty gets the chosen category as its default category, and the next capture for it pre-fills that category. The owner can override the category for one entry. Changing a vendor's default category recategorizes past entries that inherited it and leaves overridden entries alone (ADR 0002).

**Blocked by:** 01

**Status:** ledger implemented

- [ ] Capture pre-fills the category from the counterparty's default category
- [x] An entry records whether its category is inherited or overridden, even when both name the same category
- [x] Changing a default category recategorizes inherited entries in all reports, past periods included
- [x] Entries with an explicit override keep their category when the default changes
- [x] Changing one entry's category does not change the counterparty's default category
- [ ] The owner can view and edit counterparties and their default categories

## Comments

The capture screen calls `prefillCategory` when the counterparty changes. That screen has not been checked on a device.
The People screen lists counterparties and edits their default categories. It has not been checked on a device.

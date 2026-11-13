# 10: Interpreter evaluation

**What to build:** Apple Foundation Models is measured on device for turning the owner's typed requests into report operations. The result is a recorded decision to adopt it, change the approach, or fine-tune. No user-facing feature ships in this ticket.

**Blocked by:** 07, 08

**Status:** ready-for-agent

- [ ] A fixture set covers each operation (total, breakdown, period comparison, transaction search) with paraphrases, ambiguous names and unsupported requests
- [ ] Each case is scored on the chosen operation and every argument, not on schema validity alone
- [ ] Names resolve only to existing categories, counterparties or confirmed aliases; inventing an identity counts as a failure
- [ ] Cold and warm end-to-end latency is recorded on the iPhone against the 5–7 second budget, and separately on the Mac
- [ ] Model-unavailable states (ineligible device, Apple Intelligence off, model not ready) are detected
- [ ] An ADR records the adopt / change / fine-tune decision with the measurements

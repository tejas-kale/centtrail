# 11: Action button and Control open capture already listening

**What to build:** Pressing the Action button, or the Lock Screen / Control Center control, opens the capture card with the listening overlay already active, so speaking an expense takes zero taps. The in-app + still opens the card without listening. Spec: `../spec.md`.

**Blocked by:** 10 (Voice overlay filling amount, payee and date)

**Status:** implemented; pending manual verification

- [x] An App Intent opens the capture card in listening mode; the Action button and the control use it.
- [x] Launching from the Lock Screen or a cold start still lands in listening mode.
- [x] Tapping outside the overlay leaves the card open for typing.
- [x] The in-app + and Mac Cmd-N do not auto-listen.
- [ ] Verified by hand on the iPhone Air.

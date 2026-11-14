# 14: Voice in the + form

**What to build:** A mic button in the + form. The owner says something like "20 euros at Middle Eats with Revolut"; on-device speech recognition transcribes it, and the Interpreter fills amount, payee, category, account and date using Apple's model, or the keyword parser when the model is unavailable. Unmentioned fields keep their defaults. Nothing is saved until the owner taps Save.

**Blocked by:** 06, 13

**Status:** done

- [ ] Speaking a sentence fills the mentioned fields and leaves the rest as defaults
- [ ] With Apple Intelligence off, the mic still fills amount, payee and date
- [ ] Microphone and speech permissions are requested with a clear reason; denial shows a message
- [x] Interpreter capture tests cover account and payee extraction with the fake model and the fallback

Implementation and deterministic Interpreter checks are complete. Physical microphone, permission prompts and on-device recognition still need the manual checks in `docs/platform-feasibility.md`.

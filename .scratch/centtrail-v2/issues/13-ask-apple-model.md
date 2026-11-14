# 13: Ask on Apple's on-device model

**What to build:** Ask uses Apple Foundation Models through guided generation into the existing typed report operations, falling back to the keyword parser and preset chips when the system reports the model unavailable, with a note that says why. Accuracy and latency are measured on the iPhone Air.

**Blocked by:** 12

**Status:** done

- [ ] Model availability comes from the system; the note appears only when the model really is unavailable
- [ ] The model's output is validated like any other operation; invalid output becomes a clarification or explanation
- [ ] An evaluation set of representative questions records operation and argument accuracy
- [ ] Cold and warm end-to-end timings on the iPhone are recorded against the 5–7 second target
- [ ] Results are written to the platform-feasibility doc

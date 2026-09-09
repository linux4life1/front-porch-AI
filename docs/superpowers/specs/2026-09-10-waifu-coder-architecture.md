# Waifu Coder — architecture judo (amendment)

**Date:** 2026-09-10
**Status:** Executing on Rawhide. Amends `docs/superpowers/specs/2026-09-05-waifu-coding-design.md`.
**Plan:** `docs/superpowers/plans/2026-09-10-waifu-coder-architecture.md`

Product law unchanged: desktop only, no ChatService, Plan/Build/Yolo vs Jail/Disk stay two knobs, verify-before-speech stays.

Target internals: one history (`user|assistant|tool|recap`), one `WaifuTurn` (live bubble + receipts), one fill number, one `decide(call)` after jail.

**Re-reads:** After a write, re-read that path (required). Do not glob/read a path still in the prompt unless just mutated.

**First tool:** The first action this turn is a tool (read the file you will change, then patch it). Do not draft source or a ten-step plan in thinking before that tool. Thinking while tools run is fine; thinking instead of tools is not. Harness: first generate of a file-change send sends `tool_choice: required` and turns thinking off (`reasoningMaxTokens: 0`) so MiniMax cannot spend the step drafting Swift. Later steps and plain chat stay auto.

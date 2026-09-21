# Front Porch AI — Documentation

Everything here is written and current. Start with the install guide if you're
new, or jump straight to whatever you're stuck on.

## Start here

| Document | What's in it |
|---|---|
| [Installation Guide](install.md) | Hardware requirements, install methods for Windows/macOS/Linux, and building from source |
| [Getting Started](getting-started.md) | First launch, picking a backend and model, and your first conversation |
| [User Guide](user-guide.md) | The full feature reference — chats, groups, personas, lorebooks, worlds, TTS, image generation and the web/mobile UI |

## Going deeper

| Document | What's in it |
|---|---|
| [The Realism Engine](realism-engine.md) | How emotion, bond/trust, needs, fixation, chaos mode and the passage of time actually work |
| [Characters](characters.md) | Creating and editing characters, the V2/V2.5 card spec, avatars and expressions, importing from Backyard `.byaf` |
| [Keyboard Shortcuts](keyboard-shortcuts.md) | Every shortcut, by screen |
| [Output Sanitizer Syntax](output-sanitizer-syntax.md) | The find/replace rules for cleaning up model output, with worked examples |
| [MoE-Aware VRAM Estimation](moe-vram-estimation.md) | How GPU layer counts are chosen for mixture-of-experts models |

## When something goes wrong

| Document | What's in it |
|---|---|
| [Troubleshooting](troubleshooting.md) | Diagnosing common errors, by symptom |
| [FAQ](faq.md) | The questions that come up most often |
| [Privacy Policy](privacy.html) | What the app stores, and what it never sends anywhere |

Still stuck? Ask in the [Discord](https://discord.gg/e4tET6rpdv), or
[open an issue](https://github.com/linux4life1/front-porch-AI/issues/new/choose).
**Please don't report security problems publicly** — use the
[Security tab](https://github.com/linux4life1/front-porch-AI/security) instead.

## What changed

| Document | What's in it |
|---|---|
| [Release Notes](release-notes.md) | Long-form version history |
| [What's New](main.md) | The stable-channel notes shown in the in-app update dialog |
| [Rawhide — What's New](Rawhide.md) | Nightly / rolling-development notes |
| [STMacro — What's New](STMacro.md) | Notes for the STMacro cutting-edge builds |

## For developers

| Document | What's in it |
|---|---|
| [Design docs](design/) | Architecture and design notes per subsystem — the Journal memory system, Living Time, the sidecar retirement, and more |
| [Path-complete chat work](design/path-complete-chat-work.md) | Agent law: Continue/regen/group/Journal–Growth twins — fill the matrix before claiming chat work is done |
| [Maintainer agent playbook](maintainer-agent-playbook.md) | How to drive AI agents without reading Dart — copy-paste prompts, smoke role, cadence |
| [Character Card Forge Integration](CharacterCardForge_GroupChat_Integration_Guide.md) | For tool authors writing to the database directly, particularly group chats |
| [Contributing](../CONTRIBUTING.md) | How to set up, what CI checks, and what licence your contributions are under |
| [CLAUDE.md](../CLAUDE.md) | Engineering law for humans and agents. [AGENTS.md](../AGENTS.md) is a short pointer at the same law |

Maintainer working notes (refactor logs, release runbook) live in
[`dev-notes/`](../dev-notes/) and are deliberately kept out of this published
documentation.

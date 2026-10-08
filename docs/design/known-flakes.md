# Known CI flakes

A failed check is read before it is re-run. This is the list of failures
that have been infrastructure or timing rather than the change under test,
with how to tell, and what fixed or would fix each. A failure not on this
list, or one that fails twice, is a regression until shown otherwise.

How to read a failed job: `gh api repos/linux4life1/front-porch-AI/actions/jobs/<job id>/logs`,
then look for the test name and the first `[E]`, `Test failed` or
`##[error]` line. A job whose cancelled step is "Install Linux desktop
dependencies" never ran a test.

## Infrastructure (re-run once, no diagnosis needed)

- **Linux job cancelled inside "Install Linux desktop dependencies"** — the
  apt mirror hung; the job's own limit (45–60 min) was the only clock.
  Fixed: every apt step has `timeout-minutes: 10` and `Acquire::Retries=3`,
  so it now fails in minutes and is re-run.
- **Windows E2E shard: "Building native assets failed" with no cause line**,
  while the other shards built the same commit — runner toolchain.
- **GitHub runner death**: jobs "cancelled" at about 20 minutes with no
  logs at all (`BlobNotFound`), steps without conclusions.
- **Phone WebKit "Target crashed"** mid-sweep — the browser, not the page;
  `web_ui/e2e/support/fixtures.ts` already gives it one retry on CI for a
  crash only.

## Timing in a test (fixed at the cause; listed so a recurrence is noticed)

- **`integration_test/model_downloader_test.dart`**: the tap on the
  "Search / Download" tab landed on the page transition's IgnorePointer
  right after `appState.setIndex(2)`, then a 3-minute wait for the Search
  button. Fixed: `tapWhenHittable` (in `support/e2e_sandbox.dart`) waits
  for the control to be under the pointer.
- **`integration_test/persona_folder_test.dart`**: the same shape, for "New
  Persona" (Windows) and "Move to Folder…" (Linux). Fixed the same way.
- **`web_ui/e2e/sweep.spec.ts` screens 15 and 18 ("every control works",
  90 s)**: the sweep pressed a story job starter (Autopilot, Redistill,
  Outline scenes, Interview) that launched a real run in the app, and every
  tap after it waited out `settle`'s network-idle on a server that never
  went idle, on that screen and the ones after it. Fixed: those verbs are
  on the sweep's skip list with the other job starters.
- **macOS E2E `group_realism_wiring_test`**: "after a reload, no outbound
  prompt carried the stored emotion across two turns" — macOS shard only,
  seen once after the refractory change; the wait around the reload is the
  suspect if it recurs.
- **macOS E2E `message_actions_test`**: "the bubble … was not reachable by
  scrolling the chat list"; seen once.
- **`test/services/auth_service_test.dart` TOTP enrolment**: a 30 s limit
  under a loaded runner; passes alone.
- **`test/services/chat/start_fresh_chat_test.dart` "an empty persona id
  leaves the active persona alone"**: `UNIQUE constraint failed:
  personas.id` once under `--concurrency=4`; a test-isolation slip in that
  file.

## Not flakes, though they look like one

- **"Guard protected paths" red on a PR that edits an existing test, a
  golden, a baseline or `.github/`**: it is asking for the
  `approved-test-change` label, which a maintainer applies after reading
  the change. A promotion candidate (`release/promote-*`) is exempt.
- **Dependabot alerts that stay listed after the fix merged to Rawhide**:
  they are computed against `main` and clear on the next promotion.

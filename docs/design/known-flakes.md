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
  First fix: every apt step got `timeout-minutes: 10` and
  `Acquire::Retries=3`, so it failed in minutes and was re-run. It came back
  as a timeout on #618 and #620: one E2E Linux shard pulled ~150 packages
  from azure.archive.ubuntu.com at several seconds each while its siblings
  took 40 s, and Playwright's `--with-deps` sat on the same mirror for 27+
  minutes. Fixed: `.github/actions/linux-desktop-deps` caches the .debs
  (Actions cache, keyed on the runner image and package list), gives every
  apt network call its own clock, and after a failed first attempt moves
  apt to archive.ubuntu.com for one retry and the rest of the job.
  Playwright's browser libraries go through the same action, and the
  browsers themselves are cached. The nightly, release and beta-release
  Linux builds (step "Install Linux desktop dependencies" there too) call
  the same action, release.yml with the .deb cache off, after the first
  Rawhide nightly timed out on its own plain apt step the same way. The
  scheduled nightly runs main's copy of nightly.yml, so it is covered once
  Rawhide is promoted. The log line `apt-retry: attempt 2
  (fallback mirror) succeeded` means the mirror was slow again and the
  fallback absorbed it; `failed on both mirrors` is still infrastructure.
  Expected in these logs, not regressions: apt's `Download is performed
  unsandboxed as root … couldn't be accessed by user '_apt'` (the cache
  directory sits under the runner's temp folder, which `_apt` cannot
  write; harmless); `Unable to reserve cache … another job may be creating
  this cache` when several shards finish a cold key at once (one saves, the
  rest warn; not a failure); and an install step with no clock of its own,
  on purpose: only the step's `timeout-minutes` bounds it, so no inner
  clock can stop dpkg halfway.
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
- **E2E `message_actions_test`** (macOS, then Linux): "the bubble … was not
  reachable by scrolling the chat list", with only the last three of five
  bubbles built. #403 made the reveal step the list's own ScrollPosition,
  which was needed but not the cause; it came back on 2026-10-10. The
  cause was in the app: the fake backend's two replies are word for word
  the same, and when the second line and its reply landed between two
  rebuilds, the transcript window took them for older history loaded
  above (same last line, longer list) and slid its mounted rows down by
  two. The greeting and the first line left the list, and three short
  rows do not scroll, so nothing could bring them back. Fixed in
  `isTranscriptPrepend` (desktop `transcript_auto_scroll.dart`, phone
  `transcriptAutoScroll.ts`): rows added with the oldest row unchanged are
  an append. Pinned by `transcript_same_reply_append_test.dart` and
  `ChatMessageList.repeatReply.test.tsx`.
- **`web_ui/e2e/journeys.spec.ts` Director Mode journey: the line never
  sent.** The narrator's or the whisper's line never shows (the
  "Narrator" director note not found, or the whisper note missing), on
  phone WebKit (#627) and desktop Chromium (#623). No `POST
  /api/chat/send` for that line is in the trace. Two causes. (1) Enter
  while the page still thought a reply was streaming: `waitIdle` checked
  Send before it polled the host, so it could pass while the composer
  showed Stop, and `send()` keeps the line in the box then, by design.
  #621's second `waitIdle` narrowed this, it did not close it. (2) On
  phone WebKit the narrate `fill()` never reached the box: the trace
  shows it empty at Enter, so `send()` had nothing to send. Fixed:
  composer lines go through `sendLine` (`web_ui/e2e/support/composer.ts`).
  It waits for `waitSendable` (the host idle, then the page showing Send),
  checks the box holds the line, and checks Enter emptied it. It tries
  again only while the line is still in the box, so nothing sends twice.
  A `Composer line retried` warning on a passing run means it caught one.
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

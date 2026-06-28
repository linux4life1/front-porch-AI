# Local widget-golden harness (Linux/amd64 in Docker)

The Flutter **widget pixel goldens** (`test/golden/widget/**`, tag `golden`) are
`@TestOn('linux')` — they **cannot run on macOS at all** and are byte-sensitive
to the OS, FreeType version, and CPU architecture. CI runs them on
`ubuntu-latest` (amd64) with Flutter `3.41.1`.

This folder lets you run/refresh those goldens locally in a container that
mirrors that CI image, so you don't need a CI round-trip for every UI tweak.

## Usage

```bash
# Check goldens (fails on any pixel mismatch) — default:
tools/golden/golden.sh check

# Regenerate after an intentional UI change, then review + commit the PNGs:
tools/golden/golden.sh update
git status --short -- test/golden   # review what moved
```

The script copies the working tree into the container (so `pub get` never
rewrites your host `.dart_tool`), runs the goldens, and — in `update` mode —
copies the refreshed PNGs back into `test/golden/`.

## Requirements

- **Docker Desktop** with **amd64 emulation (Rosetta)** enabled
  (Settings → General → "Use Rosetta for x86/amd64 emulation"). On Apple
  Silicon the image is built/run with `--platform linux/amd64` so it matches the
  amd64 CI runners. The first build downloads the Flutter SDK and warms the
  toolchain under emulation (slow, several minutes); it's cached afterward.

## Authoritative path

This is **best-effort local parity**. The CI `Widget Golden Tests` job stays
authoritative. If a local `check` ever disagrees with CI, regenerate on the real
runner via the **`update-goldens`** workflow
(`.github/workflows/update-goldens.yml`): trigger it from the Actions tab
(`workflow_dispatch`) once it's on the default branch, or push a commit whose
message contains `[update-goldens]`; it uploads the changed PNGs as an artifact
to drop back into the repo.

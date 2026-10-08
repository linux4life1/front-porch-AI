#!/usr/bin/env bash
#
# preflight.sh — what to run before pushing a branch, in one command.
# (Lives in tools/, not scripts/: .gitignore keeps scripts/ for the
# release and gate scripts, which agents never add to.)
#
#   tools/preflight.sh              # changes vs origin/Rawhide
#   tools/preflight.sh --base main  # changes vs another branch
#   tools/preflight.sh --browser    # also the browser suite (web_ui changes)
#   tools/preflight.sh --no-web     # skip the web steps even if web_ui changed
#
# It looks at what the branch changes and runs the checks those files need:
#   - flutter analyze on every changed Dart file (CI's analyze job is the same)
#   - the hygiene ratchets (god files, raw dialogs, raw colours, pickers)
#   - the Dart test files the branch adds or edits
#   - web_ui changed: npm run lint, the vitests, npm run build
#   - --browser (or web_ui changed and not --no-web): the Playwright suite
#     against the real app, which is the only place a web journey runs
# Each failure is named at the end; the exit code is the number of failures.
# It is deliberately the same list CLAUDE.md gives; this is the one place to
# run it from, so an integration of two branches is not pushed with one
# parent's suite unrun.

set -u
BASE="origin/Rawhide"
BROWSER=0
WEB=1
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --browser) BROWSER=1; shift ;;
    --no-web) WEB=0; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)" || exit 2
git fetch --quiet origin 2>/dev/null || true
MB="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "cannot find the merge base with $BASE" >&2; exit 2; }

changed() { git diff --name-only --diff-filter=d "$MB" HEAD -- "$@"; git diff --name-only --diff-filter=d -- "$@"; }
DART=$(changed 'lib/*.dart' 'test/*.dart' 'integration_test/*.dart' | grep -v '\.g\.dart$' | sort -u)
TESTS=$(changed 'test/*_test.dart' | sort -u)
WEB_CHANGED=$(changed 'web_ui/*' | grep -v '^web_ui/e2e/report' | head -1)

failures=()
step() { printf '\n\033[1m• %s\033[0m\n' "$1"; }
run() { "$@" || failures+=("$*"); }

echo "flutter: $(flutter --version 2>/dev/null | head -1)"
echo "base: $BASE ($(git rev-parse --short "$MB"))"

if [ -n "$DART" ]; then
  step "flutter analyze on $(echo "$DART" | wc -l | tr -d ' ') changed Dart file(s)"
  # shellcheck disable=SC2086
  run flutter analyze $DART
else
  echo "no Dart changes"
fi

step "hygiene ratchets"
run flutter test --concurrency=4 test/hygiene/

if [ -n "$TESTS" ]; then
  step "the $(echo "$TESTS" | wc -l | tr -d ' ') test file(s) this branch adds or edits"
  # shellcheck disable=SC2086
  run flutter test --concurrency=4 $TESTS
fi

if [ ! -f assets/web_app/index.html ] && [ "$WEB" -eq 1 ]; then
  step "the WebUI bundle is missing (it is built, not tracked): building it"
  ( cd web_ui && [ -d node_modules ] || npm ci --ignore-scripts; npm run build ) || failures+=("web_ui build")
fi

if [ -n "$WEB_CHANGED" ] && [ "$WEB" -eq 1 ]; then
  step "web_ui: lint, vitests, bundle"
  ( cd web_ui && npm run lint && npm test -- --run && npm run build ) || failures+=("web_ui lint/test/build")
  [ "$BROWSER" -eq 1 ] || { BROWSER=1; echo "web_ui changed: the browser suite runs too (pass --no-web to skip the web steps)"; }
fi

if [ "$BROWSER" -eq 1 ]; then
  step "the browser suite against the real app (one process, several minutes)"
  case "$(uname -s)" in
    Darwin) DEVICE=macos; unset MallocStackLogging MallocStackLoggingNoCompact MallocStackLoggingLite ;;
    Linux) DEVICE=linux ;;
    *) DEVICE=windows ;;
  esac
  run flutter test integration_test/web_ui/browser_test.dart -d "$DEVICE"
fi

echo
if [ "${#failures[@]}" -eq 0 ]; then
  printf '\033[32m✓ preflight clean\033[0m\n'
  exit 0
fi
printf '\033[31m✗ %d step(s) failed:\033[0m\n' "${#failures[@]}"
for f in "${failures[@]}"; do echo "  - $f"; done
exit "${#failures[@]}"

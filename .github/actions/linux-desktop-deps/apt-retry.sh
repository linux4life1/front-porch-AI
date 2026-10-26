#!/usr/bin/env bash
# Runs one apt-backed command as root with a clock on each attempt. If the
# first attempt fails or runs out of time, apt is pointed at
# archive.ubuntu.com instead of the Azure mirror and the command gets one
# more try. The log says which attempt won, so a slow mirror stays visible.
#
#   apt-retry.sh <seconds per attempt> <command> [args...]
#
# Why: docs/design/known-flakes.md, "Install Linux desktop dependencies".
# The mirror switch is left in place on purpose, so later apt calls in the
# same job (Playwright's install-deps in web-e2e) use the mirror that worked.
set -uo pipefail

secs=$1
shift
# The log label is the command without `env`, NAME=value words and
# `-o Name=value` pairs.
words=()
skip=0
for w in "$@"; do
  if [ "$skip" -eq 1 ]; then skip=0; continue; fi
  case "$w" in
    -o) skip=1 ;;
    env | *=*) ;;
    *) words+=("$w") ;;
  esac
done
label=$(printf '%s ' "${words[@]}" | cut -c1-80 | sed 's/ *$//')

attempt() {
  # timeout runs as root so its clock can kill apt and its fetch workers;
  # a runner-owned timeout cannot signal root processes behind sudo.
  sudo env "PATH=$PATH" DEBIAN_FRONTEND=noninteractive \
    timeout -k 10s "${secs}s" "$@"
}

# Hostname swap only, so it covers deb822 (.sources, the 24.04 default),
# one-line .list files and the runner image's apt-mirrors.txt alike.
use_fallback_mirror() {
  local f changed=0
  for f in /etc/apt/apt-mirrors.txt /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    if grep -q 'azure\.archive\.ubuntu\.com' "$f"; then
      sudo sed -i 's/azure\.archive\.ubuntu\.com/archive.ubuntu.com/g' "$f"
      echo "apt-retry: $f now points at archive.ubuntu.com"
      changed=1
    fi
  done
  if [ "$changed" -eq 0 ]; then
    echo "apt-retry: no source names azure.archive.ubuntu.com; retrying as configured"
  fi
}

if attempt "$@"; then
  echo "apt-retry: attempt 1 succeeded: $label"
  exit 0
fi
# Workflow commands must start a line, and a killed apt can leave one
# half-printed, hence the bare `echo`s.
echo
echo "::warning::apt-retry: attempt 1 failed or ran past ${secs}s, retrying once on archive.ubuntu.com: $label"
use_fallback_mirror
# A clock that fired inside dpkg leaves it half-configured; finish that
# first or the retry stops at "dpkg was interrupted".
sudo dpkg --configure -a || true
if attempt "$@"; then
  echo
  echo "::notice::apt-retry: attempt 2 (fallback mirror) succeeded: $label"
  exit 0
fi
echo
echo "::error::apt-retry: failed on both mirrors: $label"
exit 1

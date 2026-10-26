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
#
# On GitHub's Ubuntu 24.04 image the primary path is the mirror list: the
# sources say `URIs: mirror+file:/etc/apt/apt-mirrors.txt`, and swapping the
# host inside apt-mirrors.txt needs no new `apt-get update` (the lists are
# keyed on the mirror+file URI, not the host). A direct azure host in a
# .list or .sources file is different: its lists are keyed on the host, so
# after rewriting one this script runs one bounded `apt-get update` before
# the retry, unless the command refreshes the index itself. Lists fetched
# from azure can lag or lead archive.ubuntu.com, so attempt 2 can rarely
# 404 on a package version; that is a failed attempt, not a hang.
set -uo pipefail

secs=$1
shift
# The log label is the command without `env`, NAME=value words and
# `-o Name=value` pairs. The `-o` pairs and NAME=value words are also kept
# so the index refresh below uses the command's own apt options.
words=()
apt_opts=()
assigns=()
skip=0
for w in "$@"; do
  if [ "$skip" -eq 1 ]; then apt_opts+=(-o "$w"); skip=0; continue; fi
  case "$w" in
    -o) skip=1 ;;
    env) ;;
    *=*) assigns+=("$w") ;;
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
# one-line .list files and the runner image's apt-mirrors.txt alike. Sets
# direct_changed=1 when a file other than apt-mirrors.txt was rewritten.
direct_changed=0
use_fallback_mirror() {
  local f changed=0
  for f in /etc/apt/apt-mirrors.txt /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    if grep -q 'azure\.archive\.ubuntu\.com' "$f"; then
      sudo sed -i 's/azure\.archive\.ubuntu\.com/archive.ubuntu.com/g' "$f"
      echo "apt-retry: $f now points at archive.ubuntu.com"
      changed=1
      if [ "$f" != /etc/apt/apt-mirrors.txt ]; then direct_changed=1; fi
    fi
  done
  if [ "$changed" -eq 0 ]; then
    echo "apt-retry: no source names azure.archive.ubuntu.com; retrying as configured"
  fi
}

# Whether the command refreshes the index on its own (apt-get update, or
# Playwright's install-deps, which runs one first).
refreshes_index() {
  local w
  for w in "${words[@]}"; do
    case "$w" in update | install-deps) return 0 ;; esac
  done
  return 1
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
if [ "$direct_changed" -eq 1 ] && ! refreshes_index; then
  echo "apt-retry: a direct source changed host; refreshing the index (70 s clock) before the retry"
  sudo env "PATH=$PATH" DEBIAN_FRONTEND=noninteractive "${assigns[@]}" \
    timeout -k 10s 70s apt-get "${apt_opts[@]}" update ||
    echo "apt-retry: index refresh failed; retrying anyway"
fi
if attempt "$@"; then
  echo
  echo "::notice::apt-retry: attempt 2 (fallback mirror) succeeded: $label"
  exit 0
fi
echo
echo "::error::apt-retry: failed on both mirrors: $label"
exit 1

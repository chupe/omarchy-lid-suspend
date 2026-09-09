#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chupe.lid-suspend.cleanup.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

cleanup="$plugin_dir/uninstall-cleanup"
[[ -f $cleanup ]] || {
  echo "uninstall-cleanup is missing" >&2
  exit 1
}

export HOME="$tmp_dir/home"
export XDG_RUNTIME_DIR="$tmp_dir/runtime"
export FAKE_CALLS="$tmp_dir/calls"
export FAKE_POWER_PROFILE="$tmp_dir/profile"
export FAKE_UNIT_LOAD_STATE=loaded

mkdir -p "$XDG_RUNTIME_DIR/chupe.lid-suspend"
printf 'power-saver\n' >"$FAKE_POWER_PROFILE"
printf 'balanced\n' >"$XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile"

omarchy-toggle() {
  printf 'toggle %s\n' "$*" >>"$FAKE_CALLS"
}

omarchy() {
  [[ ${1:-} == plugin && ${2:-} == disable && ${3:-} == chupe.lid-suspend ]] || return 2
  printf 'plugin disable %s\n' "$3" >>"$FAKE_CALLS"
}

systemctl() {
  [[ ${1:-} == --user ]] || return 2
  shift

  case "${1:-}" in
    show)
      printf 'systemctl show\n' >>"$FAKE_CALLS"
      printf '%s\n' "$FAKE_UNIT_LOAD_STATE"
      ;;
    stop)
      printf 'systemctl stop\n' >>"$FAKE_CALLS"
      ;;
    *)
      return 2
      ;;
  esac
}

powerprofilesctl() {
  case "${1:-}" in
    get)
      cat "$FAKE_POWER_PROFILE"
      ;;
    set)
      printf 'profile set %s\n' "$2" >>"$FAKE_CALLS"
      printf '%s\n' "$2" >"$FAKE_POWER_PROFILE"
      ;;
    *)
      return 2
      ;;
  esac
}

export -f omarchy-toggle omarchy systemctl powerprofilesctl

bash "$cleanup"
mapfile -t calls <"$FAKE_CALLS"
[[ ${calls[*]} == "toggle lid-suspend-off off plugin disable chupe.lid-suspend systemctl show systemctl stop profile set balanced" ]]
[[ $(<"$FAKE_POWER_PROFILE") == balanced ]]
[[ ! -e $XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile ]]

: >"$FAKE_CALLS"
export FAKE_UNIT_LOAD_STATE=not-found
bash "$cleanup"
mapfile -t calls <"$FAKE_CALLS"
[[ ${calls[*]} == "toggle lid-suspend-off off plugin disable chupe.lid-suspend systemctl show" ]]

bash "$cleanup" --help | grep -q '^Usage:'
if bash "$cleanup" invalid >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then
  echo "invalid argument unexpectedly succeeded" >&2
  exit 1
fi
grep -q '^Usage:' "$tmp_dir/stderr"

echo "uninstall-cleanup tests passed"

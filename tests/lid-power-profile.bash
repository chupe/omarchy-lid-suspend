#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chupe.lid-suspend.power-profile.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

export XDG_RUNTIME_DIR="$tmp_dir/runtime"
export FAKE_POWER_PROFILE="$tmp_dir/profile"
mkdir -p "$XDG_RUNTIME_DIR"
printf 'balanced\n' >"$FAKE_POWER_PROFILE"

powerprofilesctl() {
  case "$1" in
    get)
      cat "$FAKE_POWER_PROFILE"
      ;;
    set)
      printf '%s\n' "$2" >"$FAKE_POWER_PROFILE"
      ;;
    *)
      return 2
      ;;
  esac
}
export -f powerprofilesctl

profile_state="$XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile"
script="$plugin_dir/lid-power-profile"

bash "$script" close
[[ $(<"$FAKE_POWER_PROFILE") == power-saver ]]
[[ $(<"$profile_state") == balanced ]]

bash "$script" close
[[ $(<"$profile_state") == balanced ]]

bash "$script" open
[[ $(<"$FAKE_POWER_PROFILE") == balanced ]]
[[ ! -e $profile_state ]]

bash "$script" open
[[ $(<"$FAKE_POWER_PROFILE") == balanced ]]

printf 'power-saver\n' >"$FAKE_POWER_PROFILE"
bash "$script" close
bash "$script" open
[[ $(<"$FAKE_POWER_PROFILE") == power-saver ]]

bash "$script" --help | grep -q '^Usage:'
if bash "$script" invalid >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then
  echo "invalid action unexpectedly succeeded" >&2
  exit 1
fi
grep -q '^Usage:' "$tmp_dir/stderr"

echo "lid-power-profile tests passed"

#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chupe.lid-suspend.power-profile.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

export XDG_RUNTIME_DIR="$tmp_dir/runtime"
export FAKE_POWER_PROFILE="$tmp_dir/profile"
mkdir -m 700 "$XDG_RUNTIME_DIR"
printf 'balanced\n' >"$FAKE_POWER_PROFILE"

powerprofilesctl() {
  case "$1" in
    get)
      cat "$FAKE_POWER_PROFILE"
      ;;
    set)
      if [[ $2 == power-saver && ${BLOCK_CLOSE:-0} == 1 ]]; then
        printf 'started\n' >"$CLOSE_STARTED_FIFO"
        read -r <"$CLOSE_RELEASE_FIFO"
      fi
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

printf 'balanced\n' >"$FAKE_POWER_PROFILE"
rm -f "$profile_state"
started_fifo="$tmp_dir/close-started"
release_fifo="$tmp_dir/close-release"
mkfifo "$started_fifo" "$release_fifo"
export BLOCK_CLOSE=1
export CLOSE_STARTED_FIFO="$started_fifo"
export CLOSE_RELEASE_FIFO="$release_fifo"

bash "$script" close &
close_pid=$!
read -r started <"$started_fifo"
[[ $started == started ]]

lock_file="$XDG_RUNTIME_DIR/chupe.lid-suspend/power-profile.lock"
if flock --nonblock "$lock_file" true; then
  printf 'release\n' >"$release_fifo"
  wait "$close_pid"
  echo "profile transition lock was not held during powerprofilesctl" >&2
  exit 1
fi

printf 'release\n' >"$release_fifo"
wait "$close_pid"
unset BLOCK_CLOSE CLOSE_STARTED_FIFO CLOSE_RELEASE_FIFO

bash "$script" --help | grep -q '^Usage:'
if bash "$script" invalid >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then
  echo "invalid action unexpectedly succeeded" >&2
  exit 1
fi
grep -q '^Usage:' "$tmp_dir/stderr"

echo "lid-power-profile tests passed"

#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
control="$plugin_dir/inhibitor-control"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chupe.lid-suspend.inhibitor.XXXXXX")
fake_child_pid_file="$tmp_dir/fake-child-pid"

cleanup() {
  local pid

  if [[ -f $fake_child_pid_file ]]; then
    pid=$(<"$fake_child_pid_file")
    kill "$pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

[[ -f $control ]] || {
  echo "inhibitor-control is missing" >&2
  exit 1
}

export XDG_RUNTIME_DIR="$tmp_dir/runtime"
export FAKE_CALLS="$tmp_dir/calls"
export FAKE_UNIT_STATE="$tmp_dir/unit-state"
export FAKE_CHILD_PID_FILE="$fake_child_pid_file"
export FAKE_LOAD_STATE=loaded
mkdir -p "$XDG_RUNTIME_DIR"
printf 'inactive\n' >"$FAKE_UNIT_STATE"

systemctl() {
  [[ ${1:-} == --user ]] || return 2
  shift

  case "${1:-}" in
    is-active)
      [[ $(<"$FAKE_UNIT_STATE") == active ]]
      ;;
    reset-failed)
      printf 'reset-failed\n' >>"$FAKE_CALLS"
      ;;
    show)
      printf '%s\n' "$FAKE_LOAD_STATE"
      ;;
    stop)
      printf 'stop\n' >>"$FAKE_CALLS"
      printf 'inactive\n' >"$FAKE_UNIT_STATE"
      ;;
    *)
      return 2
      ;;
  esac
}

systemd-run() {
  printf '%s\n' "$BASHPID" >"$FAKE_CHILD_PID_FILE"
  printf 'systemd-run\n' >>"$FAKE_CALLS"
  if [[ ${BLOCK_START:-0} == 1 ]]; then
    printf 'started\n' >"$STARTED_FIFO"
    read -r <"$RELEASE_FIFO"
  fi
  printf 'active\n' >"$FAKE_UNIT_STATE"
  if [[ ${BLOCK_START:-0} == 1 ]]; then
    printf 'finished\n' >"$FINISHED_FIFO"
  fi
}

export -f systemctl systemd-run

[[ $(bash "$control" hold) == held ]]
[[ $(<"$FAKE_UNIT_STATE") == active ]]
[[ $(bash "$control" release) == released ]]
[[ $(<"$FAKE_UNIT_STATE") == inactive ]]

started_fifo="$tmp_dir/started"
release_fifo="$tmp_dir/release"
finished_fifo="$tmp_dir/finished"
mkfifo "$started_fifo" "$release_fifo" "$finished_fifo"
export BLOCK_START=1
export STARTED_FIFO="$started_fifo"
export RELEASE_FIFO="$release_fifo"
export FINISHED_FIFO="$finished_fifo"

bash "$control" hold >"$tmp_dir/hold-output" &
holder_pid=$!
read -r started <"$started_fifo"
[[ $started == started ]]

kill "$holder_pid"
wait "$holder_pid" 2>/dev/null || true

lock_file="$XDG_RUNTIME_DIR/chupe.lid-suspend/inhibitor.lock"
if flock --nonblock "$lock_file" true; then
  echo "inhibitor lock was released before the surviving child exited" >&2
  exit 1
fi

printf 'release\n' >"$release_fifo"
read -r finished <"$finished_fifo"
[[ $finished == finished ]]
[[ $(<"$FAKE_UNIT_STATE") == active ]]

[[ $(bash "$control" release) == released ]]
[[ $(<"$FAKE_UNIT_STATE") == inactive ]]

echo "inhibitor-control tests passed"

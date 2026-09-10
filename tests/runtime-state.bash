#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state_tool="$plugin_dir/runtime_state.py"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/chupe.lid-suspend.runtime-state.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT

[[ -f $state_tool ]] || {
  echo "runtime-state is missing" >&2
  exit 1
}

export XDG_RUNTIME_DIR="$tmp_dir/runtime"
mkdir -m 700 "$XDG_RUNTIME_DIR"

python3 "$state_tool" write previous-power-profile balanced
[[ $(python3 "$state_tool" read previous-power-profile) == balanced ]]
[[ $(stat -c %a "$XDG_RUNTIME_DIR/chupe.lid-suspend") == 700 ]]

victim="$tmp_dir/victim"
printf 'untouched\n' >"$victim"
rm -f "$XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile"
ln -s "$victim" "$XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile"
ln -s "$victim" "$XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile.tmp"
python3 "$state_tool" write previous-power-profile performance
[[ $(<"$victim") == untouched ]]
[[ $(python3 "$state_tool" read previous-power-profile) == performance ]]
[[ -L $XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile.tmp ]]
rm -f "$XDG_RUNTIME_DIR/chupe.lid-suspend/previous-power-profile.tmp"

lock_path="$XDG_RUNTIME_DIR/chupe.lid-suspend/power-profile.lock"
ln -s "$victim" "$lock_path"
if python3 "$state_tool" with-lock power-profile.lock true; then
  echo "symlinked lock file unexpectedly succeeded" >&2
  exit 1
fi
[[ $(<"$victim") == untouched ]]
rm -f "$lock_path"

ln "$victim" "$lock_path"
if python3 "$state_tool" with-lock power-profile.lock true; then
  echo "hard-linked lock file unexpectedly succeeded" >&2
  exit 1
fi
[[ $(<"$victim") == untouched ]]
rm -f "$lock_path"

python3 "$state_tool" remove previous-power-profile
if python3 "$state_tool" read previous-power-profile; then
  echo "missing state unexpectedly succeeded" >&2
  exit 1
else
  [[ $? == 3 ]]
fi

chmod 755 "$XDG_RUNTIME_DIR/chupe.lid-suspend"
python3 "$state_tool" write previous-power-profile balanced
[[ $(stat -c %a "$XDG_RUNTIME_DIR/chupe.lid-suspend") == 700 ]]
python3 "$state_tool" remove previous-power-profile

rm -rf "$XDG_RUNTIME_DIR/chupe.lid-suspend"
mkdir "$tmp_dir/redirected-state"
ln -s "$tmp_dir/redirected-state" "$XDG_RUNTIME_DIR/chupe.lid-suspend"
if python3 "$state_tool" write previous-power-profile power-saver; then
  echo "symlinked state directory unexpectedly succeeded" >&2
  exit 1
fi
[[ ! -e $tmp_dir/redirected-state/previous-power-profile ]]

bad_runtime="$tmp_dir/bad-runtime"
mkdir -m 755 "$bad_runtime"
if XDG_RUNTIME_DIR="$bad_runtime" \
  python3 "$state_tool" write previous-power-profile balanced; then
  echo "shared runtime directory unexpectedly succeeded" >&2
  exit 1
fi

real_runtime="$tmp_dir/real-runtime"
mkdir -m 700 "$real_runtime"
ln -s "$real_runtime" "$tmp_dir/runtime-link"
if XDG_RUNTIME_DIR="$tmp_dir/runtime-link" \
  python3 "$state_tool" write previous-power-profile balanced; then
  echo "symlinked runtime directory unexpectedly succeeded" >&2
  exit 1
fi

echo "runtime-state tests passed"

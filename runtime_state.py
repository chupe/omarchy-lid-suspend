from __future__ import annotations

import fcntl
import os
import secrets
import stat
import subprocess
import sys
from collections.abc import Generator
from contextlib import contextmanager
from typing import Final

STATE_DIR: Final = "chupe.lid-suspend"
STATE_FILES: Final = frozenset({"previous-power-profile"})
LOCK_FILES: Final = frozenset({"inhibitor.lock", "power-profile.lock"})
MAX_VALUE_BYTES: Final = 64


class RuntimeStateError(Exception):
    message: str

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(message)


def open_runtime_root() -> int:
    path = os.environ.get("XDG_RUNTIME_DIR")
    if path is None or not os.path.isabs(path):
        raise RuntimeStateError("XDG_RUNTIME_DIR must be an absolute path")

    absolute = os.path.abspath(path)
    if os.path.realpath(absolute) != absolute:
        raise RuntimeStateError("XDG_RUNTIME_DIR must not contain symlinks")

    path_stat = os.lstat(absolute)
    if not stat.S_ISDIR(path_stat.st_mode):
        raise RuntimeStateError("XDG_RUNTIME_DIR must be a directory")
    if path_stat.st_uid != os.geteuid():
        raise RuntimeStateError("XDG_RUNTIME_DIR must be owned by the current user")
    if stat.S_IMODE(path_stat.st_mode) & 0o077:
        raise RuntimeStateError("XDG_RUNTIME_DIR must not be accessible by other users")

    root_fd = os.open(
        absolute,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
    )
    opened_stat = os.fstat(root_fd)
    if (opened_stat.st_dev, opened_stat.st_ino) != (
        path_stat.st_dev,
        path_stat.st_ino,
    ):
        os.close(root_fd)
        raise RuntimeStateError("XDG_RUNTIME_DIR changed while opening")
    return root_fd


@contextmanager
def open_state_dir() -> Generator[int, None, None]:
    root_fd = open_runtime_root()
    try:
        try:
            os.mkdir(STATE_DIR, 0o700, dir_fd=root_fd)
        except FileExistsError:
            pass

        state_fd = os.open(
            STATE_DIR,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=root_fd,
        )
        try:
            state_stat = os.fstat(state_fd)
            if state_stat.st_uid != os.geteuid():
                raise RuntimeStateError("runtime state directory has the wrong owner")
            os.fchmod(state_fd, 0o700)
            yield state_fd
        finally:
            os.close(state_fd)
    finally:
        os.close(root_fd)


def require_name(name: str, allowed: frozenset[str]) -> str:
    if name not in allowed:
        raise RuntimeStateError(f"unsupported runtime state name: {name}")
    return name


def require_regular_owned_file(file_fd: int, label: str) -> None:
    file_stat = os.fstat(file_fd)
    if not stat.S_ISREG(file_stat.st_mode):
        raise RuntimeStateError(f"{label} must be a regular file")
    if file_stat.st_uid != os.geteuid():
        raise RuntimeStateError(f"{label} has the wrong owner")
    if file_stat.st_nlink != 1:
        raise RuntimeStateError(f"{label} must not be hard-linked")
    os.fchmod(file_fd, 0o600)


def write_state(name: str, value: str) -> None:
    safe_name = require_name(name, STATE_FILES)
    encoded = f"{value}\n".encode()
    if len(encoded) > MAX_VALUE_BYTES or "\n" in value:
        raise RuntimeStateError("runtime state value is invalid")

    with open_state_dir() as state_fd:
        temporary_name = f".{safe_name}.{secrets.token_hex(16)}.tmp"
        temporary_fd = os.open(
            temporary_name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
            dir_fd=state_fd,
        )
        try:
            with os.fdopen(temporary_fd, "wb", closefd=False) as temporary:
                written = temporary.write(encoded)
                if written != len(encoded):
                    raise RuntimeStateError("runtime state write was incomplete")
                temporary.flush()
                os.fsync(temporary_fd)
            os.replace(
                temporary_name,
                safe_name,
                src_dir_fd=state_fd,
                dst_dir_fd=state_fd,
            )
            os.fsync(state_fd)
        except OSError:
            try:
                os.unlink(temporary_name, dir_fd=state_fd)
            except FileNotFoundError:
                pass
            raise
        finally:
            os.close(temporary_fd)


def read_state(name: str) -> str | None:
    safe_name = require_name(name, STATE_FILES)
    with open_state_dir() as state_fd:
        try:
            state_file_fd = os.open(
                safe_name,
                os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC,
                dir_fd=state_fd,
            )
        except FileNotFoundError:
            return None

        try:
            require_regular_owned_file(state_file_fd, safe_name)
            content = os.read(state_file_fd, MAX_VALUE_BYTES + 1)
        finally:
            os.close(state_file_fd)

    if len(content) > MAX_VALUE_BYTES:
        raise RuntimeStateError("runtime state value is too large")
    return content.decode().rstrip("\n")


def remove_state(name: str) -> None:
    safe_name = require_name(name, STATE_FILES)
    with open_state_dir() as state_fd:
        try:
            state_stat = os.stat(safe_name, dir_fd=state_fd, follow_symlinks=False)
        except FileNotFoundError:
            return
        if (
            not stat.S_ISREG(state_stat.st_mode)
            or state_stat.st_uid != os.geteuid()
            or state_stat.st_nlink != 1
        ):
            raise RuntimeStateError(f"{safe_name} is not a current-user regular file")
        os.unlink(safe_name, dir_fd=state_fd)
        os.fsync(state_fd)


def run_with_lock(name: str, command: list[str]) -> int:
    safe_name = require_name(name, LOCK_FILES)
    if not command:
        raise RuntimeStateError("with-lock requires a command")

    with open_state_dir() as state_fd:
        lock_fd = os.open(
            safe_name,
            os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
            dir_fd=state_fd,
        )
        require_regular_owned_file(lock_fd, safe_name)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        try:
            completed = subprocess.run(
                command,
                check=False,
                pass_fds=(lock_fd,),
            )
            return completed.returncode
        finally:
            os.close(lock_fd)


def run(arguments: list[str]) -> int:
    match arguments:
        case ["write", name, value]:
            write_state(name, value)
        case ["read", name]:
            value = read_state(name)
            if value is None:
                return 3
            print(value)
        case ["remove", name]:
            remove_state(name)
        case ["with-lock", name, *command] if command:
            return run_with_lock(name, command)
        case ["-h" | "--help"]:
            print("Usage: runtime-state write|read|remove|with-lock ...")
        case _:
            print(
                "Usage: runtime-state write|read|remove|with-lock ...", file=sys.stderr
            )
            return 2
    return 0


def main() -> int:
    try:
        return run(sys.argv[1:])
    except (RuntimeStateError, OSError, UnicodeError) as error:
        print(f"runtime-state: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

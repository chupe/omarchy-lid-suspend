# Contributing to Lid Suspend

## Quickshell Pre-Fix Development Gate

Apply this gate while the installed Quickshell build lacks upstream fix
[`afb2c27`](https://github.com/quickshell-mirror/quickshell/commit/afb2c27cd6d600d221d9379a332ee1b321a68487)
or an equivalent backport. `quickshell 0.3.1-1` predates the fix; version alone
does not prove a later package contains it. That commit only removes the abort:
`QSWaylandSessionLockManager::active` is still cleared only by `unlock()`, so a
lock destroyed by a plugin reload leaves a dangling pointer and the recovered
lock can never be acquired again by that process (tracked in
[Quickshell #1054](https://github.com/quickshell-mirror/quickshell/issues/1054)).
Remove this gate only after the installed package is confirmed to include both
fixes.

Before changing lid, suspend, or session-lock behavior, and before every write
that can hot-reload this plugin, run:

```bash
omarchy-shell lock status
```

Proceed only when `locked`, `requested`, `pending`, `sessionLocked`, and
`secure` are all `false`. If status is unavailable or any field is `true`,
pause and ask the user to unlock or recover the session before writing files,
restarting the shell, or running `rescanPlugins`.

The shell's plugin watcher is `inotifywait -r` on `~/.config/omarchy/plugins`
and does not descend into a symlinked plugin directory, so edits made through
a stow symlink do not hot-reload; apply them with
`omarchy-shell shell rescanPlugins`, which is subject to the same gate.

Keep the session unlocked until the hot reload settles and shell health checks
pass. Run lid, suspend, and lock integration checks only after file writes and
plugin reloads have stopped; never overlap those checks with a save or reload.

## Failure Mechanism

Affected Quickshell builds can fail to acquire a Wayland session lock, clear
the requested lock target, then still call `updateSurfaces(true)`. The missing
owned lock triggers a deliberate `qFatal()` and `SIGABRT`. Omarchy plugin reload
can expose this path by destroying and recreating services around an active or
stranded lock. See [Quickshell #296](https://github.com/quickshell-mirror/quickshell/issues/296)
(closed by `afb2c27`), [#1054](https://github.com/quickshell-mirror/quickshell/issues/1054)
(open: Omarchy plugin reload over a stranded lock, dangling `active` pointer)
and [#1086](https://github.com/quickshell-mirror/quickshell/issues/1086)
(open: abort on failed lock request, `onScreensChanged` race).

## Validation

After each QML reload, verify shell, plugin, and lock state before testing a lid
transition:

```bash
omarchy-shell shell ping
omarchy-shell chupe.lid-suspend status
omarchy-shell lock status
```

The shell must answer, plugin status must match expected state, and lock status
must remain fully clear before any separate lock or lid-close test.

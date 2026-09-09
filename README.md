# Lid Suspend

Omarchy shell plugin: a bar icon that shows and toggles whether closing the
laptop lid suspends the machine. Companion to the stock Stay Awake indicator,
which only covers idle lock and screensaver.

The setting survives reboots and shell restarts, and it is a plain flag file,
so keybinds, menu rows, and your own lid scripts can read or flip it.
While lid suspend is disabled, closing the lid selects the power-saver profile
and opening it restores the previous profile.

## Install

```bash
omarchy plugin add https://github.com/chupe/omarchy-lid-suspend.git --enable
```

Keep the session unlocked while Omarchy loads or updates the plugin.

Optional: sit it next to the stock indicators so it reads as one of them.

```bash
omarchy bar move chupe.lid-suspend --after omarchy.indicators
```

## Update

Keep the session unlocked, then update through Omarchy:

```bash
omarchy plugin update chupe.lid-suspend
```

## Disable or uninstall

```bash
bash ~/.config/omarchy/plugins/chupe.lid-suspend/uninstall-cleanup
```

Cleanup clears the setting, disables and unloads the plugin, releases the
transient inhibitor, and restores any power profile saved for the current
lid-close cycle. To remove the plugin after cleanup succeeds:

```bash
omarchy plugin remove chupe.lid-suspend
```

## Dependencies

Stock Omarchy Quattro provides every runtime dependency:

- Omarchy: `omarchy-shell`, `omarchy-toggle`, `omarchy-toggle-enabled`
- systemd: `systemctl`, `systemd-run`, `systemd-inhibit`, `busctl`
- D-Bus and UPower: `dbus-monitor`, `org.freedesktop.UPower`
- power-profiles-daemon: `powerprofilesctl`
- util-linux: `flock`

No extra package, sudo, pkexec, system unit, or configuration file is required.

## Development

The project-scoped mise config pins ShellCheck, aqtinstall, and Qt. Qt stays in
mise's data directory and is activated only inside this project.

```bash
mise install
mise run check
```

## How it works

- State is the flag file `~/.local/state/omarchy/toggles/lid-suspend-off`,
  written with the stock `omarchy-toggle lid-suspend-off` and readable with
  `omarchy-toggle-enabled lid-suspend-off`. Named for the off state like
  `suspend-off` and `screensaver-off`.
- While the flag is set, the service keeps the transient user unit
  `chupe.lid-suspend-inhibit.service` running, which holds one
  `systemd-inhibit --what=handle-lid-switch --mode=block` inhibitor. logind
  always honors that inhibitor type, so lid close no longer suspends. Manual
  suspend and idle behavior are untouched.
- The unit belongs to `systemd --user`, not the shell, so a shell reload,
  restart, or crash neither drops nor duplicates the inhibitor. Every read of
  the flag reconciles the unit to it.
- While Ignore Lid Close is enabled, UPower lid events select `power-saver` on
  close. The profile active before close is saved under `$XDG_RUNTIME_DIR` and
  restored on open or disable, including across shell reloads.
- Profile transitions use a runtime-directory lock, so cleanup waits for any
  transition that survived service teardown before restoring the saved profile.
- The icon behaves like an `omarchy.indicators` entry: collapsed while
  inactive, dimmed on hover of the bar's center section, full while active.
  `alwaysShow: true` in the widget settings keeps it visible.

Omarchy's own lid handling still runs: with no external display the session
locks on lid close, with one attached the internal panel blanks.

## Surfaces

| Surface | Command |
|---|---|
| Bar icon | click |
| Shell IPC | `omarchy-shell chupe.lid-suspend status\|enable\|disable\|toggle` |
| Any script | `omarchy-toggle lid-suspend-off [toggle\|on\|off]` |
| Inhibitor | `systemctl --user status chupe.lid-suspend-inhibit.service` |

Optional menu row for `~/.config/omarchy/extensions/omarchy-menu.jsonc`,
shaped like the stock Stay Awake row:

```jsonc
"trigger.toggle.lid-suspend": {"icon":"󰌢","label":"Ignore Lid Close","action":"omarchy-toggle lid-suspend-off","checked":"omarchy-toggle-enabled lid-suspend-off"},
```

Remove that row manually when uninstalling; plugins cannot modify the shared
menu extension file safely.

## Custom lid handlers

If your logind config ignores the lid switch and a Hyprland bind decides
suspend, gate that decision on the same flag:

```bash
omarchy-toggle-enabled lid-suspend-off && exit 0
```

## License

MIT, see [LICENSE](LICENSE).

# Lid Suspend

Omarchy shell plugin: a bar icon that shows and toggles whether closing the
laptop lid suspends the machine. Companion to the stock Stay Awake indicator,
which only covers idle lock and screensaver.

The setting survives reboots and shell restarts, and it is a plain flag file,
so keybinds, menu rows, and your own lid scripts can read or flip it.

## Install

```bash
omarchy plugin add https://github.com/chupe/omarchy-lid-suspend.git --enable
```

Optional: sit it next to the stock indicators so it reads as one of them.

```bash
omarchy bar put chupe.lid-suspend --after omarchy.indicators
```

## Uninstall

```bash
omarchy plugin remove chupe.lid-suspend
rm -f ~/.local/state/omarchy/toggles/lid-suspend-off
```

Removing the plugin releases the inhibitor. The second line clears the saved
state; skip it if you plan to reinstall.

## Dependencies

None beyond Omarchy Quattro (`omarchy-shell`, `omarchy-toggle`) and
`systemd-logind`. No sudo or pkexec is required.

## How it works

- State is the flag file `~/.local/state/omarchy/toggles/lid-suspend-off`,
  written with the stock `omarchy-toggle lid-suspend-off` and readable with
  `omarchy-toggle-enabled lid-suspend-off`. Named for the off state like
  `suspend-off` and `screensaver-off`.
- While the flag is set, the service holds one
  `systemd-inhibit --what=handle-lid-switch --mode=block` inhibitor. logind
  always honors that inhibitor type, so lid close no longer suspends. Manual
  suspend and idle behavior are untouched.
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

Optional menu row for `~/.config/omarchy/extensions/omarchy-menu.jsonc`,
shaped like the stock Stay Awake row:

```jsonc
"trigger.toggle.lid-suspend": {"icon":"󰌢","label":"Ignore Lid Close","action":"omarchy-toggle lid-suspend-off"},
```

## Custom lid handlers

If your logind config ignores the lid switch and a Hyprland bind decides
suspend, gate that decision on the same flag:

```bash
omarchy-toggle-enabled lid-suspend-off && exit 0
```

## License

MIT, see [LICENSE](LICENSE).

# Pomo Doro for Omarchy

A live pomodoro countdown in the Omarchy bar, sharing one session with the
[pomo-doro](https://github.com/dandrok/pomo_doro) terminal app.

```
◈ 18:42
```

Start a focus block from the bar with no terminal open, or start it in a
terminal and watch it in the bar — it is the same session either way. Pausing
in one place pauses it in the other, and every completed pomodoro lands in the
same history the terminal app shows.

## How it works

pomo-doro elects exactly one process to run the clock, claimed by binding a
unix socket in `XDG_RUNTIME_DIR`. That owner publishes its state to
`~/.config/pomo-doro-nodejs/state.json` once a second and takes commands on
the socket.

This widget owns no clock. It watches the state file and shells out to `pomo`
for anything that changes state, so the bar and the terminal cannot drift
apart — there is only ever one timer.

```
        owner (runs the clock, writes history)
        ├── pomo start   detached, no terminal   ← the Start button
        └── pomo         terminal UI

        views
        ├── this widget  reads state.json, runs `pomo <verb>`
        └── pomo         attaches when an owner already exists
```

If the owner is killed outright, no further writes arrive and the widget
clears itself after five seconds rather than showing a countdown frozen at
whatever second the process died on.

## Requirements

- Omarchy 4.0 or newer
- `pomo-doro-tui` **1.16.0 or newer** on your `PATH` — earlier versions have no
  state file and no CLI verbs, so the widget will sit permanently idle

```bash
npm install -g pomo-doro-tui
pomo --help    # should list start, pause, skip, ...
```

## Install

```bash
omarchy plugin add https://github.com/dandrok/omarchy-pomo-doro.git --enable
```

Plugins land disabled so you can read the code first; `--enable` skips that.
To install by hand instead:

```bash
git clone https://github.com/dandrok/omarchy-pomo-doro.git \
  ~/.config/omarchy/plugins/io.github.dandrok.pomo-doro
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.dandrok.pomo-doro
```

Move it around the bar with `omarchy bar move io.github.dandrok.pomo-doro
--section right`, and turn it off with `omarchy plugin disable
io.github.dandrok.pomo-doro`.

## Using it

| Where | Action | Does |
|---|---|---|
| Bar | Left click | Open the popup |
| Bar | Right click | Pause / resume, or start when idle |
| Bar | Middle click | Skip to the next phase |
| Popup | `p` | Pause / resume, or start when idle |
| Popup | `s` | Skip |
| Popup | `r` | Restart the current phase |
| Popup | `x` | Stop the session |
| Popup | `t` | Open the terminal app on this session |

The popup also shows today's focus time, pomodoro count, progress toward your
daily goal, and the last 14 days as a heatmap.

### Keybindings

Every action is on the shell IPC target `pomo-doro`, so you can bind it in
`~/.config/hypr/bindings.lua` without a terminal:

```lua
o.bind("SUPER SHIFT", "P", "omarchy-shell pomo-doro togglePause")
o.bind("SUPER SHIFT", "S", "omarchy-shell pomo-doro skip")
```

Available: `start`, `pause`, `resume`, `togglePause`, `skip`, `reset`, `stop`,
`open`, `close`, `toggle`.

## Settings

Set these on the widget's entry in `~/.config/omarchy/shell.json`, or through
Setup > Plugins. The file hot-reloads on save.

| Key | Default | What it does |
|---|---|---|
| `command` | `pomo` | The pomo-doro binary |
| `statePath` | `~/.config/pomo-doro-nodejs/state.json` | Session state file |
| `hideWhenIdle` | `false` | Take no room in the bar unless a session is running |
| `showSeconds` | `true` | Off shows whole minutes, which is calmer to glance at |
| `notifyPhaseChange` | `false` | See the note below |
| `defaultFocus` | `25` | Minutes used by the Start button |
| `defaultShortBreak` | `5` | |
| `defaultLongBreak` | `15` | |
| `defaultTag` | `""` | Tag for sessions started from the bar; empty reuses the last one |
| `terminalCommand` | `xdg-terminal-exec … pomo` | How the popup opens the terminal app |
| `workIcon` / `shortBreakIcon` / `longBreakIcon` / `idleIcon` | `◈` `◇` `◆` `󰔟` | Bar glyphs |

Example:

```json
{
  "id": "io.github.dandrok.pomo-doro",
  "hideWhenIdle": true,
  "showSeconds": false,
  "defaultFocus": 45,
  "defaultTag": "Coding"
}
```

### About `notifyPhaseChange`

The CLI already sends its own `notify-send` notification when a phase ends, so
turning this on gives you each transition twice. Turn it on only if you prefer
the shell's notifications, and mute the CLI's in the terminal app's Settings
(`m` on the timer screen) first.

## Troubleshooting

**The widget is always idle.** Check the state file is being written:

```bash
pomo start -w 1 && sleep 2 && cat ~/.config/pomo-doro-nodejs/state.json
```

Note the `-nodejs` suffix — that is `conf`'s default project suffix, and the
path is easy to get wrong by hand. If the file is missing, your `pomo-doro-tui`
predates the state file; upgrade it.

**Buttons do nothing.** The popup shows the CLI's error text under the
controls. Most often `pomo` is not on the `PATH` the shell was started with;
set `command` to an absolute path.

**Nothing reloads after an edit.** Saving under `~/.config/omarchy/plugins/`
reloads plugin code automatically. Force it with `omarchy-shell shell
rescanPlugins`.

## License

ISC

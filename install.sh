#!/bin/bash

# Install (or re-install after an edit) the Pomo Doro shell plugin.
#
# Omarchy discovers plugins under ~/.config/omarchy/plugins/<plugin-id>/, and
# the files have to be copied there rather than symlinked: the shell watches
# that tree with `inotifywait -r`, which does not follow symlinks, so a
# symlinked plugin loads once and then never picks up an edit again.
#
# Run this again after changing any .qml file or manifest.json.
#
# Pass --no-restart to copy without restarting the shell (the new code will not
# take effect until the shell restarts on its own).

set -euo pipefail

PLUGIN_ID="io.github.dandrok.pomo-doro"
RESTART=1

# Reject anything unrecognised rather than ignoring it: a typo like --norestart
# would otherwise look accepted while the shell restarted anyway.
while (( $# > 0 )); do
  case "$1" in
    --no-restart) RESTART=0 ;;
    -h|--help)
      echo "Usage: install.sh [--no-restart]"
      exit 0
      ;;
    *)
      echo "install.sh: unknown option '$1' (supported: --no-restart)" >&2
      exit 1
      ;;
  esac
  shift
done

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

[[ -f "$SOURCE_DIR/manifest.json" ]] || {
  echo "install.sh: no manifest.json next to this script" >&2
  exit 1
}

# Validate before overwriting a working copy: the plugin runs unsandboxed inside
# the long-lived shell process, so a broken manifest is better caught here.
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$SOURCE_DIR"
fi

# Without nullglob an empty match leaves the pattern itself in the loop variable,
# so a run from the wrong directory would copy nothing and still claim success.
shopt -s nullglob
qml_files=("$SOURCE_DIR"/*.qml)
shopt -u nullglob

# The manifest names Panel.qml as the entry point; installing without it leaves a
# plugin the shell discovers and then fails to load.
[[ -f "$SOURCE_DIR/Panel.qml" ]] || {
  echo "install.sh: Panel.qml is missing from $SOURCE_DIR" >&2
  exit 1
}

mkdir -p "$TARGET_DIR"

# Copy the plugin payload: the manifest, every QML file, and the docs. Copying
# all *.qml rather than a hand-written list means a newly added component cannot
# be left behind - which silently breaks the plugin at load time. Everything
# else in the repo (.git, these scripts) is deliberately not copied.
cp -f "$SOURCE_DIR/manifest.json" "$TARGET_DIR/manifest.json"
[[ -f "$SOURCE_DIR/README.md" ]] && cp -f "$SOURCE_DIR/README.md" "$TARGET_DIR/README.md"
[[ -f "$SOURCE_DIR/LICENSE" ]] && cp -f "$SOURCE_DIR/LICENSE" "$TARGET_DIR/LICENSE"
for qml in "${qml_files[@]}"; do
  cp -f "$qml" "$TARGET_DIR/$(basename "$qml")"
done

echo "Installed $PLUGIN_ID to $TARGET_DIR (${#qml_files[@]} QML file(s))"

# The widget draws a state file the CLI writes and shells out to `pomo` for
# every action, so a missing or too-old CLI is a plugin that installs cleanly
# and then sits idle forever. Say so here rather than leaving it to be
# discovered as an empty bar slot.
if ! command -v pomo >/dev/null 2>&1; then
  echo >&2
  echo "Warning: 'pomo' is not on PATH. The widget will stay idle until it is." >&2
  echo "  npm install -g pomo-doro-tui" >&2
elif ! pomo --help 2>/dev/null | grep -q "^  start "; then
  echo >&2
  echo "Warning: the installed pomo-doro is too old - it has no CLI verbs and" >&2
  echo "writes no state file, so the widget will stay idle. Needs 1.16.0+." >&2
  echo "  npm install -g pomo-doro-tui@latest" >&2
fi

# A rescan is enough for a plugin the shell has never seen, but not for an
# update: omarchy-shell is long-lived and Qt caches compiled QML per file URL,
# so an already-loaded Panel.qml keeps running the old build until the process
# restarts. Disable/enable does not help either - it only flips a flag.
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

# Mark the journal position before restarting, so the check below reads only
# what this restart produced. A fixed time window would also catch errors from a
# previous attempt, and would miss a restart that took longer than the window.
journal_cursor=""
if (( RESTART )); then
  journal_cursor=$(journalctl --user -n 0 --show-cursor --no-pager 2>/dev/null |
    sed -n 's/^-- cursor: //p' || true)
fi

if (( ! RESTART )); then
  echo "Skipped shell restart (--no-restart); run 'omarchy restart shell' to load this build."
elif ! command -v omarchy-restart-shell >/dev/null 2>&1; then
  echo "omarchy-restart-shell not found; run 'omarchy restart shell' to load this build." >&2
else
  echo "Restarting the Omarchy shell so the new build loads..."
  if omarchy-restart-shell; then
    echo "Shell restarted."
  else
    echo "Shell restart failed - run 'omarchy restart shell' yourself." >&2
  fi
fi

# A plugin that fails to load does so silently from the installer's point of
# view: the shell restarts fine and only the widget is missing. Read the log back
# so a load failure is reported here rather than discovered by its absence.
if (( RESTART )); then
  if [[ -n $journal_cursor ]]; then
    journal_args=(--after-cursor "$journal_cursor")
  else
    journal_args=(--since "30 seconds ago")
  fi

  # A fixed sleep either wastes time or reads too early and calls a slow failure
  # a success. Poll instead: the shell answering ping means it is up, and our
  # plugin appearing in the journal means plugin loading has reached us. Give up
  # after ~5s and read whatever is there.
  for _ in {1..20}; do
    sleep 0.25
    omarchy-shell shell ping >/dev/null 2>&1 || continue
    if journalctl --user "${journal_args[@]}" --no-pager 2>/dev/null |
        grep -qF "$PLUGIN_ID"; then
      break
    fi
  done

  # Read the journal on its own, so a journalctl failure is distinguishable from
  # "no errors found". Folding them together - the obvious `journalctl | grep ...
  # || true` - makes a broken check report success, which is the one thing this
  # check must never do: it exists because a load failure is otherwise silent.
  if ! journal_output=$(journalctl --user "${journal_args[@]}" --no-pager 2>&1); then
    echo >&2
    echo "Could not read the journal to verify the plugin loaded:" >&2
    head -3 <<<"$journal_output" | sed 's/^/  /' >&2
    echo "Verify by hand: journalctl --user | grep $PLUGIN_ID" >&2
    echo "(The files were installed and the shell restarted; only the check failed.)" >&2
    exit 1
  else
    # grep exiting 1 for no matches is the success case here, hence `|| true`.
    failures=$(grep -F "$PLUGIN_ID" <<<"$journal_output" |
      grep -iE "failed|error|unavailable|Non-existent" | tail -5 || true)
    if [[ -n $failures ]]; then
      echo >&2
      echo "The shell reported errors loading this plugin:" >&2
      # shellcheck disable=SC2001  # ${var//find/replace} cannot do this: the
      # strip is a per-line regex over a multi-line variable, and a glob
      # replacement would run its `*` straight through the newlines, collapsing
      # every reported failure into one.
      sed -e 's/^.*omarchy-shell\[[0-9]*\]: //' -e 's/^/  /' <<<"$failures" >&2
      echo >&2
      echo "The widget will be missing from the bar until these are fixed." >&2
      exit 1
    fi
    echo "No load errors reported by the shell."
  fi
fi

cat <<EOF

Next:
  omarchy plugin list | grep pomo                    # confirm discovery
  omarchy plugin enable $PLUGIN_ID right

Already enabled? Nothing else to do - the restart above loaded this build.

Try it:
  pomo start -w 25 -t Coding    # the bar should show the countdown
  pomo stop

Rollback:
  omarchy plugin disable $PLUGIN_ID
EOF

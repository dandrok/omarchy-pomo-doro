#!/bin/bash

# Validate the plugin as far as tooling allows before it is loaded into the
# long-lived shell process, where a mistake surfaces as a broken bar rather than
# an error message.
#
# Three gates, because none of them is sufficient alone:
#
#  1. qmllint - but it cannot parse a file containing a typed QML function
#     (`function pause(): void`), which Quickshell's IPC requires. Omarchy's own
#     shipped files fail the same way. So we lint a copy with the annotations
#     stripped, which still checks everything else.
#  2. Imports - a type used without its module imported loads fine in qmllint and
#     fails at runtime, as an empty bar slot with one line in the journal.
#  3. omarchy plugin validate - manifest shape and entry points.

set -uo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
status=0

# A missing tool is not a failing check, it is an unrun one, and CI must be able
# to tell them apart. Every gate below skips loudly rather than reporting FAIL
# for a tool that was never installed.
skip() {
  printf '  %-8s SKIP  %s\n' "$1" "$2"
}

# --- 1. syntax / semantics ---------------------------------------------------
if ! command -v qmllint >/dev/null 2>&1; then
  skip lint "qmllint not installed (qt6-declarative-dev-tools)"
else
  cp "$SOURCE_DIR"/*.qml "$TMP/"
  sed -i 's/): void {/) {/g' "$TMP"/*.qml
  for f in "$TMP"/*.qml; do
    if qmllint "$f" >/dev/null 2>&1; then
      echo "  lint    OK    $(basename "$f")"
    else
      echo "  lint    FAIL  $(basename "$f")" >&2
      qmllint "$f" 2>&1 | head -5 >&2
      status=1
    fi
  done
fi

# --- 2. types used vs modules imported ---------------------------------------
# Each entry is "Type=Module". A type used in a file whose imports do not include
# its module is a runtime failure waiting to happen.
CHECKS=(
  "WlrLayershell=Quickshell.Wayland"
  "WlrLayer=Quickshell.Wayland"
  "WlrKeyboardFocus=Quickshell.Wayland"
  "PanelWindow=Quickshell"
  "ExclusionMode=Quickshell"
  "Region=Quickshell"
  "Quickshell.env=Quickshell"
  "Quickshell.execDetached=Quickshell"
  "Process=Quickshell.Io"
  "FileView=Quickshell.Io"
  "IpcHandler=Quickshell.Io"
  "SplitParser=Quickshell.Io"
  "StdioCollector=Quickshell.Io"
)

for f in "$SOURCE_DIR"/*.qml; do
  imports=$(grep -E '^import ' "$f")
  for check in "${CHECKS[@]}"; do
    type="${check%%=*}"
    module="${check##*=}"
    # A type is "used" only when it is instantiated (`Process {`) or dereferenced
    # (`Quickshell.env`). Matching the bare word would also hit string literals -
    # a button labelled "Region" is not a Quickshell type.
    if [[ $type == *.* ]]; then
      pattern="${type//./\\.}"
    else
      pattern="\\b${type}[[:space:]]*[{.]"
    fi
    if sed 's,//.*,,' "$f" | grep -qE "$pattern"; then
      if ! grep -qF "import $module" <<<"$imports"; then
        echo "  import  FAIL  $(basename "$f"): uses $type without 'import $module'" >&2
        status=1
      fi
    fi
  done
done
(( status == 0 )) && echo "  import  OK    all types have their module imported"

# --- 3. manifest -------------------------------------------------------------
# omarchy-plugin-validate is the validator install.sh already uses, so both
# agree on what a valid plugin is. It exists only on an Omarchy desktop, never
# on a CI runner, so its absence cannot be allowed to fail the run.
if ! command -v omarchy-plugin-validate >/dev/null 2>&1; then
  skip manifest "omarchy-plugin-validate not installed"
elif omarchy-plugin-validate "$SOURCE_DIR" >/dev/null 2>&1; then
  echo "  manifest OK"
else
  echo "  manifest FAIL" >&2
  omarchy-plugin-validate "$SOURCE_DIR" >&2
  status=1
fi

exit $status

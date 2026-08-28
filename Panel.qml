import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget and popup for the pomo-doro terminal timer.
//
// The widget owns no clock of its own. pomo-doro elects exactly one process to
// run the timer - a terminal you started it in, or the detached one this
// widget's Start button spawns - and that process publishes its state to a
// JSON file once a second and takes commands on a unix socket. So this file
// watches the file and shells out to `pomo` for anything that changes state.
//
// Which means the bar and the terminal are never two views that can disagree:
// pausing here pauses the countdown in an open terminal, and pressing `p`
// there stops the number in the bar.
Panel {
  id: root

  moduleName: "io.github.dandrok.pomo-doro"
  ipcTarget: "pomo-doro"
  // The base Panel installs its own handler for this target; ours adds the
  // timer verbs, so a keybind can pause without opening anything.
  manageIpc: false

  // --- settings (per-widget overrides in shell.json) -----------------------

  readonly property string cli: setting("command", "pomo")

  // Must resolve to the same place as `stateFile` in src/utils/config.ts, or
  // the widget watches a file nothing writes. `conf` appends its default
  // "-nodejs" project suffix, which is easy to leave out by hand.
  readonly property string defaultStatePath: {
    var home = Quickshell.env("HOME")
    // Without HOME this would resolve to /.config/..., a path outside the
    // user's home. Better to watch nothing than to read from there.
    return (home && home !== "")
      ? home + "/.config/pomo-doro-nodejs/state.json"
      : ""
  }
  readonly property string statePath: setting("statePath", root.defaultStatePath)

  readonly property bool hideWhenIdle: setting("hideWhenIdle", false)
  readonly property bool showSeconds: setting("showSeconds", true)
  readonly property bool notifyPhaseChange: setting("notifyPhaseChange", false)

  readonly property int defaultFocus: setting("defaultFocus", 25)
  readonly property int defaultShortBreak: setting("defaultShortBreak", 5)
  readonly property int defaultLongBreak: setting("defaultLongBreak", 15)
  readonly property string defaultTag: setting("defaultTag", "")

  readonly property string terminalCommand: setting("terminalCommand",
    "uwsm-app -- xdg-terminal-exec --title=\"Pomo Doro\" -- " + root.cli)

  // The same glyphs the terminal app and current.txt use, so the bar and the
  // status line read as one thing. Any Nerd Font glyph works instead.
  readonly property string workIcon: setting("workIcon", "◈")
  readonly property string shortBreakIcon: setting("shortBreakIcon", "◇")
  readonly property string longBreakIcon: setting("longBreakIcon", "◆")
  readonly property string idleIcon: setting("idleIcon", "󰔟")

  // --- state mirrored from the session owner ------------------------------

  property bool sessionRunning: false
  property bool paused: false
  property string mode: "work"
  property int secondsRemaining: 0
  property int totalSeconds: 0
  property real progress: 0
  property int pomodoroCount: 0
  property string tag: ""
  property string description: ""
  property int todayFocusSeconds: 0
  property int todayCompleted: 0
  property int dailyGoal: 0
  property var history14: []
  property double updatedAtMs: 0

  // Bumped once a second so `fresh` re-evaluates. Without it a session whose
  // owner was killed with SIGKILL - leaving no chance to blank the file -
  // would sit in the bar counting down forever at whatever second it died on.
  property double nowMs: Date.now()

  // The owner rewrites state.json every tick, pause included, so silence means
  // it is gone rather than idle. Five seconds is generous against a loaded
  // machine while still clearing a phantom countdown promptly.
  readonly property bool fresh: root.updatedAtMs > 0
    && (root.nowMs - root.updatedAtMs) < 5000

  readonly property bool running: root.sessionRunning && root.fresh

  readonly property string modeLabel: root.mode === "work" ? "Focus"
    : root.mode === "shortBreak" ? "Short break"
    : root.mode === "longBreak" ? "Long break"
    : ""

  readonly property string modeIcon: root.mode === "work" ? root.workIcon
    : root.mode === "shortBreak" ? root.shortBreakIcon
    : root.longBreakIcon

  readonly property string barGlyph: root.running ? root.modeIcon : root.idleIcon

  // Breaks are not urgent, and neither is a paused timer - only a focus block
  // actually running earns the accent colour.
  readonly property bool barActive: root.running && !root.paused
    && root.mode === "work"

  function pad(value) {
    return value < 10 ? "0" + value : String(value)
  }

  readonly property string remainingText: {
    if (!root.running) return ""
    var minutes = Math.floor(root.secondsRemaining / 60)
    var seconds = root.secondsRemaining % 60
    if (root.showSeconds) return root.pad(minutes) + ":" + root.pad(seconds)
    // Round up, so a timer never shows 0m with time still on it.
    return String(Math.ceil(root.secondsRemaining / 60)) + "m"
  }

  readonly property string barText: root.running
    ? root.barGlyph + " " + root.remainingText + (root.paused ? " ⏸" : "")
    : root.barGlyph

  readonly property string tooltip: {
    if (!root.running) {
      return "Pomo Doro - no session running"
    }
    var parts = [root.modeLabel]
    if (root.tag !== "") parts.push(root.tag)
    if (root.paused) parts.push("paused")
    return parts.join(" · ") + "\n" + root.remainingText + " left"
  }

  function formatDuration(seconds) {
    if (seconds < 60) return seconds + "s"
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m"
  }

  // --- commands -----------------------------------------------------------

  // Every mutation goes through the CLI rather than being applied here: the
  // session owner is the only thing allowed to move the clock or write
  // history, and duplicating any of that in QML is how the two views would
  // start to disagree.
  function run(args) {
    commandProc.running = false
    commandProc.command = [root.cli].concat(args)
    commandProc.running = true
  }

  function startSession() {
    var args = ["start",
      "-w", String(root.defaultFocus),
      "-b", String(root.defaultShortBreak),
      "-l", String(root.defaultLongBreak)]
    // An empty tag is not "no tag" to the CLI - it means "reuse the last one",
    // which is the friendlier default for a one-click start.
    if (root.defaultTag !== "") args = args.concat(["-t", root.defaultTag])
    root.run(args)
  }

  function openInTerminal() {
    if (root.bar && typeof root.bar.run === "function" && root.terminalCommand !== "")
      root.bar.run(root.terminalCommand)
    root.close()
  }

  // --- reading the session's state ----------------------------------------

  function clearState() {
    root.sessionRunning = false
    root.paused = false
    root.secondsRemaining = 0
    root.totalSeconds = 0
    root.progress = 0
    root.tag = ""
    root.description = ""
    root.updatedAtMs = 0
  }

  function readSessionState(raw) {
    var text = String(raw || "").trim()
    if (text === "" || text.charAt(0) !== "{") return

    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      // A read that caught the file mid-write; the next one is a second away.
      return
    }

    // An unknown schema is worse than no widget: the fields this draws would
    // silently read as zero and show a confident, wrong countdown.
    if (data.version !== 1) return

    var previousMode = root.mode
    var wasRunning = root.running

    root.sessionRunning = data.running === true
    root.paused = data.paused === true
    root.mode = String(data.mode || "work")
    root.secondsRemaining = Number(data.secondsRemaining) || 0
    root.totalSeconds = Number(data.totalSeconds) || 0
    root.progress = Number(data.progress) || 0
    root.pomodoroCount = Number(data.pomodoroCount) || 0
    root.tag = String(data.tag || "")
    root.description = String(data.description || "")
    root.dailyGoal = Number(data.dailyGoal) || 0
    root.history14 = data.history14 || []

    if (data.today) {
      root.todayFocusSeconds = Number(data.today.focusSeconds) || 0
      root.todayCompleted = Number(data.today.completedPomodoros) || 0
    }

    var stamp = Date.parse(String(data.updatedAt || ""))
    root.updatedAtMs = isNaN(stamp) ? 0 : stamp
    root.nowMs = Date.now()

    // Only announce a transition between two live sessions. Without the
    // wasRunning guard, the shell would fire a notification every time the
    // widget loaded and found a break already in progress.
    if (root.notifyPhaseChange && wasRunning && root.running
        && previousMode !== root.mode) {
      root.announcePhase()
    }
  }

  function announcePhase() {
    var body = root.mode === "work"
      ? "Back to focus."
      : "Time for a " + root.modeLabel.toLowerCase() + "."
    Quickshell.execDetached(["notify-send", "-a", "Pomo Doro",
      root.modeLabel, body])
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    // No state file is the normal never-run-it-yet case, not an error.
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readSessionState(stateFile.text())
    onLoadFailed: root.clearState()
  }

  // Safety net for a write the watcher misses, and the clock behind `fresh`.
  // One timer covers both; a file read this small is far cheaper than the
  // per-second process spawn the alternative would need.
  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      stateFile.reload()
    }
  }

  Process {
    id: commandProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.commandError = message
      }
    }
    onExited: function(exitCode) {
      // The CLI reports "no session running" on stderr and exits non-zero;
      // anything else that fails is worth showing rather than swallowing.
      if (exitCode === 0) root.commandError = ""
      // The owner rewrites state.json as it applies the command, but reloading
      // now closes the gap between the click and the next tick.
      stateFile.reload()
    }
  }

  // Shown in the popup so a missing binary is diagnosable without a terminal.
  property string commandError: ""

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    function start(): void { root.startSession() }
    function pause(): void { root.run(["pause"]) }
    function resume(): void { root.run(["resume"]) }
    function togglePause(): void { root.run(["toggle"]) }
    function skip(): void { root.run(["skip"]) }
    function reset(): void { root.run(["reset"]) }
    function stop(): void { root.run(["stop"]) }
  }

  // --- bar button ---------------------------------------------------------

  visible: !root.hideWhenIdle || root.running
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    active: root.barActive
    tooltipText: root.tooltip

    onPressed: function(pressedButton) {
      // Right click is the one-handed pause: the thing you want most often
      // without looking away from what you are doing.
      if (pressedButton === Qt.RightButton) {
        if (root.running) root.run(["toggle"])
        else root.startSession()
      } else if (pressedButton === Qt.MiddleButton) {
        if (root.running) root.run(["skip"])
      } else {
        root.toggle()
      }
    }
  }

  // --- popup --------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(popupBody.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(key) {
        var lower = String(key).toLowerCase()
        if (lower === "p") {
          if (root.running) root.run(["toggle"])
          else root.startSession()
        } else if (lower === "s" && root.running) {
          root.run(["skip"])
        } else if (lower === "r" && root.running) {
          root.run(["reset"])
        } else if (lower === "x" && root.running) {
          root.run(["stop"])
        } else if (lower === "t") {
          root.openInTerminal()
        }
      }

      WidgetBody {
        id: popupBody
        panel: root
        anchors.left: parent.left
        anchors.right: parent.right
      }
    }
  }
}

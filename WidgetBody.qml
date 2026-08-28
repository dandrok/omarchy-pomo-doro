import QtQuick
import qs.Commons
import qs.Ui

// The popup's entire content: what the session is doing, the controls for it,
// and how the day has gone.
//
// `panel` points back at Panel.qml, which owns the state and the CLI plumbing;
// this file only draws it.
Item {
  id: body

  required property var panel

  implicitWidth: column.implicitWidth
  implicitHeight: column.implicitHeight

  readonly property string goalText: {
    if (panel.dailyGoal <= 0) return ""
    return panel.todayCompleted + " / " + panel.dailyGoal
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.spacing.md

    // Header: the phase, and whether it is actually moving.
    Item {
      width: parent.width
      implicitHeight: Math.max(headline.implicitHeight, dot.height)

      Rectangle {
        id: dot
        width: Style.space(8)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: !panel.running
          ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.35)
          : panel.mode === "work" ? Color.urgent : Color.accent

        // Only a live focus block pulses. A paused timer holding a steady dot
        // is the difference you most need to see at a glance.
        SequentialAnimation on opacity {
          running: panel.running && !panel.paused
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.4; duration: 900 }
          NumberAnimation { from: 0.4; to: 1.0; duration: 900 }
        }
      }

      Text {
        id: headline
        anchors.left: dot.right
        anchors.leftMargin: Style.spacing.sm
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: panel.running
          ? panel.modeLabel + (panel.tag !== "" ? " · " + panel.tag : "")
            + (panel.paused ? " (paused)" : "")
          : "No session running"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: panel.running
        elide: Text.ElideRight
      }
    }

    Text {
      width: parent.width
      visible: panel.running && panel.description !== ""
      text: panel.description
      color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.65)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      elide: Text.ElideRight
      maximumLineCount: 2
    }

    // The countdown, big enough to read from across the desk.
    Text {
      visible: panel.running
      anchors.horizontalCenter: parent.horizontalCenter
      text: panel.remainingText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge * 1.6
      font.bold: true
    }

    Item {
      width: parent.width
      visible: panel.running
      implicitHeight: track.height

      Rectangle {
        id: track
        width: parent.width - percent.width - Style.spacing.sm
        height: Style.space(6)
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.15)

        Rectangle {
          width: Math.max(0, Math.min(1, panel.progress)) * parent.width
          height: parent.height
          radius: parent.radius
          color: panel.mode === "work" ? Color.urgent : Color.accent

          Behavior on width {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
          }
        }
      }

      Text {
        id: percent
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(Math.max(0, Math.min(1, panel.progress)) * 100) + "%"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    PanelSeparator {}

    PanelSectionHeader { text: panel.running ? "SESSION" : "START" }

    Flow {
      width: parent.width
      spacing: Style.spacing.sm
      // Buttons wrap onto another line rather than overflowing the panel edge
      // when the set grows or the theme's font is larger.

      Button {
        visible: panel.running
        text: panel.paused ? "Resume" : "Pause"
        iconText: panel.paused ? "󰐊" : "󰏤"
        bordered: true
        onClicked: panel.run(["toggle"])
      }

      Button {
        visible: panel.running
        text: "Skip"
        iconText: "󰒭"
        bordered: true
        tooltipText: "Move to the next phase without counting this one"
        onClicked: panel.run(["skip"])
      }

      Button {
        visible: panel.running
        text: "Reset"
        iconText: "󰑙"
        bordered: true
        tooltipText: "Restart the current phase from the top"
        onClicked: panel.run(["reset"])
      }

      Button {
        visible: panel.running
        text: "Stop"
        iconText: "󰓛"
        bordered: true
        tooltipText: "End the session and keep the time already earned"
        onClicked: panel.run(["stop"])
      }

      // Starting from here needs no terminal: the CLI spawns a detached owner
      // that runs the clock, sends the notifications, and writes the history
      // exactly as a session started in a shell would.
      Button {
        visible: !panel.running
        text: "Start focus"
        iconText: "󰐊"
        bordered: true
        tooltipText: panel.defaultFocus + " min focus"
          + (panel.defaultTag !== "" ? " · " + panel.defaultTag : "")
        onClicked: panel.startSession()
      }

      Button {
        text: "Terminal"
        iconText: "󰆍"
        bordered: true
        tooltipText: panel.running
          ? "Open the full app on this session"
          : "Open the full app"
        onClicked: panel.openInTerminal()
      }
    }

    Text {
      width: parent.width
      visible: panel.commandError !== ""
      text: panel.commandError
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      elide: Text.ElideRight
    }

    PanelSeparator {}

    PanelSectionHeader { text: "TODAY" }

    Item {
      width: parent.width
      implicitHeight: todayLine.implicitHeight

      Text {
        id: todayLine
        anchors.left: parent.left
        text: panel.todayCompleted + " pomodoro" + (panel.todayCompleted === 1 ? "" : "s")
          + " · " + panel.formatDuration(panel.todayFocusSeconds)
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.baseline: todayLine.baseline
        visible: body.goalText !== ""
        text: "Goal " + body.goalText
        color: panel.dailyGoal > 0 && panel.todayCompleted >= panel.dailyGoal
          ? Color.accent
          : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.65)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Heatmap {
      width: parent.width
      days: panel.history14
    }
  }
}

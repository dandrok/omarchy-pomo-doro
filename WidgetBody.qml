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

  property bool optionsExpanded: false
  readonly property bool inputActiveFocus: todoList.inputActiveFocus || (tagInput && tagInput.activeFocus)

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

    // Header with chevron toggle for options when idle
    Item {
      width: parent.width
      implicitHeight: Math.max(startHeader.implicitHeight, optionsChevron.implicitHeight)

      PanelSectionHeader {
        id: startHeader
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: panel.running ? "SESSION" : "START"
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs
        visible: !panel.running

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: panel.sessionFocus + "m · " + panel.sessionShortBreak + "m"
            + (panel.sessionTag.trim() !== "" ? " · #" + panel.sessionTag.trim() : "")
          color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          id: optionsChevron
          anchors.verticalCenter: parent.verticalCenter
          text: body.optionsExpanded ? "󰅃" : "󰅀"
          color: Qt.darker(Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: !panel.running
        cursorShape: Qt.PointingHandCursor
        onClicked: body.optionsExpanded = !body.optionsExpanded
      }
    }

    // Expandable minimalist options (hidden by default)
    Column {
      id: optionsArea
      width: parent.width
      spacing: Style.spacing.sm
      visible: !panel.running && body.optionsExpanded

      // Compact tag input row
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacing.xs

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "#"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        TextField {
          id: tagInput
          width: Style.space(160)
          placeholderText: "tag..."
          text: panel.sessionTag
          verticalPadding: Style.spacing.xxs
          font.pixelSize: Style.font.bodySmall
          onTextEdited: panel.sessionTag = text
          onAccepted: panel.startSession()
        }
      }

      // Minimalist stepper pills
      Row {
        width: parent.width
        spacing: Style.spacing.xs

        // Focus
        Rectangle {
          width: Math.floor((parent.width - parent.spacing * 2) / 3)
          implicitHeight: Style.space(42)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.04)
          border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.1)
          border.width: 1

          Column {
            anchors.centerIn: parent
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "FOCUS"
              color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption * 0.85
              font.bold: true
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.xs

              Text {
                text: "−"
                color: minusFocusMouse.containsMouse ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: minusFocusMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.sessionFocus = Math.max(5, panel.sessionFocus - 5)
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.sessionFocus + "m"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                text: "+"
                color: plusFocusMouse.containsMouse ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: plusFocusMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.sessionFocus = Math.min(120, panel.sessionFocus + 5)
                }
              }
            }
          }
        }

        // Short break
        Rectangle {
          width: Math.floor((parent.width - parent.spacing * 2) / 3)
          implicitHeight: Style.space(42)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.04)
          border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.1)
          border.width: 1

          Column {
            anchors.centerIn: parent
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "SHORT"
              color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption * 0.85
              font.bold: true
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.xs

              Text {
                text: "−"
                color: minusShortMouse.containsMouse ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: minusShortMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.sessionShortBreak = Math.max(1, panel.sessionShortBreak - 1)
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.sessionShortBreak + "m"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                text: "+"
                color: plusShortMouse.containsMouse ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: plusShortMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.sessionShortBreak = Math.min(30, panel.sessionShortBreak + 1)
                }
              }
            }
          }
        }

        // Long break
        Rectangle {
          width: Math.floor((parent.width - parent.spacing * 2) / 3)
          implicitHeight: Style.space(42)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.04)
          border.color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.1)
          border.width: 1

          Column {
            anchors.centerIn: parent
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "LONG"
              color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption * 0.85
              font.bold: true
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.xs

              Text {
                text: "−"
                color: minusLongMouse.containsMouse ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: minusLongMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.sessionLongBreak = Math.max(5, panel.sessionLongBreak - 5)
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.sessionLongBreak + "m"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                text: "+"
                color: plusLongMouse.containsMouse ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: plusLongMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.sessionLongBreak = Math.min(60, panel.sessionLongBreak + 5)
                }
              }
            }
          }
        }
      }
    }

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
        tooltipText: panel.sessionFocus + " min focus"
          + (panel.sessionTag.trim() !== "" ? " · " + panel.sessionTag.trim() : (panel.defaultTag !== "" ? " · " + panel.defaultTag : ""))
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

    PanelSeparator {}

    TodoList {
      id: todoList
      width: parent.width
    }
  }
}

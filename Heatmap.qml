import QtQuick
import qs.Commons
import qs.Ui

// The last two weeks of focus time, one cell per day, oldest on the left.
//
// The days arrive pre-built and zero-filled from the session's state file, so
// there are always exactly as many cells as days and no gap handling to do
// here. Intensity is scaled against the best day in the window rather than a
// fixed ceiling: the question this answers is "how does today compare with how
// I have been working", which a fixed scale flattens for light and heavy weeks
// alike.
Item {
  id: root

  property var days: []

  readonly property int count: root.days ? root.days.length : 0

  readonly property int peakSeconds: {
    var peak = 0
    for (var i = 0; i < root.count; i++) {
      var value = Number(root.days[i].focusSeconds) || 0
      if (value > peak) peak = value
    }
    return peak
  }

  function formatDuration(seconds) {
    if (seconds <= 0) return "no focus time"
    if (seconds < 60) return seconds + "s"
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m"
  }

  visible: root.count > 0
  implicitHeight: visible ? grid.height + label.height + Style.spacing.xs : 0

  Row {
    id: grid
    width: parent.width
    spacing: Style.spacing.xxs

    Repeater {
      model: root.days

      Rectangle {
        required property var modelData
        required property int index

        readonly property int focusSeconds: Number(modelData.focusSeconds) || 0
        readonly property int completed: Number(modelData.completedPomodoros) || 0
        readonly property bool isToday: index === root.count - 1

        // A day with any focus at all keeps a visible floor, so five minutes
        // reads as "worked a little" rather than as an empty day.
        readonly property real intensity: {
          if (focusSeconds <= 0) return 0
          if (root.peakSeconds <= 0) return 0
          return 0.25 + 0.75 * (focusSeconds / root.peakSeconds)
        }

        width: (grid.width - (root.count - 1) * grid.spacing) / root.count
        height: Style.space(18)
        radius: Style.space(2)

        color: intensity > 0
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, intensity)
          : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.10)

        border.width: isToday ? 1 : 0
        border.color: Color.popups.text

        MouseArea {
          id: cell
          anchors.fill: parent
          hoverEnabled: true

          PanelToolTip {
            visible: cell.containsMouse
            text: modelData.date + "\n"
              + root.formatDuration(focusSeconds) + " · "
              + completed + " pomodoro" + (completed === 1 ? "" : "s")
          }
        }
      }
    }
  }

  Text {
    id: label
    anchors.top: grid.bottom
    anchors.topMargin: Style.spacing.xs
    anchors.left: parent.left
    text: "Last " + root.count + " days"
    color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.5)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}

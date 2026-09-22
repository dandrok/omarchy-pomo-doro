import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Minimalist, persistent todo list for the pomo-doro popup.
//
// State is stored in ~/.config/pomo-doro-nodejs/todos.json via Quickshell's
// FileView so items persist across shell restarts. Exposes `inputActiveFocus`
// so the parent panel can disable single-key timer shortcuts while the user
// is typing in the task input.
Item {
  id: root

  readonly property string todosPath: {
    var home = Quickshell.env("HOME")
    return (home && home !== "")
      ? home + "/.config/pomo-doro-nodejs/todos.json"
      : ""
  }

  property bool expanded: false
  readonly property bool inputActiveFocus: inputField.activeFocus
  readonly property int totalCount: todoModel.count
  property int completedCount: 0

  function updateCompletedCount() {
    var count = 0
    for (var i = 0; i < todoModel.count; i++) {
      if (todoModel.get(i).done === true) count++
    }
    completedCount = count
  }

  implicitWidth: contentColumn.implicitWidth
  implicitHeight: contentColumn.implicitHeight

  function loadTodos(raw) {
    var text = String(raw || "").trim()
    if (text === "" || text.charAt(0) !== "[") return

    try {
      var data = JSON.parse(text)
      if (Array.isArray(data)) {
        todoModel.clear()
        for (var i = 0; i < data.length; i++) {
          var item = data[i]
          if (item && typeof item.text === "string" && item.text.trim() !== "") {
            todoModel.append({
              id: Number(item.id) || (Date.now() + i),
              text: String(item.text).trim(),
              done: item.done === true
            })
          }
        }
        root.updateCompletedCount()
      }
    } catch (e) {}
  }

  function saveTodos() {
    var list = []
    for (var i = 0; i < todoModel.count; i++) {
      var entry = todoModel.get(i)
      list.push({
        id: entry.id,
        text: entry.text,
        done: entry.done === true
      })
    }
    todoFile.setText(JSON.stringify(list, null, 2) + "\n")
  }

  function addTodo() {
    var task = inputField.text.trim()
    if (task === "") return

    todoModel.append({
      id: Date.now(),
      text: task,
      done: false
    })
    inputField.text = ""
    root.saveTodos()
    root.updateCompletedCount()
  }

  ListModel {
    id: todoModel
  }

  FileView {
    id: todoFile
    path: root.todosPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadTodos(todoFile.text())
    onFileChanged: reload()
  }

  Component.onCompleted: {
    var home = Quickshell.env("HOME")
    if (home && home !== "") {
      Quickshell.execDetached(["mkdir", "-p", home + "/.config/pomo-doro-nodejs"])
    }
  }

  Column {
    id: contentColumn
    width: parent.width
    spacing: Style.spacing.sm

    // Header toggle row
    Item {
      width: parent.width
      implicitHeight: Math.max(headerLabel.implicitHeight, toggleChevron.implicitHeight)

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
      }

      PanelSectionHeader {
        id: headerLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "TASKS" + (root.totalCount > 0 ? " (" + root.completedCount + "/" + root.totalCount + ")" : "")
      }

      Text {
        id: toggleChevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.expanded ? "󰅃" : "󰅀"
        color: Qt.darker(Color.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    // Expandable content
    Column {
      id: expandableArea
      width: parent.width
      spacing: Style.spacing.sm
      visible: root.expanded

      // Empty state
      Text {
        visible: root.totalCount === 0
        width: parent.width
        text: "No tasks yet"
        color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        topPadding: Style.spacing.xs
        bottomPadding: Style.spacing.xs
      }

      // Tasks list (bounded height to prevent overflowing popup)
      ListView {
        id: taskList
        width: parent.width
        implicitHeight: Math.min(contentHeight, Style.space(160))
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: todoModel
        spacing: Style.spacing.xxs

        delegate: Rectangle {
          id: itemRow
          width: taskList.width
          implicitHeight: Math.max(itemContent.implicitHeight + Style.spacing.xs * 2, Style.space(28))
          radius: Style.cornerRadius
          color: rowMouse.containsMouse
            ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.07)
            : "transparent"

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var currentDone = model.done
              todoModel.setProperty(index, "done", !currentDone)
              root.updateCompletedCount()
              root.saveTodos()
            }
          }

          Row {
            id: itemContent
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.xs
            anchors.right: deleteButton.left
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Text {
              id: checkboxIcon
              anchors.verticalCenter: parent.verticalCenter
              text: model.done ? "󰄲" : "󰄱"
              color: model.done ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              id: taskLabel
              anchors.verticalCenter: parent.verticalCenter
              width: itemContent.width - checkboxIcon.width - itemContent.spacing
              text: model.text
              color: model.done
                ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.45)
                : Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.strikeout: model.done
              elide: Text.ElideRight
            }
          }

          Item {
            id: deleteButton
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(20)
            height: width
            visible: rowMouse.containsMouse || deleteMouse.containsMouse

            Text {
              anchors.centerIn: parent
              text: "✕"
              color: deleteMouse.containsMouse ? Color.urgent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            MouseArea {
              id: deleteMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                mouse.accepted = true
                todoModel.remove(index)
                root.updateCompletedCount()
                root.saveTodos()
              }
            }
          }
        }
      }

      // Input row: [input...] [Add]
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        TextField {
          id: inputField
          width: parent.width - addButton.width - parent.spacing
          placeholderText: "New task..."
          onAccepted: root.addTodo()
        }

        Button {
          id: addButton
          text: "Add"
          bordered: true
          onClicked: root.addTodo()
        }
      }
    }
  }
}

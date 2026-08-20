import QtQuick
import qs.Commons

// Simplified vector rendering of the Vaultez brand mark's key (bow, shaft,
// tooth) for the bar icon slot. Traced from
// ~/Documents/Vaultez/vaultez-logo-regular.png, dropping the hexagon frame
// and fine circuit-node branches since they don't read at bar-icon scale —
// same simplification Dropbox's own bar icon (DropboxIcon.qml) makes against
// its fuller logo.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Key bow (ring)
  Rectangle {
    id: bow
    width: root.iconSize * 0.46
    height: width
    radius: width / 2
    color: "transparent"
    border.color: root.color
    border.width: Math.max(1, root.iconSize * 0.13)
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.iconSize * 0.06
  }

  // Bow center dot
  Rectangle {
    width: root.iconSize * 0.15
    height: width
    radius: width / 2
    color: root.color
    anchors.centerIn: bow
  }

  // Key shaft
  Rectangle {
    id: shaft
    width: root.iconSize * 0.15
    height: root.iconSize * 0.46
    radius: width / 2
    color: root.color
    anchors.horizontalCenter: parent.horizontalCenter
    y: bow.y + bow.height * 0.6
  }

  // Key tooth
  Rectangle {
    width: root.iconSize * 0.17
    height: root.iconSize * 0.11
    color: root.color
    x: shaft.x + shaft.width
    y: shaft.y + shaft.height * 0.58
  }
}

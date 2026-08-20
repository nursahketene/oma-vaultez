import QtQuick
import QtQuick.Shapes
import qs.Commons

// Simplified vector rendering of the Vaultez brand mark (hexagon + key) for
// the bar icon slot. Traced from ~/Documents/Vaultez/vaultez-logo-regular.png,
// dropping the fine circuit-node branches since they don't read at bar-icon
// scale — same simplification Dropbox's own bar icon (DropboxIcon.qml) makes
// against its fuller logo.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    id: hexagon
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.09)
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root.width * 0.5; startY: root.height * 0.02
      PathLine { x: root.width * 0.93; y: root.height * 0.28 }
      PathLine { x: root.width * 0.93; y: root.height * 0.72 }
      PathLine { x: root.width * 0.5; y: root.height * 0.98 }
      PathLine { x: root.width * 0.07; y: root.height * 0.72 }
      PathLine { x: root.width * 0.07; y: root.height * 0.28 }
      PathLine { x: root.width * 0.5; y: root.height * 0.02 }
    }
  }

  // Key bow (ring)
  Rectangle {
    id: bow
    width: root.iconSize * 0.34
    height: width
    radius: width / 2
    color: "transparent"
    border.color: root.color
    border.width: Math.max(1, root.iconSize * 0.09)
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.iconSize * 0.24
  }

  // Bow center dot
  Rectangle {
    width: root.iconSize * 0.10
    height: width
    radius: width / 2
    color: root.color
    anchors.centerIn: bow
  }

  // Key shaft
  Rectangle {
    id: shaft
    width: root.iconSize * 0.11
    height: root.iconSize * 0.40
    radius: width / 2
    color: root.color
    anchors.horizontalCenter: parent.horizontalCenter
    y: bow.y + bow.height * 0.55
  }

  // Key tooth
  Rectangle {
    width: root.iconSize * 0.13
    height: root.iconSize * 0.08
    color: root.color
    x: shaft.x + shaft.width
    y: shaft.y + shaft.height * 0.62
  }
}

import QtQuick
import QtQuick.Shapes

// Um dos três botões do Mac: vermelho fecha, amarelo minimiza, verde amplia.
// Apagado na janela sem foco; com o cursor no grupo, colorido e com o glifo.
Item {
  id: root

  property string kind: "close" // close | minimize | zoom
  property bool lit: true
  property bool glyph: false
  property bool dark: false
  signal clicked()

  readonly property var palette: ({
    close: { fill: "#ff5f57", edge: "#e0443e", mark: "#4d0000" },
    minimize: { fill: "#febc2e", edge: "#dea123", mark: "#995700" },
    zoom: { fill: "#28c840", edge: "#1aab29", mark: "#006500" }
  })
  readonly property var colors: palette[kind] || palette.close

  width: 12
  height: 12

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    antialiasing: true
    color: root.lit ? root.colors.fill : (root.dark ? "#4b4b50" : "#d9d9dc")
    border.width: 0.5
    border.color: root.lit ? root.colors.edge : (root.dark ? "#3c3c40" : "#c4c4c8")
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Shape {
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: 0.5
    visible: root.glyph && root.lit
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.kind === "zoom" ? "transparent" : root.colors.mark
      strokeWidth: root.kind === "zoom" ? -1 : 2.6
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathSvg { path: root.kind === "close" ? "M7.5 7.5 L16.5 16.5 M16.5 7.5 L7.5 16.5" : "M6.5 12 H17.5" }
    }

    ShapePath {
      strokeColor: "transparent"
      fillColor: root.kind === "zoom" ? root.colors.mark : "transparent"
      // Dois triângulos opostos, como o botão verde do macOS.
      PathSvg { path: "M7 17 V9.5 L14.5 17 Z M17 7 V14.5 L9.5 7 Z" }
    }
  }

  MouseArea {
    anchors.fill: parent
    anchors.margins: -4
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}

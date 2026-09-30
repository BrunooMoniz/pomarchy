import QtQuick
import QtQuick.Shapes
import "Glyphs.js" as Glyphs

// Glifo vetorial (ver Glyphs.js), nítido em qualquer tamanho e com a cor que
// o chamador pedir. A espessura do traço é medida na grade de 24.
Item {
  id: root

  property string name: ""
  property color color: Theme.label
  // Cor do traço; por padrão a mesma do preenchimento (o ponteiro usa outra
  // para ganhar o contorno claro).
  property color strokeColor: color
  property real size: 16
  property real weight: 1.9

  readonly property var def: Glyphs.get(name)

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: 24
    height: 24
    scale: root.size / 24
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.def.stroke ? root.strokeColor : "transparent"
      strokeWidth: root.def.stroke ? root.weight : -1
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.def.stroke || "M0 0" }
    }

    ShapePath {
      fillColor: root.def.fill ? root.color : "transparent"
      fillRule: ShapePath.OddEvenFill
      strokeColor: "transparent"
      strokeWidth: -1
      PathSvg { path: root.def.fill || "M0 0" }
    }
  }
}

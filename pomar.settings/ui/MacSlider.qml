import QtQuick
import QtQuick.Effects
import "../shared/Tokens.js" as Tokens

// Régua no estilo do Mac: trilho fino, parte cheia no destaque e bolinha
// clara. `moved` sai durante o arrasto (o chamador decide quando gravar) e
// `released` no fim.
Item {
  id: root

  property real from: 0
  property real to: 1
  property real value: 0
  property real stepSize: 1
  property bool dragging: false
  property real liveValue: value

  signal moved(real value)
  signal released(real value)

  implicitWidth: 220
  implicitHeight: 28
  opacity: enabled ? 1 : 0.45

  onValueChanged: if (!dragging) liveValue = value

  readonly property real span: Math.max(0.0001, to - from)
  readonly property real progress: Tokens.clamp((liveValue - from) / span, 0, 1)
  readonly property real knobSize: 20

  function snap(v) {
    var stepped = stepSize > 0 ? Math.round((v - from) / stepSize) * stepSize + from : v
    return Tokens.clamp(stepped, from, to)
  }

  function valueAt(x) {
    var usable = Math.max(1, width - knobSize)
    return snap(from + Tokens.clamp((x - knobSize / 2) / usable, 0, 1) * span)
  }

  Rectangle {
    id: rail
    x: root.knobSize / 2 - 2
    width: root.width - root.knobSize + 4
    height: 4
    radius: 2
    anchors.verticalCenter: parent.verticalCenter
    color: Theme.track
  }

  Rectangle {
    anchors.left: rail.left
    anchors.verticalCenter: rail.verticalCenter
    height: rail.height
    radius: rail.radius
    width: knob.x + knob.width / 2 - rail.x
    color: Theme.accent
  }

  RectangularShadow {
    anchors.fill: knob
    radius: knob.radius
    blur: 5
    offset.y: 1
    color: Tokens.withAlpha(Theme.shadow, 0.40)
  }

  Rectangle {
    id: knob
    width: root.knobSize
    height: width
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    x: root.progress * (root.width - width)
    antialiasing: true
    color: Theme.white
    border.width: 1
    border.color: Theme.outline
    Behavior on x {
      enabled: !root.dragging
      NumberAnimation { duration: Tokens.motion.fast; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    anchors.fill: parent
    anchors.topMargin: -8
    anchors.bottomMargin: -8
    cursorShape: Qt.PointingHandCursor
    preventStealing: true
    onPressed: function(mouse) {
      root.dragging = true
      root.liveValue = root.valueAt(mouse.x)
      root.moved(root.liveValue)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = root.valueAt(mouse.x)
      if (next === root.liveValue) return
      root.liveValue = next
      root.moved(next)
    }
    onReleased: {
      root.dragging = false
      root.released(root.liveValue)
    }
    onCanceled: {
      root.dragging = false
      root.released(root.liveValue)
    }
    onWheel: function(wheel) {
      var next = root.snap(root.liveValue + (wheel.angleDelta.y > 0 ? root.stepSize : -root.stepSize))
      root.liveValue = next
      root.moved(next)
      root.released(next)
    }
  }
}

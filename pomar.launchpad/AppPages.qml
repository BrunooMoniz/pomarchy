pragma ComponentBehavior: Bound

import QtQuick
import "shared/Tokens.js" as Tokens

// Páginas horizontais de apps com encaixe, como no Launchpad do Mac. Arrastar
// segue o dedo 1:1 (com elástico nas pontas) e, ao soltar, vira a página se
// passou da metade ou se o movimento foi rápido; senão volta. A roda do mouse
// e a rolagem de dois dedos viram uma página por gesto. A grade de cada página
// é posicionada pelas medidas que o Launchpad tira da tela, nunca do conteúdo.
//
// O ListView só monta e recicla as páginas; a posição (contentX) é toda
// daqui: o encaixe do próprio ListView (SnapOneItem) vira a página com
// qualquer arrasto, mesmo curto e lento.
ListView {
  id: pages

  property var items: []
  property int cols: 7
  property int perPage: 35
  property real cellWidth: 200
  property real cellHeight: 180
  property real gridX: 0
  property real gridY: 0
  property real iconSize: 96
  property real labelGap: 10
  property real devicePixelRatio: 1
  property int selectedIndex: -1
  property bool showSelection: false
  // Arrasto e roda ligados (o menu aberto e a pinça desligam).
  property bool dragEnabled: true
  // Página atual; muda na hora em que a virada começa (os pontinhos seguem).
  property int page: 0

  property real wheelAccumulated: 0
  property double wheelLockedUntil: 0

  signal activated(int index)
  signal menuRequested(int index, real sceneX, real sceneY)
  signal emptyClicked()

  readonly property int pageCount: Math.max(1, Math.ceil(items.length / Math.max(1, perPage)))

  function pageX(index) {
    return pages.originX + index * pages.width
  }

  function clampPage(index) {
    return Math.max(0, Math.min(pages.pageCount - 1, index))
  }

  // Vai para a página com a animação de assentar (OutCubic, mais curta quando
  // falta pouco, como no fim de um arrasto).
  function goTo(index, duration) {
    var target = pages.clampPage(index)
    pages.page = target
    settle.stop()
    var distance = Math.abs(pages.pageX(target) - pages.contentX)
    if (distance < 0.5) {
      pages.contentX = pages.pageX(target)
      return
    }
    var full = duration === undefined ? Tokens.motion.slow : duration
    settle.to = pages.pageX(target)
    settle.duration = Math.round(Tokens.clamp(full * Math.sqrt(distance / Math.max(1, pages.width)), Tokens.motion.fast, full))
    settle.start()
  }

  function jumpTo(index) {
    settle.stop()
    pages.page = pages.clampPage(index)
    pages.contentX = pages.pageX(pages.page)
  }

  function step(delta) {
    pages.goTo(pages.page + delta)
  }

  function pageOf(index) {
    return Math.floor(Math.max(0, index) / Math.max(1, pages.perPage))
  }

  // Além da primeira e da última página o conteúdo resiste, como um elástico.
  function elastic(x) {
    var first = pages.pageX(0)
    var last = pages.pageX(pages.pageCount - 1)
    var reach = pages.width * 0.18
    if (x < first) return first - reach * (1 - Math.exp((x - first) / reach))
    if (x > last) return last + reach * (1 - Math.exp((last - x) / reach))
    return x
  }

  function release(velocityX) {
    var offset = (pages.contentX - pages.pageX(pages.page)) / Math.max(1, pages.width)
    var quick = Math.abs(velocityX) > 480
    var target = pages.page
    if (offset > 0.5 || (quick && velocityX < 0 && offset > 0.03)) target = pages.page + 1
    else if (offset < -0.5 || (quick && velocityX > 0 && offset < -0.03)) target = pages.page - 1
    pages.goTo(target)
  }

  orientation: ListView.Horizontal
  interactive: false
  highlightRangeMode: ListView.NoHighlightRange
  snapMode: ListView.NoSnap
  // Uma página inteira de cada lado já montada: virar a página não cria
  // 35 ícones no meio da animação.
  cacheBuffer: Math.max(0, width)
  reuseItems: false
  model: pages.pageCount

  // Tela nova ou menos páginas (um app ocultado): volta a alinhar.
  onWidthChanged: pages.jumpTo(pages.page)
  onPageCountChanged: Qt.callLater(function() { pages.jumpTo(pages.page) })

  NumberAnimation {
    id: settle
    target: pages
    property: "contentX"
    easing.type: Easing.OutCubic
  }

  delegate: Item {
    id: page

    required property int index

    width: pages.width
    height: pages.height

    // Espaço vazio entre os ícones fecha o Launchpad (fica por baixo das
    // células; um arrasto cancela o clique).
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: pages.emptyClicked()
    }

    Repeater {
      model: pages.items.slice(page.index * pages.perPage, (page.index + 1) * pages.perPage)

      delegate: AppCell {
        x: pages.gridX + (index % pages.cols) * pages.cellWidth
        y: pages.gridY + Math.floor(index / pages.cols) * pages.cellHeight
        width: pages.cellWidth
        height: pages.cellHeight
        globalIndex: page.index * pages.perPage + index
        iconSize: pages.iconSize
        labelGap: pages.labelGap
        devicePixelRatio: pages.devicePixelRatio
        selected: pages.showSelection && globalIndex === pages.selectedIndex
        onActivated: function(globalIndex) { pages.activated(globalIndex) }
        onMenuRequested: function(globalIndex, sceneX, sceneY) { pages.menuRequested(globalIndex, sceneX, sceneY) }
      }
    }
  }

  // Arrasto com mouse, toque ou clique-e-arraste do touchpad. Passado o
  // limiar de arrasto, toma o clique das células (que então não abrem nada).
  DragHandler {
    id: drag

    property real startX: 0
    // Últimas posições com horário: a velocidade do Qt fica "congelada" no
    // último movimento quando o dedo para antes de soltar.
    property var samples: []

    // Velocidade (px/s) dos últimos ~80 ms; zero se o dedo parou antes de soltar.
    function releaseVelocity() {
      var list = drag.samples
      if (list.length < 2) return 0
      var last = list[list.length - 1]
      if (Date.now() - last.t > 90) return 0
      var first = list[0]
      for (var i = list.length - 2; i >= 0; i--) {
        first = list[i]
        if (last.t - first.t >= 60) break
      }
      var seconds = (last.t - first.t) / 1000
      return seconds > 0 ? (last.x - first.x) / seconds : 0
    }

    target: null
    enabled: pages.dragEnabled
    yAxis.enabled: false
    onActiveChanged: {
      if (drag.active) {
        settle.stop()
        drag.startX = pages.contentX
        drag.samples = [{ t: Date.now(), x: 0 }]
      } else {
        pages.release(drag.releaseVelocity())
      }
    }
    onTranslationChanged: {
      if (!drag.active) return
      pages.contentX = pages.elastic(drag.startX - drag.activeTranslation.x)
      drag.samples.push({ t: Date.now(), x: drag.activeTranslation.x })
      if (drag.samples.length > 8) drag.samples.shift()
    }
  }

  // Roda do mouse e rolagem de dois dedos: acumula até um limiar e vira uma
  // página; a trava curta impede que o resto do mesmo gesto vire várias.
  // Delta negativo (roda para baixo, dedos para a esquerda com rolagem
  // natural) = próxima página, a mesma convenção do Flickable. O `inverted`
  // não é compensado: a preferência de rolagem do sistema já vem no delta.
  function wheelStep(event, horizontal) {
    event.accepted = true
    if (!pages.dragEnabled || drag.active) return
    var pixel = event.pixelDelta
    var usePixel = pixel.x !== 0 || pixel.y !== 0
    var dx = usePixel ? pixel.x : event.angleDelta.x
    var dy = usePixel ? pixel.y : event.angleDelta.y
    // Cada evento conta uma vez só, no handler do eixo dominante.
    if ((Math.abs(dx) > Math.abs(dy)) !== horizontal) return
    var delta = horizontal ? dx : dy
    var now = Date.now()
    if (now < pages.wheelLockedUntil) {
      pages.wheelAccumulated = 0
      return
    }
    if (pages.wheelAccumulated * delta < 0) pages.wheelAccumulated = 0
    pages.wheelAccumulated += delta
    if (Math.abs(pages.wheelAccumulated) < (usePixel ? 48 : 110)) return
    pages.step(pages.wheelAccumulated < 0 ? 1 : -1)
    pages.wheelAccumulated = 0
    pages.wheelLockedUntil = now + 340
  }

  // O WheelHandler só escuta um eixo (o padrão é o vertical): um para cada.
  WheelHandler {
    target: null
    orientation: Qt.Vertical
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { pages.wheelStep(event, false) }
  }

  WheelHandler {
    target: null
    orientation: Qt.Horizontal
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) { pages.wheelStep(event, true) }
  }
}

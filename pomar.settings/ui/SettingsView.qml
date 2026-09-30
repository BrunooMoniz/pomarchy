import QtQuick
import "../shared/Tokens.js" as Tokens

// Conteúdo da janela dos Ajustes: barra lateral de vidro à esquerda (os três
// botões, a marca e as páginas) e a página escolhida à direita.
FocusScope {
  id: view

  property var app
  readonly property var sections: [
    [{ id: "geral", glyph: "gear", tint: Theme.gray }],
    [{ id: "dock", glyph: "dock", tint: Theme.blue },
     { id: "barra", glyph: "menubar", tint: Theme.teal },
     { id: "mission", glyph: "mission", tint: Theme.purple }],
    [{ id: "trackpad", glyph: "trackpad", tint: Theme.orange },
     { id: "teclado", glyph: "keyboard", tint: Theme.gray }],
    [{ id: "sobre", glyph: "leaf", tint: Theme.green }]
  ]

  readonly property Item page: pageLoader.item

  function scrollTo(y) {
    if (view.page && view.page.scrollTo) view.page.scrollTo(y)
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      view.app.close()
      event.accepted = true
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      var list = view.app.pages
      var index = list.indexOf(view.app.page) + (event.key === Qt.Key_Down ? 1 : -1)
      if (index >= 0 && index < list.length) view.app.goTo(list[index])
      event.accepted = true
    }
  }

  // ------------------------------------------------------------ fundo
  // Lado direito quase opaco (leitura), lado esquerdo de vidro: o desfoque do
  // Hyprland aparece só na barra lateral.
  Item {
    anchors.fill: parent
    anchors.leftMargin: Theme.sidebarWidth
    clip: true
    Rectangle {
      x: -Theme.windowRadius * 2
      width: parent.width + Theme.windowRadius * 2
      height: parent.height
      radius: Theme.windowRadius
      color: Theme.windowFill
    }
  }

  Item {
    width: Theme.sidebarWidth
    height: parent.height
    clip: true
    Rectangle {
      width: parent.width + Theme.windowRadius * 2
      height: parent.height
      radius: Theme.windowRadius
      color: Theme.sidebarFill
    }
  }

  Rectangle {
    x: Theme.sidebarWidth
    width: 1
    height: parent.height
    color: Theme.separator
    opacity: Theme.dark ? 1.0 : 0.7
  }

  // ------------------------------------------------------------ barra lateral
  Item {
    id: sidebar
    width: Theme.sidebarWidth
    height: parent.height

    TrafficLights {
      x: 20
      y: 20
      onCloseClicked: view.app.close()
    }

    // Cartão da marca, como o da conta no topo dos Ajustes do Mac.
    Item {
      id: brand
      x: 10
      y: 50
      width: parent.width - 20
      height: 54

      Rectangle {
        anchors.fill: parent
        radius: Theme.itemRadius + 2
        color: view.app.page === "sobre" ? Theme.hover : (brandArea.containsMouse ? Tokens.withAlpha(Theme.hover, Theme.hover.a * 0.7) : "transparent")
      }

      IconTile {
        id: brandTile
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        size: 36
        color: Theme.green
        glyph: "leaf"
      }

      Column {
        anchors.left: brandTile.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Label {
          width: parent.width
          text: "Pomarchy OS"
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Label {
          width: parent.width
          text: view.app.t("brand.subtitle")
          color: Theme.secondary
          font.pixelSize: Theme.caption
          elide: Text.ElideRight
        }
      }

      MouseArea {
        id: brandArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: view.app.goTo("sobre")
      }
    }

    Column {
      id: nav
      y: brand.y + brand.height + 14
      width: parent.width
      spacing: 12

      Repeater {
        model: view.sections

        Column {
          required property var modelData
          width: nav.width
          spacing: 2

          Repeater {
            model: parent.modelData

            SidebarItem {
              required property var modelData
              label: view.app.t("page." + modelData.id)
              glyph: modelData.glyph
              tint: modelData.tint
              selected: view.app.page === modelData.id
              onClicked: view.app.goTo(modelData.id)
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ página
  Item {
    id: content
    anchors.fill: parent
    anchors.leftMargin: Theme.sidebarWidth + 1

    // Faixa de título: o nome pequeno aparece quando o título grande rola
    // para fora, como nos apps do Mac.
    Item {
      id: toolbar
      width: parent.width
      height: 52

      Label {
        anchors.centerIn: parent
        text: view.app.t("page." + view.app.page)
        font.pixelSize: Theme.title
        font.weight: Font.Bold
        opacity: view.page ? Tokens.clamp((view.page.contentY - 60) / 30, 0, 1) : 0
      }

      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.separator
        opacity: view.page ? Tokens.clamp(view.page.contentY / 20, 0, 1) * 0.8 : 0
      }
    }

    Loader {
      id: pageLoader
      anchors.fill: parent
      anchors.topMargin: toolbar.height
      sourceComponent: {
        switch (view.app.page) {
        case "dock": return dockPage
        case "barra": return barraPage
        case "mission": return missionPage
        case "trackpad": return trackpadPage
        case "teclado": return tecladoPage
        case "sobre": return sobrePage
        default: return geralPage
        }
      }
      onLoaded: {
        item.opacity = 0
        fadeIn.restart()
      }
    }

    NumberAnimation {
      id: fadeIn
      target: pageLoader.item
      property: "opacity"
      to: 1
      duration: Tokens.motion.fast
      easing.type: Easing.OutCubic
    }
  }

  Component { id: geralPage; PageGeral { app: view.app } }
  Component { id: dockPage; PageDock { app: view.app } }
  Component { id: barraPage; PageBarra { app: view.app } }
  Component { id: missionPage; PageMission { app: view.app } }
  Component { id: trackpadPage; PageTrackpad { app: view.app } }
  Component { id: tecladoPage; PageTeclado { app: view.app } }
  Component { id: sobrePage; PageSobre { app: view.app } }

  // Contorno da janela por cima de tudo: fio escuro por fora, luz por dentro.
  Rectangle {
    anchors.fill: parent
    radius: Theme.windowRadius
    color: "transparent"
    border.width: 1
    border.color: Theme.outline
    antialiasing: true
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Theme.windowRadius - 1
    color: "transparent"
    border.width: 1
    border.color: Theme.highlight
    opacity: Theme.dark ? 0.5 : 0.8
    antialiasing: true
  }
}

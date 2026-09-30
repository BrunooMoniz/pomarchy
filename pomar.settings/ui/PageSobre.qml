import QtQuick

// Sobre: marca, versão, créditos e o endereço do projeto.
Page {
  id: page

  title: app.t("page.sobre")
  intro: app.t("intro.sobre")
  glyph: "leaf"
  tint: Theme.green
  showHeader: false

  Rectangle {
    width: parent.width
    height: brand.implicitHeight + 56
    radius: Theme.groupRadius
    color: Theme.card
    border.width: 1
    border.color: Theme.cardStroke

    Column {
      id: brand
      anchors.centerIn: parent
      spacing: 10

      IconTile {
        anchors.horizontalCenter: parent.horizontalCenter
        size: 96
        color: Theme.green
        glyph: "leaf"
      }

      Item { width: 1; height: 4 }

      Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Pomarchy OS"
        font.pixelSize: Theme.displayLarge
        font.weight: Font.Bold
      }

      Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: app.t("brand.subtitle")
        font.pixelSize: Theme.subtitle
      }

      Label {
        anchors.horizontalCenter: parent.horizontalCenter
        text: app.t("sobre.version", app.version)
        color: Theme.secondary
        font.pixelSize: Theme.small
      }
    }
  }

  Group {
    title: app.t("sobre.credits")

    FormRow {
      label: app.t("sobre.madeBy", app.author)
    }
    FormRow {
      label: app.t("sobre.builtOn")
    }
    FormRow {
      label: app.t("sobre.license")
    }
  }

  Group {
    FormRow {
      label: app.t("sobre.project")
      description: app.projectUrl
      glyph: "external"
      glyphColor: Theme.blue

      PushButton {
        text: app.t("sobre.open")
        onClicked: app.openProject()
      }
    }
  }
}

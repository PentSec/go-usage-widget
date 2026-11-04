// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// A titled group of setting rows: small uppercase title, then a rounded card
// with a hairline border. Children declared inside become the rows.

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: card

    property QtObject style: null
    property string title: ""

    default property alias rows: body.data

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    readonly property real padding: Math.round(Kirigami.Units.largeSpacing / 1.5)

    Text {
        Layout.leftMargin: 4
        visible: card.title !== ""
        text: card.title.toUpperCase()
        color: card.style ? card.style.muted : Kirigami.Theme.textColor
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + card.padding * 2
        radius: 10
        color: card.style ? card.style.card : "transparent"
        border.width: 1
        border.color: card.style ? card.style.line : "transparent"

        ColumnLayout {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: card.padding
            spacing: Math.round(Kirigami.Units.smallSpacing * 1.2)
        }
    }
}

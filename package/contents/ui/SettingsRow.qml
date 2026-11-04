// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// One setting: label (and optional description) on the left, control on the
// right. Children declared inside become the control.

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

RowLayout {
    id: row

    property QtObject style: null
    property string label: ""
    property string description: ""

    default property alias control: slot.data

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
            Layout.fillWidth: true
            text: row.label
            color: row.style ? row.style.text : Kirigami.Theme.textColor
            font: Kirigami.Theme.defaultFont
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: row.description !== ""
            text: row.description
            color: row.style ? row.style.muted : Kirigami.Theme.textColor
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
            lineHeight: 0.95
        }
    }

    RowLayout {
        id: slot

        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignVCenter
    }
}

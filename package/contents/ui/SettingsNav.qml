// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// Vertical section list for the settings dashboard. Deliberately not pill
// shaped: the hover and selection backgrounds are softly rounded rectangles, so
// the list reads as a navigation column rather than a row of chips.

import QtQuick
import org.kde.kirigami as Kirigami

Column {
    id: nav

    property QtObject style: null
    property var entries: []
    property string current: ""

    signal picked(string key)

    spacing: 2

    Repeater {
        model: nav.entries

        delegate: Item {
            id: entry

            required property var modelData

            readonly property bool active: nav.current === modelData.key
            readonly property bool hovered: hover.hovered

            width: nav.width
            implicitHeight: entryLabel.implicitHeight + 12

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: entry.active
                    ? (nav.style ? nav.style.accentTint : "transparent")
                    : (entry.hovered ? (nav.style ? nav.style.track : "transparent") : "transparent")

                Behavior on color {
                    ColorAnimation {
                        duration: Kirigami.Units.shortDuration
                    }
                }
            }

            Text {
                id: entryLabel

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                text: entry.modelData.label
                color: entry.active
                    ? (nav.style ? nav.style.text : Kirigami.Theme.textColor)
                    : (nav.style ? nav.style.muted : Kirigami.Theme.textColor)
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }

            HoverHandler {
                id: hover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: nav.picked(entry.modelData.key)
            }
        }
    }
}

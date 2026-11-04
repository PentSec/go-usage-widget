// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// A row of pill chips, one per entry, with the current one tinted. Wraps onto a
// second line when the labels do not fit, so a growing list of sections never
// pushes the content sideways.

import QtQuick

import org.kde.kirigami as Kirigami

Flow {
    id: bar

    property QtObject style: null
    property var entries: []
    property string current: ""

    signal picked(string key)

    spacing: 2

    Repeater {
        model: bar.entries

        delegate: Item {
            id: chip

            required property var modelData

            readonly property bool active: bar.current === modelData.key
            readonly property bool hovered: hover.hovered

            implicitWidth: chipLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
            implicitHeight: chipLabel.implicitHeight + Math.round(Kirigami.Units.smallSpacing / 1.5)

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: chip.active
                    ? (bar.style ? bar.style.accentTint : "transparent")
                    : (chip.hovered ? (bar.style ? bar.style.track : "transparent") : "transparent")

                Behavior on color {
                    ColorAnimation {
                        duration: Kirigami.Units.shortDuration
                    }
                }
            }

            Text {
                id: chipLabel

                anchors.centerIn: parent
                text: chip.modelData.label
                color: chip.active
                    ? (bar.style ? bar.style.text : Kirigami.Theme.textColor)
                    : (bar.style ? bar.style.muted : Kirigami.Theme.textColor)
                font: Kirigami.Theme.smallFont
            }

            HoverHandler {
                id: hover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: bar.picked(chip.modelData.key)
            }
        }
    }
}

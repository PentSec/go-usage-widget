// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// Compact pill switch. The owner decides the value: this emits `toggled` with
// what the user asked for and never changes `checked` on its own.

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: control

    property QtObject style: null
    property bool checked: false

    signal toggled(bool requested)

    implicitWidth: 36
    implicitHeight: 20
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: control.checked
            ? (control.style ? control.style.themeAccent : Kirigami.Theme.highlightColor)
            : (control.style ? control.style.line : Kirigami.Theme.disabledTextColor)

        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }
    }

    Rectangle {
        id: knob

        y: 3
        width: 14
        height: 14
        radius: 7
        x: control.checked ? parent.width - width - 3 : 3
        color: control.checked
            ? (control.style ? control.style.knob : "#ffffff")
            : (control.style ? control.style.knobOff : "#ffffff")

        Behavior on x {
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: control.toggled(!control.checked)
    }
}

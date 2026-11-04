// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../code/logic.mjs" as Logic

RowLayout {
    id: row

    // Non-null default so the first bindings never read a missing object; main.qml
    // replaces it with the configured token layer.
    property QtObject style: fallbackStyle

    Style {
        id: fallbackStyle
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    property string label: ""
    property string windowKey: "rolling"
    property var windowData: null
    property double now: Date.now()
    property bool showPace: true
    property bool showCountdown: true

    readonly property var described: Logic.describeWindow(windowData, windowKey, now, {
        showPace: showPace,
        showCountdown: showCountdown
    })

    FontMetrics {
        id: labelMetrics
        font: Kirigami.Theme.smallFont
    }

    FontMetrics {
        id: valueMetrics
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        font.weight: Font.Medium
    }

    // Hidden probes. A real Text always reports its painted width, while
    // FontMetrics can be evaluated before the theme font resolves and then never
    // recompute. These give the columns a reserve that cannot go stale; the
    // minimum width of each label is still its own implicitWidth, so a label can
    // never paint over its neighbour.
    Text {
        id: paceWidestProbe

        visible: false
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        font.weight: Font.Medium
        text: Format.paceText({ kind: "on-pace" })
    }

    Text {
        id: paceNumberProbe

        visible: false
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        font.weight: Font.Medium
        text: Format.paceText({ kind: "reserve", delta: 100 })
    }

    Text {
        id: countdownProbe

        visible: false
        font: Kirigami.Theme.smallFont
        text: "↻ " + Format.countdownText({ kind: "days", days: 31, hours: 23 })
    }

    readonly property real paceReserve: Math.max(paceWidestProbe.implicitWidth, paceNumberProbe.implicitWidth)
    readonly property real countdownReserve: countdownProbe.implicitWidth

    Text {
        text: row.label
        color: row.style.muted
        font: Kirigami.Theme.smallFont
        verticalAlignment: Text.AlignVCenter
        // Reserved from the widest label so the bars always start together.
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: Math.max(labelMetrics.advanceWidth("1mo"), implicitWidth)
    }

    Item {
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit
        Layout.preferredHeight: row.style.barHeight
        implicitHeight: row.style.barHeight

        Rectangle {
            anchors.fill: parent
            radius: row.style.barRadius
            color: row.style.track
        }

        Rectangle {
            id: fill

            readonly property real ratio: row.described.bar.cells > 0
                ? row.described.bar.filled / row.described.bar.cells
                : 0

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * ratio
            radius: row.style.barRadius
            color: row.style.severityColor(row.described.severity)
            visible: width > 0

            Behavior on width {
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Kirigami.Units.shortDuration
                }
            }
        }
    }

    Text {
        id: percentLabel

        text: row.described.clamped + "%"
        color: row.style.percentColor(row.described.severity)
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        font.weight: Font.Medium
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: Math.max(valueMetrics.advanceWidth("100%"), implicitWidth)
    }

    Text {
        id: paceLabel

        text: Format.paceText(row.described.pace)
        color: row.style.paceColor(row.described.pace ? row.described.pace.kind : "")
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        font.weight: Font.Medium
        verticalAlignment: Text.AlignVCenter
        visible: row.showPace
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: Math.max(row.paceReserve, implicitWidth)
    }

    Text {
        id: countdownLabel

        text: row.showCountdown ? "↻ " + Format.countdownText(row.described.countdown) : ""
        color: row.style.muted
        font: Kirigami.Theme.smallFont
        verticalAlignment: Text.AlignVCenter
        visible: row.showCountdown
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: Math.max(row.countdownReserve, implicitWidth)
    }
}

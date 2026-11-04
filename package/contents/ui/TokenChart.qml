// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// Token usage chart. Fed by the local OpenCode databases through
// `opencode_usage.py --tokens`; it never talks to the network.
// Drawn with plain Rectangles so the widget does not depend on Qt Charts.

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../code/logic.mjs" as Logic

ColumnLayout {
    id: chart

    // Non-null default so the first bindings never read a missing object.
    property QtObject style: fallbackStyle

    Style {
        id: fallbackStyle
    }

    property var buckets: null
    property string range: "day"
    property bool busy: false
    property string errorCode: ""

    signal rangePicked(string mode)

    spacing: Kirigami.Units.smallSpacing

    readonly property var values: buckets && buckets.values ? buckets.values : []
    readonly property real peak: buckets && buckets.peak > 0 ? buckets.peak : 0
    readonly property bool empty: !busy && (!buckets || buckets.total === 0)

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            text: chart.buckets ? Logic.compactNumber(chart.buckets.total) : "—"
            color: chart.style.text
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            font.weight: Font.DemiBold
        }

        Text {
            text: i18n("tokens")
            color: chart.style.muted
            font: Kirigami.Theme.smallFont
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: Math.round(Kirigami.Units.smallSpacing / 2)
        }

        Item {
            Layout.fillWidth: true
        }

        Row {
            spacing: 2

            Repeater {
                model: Logic.TOKEN_RANGES

                delegate: Item {
                    id: chip

                    required property var modelData

                    readonly property bool active: chart.range === modelData.key
                    readonly property bool hovered: hover.hovered

                    implicitWidth: chipLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                    implicitHeight: chipLabel.implicitHeight + Math.round(Kirigami.Units.smallSpacing / 1.5)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: chip.active
                            ? chart.style.accentTint
                            : (chip.hovered ? chart.style.track : "transparent")

                        Behavior on color {
                            ColorAnimation {
                                duration: Kirigami.Units.shortDuration
                            }
                        }
                    }

                    Text {
                        id: chipLabel

                        anchors.centerIn: parent
                        text: Format.rangeLabel(chip.modelData.key)
                        color: chip.active ? chart.style.text : chart.style.muted
                        font: Kirigami.Theme.smallFont
                    }

                    HoverHandler {
                        id: hover
                    }

                    TapHandler {
                        onTapped: chart.rangePicked(chip.modelData.key)
                    }
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 2.2

        Row {
            id: bars

            anchors.fill: parent
            spacing: 2

            Repeater {
                model: chart.values

                delegate: Item {
                    id: bar

                    required property int index
                    required property var modelData

                    readonly property int slotCount: chart.values.length
                    readonly property real ratio: chart.peak > 0 ? modelData / chart.peak : 0
                    readonly property bool current: index === slotCount - 1

                    width: slotCount > 0
                        ? (bars.width - (slotCount - 1) * bars.spacing) / slotCount
                        : 0
                    height: bars.height

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: chart.peak > 0 && bar.modelData > 0
                            ? Math.max(2, parent.height * bar.ratio)
                            : 0
                        radius: Math.min(2, width / 2)
                        color: bar.current ? chart.style.accentStrong : chart.style.accentSoft

                        Behavior on height {
                            NumberAnimation {
                                duration: Kirigami.Units.shortDuration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: chart.empty
            text: chart.errorCode ? i18n("Token history unavailable") : i18n("No local sessions yet")
            color: chart.style.muted
            font: Kirigami.Theme.smallFont
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !chart.empty && chart.buckets !== null

        Text {
            text: chart.buckets ? Format.shortDate(chart.buckets.from) : ""
            color: chart.style.muted
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            text: chart.buckets ? Format.shortDate(chart.buckets.to) : ""
            color: chart.style.muted
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}

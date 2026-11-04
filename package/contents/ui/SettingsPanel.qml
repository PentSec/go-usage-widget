// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// The in-popup settings dashboard. Split into sections so the panel stays one
// short page per section instead of an endless scroll, and so adding settings
// later means extending a section rather than the whole page.
//
// Every control writes straight to the applet configuration, so it stays in
// sync with the standard Configure dialog.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

ColumnLayout {
    id: panel

    property QtObject style: fallbackStyle
    property var config: ({})
    property string section: "display"

    Style {
        id: fallbackStyle
    }

    readonly property int pollInterval: config.pollInterval !== undefined ? config.pollInterval : 60
    readonly property int backgroundOpacity: config.backgroundOpacity !== undefined ? config.backgroundOpacity : 60

    readonly property var sections: [
        { key: "display", label: i18n("Display") },
        { key: "colours", label: i18n("Colours") },
        { key: "background", label: i18n("Background") }
    ]

    spacing: Kirigami.Units.smallSpacing

    onSectionChanged: page.contentY = 0

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Kirigami.Units.smallSpacing

        SettingsNav {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
            style: panel.style
            entries: panel.sections
            current: panel.section

            onPicked: function(key) {
                panel.section = key;
            }
        }

        Flickable {
            id: page

            Layout.fillWidth: true
            Layout.fillHeight: true

        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        QQC2.ScrollBar.vertical: QQC2.ScrollBar { }

        ColumnLayout {
            id: body

            width: page.width
            spacing: Kirigami.Units.largeSpacing

            SettingsCard {
                style: panel.style
                title: ""
                visible: panel.section === "display"

                SettingsRow {
                    style: panel.style
                    label: i18n("Refresh every")

                    QQC2.Slider {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        from: 30
                        to: 300
                        stepSize: 15
                        value: panel.pollInterval
                        onMoved: panel.config.pollInterval = Math.round(value)
                    }

                    Text {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        text: i18n("%1 s", panel.pollInterval)
                        color: panel.style.muted
                        font: Kirigami.Theme.smallFont
                        horizontalAlignment: Text.AlignRight
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("Show pace")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.showPace !== false
                        onToggled: requested => panel.config.showPace = requested
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("Show countdown")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.showCountdown !== false
                        onToggled: requested => panel.config.showCountdown = requested
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("Show token chart")
                    description: i18n("One point per day, read from your local OpenCode databases.")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.showChart !== false
                        onToggled: requested => panel.config.showChart = requested
                    }
                }
            }

            SettingsCard {
                style: panel.style
                title: ""
                visible: panel.section === "colours"

                SettingsRow {
                    style: panel.style
                    label: i18n("Bar fill")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.useCustomBarColors === true
                        onToggled: requested => panel.config.useCustomBarColors = requested
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomBarColors === true
                        showAlphaChannel: false
                        color: panel.config.barOkColor || "#3fb950"
                        onAccepted: chosen => panel.config.barOkColor = chosen
                        Accessible.name: i18n("Bar colour below 75%")
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomBarColors === true
                        showAlphaChannel: false
                        color: panel.config.barWarnColor || "#d29922"
                        onAccepted: chosen => panel.config.barWarnColor = chosen
                        Accessible.name: i18n("Bar colour at 75% and above")
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomBarColors === true
                        showAlphaChannel: false
                        color: panel.config.barDangerColor || "#f85149"
                        onAccepted: chosen => panel.config.barDangerColor = chosen
                        Accessible.name: i18n("Bar colour at 90% and above")
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("Percentage")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.useCustomPercentColors === true
                        onToggled: requested => panel.config.useCustomPercentColors = requested
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomPercentColors === true
                        showAlphaChannel: false
                        color: panel.config.percentOkColor || "#3fb950"
                        onAccepted: chosen => panel.config.percentOkColor = chosen
                        Accessible.name: i18n("Percentage colour below 75%")
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomPercentColors === true
                        showAlphaChannel: false
                        color: panel.config.percentWarnColor || "#d29922"
                        onAccepted: chosen => panel.config.percentWarnColor = chosen
                        Accessible.name: i18n("Percentage colour at 75% and above")
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomPercentColors === true
                        showAlphaChannel: false
                        color: panel.config.percentDangerColor || "#f85149"
                        onAccepted: chosen => panel.config.percentDangerColor = chosen
                        Accessible.name: i18n("Percentage colour at 90% and above")
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("Pace")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.useCustomPaceColors === true
                        onToggled: requested => panel.config.useCustomPaceColors = requested
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomPaceColors === true
                        showAlphaChannel: false
                        color: panel.config.paceReserveColor || "#3fb950"
                        onAccepted: chosen => panel.config.paceReserveColor = chosen
                        Accessible.name: i18n("Reserve pace colour")
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomPaceColors === true
                        showAlphaChannel: false
                        color: panel.config.paceDeficitColor || "#d29922"
                        onAccepted: chosen => panel.config.paceDeficitColor = chosen
                        Accessible.name: i18n("Deficit pace colour")
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomPaceColors === true
                        showAlphaChannel: false
                        color: panel.config.paceOnPaceColor || "#39c5cf"
                        onAccepted: chosen => panel.config.paceOnPaceColor = chosen
                        Accessible.name: i18n("On pace colour")
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("General text")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.useCustomTextColor === true
                        onToggled: requested => panel.config.useCustomTextColor = requested
                    }

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.useCustomTextColor === true
                        showAlphaChannel: false
                        color: panel.config.textColor || "#ffffff"
                        onAccepted: chosen => panel.config.textColor = chosen
                        Accessible.name: i18n("General text colour")
                    }
                }
            }

            SettingsCard {
                style: panel.style
                title: ""
                visible: panel.section === "background"

                SettingsRow {
                    style: panel.style
                    label: i18n("Custom background")
                    description: i18n("Painted behind the content; the popup frame stays native.")

                    ToggleSwitch {
                        style: panel.style
                        checked: panel.config.customBackground === true
                        onToggled: requested => panel.config.customBackground = requested
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("Colour")

                    KQuickControls.ColorButton {
                        implicitWidth: 32
                        implicitHeight: 22
                        enabled: panel.config.customBackground === true
                        showAlphaChannel: false
                        color: panel.config.backgroundColor || "#000000"
                        onAccepted: chosen => panel.config.backgroundColor = chosen
                        Accessible.name: i18n("Background colour")
                    }
                }

                SettingsRow {
                    style: panel.style
                    label: i18n("Opacity")

                    QQC2.Slider {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        from: 0
                        to: 100
                        stepSize: 5
                        enabled: panel.config.customBackground === true
                        value: panel.backgroundOpacity
                        onMoved: panel.config.backgroundOpacity = Math.round(value)
                    }

                    Text {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        text: panel.backgroundOpacity + "%"
                        color: panel.style.muted
                        font: Kirigami.Theme.smallFont
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
        }
    }
}

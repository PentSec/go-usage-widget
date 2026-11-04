// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.FormLayout {
    property alias cfg_pollInterval: intervalSpin.value
    property alias cfg_showPace: paceCheck.checked
    property alias cfg_showCountdown: countdownCheck.checked
    property alias cfg_showChart: chartCheck.checked

    property alias cfg_useCustomBarColors: barColorsCheck.checked
    property alias cfg_barOkColor: barOk.color
    property alias cfg_barWarnColor: barWarn.color
    property alias cfg_barDangerColor: barDanger.color

    property alias cfg_useCustomPercentColors: percentColorsCheck.checked
    property alias cfg_percentOkColor: percentOk.color
    property alias cfg_percentWarnColor: percentWarn.color
    property alias cfg_percentDangerColor: percentDanger.color

    property alias cfg_useCustomPaceColors: paceColorsCheck.checked
    property alias cfg_paceReserveColor: paceReserve.color
    property alias cfg_paceDeficitColor: paceDeficit.color
    property alias cfg_paceOnPaceColor: paceOnPace.color

    property alias cfg_useCustomTextColor: textColorCheck.checked
    property alias cfg_textColor: textColor.color

    property alias cfg_customBackground: backgroundCheck.checked
    property alias cfg_backgroundColor: backgroundColor.color
    property alias cfg_backgroundOpacity: opacitySlider.value

    // ------------------------------------------------------------ behaviour
    QQC2.SpinBox {
        id: intervalSpin

        from: 30
        to: 3600
        stepSize: 30
        editable: true

        Kirigami.FormData.label: i18n("Refresh every (seconds):")
    }

    QQC2.CheckBox {
        id: paceCheck

        text: i18n("Show pace against the elapsed window")
    }

    QQC2.CheckBox {
        id: countdownCheck

        text: i18n("Show countdown to reset")
    }

    QQC2.CheckBox {
        id: chartCheck

        text: i18n("Show token usage chart under the budget rows")
    }

    // --------------------------------------------------------------- colours
    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Colours")
    }

    QQC2.CheckBox {
        id: barColorsCheck

        Kirigami.FormData.label: i18n("Bar fill:")
        text: i18n("Custom")
    }

    KQuickControls.ColorButton {
        id: barOk

        Kirigami.FormData.label: i18n("Below 75%:")
        enabled: barColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    KQuickControls.ColorButton {
        id: barWarn

        Kirigami.FormData.label: i18n("75% and above:")
        enabled: barColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    KQuickControls.ColorButton {
        id: barDanger

        Kirigami.FormData.label: i18n("90% and above:")
        enabled: barColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    QQC2.CheckBox {
        id: percentColorsCheck

        Kirigami.FormData.label: i18n("Percentage:")
        text: i18n("Custom")
    }

    KQuickControls.ColorButton {
        id: percentOk

        Kirigami.FormData.label: i18n("Below 75%:")
        enabled: percentColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    KQuickControls.ColorButton {
        id: percentWarn

        Kirigami.FormData.label: i18n("75% and above:")
        enabled: percentColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    KQuickControls.ColorButton {
        id: percentDanger

        Kirigami.FormData.label: i18n("90% and above:")
        enabled: percentColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    QQC2.CheckBox {
        id: paceColorsCheck

        Kirigami.FormData.label: i18n("Pace:")
        text: i18n("Custom")
    }

    KQuickControls.ColorButton {
        id: paceReserve

        Kirigami.FormData.label: i18n("Reserve:")
        enabled: paceColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    KQuickControls.ColorButton {
        id: paceDeficit

        Kirigami.FormData.label: i18n("Deficit:")
        enabled: paceColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    KQuickControls.ColorButton {
        id: paceOnPace

        Kirigami.FormData.label: i18n("On pace:")
        enabled: paceColorsCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    QQC2.CheckBox {
        id: textColorCheck

        Kirigami.FormData.label: i18n("General text:")
        text: i18n("Custom")
    }

    KQuickControls.ColorButton {
        id: textColor

        Kirigami.FormData.label: i18n("Colour:")
        enabled: textColorCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    // ------------------------------------------------------------ background
    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Background")
    }

    QQC2.CheckBox {
        id: backgroundCheck

        Kirigami.FormData.label: i18n("Background:")
        text: i18n("Paint a background behind the content")
    }

    KQuickControls.ColorButton {
        id: backgroundColor

        Kirigami.FormData.label: i18n("Colour:")
        enabled: backgroundCheck.checked
        showAlphaChannel: false
        Layout.fillWidth: true
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Opacity:")

        QQC2.Slider {
            id: opacitySlider

            from: 0
            to: 100
            stepSize: 5
            enabled: backgroundCheck.checked
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: Math.round(opacitySlider.value) + "%"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
            horizontalAlignment: Text.AlignRight
        }
    }
}

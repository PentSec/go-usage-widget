// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// The token layer: the QML answer to a stylesheet. Every value starts from the
// user's Plasma theme and can be overridden per group from the configuration.
// It is a plain component rather than a singleton because it reads
// `plasmoid.configuration`, and that context property does not exist at engine
// level where singletons are created.

import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
    id: style

    /// The applet configuration map. Bound once by main.qml.
    property var config: null

    readonly property var settings: config ? config : ({})

    // ------------------------------------------------------------ custom opts
    readonly property bool customBar: settings.useCustomBarColors === true
    readonly property bool customPercent: settings.useCustomPercentColors === true
    readonly property bool customPace: settings.useCustomPaceColors === true
    readonly property bool customText: settings.useCustomTextColor === true

    // ---------------------------------------------------------------- colours
    readonly property color themePositive: Kirigami.Theme.positiveTextColor
    readonly property color themeNeutral: Kirigami.Theme.neutralTextColor
    readonly property color themeNegative: Kirigami.Theme.negativeTextColor
    readonly property color themeAccent: Kirigami.Theme.highlightColor

    readonly property color barOk: customBar ? settings.barOkColor : themePositive
    readonly property color barWarn: customBar ? settings.barWarnColor : themeNeutral
    readonly property color barDanger: customBar ? settings.barDangerColor : themeNegative

    readonly property color percentOk: customPercent ? settings.percentOkColor : themePositive
    readonly property color percentWarn: customPercent ? settings.percentWarnColor : themeNeutral
    readonly property color percentDanger: customPercent ? settings.percentDangerColor : themeNegative

    readonly property color paceReserve: customPace ? settings.paceReserveColor : themePositive
    readonly property color paceDeficit: customPace ? settings.paceDeficitColor : themeNeutral
    readonly property color paceOnPace: customPace ? settings.paceOnPaceColor : themeAccent

    readonly property color text: customText ? settings.textColor : Kirigami.Theme.textColor
    readonly property color muted: Qt.rgba(text.r, text.g, text.b, 0.62)
    readonly property color track: Qt.rgba(text.r, text.g, text.b, 0.15)

    // ------------------------------------------------------------- background
    readonly property bool showBackground: settings.customBackground === true
    readonly property color backgroundColor: settings.backgroundColor !== undefined
        ? settings.backgroundColor : "black"
    readonly property real backgroundOpacity: settings.backgroundOpacity !== undefined
        ? settings.backgroundOpacity / 100 : 0.6
    readonly property color backgroundFill: Qt.rgba(
        backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundOpacity)

    // ------------------------------------------------------------------ sizes
    readonly property real barHeight: Math.max(3, Math.round(Kirigami.Units.gridUnit / 5))
    readonly property real barRadius: barHeight / 2

    function severityColor(bucket) {
        if (bucket === "danger") {
            return barDanger;
        }
        if (bucket === "warn") {
            return barWarn;
        }
        return barOk;
    }

    function percentColor(bucket) {
        if (bucket === "danger") {
            return percentDanger;
        }
        if (bucket === "warn") {
            return percentWarn;
        }
        return percentOk;
    }

    function paceColor(kind) {
        if (kind === "reserve") {
            return paceReserve;
        }
        if (kind === "deficit") {
            return paceDeficit;
        }
        if (kind === "on-pace") {
            return paceOnPace;
        }
        return muted;
    }
}

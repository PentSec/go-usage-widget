// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Effects
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

import "../code/logic.mjs" as Logic

PlasmoidItem {
    id: root

    Style {
        id: tokens
        config: plasmoid.configuration
    }

    // ------------------------------------------------------------- settings
    readonly property int pollIntervalSeconds: Math.max(30, plasmoid.configuration.pollInterval || 60)
    readonly property bool showPace: plasmoid.configuration.showPace !== false
    readonly property bool showCountdown: plasmoid.configuration.showCountdown !== false
    readonly property bool showChart: plasmoid.configuration.showChart !== false
    readonly property string chartRange: plasmoid.configuration.chartRange || "day"

    // ---------------------------------------------------------------- state
    property string phase: "loading"
    property var usage: null
    property string errorCode: ""
    property int errorStatus: 0
    property bool busy: false
    property double now: Date.now()
    property double lastUpdated: 0

    property var tokenDays: null
    property double tokensUpdated: 0
    property bool tokensBusy: false
    property string tokensError: ""
    property bool showSettings: false

    readonly property var tokenBuckets: Logic.tokenBuckets(tokenDays, chartRange, now)

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    readonly property string helperPath: {
        var url = Qt.resolvedUrl("../code/opencode_usage.py").toString();
        return decodeURIComponent(url.replace("file://", ""));
    }

    // ----------------------------------------------------------- behaviour
    function shellQuote(path) {
        return "'" + path.replace(/'/g, "'\\''") + "'";
    }

    function refresh() {
        if (busy) {
            return;
        }
        busy = true;
        watchdog.restart();
        usageSource.connectSource("python3 " + shellQuote(helperPath));
    }

    function refreshTokens() {
        if (tokensBusy) {
            return;
        }
        tokensBusy = true;
        tokensWatchdog.restart();
        tokensSource.connectSource("python3 " + shellQuote(helperPath) + " --tokens");
    }

    onExpandedChanged: function(isExpanded) {
        if (!isExpanded) {
            showSettings = false;
            return;
        }
        if (!showChart) {
            return;
        }
        if (tokenDays === null || Date.now() - tokensUpdated > 300000) {
            refreshTokens();
        }
    }

    function fail(code, status) {
        usage = null;
        errorCode = code;
        errorStatus = status || 0;
        phase = "error";
    }

    function apply(payload) {
        now = Date.now();
        lastUpdated = now;

        if (payload && payload.ok) {
            usage = payload.ok;
            errorCode = "";
            errorStatus = 0;
            phase = "ready";
            return;
        }

        var error = payload && payload.error ? payload.error : {};
        fail(error.code || "unexpected_response", error.status || 0);
    }

    function errorLabel() {
        switch (errorCode) {
        case "no_credential_found":
            return i18n("No OpenCode Go credential found");
        case "credential_rejected":
            return i18n("Credential rejected");
        case "rate_limited":
            return i18n("Rate limited");
        case "network_error":
            return i18n("Network error");
        case "request_timed_out":
            return i18n("Timed out");
        case "invalid_response":
            return i18n("Unexpected response");
        case "unexpected_response":
            return i18n("Unexpected response");
        case "unexpected_error":
            return i18n("Unexpected error");
        case "helper_missing":
            return i18n("python3 not found");
        case "os_error":
            return i18n("Cannot run the usage helper");
        }
        if (errorCode === "http_error") {
            return errorStatus > 0
                ? i18n("Server error (HTTP %1)", errorStatus)
                : i18n("Server error");
        }
        return i18n("Unexpected response");
    }

    // --------------------------------------------------------------- source
    P5Support.DataSource {
        id: usageSource

        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            // The engine reports everything at once, when the process exits.
            if (data["exit code"] === undefined) {
                return;
            }

            watchdog.stop();
            usageSource.disconnectSource(sourceName);
            root.busy = false;

            var exitCode = data["exit code"];
            if (exitCode === 127) {
                root.fail("helper_missing");
                return;
            }

            var stdout = data["stdout"] || "";
            if (exitCode !== 0 || stdout.length === 0) {
                root.fail("os_error");
                return;
            }

            try {
                root.apply(JSON.parse(stdout));
            } catch (parseError) {
                root.fail("unexpected_response");
            }
        }
    }

    Timer {
        id: watchdog

        interval: 20000
        repeat: false

        onTriggered: {
            if (!root.busy) {
                return;
            }
            root.busy = false;
            root.fail("request_timed_out");
        }
    }

    P5Support.DataSource {
        id: tokensSource

        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            if (data["exit code"] === undefined) {
                return;
            }

            tokensWatchdog.stop();
            tokensSource.disconnectSource(sourceName);
            root.tokensBusy = false;

            var stdout = data["stdout"] || "";
            if (data["exit code"] !== 0 || stdout.length === 0) {
                root.tokensError = "os_error";
                return;
            }

            try {
                var payload = JSON.parse(stdout);
                if (payload && payload.ok && Array.isArray(payload.ok.days)) {
                    root.tokenDays = payload.ok.days;
                    root.tokensUpdated = Date.now();
                    root.tokensError = "";
                } else {
                    root.tokensError = "unexpected_response";
                }
            } catch (parseError) {
                root.tokensError = "unexpected_response";
            }
        }
    }

    Timer {
        id: tokensWatchdog

        interval: 30000
        repeat: false

        onTriggered: {
            if (!root.tokensBusy) {
                return;
            }
            root.tokensBusy = false;
            root.tokensError = "request_timed_out";
        }
    }

    Timer {
        interval: root.pollIntervalSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true

        onTriggered: root.now = Date.now()
    }

    // --------------------------------------------------------------- compact
    compactRepresentation: Item {
        id: compact

        implicitWidth: chips.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: Kirigami.Units.gridUnit
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.minimumHeight: implicitHeight

        Accessible.role: Accessible.Button
        Accessible.name: i18n("OpenCode Go Usage")
        Accessible.description: i18n("Shows the OpenCode Go usage breakdown")

        TapHandler {
            onTapped: root.expanded = !root.expanded
        }

        Grid {
            id: chips

            anchors.centerIn: parent
            columns: root.vertical ? 1 : Logic.WINDOWS.length
            columnSpacing: Kirigami.Units.smallSpacing * 1.6
            rowSpacing: 0

            Repeater {
                model: Logic.WINDOWS

                delegate: Row {
                    required property var modelData

                    readonly property var entry: root.usage ? root.usage[modelData.key] : null

                    spacing: Kirigami.Units.smallSpacing / 2

                    Text {
                        text: modelData.label
                        color: tokens.muted
                        font: Kirigami.Theme.smallFont
                    }

                    Text {
                        text: parent.entry ? Logic.clampPercent(parent.entry.percent) + "%" : "—"
                        color: parent.entry ? tokens.percentColor(Logic.severity(parent.entry.percent)) : tokens.muted
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ full
    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 21
        Layout.minimumHeight: root.showSettings
            ? Kirigami.Units.gridUnit * 20
            : usageContent.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.preferredHeight: Layout.minimumHeight

        contentItem: Item {
            implicitWidth: usageContent.implicitWidth
            implicitHeight: usageContent.implicitHeight

            Rectangle {
                anchors.fill: parent
                visible: tokens.showBackground
                color: tokens.backgroundFill
                radius: Kirigami.Units.largeSpacing / 2
            }

            ColumnLayout {
                id: body

                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        level: 3
                        text: root.showSettings ? i18n("Settings") : i18n("OpenCode Go Usage")
                        color: tokens.text
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Item {
                        id: settingsButton

                        implicitWidth: 28
                        implicitHeight: 28
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: root.showSettings ? i18n("Back to usage") : i18n("Settings")

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: settingsHover.hovered || root.showSettings ? tokens.track : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Kirigami.Units.shortDuration
                                }
                            }
                        }

                        Image {
                            id: settingsIcon

                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: root.showSettings
                                ? Qt.resolvedUrl("../assets/arrow-left-dashed.svg")
                                : Qt.resolvedUrl("../assets/adjustments.svg")
                            sourceSize.width: 18
                            sourceSize.height: 18
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: settingsIcon
                            source: settingsIcon
                            colorization: 1
                            colorizationColor: tokens.text
                        }

                        HoverHandler {
                            id: settingsHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: root.showSettings = !root.showSettings
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "view-refresh"
                        enabled: !root.busy
                        onClicked: root.refresh()

                        Accessible.name: i18n("Refresh now")
                        QQC2.ToolTip.text: i18n("Refresh now")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }

                ColumnLayout {
                    id: usageContent

                    Layout.fillWidth: true
                    visible: !root.showSettings
                    spacing: Kirigami.Units.smallSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: root.phase === "ready"

                        Repeater {
                            model: Logic.WINDOWS

                            delegate: UsageRow {
                                required property var modelData

                                style: tokens
                                Layout.fillWidth: true
                                label: modelData.label
                                windowKey: modelData.key
                                windowData: root.usage ? root.usage[modelData.key] : null
                                now: root.now
                                showPace: root.showPace
                                showCountdown: root.showCountdown
                            }
                        }
                    }

                    TokenChart {
                        visible: root.showChart && root.phase === "ready"

                        style: tokens
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        buckets: root.tokenBuckets
                        range: root.chartRange
                        busy: root.tokensBusy
                        errorCode: root.tokensError

                        onRangePicked: function(mode) {
                            plasmoid.configuration.chartRange = mode;
                        }
                    }

                    Text {
                        visible: root.phase === "loading"
                        text: "…"
                        color: tokens.muted
                        font: Kirigami.Theme.defaultFont
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: root.phase === "error"
                        text: "✗ " + root.errorLabel()
                        color: tokens.themeNegative
                        font: Kirigami.Theme.defaultFont
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    Text {
                        visible: root.phase === "ready" && root.lastUpdated > 0
                        text: i18n("Updated %1", Qt.formatTime(new Date(root.lastUpdated), Qt.DefaultLocaleShortDate))
                        color: tokens.muted
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                    }
                }

                SettingsPanel {
                    visible: root.showSettings

                    style: tokens
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    config: plasmoid.configuration
                }
            }
        }
    }
}

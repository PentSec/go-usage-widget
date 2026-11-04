// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// Token usage curve. Fed by the local OpenCode databases through
// `opencode_usage.py --tokens`; it never talks to the network.
//
// The curve is a chain of cubic segments whose control points sit on the same
// horizontal line as their endpoints, so the slope is zero at every sample and
// the line never overshoots a value that was not measured. `curveTension`
// moves those control points between the endpoints.

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

    // Presentation knobs. Sensible defaults, all optional.
    property real curveTension: 0.5
    property bool showFill: true
    property bool showGlow: true
    property bool showGrid: true

    property int hoverIndex: -1

    signal rangePicked(string mode)

    spacing: Kirigami.Units.smallSpacing

    readonly property var values: buckets && buckets.values ? buckets.values : []
    readonly property real peak: buckets && buckets.peak > 0 ? buckets.peak : 0
    readonly property bool empty: !busy && (!buckets || buckets.total === 0)
    readonly property bool hovering: hoverIndex >= 0 && hoverIndex < values.length
    readonly property var rangeEntries: Logic.TOKEN_RANGES.map(function (entry) {
        return { key: entry.key, label: Format.rangeLabel(entry.key) };
    })

    function bucketLabel(index) {
        if (!buckets || !buckets.labels || index < 0 || index >= buckets.labels.length) {
            return "";
        }
        return buckets.labels[index];
    }

    function updateHover(positionX) {
        var count = values.length;
        if (count === 0 || peak <= 0) {
            hoverIndex = -1;
            return;
        }
        var inset = 3;
        var usable = Math.max(1, plot.width - inset * 2);
        var ratio = (positionX - inset) / usable;
        hoverIndex = Math.max(0, Math.min(count - 1, Math.round(ratio * (count - 1))));
    }

    // ---------------------------------------------------------------- header
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            text: chart.hovering
                ? Logic.compactNumber(chart.values[chart.hoverIndex])
                : (chart.buckets ? Logic.compactNumber(chart.buckets.total) : "—")
            color: chart.style.text
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            font.weight: Font.DemiBold
        }

        Text {
            text: chart.hovering
                ? Format.shortDate(chart.bucketLabel(chart.hoverIndex))
                : i18n("tokens")
            color: chart.style.muted
            font: Kirigami.Theme.smallFont
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: Math.round(Kirigami.Units.smallSpacing / 2)
        }

        Item {
            Layout.fillWidth: true
        }

        ChipBar {
            style: chart.style
            entries: chart.rangeEntries
            current: chart.range

            onPicked: function(key) {
                chart.rangePicked(key);
            }
        }
    }

    // ------------------------------------------------------------------ plot
    Item {
        id: plotArea

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 3.2

        Canvas {
            id: plot

            anchors.fill: parent
            visible: !chart.empty

            property color lineColor: chart.style.themeAccent
            property color gridColor: chart.style.text

            onLineColorChanged: requestPaint()
            onGridColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: requestPaint()

            onPaint: renderCurve()

            Connections {
                target: chart

                function onValuesChanged() {
                    plot.requestPaint();
                }

                function onHoverIndexChanged() {
                    plot.requestPaint();
                }

                function onCurveTensionChanged() {
                    plot.requestPaint();
                }

                function onShowFillChanged() {
                    plot.requestPaint();
                }

                function onShowGlowChanged() {
                    plot.requestPaint();
                }

                function onShowGridChanged() {
                    plot.requestPaint();
                }
            }

            function rgba(color, alpha) {
                if (!color || color.r === undefined) {
                    return "rgba(255,255,255," + alpha + ")";
                }
                return "rgba(" + Math.round(color.r * 255) + ","
                    + Math.round(color.g * 255) + ","
                    + Math.round(color.b * 255) + ","
                    + alpha + ")";
            }

            function renderCurve() {
                var ctx = getContext("2d");
                var width = plot.width;
                var height = plot.height;
                ctx.clearRect(0, 0, width, height);

                var series = chart.values;
                var count = series.length;
                if (count === 0) {
                    return;
                }

                var top = 6;
                var bottom = 3;
                var inset = 3;
                var usableWidth = Math.max(1, width - inset * 2);
                var usableHeight = Math.max(1, height - top - bottom);
                var peak = chart.peak;

                function atX(index) {
                    return count === 1 ? width / 2 : inset + (index / (count - 1)) * usableWidth;
                }

                function atY(value) {
                    if (peak <= 0) {
                        return top + usableHeight;
                    }
                    return top + usableHeight - (value / peak) * usableHeight;
                }

                function traceCurve() {
                    ctx.moveTo(atX(0), atY(series[0]));
                    for (var index = 0; index < count - 1; ++index) {
                        var x0 = atX(index);
                        var y0 = atY(series[index]);
                        var x1 = atX(index + 1);
                        var y1 = atY(series[index + 1]);
                        var span = x1 - x0;
                        ctx.bezierCurveTo(
                            x0 + span * chart.curveTension, y0,
                            x1 - span * chart.curveTension, y1,
                            x1, y1);
                    }
                }

                if (chart.showGrid && peak > 0) {
                    ctx.save();
                    ctx.setLineDash([2, 4]);
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = rgba(gridColor, 0.16);
                    var levels = [0.25, 0.5, 0.75, 1];
                    for (var level = 0; level < levels.length; ++level) {
                        var y = top + usableHeight - levels[level] * usableHeight;
                        ctx.beginPath();
                        ctx.moveTo(inset, y);
                        ctx.lineTo(width - inset, y);
                        ctx.stroke();
                    }
                    ctx.restore();
                }

                var accent = chart.style.themeAccent;

                if (chart.showGlow) {
                    var passes = [[12, 0.06], [7, 0.13], [3.5, 0.28]];
                    for (var pass = 0; pass < passes.length; ++pass) {
                        ctx.save();
                        ctx.beginPath();
                        traceCurve();
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";
                        ctx.lineWidth = passes[pass][0];
                        ctx.strokeStyle = rgba(accent, passes[pass][1]);
                        ctx.stroke();
                        ctx.restore();
                    }
                }

                if (chart.showFill) {
                    var gradient = ctx.createLinearGradient(0, top, 0, height);
                    gradient.addColorStop(0, rgba(accent, 0.26));
                    gradient.addColorStop(0.65, rgba(accent, 0.07));
                    gradient.addColorStop(1, rgba(accent, 0));
                    ctx.beginPath();
                    traceCurve();
                    ctx.lineTo(atX(count - 1), top + usableHeight);
                    ctx.lineTo(atX(0), top + usableHeight);
                    ctx.closePath();
                    ctx.fillStyle = gradient;
                    ctx.fill();
                }

                ctx.beginPath();
                traceCurve();
                ctx.lineWidth = 1.8;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.strokeStyle = rgba(accent, 1);
                ctx.stroke();

                var lastX = atX(count - 1);
                var lastY = atY(series[count - 1]);
                ctx.beginPath();
                ctx.arc(lastX, lastY, 5.5, 0, Math.PI * 2);
                ctx.fillStyle = rgba(accent, 0.18);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(lastX, lastY, 2.6, 0, Math.PI * 2);
                ctx.fillStyle = rgba(accent, 1);
                ctx.fill();

                if (chart.hovering) {
                    var hoverX = atX(chart.hoverIndex);
                    var hoverY = atY(series[chart.hoverIndex]);
                    ctx.save();
                    ctx.setLineDash([2, 3]);
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = rgba(chart.style.text, 0.22);
                    ctx.beginPath();
                    ctx.moveTo(hoverX, top);
                    ctx.lineTo(hoverX, top + usableHeight);
                    ctx.stroke();
                    ctx.restore();
                    ctx.beginPath();
                    ctx.arc(hoverX, hoverY, 3.2, 0, Math.PI * 2);
                    ctx.fillStyle = rgba(accent, 1);
                    ctx.fill();
                }
            }
        }

        HoverHandler {
            id: pointer

            enabled: !chart.empty

            onPointChanged: chart.updateHover(point.position.x)
            onHoveredChanged: {
                if (!hovered) {
                    chart.hoverIndex = -1;
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

    // ---------------------------------------------------------------- footer
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

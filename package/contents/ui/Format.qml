pragma Singleton

// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// Wording lives here, arithmetic lives in logic.mjs. Keeping the two apart is
// what lets the countdown be translated without touching a single test vector.

import QtQuick

import "../code/logic.mjs" as Logic

QtObject {
    function countdownText(descriptor) {
        if (!descriptor) {
            return "—";
        }
        switch (descriptor.kind) {
        case "days":
            return i18n("%1d %2h", descriptor.days, descriptor.hours);
        case "hours":
            return i18n("%1h %2m", descriptor.hours, descriptor.minutes);
        case "minutes":
            return i18n("%1m", descriptor.minutes);
        case "soon":
            return i18n("<1m");
        case "now":
            return i18n("now");
        case "hidden":
            return "";
        default:
            return "—";
        }
    }

    /// Localised pace label: `+12pp`, `-12pp`, `on pace` or an empty string.
    function paceText(pace) {
        if (!pace) {
            return "";
        }
        if (pace.kind === "on-pace") {
            return i18n("on pace");
        }
        return Logic.formatPaceDelta(pace);
    }
}

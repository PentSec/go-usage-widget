// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

// Pure presentation logic. No QML imports, no I/O, no `Date.now()` default
// arguments: every function receives `now` explicitly so the tests are
// deterministic. Shared verbatim by the plasmoid and `node --test`.

export const WINDOW_KEYS = ["rolling", "weekly", "monthly"];

export const WINDOWS = [
    { key: "rolling", label: "5h" },
    { key: "weekly", label: "7d" },
    { key: "monthly", label: "1mo" },
];

export const BAR_CELLS = 10;
export const PACE_TOLERANCE = 5;
export const WARN_PERCENT = 75;
export const DANGER_PERCENT = 90;

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

/**
 * Round and clamp a raw percentage for display.
 * Non-finite input collapses to 0 instead of poisoning the bar.
 */
export function clampPercent(value) {
    if (typeof value !== "number" || !isFinite(value)) {
        return 0;
    }
    return Math.max(0, Math.min(100, Math.round(value)));
}

/** Severity bucket driving the bar fill and the percentage color. */
export function severity(percent) {
    const clamped = clampPercent(percent);
    if (clamped >= DANGER_PERCENT) {
        return "danger";
    }
    if (clamped >= WARN_PERCENT) {
        return "warn";
    }
    return "ok";
}

/**
 * Ten-step bar model. Zero draws nothing; any non-zero usage draws at least one
 * cell so 1-4% stays visible.
 */
export function bar(percent, width) {
    const cells = Math.max(1, Math.floor(typeof width === "number" ? width : BAR_CELLS));
    const clamped = clampPercent(percent);
    const filled = clamped === 0 ? 0 : Math.max(1, Math.round((clamped / 100) * cells));
    return { filled: filled, empty: cells - filled, cells: cells };
}

/** Start of the calendar month preceding `resetsMs`, in UTC, day clamped. */
export function monthlyStartMs(resetsMs) {
    const resets = new Date(resetsMs);
    const year = resets.getUTCFullYear();
    const month = resets.getUTCMonth();
    const day = resets.getUTCDate();
    const lastDayOfPreviousMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();

    const start = new Date(resetsMs);
    start.setUTCDate(1);
    start.setUTCMonth(month - 1);
    start.setUTCDate(Math.min(day, lastDayOfPreviousMonth));
    return start.getTime();
}

function windowStartMs(resetsMs, kind) {
    if (kind === "rolling") {
        return resetsMs - 5 * HOUR_MS;
    }
    if (kind === "weekly") {
        return resetsMs - 7 * DAY_MS;
    }
    return monthlyStartMs(resetsMs);
}

/**
 * Share of the budget window that has already elapsed, in percent.
 * Returns undefined when the reset timestamp is missing or unusable.
 */
export function expectedPercent(resetsAt, kind, now) {
    if (typeof resetsAt !== "string" || resetsAt.length === 0) {
        return undefined;
    }
    const resets = Date.parse(resetsAt);
    if (!isFinite(resets)) {
        return undefined;
    }
    const start = windowStartMs(resets, kind);
    const length = resets - start;
    if (!(length > 0)) {
        return undefined;
    }
    const elapsed = Math.min(length, Math.max(0, now - start));
    return (elapsed / length) * 100;
}

/**
 * Compare usage against the elapsed share of the window.
 * `usedPercent` must be the raw value: rounding it here would hide sub-point
 * differences that the tolerance band is meant to expose.
 */
export function paceOf(usedPercent, resetsAt, kind, now) {
    const expected = expectedPercent(resetsAt, kind, now);
    if (expected === undefined) {
        return undefined;
    }
    const delta = usedPercent - expected;
    const magnitude = Math.round(Math.abs(delta));
    if (magnitude <= PACE_TOLERANCE) {
        return { kind: "on-pace" };
    }
    return delta < 0
        ? { kind: "reserve", delta: magnitude }
        : { kind: "deficit", delta: magnitude };
}

/**
 * Numeric part of a pace label: `+32pp`, `-6pp`, or an empty string when the
 * pace is on track or unavailable. Language-neutral, so the view can localise
 * the `on pace` wording on its own.
 */
export function formatPaceDelta(pace) {
    if (!pace || pace.kind === "on-pace") {
        return "";
    }
    const sign = pace.kind === "reserve" ? "+" : "-";
    return sign + pace.delta + "pp";
}

/**
 * Reference English label. The plasmoid composes its own localised label from
 * `formatPaceDelta`, so this form exists for parity with the original plugin
 * and for the test vectors.
 */
export function formatPace(pace) {
    if (!pace) {
        return "";
    }
    if (pace.kind === "on-pace") {
        return "on pace";
    }
    return formatPaceDelta(pace);
}

/**
 * Remaining time before a reset, as a locale-neutral descriptor.
 * The view owns the wording (`i18n`), this function owns the arithmetic.
 */
export function countdown(resetsAt, now) {
    if (typeof resetsAt !== "string" || resetsAt.length === 0) {
        return { kind: "unknown" };
    }
    const target = Date.parse(resetsAt);
    if (!isFinite(target)) {
        return { kind: "unknown" };
    }
    const ms = target - now;
    if (ms <= 0) {
        return { kind: "now" };
    }
    const days = Math.floor(ms / DAY_MS);
    if (days >= 1) {
        return { kind: "days", days: days, hours: Math.floor((ms % DAY_MS) / HOUR_MS) };
    }
    const hours = Math.floor(ms / HOUR_MS);
    if (hours >= 1) {
        return { kind: "hours", hours: hours, minutes: Math.floor((ms % HOUR_MS) / MINUTE_MS) };
    }
    const minutes = Math.floor(ms / MINUTE_MS);
    if (minutes >= 1) {
        return { kind: "minutes", minutes: minutes };
    }
    return { kind: "soon" };
}

/**
 * One window, resolved for display. `data` is the sanitized
 * `{percent, resetsAt}` object produced by the helper.
 */
export function describeWindow(data, kind, now, options) {
    const opts = options || {};
    const raw = data && typeof data.percent === "number" ? data.percent : 0;
    const resetsAt = data && typeof data.resetsAt === "string" ? data.resetsAt : undefined;
    return {
        rawPercent: raw,
        clamped: clampPercent(raw),
        severity: severity(raw),
        bar: bar(raw),
        pace: opts.showPace === false ? undefined : paceOf(raw, resetsAt, kind, now),
        countdown: opts.showCountdown === false ? { kind: "hidden" } : countdown(resetsAt, now),
    };
}

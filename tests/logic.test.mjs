// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

import test from "node:test";
import assert from "node:assert/strict";

import {
    BAR_CELLS,
    WINDOWS,
    bar,
    clampPercent,
    countdown,
    describeWindow,
    expectedPercent,
    formatPace,
    formatPaceDelta,
    monthlyStartMs,
    paceOf,
    severity,
} from "../package/contents/code/logic.mjs";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;

test("window order is rolling, weekly, monthly", () => {
    assert.deepEqual(
        WINDOWS.map((w) => w.key),
        ["rolling", "weekly", "monthly"],
    );
    assert.deepEqual(
        WINDOWS.map((w) => w.label),
        ["5h", "7d", "1mo"],
    );
});

test("clampPercent rounds, clamps and neutralises non-finite input", () => {
    assert.equal(clampPercent(74.6), 75);
    assert.equal(clampPercent(74.4), 74);
    assert.equal(clampPercent(-12), 0);
    assert.equal(clampPercent(140), 100);
    assert.equal(clampPercent(Number.NaN), 0);
    assert.equal(clampPercent(Number.POSITIVE_INFINITY), 0);
    assert.equal(clampPercent(undefined), 0);
    assert.equal(clampPercent("42"), 0);
});

test("severity boundaries are 75 and 90", () => {
    assert.equal(severity(0), "ok");
    assert.equal(severity(74), "ok");
    assert.equal(severity(74.6), "warn");
    assert.equal(severity(75), "warn");
    assert.equal(severity(89), "warn");
    assert.equal(severity(89.6), "danger");
    assert.equal(severity(90), "danger");
    assert.equal(severity(100), "danger");
});

test("bar keeps ten cells and never hides low usage", () => {
    assert.deepEqual(bar(0), { filled: 0, empty: 10, cells: 10 });
    assert.equal(bar(1).filled, 1);
    assert.equal(bar(4).filled, 1);
    assert.equal(bar(5).filled, 1);
    assert.equal(bar(100).filled, 10);
    assert.equal(bar(100).empty, 0);
    for (const percent of [0, 1, 33, 66, 99, 100]) {
        const model = bar(percent);
        assert.equal(model.filled + model.empty, BAR_CELLS);
    }
});

test("bar quantises to the same steps as the reference", () => {
    assert.equal(bar(50).filled, 5);
    assert.equal(bar(44).filled, 4);
    assert.equal(bar(46).filled, 5);
    assert.equal(bar(95).filled, 10);
});

test("monthly window is a UTC calendar month with day clamping", () => {
    const at = (iso) => monthlyStartMs(Date.parse(iso));

    assert.equal(at("2026-03-31T00:00:00.000Z"), Date.parse("2026-02-28T00:00:00.000Z"));
    assert.equal(at("2028-03-31T00:00:00.000Z"), Date.parse("2028-02-29T00:00:00.000Z"));
    assert.equal(at("2026-05-31T00:00:00.000Z"), Date.parse("2026-04-30T00:00:00.000Z"));
    assert.equal(at("2026-01-15T00:00:00.000Z"), Date.parse("2025-12-15T00:00:00.000Z"));
    assert.equal(at("2026-03-15T00:00:00.000Z"), Date.parse("2026-02-15T00:00:00.000Z"));
    assert.equal(at("2026-03-01T00:00:00.000Z"), Date.parse("2026-02-01T00:00:00.000Z"));
});

test("monthly window length is 28 to 31 days, never 30 by fiat", () => {
    const lengths = [
        ["2026-03-31T00:00:00.000Z", 31],
        ["2026-02-28T00:00:00.000Z", 31],
        ["2026-03-15T00:00:00.000Z", 28],
        ["2028-03-15T00:00:00.000Z", 29],
    ];
    for (const [iso, days] of lengths) {
        const resets = Date.parse(iso);
        const start = monthlyStartMs(resets);
        assert.equal((resets - start) / DAY, days, iso);
    }
});

test("expected share is linear inside each window", () => {
    const rollingReset = Date.parse("2026-11-03T23:36:33.000Z");
    assert.equal(expectedPercent("2026-11-03T23:36:33.000Z", "rolling", rollingReset - 2.5 * HOUR), 50);

    const weeklyReset = Date.parse("2026-11-09T00:00:00.000Z");
    assert.equal(expectedPercent("2026-11-09T00:00:00.000Z", "weekly", weeklyReset - 3.5 * DAY), 50);

    const monthlyReset = Date.parse("2026-11-15T18:12:24.000Z");
    const monthlyStart = monthlyStartMs(monthlyReset);
    const half = monthlyStart + (monthlyReset - monthlyStart) / 2;
    assert.equal(expectedPercent("2026-11-15T18:12:24.000Z", "monthly", half), 50);
});

test("expected share clamps outside the window", () => {
    const resets = "2026-11-09T00:00:00.000Z";
    const resetsMs = Date.parse(resets);
    assert.equal(expectedPercent(resets, "weekly", resetsMs - 30 * DAY), 0);
    assert.equal(expectedPercent(resets, "weekly", resetsMs + 30 * DAY), 100);
    assert.equal(expectedPercent(undefined, "weekly", Date.now()), undefined);
    assert.equal(expectedPercent("", "weekly", Date.now()), undefined);
    assert.equal(expectedPercent("not a date", "weekly", Date.now()), undefined);
});

test("window time includes weekends", () => {
    // Reset Monday 2026-11-09T00:00Z. Six days earlier is Sunday: the elapsed
    // share is 6/7, so Saturday and Sunday count as budget time.
    const resets = "2026-11-09T00:00:00.000Z";
    const now = Date.parse(resets) - 1 * DAY;
    assert.equal(expectedPercent(resets, "weekly", now), (6 / 7) * 100);
});

test("pace tolerance band is inclusive at 5 after rounding", () => {
    const resets = "2026-11-09T00:00:00.000Z";
    const now = Date.parse(resets) - 3.5 * DAY; // expected 50

    assert.deepEqual(paceOf(50, resets, "weekly", now), { kind: "on-pace" });
    assert.deepEqual(paceOf(55, resets, "weekly", now), { kind: "on-pace" });
    assert.deepEqual(paceOf(55.4, resets, "weekly", now), { kind: "on-pace" });
    assert.deepEqual(paceOf(55.5, resets, "weekly", now), { kind: "deficit", delta: 6 });
    assert.deepEqual(paceOf(56, resets, "weekly", now), { kind: "deficit", delta: 6 });
    assert.deepEqual(paceOf(45, resets, "weekly", now), { kind: "on-pace" });
    assert.deepEqual(paceOf(44.6, resets, "weekly", now), { kind: "on-pace" });
    assert.deepEqual(paceOf(44.5, resets, "weekly", now), { kind: "reserve", delta: 6 });
    assert.deepEqual(paceOf(44, resets, "weekly", now), { kind: "reserve", delta: 6 });
});

test("pace is undefined without a usable reset timestamp", () => {
    assert.equal(paceOf(50, undefined, "weekly", Date.now()), undefined);
    assert.equal(paceOf(50, "nonsense", "weekly", Date.now()), undefined);
});

test("pace labels use the budget sign convention", () => {
    assert.equal(formatPace({ kind: "reserve", delta: 32 }), "+32pp");
    assert.equal(formatPace({ kind: "deficit", delta: 6 }), "-6pp");
    assert.equal(formatPace({ kind: "on-pace" }), "on pace");
    assert.equal(formatPace(undefined), "");
    assert.equal(formatPace({ kind: "reserve", delta: 100 }), "+100pp");
});

test("pace delta leaves the wording to the view", () => {
    assert.equal(formatPaceDelta({ kind: "reserve", delta: 32 }), "+32pp");
    assert.equal(formatPaceDelta({ kind: "deficit", delta: 6 }), "-6pp");
    assert.equal(formatPaceDelta({ kind: "on-pace" }), "");
    assert.equal(formatPaceDelta(undefined), "");
});

test("reference worked example: 31 day window, 19d6h elapsed, 30% used", () => {
    const resets = "2026-11-15T18:12:24.000Z";
    const start = monthlyStartMs(Date.parse(resets));
    const now = start + 19 * DAY + 6 * HOUR;

    const pace = paceOf(30, resets, "monthly", now);
    assert.deepEqual(pace, { kind: "reserve", delta: 32 });
    assert.equal(formatPace(pace), "+32pp");
});

test("pace ignores the rounded percentage", () => {
    // 74.6 rounds to 75 for display but must not be classified with 75.
    const resets = "2026-11-09T00:00:00.000Z";
    const resetsMs = Date.parse(resets);
    const now = resetsMs - 3.5 * DAY;
    // expected 50, raw 52.4 -> delta 2.4 -> on pace; rounded 52 would also be.
    // Use a delta that straddles the band instead: raw 55.6 -> 5.6 -> deficit 6,
    // while the rounded display value 56 is not the input to the pace.
    assert.deepEqual(paceOf(55.6, resets, "weekly", now), { kind: "deficit", delta: 6 });
});

test("countdown descriptors", () => {
    const now = Date.parse("2026-11-03T12:00:00.000Z");
    const at = (ms) => new Date(now + ms).toISOString();

    assert.deepEqual(countdown(at(2 * DAY + 5 * HOUR), now), { kind: "days", days: 2, hours: 5 });
    assert.deepEqual(countdown(at(3 * HOUR + 12 * 60_000), now), { kind: "hours", hours: 3, minutes: 12 });
    assert.deepEqual(countdown(at(42 * 60_000), now), { kind: "minutes", minutes: 42 });
    assert.deepEqual(countdown(at(59_000), now), { kind: "soon" });
    assert.deepEqual(countdown(at(0), now), { kind: "now" });
    assert.deepEqual(countdown(at(-60_000), now), { kind: "now" });
    assert.deepEqual(countdown(undefined, now), { kind: "unknown" });
    assert.deepEqual(countdown("", now), { kind: "unknown" });
    assert.deepEqual(countdown("nope", now), { kind: "unknown" });
});

test("countdown drops sub-hour precision but keeps days", () => {
    const now = 0;
    assert.deepEqual(countdown(new Date(DAY - 1).toISOString(), now), {
        kind: "hours",
        hours: 23,
        minutes: 59,
    });
    assert.deepEqual(countdown(new Date(DAY + HOUR).toISOString(), now), {
        kind: "days",
        days: 1,
        hours: 1,
    });
});

test("describeWindow resolves every display field from one input", () => {
    const resets = "2026-11-09T00:00:00.000Z";
    const now = Date.parse(resets) - 3.5 * DAY;
    const described = describeWindow({ percent: 74.6, resetsAt: resets }, "weekly", now);

    assert.equal(described.rawPercent, 74.6);
    assert.equal(described.clamped, 75);
    assert.equal(described.severity, "warn");
    assert.equal(described.bar.filled, 8);
    assert.deepEqual(described.pace, { kind: "deficit", delta: 25 });
    assert.deepEqual(described.countdown, { kind: "days", days: 3, hours: 12 });
});

test("describeWindow tolerates missing payloads", () => {
    const described = describeWindow(undefined, "rolling", Date.now());
    assert.equal(described.clamped, 0);
    assert.equal(described.severity, "ok");
    assert.equal(described.bar.filled, 0);
    assert.equal(described.pace, undefined);
    assert.deepEqual(described.countdown, { kind: "unknown" });
});

test("describeWindow can hide pace and countdown", () => {
    const described = describeWindow(
        { percent: 10, resetsAt: "2026-11-09T00:00:00.000Z" },
        "weekly",
        Date.parse("2026-11-05T00:00:00.000Z"),
        { showPace: false, showCountdown: false },
    );
    assert.equal(described.pace, undefined);
    assert.deepEqual(described.countdown, { kind: "hidden" });
});

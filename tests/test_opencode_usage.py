# SPDX-FileCopyrightText: 2026 Jeff
# SPDX-License-Identifier: MIT

"""Tests for the credential + HTTP helper.

Run with: python3 -m unittest discover -s tests
"""

from __future__ import annotations

import datetime
import importlib.util
import json
import os
import sqlite3
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "package"
    / "contents"
    / "code"
    / "opencode_usage.py"
)
SPEC = importlib.util.spec_from_file_location("opencode_usage", MODULE_PATH)
usage = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(usage)

NOW_MS = 1_800_000_000_000


class FakeResponse:
    def __init__(self, body: bytes) -> None:
        self._body = body

    def read(self) -> bytes:
        return self._body

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *args: object) -> bool:
        return False


class FakeOpener:
    def __init__(self, outcome: object) -> None:
        self.outcome = outcome
        self.calls: list[tuple[object, float]] = []

    def open(self, request: object, timeout: float) -> FakeResponse:
        self.calls.append((request, timeout))
        if isinstance(self.outcome, BaseException):
            raise self.outcome
        assert isinstance(self.outcome, FakeResponse)
        return self.outcome


def http_error(code: int) -> urllib.error.HTTPError:
    return urllib.error.HTTPError(usage.USAGE_URL, code, "error", None, None)  # type: ignore[arg-type]


def payload(percent: float = 10) -> dict:
    return {
        "usage": {
            "rolling": {"status": "ok", "percent": percent, "resetsAt": "2026-11-03T23:36:33.000Z"},
            "weekly": {"status": "ok", "percent": 3, "resetsAt": "2026-11-09T00:00:00.000Z"},
            "monthly": {"status": "ok", "percent": 30, "resetsAt": "2026-11-15T18:12:24.000Z"},
        }
    }


class CredentialEntryTests(unittest.TestCase):
    def test_plain_fields_in_priority_order(self) -> None:
        self.assertEqual(usage.credential_from_entry({"key": "k", "apiKey": "a"}, NOW_MS), "k")
        self.assertEqual(usage.credential_from_entry({"apiKey": "a", "token": "t"}, NOW_MS), "a")
        self.assertEqual(usage.credential_from_entry({"token": "t"}, NOW_MS), "t")
        self.assertIsNone(usage.credential_from_entry({"key": ""}, NOW_MS))
        self.assertIsNone(usage.credential_from_entry({"key": 42}, NOW_MS))
        self.assertIsNone(usage.credential_from_entry("nope", NOW_MS))
        self.assertIsNone(usage.credential_from_entry(None, NOW_MS))

    def test_oauth_uses_access_unless_expired(self) -> None:
        live = {"type": "oauth", "access": "token", "expires": NOW_MS + 1000}
        self.assertEqual(usage.credential_from_entry(live, NOW_MS), "token")

        expired = {"type": "oauth", "access": "token", "expires": NOW_MS - 1}
        self.assertIsNone(usage.credential_from_entry(expired, NOW_MS))

        no_expiry = {"type": "oauth", "access": "token"}
        self.assertEqual(usage.credential_from_entry(no_expiry, NOW_MS), "token")

        non_numeric = {"type": "oauth", "access": "token", "expires": "soon"}
        self.assertEqual(usage.credential_from_entry(non_numeric, NOW_MS), "token")

        self.assertIsNone(usage.credential_from_entry({"type": "oauth"}, NOW_MS))

    def test_array_layout_returns_first_usable_entry(self) -> None:
        value = [
            {"type": "oauth", "access": "expired", "expires": NOW_MS - 1},
            {"key": "usable"},
            {"key": "second"},
        ]
        self.assertEqual(usage.credential_from_value(value, NOW_MS), "usable")
        self.assertIsNone(usage.credential_from_value([], NOW_MS))


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.base = self.root / "opencode"
        self.base.mkdir()

    def make_db(self, rows: list[tuple[str, object, str]]) -> None:
        connection = sqlite3.connect(self.base / "opencode.db")
        connection.execute(
            "create table credential ("
            "id text primary key, integration_id text, label text not null, "
            "value text not null, active integer, "
            "time_created integer not null, time_updated integer not null)"
        )
        for index, (provider, active, value) in enumerate(rows):
            connection.execute(
                "insert into credential values (?, ?, ?, ?, ?, 0, 0)",
                (f"id{index}", provider, "label", value, active),
            )
        connection.commit()
        connection.close()

    def test_null_active_counts_as_active(self) -> None:
        self.make_db([("opencode-go", None, json.dumps({"key": "legacy"}))])
        self.assertEqual(usage.read_db(self.base / "opencode.db", "opencode-go", NOW_MS), "legacy")

    def test_explicit_active_one_wins_over_null(self) -> None:
        self.make_db(
            [
                ("opencode-go", None, json.dumps({"key": "legacy"})),
                ("opencode-go", 1, json.dumps({"key": "explicit"})),
            ]
        )
        self.assertEqual(usage.read_db(self.base / "opencode.db", "opencode-go", NOW_MS), "explicit")

    def test_inactive_rows_are_excluded(self) -> None:
        self.make_db([("opencode-go", 0, json.dumps({"key": "off"}))])
        self.assertIsNone(usage.read_db(self.base / "opencode.db", "opencode-go", NOW_MS))

    def test_corrupt_row_is_skipped_not_echoed(self) -> None:
        self.make_db([("opencode-go", 1, "{not json")])
        self.assertIsNone(usage.read_db(self.base / "opencode.db", "opencode-go", NOW_MS))

    def test_corrupt_row_does_not_shadow_a_valid_lower_priority_row(self) -> None:
        self.make_db(
            [
                ("opencode-go", 1, "{not json"),
                ("opencode-go", None, json.dumps({"key": "legacy"})),
            ]
        )
        self.assertEqual(usage.read_db(self.base / "opencode.db", "opencode-go", NOW_MS), "legacy")

    def test_exhausted_cycle_budget_stops_reading_the_stores(self) -> None:
        self.make_db([("opencode-go", 1, json.dumps({"key": "go"}))])
        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            self.assertEqual(list(usage.stored_candidates(NOW_MS, deadline=0.0)), [])

    def test_missing_database_and_missing_schema_are_silent(self) -> None:
        self.assertIsNone(usage.read_db(self.base / "absent.db", "opencode-go", NOW_MS))

        connection = sqlite3.connect(self.base / "opencode.db")
        connection.execute("create table other (x text)")
        connection.commit()
        connection.close()
        self.assertIsNone(usage.read_db(self.base / "opencode.db", "opencode-go", NOW_MS))

    def test_auth_json_object_and_array_layouts(self) -> None:
        (self.base / "auth.json").write_text(
            json.dumps(
                {
                    "opencode-go": {"key": "plain"},
                    "opencode": [{"key": "first"}, {"key": "second"}],
                }
            ),
            encoding="utf-8",
        )
        self.assertEqual(usage.read_auth_json(self.base / "auth.json", "opencode-go", NOW_MS), "plain")
        self.assertEqual(usage.read_auth_json(self.base / "auth.json", "opencode", NOW_MS), "first")

    def test_corrupt_auth_json_is_silent(self) -> None:
        (self.base / "auth.json").write_text("{broken", encoding="utf-8")
        self.assertIsNone(usage.read_auth_json(self.base / "auth.json", "opencode-go", NOW_MS))

    def test_databases_are_read_before_auth_json(self) -> None:
        self.make_db([("opencode-go", 1, json.dumps({"key": "from-db"}))])
        (self.base / "auth.json").write_text(
            json.dumps({"opencode-go": {"key": "from-file"}}), encoding="utf-8"
        )
        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            found = list(usage.stored_candidates(NOW_MS))
        self.assertEqual(found, ["from-db", "from-file"])

    def test_provider_order_and_deduplication(self) -> None:
        self.make_db(
            [
                ("opencode", 1, json.dumps({"key": "console"})),
                ("opencode-go", 1, json.dumps({"key": "go"})),
            ]
        )
        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            found = list(usage.stored_candidates(NOW_MS))
        self.assertEqual(found, ["go", "console"])

    def test_duplicate_data_dirs_are_collapsed(self) -> None:
        self.make_db([("opencode-go", 1, json.dumps({"key": "go"}))])
        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base, self.base])):
            found = list(usage.stored_candidates(NOW_MS))
        self.assertEqual(found, ["go"])


class CandidateTests(unittest.TestCase):
    def test_environment_key_comes_first(self) -> None:
        environment = {usage.ENV_KEY: "from-env"}
        with mock.patch.dict(os.environ, environment, clear=False), mock.patch.object(
            usage, "stored_candidates", return_value=iter(["stored"])
        ):
            self.assertEqual(list(usage.candidates(NOW_MS)), ["from-env", "stored"])

    def test_environment_key_is_deduplicated_against_stores(self) -> None:
        environment = {usage.ENV_KEY: "same"}
        with mock.patch.dict(os.environ, environment, clear=False), mock.patch.object(
            usage, "stored_candidates", return_value=iter(["same", "other"])
        ):
            self.assertEqual(list(usage.candidates(NOW_MS)), ["same", "other"])

    def test_blank_environment_key_is_ignored(self) -> None:
        with mock.patch.dict(os.environ, {usage.ENV_KEY: "   "}, clear=False), mock.patch.object(
            usage, "stored_candidates", return_value=iter(["stored"])
        ):
            self.assertEqual(list(usage.candidates(NOW_MS)), ["stored"])

    def test_stores_are_not_touched_when_the_environment_key_works(self) -> None:
        def forbidden(*args: object, **kwargs: object):
            raise AssertionError("stores must stay closed")

        with mock.patch.dict(os.environ, {usage.ENV_KEY: "env"}, clear=False), mock.patch.object(
            usage, "stored_candidates", side_effect=forbidden
        ), mock.patch.object(
            usage, "probe", return_value=(usage.sanitize(payload()), None, None)
        ):
            result = usage.collect(usage.time.monotonic() + usage.CYCLE_BUDGET_S)
        self.assertIn("ok", result)

    def test_data_dirs_follow_the_documented_order(self) -> None:
        environment = {"HOME": "/home/tester", "XDG_DATA_HOME": "/xdg", "LOCALAPPDATA": "/local", "APPDATA": "/roaming"}
        with mock.patch.dict(os.environ, environment, clear=False):
            found = [str(path) for path in usage.data_dirs()]
        self.assertEqual(
            found,
            [
                "/xdg/opencode",
                "/home/tester/.local/share/opencode",
                "/local/opencode",
                "/roaming/opencode",
                "/home/tester/Library/Application Support/opencode",
            ],
        )


class SanitizeTests(unittest.TestCase):
    def test_keeps_only_percent_and_resets(self) -> None:
        sanitized = usage.sanitize(payload(42))
        assert sanitized is not None
        self.assertEqual(sanitized["rolling"], {"percent": 42.0, "resetsAt": "2026-11-03T23:36:33.000Z"})
        self.assertEqual(set(sanitized), {"rolling", "weekly", "monthly"})

    def test_percent_coercion(self) -> None:
        document = payload()
        document["usage"]["rolling"]["percent"] = "12.5"
        sanitized = usage.sanitize(document)
        assert sanitized is not None
        self.assertEqual(sanitized["rolling"]["percent"], 12.5)

        document["usage"]["rolling"]["percent"] = "abc"
        sanitized = usage.sanitize(document)
        assert sanitized is not None
        self.assertEqual(sanitized["rolling"]["percent"], 0.0)

    def test_non_string_reset_becomes_none(self) -> None:
        document = payload()
        document["usage"]["weekly"]["resetsAt"] = 1234
        sanitized = usage.sanitize(document)
        assert sanitized is not None
        self.assertIsNone(sanitized["weekly"]["resetsAt"])

    def test_every_window_must_be_present(self) -> None:
        for broken in ({}, {"usage": {}}, {"usage": {"rolling": {}}}, {"usage": {"rolling": {}, "weekly": {}, "monthly": 3}}):
            self.assertIsNone(usage.sanitize(broken), broken)

    def test_redirects_are_refused(self) -> None:
        handler = usage._NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, "Found", {}, "https://evil.example"))


class ProbeTests(unittest.TestCase):
    def run_probe(self, outcome: object, remaining: float = 10.0):
        opener = FakeOpener(outcome)
        with mock.patch.object(usage, "_OPENER", opener):
            return usage.probe("secret", usage.time.monotonic() + remaining)

    def test_success(self) -> None:
        found, error, status = self.run_probe(FakeResponse(json.dumps(payload()).encode()))
        self.assertEqual(error, None)
        self.assertEqual(status, None)
        assert found is not None
        self.assertEqual(found["monthly"]["percent"], 30.0)

    def test_401_is_credential_rejected(self) -> None:
        self.assertEqual(self.run_probe(http_error(401)), (None, "credential_rejected", 401))

    def test_429_is_rate_limited(self) -> None:
        self.assertEqual(self.run_probe(http_error(429)), (None, "rate_limited", 429))

    def test_5xx_reports_the_status(self) -> None:
        self.assertEqual(self.run_probe(http_error(503)), (None, "http_error", 503))

    def test_redirect_is_not_followed(self) -> None:
        self.assertEqual(self.run_probe(http_error(302)), (None, "http_error", 302))

    def test_invalid_json(self) -> None:
        self.assertEqual(self.run_probe(FakeResponse(b"not json")), (None, "invalid_response", None))

    def test_unexpected_payload(self) -> None:
        self.assertEqual(
            self.run_probe(FakeResponse(json.dumps({"nope": True}).encode())),
            (None, "unexpected_response", None),
        )

    def test_timeout(self) -> None:
        self.assertEqual(self.run_probe(TimeoutError()), (None, "request_timed_out", None))

    def test_wrapped_timeout(self) -> None:
        wrapped = urllib.error.URLError(TimeoutError())
        self.assertEqual(self.run_probe(wrapped), (None, "request_timed_out", None))

    def test_network_error(self) -> None:
        self.assertEqual(
            self.run_probe(urllib.error.URLError(OSError("down"))),
            (None, "network_error", None),
        )

    def test_exhausted_budget_skips_the_request(self) -> None:
        opener = FakeOpener(FakeResponse(b"{}"))
        with mock.patch.object(usage, "_OPENER", opener):
            result = usage.probe("secret", usage.time.monotonic() - 1)
        self.assertEqual(result, (None, "request_timed_out", None))
        self.assertEqual(opener.calls, [])

    def test_authorization_header_is_sent(self) -> None:
        opener = FakeOpener(FakeResponse(json.dumps(payload()).encode()))
        with mock.patch.object(usage, "_OPENER", opener):
            usage.probe("secret", usage.time.monotonic() + 10)
        request = opener.calls[0][0]
        self.assertEqual(request.get_header("Authorization"), "Bearer secret")
        self.assertEqual(request.get_header("Accept"), "application/json")
        self.assertEqual(request.get_header("User-agent"), usage.USER_AGENT)

    def test_user_agent_is_not_the_blocked_urllib_default(self) -> None:
        # The endpoint answers 403 to `Python-urllib/*` even with a valid token.
        self.assertNotIn("python", usage.USER_AGENT.lower())

    def test_helper_version_matches_package_metadata(self) -> None:
        metadata = json.loads(
            (MODULE_PATH.parents[2] / "metadata.json").read_text(encoding="utf-8")
        )
        self.assertEqual(metadata["KPlugin"]["Version"], usage.APP_VERSION)



class CollectTests(unittest.TestCase):
    def collect_with(self, results: dict[str, tuple], order: list[str]) -> dict:
        def fake_probe(key: str, deadline: float):
            return results[key]

        with mock.patch.object(usage, "candidates", return_value=iter(order)), mock.patch.object(
            usage, "probe", side_effect=fake_probe
        ):
            return usage.collect(usage.time.monotonic() + usage.CYCLE_BUDGET_S)

    def test_first_candidate_wins(self) -> None:
        result = self.collect_with({"a": (usage.sanitize(payload()), None, None)}, ["a", "b"])
        self.assertIn("ok", result)

    def test_401_advances_to_the_next_candidate(self) -> None:
        result = self.collect_with(
            {
                "a": (None, "credential_rejected", 401),
                "b": (usage.sanitize(payload()), None, None),
            },
            ["a", "b"],
        )
        self.assertIn("ok", result)

    def test_all_rejected(self) -> None:
        result = self.collect_with(
            {
                "a": (None, "credential_rejected", 401),
                "b": (None, "credential_rejected", 401),
            },
            ["a", "b"],
        )
        self.assertEqual(result, {"error": {"code": "credential_rejected", "status": 401}})

    def test_non_401_stops_the_chain(self) -> None:
        def explode(*args: object, **kwargs: object):
            raise AssertionError("must not advance after a non-401 failure")

        with mock.patch.object(usage, "candidates", return_value=iter(["a", "b"])), mock.patch.object(
            usage, "probe", side_effect=[(None, "rate_limited", 429), explode]
        ):
            result = usage.collect(usage.time.monotonic() + usage.CYCLE_BUDGET_S)
        self.assertEqual(result, {"error": {"code": "rate_limited", "status": 429}})

    def test_no_credential(self) -> None:
        self.assertEqual(
            self.collect_with({}, []),
            {"error": {"code": "no_credential_found"}},
        )

    def test_main_prints_one_json_line(self) -> None:
        with mock.patch.object(usage, "collect", return_value={"ok": usage.sanitize(payload())}), mock.patch.object(
            usage.sys, "stdout"
        ) as stdout:
            self.assertEqual(usage.main([]), 0)
        written = "".join(call.args[0] for call in stdout.write.call_args_list)
        self.assertEqual(written.count("\n"), 1)
        self.assertNotIn("secret", written)
        self.assertIn('"ok"', written)

    def test_main_never_leaks_a_traceback(self) -> None:
        with mock.patch.object(usage, "collect", side_effect=RuntimeError("boom")), mock.patch.object(
            usage.sys, "stdout"
        ) as stdout:
            self.assertEqual(usage.main([]), 0)
        written = "".join(call.args[0] for call in stdout.write.call_args_list)
        self.assertEqual(json.loads(written), {"error": {"code": "unexpected_error"}})


class TokenSeriesTests(unittest.TestCase):
    """`--tokens` reads only aggregates from the local databases."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.base = self.root / "opencode"
        self.base.mkdir()

    def make_session_messages(self, base: Path, rows: list[tuple[int, str, int, int, int]]) -> None:
        connection = sqlite3.connect(base / "opencode.db")
        connection.execute(
            "create table session_message (id text, session_id text, type text, seq integer, "
            "time_created integer, time_updated integer, data text)"
        )
        for index, (timestamp, kind, prompt, completion, reasoning) in enumerate(rows):
            data = json.dumps(
                {"tokens": {"input": prompt, "output": completion, "reasoning": reasoning,
                            "cache": {"read": 999999, "write": 0}}}
            )
            connection.execute(
                "insert into session_message values (?, ?, ?, ?, ?, ?, ?)",
                (f"m{index}", "session", kind, index, timestamp, timestamp, data),
            )
        connection.commit()
        connection.close()

    def make_legacy_messages(self, base: Path, rows: list[tuple[int, str, int]]) -> None:
        connection = sqlite3.connect(base / "opencode.db")
        connection.execute(
            "create table message (id text, session_id text, "
            "time_created integer, time_updated integer, data text)"
        )
        for index, (timestamp, role, total) in enumerate(rows):
            data = json.dumps(
                {"role": role, "tokens": {"total": total, "input": 10, "output": 5,
                                          "reasoning": 0, "cache": {"read": total}}}
            )
            connection.execute(
                "insert into message values (?, ?, ?, ?, ?)",
                (f"m{index}", "session", timestamp, timestamp, data),
            )
        connection.commit()
        connection.close()

    def local_day(self, timestamp_ms: int) -> str:
        return datetime.date.fromtimestamp(timestamp_ms / 1000).isoformat()

    def test_sums_assistant_work_tokens_per_local_day(self) -> None:
        noon = int(datetime.datetime(2026, 5, 16, 12, 0).timestamp() * 1000)
        next_noon = int(datetime.datetime(2026, 5, 17, 12, 0).timestamp() * 1000)

        self.make_session_messages(
            self.base,
            [
                (noon, "assistant", 100, 50, 5),
                (noon + 1000, "assistant", 1, 1, 1),
                (next_noon, "assistant", 7, 0, 0),
                (noon, "user", 999, 999, 999),
            ],
        )

        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            days = usage.token_days()

        self.assertEqual(
            days,
            [
                [self.local_day(noon), 158],
                [self.local_day(next_noon), 7],
            ],
        )

    def test_cache_reads_are_excluded(self) -> None:
        noon = int(datetime.datetime(2026, 5, 16, 12, 0).timestamp() * 1000)
        self.make_session_messages(self.base, [(noon, "assistant", 100, 20, 0)])

        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            days = usage.token_days()

        self.assertEqual(days, [[self.local_day(noon), 120]])

    def test_session_message_wins_over_the_legacy_table(self) -> None:
        noon = int(datetime.datetime(2026, 5, 16, 12, 0).timestamp() * 1000)
        self.make_session_messages(self.base, [(noon, "assistant", 100, 0, 0)])

        connection = sqlite3.connect(self.base / "opencode.db")
        connection.execute(
            "create table message (id text, session_id text, "
            "time_created integer, time_updated integer, data text)"
        )
        connection.execute(
            "insert into message values ('x', 'session', ?, ?, ?)",
            (noon, noon, json.dumps({"role": "assistant", "tokens": {"total": 999999}})),
        )
        connection.commit()
        connection.close()

        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            days = usage.token_days()

        self.assertEqual(days, [[self.local_day(noon), 100]])

    def test_legacy_table_is_used_when_session_message_is_absent(self) -> None:
        noon = int(datetime.datetime(2026, 5, 16, 12, 0).timestamp() * 1000)
        self.make_legacy_messages(self.base, [(noon, "assistant", 500000), (noon, "user", 7)])

        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            days = usage.token_days()

        # input(10) + output(5) + reasoning(0); `tokens.total` includes cache.
        self.assertEqual(days, [[self.local_day(noon), 15]])

    def test_merges_every_database_and_sorts_by_day(self) -> None:
        second = self.root / "other" / "opencode"
        second.mkdir(parents=True)
        day_one = int(datetime.datetime(2026, 5, 16, 9, 0).timestamp() * 1000)
        day_two = int(datetime.datetime(2026, 5, 17, 9, 0).timestamp() * 1000)

        self.make_session_messages(self.base, [(day_two, "assistant", 20, 0, 0)])
        self.make_session_messages(second, [(day_one, "assistant", 5, 0, 0),
                                            (day_two, "assistant", 30, 0, 0)])

        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base, second])):
            days = usage.token_days()

        self.assertEqual(
            days,
            [
                [self.local_day(day_one), 5],
                [self.local_day(day_two), 50],
            ],
        )

    def test_database_without_a_known_table_is_skipped(self) -> None:
        connection = sqlite3.connect(self.base / "opencode.db")
        connection.execute("create table other (x text)")
        connection.commit()
        connection.close()

        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])):
            self.assertEqual(usage.token_days(), [])

    def test_missing_database_returns_an_empty_series(self) -> None:
        with mock.patch.object(usage, "data_dirs", return_value=iter([self.root / "absent"])):
            self.assertEqual(usage.token_days(), [])

    def test_tokens_mode_never_touches_the_network(self) -> None:
        noon = int(datetime.datetime(2026, 5, 16, 12, 0).timestamp() * 1000)
        self.make_session_messages(self.base, [(noon, "assistant", 42, 0, 0)])

        def forbidden(*args: object, **kwargs: object):
            raise AssertionError("tokens mode must not probe")

        with mock.patch.object(usage, "data_dirs", return_value=iter([self.base])), mock.patch.object(
            usage, "probe", side_effect=forbidden
        ), mock.patch.object(usage, "collect", side_effect=forbidden), mock.patch.object(
            usage.sys, "stdout"
        ) as stdout:
            self.assertEqual(usage.main(["--tokens"]), 0)

        written = "".join(call.args[0] for call in stdout.write.call_args_list)
        payload = json.loads(written)
        self.assertEqual(payload, {"ok": {"days": [[self.local_day(noon), 42]]}})

    def test_tokens_mode_reports_an_internal_error_without_a_traceback(self) -> None:
        with mock.patch.object(usage, "token_days", side_effect=RuntimeError("boom")), mock.patch.object(
            usage.sys, "stdout"
        ) as stdout:
            self.assertEqual(usage.main(["--tokens"]), 0)

        written = "".join(call.args[0] for call in stdout.write.call_args_list)
        self.assertEqual(json.loads(written), {"error": {"code": "unexpected_error"}})


if __name__ == "__main__":
    unittest.main()

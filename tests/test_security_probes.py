# SPDX-FileCopyrightText: 2026 Jeff
# SPDX-License-Identifier: MIT

"""Security probes for the credential path (S11-S14, S17).

These are the invariants that must not regress when the helper changes. They are
deliberately separate from the behaviour tests: one class per promise.

Run with: python3 -m unittest discover -s tests
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
import sqlite3
import tempfile
import threading
import unittest
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock

MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "package"
    / "contents"
    / "code"
    / "opencode_usage.py"
)
SPEC = importlib.util.spec_from_file_location("opencode_usage_probes", MODULE_PATH)
usage = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(usage)

NOW_MS = 1_800_000_000_000


def ok_payload() -> dict:
    return {
        "usage": {
            name: {"percent": 1, "resetsAt": "2026-11-03T23:36:33.000Z"}
            for name in usage.WINDOWS
        }
    }


class RedirectProbeTests(unittest.TestCase):
    """The request carries a bearer token, so a redirect could leak it."""

    def test_real_302_and_307_are_refused_without_contacting_target(self) -> None:
        hits: list[str] = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                hits.append(self.path)
                if self.path in ("/r302", "/r307"):
                    self.send_response(302 if self.path == "/r302" else 307)
                    self.send_header("Location", "/target")
                    self.end_headers()
                else:
                    body = json.dumps(ok_payload()).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(body)

            def log_message(self, *args: object) -> None:
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for path, code in (("/r302", 302), ("/r307", 307)):
                with mock.patch.object(
                    usage,
                    "USAGE_URL",
                    "http://127.0.0.1:%d%s" % (server.server_port, path),
                ):
                    self.assertEqual(
                        usage.probe("t", usage.time.monotonic() + 5),
                        (None, "http_error", code),
                    )
        finally:
            server.shutdown()
            server.server_close()

        self.assertNotIn("/target", hits)
        self.assertEqual(hits.count("/r302"), 1)
        self.assertEqual(hits.count("/r307"), 1)


class SanitizationTests(unittest.TestCase):
    """Nothing but percentages, reset timestamps and an error code reaches stdout."""

    def test_main_never_emits_token_path_or_traceback(self) -> None:
        token = "sk-CANARY-1234567890"
        out, err = io.StringIO(), io.StringIO()

        with mock.patch.object(
            usage,
            "collect",
            side_effect=RuntimeError("boom " + token + " /home/secret/path"),
        ), mock.patch.object(usage.sys, "stdout", out), mock.patch.object(usage.sys, "stderr", err):
            self.assertEqual(usage.main([]), 0)

        written = out.getvalue()
        self.assertEqual(written.count("\n"), 1)
        self.assertEqual(json.loads(written), {"error": {"code": "unexpected_error"}})
        combined = written + err.getvalue()
        self.assertNotIn(token, combined)
        self.assertNotIn("Traceback", combined)
        self.assertNotIn("/home/secret", combined)


class StoreProbeTests(unittest.TestCase):
    """The database is opened read-only and the provider is a bound parameter."""

    def make_db(self, base: Path, rows: list[tuple[str, object, str]]) -> None:
        connection = sqlite3.connect(base / "opencode.db")
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

    def test_db_is_read_only_and_parameterized(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            database = base / "opencode.db"
            self.make_db(base, [("opencode-go", 1, json.dumps({"key": "dbsecret"}))])

            seen: dict[str, object] = {}
            real_connect = sqlite3.connect

            def spy(*args: object, **kwargs: object):
                seen["uri"] = args[0]
                seen["kwargs"] = kwargs
                return real_connect(*args, **kwargs)

            with mock.patch.object(usage.sqlite3, "connect", side_effect=spy):
                self.assertIsNone(
                    usage.read_db(database, "opencode-go'; drop table credential; --", NOW_MS)
                )

            self.assertTrue(str(seen["uri"]).endswith("?mode=ro"))
            self.assertIs(seen["kwargs"].get("uri"), True)  # type: ignore[union-attr]

            read_only = real_connect("file:" + str(database) + "?mode=ro", uri=True)
            try:
                with self.assertRaises(sqlite3.OperationalError):
                    read_only.execute("insert into credential values ('x','p','l','v',1,0,0)")
            finally:
                read_only.close()

            self.assertEqual(usage.read_db(database, "opencode-go", NOW_MS), "dbsecret")

    def test_environment_key_never_opens_the_stores(self) -> None:
        def forbidden(*args: object, **kwargs: object):
            raise AssertionError("store must stay closed")

        with mock.patch.dict(os.environ, {usage.ENV_KEY: "env"}, clear=False), mock.patch.object(
            usage.sqlite3, "connect", side_effect=forbidden
        ), mock.patch.object(usage.Path, "open", side_effect=forbidden), mock.patch.object(
            usage, "probe", return_value=(usage.sanitize(ok_payload()), None, None)
        ):
            self.assertIn("ok", usage.collect(usage.time.monotonic() + usage.CYCLE_BUDGET_S))


class OriginProbeTests(unittest.TestCase):
    """The origin is a constant; no environment variable can move it."""

    def test_fixed_origin_cannot_be_overridden(self) -> None:
        holder: list[str] = []

        class Opener:
            def open(self, request: object, timeout: float):
                holder.append(request.full_url)
                raise urllib.error.HTTPError(request.full_url, 500, "error", None, None)

        environment = {
            "OPENCODE_USAGE_URL": "https://evil.example",
            "USAGE_URL": "https://evil.example",
        }
        with mock.patch.dict(os.environ, environment, clear=False), mock.patch.object(
            usage, "_OPENER", Opener()
        ):
            self.assertEqual(
                usage.probe("t", usage.time.monotonic() + 5),
                (None, "http_error", 500),
            )

        self.assertEqual(holder, [usage.USAGE_URL])


if __name__ == "__main__":
    unittest.main()

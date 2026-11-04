#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Jeff
# SPDX-License-Identifier: MIT
"""Resolve an OpenCode Go credential, query the usage endpoint, print one line of JSON.

Contract with the plasmoid:

    stdout  {"ok": {"rolling": {...}, "weekly": {...}, "monthly": {...}}}
            {"error": {"code": "<snake_case_code>", "status": <int|null>}}
    stderr  unused
    exit    0, always

The credential never leaves this process. Only the sanitized payload is printed,
so the token never reaches QML, a widget property, a log line or a tooltip.
"""

from __future__ import annotations

import json
import math
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Iterator

USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
PROVIDERS = ("opencode-go", "opencode")
WINDOWS = ("rolling", "weekly", "monthly")
ENV_KEY = "OPENCODE_GO_API_KEY"

# The endpoint rejects the default urllib User-Agent with a 403 even when the
# token is valid, so the widget identifies itself. Keep in sync with
# metadata.json; `tests/test_opencode_usage.py` enforces the match.
APP_VERSION = "0.1.0"
USER_AGENT = "go-usage-widget/" + APP_VERSION

REQUEST_TIMEOUT_S = 10.0
CYCLE_BUDGET_S = 15.0

CREDENTIAL_FIELDS = ("key", "apiKey", "access", "token")

ERROR_NO_CREDENTIAL = "no_credential_found"
ERROR_REJECTED = "credential_rejected"
ERROR_RATE_LIMITED = "rate_limited"
ERROR_NETWORK = "network_error"
ERROR_TIMEOUT = "request_timed_out"
ERROR_INVALID = "invalid_response"
ERROR_UNEXPECTED = "unexpected_response"
ERROR_HTTP = "http_error"
ERROR_UNEXPECTED_INTERNAL = "unexpected_error"

TOKENS_FLAG = "--tokens"

# Cache reads are deliberately excluded: they are the same context re-sent to
# the model, and on a real machine they are about 95% of the raw sum. The chart
# counts work tokens, input + output + reasoning. Note that the legacy
# `message.tokens.total` DOES include cache, which is why it is never used.
TOKENS_QUERY_SESSION_MESSAGE = """
select date(time_created / 1000, 'unixepoch', 'localtime') as day,
       sum(coalesce(json_extract(data, '$.tokens.input'), 0)
         + coalesce(json_extract(data, '$.tokens.output'), 0)
         + coalesce(json_extract(data, '$.tokens.reasoning'), 0)) as tokens
from session_message
where type = 'assistant' and json_extract(data, '$.tokens') is not null
group by day
order by day
"""

# Older OpenCode builds only have the `message` table.
TOKENS_QUERY_MESSAGE = """
select date(time_created / 1000, 'unixepoch', 'localtime') as day,
       sum(coalesce(json_extract(data, '$.tokens.input'), 0)
         + coalesce(json_extract(data, '$.tokens.output'), 0)
         + coalesce(json_extract(data, '$.tokens.reasoning'), 0)) as tokens
from message
where json_extract(data, '$.role') = 'assistant'
group by day
order by day
"""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse every redirect.

    The endpoint is a fixed origin and the request carries a bearer token.
    Following a redirect could hand that token to a different host, so a 3xx is
    surfaced as an error instead.
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D102
        return None


_OPENER = urllib.request.build_opener(_NoRedirect())


def _now_ms() -> int:
    return int(time.time() * 1000)


def data_dirs() -> Iterator[Path]:
    """Candidate OpenCode data directories, deduplicated, in resolution order."""
    candidates: list[Path] = []

    xdg_data_home = os.environ.get("XDG_DATA_HOME")
    if xdg_data_home:
        candidates.append(Path(xdg_data_home) / "opencode")
    candidates.append(Path.home() / ".local" / "share" / "opencode")

    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        candidates.append(Path(local_app_data) / "opencode")
    roaming_app_data = os.environ.get("APPDATA")
    if roaming_app_data:
        candidates.append(Path(roaming_app_data) / "opencode")

    candidates.append(Path.home() / "Library" / "Application Support" / "opencode")

    seen: set[str] = set()
    for candidate in candidates:
        marker = str(candidate)
        if marker in seen:
            continue
        seen.add(marker)
        yield candidate


def credential_from_entry(entry: object, now_ms: int) -> str | None:
    """Extract one credential from a single stored entry, or None."""
    if not isinstance(entry, dict):
        return None

    if entry.get("type") == "oauth":
        expires = entry.get("expires")
        if isinstance(expires, (int, float)) and math.isfinite(expires) and expires <= now_ms:
            return None
        access = entry.get("access")
        return access if isinstance(access, str) and access else None

    for field in CREDENTIAL_FIELDS:
        value = entry.get(field)
        if isinstance(value, str) and value:
            return value
    return None


def credential_from_value(value: object, now_ms: int) -> str | None:
    """Extract a credential from an entry object or an older array of entries."""
    if isinstance(value, list):
        for entry in value:
            found = credential_from_entry(entry, now_ms)
            if found:
                return found
        return None
    return credential_from_entry(value, now_ms)


def read_db(path: Path, provider: str, now_ms: int) -> str | None:
    """Read the active credential for one provider from an OpenCode SQLite database."""
    if not path.is_file():
        return None

    uri = "file:" + urllib.parse.quote(str(path), safe="/") + "?mode=ro"
    try:
        connection = sqlite3.connect(uri, uri=True, timeout=2.0)
    except sqlite3.Error:
        return None

    try:
        rows = connection.execute(
            "select value from credential "
            "where integration_id = ? and coalesce(active, 1) = 1 "
            "order by (active is 1) desc",
            (provider,),
        ).fetchall()
    except sqlite3.Error:
        return None
    finally:
        connection.close()

    # Rows are already ordered so an explicit `active = 1` wins over a legacy
    # NULL row. A corrupt row is skipped instead of discarding the rest.
    for row in rows:
        if row[0] is None:
            continue
        try:
            payload = json.loads(row[0])
        except (TypeError, ValueError):
            continue
        found = credential_from_value(payload, now_ms)
        if found:
            return found
    return None


def read_auth_json(path: Path, provider: str, now_ms: int) -> str | None:
    """Read the credential for one provider from an OpenCode `auth.json`."""
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(document, dict):
        return None
    return credential_from_value(document.get(provider), now_ms)


def stored_candidates(now_ms: int, deadline: float = float("inf")) -> Iterator[str]:
    """Stored credentials: every database first, then every `auth.json`."""
    directories: list[Path] = []
    seen_directories: set[str] = set()
    for directory in data_dirs():
        marker = str(directory)
        if marker in seen_directories:
            continue
        seen_directories.add(marker)
        directories.append(directory)

    for base in directories:
        for provider in PROVIDERS:
            if time.monotonic() >= deadline:
                return
            found = read_db(base / "opencode.db", provider, now_ms)
            if found:
                yield found
    for base in directories:
        for provider in PROVIDERS:
            if time.monotonic() >= deadline:
                return
            found = read_auth_json(base / "auth.json", provider, now_ms)
            if found:
                yield found


def candidates(now_ms: int, deadline: float = float("inf")) -> Iterator[str]:
    """Ordered candidates: environment first, stores resolved lazily, deduplicated."""
    seen: set[str] = set()

    environment = os.environ.get(ENV_KEY, "").strip()
    if environment:
        seen.add(environment)
        yield environment

    for found in stored_candidates(now_ms, deadline):
        if found in seen:
            continue
        seen.add(found)
        yield found


def sanitize(document: object) -> dict[str, dict[str, object]] | None:
    """Validate the payload and keep only what the widget needs."""
    if not isinstance(document, dict):
        return None
    usage = document.get("usage")
    if not isinstance(usage, dict):
        return None

    sanitized: dict[str, dict[str, object]] = {}
    for name in WINDOWS:
        window = usage.get(name)
        if not isinstance(window, dict):
            return None

        percent = window.get("percent")
        try:
            value = float(percent)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            value = 0.0
        if not math.isfinite(value):
            value = 0.0

        resets = window.get("resetsAt")
        sanitized[name] = {
            "percent": value,
            "resetsAt": resets if isinstance(resets, str) else None,
        }
    return sanitized


def probe(key: str, deadline: float) -> tuple[dict | None, str | None, int | None]:
    """One request. Returns (payload, error_code, http_status)."""
    timeout = min(REQUEST_TIMEOUT_S, deadline - time.monotonic())
    if timeout <= 0:
        return None, ERROR_TIMEOUT, None

    request = urllib.request.Request(
        USAGE_URL,
        method="GET",
        headers={
            "Authorization": "Bearer " + key,
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )

    try:
        with _OPENER.open(request, timeout=timeout) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        if status == 401:
            return None, ERROR_REJECTED, 401
        if status == 429:
            return None, ERROR_RATE_LIMITED, 429
        return None, ERROR_HTTP, status
    except TimeoutError:
        return None, ERROR_TIMEOUT, None
    except urllib.error.URLError as error:
        if isinstance(error.reason, TimeoutError):
            return None, ERROR_TIMEOUT, None
        return None, ERROR_NETWORK, None
    except OSError:
        return None, ERROR_NETWORK, None

    try:
        document = json.loads(body)
    except ValueError:
        return None, ERROR_INVALID, None

    payload = sanitize(document)
    if payload is None:
        return None, ERROR_UNEXPECTED, None
    return payload, None, None


def collect(deadline: float) -> dict[str, object]:
    """Try candidates in order. Only a 401 advances to the next one."""
    saw_rejection = False

    for key in candidates(_now_ms(), deadline):
        payload, error_code, status = probe(key, deadline)
        if payload is not None:
            return {"ok": payload}

        if error_code != ERROR_REJECTED:
            failure: dict[str, object] = {"code": error_code}
            if status is not None:
                failure["status"] = status
            return {"error": failure}

        saw_rejection = True

    if saw_rejection:
        return {"error": {"code": ERROR_REJECTED, "status": 401}}
    return {"error": {"code": ERROR_NO_CREDENTIAL}}


def token_days() -> list[list[object]]:
    """Per-day assistant token totals across every OpenCode database, merged.

    Only aggregates leave this process: no prompt, no title, no session id.
    """
    totals: dict[str, int] = {}

    for base in data_dirs():
        database = base / "opencode.db"
        if not database.is_file():
            continue

        uri = "file:" + urllib.parse.quote(str(database), safe="/") + "?mode=ro"
        try:
            connection = sqlite3.connect(uri, uri=True, timeout=2.0)
        except sqlite3.Error:
            continue

        try:
            tables = {
                row[0]
                for row in connection.execute(
                    "select name from sqlite_master where type = 'table'"
                ).fetchall()
            }
            query = (
                TOKENS_QUERY_SESSION_MESSAGE
                if "session_message" in tables
                else TOKENS_QUERY_MESSAGE
            )
            rows = connection.execute(query).fetchall()
        except sqlite3.Error:
            continue
        finally:
            connection.close()

        for day, tokens in rows:
            if not isinstance(day, str) or tokens is None:
                continue
            totals[day] = totals.get(day, 0) + int(tokens)

    return [[day, totals[day]] for day in sorted(totals)]


def tokens_result() -> dict[str, object]:
    try:
        return {"ok": {"days": token_days()}}
    except Exception:  # noqa: BLE001 - never leak a traceback to the widget
        return {"error": {"code": ERROR_UNEXPECTED_INTERNAL}}


def main(argv: list[str]) -> int:
    deadline = time.monotonic() + CYCLE_BUDGET_S
    try:
        if argv and argv[0] == TOKENS_FLAG:
            result = tokens_result()
        else:
            result = collect(deadline)
    except Exception:  # noqa: BLE001 - never leak a traceback to the widget
        result = {"error": {"code": ERROR_UNEXPECTED_INTERNAL}}

    sys.stdout.write(json.dumps(result, separators=(",", ":")))
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

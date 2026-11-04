# OpenCode Go Usage

A KDE Plasma 6 panel widget that shows your OpenCode Go subscription usage for
the three budget windows: **5 hours**, **7 days** and **1 calendar month**.

<div align="center">
<kbd><img width="1440" height="1080" alt="go-usage-kde" src="https://github.com/user-attachments/assets/e5e3ef81-5f13-4a21-a096-d0af78f53cb5" /></kbd>
</div>

## Features

- Three windows with label, bar, percentage, pace and reset countdown.
- Pace compares your usage with the elapsed share of the window and reports
  `+Npp` (reserve), `-Npp` (deficit) or `on pace`.
- Compact panel representation: one chip per window, coloured by severity, with
  the full breakdown in the tooltip.
- Token usage curve under the budget rows, grouped by day, week, month or all
  time, read from your local OpenCode databases.
- Full popup with the complete row layout and a refresh button.
- Everything follows your Plasma theme, colour scheme and accent colour. No
  hardcoded colours.
- Read-only. No telemetry, no storage, no configuration of the endpoint.

## Requirements

- Plasma 6.0 or newer (developed against Plasma 6.8).
- `python3` (any 3.9+) on `PATH`. It is the only runtime dependency and it is
  present on every desktop distribution.

## Install

From a checkout:

```bash
make install
```

Then add the widget to a panel: **right click the panel → Add or Manage Widgets →
OpenCode Go Usage**.

To remove it:

```bash
make uninstall
```

## Configuration

The gear icon in the popup header opens an in-widget settings dashboard, split
into **Display**, **Colours** and **Background** sections so each one stays a
short page instead of an endless scroll. The same icon turns into a back arrow
while the dashboard is open. It writes to the same configuration as the standard
*Configure* dialog, so both stay in sync and either can be used.

| Option | Default | Meaning |
| --- | --- | --- |
| Refresh interval | 60 s | Minimum 30 s. The API is polled on this schedule. |
| Show pace | on | Hide the `+Npp` / `-Npp` column. |
| Show countdown | on | Hide the `↻ …` column. |
| Bar fill colours | theme | Three colours: below 75%, 75% and above, 90% and above. |
| Percentage colours | theme | Same three thresholds, applied to the percentage text. |
| Pace colours | theme | Reserve, deficit and on pace. |
| General text colour | theme | Labels, title and countdown. |
| Background | off | Optional colour and opacity painted behind the content. |
| Token chart | on | Chart of tokens used, fed by the local OpenCode databases. |

Every colour group has its own **Custom** switch. While a group follows the
theme it tracks your Plasma colour scheme and accent colour; the moment you turn
its switch on, the three pickers take over. The background is a separate overlay,
so the native popup frame stays intact.

There is deliberately **no endpoint setting**. The request always goes to the
fixed origin `https://opencode.ai/zen/go/v1/usage`, so a credential can never be
redirected somewhere else.

## Token chart

Below the budget rows the popup draws a smooth curve of the tokens you have
used. Every range plots **one point per day**, so moving along the curve steps
day by day; the range only picks the window: 14 days, 12 weeks, 12 months or the
whole history. The window never starts before your first recorded session, and
hovering a point shows its value and date in the header. It reads only your local
`opencode.db`, aggregating `session_message` when that table exists and falling
back to the older `message` table otherwise.

Two deliberate details:

- **Cache reads are excluded.** On a real machine they are around 95% of the raw
  sum, because they are the same context re-sent to the model. The chart counts
  work tokens: input plus output plus reasoning.
- **It is local, not server side.** The subscription endpoint reports
  percentages, not tokens, so the chart shows what your machine recorded, not
  what the service billed. Neither the chart nor its query ever touches the
  network.

The chart is refreshed when you open the popup, at most once every five minutes.

## How it works

Three layers, each with one job:

| Layer | Language | Responsibility |
| --- | --- | --- |
| `contents/ui/` | QML | Panel chip, popup, bars, animations, theme tokens |
| `contents/code/logic.mjs` | ES module | Pace, bar quantisation, severity, countdown arithmetic |
| `contents/code/opencode_usage.py` | Python 3 stdlib | Credential resolution, HTTP, error mapping |

`logic.mjs` is imported by QML **and** executed by `node --test`, so the widget
and the test suite run the same code. The Python helper is invoked through the
`executable` data engine (`Plasma5Support.DataSource`) on every poll and prints
a single line of JSON.

### Credentials

Resolution order, with the stores opened lazily — only when the environment key
is absent or rejected:

1. `OPENCODE_GO_API_KEY`
2. `opencode.db` (SQLite), provider `opencode-go` then `opencode`
3. `auth.json`, provider `opencode-go` then `opencode`

Candidate data directories are `$XDG_DATA_HOME/opencode`,
`~/.local/share/opencode`, `$LOCALAPPDATA/opencode`, `$APPDATA/opencode` and
`~/Library/Application Support/opencode`, deduplicated in that order.

`active` columns that are `NULL` count as active; an explicit `active = 1` wins;
`active = 0` is skipped. OAuth entries use `access` unless a numeric `expires`
is already in the past. A corrupt row is skipped without discarding the others.

Only a `401` advances to the next candidate. A rate limit, a 5xx, a malformed
payload, a network error or a timeout stops the chain, because another
credential cannot fix any of them.

### Privacy

The credential is read locally and sent only to the fixed `opencode.ai` origin
as a bearer header. It **never enters the QML process**: the helper performs the
request and prints only percentages and reset timestamps, so the token cannot
reach a widget property, a log line, a tooltip or an error message. The helper
refuses HTTP redirects for the same reason.

The widget stores nothing. There is no telemetry.

## Development

```bash
make test     # node --test (three timezones) + python unittest
make lint     # qmllint over every QML file
make run      # load the applet from the working tree in a window
make package  # build build/<id>.plasmoid
```

Test layout:

| File | Covers |
| --- | --- |
| `tests/logic.test.mjs` | bar quantisation, severity boundaries, monthly clamping, pace tolerance and labels, countdown descriptors, timezone independence |
| `tests/test_opencode_usage.py` | entry extraction, provider and store order, `active` semantics, OAuth expiry, payload sanitisation, 401 fallback, non-401 stop, redirect refusal, user agent |
| `tests/test_security_probes.py` | redirects refused against a real local server, no token/path/traceback on stdout, database opened read-only with a bound provider, environment key never opens the stores, origin cannot be overridden |

QML is verified by loading it in `plasmawindowed`; that is the only check that
catches binding and attached-property errors, so it is part of the release
checklist rather than of CI.

## Releasing

1. Bump `KPlugin.Version` in `package/metadata.json` and `APP_VERSION` in
   `contents/code/opencode_usage.py`. A test asserts they match.
2. Update `CHANGELOG.md`.
3. `make test && make package`.
4. Upload `build/io.github.pentsec.gousage.plasmoid` to the KDE Store.

## TUI go-usage plugin for opencode.
[opencode-go-usage-meter](https://github.com/PentSec/opencode-go-usage-meter)

## License

MIT. See [LICENSE](LICENSE).

### Support me ❤️ ⬎

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/D5R327PO99)

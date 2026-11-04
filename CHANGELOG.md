# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Token usage curve under the budget rows, with day, week, month and all-time
  ranges, fed by the local OpenCode databases. Cache reads are excluded, so the
  figure counts input, output and reasoning only. Enabled by default and
  switchable in the settings.

## [0.1.0] - 2026-11-04

### Added

- Plasma 6 applet with 5 hour, 7 day and calendar month budget windows.
- Pace indicator (`+Npp` reserve, `-Npp` deficit, `on pace`) against the elapsed
  share of each window.
- Reset countdown with `Xd Yh`, `Xh Ym`, `Xm`, `<1m` and `now` forms.
- Severity colouring at 75% and 90%, applied to the bar fill and the percentage.
- Credential resolution from `OPENCODE_GO_API_KEY`, `opencode.db` and
  `auth.json`, with `opencode-go` preferred over `opencode`.
- Python helper that performs the request, so the token never enters the QML
  process.
- Compact panel chips and a full popup with refresh action.
- 20 logic tests (three timezones) and 51 helper tests, including a dedicated
  security-probe suite for the credential path.

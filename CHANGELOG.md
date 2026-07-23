# Changelog

All notable changes to the DDEV Pressable provider add-on are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `post-import-db` URL rewrite after `ddev pull pressable` was a silent no-op.
  DDEV's `wp-config-ddev.php` defines the `WP_HOME` / `WP_SITEURL` constants, so
  `wp option get siteurl|home` returned `DDEV_PRIMARY_URL` and masked the stored
  production value — the rewrite guard was always false and `wp search-replace`
  never ran, leaving the local database pointed at the production/staging domain.
  The hook now reads the raw `siteurl`/`home` values from the options table so
  the constants cannot mask them, and additionally rewrites JSON-escaped
  (`https:\/\/host`) occurrences that `wp search-replace` leaves untouched. The
  push hook mirrors that escaped-slash rewrite so a pull → push round-trip
  leaves no local URL on the remote, and the pull hook now refuses to run if
  `DDEV_PRIMARY_URL` is empty (which would otherwise blank the production URL
  across all tables).

## [1.0.0] - 2026-07-06

First stable release. The add-on has run its documented `ddev pull pressable` /
`ddev push pressable` flow end-to-end against real Pressable sites, so the
pull/push interface and the `PRESSABLE_*` configuration variables are now
considered stable and covered by semver.

There are no functional changes from `v0.0.1`; this release graduates the add-on
from its initial `0.x` line to a supported `1.x` line.

## [0.0.1] - 2026-06-23

Initial release.

- `ddev pull pressable` / `ddev push pressable` provider running entirely over the
  site's existing SSH + WP-CLI + rsync access (no Pressable API, no plugin, no
  platform changes).
- Serialized-data-safe URL rewriting in both directions via `wp search-replace`.
- Selective-table pull via `PRESSABLE_DB_EXCLUDE_TABLES` (exclude) and
  `PRESSABLE_DB_TABLES` (import-only).
- Post-push `wp cache flush` on the remote; additive files push by default.
- Tag-driven (`release.yml`) and merge-driven (`release-on-merge.yml`) release
  automation.

[Unreleased]: https://github.com/pressable/ddev-pressable/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/pressable/ddev-pressable/releases/tag/v1.0.0
[0.0.1]: https://github.com/pressable/ddev-pressable/releases/tag/v0.0.1

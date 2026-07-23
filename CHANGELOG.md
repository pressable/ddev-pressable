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
  across all tables). The push hook likewise validates the local/remote URLs
  (non-empty, plain `http(s)`, shell-safe) and fails closed before overwriting
  the remote database.
- Subdirectory "WordPress in its own directory" split installs (`siteurl` a
  subpath of `home`, e.g. `home=https://example.com`,
  `siteurl=https://example.com/wp`) now round-trip through `ddev pull` /
  `ddev push`. Pull preserves the subdirectory on the local URL instead of
  flattening both bases onto one, and push reverses the mapping most-specific
  URL first. Only splits where `home` and `siteurl` are on *different hosts*
  remain lossy (DDEV forces a single local host); this is documented in the
  README "Safety" section.

### Changed

- Release automation now rolls this changelog when it tags: `release.rb` renames
  `[Unreleased]` to the new dated `[X.Y.Z]` section, opens a fresh `[Unreleased]`,
  updates the link refs, commits that, and pushes `main` + the tag together
  (recovering from a concurrent merge). Releases no longer ship with changes
  stranded under `[Unreleased]`.

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

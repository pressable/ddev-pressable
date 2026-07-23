[![tests](https://github.com/pressable/ddev-pressable/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/pressable/ddev-pressable/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/pressable/ddev-pressable)](https://github.com/pressable/ddev-pressable/commits)
[![release](https://img.shields.io/github/v/release/pressable/ddev-pressable)](https://github.com/pressable/ddev-pressable/releases/latest)

# DDEV Pressable Provider

A [DDEV](https://ddev.com/) provider add-on that syncs a [Pressable](https://pressable.com/)
WordPress site's database and uploads to and from your local DDEV project with
`ddev pull pressable` and `ddev push pressable`.

It runs entirely over the SSH and WP-CLI access your Pressable site already has.
There is no Pressable API token, no plugin, and nothing to enable on the
platform. Under the hood it uses SSH, WP-CLI (`wp db export` / `wp db import` /
`wp search-replace`), and `rsync`.

## What it does

| Direction | What moves | Command |
| --- | --- | --- |
| Pull | Remote DB + uploads down to local | `ddev pull pressable` |
| Push | Local DB + uploads up to a staging site | `ddev push pressable` |

Site URLs are rewritten automatically in both directions with `wp search-replace`
(serialized-data safe), so the local site renders at its `*.ddev.site` URL and a
pushed site renders at its own URL (one caveat for cross-host `home`/`siteurl`
splits — see [Safety](#safety)). Your theme and plugin code is **not** synced.
That comes from your own git repository, the way DDEV intends.

## Requirements

- DDEV `v1.24.0` or newer.
- A Pressable site, and the SSH key for it loaded locally.
- A WordPress DDEV project on your machine (`ddev config --project-type=wordpress`).

## Installation

```bash
ddev add-on get pressable/ddev-pressable
```

Then configure the project (below) and `ddev restart`. Commit the resulting
`.ddev` directory to version control so your team shares the same setup.

## Configuration

### 1. Set the site's SSH user

SSH/SFTP usernames on Pressable are **per-site**, not per-account, so one DDEV
project maps to one Pressable site with one username. Set it on the project
rather than committing it to the provider file:

```bash
ddev config --web-environment-add="PRESSABLE_SSH_USER=<site-ssh-user>"
ddev restart
```

Three ways to find the username:

1. **Control panel.** Open the site, then its SFTP/SSH section.
2. **API.** `GET /v1/sites/{id}/ftp` returns `username` and `sftp_domain`
   (Doorkeeper OAuth, scopes `ftp_read` / `sites_read`).
3. **MCP.** `list_site_ftp_accounts` returns the username;
   `get_ftp_account_details` returns the username and `sftp_domain`.

The SSH host defaults to `ssh.pressable.com`. Override it only if needed with
`PRESSABLE_SSH_HOST`.

### 2. Load your SSH key into DDEV

DDEV runs the sync inside its web container, which cannot reach the macOS
Keychain, so load your key into DDEV's ssh-agent once per `ddev` session:

```bash
ddev auth ssh
```

This is standard for every SSH-based DDEV provider.

## Usage

Direction and granularity are built into DDEV's pull/push flags:

| Want | Command |
| --- | --- |
| DB + files | `ddev pull pressable` |
| DB only | `ddev pull pressable --skip-files` |
| Files only | `ddev pull pressable --skip-db` |
| Download, do not import | `ddev pull pressable --skip-import` |

The same `--skip-db` / `--skip-files` flags work on `ddev push pressable`, so
`ddev push pressable --skip-files` pushes just the database to a staging site.

### Common workflows

1. **Pull production to local for development.** `ddev pull pressable` brings the
   database and uploads down; your code comes from git.
2. **Push local to staging for a client demo.** `ddev push pressable` to a staging
   site, both database and files, or `--skip-files` for the database alone.
3. **Database-only refresh.** `ddev pull pressable --skip-files` grabs the latest
   content without re-downloading a large media library.
4. **Files-only sync.** `ddev pull pressable --skip-db` pulls new media without
   clobbering your local database state.
5. **Selective-table pull.** Exclude bulky log/transient tables from a refresh,
   or (advanced) import only a chosen set (see below). `ddev pull` replaces the
   local database, so use `--skip-db` if you want to leave it untouched.
6. **Two-environment flow.** Pull content from production (read-only),
   develop locally, push to staging for review, and ship code through git, so the
   database and files never touch the live site.

### Selective tables (pull)

`ddev pull` **replaces** the local database (it drops the existing tables before
importing), so these variables control *what gets imported*, not what is kept.
To leave your local database untouched, use `--skip-db` instead.

The common, safe use is to **exclude** bulky log or transient tables while
keeping everything else:

```bash
# Import everything except these (e.g. skip bulky log/transient tables)
ddev config --web-environment-add="PRESSABLE_DB_EXCLUDE_TABLES=wp_actionscheduler_logs,wp_actionscheduler_actions"
```

`PRESSABLE_DB_TABLES` imports **only** the listed tables and drops the rest,
which is advanced: a WordPress site needs its core tables to boot, and the
post-pull URL rewrite only runs when `wp_options` is among the imported tables.
Include the full set you need:

```bash
ddev config --web-environment-add="PRESSABLE_DB_TABLES=wp_options,wp_posts,wp_postmeta,wp_users,wp_usermeta"
```

`PRESSABLE_DB_TABLES` takes precedence over the exclude list. Filtering is
whole-table; row- and field-level filtering is out of scope.

## Local version parity

Local tool versions live in your own `.ddev/config.yaml`, not in this add-on, so
there is nothing to maintain here per release. To match local to the site:

- **PHP.** Mirror the site's control-panel value with `php_version`.
- **Database.** Any recent MariaDB imports a `wp db export` dump fine. Pin
  `mariadb_version: "10.11"` only if you want exact parity.
- **Webserver.** `webserver_type: nginx-fpm`.
- **WordPress core.** This is your own codebase, not a config value. Pull moves
  the database and uploads only, never core.

## Safety

- **Push to staging, never to a live site.** A database push **overwrites** the
  remote database. On a live site that destroys everything created since the
  dump (orders, comments, form entries). `ddev push` always prompts for
  confirmation; do not bypass it with `-y`. Keep pushes pointed at staging sites.
- **Files push is additive by default.** It never deletes remote media. Mirror
  mode (deleting remote files missing locally) is opt-in only; edit the
  `files_push_command` rsync line in `.ddev/providers/pressable.yaml` to add
  `--delete`, and understand the risk first.
- **Object cache after a push.** A `ddev push` imports the database with a raw
  `wp db import`, which bypasses the hosting platform's object cache, so reads can be stale
  until the cache is flushed. The provider runs `wp cache flush` on the remote
  automatically after every push. If you need the rendered HTML fresh immediately
  (not just the data layer), also run a full-page or edge-cache purge, for example
  `wp edge-cache` against the remote.
- **Cross-host `home`/`siteurl` splits don't fully round-trip.** A subdirectory
  "WordPress in its own directory" split install — where `siteurl` is a subpath
  of `home` (e.g. `home=https://example.com`, `siteurl=https://example.com/wp`) —
  *does* round-trip: pull keeps the subdirectory on the local URL and push
  reverses it. But when `home` and `siteurl` live on **different hosts**
  (e.g. `home=https://example.com`, `siteurl=https://cdn.example.net`), DDEV
  forces a single local host, so both collapse locally and a later push can only
  restore the `home` option, not home-based content URLs. Same-host sites (the
  common Pressable case) round-trip losslessly.

## How it works

- **Transport.** `ssh <PRESSABLE_SSH_USER>@ssh.pressable.com`, where `wp` is on
  the PATH and auto-locates the install from the login home directory.
- **Pull.** `wp db export -` streams a dump over SSH into
  `.ddev/.downloads/db.sql.gz`; `rsync` brings `htdocs/wp-content/uploads/` into
  `.ddev/.downloads/files/`. DDEV imports both, then a `post-import-db` hook
  rewrites the production URL to your local DDEV URL.
- **Push.** DDEV exports the local database; the provider captures the remote URL,
  imports the local dump over SSH, rewrites URLs back to the remote URL with
  `wp search-replace`, runs `wp cache flush`, and `rsync`s uploads up.

## Releasing (maintainers)

This add-on is versioned by git tags: `ddev add-on get pressable/ddev-pressable`
installs the latest GitHub release.

**Automatic (default).** Every merge to `main` cuts a release once the `tests`
workflow passes —
[`.github/workflows/release-on-merge.yml`](.github/workflows/release-on-merge.yml)
computes the next version, tags it, and publishes the release.

- **Bump level** defaults to a patch (`1.2.3 -> 1.2.4`). For a larger bump, add a
  `release:minor` or `release:major` label to the PR, or put `#minor` / `#major`
  in the merge commit message.
- **Skip** a release for a given merge with a `release:skip` label or
  `[skip release]` in the commit message.

**Manual (out-of-band).** To cut a release without a merge, run the Ruby helper
locally; pushing the tag triggers
[`.github/workflows/release.yml`](.github/workflows/release.yml):

```bash
.github/scripts/release.rb            # patch bump (default), e.g. 1.2.3 -> 1.2.4
.github/scripts/release.rb minor      # 1.2.3 -> 1.3.0
.github/scripts/release.rb major      # 1.2.3 -> 2.0.0
.github/scripts/release.rb 1.5.0      # explicit version
.github/scripts/release.rb --dry-run minor
```

It validates that the tree is clean and on `main`, computes the next version from
the latest tag, then creates and pushes the annotated tag.

## Credits

Maintained by [Pressable](https://pressable.com/). Scaffolded from
[`ddev/ddev-addon-template`](https://github.com/ddev/ddev-addon-template).
Licensed under [Apache 2.0](LICENSE).

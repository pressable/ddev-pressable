#!/usr/bin/env ruby
# frozen_string_literal: true

# Cut a release for the ddev-pressable add-on.
#
# DDEV add-ons are versioned by git tags: `ddev add-on get pressable/ddev-pressable`
# installs the latest GitHub release, which .github/workflows/release.yml publishes
# automatically when a `vX.Y.Z` tag is pushed. This helper computes the next
# version from the latest tag, rolls CHANGELOG.md's `[Unreleased]` section into a
# dated `[X.Y.Z]` section, commits that, then creates and pushes the annotated tag
# (together with main, so the tagged commit carries the rolled changelog).
#
# Usage (run from the repo root):
#   .github/scripts/release.rb            # patch bump (default): 1.2.3 -> 1.2.4
#   .github/scripts/release.rb patch      # 1.2.3 -> 1.2.4
#   .github/scripts/release.rb minor      # 1.2.3 -> 1.3.0
#   .github/scripts/release.rb major      # 1.2.3 -> 2.0.0
#   .github/scripts/release.rb 1.5.0      # explicit version
#   .github/scripts/release.rb --dry-run minor

require "open3"

DEFAULT_BUMP = "patch"
REMOTE = "origin"
MAIN_BRANCH = "main"

# Run a command, aborting with its output on failure.
def run(*cmd)
  out, status = Open3.capture2e(*cmd)
  abort "command failed: #{cmd.join(' ')}\n#{out}" unless status.success?
  out.strip
end

# Run a command, returning its (stripped) output and ignoring a non-zero exit.
def capture(*cmd)
  out, = Open3.capture2e(*cmd)
  out.strip
end

# Roll CHANGELOG.md for a release: rename the "## [Unreleased]" section to
# "## [version] - date", insert a fresh empty "## [Unreleased]" above it, repoint
# the [Unreleased] compare link to the new version, and add a [version] release
# link (matching the existing /releases/tag/ style). Returns [new_content,
# rolled?]. When there is no [Unreleased] section, or it is empty, returns the
# content unchanged with rolled? = false so the caller tags without a changelog
# commit rather than failing the release.
def roll_changelog(content, version, date)
  return [content, false] unless content =~ /^## \[Unreleased\][ \t]*$/

  body = content[/^## \[Unreleased\][ \t]*\n(.*?)(?=^## |\z)/m, 1] || ""
  return [content, false] if body.strip.empty?

  base = content[%r{^\[[0-9][0-9.]*\]:\s+(https?://\S+?)/releases/tag/}, 1]
  base ||= (slug = capture("git", "remote", "get-url", REMOTE)[%r{github\.com[:/](.+?)(?:\.git)?\z}, 1]) &&
           "https://github.com/#{slug}"
  abort "Cannot determine repository URL for CHANGELOG links." unless base

  out = content.sub(/^## \[Unreleased\][ \t]*$/, "## [Unreleased]\n\n## [#{version}] - #{date}")

  release_ref = "[#{version}]: #{base}/releases/tag/v#{version}"
  if out =~ /^\[Unreleased\]:.*$/
    out = out.sub(/^\[Unreleased\]:.*$/, "[Unreleased]: #{base}/compare/v#{version}...HEAD\n#{release_ref}")
  elsif out =~ /^\[[^\]]+\]:\s+https?:/
    out = out.sub(/^(\[[^\]]+\]:\s+https?:.*)$/, "#{release_ref}\n\\1")
  else
    out = "#{out.rstrip}\n\n#{release_ref}\n"
  end
  [out, true]
end

# Push MAIN_BRANCH + tag atomically. --atomic guarantees the tag never lands
# without its main commit (and vice versa), so a release is never half-published.
#
# If a concurrent merge advanced main between our checkout and the push, the push
# is rejected as a non-fast-forward. We deliberately do NOT rebase the release
# commit onto that newer head and retag: that head may still be under test (or
# later fail), and release-on-merge only cuts a release once `tests` passes — so
# rebasing onto it would risk publishing an unverified tree. Instead we abort.
# No untested tree is ever published; the next tested commit's own release run
# rolls these still-`[Unreleased]` entries into its release. (A re-run of THIS
# commit is not a no-op — no tag was pushed, so it would just re-lose the race and
# re-abort; the next tested descendant is what proceeds.)
#
# Known limitation: the deferred commit's own bump level is not carried forward,
# so a `release:major`/`minor` commit that loses this race can downgrade to the
# next commit's bump. Rare, and recoverable with `release.rb major|minor` by hand.
def push_release(tag)
  out, status = Open3.capture2e("git", "push", "--atomic", REMOTE, MAIN_BRANCH, tag)
  return if status.success?

  abort "Push of #{MAIN_BRANCH} + #{tag} was rejected (main likely advanced during the " \
        "release job). Refusing to rebase onto an unverified head — deferring these changes " \
        "to the next tested commit's release rather than publishing an untested tree.\n#{out}"
end

if $PROGRAM_NAME == __FILE__
  dry_run = !ARGV.delete("--dry-run").nil?
  arg = ARGV.shift || DEFAULT_BUMP

  branch = run("git", "rev-parse", "--abbrev-ref", "HEAD")
  abort "Refusing to release from '#{branch}'; switch to '#{MAIN_BRANCH}' first." unless branch == MAIN_BRANCH

  abort "Working tree is dirty; commit or stash changes first." unless capture("git", "status", "--porcelain").empty?

  run("git", "fetch", "--tags", REMOTE)
  local = run("git", "rev-parse", "@")
  # `--verify --quiet` prints nothing and exits non-zero when there is no upstream
  # (e.g. CI's `git checkout -B main`), so the sync check is skipped rather than
  # tripping on the error text. Without it the check aborts whenever no upstream
  # tracking is configured.
  upstream = capture("git", "rev-parse", "--verify", "--quiet", "@{u}")
  abort "Local #{MAIN_BRANCH} is out of sync with #{REMOTE}; pull/push first." unless upstream.empty? || local == upstream

  # Pick the highest STRICT semver tag, ignoring any malformed `v*` tags
  # (e.g. `v1`, `vfoo`) that would otherwise crash the major.minor.patch split.
  latest = capture("git", "tag", "--list", "v*", "--sort=-v:refname")
           .lines.map(&:strip)
           .find { |t| t.match?(/\Av\d+\.\d+\.\d+\z/) }
  current = latest ? latest.sub(/\Av/, "") : "0.0.0"
  major, minor, patch = current.split(".").map(&:to_i)

  next_version =
    case arg
    when "major" then "#{major + 1}.0.0"
    when "minor" then "#{major}.#{minor + 1}.0"
    when "patch" then "#{major}.#{minor}.#{patch + 1}"
    when /\Av?\d+\.\d+\.\d+\z/ then arg.sub(/\Av/, "")
    else abort "Unknown argument '#{arg}'. Use major | minor | patch, or an explicit X.Y.Z."
    end

  tag = "v#{next_version}"
  abort "Tag #{tag} already exists." unless capture("git", "tag", "--list", tag).empty?

  puts "Current version: v#{current}"
  puts "Next version:    #{tag}"

  date = Time.now.utc.strftime("%Y-%m-%d")
  changelog_path = File.join(run("git", "rev-parse", "--show-toplevel"), "CHANGELOG.md")
  rolled = false
  new_changelog = nil
  if File.exist?(changelog_path)
    new_changelog, rolled = roll_changelog(File.read(changelog_path, encoding: "UTF-8"), next_version, date)
  end

  if dry_run
    puts(if rolled
           "[dry-run] Would roll CHANGELOG.md: [Unreleased] -> [#{next_version}] - #{date}, reset [Unreleased], add link refs."
         else
           "[dry-run] No [Unreleased] entries to roll; CHANGELOG.md left as-is."
         end)
    puts "[dry-run] Would #{'commit the changelog, ' if rolled}create tag #{tag}, and push " \
         "#{rolled ? "#{MAIN_BRANCH} + #{tag}" : tag} to #{REMOTE}."
    exit 0
  end

  if rolled
    File.write(changelog_path, new_changelog, encoding: "UTF-8")
    run("git", "add", "CHANGELOG.md")
    run("git", "commit", "-m", "Release #{tag}")
  end

  run("git", "tag", "-a", tag, "-m", "Release #{tag}")

  # When we rolled the changelog, the tag points at that new commit, so main and
  # the tag must ship together — push_release does that atomically, and defers on a
  # concurrent-merge race rather than rebasing (see its comment). With nothing to
  # roll, main is unchanged and already on the remote — push only the tag.
  if rolled
    push_release(tag)
  else
    run("git", "push", REMOTE, tag)
  end

  puts "Pushed #{tag}#{" and #{MAIN_BRANCH}" if rolled}. The release workflow will publish the GitHub release."
  slug = capture("git", "remote", "get-url", REMOTE)[%r{github\.com[:/](.+?)(?:\.git)?\z}, 1]
  puts "Watch: https://github.com/#{slug}/actions" if slug
end

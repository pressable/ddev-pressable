#!/usr/bin/env ruby
# frozen_string_literal: true

# Cut a release for the ddev-pressable add-on.
#
# DDEV add-ons are versioned by git tags: `ddev add-on get pressable/ddev-pressable`
# installs the latest GitHub release, which .github/workflows/release.yml publishes
# automatically when a `vX.Y.Z` tag is pushed. This helper computes the next
# version from the latest tag, then creates and pushes the annotated tag.
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

if dry_run
  puts "[dry-run] Would create and push annotated tag #{tag} to #{REMOTE}."
  exit 0
end

run("git", "tag", "-a", tag, "-m", "Release #{tag}")
run("git", "push", REMOTE, tag)

puts "Pushed #{tag}. The release workflow will publish the GitHub release."
slug = capture("git", "remote", "get-url", REMOTE)[%r{github\.com[:/](.+?)(?:\.git)?\z}, 1]
puts "Watch: https://github.com/#{slug}/actions" if slug

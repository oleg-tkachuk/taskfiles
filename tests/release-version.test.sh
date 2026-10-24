#!/usr/bin/env bash
# release: an untagged build's base comes from the latest tag, one patch up,
# so it sorts above the release it follows; VERSION_BASE still sets it outright.
source "$(dirname "$0")/lib.sh"

consumer release release
repo() { git -C "$CONSUMER" "$@"; }
repo init -q
# Every write below goes to this repository and no other.
[ "$(repo rev-parse --absolute-git-dir)" = "$(cd "$CONSUMER" && pwd -P)/.git" ] \
  || { echo "✖ the fixture repository is not the consumer's own" >&2; exit 1; }
repo config user.email test@example.invalid
repo config user.name test
printf '.task/\n' > "$CONSUMER/.gitignore"
commit() { printf '%s\n' "$1" >> "$CONSUMER/log"; repo add -A; repo commit -qm "$1"; }
commit first

# expect_version <glob> <case name> [task args...]
expect_version() {
  want=$1 name=$2; shift 2
  run_task release:version "$@"
  got=$(cat "$OUT")
  # shellcheck disable=SC2254 # the glob is the assertion
  case "$got" in
    $want) pass "$name" ;;
    *) fail "$name: want $want, got $got" ;;
  esac
}

expect_version '0.1.0-dev.*.g*' "no tag: the first base"

repo tag v1.2.0
expect_version '1.2.0' "on a tag, clean: the tag"

printf 'wip\n' >> "$CONSUMER/log"
expect_version '1.2.1-dev.*.dirty.*.g*' "on a tag, dirty: above the tag"
repo checkout -q -- log

commit second
expect_version '1.2.1-dev.*.g*' "after a tag: one patch above it"
expect_version '2.0.0-dev.*.g*' "VERSION_BASE sets the base outright" VERSION_BASE=2.0.0
expect_version '7.7.7' "APP_VERSION pins the version" APP_VERSION=7.7.7

repo tag api/9.9.9
expect_version '1.2.1-dev.*.g*' "an excluded tag namespace is not a base" 'VERSION_TAG_EXCLUDE=api/*'

commit third
repo tag v1.3.0-rc.1
commit fourth
expect_version '1.3.1-dev.*.g*' "after a pre-release tag: one patch above its core"

repo tag release-5
commit fifth
expect_version '1.3.1-dev.*.g*' "a tag that is not a version is passed over"

repo tag stable
expect_version '1.3.1-dev.*.g*' "a tag on HEAD that is not a version does not become one"

repo tag v1.4.0
expect_version '1.4.0' "a version tag beside a tag that is not one is still the version"

finish

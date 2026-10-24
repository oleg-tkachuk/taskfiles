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
expect_version '1.3.0-rc.1.dev.*.g*' "after a pre-release tag: that pre-release, extended"

repo tag release-5
commit fifth
expect_version '1.3.0-rc.1.dev.*.g*' "a tag that is not a version is passed over"

repo tag stable
expect_version '1.3.0-rc.1.dev.*.g*' "a tag on HEAD that is not a version does not become one"

repo tag v1.4.0
expect_version '1.4.0' "a version tag beside a tag that is not one is still the version"

# ─── ordering, by SemVer precedence ──────────────────────────────────────────
# A resolver such as ArgoCD's `>=0.0.0-0` serves the highest version, so what
# matters is where a build sorts, not what it reads like.
#
# The comparator first, against the precedence chain SemVer §11 itself gives,
# both ways round, and with build metadata ignored.
chain=(1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0 1.0.1 1.1.0 2.0.0)
for ((i = 0; i < ${#chain[@]} - 1; i++)); do
  expect_before "${chain[i]}" "${chain[i + 1]}" "semver: ${chain[i]} < ${chain[i + 1]}"
  if [ "$(semver_cmp "${chain[i + 1]}" "${chain[i]}")" = 1 ]; then
    pass "semver: ${chain[i + 1]} > ${chain[i]}"
  else
    fail "semver: ${chain[i + 1]} > ${chain[i]}"
  fi
done
if [ "$(semver_cmp 1.0.0+a 1.0.0+b)" = 0 ]; then pass "semver: build metadata does not order"; else fail "semver: build metadata does not order"; fi

# Then the builds, on a fresh history.
rm -rf "$CONSUMER/.git"
repo init -q
repo config user.email test@example.invalid
repo config user.name test
commit candidate
version() { run_task release:version; cat "$OUT"; }

repo tag v1.2.0-rc.1
expect_version '1.2.0-rc.1' "on a pre-release tag, clean: the tag"
commit after-candidate
clean=$(version)
expect_before 1.2.0-rc.1 "$clean" "after v1.2.0-rc.1: a build sorts above the candidate it follows"
expect_before "$clean" 1.2.0-rc.2 "after v1.2.0-rc.1: a build sorts below the next candidate"
expect_before "$clean" 1.2.0 "after v1.2.0-rc.1: a build sorts below the release the candidate is for"

printf 'wip\n' >> "$CONSUMER/log"
dirty=$(version)
repo checkout -q -- log
expect_before "$dirty" "$clean" "after v1.2.0-rc.1: the clean build of a commit outranks its dirty one"
expect_before 1.2.0-rc.1 "$dirty" "after v1.2.0-rc.1: a dirty build still sorts above the candidate"
expect_version '2.0.0-dev.*.g*' "after a pre-release tag: VERSION_BASE still sets the base" VERSION_BASE=2.0.0
expect_version '7.7.7' "after a pre-release tag: APP_VERSION still pins the version" APP_VERSION=7.7.7

commit release
repo tag v1.2.0
commit after-release
clean=$(version)
expect_version '1.2.1-dev.*.g*' "after a final tag: one patch up, as before"
expect_before 1.2.0 "$clean" "after v1.2.0: a build sorts above the release"
expect_before "$clean" 1.2.1 "after v1.2.0: a build sorts below the next patch"

printf 'wip\n' >> "$CONSUMER/log"
dirty=$(version)
repo checkout -q -- log
expect_before "$dirty" "$clean" "after v1.2.0: the clean build of a commit outranks its dirty one"

# ─── BUILD_KIND ──────────────────────────────────────────────────────────────
# What kind of build a version is, said outright in the info file, so nothing
# downstream has to recognise it from the version's shape. Written under
# .task/, which the fixture ignores, so writing it dirties nothing.
# expect_kind <kind> <case name> [task args...]
expect_kind() {
  want=$1 name=$2; shift 2
  run_task release:metadata INFO_ENV_FILE=.task/info.env "$@"
  if grep -qx "BUILD_KIND=$want" "$CONSUMER/.task/info.env"; then pass "$name"; else fail "$name: want BUILD_KIND=$want"; fi
}

expect_kind dev "kind: an untagged build is dev"
repo tag v1.2.1
expect_kind release "kind: an exact tag on a clean tree is a release"
printf 'wip\n' >> "$CONSUMER/log"
expect_kind dev "kind: a tagged commit with a dirty tree is dev"
repo checkout -q -- log
expect_kind pinned "kind: APP_VERSION is pinned, not a release git vouches for" APP_VERSION=9.9.9

finish

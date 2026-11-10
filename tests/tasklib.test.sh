#!/usr/bin/env bash
# tasklib: bump moves every pin and every lock together, lock replaces a lock
# only once its downloads succeeded and retries one that lost a race, check
# refuses pins that disagree or a Taskfile its lock does not load — and the
# Renovate preset matches the Taskfile names the module does.
source "$(dirname "$0")/lib.sh"

# What a pin of the library looks like in a consumer, less the ref.
readonly PIN='https://github.com/acme/taskfiles.git//%s?ref='
readonly OLD=v1.0.0
readonly NEW=v2.0.0
# Where the module keeps a directory's lock, and the fake's file for a ref.
readonly LOCK=.task/remote
lock_file() { printf '%s/git.fake.%s.checksum' "$LOCK" "$1"; }

# The module runs `task` once per Taskfile, always with --remote-cache-dir.
# Those calls are faked; any other is the test's own and goes to the real one.
#
# --download writes a module and its checksum per ref the Taskfile pins, after
# failing FAIL_TIMES times; --offline succeeds when every module is there and,
# as Task does under -v, names each lock file it reads — unless FAKE_SILENT is
# set. Each faked call records whether git's GIT_DIR reached it.
REAL_TASK=$(command -v task)
export REAL_TASK
export FAILS="$WORK/fails"
# shellcheck disable=SC2016 # the shim's own variables, written literally
shim task '
case " $* " in *" --remote-cache-dir "*) ;; *) exec "$REAL_TASK" "$@" ;; esac
printf "GIT_DIR=%s\n" "${GIT_DIR-unset}" >> "$CALLS"
mode="" file="" cache=""
while [ $# -gt 0 ]; do
  case "$1" in
    -t) file=$2; shift ;;
    --remote-cache-dir) cache=$2; shift ;;
    --download) mode=download ;;
    --offline) mode=offline ;;
  esac
  shift
done
refs=$(sed -n "s/.*taskfiles\.git[^?]*?ref=\([^'"'"' ]*\).*/\1/p" "$file" | sort -u)
if [ "$mode" = download ]; then
  left=$(cat "$FAILS" 2>/dev/null || printf 0)
  if [ "$left" -gt 0 ]; then printf "%s" $((left - 1)) > "$FAILS"; echo "failed to clone repository" >&2; exit 1; fi
  for r in $refs; do
    mkdir -p "$cache/remote"
    printf "module at %s\n" "$r" > "$cache/remote/git.fake.$r.yaml"
    shasum -a 256 "$cache/remote/git.fake.$r.yaml" | awk "{ printf \"%s\", \$1 }" > "$cache/remote/git.fake.$r.checksum"
  done
  exit 0
fi
for r in $refs; do
  [ -f "$cache/remote/git.fake.$r.yaml" ] || { echo "not found in the cache" >&2; exit 1; }
  [ -n "${FAKE_SILENT:-}" ] || printf "checking cache for \"https://example.invalid//m?ref=%s\" in \"%s/%s/remote/git.fake.%s.yaml\"\n" "$r" "$PWD" "$cache" "$r" >&2
done'

# What a comment showing how to pin looks like: not a pin.
readonly EXAMPLE="  # TASKLIB: '$PIN<tag>'"

# pinned <path> <ref> — a Taskfile at <path> pinning the library at <ref>.
pinned() {
  mkdir -p "$(dirname "$CONSUMER/$1")"
  cat > "$CONSUMER/$1" <<YAML
version: "3"
vars:
$EXAMPLE
  TASKLIB: '$PIN$2'
  OTHER: 'https://github.com/acme/other.git//%s?ref=v9.9.9'
YAML
}

# root [include vars] — the root Taskfile: the module, and a pin of its own.
root() {
  consumer tasklib tasklib "${1:-"{}"}"
  printf "vars:\n  TASKLIB: '%s'\n" "$PIN$OLD" >> "$CONSUMER/Taskfile.yaml"
}

fail_downloads() { printf '%s' "$1" > "$FAILS"; }

expect_file() { if [ -e "$CONSUMER/$1" ]; then pass "$2"; else fail "$2: $1 is not there"; fi; }
refute_file() { if [ -e "$CONSUMER/$1" ]; then fail "$2: $1 is there"; else pass "$2"; fi; }
expect_pin() { if grep -qF -- "$PIN$2" "$CONSUMER/$1"; then pass "$3"; else fail "$3: $1 does not pin $2"; fi; }

git init -q "$CONSUMER"
root
pinned Taskfile.dev.yaml "$OLD"
pinned api/Taskfile.yaml "$OLD"
# An old lock in both directories, for bump to replace.
for d in . api; do
  mkdir -p "$CONSUMER/$d/$LOCK"
  : > "$CONSUMER/$d/$(lock_file "$OLD")"
done

# ─── bump ────────────────────────────────────────────────────────────────────
run_task tasklib:bump "VERSION=$NEW"
expect_status ok "bump: runs"
expect_pin Taskfile.yaml "$NEW" "bump: moves the root pin"
expect_pin Taskfile.dev.yaml "$NEW" "bump: moves a second entry point's pin"
expect_pin api/Taskfile.yaml "$NEW" "bump: moves a component's pin"
if grep -qxF -- "$EXAMPLE" "$CONSUMER/api/Taskfile.yaml"; then pass "bump: leaves a pin written in a comment alone"; else fail "bump: rewrote a pin written in a comment"; fi
if grep -qF 'other.git//%s?ref=v9.9.9' "$CONSUMER/api/Taskfile.yaml"; then pass "bump: leaves another library's pin alone"; else fail "bump: rewrote another library's pin"; fi
expect_file "$(lock_file "$NEW")" "bump: locks the root at the new ref"
expect_file "api/$(lock_file "$NEW")" "bump: locks a component at the new ref"
refute_file "$(lock_file "$OLD")" "bump: drops the lock the old ref left"
refute_file "api/$(lock_file "$OLD")" "bump: drops a component's old lock"

for bad in "" "v1&x" "v1 x"; do
  run_task tasklib:bump "VERSION=$bad"
  expect_status fail "bump: VERSION '$bad' is refused"
done
expect_pin Taskfile.yaml "$NEW" "bump: a refused VERSION rewrites nothing"

# ─── check ───────────────────────────────────────────────────────────────────
reset_calls
run_task tasklib:check
expect_status ok "check: agreeing pins with their locks pass"
expect_output "$NEW pinned by 3 Taskfile(s)" "check: names the ref and how many pin it"
expect_call "-v -t Taskfile.yaml --offline" "check: asks Task which lock files it reads"

# The lock itself: a module with no checksum, one that changed after it was
# fetched, and a file no Taskfile reads are each refused.
module="$CONSUMER/api/$LOCK/git.fake.$NEW"
mv "$module.checksum" "$WORK/held.checksum"
run_task tasklib:check
expect_status fail "check: a module with no .checksum beside it is refused"
expect_output "git.fake.$NEW.yaml has no .checksum beside it" "check: names the module with no checksum"
mv "$WORK/held.checksum" "$module.checksum"

printf 'tampered\n' >> "$module.yaml"
run_task tasklib:check
expect_status fail "check: a module that changed after it was fetched is refused"
expect_output "git.fake.$NEW.yaml is not what its .checksum records" "check: names the changed module"
printf 'module at %s\n' "$NEW" > "$module.yaml"

: > "$CONSUMER/api/$(lock_file "$OLD")"
run_task tasklib:check
expect_status fail "check: a lock file no Taskfile reads is refused"
expect_output "git.fake.$OLD.checksum is read by no Taskfile in api" "check: names the file an earlier ref left"
rm -f "$CONSUMER/api/$(lock_file "$OLD")"

# A Task that does not name what it reads: said, not guessed.
: > "$CONSUMER/api/$(lock_file "$OLD")"
FAKE_SILENT=1 run_task tasklib:check
expect_status ok "check: passes when Task does not say which files it read"
expect_output "files left by earlier refs are not checked" "check: says the leftover check was skipped"
rm -f "$CONSUMER/api/$(lock_file "$OLD")"
run_task tasklib:check
expect_status ok "check: a restored lock passes again"
refute_output "<tag>" "check: a pin written in a comment is not a pin"
expect_call "--offline --remote-cache-dir .task" "check: loads each Taskfile offline, from the lock's directory"
refute_call "--download" "check: downloads nothing"

pinned api/Taskfile.yaml "$OLD"
run_task tasklib:check
expect_status fail "check: pins that disagree are refused"
expect_output "$OLD	api/Taskfile.yaml" "check: names the Taskfile on the other ref"

pinned api/Taskfile.yaml "$NEW"
rm -rf "$CONSUMER/api/.task"
run_task tasklib:check
expect_status fail "check: a Taskfile with no lock is refused"
expect_output "api/Taskfile.yaml does not load from its lock" "check: names the Taskfile that does not load"

# ─── lock ────────────────────────────────────────────────────────────────────
reset_calls
run_task tasklib:lock
expect_status ok "lock: runs"
expect_file "api/$(lock_file "$NEW")" "lock: writes a lock that was missing"
expect_call "-t Taskfile.dev.yaml --yes --offline=false --download --timeout 1m" "lock: downloads each entry point, whatever offline default is set, with its own timeout"
refute_call "GIT_DIR=/" "lock: no GIT_DIR reaches the download"

reset_calls
GIT_DIR="$CONSUMER/.git" run_task tasklib:lock
expect_status ok "lock: runs under a git hook's environment"
expect_call "GIT_DIR=unset" "lock: clears a hook's GIT_DIR before the download"
refute_call "GIT_DIR=/" "lock: a hook's GIT_DIR reaches no download"

fail_downloads 1
run_task tasklib:lock
expect_status ok "lock: a download that fails once is tried again"
expect_output "trying again" "lock: says it is trying again"

: > "$CONSUMER/$(lock_file "$OLD")"
fail_downloads 99
run_task tasklib:lock
expect_status fail "lock: a download that keeps failing fails the task"
expect_output "its lock is unchanged" "lock: says the lock was left alone"
expect_output "failed to clone repository" "lock: shows what Task said"
expect_file "$(lock_file "$OLD")" "lock: a failed download leaves the old lock in place"
fail_downloads 0

run_task tasklib:lock TASKLIB_RETRIES=0
expect_status fail "lock: TASKLIB_RETRIES=0 is refused"

# A directory whose Taskfile has no remote include keeps no lock.
mkdir -p "$CONSUMER/docs/$LOCK"
printf 'version: "3"\n' > "$CONSUMER/docs/Taskfile.yaml"
: > "$CONSUMER/docs/$(lock_file "$OLD")"
run_task tasklib:lock
expect_status ok "lock: runs over a Taskfile with no remote include"
refute_file "docs/$LOCK" "lock: removes a lock no include needs"

# TASKLIB_FILES narrows the run to the Taskfiles it names.
root '{ TASKLIB_FILES: [api/Taskfile.yaml] }'
rm -rf "$CONSUMER/.task" "$CONSUMER/api/.task"
run_task tasklib:lock
expect_status ok "lock: runs over TASKLIB_FILES"
expect_file "api/$(lock_file "$NEW")" "lock: locks a Taskfile TASKLIB_FILES names"
refute_file "$LOCK" "lock: leaves a Taskfile TASKLIB_FILES does not name"

# ─── a gate that would check nothing ─────────────────────────────────────────
rm -rf "$CONSUMER/api" "$CONSUMER/docs" "$CONSUMER/Taskfile.dev.yaml"
consumer tasklib tasklib
run_task tasklib:check
expect_status fail "check: no pin anywhere is refused"
expect_output "this gate checks nothing" "check: says it would check nothing"
run_task tasklib:bump "VERSION=$NEW"
expect_status fail "bump: no pin anywhere is refused"

# ─── the Renovate preset names the same files and reads the same pin ─────────
PRESET="$LIB_ROOT/renovate/tasklib.json"
name_re=$(yq -r '.vars._TL_NAME_RE' "$LIB_ROOT/tasklib/Taskfile.yaml")
preset_re=$(yq -p json -o tsv '.customManagers[0].managerFilePatterns[0] | sub("^/"; "") | sub("/$"; "")' "$PRESET")
match_re=$(yq -p json -o tsv '.customManagers[0].matchStrings[0]' "$PRESET")

matches() { NAME=$1 RE=$2 perl -e 'exit($ENV{NAME} =~ /$ENV{RE}/ ? 0 : 1)'; }
for name in Taskfile.yaml taskfile.yml Taskfile.dev.yaml api/Taskfile.yaml a/b/Taskfile.dist.yml; do
  if matches "$name" "$name_re" && matches "$name" "$preset_re"; then pass "preset: $name is a Taskfile to both"; else fail "preset: the module and the preset disagree on $name"; fi
done
for name in Taskfile.yaml.bak tasks/build.yaml MyTaskfile.yaml .github/workflows/ci.yml; do
  if matches "$name" "$name_re" || matches "$name" "$preset_re"; then fail "preset: $name is read as a Taskfile"; else pass "preset: $name is a Taskfile to neither"; fi
done

got=$(LINE="  TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git//%s?ref=v14.3.2'" RE=$match_re perl -e 'print "$+{depName} $+{currentValue}" if $ENV{LINE} =~ /$ENV{RE}/')
if [ "$got" = "oleg-tkachuk/taskfiles v14.3.2" ]; then pass "preset: reads the repository and the ref from a pin"; else fail "preset: read '$got' from a pin"; fi
got=$(LINE="go: { taskfile: 'https://github.com/acme/other.git//go?ref=v1.0.0' }" RE=$match_re perl -e 'print "matched" if $ENV{LINE} =~ /$ENV{RE}/')
if [ -z "$got" ]; then pass "preset: another library's pin is not this one's"; else fail "preset: matched another library's pin"; fi

finish

#!/usr/bin/env bash
# packer: a build is validated before anybody is asked about it, and a name in
# ONLY that matches no build is refused where the CLI would build the rest.
source "$(dirname "$0")/lib.sh"

# Answers as the CLI does, by subcommand. A name that matches no build is a
# warning beside a pass, never a failure: an -only or an -except holding
# "no-such" gets its own, on the stream FAKE_WARN_FD names. FAKE_SILENT is a
# CLI that words both warnings otherwise, FAKE_SILENT_EXCEPT one that words
# only the second so. Every call also logs the directory it ran in.
shim packer '
printf "in %s\n" "${PWD##*/}" >> "$CALLS"
case " $* " in
  *" fmt "*) exit "${FAKE_FMT:-0}" ;;
  *" init "*) printf "%s\n" "Installed plugin"; exit "${FAKE_INIT:-0}" ;;
  *" inspect "*) printf "%s\n" "> builds:"; exit "${FAKE_INSPECT:-0}" ;;
  *" validate "*)
    for arg in "$@"; do
      case "${FAKE_SILENT:-0}${FAKE_SILENT_EXCEPT:-0} $arg" in
        "0"?" -only="*no-such*)
          printf "%s\n" "Warning: an '\''only'\'' option was passed, but not all matches were found for the given build." >&"${FAKE_WARN_FD:-1}" ;;
        "00 -except="*no-such*)
          printf "%s\n" "Warning: an '\''except'\'' option was passed, but did not match any build." >&"${FAKE_WARN_FD:-1}" ;;
        *" -only="*no-such* | *" -except="*no-such*) printf "%s\n" "Warning: no build is named so." ;;
      esac
    done
    printf "%s\n" "The configuration is valid."; exit "${FAKE_VALIDATE:-0}" ;;
  *" build "*) printf "%s\n" "==> Builds finished."; exit "${FAKE_BUILD:-0}" ;;
esac'

# called_before <a> <b> <case name> — the first call holding a came before the
# first holding b.
called_before() {
  if A=$1 B=$2 awk 'index($0, ENVIRON["A"]) && !a { a = NR } index($0, ENVIRON["B"]) && !b { b = NR } END { exit !(a && b && a < b) }' "$CALLS"; then
    pass "$3"
  else
    fail "$3: '$1' was not called before '$2'"; quoted '    > ' "$CALLS"
  fi
}

# expect_line <line> <case name> — some shim call is exactly that line.
expect_line() {
  if has_line "$CALLS" "$1"; then pass "$2"; else fail "$2: no call that is '$1'"; quoted '    > ' "$CALLS"; fi
}

# expect_ran_in <call> <directory> <case name> — the call that is exactly
# <call> ran in a directory of that name: the shim logs it on the next line.
expect_ran_in() {
  if CALL=$1 DIR="in $2" awk '$0 == ENVIRON["CALL"] { getline; if ($0 == ENVIRON["DIR"]) found = 1 } END { exit !found }' "$CALLS"; then
    pass "$3"
  else
    fail "$3: '$1' did not run in $2"; quoted '    > ' "$CALLS"
  fi
}

# The name the module asks the CLI about to learn whether it would say so.
SENTINEL=taskfiles-no-such-build

IMAGES="$CONSUMER/images"
mkdir -p "$IMAGES"
: > "$IMAGES/base.pkr.hcl"
# A file a glob in ONLY would become, were it left to the shell.
: > "$IMAGES/web.one"
consumer pk packer '{ PACKER_DIR: images }'

# ─── fmt ─────────────────────────────────────────────────────────────────────
reset_calls
run_task pk:fmt
expect_status ok "fmt: files in the canonical format pass"
expect_line "packer fmt -check -recursive ." "fmt: checks every file, and rewrites none"
expect_ran_in "packer fmt -check -recursive ." images "fmt: under PACKER_DIR"

FAKE_FMT=3 run_task pk:fmt
expect_status fail "fmt: a file the CLI lists fails"
expect_output "not formatted" "fmt: and is told from a failure to read one"

FAKE_FMT=1 run_task pk:fmt
expect_status fail "fmt: a file the CLI could not read fails"
expect_output "did not complete" "fmt: as an error, not as formatting"
refute_output "not formatted" "fmt: which it says nothing about"

consumer pk packer '{ PACKER_DIR: no-such }'
reset_calls
run_task pk:fmt
expect_status fail "fmt: a PACKER_DIR that is not a directory is refused"
expect_output "not a directory" "fmt: and named as the reason"
refute_call "packer" "fmt: and nothing runs"
consumer pk packer '{ PACKER_DIR: images }'

# ─── init ────────────────────────────────────────────────────────────────────
reset_calls
run_task pk:init
expect_status ok "init: installs what the template requires"
expect_line "packer init ." "init: for the template in PACKER_DIR"
expect_ran_in "packer init ." images "init: from PACKER_DIR"

FAKE_INIT=1 run_task pk:init
expect_status fail "init: a plugin that could not be installed fails"

consumer pk packer '{ PACKER_DIR: images, PACKER_INIT_FLAGS: "-upgrade" }'
reset_calls
run_task pk:init
expect_line "packer init -upgrade ." "init: PACKER_INIT_FLAGS reach it"
consumer pk packer '{ PACKER_DIR: images }'

# ─── inspect ─────────────────────────────────────────────────────────────────
reset_calls
run_task pk:inspect
expect_status ok "inspect: shows the template"
expect_line "packer inspect ." "inspect: the template"
expect_ran_in "packer inspect ." images "inspect: the one in PACKER_DIR"
refute_call "packer build" "inspect: and builds nothing"

# ─── validate ────────────────────────────────────────────────────────────────
reset_calls
run_task pk:validate
expect_status ok "validate: a valid template passes"
expect_line "packer validate ." "validate: every build, with no -only to match nothing"
expect_ran_in "packer validate ." images "validate: from PACKER_DIR, so the template's own relative paths resolve"
refute_call "$SENTINEL" "validate: with no ONLY there is nothing to ask the CLI about"
if [ "$(awk '$0 == "packer validate ." { n++ } END { print n + 0 }' "$CALLS")" = 1 ]; then
  pass "validate: and the CLI is asked once"
else
  fail "validate: the CLI was not asked exactly once"; quoted '    > ' "$CALLS"
fi

FAKE_VALIDATE=1 run_task pk:validate
expect_status fail "validate: a template the CLI rejects fails"

consumer pk packer '{ PACKER_DIR: images, PACKER_VAR_FLAGS: "-var-file=prod.pkrvars.hcl" }'
reset_calls
run_task pk:validate
expect_line "packer validate -var-file=prod.pkrvars.hcl ." "validate: PACKER_VAR_FLAGS reach it"
consumer pk packer '{ PACKER_DIR: images }'

reset_calls
run_task pk:validate ONLY="base.null.one base.null.two"
expect_status ok "validate: ONLY naming builds that are there passes"
expect_line "packer validate -only=base.null.one,base.null.two ." "validate: the names reach the CLI as one list"

reset_calls
run_task pk:validate ONLY="*.one"
expect_line "packer validate -only=*.one ." "validate: a pattern reaches the CLI as written, not as the files it matches"

# The CLI builds what does match and exits 0: a typo drops a build in silence.
reset_calls
run_task pk:validate ONLY="base.null.one base.null.no-such"
expect_status fail "validate: a name in ONLY that matches no build is refused"
expect_output "ONLY" "validate: and says which input"
refute_call "$SENTINEL" "validate: with nothing further asked"

FAKE_WARN_FD=2 run_task pk:validate ONLY="base.null.no-such"
expect_status fail "validate: wherever the CLI writes its warning"

# A CLI that words the warning otherwise would let every typo through.
reset_calls
run_task pk:validate ONLY=base.null.one
expect_call "packer validate -only=$SENTINEL ." "validate: the CLI is asked about a name no build has"
called_before "-only=base.null.one" "-only=$SENTINEL" "validate: after the template itself is validated"

FAKE_SILENT=1 run_task pk:validate ONLY=base.null.one
expect_status fail "validate: a CLI that does not say when a name matches nothing is refused"
expect_output "ONLY cannot be held" "validate: rather than trusted with ONLY"
expect_output "no build is named so" "validate: and what it said instead is shown"

FAKE_SILENT=1 run_task pk:validate
expect_status ok "validate: which only matters when there is an ONLY"

# EXCEPT is held the same way. A mistyped name there leaves nothing out: the
# CLI builds what it was told to skip, and exits 0.
reset_calls
run_task pk:validate EXCEPT="base.null.one listing"
expect_status ok "validate: EXCEPT naming what is there passes"
expect_line "packer validate -except=base.null.one,listing ." "validate: the names reach the CLI as one list"
expect_line "packer validate -except=$SENTINEL ." "validate: the CLI is asked about a name nothing has, as an -except alone"

reset_calls
run_task pk:validate EXCEPT="base.null.one base.null.no-such"
expect_status fail "validate: a name in EXCEPT that matches nothing is refused"
expect_output "EXCEPT" "validate: and says which input"
refute_output "in ONLY" "validate: and not the other"
refute_call "$SENTINEL" "validate: with nothing further asked"

FAKE_WARN_FD=2 run_task pk:validate EXCEPT="base.null.no-such"
expect_status fail "validate: wherever the CLI writes that warning"

reset_calls
run_task pk:validate ONLY="base.*" EXCEPT=base.null.two
expect_status ok "validate: ONLY and EXCEPT together pass"
expect_line "packer validate -only=base.* -except=base.null.two ." "validate: both reach the CLI"
expect_line "packer validate -only=$SENTINEL -except=$SENTINEL ." "validate: and the CLI is asked about both in one call"

run_task pk:validate ONLY=base.null.no-such EXCEPT=base.null.one
expect_status fail "validate: a bad ONLY beside a good EXCEPT is refused"
expect_output "in ONLY" "validate: as the ONLY it is"

FAKE_SILENT_EXCEPT=1 run_task pk:validate EXCEPT=base.null.one
expect_status fail "validate: a CLI that does not say when an -except matches nothing is refused"
expect_output "EXCEPT cannot be held" "validate: rather than trusted with EXCEPT"

FAKE_SILENT_EXCEPT=1 run_task pk:validate ONLY=base.null.one
expect_status ok "validate: which only matters when there is an EXCEPT"

FAKE_SILENT=1 run_task pk:validate ONLY=base.null.one EXCEPT=base.null.two
expect_status fail "validate: a CLI that says neither is refused with both"
expect_output "ONLY cannot be held" "validate: for the first of them"

reset_calls
FAKE_VALIDATE=1 run_task pk:validate ONLY=base.null.one
expect_status fail "validate: an invalid template fails with an ONLY too"
refute_call "$SENTINEL" "validate: and the CLI is asked nothing more"

# ─── build ───────────────────────────────────────────────────────────────────
reset_calls
run_task pk:build
expect_status ok "build: builds the template"
expect_line "packer build ." "build: every build of it"
called_before "packer validate ." "packer build ." "build: validated before it is built"
expect_ran_in "packer build ." images "build: from PACKER_DIR"

consumer pk packer '{ PACKER_DIR: images, PACKER_VAR_FLAGS: "-var-file=prod.pkrvars.hcl", PACKER_BUILD_FLAGS: "-force" }'
reset_calls
run_task pk:build ONLY="base.null.one base.null.two"
expect_line "packer build -var-file=prod.pkrvars.hcl -force -only=base.null.one,base.null.two ." "build: the variables, the build flags and ONLY reach it"
expect_line "packer validate -var-file=prod.pkrvars.hcl -only=base.null.one,base.null.two ." "build: and it is validated with the same variables and ONLY"
refute_call "validate -var-file=prod.pkrvars.hcl -force" "build: the build flags are the build's alone"
consumer pk packer '{ PACKER_DIR: images }'

reset_calls
run_task pk:build ONLY="base.null.one base.null.no-such"
expect_status fail "build: a name in ONLY that matches no build is refused"
refute_call "packer build" "build: and the builds it does match are not built"

reset_calls
run_task pk:build ONLY="base.*" EXCEPT=base.null.two
expect_status ok "build: ONLY and EXCEPT narrow it together"
expect_line "packer build -only=base.* -except=base.null.two ." "build: both reach the build"
called_before "packer validate -only=base.* -except=base.null.two ." "packer build" "build: and the validation before it"

reset_calls
run_task pk:build EXCEPT=base.null.no-such
expect_status fail "build: a name in EXCEPT that matches nothing is refused"
refute_call "packer build" "build: and what it was meant to leave out is not built"

# Called by another task, ONLY is that call's and not the command line's.
printf '%s\n' 'tasks:' '  narrow:' '    cmds:' '      - task: pk:build' '        vars: { ONLY: base.null.no-such }' >> "$CONSUMER/Taskfile.yaml"
reset_calls
run_task narrow
expect_status fail "build: an ONLY given by a calling task is held to the builds too"
refute_call "packer build" "build: and nothing is built"
consumer pk packer '{ PACKER_DIR: images }'
printf '%s\n' 'tasks:' '  leave-out:' '    cmds:' '      - task: pk:build' '        vars: { EXCEPT: base.null.no-such }' >> "$CONSUMER/Taskfile.yaml"
reset_calls
run_task leave-out
expect_status fail "build: so is an EXCEPT given by a calling task"
refute_call "packer build" "build: and nothing is built then either"
consumer pk packer '{ PACKER_DIR: images }'

reset_calls
FAKE_VALIDATE=1 run_task pk:build
expect_status fail "build: a template that is not valid is not built"
refute_call "packer build" "build: no build starts"

FAKE_BUILD=1 run_task pk:build
expect_status fail "build: a build that fails fails"
expect_output "artifacts" "build: and says the builds that finished left theirs"

# ─── nobody to answer ────────────────────────────────────────────────────────
# Every case above runs under --yes, as a pipeline does. Without it, and with
# no terminal to ask, Task cancels a task that has a prompt.
#
# run_unanswered <args...> — run_task, with no --yes.
run_unanswered() {
  status=0
  (cd "$CONSUMER" && task "$@") < /dev/null > "$OUT" 2>&1 || status=$?
  printf '%s' "$status" > "$WORK/last-status"
}

reset_calls
run_unanswered pk:build
expect_status fail "build, unanswered: fails"
expect_call "packer validate ." "build, unanswered: the template was validated"
refute_call "packer build" "build, unanswered: and nothing is built"

reset_calls
run_unanswered pk:validate
expect_status ok "validate, unanswered: asks nothing"

finish

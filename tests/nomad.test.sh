#!/usr/bin/env bash
# nomad: the cluster is named and never the CLI's default, a job is submitted
# only as the plan that was saved and read, and a stop names its job whole.
source "$(dirname "$0")/lib.sh"

# Answers as the CLI does, by subcommand. A render is told from a submission
# by -output, and the plan that reads the modify index from the one that is
# shown by -t. Every call also logs the directory it ran in.
shim nomad '
printf "in %s\n" "${PWD##*/}" >> "$CALLS"
case " $* " in
  *" fmt "*) exit "${FAKE_FMT:-0}" ;;
  *" job validate "*)
    case "$*" in *broken*) printf "%s\n" "Job validation errors"; exit 1 ;; esac
    printf "%s\n" "Job validation successful"; exit "${FAKE_VALIDATE:-0}" ;;
  *" job run -output "*) printf "%s\n" "{\"Job\":{\"ID\":\"web\"}}"; exit "${FAKE_RENDER:-0}" ;;
  *" job plan "*" -t "*) printf "%s\n" "${FAKE_INDEX-7}"; exit "${FAKE_PLAN:-1}" ;;
  *" job plan "*) printf "%s\n" "+ Task Group: web (1 create)"; exit "${FAKE_PLAN:-1}" ;;
  *" job run "*) printf "%s\n" "Job registration successful"; exit "${FAKE_RUN:-0}" ;;
  *" job inspect "*) printf "%s\n" "${FAKE_ID-web}"; exit "${FAKE_INSPECT:-0}" ;;
  *" job status "*) printf "%s\n" "ID = web"; exit "${FAKE_STATUS:-0}" ;;
  *" job stop "*) printf "%s\n" "stopped"; exit "${FAKE_STOP:-0}" ;;
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

# expect_file <path> <case name> / refute_file <path> <case name>
expect_file() { if [ -f "$1" ]; then pass "$2"; else fail "$2: $1 does not exist"; fi; }
refute_file() { if [ -e "$1" ]; then fail "$2: $1 exists"; else pass "$2"; fi; }

ADDR=http://nomad.test:4646
JOBS="$CONSUMER/jobs"
PLANS="$JOBS/.nomad-plan"
SAVED="$PLANS/web.nomad.hcl.json"
INDEX="$PLANS/web.nomad.hcl.index"

mkdir -p "$JOBS/sub"
: > "$JOBS/web.nomad.hcl"
: > "$JOBS/sub/api.nomad"
: > "$JOBS/notes.hcl"
consumer nm nomad '{ NOMAD_DIR: jobs }'

# Nothing here may reach a cluster the caller happens to have configured.
unset NOMAD_ADDR NOMAD_NAMESPACE NOMAD_REGION NOMAD_TOKEN

# ─── fmt ─────────────────────────────────────────────────────────────────────
reset_calls
run_task nm:fmt
expect_status ok "fmt: files in the canonical format pass"
expect_call "nomad fmt -check -recursive ." "fmt: checks every file, and rewrites none"
expect_call "in jobs" "fmt: under NOMAD_DIR"

FAKE_FMT=1 run_task nm:fmt
expect_status fail "fmt: a file the CLI lists fails"

consumer nm nomad '{ NOMAD_DIR: no-such }'
reset_calls
run_task nm:fmt
expect_status fail "fmt: a NOMAD_DIR that is not a directory is refused"
refute_call "nomad" "fmt: and nothing runs"
consumer nm nomad '{ NOMAD_DIR: jobs }'

# ─── validate ────────────────────────────────────────────────────────────────
reset_calls
run_task nm:validate FILE=web.nomad.hcl
expect_status ok "validate: a valid job passes, with no NOMAD_ADDR"
expect_call "nomad job validate web.nomad.hcl" "validate: validates the file named"
expect_call "in jobs" "validate: from NOMAD_DIR, so the file's own relative paths resolve"
refute_call "api.nomad" "validate: and no other"

reset_calls
run_task nm:validate
expect_status ok "validate: with no FILE, every job file passes"
expect_call "nomad job validate ./web.nomad.hcl" "validate: a .nomad.hcl file is a job file"
expect_call "nomad job validate ./sub/api.nomad" "validate: so is a .nomad file, at any depth"
refute_call "notes.hcl" "validate: a bare .hcl file is not"

: > "$JOBS/broken.nomad.hcl"
reset_calls
run_task nm:validate
expect_status fail "validate: one invalid job among valid ones fails"
expect_call "nomad job validate ./web.nomad.hcl" "validate: and the ones after it are still validated"
expect_output "broken.nomad.hcl" "validate: the failure names the file"
rm -f "$JOBS/broken.nomad.hcl"

FAKE_VALIDATE=1 run_task nm:validate FILE=web.nomad.hcl
expect_status fail "validate: a job the CLI rejects fails"

reset_calls
run_task nm:validate FILE=no-such.nomad.hcl
expect_status fail "validate: a FILE that is not there is refused"
refute_call "nomad" "validate: and nothing runs"

mkdir -p "$CONSUMER/empty"
consumer nm nomad '{ NOMAD_DIR: empty }'
run_task nm:validate
expect_status fail "validate: a directory with no job file fails"
expect_output "no job file" "validate: rather than pass by covering nothing"

consumer nm nomad '{ NOMAD_DIR: jobs, NOMAD_JOB_FLAGS: "-var-file=prod.vars.hcl" }'
reset_calls
run_task nm:validate FILE=web.nomad.hcl
expect_call "nomad job validate -var-file=prod.vars.hcl web.nomad.hcl" "validate: NOMAD_JOB_FLAGS reach it"
consumer nm nomad '{ NOMAD_DIR: jobs }'

# ─── plan ────────────────────────────────────────────────────────────────────
# The CLI with no address goes to 127.0.0.1:4646, whatever answers there.
reset_calls
run_task nm:plan FILE=web.nomad.hcl
expect_status fail "plan: no NOMAD_ADDR is refused"
expect_output "NOMAD_ADDR" "plan: says which variable"
refute_call "nomad" "plan: and nothing runs on the CLI's default address"

# Named by the including Taskfile, for a repository with one cluster.
printf 'env:\n  NOMAD_ADDR: %s\n' "$ADDR" >> "$CONSUMER/Taskfile.yaml"
run_task nm:plan FILE=web.nomad.hcl
expect_status ok "plan: a NOMAD_ADDR the including Taskfile sets is one"
if has_line "$INDEX" "$ADDR"; then pass "plan: and is the address the plan is made against"; else fail "plan: the plan was not made against the Taskfile's address"; fi
consumer nm nomad '{ NOMAD_DIR: jobs }'

export NOMAD_ADDR=$ADDR

reset_calls
run_task nm:plan
expect_status fail "plan: no FILE is refused"
refute_call "nomad" "plan: and nothing runs"

reset_calls
run_task nm:plan FILE=web.nomad.hcl
expect_status ok "plan: a plan that holds changes passes"
expect_call "nomad job run -output web.nomad.hcl" "plan: renders the job, submitting nothing"
expect_call "nomad job plan -json -t {{.JobModifyIndex}} .nomad-plan/web.nomad.hcl.json" "plan: reads the modify index of the rendered job"
expect_call "nomad job plan -json .nomad-plan/web.nomad.hcl.json" "plan: and shows the plan of the same file"
called_before " -t " "nomad job plan -json .nomad-plan" "plan: the index is read before the plan is shown, so a change in between fails the apply"
expect_output "+ Task Group: web (1 create)" "plan: shows the plan"
expect_file "$SAVED" "plan: saves the rendered job"
if has_line "$SAVED" '{"Job":{"ID":"web"}}'; then pass "plan: as the CLI rendered it"; else fail "plan: the saved job is not what the CLI rendered"; fi
if [ "$(cat "$INDEX" 2>/dev/null)" = "$(printf '%s\n' 7 "$ADDR" "" "")" ]; then
  pass "plan: saves the index beside it, with the address, namespace and region it was read from"
else
  fail "plan: the saved index is not the index, address, namespace and region"; quoted '    > ' "$INDEX"
fi
if has_line "$PLANS/.gitignore" '*'; then pass "plan: the saved plans ignore themselves in git"; else fail "plan: nothing keeps a saved plan out of git"; fi

FAKE_PLAN=0 run_task nm:plan FILE=web.nomad.hcl
expect_status ok "plan: a plan that moves no allocation passes"
refute_output "no changes" "plan: and is not called unchanged — an update in place exits the same"

# A plan that did not complete leaves nothing for apply to submit — not this
# plan, and not the one before it.
FAKE_PLAN=255 run_task nm:plan FILE=web.nomad.hcl
expect_status fail "plan: a plan that errors fails"
refute_file "$SAVED" "plan: and leaves no saved job"
refute_file "$INDEX" "plan: nor an index"

run_task nm:plan FILE=web.nomad.hcl
reset_calls
FAKE_RENDER=1 run_task nm:plan FILE=web.nomad.hcl
expect_status fail "plan: a job that does not render fails"
refute_call "job plan" "plan: nothing is planned after it"
refute_file "$SAVED" "plan: and the plan saved before it is gone"

FAKE_INDEX='' run_task nm:plan FILE=web.nomad.hcl
expect_status fail "plan: a plan with no modify index fails"
refute_file "$INDEX" "plan: and saves nothing to apply"

reset_calls
run_task nm:plan FILE=../web.nomad.hcl
expect_status fail "plan: a FILE outside NOMAD_DIR is refused"
refute_call "nomad" "plan: and nothing runs"

consumer nm nomad '{ NOMAD_DIR: jobs, NOMAD_JOB_FLAGS: "-var count=2" }'
reset_calls
run_task nm:plan FILE=web.nomad.hcl
expect_call "nomad job run -output -var count=2 web.nomad.hcl" "plan: NOMAD_JOB_FLAGS reach the render"
refute_call "job plan -json -var" "plan: and not the plan, whose job is already rendered"
consumer nm nomad '{ NOMAD_DIR: jobs }'

mkdir -p "$JOBS/sub"
run_task nm:plan FILE=sub/api.nomad
expect_file "$PLANS/sub/api.nomad.json" "plan: a job in a subdirectory is saved under the same path"

# ─── apply ───────────────────────────────────────────────────────────────────
rm -rf "$PLANS"
reset_calls
run_task nm:apply FILE=web.nomad.hcl
expect_status fail "apply: no saved plan is refused"
expect_output "the plan task saves it" "apply: says what makes one"
refute_call "nomad" "apply: and nothing is submitted"

run_task nm:plan FILE=web.nomad.hcl
reset_calls
run_task nm:apply FILE=web.nomad.hcl
expect_status ok "apply: a submission the server takes passes"
expect_call "nomad job run -json -check-index 7 .nomad-plan/web.nomad.hcl.json" "apply: submits the saved job, only while its index is the one planned against"
refute_call "web.nomad.hcl " "apply: and never the file as it is now"
refute_file "$SAVED" "apply: the plan is spent"
refute_file "$INDEX" "apply: and so is its index"

run_task nm:plan FILE=web.nomad.hcl
FAKE_RUN=1 run_task nm:apply FILE=web.nomad.hcl
expect_status fail "apply: a submission the server refuses fails"
refute_file "$SAVED" "apply: and the plan is spent all the same"

run_task nm:plan FILE=web.nomad.hcl
FAKE_RUN=2 run_task nm:apply FILE=web.nomad.hcl
expect_status fail "apply: a job that could not be placed fails"
expect_output "could not be placed" "apply: and is told from a job that was not submitted"

# An index means nothing on another cluster, namespace or region.
run_task nm:plan FILE=web.nomad.hcl
reset_calls
NOMAD_ADDR=http://other.test:4646 run_task nm:apply FILE=web.nomad.hcl
expect_status fail "apply: a plan made against another address is refused"
refute_call "nomad" "apply: and nothing is submitted there"
expect_file "$SAVED" "apply: the plan is kept for the address it was made against"

reset_calls
NOMAD_NAMESPACE=other run_task nm:apply FILE=web.nomad.hcl
expect_status fail "apply: a plan made in another namespace is refused"
refute_call "nomad" "apply: and nothing is submitted"

reset_calls
NOMAD_REGION=other run_task nm:apply FILE=web.nomad.hcl
expect_status fail "apply: a plan made in another region is refused"
refute_call "nomad" "apply: and nothing is submitted"

reset_calls
(unset NOMAD_ADDR; run_task nm:apply FILE=web.nomad.hcl)
expect_status fail "apply: no NOMAD_ADDR is refused"
refute_call "nomad" "apply: and nothing runs"

consumer nm nomad '{ NOMAD_DIR: jobs, NOMAD_RUN_FLAGS: "-detach" }'
reset_calls
run_task nm:apply FILE=web.nomad.hcl
expect_call "nomad job run -json -check-index 7 -detach .nomad-plan/web.nomad.hcl.json" "apply: NOMAD_RUN_FLAGS reach the submission"
consumer nm nomad '{ NOMAD_DIR: jobs }'

consumer nm nomad '{ NOMAD_DIR: jobs, NOMAD_PLAN_DIR: ../out/plans }'
run_task nm:plan FILE=web.nomad.hcl
expect_file "$CONSUMER/out/plans/web.nomad.hcl.json" "plan: NOMAD_PLAN_DIR is where plans are saved, relative to NOMAD_DIR"
reset_calls
run_task nm:apply FILE=web.nomad.hcl
expect_call "-check-index 7 ../out/plans/web.nomad.hcl.json" "apply: and where they are read from"
consumer nm nomad '{ NOMAD_DIR: jobs }'

# ─── stop ────────────────────────────────────────────────────────────────────
reset_calls
run_task nm:stop JOB=web
expect_status fail "stop: no CONFIRM is refused"
refute_call "job stop" "stop: and nothing is stopped"

reset_calls
run_task nm:stop JOB=web CONFIRM=api
expect_status fail "stop: CONFIRM naming another job is refused"
refute_call "job stop" "stop: and nothing is stopped"

reset_calls
run_task nm:stop JOB=web CONFIRM=web
expect_status ok "stop: a job named twice is stopped"
expect_call "nomad job stop web" "stop: stops the job named"
called_before "job status" "job stop" "stop: the job is shown before it is stopped"
expect_output "ID = web" "stop: shows the job"
refute_call "-yes" "stop: the CLI's own question is left to fail a call this did not mean"

# The CLI stops the one job a prefix matches.
reset_calls
FAKE_ID=web-frontend run_task nm:stop JOB=web CONFIRM=web
expect_status fail "stop: a prefix of another job's name is refused"
expect_output "web-frontend" "stop: names the job it would have stopped"
refute_call "job stop" "stop: and stops nothing"

reset_calls
FAKE_INSPECT=1 run_task nm:stop JOB=web CONFIRM=web
expect_status fail "stop: a job the cluster does not have fails"
refute_call "job stop" "stop: and stops nothing"

FAKE_STOP=1 run_task nm:stop JOB=web CONFIRM=web
expect_status fail "stop: a stop that errors fails"

reset_calls
(unset NOMAD_ADDR; run_task nm:stop JOB=web CONFIRM=web)
expect_status fail "stop: no NOMAD_ADDR is refused"
refute_call "nomad" "stop: and nothing runs"

consumer nm nomad '{ NOMAD_DIR: jobs, NOMAD_STOP_FLAGS: "-purge -detach" }'
reset_calls
run_task nm:stop JOB=web CONFIRM=web
expect_call "nomad job stop -purge -detach web" "stop: NOMAD_STOP_FLAGS reach the stop"
consumer nm nomad '{ NOMAD_DIR: jobs }'

reset_calls
run_task nm:stop:plan JOB=web
expect_status ok "stop:plan: shows the job"
refute_call "job stop" "stop:plan: and stops nothing"

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

run_task nm:plan FILE=web.nomad.hcl
reset_calls
run_unanswered nm:apply FILE=web.nomad.hcl
expect_status fail "apply, unanswered: fails"
refute_call "nomad" "apply, unanswered: nothing is submitted"
expect_file "$SAVED" "apply, unanswered: the plan is kept"

reset_calls
run_unanswered nm:stop JOB=web CONFIRM=web
expect_status fail "stop, unanswered: fails"
expect_call "job status" "stop, unanswered: the job was shown"
refute_call "job stop" "stop, unanswered: and not stopped"

finish

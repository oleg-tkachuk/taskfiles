#!/usr/bin/env bash
# checkov: a baseline run that crashed is a failure, not "N → N"; a pinned
# version absent from PATH runs through uvx.
source "$(dirname "$0")/lib.sh"

# A run that finds anything exits 1 whether or not it crashed, as checkov does.
shim checkov '
case "$*" in
  --version) echo 3.2.0 ;;
  *--create-baseline*)
    if [ -n "${FAKE_CRASH:-}" ]; then echo "Traceback: boom" >&2; exit 1; fi
    printf "{\n    \"CKV_K8S_1\",\n    \"CKV_K8S_2\"\n}\n" > .checkov.baseline
    exit 1 ;;
esac'

consumer checkov checkov
printf 'framework: [kubernetes]\n' > "$CONSUMER/.checkov.yaml"
printf '{\n    "CKV_K8S_1"\n}\n' > "$CONSUMER/.checkov.baseline"

export FAKE_CRASH=1
run_task checkov:baseline
expect_status fail "baseline: a crashed run fails the task"
expect_output ".checkov.baseline was not written" "baseline: says the baseline was not written"
expect_output "Traceback: boom" "baseline: shows what checkov printed"
refute_output "baselined findings" "baseline: does not report a count it never produced"
unset FAKE_CRASH

run_task checkov:baseline
expect_status ok "baseline: a run that wrote the baseline passes, findings or not"
expect_output "baselined findings: 1 → 2" "baseline: reports the count before and after"

# A baseline under another name is one checkov never writes: refused up front.
consumer checkov checkov "{ CHECKOV_BASELINE: security/accepted.json }"
reset_calls
run_task checkov:baseline
expect_status fail "baseline: a name checkov never writes is refused"
expect_output "checkov writes .checkov.baseline into the directory it scans" "baseline: the refusal says where checkov writes"
refute_call "--create-baseline" "baseline: checkov does not run for a name it would never write"
consumer checkov checkov "{ CHECKOV_BASELINE: deploy/.checkov.baseline }"
reset_calls
run_task checkov:baseline
refute_output "and nowhere else" "baseline: the name checkov writes is accepted in any directory"

# Pinned and absent: the shimmed checkov is 3.2.0, so 3.3.18 goes through uvx.
shim uvx 'exit 0'
consumer checkov checkov '{ CHECKOV_VERSION: 3.3.18 }'
reset_calls
run_task checkov:triage
expect_status ok "pinned: a version not on PATH runs"
expect_call "uvx checkov@3.3.18 --compact" "pinned: runs the pinned version through uvx"
expect_output "3.3.18 through uvx, not the 3.2.0 on PATH" "pinned: says which checkov it used"

# Pinned and present: the checkov on PATH, and no uvx.
consumer checkov checkov '{ CHECKOV_VERSION: 3.2.0 }'
reset_calls
run_task checkov:triage
expect_status ok "pinned: the version on PATH runs"
expect_call "checkov --compact" "pinned: runs the checkov on PATH"
refute_call "uvx" "pinned: does not reach for uvx when PATH already has the version"

# Each framework reaches checkov as one argument, never parsed by a shell.
shim checkov '
case "$*" in --version) echo 3.2.0 ;; *) printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS" ;; esac'
pwned="$WORK/pwned"
consumer checkov checkov "{ CHECKOV_FRAMEWORKS: ['a b', '\$(touch $pwned)'] }"
reset_calls
run_task checkov:triage
expect_call "[--framework][a b][--framework][\$(touch $pwned)]" "triage: each framework is one argument"
if [ -e "$pwned" ]; then fail "triage: a \$( ) in a framework ran"; else pass "triage: a \$( ) in a framework does not run"; fi

finish

#!/usr/bin/env bash
# checkov: a baseline run that crashed is a failure, not "N → N"; a pinned
# version absent from PATH runs through uvx.
source "$(dirname "$0")/lib.sh"

# A run that finds anything exits 1 whether or not it crashed, as checkov does.
# The version ends in a carriage return, as it does from a Windows-built wheel.
shim checkov '
case "$*" in
  --version) printf "3.2.0\r\n" ;;
  *--create-baseline*)
    if [ -n "${FAKE_CRASH:-}" ]; then
      n=1; while [ "$n" -le "${FAKE_NOISE:-0}" ]; do echo "noise line $n."; n=$((n + 1)); done
      echo "Traceback: boom" >&2; exit 1
    fi
    dir=${FAKE_BASE_DIR:-.}; mkdir -p "$dir"
    printf "{\n    \"CKV_K8S_1\",\n    \"CKV_K8S_2\"\n}\n" > "$dir/.checkov.baseline"
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
# The last 20 lines of what checkov printed, indented under the message.
FAKE_NOISE=30 run_task checkov:baseline
expect_output "    Traceback: boom" "baseline: checkov's output is shown indented"
expect_output "    noise line 12." "baseline: the last lines of a long output are kept"
refute_output "noise line 11." "baseline: the lines before them are left out"
shown=$(awk '/^    / { n++ } END { print n + 0 }' "$OUT")
if [ "$shown" = 20 ]; then pass "baseline: twenty lines are shown, each once"; else fail "baseline: $shown indented lines shown, want 20"; fi
unset FAKE_CRASH

run_task checkov:baseline
expect_status ok "baseline: a run that wrote the baseline passes, findings or not"
expect_output "baselined findings: 1 → 2" "baseline: reports the count before and after"

# A config scanning another directory writes the baseline there: named.
consumer checkov checkov
reset_calls
FAKE_BASE_DIR=deploy run_task checkov:baseline
expect_status fail "baseline: one written to another directory fails"
expect_output "it wrote deploy/.checkov.baseline instead" "baseline: names where checkov did write it"
rm -rf "$CONSUMER/deploy"

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

# A version command that prints nothing has lost the pin; running whatever is
# on PATH instead would be the irreproducible result the pin exists to stop.
consumer checkov checkov "{ CHECKOV_VERSION_CMD: 'awk 0 missing.yaml 2>/dev/null | cat' }"
reset_calls
run_task checkov:triage
expect_status fail "pinned: a version command that prints nothing fails"
expect_output "CHECKOV_VERSION_CMD printed no version" "pinned: names the command that lost the pin"
refute_call "--compact" "pinned: checkov does not run unpinned"

# checkov exits 0 on a directory it could not open, having scanned nothing
# there: the line it prints is the only sign, and the scan fails on it.
shim checkov '
case "$*" in --version) echo 3.2.0 ;; *) [ -z "${FAKE_SKIPPED:-}" ] || echo "Directory deploy does not exist; skipping it" >&2 ;; esac'
consumer checkov checkov
run_task checkov:scan
expect_status ok "scan: a clean run passes"
expect_output "no findings outside the baseline" "scan: says nothing was found"
FAKE_SKIPPED=1 run_task checkov:scan
expect_status fail "scan: a directory checkov skipped fails the scan"
expect_output "part of the tree went unscanned" "scan: says a directory went unscanned"
refute_output "no findings outside the baseline" "scan: a partial scan is not reported clean"

# Findings make checkov exit 1 unless it is told to soft-fail, as checkov does.
shim checkov '
case "$*" in --version) echo 3.2.0 ;; *--soft-fail*) echo "Check: CKV_K8S_1 FAILED" ;; *) echo "Check: CKV_K8S_1 FAILED"; exit 1 ;; esac'
consumer checkov checkov
reset_calls
run_task checkov:triage
expect_status ok "triage: findings are listed, not a failure"
expect_output "CKV_K8S_1 FAILED" "triage: the findings are shown"

finish

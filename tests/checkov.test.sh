#!/usr/bin/env bash
# checkov: a baseline run that crashed is a failure, not "N → N".
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
expect_output "the baseline was not written" "baseline: says the baseline was not written"
expect_output "Traceback: boom" "baseline: shows what checkov printed"
refute_output "baselined findings" "baseline: does not report a count it never produced"
unset FAKE_CRASH

run_task checkov:baseline
expect_status ok "baseline: a run that wrote the baseline passes, findings or not"
expect_output "baselined findings: 1 → 2" "baseline: reports the count before and after"

finish

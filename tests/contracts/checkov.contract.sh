#!/usr/bin/env bash
# checkov, against the real tool: what the scan and triage tasks rely on in
# checkov's behaviour still holds — its exit codes, and the line it prints for
# a directory it could not scan.
source "$(dirname "$0")/../lib.sh"

# A Pod with no security context: several kubernetes checks fail on it.
mkdir -p "$CONSUMER/manifests"
cat > "$CONSUMER/manifests/pod.yaml" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: nginx
YAML

# ─── triage ──────────────────────────────────────────────────────────────────
# checkov exits 1 on any finding; triage lists them and passes, which only
# --soft-fail makes true.
consumer checkov checkov "{ CHECKOV_TARGET: [manifests], CHECKOV_FRAMEWORKS: [kubernetes] }"
run_task checkov:triage
expect_status ok "triage: findings are listed, not a failure"
expect_output "FAILED" "triage: the findings are shown"

# ─── scan ────────────────────────────────────────────────────────────────────
consumer checkov checkov
printf 'directory: [manifests]\nframework: [kubernetes]\n' > "$CONSUMER/.checkov.yaml"
run_task checkov:scan
expect_status fail "scan: a finding outside the baseline fails the gate"

# checkov reports a directory it cannot open on a line of its own and exits 0.
# scan fails on that line; reworded, the gate would pass over a scan of nothing.
printf 'directory: [missing]\nframework: [kubernetes]\n' > "$CONSUMER/.checkov.yaml"
run_task checkov:scan
expect_status fail "scan: a directory checkov could not scan fails the gate"
expect_output "does not exist; skipping it" "scan: checkov still names the directory it skipped"

finish

#!/usr/bin/env bash
# security, against the real trivy, hadolint and gitleaks: what each gate
# relies on in the tool's behaviour still holds. The behaviour tests shim
# these tools, and a shim answers the way it was written to — every gate bug
# found so far lived between a shim and the tool it stood in for.
source "$(dirname "$0")/../lib.sh"

# An AWS access key id shaped the way both scanners' rules match it, made up on
# each run: a literal one would trip this repository's own pre-commit scan,
# and the well-known example key is allowlisted by both scanners.
key="AKIA$(LC_ALL=C tr -dc 'A-Z2-7' < /dev/urandom | head -c 16 || true)"

consumer security security "{ TRIVY_SCANNERS: '--scanners secret' }"
repo() { git -C "$CONSUMER" "$@"; }

# ─── trivy ────────────────────────────────────────────────────────────────────
run_task security:trivy
expect_status ok "trivy: a tree with no secret passes"

printf 'aws_access_key_id = %s\n' "$key" > "$CONSUMER/creds.ini"
run_task security:trivy
expect_status fail "trivy: a secret in the tree fails the gate"
# trivy takes the last value of a repeated flag; the module puts its own
# --exit-code after TRIVY_FLAGS so a consumer's cannot switch the gate off.
run_task security:trivy "TRIVY_FLAGS=--exit-code 0"
expect_status fail "trivy: TRIVY_FLAGS with --exit-code 0 does not switch the gate off"
rm -f "$CONSUMER/creds.ini"

# ─── hadolint ─────────────────────────────────────────────────────────────────
# The gate is --failure-threshold error: warnings are reported, not fatal.
printf 'FROM ubuntu:24.04\nRUN apt-get update && apt-get install -y curl\n' > "$CONSUMER/Dockerfile"
run_task security:dockerfile
expect_status ok "hadolint: a Dockerfile with warnings only passes"
# DL3000, a relative WORKDIR, is graded error.
printf 'FROM scratch\nWORKDIR app\n' > "$CONSUMER/Dockerfile"
run_task security:dockerfile
expect_status fail "hadolint: an error-level finding fails the gate"
rm -f "$CONSUMER/Dockerfile"

# ─── gitleaks ─────────────────────────────────────────────────────────────────
repo init -q
repo config user.email test@example.invalid
repo config user.name test
printf 'clean\n' > "$CONSUMER/readme.txt"
repo add -A && repo commit -qm clean
run_task security:secrets
expect_status ok "gitleaks: a history with no secret passes"

printf 'aws_access_key_id = %s\n' "$key" > "$CONSUMER/creds.ini"
repo add -A && repo commit -qm leak
run_task security:secrets
expect_status fail "gitleaks: a committed secret fails the gate"
refute_output "$key" "gitleaks: the secret is redacted from the log"

finish

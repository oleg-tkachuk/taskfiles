#!/usr/bin/env bash
# pulumi, against the real CLI: the exit codes `unchanged` reads still mean
# what it reports, a pattern that matches nothing still passes in silence, and
# the tasks drive a stack through its whole life.
source "$(dirname "$0")/../lib.sh"

# A backend, a plugin directory and a passphrase of this run's own: nothing of
# the caller's login is read or changed, and nothing leaves the directory.
export PULUMI_HOME="$CONSUMER/.pulumi"
export PULUMI_BACKEND_URL="file://$CONSUMER/state"
export PULUMI_CONFIG_PASSPHRASE=contract
export PULUMI_SKIP_UPDATE_CHECK=1
mkdir -p "$PULUMI_HOME" "$CONSUMER/state" "$CONSUMER/infra"

# program <value> — a project with no provider to fetch: one output in the
# open and one marked secret.
program() {
  cat > "$CONSUMER/infra/Pulumi.yaml" <<YAML
name: contract
runtime: yaml
variables:
  v: $1
outputs:
  out: \${v}
  hidden:
    fn::secret: \${v}-hidden
YAML
}

program a
consumer pu pulumi '{ PULUMI_DIR: infra }'

# ─── a stack that is not there ───────────────────────────────────────────────
run_task pu:unchanged STACK=dev
expect_status fail "unchanged: a stack that does not exist fails"
expect_output "did not complete" "unchanged: the CLI's exit code for it is not the one for a change"

# Creating the stack is the repository's own.
(cd "$CONSUMER" && pulumi --non-interactive --cwd infra stack init dev >/dev/null)

# ─── plan, unchanged, apply ──────────────────────────────────────────────────
run_task pu:plan STACK=dev
expect_status ok "plan: previews a stack with nothing in it yet"

run_task pu:unchanged STACK=dev
expect_status fail "unchanged: a stack an update would change fails"
expect_output "would change" "unchanged: the CLI's exit code for a change is still read as one"

run_task pu:apply STACK=dev
expect_status ok "apply: previews, then updates"
run_task pu:unchanged STACK=dev
expect_status ok "unchanged: a stack an update would not touch passes"
expect_output "no changes" "unchanged: says so"

# ─── output ──────────────────────────────────────────────────────────────────
# The CLI still prints a bare value, masks a secret, and fails on a name the
# stack does not have.
run_task pu:output STACK=dev OUTPUT=out
expect_status ok "output: reads an output"
if [ "$(cat "$OUT")" = a ]; then pass "output: the value and nothing else"; else fail "output: printed more than the value"; quoted '    | ' "$OUT"; fi

run_task pu:output STACK=dev OUTPUT=hidden
expect_output "[secret]" "output: a secret is masked"
refute_output "a-hidden" "output: and its value is not printed"

run_task pu:output STACK=dev OUTPUT=hidden SHOW_SECRETS=1
if [ "$(cat "$OUT")" = a-hidden ]; then pass "output: SHOW_SECRETS=1 prints the secret"; else fail "output: SHOW_SECRETS=1 did not print the secret"; fi

run_task pu:output STACK=dev OUTPUT=no-such
expect_status fail "output: a name the stack does not have fails"

# ─── refresh ─────────────────────────────────────────────────────────────────
run_task pu:refresh:plan STACK=dev
expect_status ok "refresh:plan: previews a refresh"
run_task pu:refresh STACK=dev
expect_status ok "refresh: previews, then refreshes"
run_task pu:unchanged STACK=dev
expect_status ok "refresh: a state that already matched is left matching"

# ─── a pattern that matches nothing ──────────────────────────────────────────
# Why TARGETS refuses patterns: the CLI takes one that matches nothing, reports
# no changes and exits 0. When this stops being true, the refusal can go.
if (cd "$CONSUMER" && pulumi --non-interactive --cwd infra preview --stack dev --target '**::Release::no-such' >/dev/null 2>&1); then
  pass "the CLI still passes a --target pattern that matches nothing"
else
  fail "the CLI now refuses a --target pattern that matches nothing — TARGETS need not"
fi

# ─── a program that does not run ─────────────────────────────────────────────
cat > "$CONSUMER/infra/Pulumi.yaml" <<'YAML'
name: contract
runtime: yaml
outputs:
  out: ${undeclared}
YAML
run_task pu:unchanged STACK=dev
expect_status fail "unchanged: a program that errors fails"
expect_output "did not complete" "unchanged: and is read as an error, not as a change"
refute_output "would change" "unchanged: nor reported as one"
run_task pu:plan STACK=dev
expect_status fail "plan: a program that errors fails"
program a

# ─── destroy ─────────────────────────────────────────────────────────────────
run_task pu:destroy:plan STACK=dev
expect_status ok "destroy:plan: previews the destruction"
run_task pu:unchanged STACK=dev
expect_status ok "destroy:plan: and destroys nothing"

run_task pu:destroy STACK=dev CONFIRM=other
expect_status fail "destroy: CONFIRM naming another stack is refused"
run_task pu:unchanged STACK=dev
expect_status ok "destroy: and nothing was destroyed"

run_task pu:destroy STACK=dev CONFIRM=dev
expect_status ok "destroy: destroys what the stack held"
run_task pu:unchanged STACK=dev
expect_status fail "destroy: an update would now create it again"
expect_output "would change" "destroy: which the CLI reports as a change"

finish

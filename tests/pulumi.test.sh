#!/usr/bin/env bash
# pulumi: the stack is named on every call and never taken from the workspace,
# a change is shown before it is made, and a check that did not complete is
# never the clean result.
source "$(dirname "$0")/lib.sh"

# Answers as the CLI does, by subcommand; a destroy is told from its preview
# by --preview-only.
shim pulumi '
case " $* " in
  *" preview "*) printf "%s\n" "~ one resource will change"; exit "${FAKE_PREVIEW:-0}" ;;
  *" up "*) printf "%s\n" "updated"; exit "${FAKE_UP:-0}" ;;
  *" destroy "*" --preview-only "*) printf "%s\n" "- one resource will go"; exit "${FAKE_DESTROY_PREVIEW:-0}" ;;
  *" destroy "*) printf "%s\n" "destroyed"; exit "${FAKE_DESTROY:-0}" ;;
  *" refresh "*" --preview-only "*) printf "%s\n" "~ one resource has drifted"; exit "${FAKE_REFRESH_PREVIEW:-0}" ;;
  *" refresh "*) printf "%s\n" "refreshed"; exit "${FAKE_REFRESH:-0}" ;;
  *" stack output "*) printf "%s\n" "the-value"; exit "${FAKE_OUTPUT:-0}" ;;
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

URN_A='urn:pulumi:dev::app::kubernetes:helm.sh/v3:Release::traefik'
URN_B='urn:pulumi:dev::app::random:index/randomString:RandomString::r'

mkdir -p "$CONSUMER/infra"
consumer pu pulumi '{ PULUMI_DIR: infra }'

# ─── plan ────────────────────────────────────────────────────────────────────
reset_calls
run_task pu:plan STACK=dev
expect_status ok "plan: a preview that completes passes"
expect_call "pulumi --non-interactive --cwd infra preview --stack dev --diff" "plan: previews PULUMI_DIR for the stack named, without a terminal"
expect_output "~ one resource will change" "plan: shows the preview"

reset_calls
run_task pu:plan
expect_status fail "plan: no STACK is refused"
refute_call "pulumi" "plan: nothing runs on the workspace's current stack"

FAKE_PREVIEW=1 run_task pu:plan STACK=dev
expect_status fail "plan: a preview that errors fails"

consumer pu pulumi '{ PULUMI_DIR: infra, PULUMI_PLAN_FLAGS: "--policy-pack /p" }'
reset_calls
run_task pu:plan STACK=dev
expect_call "preview --stack dev --policy-pack /p" "plan: PULUMI_PLAN_FLAGS are the preview's flags"
refute_call "--diff" "plan: and replace the default one"
consumer pu pulumi '{ PULUMI_DIR: infra }'

# ─── TARGETS ─────────────────────────────────────────────────────────────────
reset_calls
run_task pu:plan STACK=dev TARGETS="$URN_A $URN_B"
expect_call "--target $URN_A --target $URN_B" "TARGETS: each URN is a --target of its own, its \$ and colons intact"

# A pattern that matches nothing is not an error to the CLI: it reports no
# changes and exits 0. So only whole URNs are taken.
reset_calls
run_task pu:plan STACK=dev TARGETS='**::Release::traefik'
expect_status fail "TARGETS: a pattern is refused"
expect_output "is a pattern" "TARGETS: says why"
refute_call "pulumi" "TARGETS: nothing runs on one"

reset_calls
run_task pu:plan STACK=dev TARGETS="$URN_A urn:pulumi:dev::app::x:y:Z::na?e"
expect_status fail "TARGETS: one pattern among whole URNs is refused too"
refute_call "pulumi" "TARGETS: and nothing runs"

# A pattern is read as written, not as the files it happens to match here.
reset_calls
run_task pu:plan STACK=dev TARGETS='inf*'
expect_status fail "TARGETS: a pattern that matches a file is still a pattern"
refute_call "pulumi" "TARGETS: and is not run as that file's name"

# ─── apply ───────────────────────────────────────────────────────────────────
# The preview first, so the question is asked with the changes on screen.
reset_calls
run_task pu:apply STACK=dev
expect_status ok "apply: an update that completes passes"
expect_call "pulumi --non-interactive --cwd infra up --stack dev --yes" "apply: updates the stack named"
called_before " preview " " up " "apply: the preview runs before the update"
expect_output "~ one resource will change" "apply: shows the preview"

reset_calls
FAKE_PREVIEW=1 run_task pu:apply STACK=dev
expect_status fail "apply: a preview that errors fails"
refute_call " up " "apply: nothing is updated after it"

FAKE_UP=1 run_task pu:apply STACK=dev
expect_status fail "apply: an update that errors fails"

reset_calls
run_task pu:apply
expect_status fail "apply: no STACK is refused"
refute_call "pulumi" "apply: nothing runs without one"

reset_calls
run_task pu:apply STACK=dev TARGETS="$URN_A"
expect_call "preview --stack dev --diff --target $URN_A" "apply: TARGETS narrow the preview"
expect_call "up --stack dev --yes --target $URN_A" "apply: and the update to the same resources"

# Called from a consumer's own task, as a repository looping over its layers
# does: what that task passes is what both steps act on.
cat >> "$CONSUMER/Taskfile.yaml" <<YAML
tasks:
  layer:
    cmds:
      - task: pu:apply
        vars: { STACK: dev, TARGETS: '$URN_B' }
YAML
reset_calls
run_task layer
expect_status ok "apply: runs when a consumer's task calls it"
expect_call "preview --stack dev --diff --target $URN_B" "apply: the preview takes the stack and targets that task passed"
expect_call "up --stack dev --yes --target $URN_B" "apply: and so does the update"

consumer pu pulumi '{ PULUMI_DIR: infra, PULUMI_UP_FLAGS: "--refresh --run-program" }'
reset_calls
run_task pu:apply STACK=dev
expect_call "up --stack dev --yes --refresh --run-program" "apply: PULUMI_UP_FLAGS reach the update"
refute_call "preview --stack dev --diff --refresh" "apply: and not the preview"
consumer pu pulumi '{ PULUMI_DIR: infra }'

# ─── destroy:plan ────────────────────────────────────────────────────────────
reset_calls
run_task pu:destroy:plan STACK=dev
expect_status ok "destroy:plan: a preview that completes passes"
expect_call "pulumi --non-interactive --cwd infra destroy --stack dev --preview-only" "destroy:plan: previews the destruction and destroys nothing"
refute_call "--yes" "destroy:plan: approves nothing"
expect_output "- one resource will go" "destroy:plan: shows what would go"

# ─── destroy ─────────────────────────────────────────────────────────────────
# CONFIRM repeats the stack: under --yes there is no question, and a second
# word that must agree is what stands between a wrong STACK and its loss.
reset_calls
run_task pu:destroy STACK=dev
expect_status fail "destroy: no CONFIRM is refused"
refute_call "pulumi" "destroy: nothing runs without one"

reset_calls
run_task pu:destroy STACK=prod CONFIRM=dev
expect_status fail "destroy: CONFIRM naming another stack is refused"
expect_output "CONFIRM does not name" "destroy: says so"
refute_call "--yes" "destroy: nothing is destroyed on a refused CONFIRM"

reset_calls
run_task pu:destroy STACK=dev CONFIRM=dev
expect_status ok "destroy: CONFIRM naming the stack passes"
expect_call "pulumi --non-interactive --cwd infra destroy --stack dev --yes" "destroy: destroys the stack named"
called_before "--preview-only" "destroy --stack dev --yes" "destroy: the preview runs before the destruction"
expect_output "- one resource will go" "destroy: shows what goes"

reset_calls
FAKE_DESTROY_PREVIEW=1 run_task pu:destroy STACK=dev CONFIRM=dev
expect_status fail "destroy: a preview that errors fails"
refute_call "--yes" "destroy: nothing is destroyed after it"

FAKE_DESTROY=1 run_task pu:destroy STACK=dev CONFIRM=dev
expect_status fail "destroy: a destruction that errors fails"

consumer pu pulumi '{ PULUMI_DIR: infra, PULUMI_DESTROY_FLAGS: "--ignore-protect" }'
reset_calls
run_task pu:destroy STACK=dev CONFIRM=dev TARGETS="$URN_A"
expect_call "destroy --stack dev --preview-only --ignore-protect --target $URN_A" "destroy: PULUMI_DESTROY_FLAGS and TARGETS shape the preview"
expect_call "destroy --stack dev --yes --ignore-protect --target $URN_A" "destroy: and the destruction the same way"
consumer pu pulumi '{ PULUMI_DIR: infra }'

# ─── unchanged ───────────────────────────────────────────────────────────────
reset_calls
run_task pu:unchanged STACK=dev
expect_status ok "unchanged: a preview with no changes passes"
expect_call "pulumi --non-interactive --cwd infra preview --stack dev --diff --expect-no-changes" "unchanged: asks the CLI to fail on a change"
expect_output "no changes" "unchanged: says so"

# 7 is the CLI's own "changes were proposed".
FAKE_PREVIEW=7 run_task pu:unchanged STACK=dev
expect_status fail "unchanged: proposed changes fail"
expect_output "~ one resource will change" "unchanged: shows them"
expect_output "would change" "unchanged: says the stack would change"

# Any other code is a preview that did not finish: a program that would not
# run, a stack that is not there. It is not a change, and never "no changes".
for code in 1 6; do
  FAKE_PREVIEW=$code run_task pu:unchanged STACK=dev
  expect_status fail "unchanged: a preview that exits $code fails"
  expect_output "did not complete" "unchanged: exit $code is reported as an error"
  refute_output "no changes" "unchanged: exit $code is never the clean result"
  refute_output "would change" "unchanged: exit $code is not reported as a change"
done

# ─── refresh:plan ────────────────────────────────────────────────────────────
reset_calls
run_task pu:refresh:plan STACK=dev
expect_status ok "refresh:plan: a preview that completes passes"
expect_call "pulumi --non-interactive --cwd infra refresh --stack dev --preview-only --diff" "refresh:plan: previews the refresh and writes nothing"
refute_call "--yes" "refresh:plan: approves nothing"
expect_output "~ one resource has drifted" "refresh:plan: shows what the state no longer matches"

reset_calls
run_task pu:refresh:plan
expect_status fail "refresh:plan: no STACK is refused"
refute_call "pulumi" "refresh:plan: nothing runs without one"

# ─── refresh ─────────────────────────────────────────────────────────────────
# It rewrites the state to match what is there — a resource that is gone
# leaves it — so it is shown first and asked about, as an update is.
reset_calls
run_task pu:refresh STACK=dev
expect_status ok "refresh: a refresh that completes passes"
expect_call "pulumi --non-interactive --cwd infra refresh --stack dev --yes --diff" "refresh: refreshes the stack named"
called_before "--preview-only" "refresh --stack dev --yes" "refresh: the preview runs before the refresh"
expect_output "~ one resource has drifted" "refresh: shows the preview"

reset_calls
FAKE_REFRESH_PREVIEW=1 run_task pu:refresh STACK=dev
expect_status fail "refresh: a preview that errors fails"
refute_call "--yes" "refresh: nothing is written after it"

FAKE_REFRESH=1 run_task pu:refresh STACK=dev
expect_status fail "refresh: a refresh that errors fails"

reset_calls
run_task pu:refresh
expect_status fail "refresh: no STACK is refused"
refute_call "pulumi" "refresh: nothing runs without one"

consumer pu pulumi '{ PULUMI_DIR: infra, PULUMI_REFRESH_FLAGS: "--run-program" }'
reset_calls
run_task pu:refresh STACK=dev TARGETS="$URN_A"
expect_call "refresh --stack dev --preview-only --run-program --target $URN_A" "refresh: PULUMI_REFRESH_FLAGS and TARGETS shape the preview"
expect_call "refresh --stack dev --yes --run-program --target $URN_A" "refresh: and the refresh the same way"
refute_call "--diff" "refresh: PULUMI_REFRESH_FLAGS replace the default one"
consumer pu pulumi '{ PULUMI_DIR: infra }'

# ─── output ──────────────────────────────────────────────────────────────────
# The value and nothing else, so a caller can capture it.
reset_calls
run_task pu:output STACK=dev OUTPUT=url
expect_status ok "output: an output that exists passes"
expect_call "pulumi --non-interactive --cwd infra stack output url --stack dev" "output: reads one output of the stack named"
refute_call "--show-secrets" "output: a secret stays masked unless asked for"
if [ "$(cat "$OUT")" = the-value ]; then pass "output: prints the value and nothing else"; else fail "output: printed more than the value"; quoted '    | ' "$OUT"; fi

reset_calls
run_task pu:output STACK=dev OUTPUT=password SHOW_SECRETS=1
expect_call "stack output password --stack dev --show-secrets" "output: SHOW_SECRETS=1 shows a secret in plaintext"

reset_calls
run_task pu:output STACK=dev OUTPUT=password SHOW_SECRETS=0
refute_call "--show-secrets" "output: SHOW_SECRETS=0 does not"

reset_calls
run_task pu:output STACK=dev OUTPUT=password SHOW_SECRETS=yes
expect_status fail "output: SHOW_SECRETS takes 0 or 1 and nothing else"
refute_call "pulumi" "output: nothing is read on another value"

reset_calls
run_task pu:output STACK=dev
expect_status fail "output: no OUTPUT is refused"
refute_call "pulumi" "output: the whole set of outputs is not dumped instead"

reset_calls
run_task pu:output OUTPUT=url
expect_status fail "output: no STACK is refused"
refute_call "pulumi" "output: nothing runs without one"

FAKE_OUTPUT=1 run_task pu:output STACK=dev OUTPUT=missing
expect_status fail "output: an output the stack does not have fails"

# ─── nobody to answer ────────────────────────────────────────────────────────
# Every case above runs under --yes, as a pipeline does. Without it, and with
# no terminal to ask, Task cancels a task that has a prompt: the preview its
# deps ran is on record and the change is not made.
#
# run_unanswered <args...> — run_task, with no --yes.
run_unanswered() {
  status=0
  (cd "$CONSUMER" && task "$@") < /dev/null > "$OUT" 2>&1 || status=$?
  printf '%s' "$status" > "$WORK/last-status"
}

reset_calls
run_unanswered pu:apply STACK=dev
expect_status fail "apply, unanswered: fails"
expect_call "preview --stack dev" "apply, unanswered: the preview still ran"
refute_call " up " "apply, unanswered: and nothing was updated"

reset_calls
run_unanswered pu:destroy STACK=dev CONFIRM=dev
expect_status fail "destroy, unanswered: fails, CONFIRM or not"
expect_call "destroy --stack dev --preview-only" "destroy, unanswered: the preview still ran"
refute_call "destroy --stack dev --yes" "destroy, unanswered: and nothing was destroyed"

reset_calls
run_unanswered pu:refresh STACK=dev
expect_status fail "refresh, unanswered: fails"
expect_call "refresh --stack dev --preview-only" "refresh, unanswered: the preview still ran"
refute_call "refresh --stack dev --yes" "refresh, unanswered: and the state was not rewritten"

# The tasks that change nothing ask nothing.
for quiet in plan destroy:plan refresh:plan unchanged; do
  run_unanswered "pu:$quiet" STACK=dev
  expect_status ok "$quiet, unanswered: runs, having nothing to ask"
done
run_unanswered pu:output STACK=dev OUTPUT=out
expect_status ok "output, unanswered: runs, having nothing to ask"

# ─── the directory ───────────────────────────────────────────────────────────
consumer pu pulumi
reset_calls
run_task pu:plan STACK=dev
expect_call "pulumi --non-interactive --cwd . preview" "PULUMI_DIR: defaults to the include's directory"

consumer pu pulumi '{ PULUMI_DIR: nowhere }'
reset_calls
run_task pu:plan STACK=dev
expect_status fail "PULUMI_DIR: a directory that does not exist is refused"
expect_output "nowhere" "PULUMI_DIR: names it"
refute_call "pulumi" "PULUMI_DIR: nothing runs"

# ─── on the call ─────────────────────────────────────────────────────────────
# A repository with several projects includes the module once and names the
# project on each call it makes from a task of its own. What the call gives
# wins over what the include gave, for that call alone.
#
# calling <task> <vars as a flow mapping> — a consumer whose task `go` calls
# pu:<task> with those vars, over an include that names infra and --diff.
calling() {
  consumer pu pulumi '{ PULUMI_DIR: infra }'
  cat >> "$CONSUMER/Taskfile.yaml" <<YAML
tasks:
  go:
    cmds:
      - task: pu:$1
        vars: $2
YAML
}

mkdir -p "$CONSUMER/layers/10-network"

calling plan '{ STACK: dev, PULUMI_DIR: layers/10-network }'
reset_calls
run_task go
expect_status ok "on the call: a plan with its own PULUMI_DIR passes"
expect_call "pulumi --non-interactive --cwd layers/10-network preview --stack dev --diff" "on the call: PULUMI_DIR is the project previewed"
refute_call "--cwd infra" "on the call: and the include's is not"

calling plan '{ STACK: dev, PULUMI_DIR: "" }'
reset_calls
run_task go
expect_call "--cwd infra preview" "on the call: an empty PULUMI_DIR falls back to the include's"

calling plan '{ STACK: dev }'
reset_calls
run_task go
expect_call "--cwd infra preview" "on the call: no PULUMI_DIR leaves the include's"

calling plan '{ STACK: dev, PULUMI_DIR: layers/20-absent }'
reset_calls
run_task go
expect_status fail "on the call: a PULUMI_DIR that does not exist is refused"
expect_output "layers/20-absent" "on the call: names it"
refute_call "pulumi" "on the call: nothing runs"

calling plan '{ STACK: dev, PULUMI_PLAN_FLAGS: "--refresh" }'
reset_calls
run_task go
expect_call "preview --stack dev --refresh" "on the call: PULUMI_PLAN_FLAGS are the preview's flags"
refute_call "--diff" "on the call: and replace the include's"

# The preview a change is shown by acts on what the call named, as the change
# does, and the question names it.
calling apply '{ STACK: dev, PULUMI_DIR: layers/10-network, PULUMI_PLAN_FLAGS: "--refresh", PULUMI_UP_FLAGS: "--run-program" }'
reset_calls
run_task go
expect_status ok "on the call: an apply with its own PULUMI_DIR passes"
expect_call "--cwd layers/10-network preview --stack dev --refresh" "on the call: apply previews the project and with the flags it was given"
expect_call "--cwd layers/10-network up --stack dev --yes --run-program" "on the call: and updates the same project, with PULUMI_UP_FLAGS"
refute_call "--cwd infra" "on the call: apply runs nothing on the include's project"
expect_output "of layers/10-network" "on the call: apply asks about the project it acts on"

calling destroy '{ STACK: dev, CONFIRM: dev, PULUMI_DIR: layers/10-network, PULUMI_DESTROY_FLAGS: "--ignore-protect" }'
reset_calls
run_task go
expect_call "--cwd layers/10-network destroy --stack dev --preview-only --ignore-protect" "on the call: destroy previews the project and with the flags it was given"
expect_call "--cwd layers/10-network destroy --stack dev --yes --ignore-protect" "on the call: and destroys the same project"
refute_call "--cwd infra" "on the call: destroy runs nothing on the include's project"
expect_output "of layers/10-network" "on the call: destroy asks about the project it acts on"

calling refresh '{ STACK: dev, PULUMI_DIR: layers/10-network, PULUMI_REFRESH_FLAGS: "--run-program" }'
reset_calls
run_task go
expect_call "--cwd layers/10-network refresh --stack dev --preview-only --run-program" "on the call: refresh previews the project and with the flags it was given"
expect_call "--cwd layers/10-network refresh --stack dev --yes --run-program" "on the call: and refreshes the same project"
refute_call "--cwd infra" "on the call: refresh runs nothing on the include's project"

calling unchanged '{ STACK: dev, PULUMI_DIR: layers/10-network }'
reset_calls
run_task go
expect_call "--cwd layers/10-network preview --stack dev --diff --expect-no-changes" "on the call: unchanged checks the project named"
expect_output "of layers/10-network" "on the call: and reports on it"

calling output '{ STACK: dev, OUTPUT: url, PULUMI_DIR: layers/10-network }'
reset_calls
run_task go
expect_call "--cwd layers/10-network stack output url --stack dev" "on the call: output reads the project named"

finish

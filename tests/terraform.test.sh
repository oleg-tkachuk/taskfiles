#!/usr/bin/env bash
# terraform: each gate reads the exit code that means what it reports, and a
# run that did not complete is never the clean result.
source "$(dirname "$0")/lib.sh"

LOCK=.terraform.lock.hcl

# Answers as the CLI does, by subcommand. FAKE_LOCK_ADDS is what `providers
# lock` appends to the lock file, as it does for a platform it had no
# checksums for. A plan given -out writes that file, under -chdir as the CLI
# resolves it, and like the CLI makes no directory for it.
CLI='
dir=.; out=""
for a in "$@"; do case "$a" in -chdir=*) dir=${a#-chdir=} ;; -out=*) out=${a#-out=} ;; esac; done
case " $* " in
  *" fmt "*) [ -z "${FAKE_FMT_OUT:-}" ] || printf "%s\n" "$FAKE_FMT_OUT"; exit "${FAKE_FMT:-0}" ;;
  *" init "*) printf "%s\n" "init said something"; exit "${FAKE_INIT:-0}" ;;
  *" validate "*) exit "${FAKE_VALIDATE:-0}" ;;
  *" providers lock "*)
    [ -z "${FAKE_LOCK_ADDS:-}" ] || printf "%s\n" "$FAKE_LOCK_ADDS" >> "$dir/'"$LOCK"'"
    exit "${FAKE_LOCK:-0}" ;;
  *" plan "*)
    printf "%s\n" "~ one resource will change"
    if [ -n "$out" ] && [ "${FAKE_PLAN:-0}" = 0 ]; then
      [ -d "$dir/$(dirname "$out")" ] || { printf "%s\n" "Error: Failed to write plan file" >&2; exit 1; }
      printf "%s\n" "$*" > "$dir/$out"
    fi
    exit "${FAKE_PLAN:-0}" ;;
  *" workspace show "*) printf "%s\n" "${FAKE_WORKSPACE:-default}" ;;
  *" apply "*) exit "${FAKE_APPLY:-0}" ;;
esac'
shim terraform "$CLI"
shim tofu "$CLI"

mkdir -p "$CONSUMER/infra"
consumer tf terraform '{ TERRAFORM_DIR: infra }'

# ─── fmt ─────────────────────────────────────────────────────────────────────
run_task tf:fmt
expect_status ok "fmt: formatted files pass"
expect_call "terraform -chdir=infra fmt -check -recursive" "fmt: checks TERRAFORM_DIR and what is under it"

# 3 is the CLI's own "something is not formatted".
FAKE_FMT=3 FAKE_FMT_OUT=infra/main.tf run_task tf:fmt
expect_status fail "fmt: an unformatted file fails"
expect_output "infra/main.tf" "fmt: names the file"
expect_output "not formatted" "fmt: says what is wrong with it"

# Any other code is a file the CLI could not read, not a formatting finding.
FAKE_FMT=2 FAKE_FMT_OUT="Error: Invalid block" run_task tf:fmt
expect_status fail "fmt: a file that does not parse fails"
expect_output "could not be read" "fmt: a parse error is not reported as formatting"
refute_output "not formatted" "fmt: and not as an unformatted file"

# ─── validate ────────────────────────────────────────────────────────────────
reset_calls
run_task tf:validate
expect_status ok "validate: a valid configuration passes"
expect_call "terraform -chdir=infra init -backend=false -input=false -lockfile=readonly" "validate: installs providers without a backend and without moving the lock"
expect_call "terraform -chdir=infra validate" "validate: validates TERRAFORM_DIR"
refute_output "init said something" "validate: an init that worked stays quiet"

reset_calls
FAKE_INIT=1 run_task tf:validate
expect_status fail "validate: a failed init fails"
expect_output "init said something" "validate: shows what init printed"
refute_call "validate" "validate: nothing is validated after a failed init"

FAKE_VALIDATE=1 run_task tf:validate
expect_status fail "validate: an invalid configuration fails"

# ─── lock ────────────────────────────────────────────────────────────────────
reset_calls
run_task tf:lock
expect_call "terraform -chdir=infra providers lock -platform=linux_amd64 -platform=darwin_arm64" "lock: records checksums for the default platforms"

consumer tf terraform '{ TERRAFORM_DIR: infra, TERRAFORM_PLATFORMS: [linux_arm64] }'
reset_calls
run_task tf:lock
expect_call "providers lock -platform=linux_arm64" "lock: TERRAFORM_PLATFORMS names the platforms"
refute_call "linux_amd64" "lock: and replaces the default ones"
consumer tf terraform '{ TERRAFORM_DIR: infra }'

# ─── lock:check ──────────────────────────────────────────────────────────────
run_task tf:lock:check
expect_status fail "lock:check: no lock file fails"
expect_output "infra/$LOCK does not exist" "lock:check: names the missing file"

printf 'provider "x" {}\n' > "$CONSUMER/infra/$LOCK"
run_task tf:lock:check
expect_status ok "lock:check: a lock the CLI has nothing to add to passes"
expect_output "linux_amd64 darwin_arm64" "lock:check: says which platforms it covers"

# The CLI adds checksums for a platform the lock lacked: that is the finding,
# and the file is put back as it was.
FAKE_LOCK_ADDS='h1:new' run_task tf:lock:check
expect_status fail "lock:check: a lock missing a platform's checksums fails"
expect_output "run the lock task" "lock:check: names the task that writes them"
if has_line "$CONSUMER/infra/$LOCK" 'h1:new'; then
  fail "lock:check: the lock file was changed by a check"
else
  pass "lock:check: the lock file is left as it was"
fi

FAKE_LOCK=1 run_task tf:lock:check
expect_status fail "lock:check: a CLI that could not read the registry fails"
refute_output "covers" "lock:check: and is not reported as covered"

# In a repository, a lock nobody committed protects nobody else.
git -C "$CONSUMER" init -q
run_task tf:lock:check
expect_status fail "lock:check: an untracked lock file fails"
expect_output "not tracked by git" "lock:check: says it is not tracked"
git -C "$CONSUMER" add "infra/$LOCK"
run_task tf:lock:check
expect_status ok "lock:check: a tracked lock passes"
rm -rf "$CONSUMER/.git"

# ─── drift ───────────────────────────────────────────────────────────────────
reset_calls
run_task tf:drift
expect_status ok "drift: an empty plan passes"
expect_call "terraform -chdir=infra init -input=false -lockfile=readonly" "drift: initialises the backend without moving the lock"
refute_call "backend=false" "drift: with the backend, which holds the state"
expect_call "terraform -chdir=infra plan -input=false -detailed-exitcode" "drift: plans with the exit code that tells a diff from an error"
expect_output "no drift" "drift: says so"

# 2 is the CLI's own "the plan succeeded and there is a diff".
FAKE_PLAN=2 run_task tf:drift
expect_status fail "drift: a plan with changes fails"
expect_output "~ one resource will change" "drift: shows the plan"
expect_output "differs from" "drift: says the infrastructure differs"

# 1 is an error. It is not drift, and above all it is not "no drift".
FAKE_PLAN=1 run_task tf:drift
expect_status fail "drift: a plan that errored fails"
expect_output "did not complete" "drift: an error is reported as one"
refute_output "no drift" "drift: and never as a clean result"
refute_output "differs from" "drift: nor as drift"

reset_calls
FAKE_INIT=1 run_task tf:drift
expect_status fail "drift: a failed init fails"
refute_call " plan " "drift: nothing is planned after a failed init"

consumer tf terraform '{ TERRAFORM_DIR: infra, TERRAFORM_PLAN_FLAGS: "-var-file=prod.tfvars" }'
reset_calls
run_task tf:drift
expect_call "-detailed-exitcode -var-file=prod.tfvars" "drift: TERRAFORM_PLAN_FLAGS reach the plan"

# ─── plan ────────────────────────────────────────────────────────────────────
PLAN=infra/.terraform/tfplan
consumer tf terraform '{ TERRAFORM_DIR: infra, TERRAFORM_PLAN_FLAGS: "-var-file=prod.tfvars" }'
reset_calls
run_task tf:plan
expect_status ok "plan: a plan that completes passes"
expect_call "terraform -chdir=infra init -input=false -lockfile=readonly" "plan: initialises the backend without moving the lock"
expect_call "terraform -chdir=infra plan -input=false -out=.terraform/tfplan -var-file=prod.tfvars" "plan: saves the plan, with TERRAFORM_PLAN_FLAGS"
expect_output "~ one resource will change" "plan: shows the plan"
expect_output "saved to $PLAN" "plan: says where it was saved"

# A plan that errored leaves nothing behind to apply, the last one included.
FAKE_PLAN=1 run_task tf:plan
expect_status fail "plan: a plan that errors fails"
refute_output "saved to" "plan: and is not reported as saved"
if [ -e "$CONSUMER/$PLAN" ]; then fail "plan: an earlier plan survived a failed one"; else pass "plan: no earlier plan is left to apply"; fi

consumer tf terraform '{ TERRAFORM_DIR: infra, TERRAFORM_PLAN_FILE: out/reviewed.tfplan }'
reset_calls
run_task tf:plan
expect_call "plan -input=false -out=out/reviewed.tfplan" "plan: TERRAFORM_PLAN_FILE names the file, under TERRAFORM_DIR"
rm -rf "$CONSUMER/infra/out"
consumer tf terraform '{ TERRAFORM_DIR: infra }'

# ─── apply ───────────────────────────────────────────────────────────────────
# Only a saved plan is applied: what runs is what was read.
reset_calls
run_task tf:apply
expect_status fail "apply: no saved plan is refused"
expect_output "$PLAN does not exist" "apply: names the plan it did not find"
refute_call " apply " "apply: nothing is applied without one"

run_task tf:plan
reset_calls
run_task tf:apply
expect_status ok "apply: a saved plan is applied"
expect_call "terraform -chdir=infra apply -input=false .terraform/tfplan" "apply: applies that file and nothing else"
refute_call "auto-approve" "apply: never approves a plan nobody saw"
if [ -e "$CONSUMER/$PLAN" ]; then fail "apply: the applied plan was left behind"; else pass "apply: an applied plan is removed"; fi

# A plan the CLI refused, or that failed part way, is stale either way.
run_task tf:plan
FAKE_APPLY=1 run_task tf:apply
expect_status fail "apply: a failed apply fails"
if [ -e "$CONSUMER/$PLAN" ]; then fail "apply: a plan that failed to apply was left behind"; else pass "apply: a plan that failed to apply is removed"; fi

# An init that failed applied nothing, so the plan is still the reviewed one.
run_task tf:plan
reset_calls
FAKE_INIT=1 run_task tf:apply
expect_status fail "apply: a failed init fails"
refute_call " apply " "apply: nothing is applied after a failed init"
if [ -e "$CONSUMER/$PLAN" ]; then pass "apply: the plan is kept when nothing was applied"; else fail "apply: the plan was removed though nothing was applied"; fi
rm -f "$CONSUMER/$PLAN"

# ─── destroy:plan ────────────────────────────────────────────────────────────
# With no data directory yet, as after an init that had nothing to install.
DESTROY_PLAN=$PLAN.destroy
rm -rf "$CONSUMER/infra/.terraform"
consumer tf terraform '{ TERRAFORM_DIR: infra, TERRAFORM_PLAN_FLAGS: "-var-file=prod.tfvars" }'
reset_calls
run_task tf:destroy:plan
expect_status ok "destroy:plan: a plan that completes passes"
expect_call "terraform -chdir=infra plan -destroy -input=false -out=.terraform/tfplan.destroy -var-file=prod.tfvars" "destroy:plan: plans the destruction into a file of its own, with TERRAFORM_PLAN_FLAGS"
refute_call " apply " "destroy:plan: destroys nothing"
expect_output "~ one resource will change" "destroy:plan: shows the plan"
expect_output "saved to $DESTROY_PLAN" "destroy:plan: says where it was saved"
if [ -e "$CONSUMER/$PLAN" ]; then fail "destroy:plan: wrote the file apply reads"; else pass "destroy:plan: apply has nothing to pick up"; fi

FAKE_PLAN=1 run_task tf:destroy:plan
expect_status fail "destroy:plan: a plan that errors fails"
if [ -e "$CONSUMER/$DESTROY_PLAN" ]; then fail "destroy:plan: an earlier plan survived a failed one"; else pass "destroy:plan: no earlier plan is left to apply"; fi
consumer tf terraform '{ TERRAFORM_DIR: infra }'

# ─── destroy ─────────────────────────────────────────────────────────────────
# Only the saved destruction is applied, and CONFIRM names what it destroys:
# the directory and the workspace selected in it, which is ambient state
# nobody re-reads before typing a command.
reset_calls
run_task tf:destroy CONFIRM=infra:default
expect_status fail "destroy: no saved plan is refused"
expect_output "$DESTROY_PLAN does not exist" "destroy: names the plan it did not find"
refute_call " apply " "destroy: nothing is destroyed without one"

# A plan apply could run is not a destruction somebody read.
run_task tf:plan
reset_calls
run_task tf:destroy CONFIRM=infra:default
expect_status fail "destroy: the plan saved for apply is not taken instead"
refute_call " apply " "destroy: and nothing is applied"
rm -f "$CONSUMER/$PLAN"

run_task tf:destroy:plan
reset_calls
run_task tf:destroy
expect_status fail "destroy: no CONFIRM is refused"
refute_call "terraform" "destroy: nothing runs without one"

reset_calls
run_task tf:destroy CONFIRM=infra:prod
expect_status fail "destroy: CONFIRM naming another workspace is refused"
expect_output "CONFIRM does not name" "destroy: says so"
refute_call " apply " "destroy: nothing is destroyed on a refused CONFIRM"

reset_calls
run_task tf:destroy CONFIRM=other:default
expect_status fail "destroy: CONFIRM naming another directory is refused"
refute_call " apply " "destroy: nothing is destroyed on it"
if [ -e "$CONSUMER/$DESTROY_PLAN" ]; then pass "destroy: the plan is kept when nothing was applied"; else fail "destroy: the plan was removed though nothing was applied"; fi

reset_calls
run_task tf:destroy CONFIRM=infra:default
expect_status ok "destroy: CONFIRM naming the directory and its workspace passes"
expect_call "terraform -chdir=infra apply -input=false .terraform/tfplan.destroy" "destroy: applies the saved destruction and nothing else"
refute_call " plan " "destroy: makes no plan of its own"
refute_call "auto-approve" "destroy: never through auto-approve"
if [ -e "$CONSUMER/$DESTROY_PLAN" ]; then fail "destroy: its plan was left behind"; else pass "destroy: an applied plan is removed"; fi

run_task tf:destroy:plan
FAKE_WORKSPACE=prod run_task tf:destroy CONFIRM=infra:default
expect_status fail "destroy: the workspace is the one the CLI reports, not the default one"
FAKE_WORKSPACE=prod run_task tf:destroy CONFIRM=infra:prod
expect_status ok "destroy: and CONFIRM naming that one passes"

run_task tf:destroy:plan
FAKE_APPLY=1 run_task tf:destroy CONFIRM=infra:default
expect_status fail "destroy: a failed apply fails"
if [ -e "$CONSUMER/$DESTROY_PLAN" ]; then fail "destroy: a plan that failed to apply was left behind"; else pass "destroy: a plan that failed to apply is removed"; fi

# ─── the CLI and the directory ───────────────────────────────────────────────
consumer tf terraform '{ TERRAFORM_DIR: infra, TERRAFORM_BIN: tofu }'
reset_calls
run_task tf:fmt
expect_call "tofu -chdir=infra fmt" "TERRAFORM_BIN: names the CLI that runs"
refute_call "terraform " "TERRAFORM_BIN: and terraform does not"

consumer tf terraform
reset_calls
run_task tf:fmt
expect_call "terraform -chdir=. fmt" "TERRAFORM_DIR: defaults to the include's directory"

consumer tf terraform '{ TERRAFORM_DIR: nowhere }'
reset_calls
run_task tf:fmt
expect_status fail "TERRAFORM_DIR: a directory that does not exist is refused"
expect_output "nowhere" "TERRAFORM_DIR: names it"
refute_call "fmt" "TERRAFORM_DIR: nothing runs"

consumer tf terraform '{ TERRAFORM_DIR: infra, TERRAFORM_BIN: no-such-cli }'
run_task tf:fmt
expect_status fail "TERRAFORM_BIN: a CLI that is not installed is refused"
expect_output "no-such-cli is not installed" "TERRAFORM_BIN: names it"

finish

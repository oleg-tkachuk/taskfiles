#!/usr/bin/env bash
# terraform: each gate reads the exit code that means what it reports, and a
# run that did not complete is never the clean result.
source "$(dirname "$0")/lib.sh"

LOCK=.terraform.lock.hcl

# Answers as the CLI does, by subcommand. FAKE_LOCK_ADDS is what `providers
# lock` appends to the lock file, as it does for a platform it had no
# checksums for.
CLI='
case " $* " in
  *" fmt "*) [ -z "${FAKE_FMT_OUT:-}" ] || printf "%s\n" "$FAKE_FMT_OUT"; exit "${FAKE_FMT:-0}" ;;
  *" init "*) printf "%s\n" "init said something"; exit "${FAKE_INIT:-0}" ;;
  *" validate "*) exit "${FAKE_VALIDATE:-0}" ;;
  *" providers lock "*)
    dir=.; for a in "$@"; do case "$a" in -chdir=*) dir=${a#-chdir=} ;; esac; done
    [ -z "${FAKE_LOCK_ADDS:-}" ] || printf "%s\n" "$FAKE_LOCK_ADDS" >> "$dir/'"$LOCK"'"
    exit "${FAKE_LOCK:-0}" ;;
  *" plan "*) printf "%s\n" "~ one resource will change"; exit "${FAKE_PLAN:-0}" ;;
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

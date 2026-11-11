#!/usr/bin/env bash
# terraform, against the real CLIs: the exit codes the gates read and the way
# `providers lock` treats a lock file still hold, for terraform and for tofu.
source "$(dirname "$0")/../lib.sh"

# Each CLI gets directories of its own: the two write the same file names, and
# neither should meet what the other left.

# gates <dir> — a root module with no provider to download and its state file
# beside it.
gates() {
  mkdir -p "$CONSUMER/$1"
  cat > "$CONSUMER/$1/main.tf" <<'HCL'
resource "terraform_data" "x" {
  input = "a"
}
HCL
}

for cli in terraform tofu; do
  dir=$cli-gates
  gates "$dir"
  consumer tf terraform "{ TERRAFORM_DIR: $dir, TERRAFORM_BIN: $cli }"

  # ─── fmt ───────────────────────────────────────────────────────────────────
  run_task tf:fmt
  expect_status ok "$cli fmt: a formatted configuration passes"

  printf 'locals {\n a   = 1\n}\n' > "$CONSUMER/$dir/loose.tf"
  run_task tf:fmt
  expect_status fail "$cli fmt: an unformatted file fails"
  expect_output "not formatted" "$cli fmt: the CLI's exit code for it is still read as that"

  printf 'locals {\n' > "$CONSUMER/$dir/loose.tf"
  run_task tf:fmt
  expect_status fail "$cli fmt: a file that does not parse fails"
  expect_output "could not be read" "$cli fmt: and its exit code is a different one"

  rm -f "$CONSUMER/$dir/loose.tf"

  # ─── validate ──────────────────────────────────────────────────────────────
  run_task tf:lock
  expect_status ok "$cli lock: writes a lock file for a configuration with no provider to fetch"
  run_task tf:validate
  expect_status ok "$cli validate: a valid configuration passes, with no backend"

  printf 'output "o" {\n  value = var.undeclared\n}\n' > "$CONSUMER/$dir/bad.tf"
  run_task tf:validate
  expect_status fail "$cli validate: a reference to nothing fails"
  rm -f "$CONSUMER/$dir/bad.tf"

  # ─── lock:check ────────────────────────────────────────────────────────────
  run_task tf:lock:check
  expect_status ok "$cli lock:check: the lock the lock task wrote is complete"

  # ─── drift ─────────────────────────────────────────────────────────────────
  run_task tf:drift
  expect_status fail "$cli drift: nothing applied yet is a difference"
  expect_output "differs from" "$cli drift: the CLI's exit code for a diff is still read as one"

  # The state the next case compares against; a local file, nothing real.
  (cd "$CONSUMER" && "$cli" -chdir="$dir" apply -input=false -auto-approve >/dev/null)
  run_task tf:drift
  expect_status ok "$cli drift: a configuration matching its state passes"
  expect_output "no drift" "$cli drift: says so"

  printf 'resource "terraform_data" "y" {\n  input = var.undeclared\n}\n' > "$CONSUMER/$dir/bad.tf"
  run_task tf:drift
  expect_status fail "$cli drift: a plan that errors fails"
  expect_output "did not complete" "$cli drift: and is not read as drift or as none"
  rm -f "$CONSUMER/$dir/bad.tf"
done

# ─── lock:check, with a provider ─────────────────────────────────────────────
# What the check rests on: asked for platforms a lock already covers, the CLI
# leaves the file as it is; asked for one it lacks, it rewrites it. The two
# differ in what a one-platform lock holds — terraform records that platform
# alone, tofu every platform the registry lists — and the check reads both
# rightly because it asks rather than counts.
provider() {
  mkdir -p "$CONSUMER/$1"
  cat > "$CONSUMER/$1/main.tf" <<'HCL'
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}
HCL
}

for cli in terraform tofu; do
  dir=$cli-lock
  provider "$dir"
  consumer tf terraform "{ TERRAFORM_DIR: $dir, TERRAFORM_BIN: $cli, TERRAFORM_PLATFORMS: [linux_amd64] }"
  run_task tf:lock
  expect_status ok "$cli lock: fetches one platform's checksums"

  cp "$CONSUMER/$dir/.terraform.lock.hcl" "$WORK/one-platform.lock"
  run_task tf:lock:check
  expect_status ok "$cli lock:check: a lock holding the platform asked for passes"

  consumer tf terraform "{ TERRAFORM_DIR: $dir, TERRAFORM_BIN: $cli, TERRAFORM_PLATFORMS: [linux_amd64, darwin_arm64] }"
  run_task tf:lock:check
  case "$cli" in
    terraform) expect_status fail "terraform lock:check: a lock written for one platform lacks the other" ;;
    tofu) expect_status ok "tofu lock:check: a lock written for one platform holds the other too" ;;
  esac
  if cmp -s "$CONSUMER/$dir/.terraform.lock.hcl" "$WORK/one-platform.lock"; then
    pass "$cli lock:check: the lock file is left as it was"
  else
    fail "$cli lock:check: the check changed the lock file"
  fi

  # A lock holding more than is asked for is complete, not different.
  run_task tf:lock
  consumer tf terraform "{ TERRAFORM_DIR: $dir, TERRAFORM_BIN: $cli, TERRAFORM_PLATFORMS: [linux_amd64] }"
  run_task tf:lock:check
  expect_status ok "$cli lock:check: a lock holding a platform more than asked for passes"

  # So is the lock most repositories have: the one a plain init wrote, checked
  # for the platform that wrote it.
  rm -f "$CONSUMER/$dir/.terraform.lock.hcl"
  (cd "$CONSUMER" && "$cli" -chdir="$dir" init -backend=false -input=false >/dev/null)
  platform=$(cd "$CONSUMER" && "$cli" version -json | awk -F'"' '/"platform"/ { print $4 }')
  consumer tf terraform "{ TERRAFORM_DIR: $dir, TERRAFORM_BIN: $cli, TERRAFORM_PLATFORMS: [$platform] }"
  run_task tf:lock:check
  expect_status ok "$cli lock:check: a lock written by init passes for the platform that wrote it ($platform)"
done

finish

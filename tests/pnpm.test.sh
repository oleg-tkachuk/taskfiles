#!/usr/bin/env bash
# pnpm: pin:check passes when every pin agrees, and names what is wrong when
# an app and a pin file disagree, a pin file carries no pin it recognises, or
# a pnpm other than corepack's shim answers first.
source "$(dirname "$0")/lib.sh"

command -v node >/dev/null 2>&1 || { pass "pnpm: node absent, skipped"; finish; exit; }

# corepack's shim: beside corepack, reporting the version the app pins.
shim corepack ':'
shim pnpm 'node -p "(require(\"./package.json\").packageManager || \"\").replace(/^pnpm@/, \"\").replace(/\+.*/, \"\")"'

mkdir -p "$CONSUMER/app"
printf '{ "packageManager": "pnpm@12.7.0+sha512.abc" }\n' > "$CONSUMER/app/package.json"
printf 'RUN npm install -g pnpm@12.7.0\n' > "$CONSUMER/Dockerfile"

consumer pnpm pnpm "{ PNPM_APPS: [app], PNPM_PIN_FILES: [Dockerfile] }"
run_task pnpm:pin:check
expect_status ok "pin:check: an app and a pin file at one version pass"
expect_output "every pin at 12.7.0" "pin:check: names the version every pin is at"

printf 'ENV PNPM_VERSION=12.6.0\n' > "$CONSUMER/Dockerfile"
run_task pnpm:pin:check
expect_status fail "pin:check: an app and a pin file that disagree fail"
expect_output "the pins disagree: 12.7.0 12.6.0" "pin:check: lists the pins that disagree"

printf 'RUN corepack enable\n' > "$CONSUMER/Dockerfile"
run_task pnpm:pin:check
expect_status fail "pin:check: a pin file with no pin it recognises fails"
expect_output "Dockerfile writes no pnpm version this recognises" "pin:check: names the pin file"

# A pnpm ahead of the shim, reporting the right version all the same.
printf 'RUN npm install -g pnpm@12.7.0\n' > "$CONSUMER/Dockerfile"
mkdir -p "$WORK/standalone"
cp "$BIN/pnpm" "$WORK/standalone/pnpm"
PATH="$WORK/standalone:$PATH" run_task pnpm:pin:check
expect_status fail "pin:check: a pnpm that is not corepack's shim fails"
expect_output "is not corepack's shim" "pin:check: says the pnpm first on PATH is not the shim"

# ─── pin:update ──────────────────────────────────────────────────────────────
# The registry answers with FAKE_LATEST, and corepack writes the pin it is
# asked to use into the app's package.json.
# shellcheck disable=SC2016 # the shims' own variables, written literally
shim npm 'case "$*" in "view pnpm@"*) printf "\"%s\"\n" "$FAKE_LATEST" ;; esac'
# shellcheck disable=SC2016
shim corepack 'case "$1" in use) printf "{ \"packageManager\": \"%s+sha512.new\" }\n" "$2" > package.json ;; esac'
mkdir -p "$CONSUMER/app2"
printf '{ "packageManager": "pnpm@12.7.0+sha512.abc" }\n' > "$CONSUMER/app/package.json"
printf '{ "packageManager": "pnpm@12.7.0+sha512.abc" }\n' > "$CONSUMER/app2/package.json"
printf 'RUN npm install -g pnpm@12.7.0\nENV PNPM_VERSION=12.7.0\n' > "$CONSUMER/Dockerfile"
consumer pnpm pnpm "{ PNPM_APPS: [app, app2], PNPM_PIN_FILES: [Dockerfile] }"

# Two apps and two pins in one file are still one version.
FAKE_LATEST=12.7.0 run_task pnpm:pin:update
expect_status ok "pin:update: pins that agree and are current pass"
expect_output "already pinned at 12.7.0 everywhere" "pin:update: several pins at one version are one version"

FAKE_LATEST=12.8.0 run_task pnpm:pin:update
expect_status ok "pin:update: a newer version is taken"
expect_output "12.7.0 → 12.8.0" "pin:update: says what it moves from and to"
if [ "$(cat "$CONSUMER/Dockerfile")" = "RUN npm install -g pnpm@12.8.0
ENV PNPM_VERSION=12.8.0" ]; then pass "pin:update: both forms of the pin are rewritten in the pin file"; else fail "pin:update: the pin file is not at 12.8.0: $(cat "$CONSUMER/Dockerfile")"; fi
expect_call "corepack use pnpm@12.8.0" "pin:update: each app is moved through corepack"

printf 'RUN npm install -g pnpm@12.6.0\n' > "$CONSUMER/Dockerfile"
reset_calls
FAKE_LATEST=12.9.0 run_task pnpm:pin:update
expect_status fail "pin:update: pins that disagree are not moved"
expect_output "the pins disagree: 12.8.0 12.8.0 12.6.0" "pin:update: lists the pins that disagree"
refute_call "corepack use" "pin:update: nothing is bumped while the pins disagree"

finish

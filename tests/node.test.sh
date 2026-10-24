#!/usr/bin/env bash
# node: script names and the project name reach the package manager as data,
# while PM, E2E_SETUP and LINT_FIX_FLAGS still run as shell fragments.
source "$(dirname "$0")/lib.sh"

shim pnpm 'echo "pnpm argc=$#" >> "$CALLS"; [ "$1" = install ] && mkdir -p node_modules && : > node_modules/.modules.yaml; true'
shim npm '[ "$1" = ci ] && mkdir -p node_modules && : > node_modules/.package-lock.json; true'
shim corepack ''

consumer node node

# install skips while the manifests are unchanged, whichever PM wrote node_modules.
for pm in pnpm npm; do
  rm -rf "$CONSUMER/node_modules" "$CONSUMER/.task"
  printf '{}\n' > "$CONSUMER/package.json"
  run_task node:install "PM=$pm"
  reset_calls
  run_task node:install "PM=$pm"
  expect_status ok "install: a second $pm install runs"
  refute_call "$pm " "install: a second $pm install with unchanged manifests is skipped"
done
rm -f "$CONSUMER/package.json"

# npm keeps a flag before `--` for itself; pnpm passes it to the script.
for case in "pnpm|pnpm run lint --fix|pnpm exec playwright install --with-deps chromium" \
            "npm|npm run lint -- --fix|npm exec -- playwright install --with-deps chromium"; do
  IFS="|" read -r pm lintfix e2e <<< "$case"
  reset_calls
  run_task node:lint:fix "PM=$pm"
  expect_call "$lintfix" "lint:fix: $pm passes --fix to the script"
  reset_calls
  run_task node:test:e2e "PM=$pm"
  expect_call "$e2e" "e2e: $pm passes --with-deps to playwright"
done

reset_calls
run_task node:build
expect_status ok "build: runs"
expect_call "pnpm run build" "build: runs the build script"

reset_calls
run_task node:test SCRIPT_TEST=test:unit
expect_status ok "test: runs"
expect_call "pnpm run test:unit" "test: runs the named test script"

pwned="$WORK/pwned"
reset_calls
run_task node:build "PROJECT_NAME=\$(touch $pwned)" "SCRIPT_BUILD=b\$(touch $pwned)"
if [ -e "$pwned" ]; then fail "values: a \$( ) in the project or script name ran"; else pass "values: a \$( ) in the project or script name does not run"; fi
expect_call "pnpm run b\$(touch $pwned)" "values: the script name reaches pnpm as data"

reset_calls
run_task node:test "SCRIPT_TEST=unit tests"
expect_call "pnpm run unit tests" "values: a script name with a space reaches pnpm"
expect_call "pnpm argc=2" "values: a script name with a space is one argument"

# typecheck asks package.json for the script by name, as an argument to node.
if command -v node >/dev/null 2>&1; then
  printf '%s\n' '{"scripts":{"tc x":"tsc"}}' > "$CONSUMER/package.json"
  reset_calls
  run_task node:typecheck "SCRIPT_TYPECHECK=tc x"
  expect_call "pnpm argc=2" "typecheck: a declared script with a space runs as one argument"
  reset_calls
  run_task node:typecheck "SCRIPT_TYPECHECK=\$(touch $pwned)\"]"
  if [ -e "$pwned" ]; then fail "typecheck: a \$( ) in the script name ran"; else pass "typecheck: a \$( ) in the script name does not run"; fi
  expect_status ok "typecheck: an undeclared script is skipped"
  refute_call "pnpm run" "typecheck: an undeclared script is not run"
  printf '%s\n' '{"scripts":' > "$CONSUMER/package.json"
  reset_calls
  run_task node:typecheck
  expect_status fail "typecheck: a package.json that does not parse fails"
  refute_output "skipped" "typecheck: a package.json that does not parse is not a skip"
  rm -f "$CONSUMER/package.json"
  run_task node:typecheck
  expect_status fail "typecheck: a missing package.json fails"
fi

# A package-manager command of more than one word still runs as a command.
reset_calls
run_task node:build "PM=corepack pnpm"
expect_status ok "pm: a multi-word manager runs"
expect_call "corepack pnpm run build" "pm: the manager is word-split into a command"

reset_calls
run_task node:test:e2e "E2E_SETUP=exec playwright install chromium"
expect_status ok "e2e: runs"
expect_call "pnpm exec playwright install chromium" "e2e: the setup fragment is word-split"
expect_call "pnpm run test:e2e" "e2e: runs the suite"

reset_calls
run_task node:test:e2e E2E_SETUP=none
refute_call "pnpm exec" "e2e: none skips the setup"

reset_calls
run_task node:lint:fix "LINT_FIX_FLAGS=--fix --quiet"
expect_call "pnpm run lint --fix --quiet" "lint:fix: the flags are appended verbatim"

finish

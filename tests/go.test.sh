#!/usr/bin/env bash
# go: values reach go as data, package lists split into one argument per
# pattern, verbatim flag inputs still word-split, and every tool is the pinned
# one before it is PATH's.
source "$(dirname "$0")/lib.sh"

# argv joined with "|", so one argument and two read differently.
argv='printf "%s|" "$0" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"'
# DRIFT names the go subcommand whose -diff has something to report.
export DRIFT="$WORK/drift"
# shellcheck disable=SC2016 # the shim's own $1, written literally
shim_go 'if [ -e "$DRIFT" ] && [ "$(cat "$DRIFT")" = "$1" ]; then printf "%s\n" "-old" "+new"; exit 1; fi'
shim gotestsum "${argv/\$0/gotestsum}"
shim golangci-lint "${argv/\$0/golangci-lint}"

consumer go go
printf 'module example.com/x\n' > "$CONSUMER/go.mod"
: > "$CONSUMER/go.sum"
printf 'package main\n' > "$CONSUMER/main.go"

pwned="$WORK/pwned"
payload="\$(touch $pwned)"
# Package inputs split on spaces by design, so theirs has none.
pkgpayload="\$(:>$pwned)"

run_task --force go:build "PROJECT_NAME=$payload" "GO_MAIN=./cmd/$pkgpayload" "GO_BIN_DIR=out $payload"
expect_status ok "build: runs with a command substitution in its values"
if [ -e "$pwned" ]; then fail "values: a \$( ) in a value ran"; else pass "values: a \$( ) in a value does not run"; fi
expect_call "go|build|-o|out $payload/|./cmd/$pkgpayload|" "build: the bin dir and main package reach go as data"
expect_output "go · build ./cmd/$pkgpayload" "build: the log line prints the value as text"

reset_calls
run_task --force go:build "GO_BUILD_FLAGS=-trimpath -ldflags -s" "GO_MAIN=./cmd/a ./cmd/b"
expect_call "go|build|-trimpath|-ldflags|-s|-o|./bin/|./cmd/a|./cmd/b|" "build: verbatim flags and the package list split into separate arguments"

reset_calls
run_task go:test "GO_PKG=./a/... $pkgpayload"
expect_status ok "test: runs with a command substitution in GO_PKG"
if [ -e "$pwned" ]; then fail "test: a \$( ) in GO_PKG ran"; else pass "test: a \$( ) in GO_PKG does not run"; fi
expect_call "gotestsum|--format|pkgname|--hide-summary|skipped|--|-race|-short|./a/...|$pkgpayload|" "test: default flags split, each package is one argument"

reset_calls
run_task go:test "GO_TEST_FLAGS=-count=1 -run TestX"
expect_call "gotestsum|--format|pkgname|--hide-summary|skipped|--|-count=1|-run|TestX|./...|" "test: verbatim GO_TEST_FLAGS split into separate arguments"

reset_calls
run_task go:test:tagged:compile "GO_TEST_TAGS=integration,$payload"
if [ -e "$pwned" ]; then fail "tags: a \$( ) in GO_TEST_TAGS ran"; else pass "tags: a \$( ) in GO_TEST_TAGS does not run"; fi
expect_call "go|vet|-tags=integration,$payload|./...|" "tags: GO_TEST_TAGS reaches go vet as one argument"

reset_calls
run_task go:lint "GOLANGCI_FLAGS=--timeout 5m"
expect_call "golangci-lint|run|--timeout|5m|./...|" "lint: verbatim GOLANGCI_FLAGS split into separate arguments"

reset_calls
run_task go:bench "BENCH=Foo|$payload"
if [ -e "$pwned" ]; then fail "bench: a \$( ) in BENCH ran"; else pass "bench: a \$( ) in BENCH does not run"; fi
expect_call "go|test|-tags=integration|-run=^\$|-bench=Foo|$payload|-benchtime=1x|./...|" "bench: the pattern reaches go as one argument"

reset_calls
run_task go:test:integration
expect_call "gotestsum|--format|pkgname|--hide-summary|skipped|--|-race|-timeout=10m|-tags=integration|./...|" "integration: go test's own timeout by default"

reset_calls
run_task go:test:integration "GO_TEST_TIMEOUT=20m $payload" "GO_TEST_JSON=out $payload.json"
if [ -e "$pwned" ]; then fail "integration: a \$( ) in its values ran"; else pass "integration: a \$( ) in its values does not run"; fi
expect_call "gotestsum|--format|pkgname|--hide-summary|skipped|--jsonfile|out $payload.json|--|-race|-timeout=20m $payload|-tags=integration|./...|" "integration: the timeout and the json file reach gotestsum as one argument each"

# Without gotestsum go test keeps no stream: a GO_TEST_JSON fails the run
# rather than leave a consumer to read none, or an earlier run's. PATH holds
# the shims and the system's tools alone, so an installed gotestsum is not
# found.
ln -sf "$(command -v task)" "$BIN/task"
mv "$BIN/gotestsum" "$WORK/gotestsum.off"
reset_calls
PATH="$BIN:/usr/bin:/bin" run_task go:test:integration "GO_TEST_JSON=out.json"
expect_status fail "integration: without gotestsum a GO_TEST_JSON fails the run"
expect_output "go test alone keeps no stream" "integration: without gotestsum the failure says why"
refute_call "go|test|" "integration: without gotestsum no suite runs whose stream is lost"
reset_calls
PATH="$BIN:/usr/bin:/bin" run_task go:test:integration
expect_call "go|test|-race|-timeout=10m|-tags=integration|./...|" "integration: without gotestsum and GO_TEST_JSON, go test runs"
mv "$WORK/gotestsum.off" "$BIN/gotestsum"

# ─── gates that change nothing ───────────────────────────────────────────────
reset_calls
run_task go:tidy:check
expect_status ok "tidy:check: a tidy module passes"
expect_call "go|mod|tidy|-diff|" "tidy:check: asks go for the diff, not the rewrite"
printf mod > "$DRIFT"
run_task go:tidy:check
expect_status fail "tidy:check: a module tidy would change fails"
expect_output "go.mod is not tidy" "tidy:check: says go.mod is not tidy"
expect_output "+new" "tidy:check: shows what tidy would change"

reset_calls
run_task go:fix:check "GO_PKG=./a/... ./b/..." "GO_FIX_FLAGS=-any=false -minmax=false"
expect_status ok "fix:check: code go fix leaves alone passes"
expect_call "go|fix|-diff|-any=false|-minmax=false|./a/...|./b/...|" "fix:check: flags and packages split, and nothing is rewritten"
printf fix > "$DRIFT"
run_task go:fix:check
expect_status fail "fix:check: code go fix would change fails"
expect_output "go fix would change files" "fix:check: says go fix would change files"
expect_output "+new" "fix:check: shows the rewrite"
rm -f "$DRIFT"

# ─── tools: the pinned one first, PATH's after it ────────────────────────────
# PATH holds the shims and the system's tools alone from here on, so a tool
# installed on this machine is not found.
only_shims() { PATH="$BIN:/usr/bin:/bin" run_task "$@"; }
shim gofmt "${argv/\$0/gofmt}"
shim govulncheck "${argv/\$0/govulncheck}"

reset_calls
only_shims go:lint
expect_status ok "lint: runs PATH's golangci-lint when none is pinned"
expect_run golangci-lint "lint: PATH's golangci-lint is the one run"

# GO_TOOLS_PINNED=1: PATH is asked for nothing. A gate fails on a tool nobody
# pinned, and a tool a task can do without is done without.
reset_calls
only_shims go:lint GO_TOOLS_PINNED=1
expect_status fail "pinned: an unpinned golangci-lint fails, though PATH has one"
expect_output "golangci-lint is not pinned by a tool directive, and GO_TOOLS_PINNED=1 leaves PATH out" "pinned: says the tool is not pinned and why PATH does not count"
refute_run golangci-lint "pinned: PATH's golangci-lint is not run"
reset_calls
only_shims go:vuln GO_TOOLS_PINNED=1
expect_status fail "pinned: an unpinned govulncheck fails, though PATH has one"
refute_run govulncheck "pinned: PATH's govulncheck is not run"
reset_calls
only_shims go:test GO_TOOLS_PINNED=1
expect_status ok "pinned: test runs without the unpinned gotestsum"
expect_call "go|test|-race|-short|./...|" "pinned: go test runs in its place"
refute_run gotestsum "pinned: PATH's gotestsum is not run"
reset_calls
only_shims go:lint "GO_TOOLS_PINNED=yes"
expect_status fail "pinned: a GO_TOOLS_PINNED that is neither 1 nor 0 is refused"
expect_output "GO_TOOLS_PINNED must be 1 or 0, got: yes" "pinned: says what GO_TOOLS_PINNED takes"
refute_call "golangci-lint" "pinned: no linter runs on a refused value"

pin_tools golangci-lint gotestsum govulncheck goimports
reset_calls
only_shims go:lint GO_TOOLS_PINNED=1
expect_status ok "pinned: a pinned golangci-lint runs"
expect_call "go|tool|golangci-lint|run|./...|" "pinned: it runs through go tool"
reset_calls
only_shims go:lint "GOLANGCI_FLAGS=--timeout 5m"
expect_call "go|tool|golangci-lint|run|--timeout|5m|./...|" "lint: a pinned golangci-lint runs through go tool, flags split"
refute_run golangci-lint "lint: PATH's golangci-lint is passed over for the pinned one"

reset_calls
only_shims go:vuln
expect_call "go|tool|govulncheck|./...|" "vuln: a pinned govulncheck runs through go tool"
refute_run govulncheck "vuln: PATH's govulncheck is passed over for the pinned one"

reset_calls
only_shims go:test
expect_call "go|tool|gotestsum|--format|pkgname|--hide-summary|skipped|--|-race|-short|./...|" "test: a pinned gotestsum runs through go tool"
refute_run gotestsum "test: PATH's gotestsum is passed over for the pinned one"

reset_calls
only_shims go:test:integration "GO_TEST_JSON=out.json"
expect_call "go|tool|gotestsum|--format|pkgname|--hide-summary|skipped|--jsonfile|out.json|" "integration: a pinned gotestsum keeps the json stream"

# GO_TOOL_MODFILE: the pins live in another go.mod.
mkdir -p "$CONSUMER/tools"
printf 'module example.com/tools\n' > "$CONSUMER/tools/go.mod"
reset_calls
only_shims go:lint "GO_TOOL_MODFILE=tools/go.mod"
expect_call "go|tool|-modfile=tools/go.mod|golangci-lint|run|./...|" "modfile: the tool is asked of GO_TOOL_MODFILE"
reset_calls
only_shims go:lint "GO_TOOL_MODFILE=tools/go.mdo"
expect_status fail "modfile: one that does not exist is refused"
expect_output "GO_TOOL_MODFILE names tools/go.mdo, which does not exist" "modfile: the missing file is named"
refute_call "golangci-lint" "modfile: no linter runs when the file is missing"

# GOLANGCI_LINT_MODFILE: the linter's pin lives apart from the other tools'.
mkdir -p "$CONSUMER/lint"
printf 'module example.com/lint\n' > "$CONSUMER/lint/go.mod"
reset_calls
only_shims go:lint "GO_TOOL_MODFILE=tools/go.mod" "GOLANGCI_LINT_MODFILE=lint/go.mod"
expect_status ok "lint modfile: runs with both set"
expect_call "go|tool|-modfile=lint/go.mod|golangci-lint|run|./...|" "lint modfile: golangci-lint is asked of its own go.mod"
refute_call "-modfile=tools/go.mod|golangci-lint" "lint modfile: not of GO_TOOL_MODFILE"
reset_calls
only_shims go:vuln "GO_TOOL_MODFILE=tools/go.mod" "GOLANGCI_LINT_MODFILE=lint/go.mod"
expect_call "go|tool|-modfile=tools/go.mod|govulncheck|./...|" "lint modfile: every other tool is still asked of GO_TOOL_MODFILE"
reset_calls
only_shims go:lint "GOLANGCI_LINT_MODFILE=lint/go.mdo"
expect_status fail "lint modfile: one that does not exist is refused"
expect_output "GOLANGCI_LINT_MODFILE names lint/go.mdo" "lint modfile: the input and the missing file are named"
refute_call "golangci-lint" "lint modfile: no linter runs when the file is missing"

# Neither pinned nor on PATH: a gate fails and says what to install.
pin_tools
mv "$BIN/golangci-lint" "$BIN/govulncheck" "$WORK/"
only_shims go:lint
expect_status fail "lint: no golangci-lint anywhere fails"
expect_output "golangci-lint is not installed" "lint: says golangci-lint is not installed"
only_shims go:vuln
expect_status fail "vuln: no govulncheck anywhere fails"
expect_output "govulncheck is not installed — go get -tool golang.org/x/vuln/cmd/govulncheck" "vuln: says how to pin govulncheck"
mv "$WORK/golangci-lint" "$WORK/govulncheck" "$BIN/"

# fmt: goimports runs when there is one, unless GO_FMT_GOIMPORTS says which.
reset_calls
only_shims go:fmt
expect_status ok "fmt: runs without goimports"
expect_run gofmt "fmt: gofmt runs"
refute_call "goimports|-w" "fmt: no goimports, none run"

reset_calls
only_shims go:fmt GO_FMT_GOIMPORTS=1
expect_status fail "fmt: GO_FMT_GOIMPORTS=1 without goimports fails"
expect_output "goimports is not installed" "fmt: says goimports is not installed"

shim goimports "${argv/\$0/goimports}"
reset_calls
only_shims go:fmt
expect_run goimports "fmt: PATH's goimports runs when it is found"
reset_calls
only_shims go:fmt GO_FMT_GOIMPORTS=0
expect_status ok "fmt: GO_FMT_GOIMPORTS=0 runs"
refute_call "goimports" "fmt: GO_FMT_GOIMPORTS=0 never runs goimports"
expect_output "formatted" "fmt: GO_FMT_GOIMPORTS=0 still reports the gofmt run"

pin_tools goimports
reset_calls
only_shims go:fmt GO_FMT_GOIMPORTS=1
expect_status ok "fmt: GO_FMT_GOIMPORTS=1 with a pinned goimports runs"
expect_call "go|tool|goimports|-w|.|" "fmt: a pinned goimports runs through go tool"
refute_run goimports "fmt: PATH's goimports is passed over for the pinned one"

only_shims go:fmt GO_FMT_GOIMPORTS=yes
expect_status fail "fmt: a GO_FMT_GOIMPORTS that is neither 1 nor 0 is refused"
expect_output "GO_FMT_GOIMPORTS must be 1 or 0, got: yes" "fmt: the refusal names the value"
pin_tools

reset_calls
run_task go:test:coverage "GO_TEST_FLAGS=-p 1"
expect_call "go|test|-p|1|-coverprofile=coverage/cover.out|./...|" "coverage: the unit run's GO_TEST_FLAGS apply"

# GOWORK: off by default, and "auto" is the explicit opt-in to the workspace —
# an empty value cannot be one, `default` reads it as unset.
shim go 'printf "go GOWORK=[%s]\n" "${GOWORK-unset}" >> "$CALLS"'
for case in "default|off|" "auto|auto|GOWORK=auto" "empty|off|GOWORK=" "path|/w/go.work|GOWORK=/w/go.work"; do
  IFS="|" read -r label expected arg <<< "$case"
  expected=${expected/auto/}
  reset_calls
  run_task --force go:compile ${arg:+"$arg"}
  expect_call "go GOWORK=[$expected]" "gowork: $label reaches go as [$expected]"
done

# ─── vuln: GOVULNCHECK_IGNORE ────────────────────────────────────────────────
# What the scan prints and exits with is read from files, so each case says
# what govulncheck found. PATH's govulncheck is the one run: nothing is pinned,
# and go is the shim that knows which tools are.
shim_go
export VULN_OUT="$WORK/vuln.out" VULN_RC="$WORK/vuln.rc"
# shellcheck disable=SC2016 # the shim's own variables, written literally
shim govulncheck 'cat "$VULN_OUT" 2>/dev/null; exit "$(cat "$VULN_RC" 2>/dev/null || printf 0)"'
pin_tools
# scan <exit status> <line...> — what the next govulncheck run reports.
scan() { printf '%s' "$1" > "$VULN_RC"; shift; printf '%s\n' "$@" > "$VULN_OUT"; }
readonly REACHED=3
two_reached() {
  scan "$REACHED" '=== Symbol Results ===' '' 'Vulnerability #1: GO-2026-0001' '    Found in: example.com/a@v1.0.0' '    Fixed in: N/A' '' 'Vulnerability #2: GO-2026-0002' '' 'Your code is affected by 2 vulnerabilities from 1 module.'
}

two_reached
only_shims go:vuln
expect_status fail "ignore: without the input a finding fails, as before"
refute_output "GOVULNCHECK_IGNORE" "ignore: without the input nothing is said of it"

only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001 GO-2026-0002"
expect_status ok "ignore: every finding named passes"
expect_output "passed over, by GOVULNCHECK_IGNORE: GO-2026-0001 GO-2026-0002" "ignore: the IDs passed over are printed"
expect_output "Vulnerability #1: GO-2026-0001" "ignore: the scan's own report is still shown"

only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001"
expect_status fail "ignore: a finding that is not named fails"
expect_output "not in GOVULNCHECK_IGNORE: GO-2026-0002" "ignore: the unnamed finding is named"
refute_output "passed over" "ignore: nothing is reported as passed over on a failure"

only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001 GO-2026-0002 GO-2026-0003"
expect_status fail "ignore: an entry the scan no longer reports fails"
expect_output "drop the entry: GO-2026-0003" "ignore: the stale entry is named"

scan 0 'No vulnerabilities found.'
only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001"
expect_status fail "ignore: a clean scan makes every entry stale"
expect_output "drop the entry: GO-2026-0001" "ignore: says to drop it"

# A scan that did not run is neither clean nor a finding.
scan 1 'govulncheck: loading packages: cache entry not found'
only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001"
expect_status fail "ignore: a scan that failed to run fails"
expect_output "loading packages" "ignore: its error is shown"
refute_output "drop the entry" "ignore: a failed scan says nothing about stale entries"
refute_output "passed over" "ignore: a failed scan passes nothing over"

# -show verbose lists what a required module merely contains under the same
# heading; only what the code reaches is held against the list.
scan "$REACHED" '=== Symbol Results ===' '' 'Vulnerability #1: GO-2026-0001' '' '=== Package Results ===' '' '=== Module Results ===' '' 'Vulnerability #1: GO-2026-0009' '' 'Your code is affected by 1 vulnerability from 1 module.'
only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001"
expect_status ok "ignore: an ID under Module Results is not a finding"

scan "$REACHED" '{"finding":{"osv":"GO-2026-0001"}}'
only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001"
expect_status fail "ignore: findings in a shape that cannot be read fail"
expect_output "named none under Symbol Results" "ignore: says the output could not be held against the list"

two_reached
reset_calls
only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001 CVE-2026-1234"
expect_status fail "ignore: an entry that is not a Go vulnerability ID is refused"
expect_output "got: CVE-2026-1234" "ignore: the refused entry is named"
refute_run govulncheck "ignore: no scan runs on a refused list"
only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-00x1"
expect_status fail "ignore: an ID with a letter in its number is refused"

# The pinned govulncheck is the one whose findings are read.
pin_tools govulncheck
reset_calls
only_shims go:vuln "GOVULNCHECK_IGNORE=GO-2026-0001"
expect_call "go|tool|govulncheck|./...|" "ignore: a pinned govulncheck runs through go tool"
expect_output "drop the entry: GO-2026-0001" "ignore: and its clean result is what the list is held against"
pin_tools

finish

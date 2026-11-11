#!/usr/bin/env bash
# security: every GO_MODULES entry is scanned in its own directory, a
# directory that is not a Go module is skipped, and one that does not exist is
# an error — never created. Each Go tool is the pinned one before it is
# PATH's.
source "$(dirname "$0")/lib.sh"

shim_go
shim govulncheck 'printf "govulncheck in %s\n" "$(basename "$PWD")" >> "$CALLS"'

mkdir -p "$CONSUMER/api" "$CONSUMER/docs"
printf 'module example.com/api\n' > "$CONSUMER/api/go.mod"

consumer security security "{ GO_MODULES: [api, docs] }"
run_task security:vuln
expect_status ok "vuln: a Go module and a plain directory pass"
expect_call "govulncheck in api" "vuln: the Go module is scanned in its own directory"
expect_output "docs is not a Go module — skipped" "vuln: a directory without go.mod is skipped"

consumer security security "{ GO_MODULES: [api, apii] }"
reset_calls
run_task security:vuln
expect_status fail "vuln: a GO_MODULES entry that does not exist fails"
expect_output "GO_MODULES names apii, which does not exist" "vuln: the missing entry is named"
if [ -e "$CONSUMER/apii" ]; then fail "vuln: the missing directory was created"; else pass "vuln: the missing directory is not created"; fi

# ─── tools: the pinned one first, PATH's after it ────────────────────────────
# PATH holds the shims and the system's tools alone, so a tool installed on
# this machine is not found.
ln -sf "$(command -v task)" "$BIN/task"
only_shims() { PATH="$BIN:/usr/bin:/bin" run_task "$@"; }
consumer security security "{ GO_MODULES: [api, docs] }"

pin_tools govulncheck golangci-lint gosec
reset_calls
only_shims security:vuln "GOVULNCHECK_FLAGS=-show verbose"
expect_status ok "vuln: runs with a pinned govulncheck"
expect_call "go|tool|govulncheck|-show|verbose|./...|" "vuln: a pinned govulncheck runs through go tool, flags split"
refute_run govulncheck "vuln: PATH's govulncheck is passed over for the pinned one"

reset_calls
only_shims security:lint
expect_call "go|tool|golangci-lint|run|--new-from-merge-base=main|./...|" "lint: a pinned golangci-lint runs through go tool"
reset_calls
only_shims security:gosec
expect_call "go|tool|gosec|./...|" "gosec: a pinned gosec runs through go tool"

# GO_TOOL_MODFILE is relative to the include, and each module is entered
# before its tool runs: the path has to survive the cd.
mkdir -p "$CONSUMER/tools"
printf 'module example.com/tools\n' > "$CONSUMER/tools/go.mod"
consumer security security "{ GO_MODULES: [api], GO_TOOL_MODFILE: tools/go.mod }"
reset_calls
only_shims security:vuln
expect_status ok "modfile: runs with GO_TOOL_MODFILE"
expect_call "go|tool|-modfile=/" "modfile: the path reaches go absolute"
expect_call "/consumer/tools/go.mod|govulncheck|./...|" "modfile: it is the include's tools/go.mod, not the module's"

consumer security security "{ GO_MODULES: [api], GO_TOOL_MODFILE: tools/go.mdo }"
reset_calls
only_shims security:vuln
expect_status fail "modfile: one that does not exist is refused"
expect_output "GO_TOOL_MODFILE names tools/go.mdo, which does not exist" "modfile: the missing file is named"
refute_call "govulncheck" "modfile: no scan runs when the file is missing"

# GOLANGCI_LINT_MODFILE: the linter's pin lives apart from the other tools'.
mkdir -p "$CONSUMER/lint"
printf 'module example.com/lint\n' > "$CONSUMER/lint/go.mod"
consumer security security "{ GO_MODULES: [api], GO_TOOL_MODFILE: tools/go.mod, GOLANGCI_LINT_MODFILE: lint/go.mod }"
reset_calls
only_shims security:lint
expect_status ok "lint modfile: runs with both set"
expect_call "/consumer/lint/go.mod|golangci-lint|run|" "lint modfile: golangci-lint is asked of its own go.mod, absolute"
refute_call "/consumer/tools/go.mod|golangci-lint" "lint modfile: not of GO_TOOL_MODFILE"
reset_calls
only_shims security:vuln
expect_call "/consumer/tools/go.mod|govulncheck|./...|" "lint modfile: govulncheck is still asked of GO_TOOL_MODFILE"
consumer security security "{ GO_MODULES: [api], GOLANGCI_LINT_MODFILE: lint/go.mdo }"
reset_calls
only_shims security:lint
expect_status fail "lint modfile: one that does not exist is refused"
expect_output "GOLANGCI_LINT_MODFILE names lint/go.mdo, which does not exist" "lint modfile: the input and the missing file are named"
refute_call "golangci-lint" "lint modfile: no linter runs when the file is missing"

# Neither pinned nor on PATH: a Go module fails the scan, a repository with
# no Go module needs no Go tool at all.
pin_tools
mv "$BIN/govulncheck" "$WORK/"
consumer security security "{ GO_MODULES: [api] }"
only_shims security:vuln
expect_status fail "vuln: no govulncheck anywhere fails a Go module"
expect_output "govulncheck is not installed — go get -tool golang.org/x/vuln/cmd/govulncheck" "vuln: says how to pin govulncheck"
only_shims security:gosec
expect_status fail "gosec: no gosec anywhere fails a Go module"
expect_output "gosec is not installed — go get -tool github.com/securego/gosec/v2/cmd/gosec" "gosec: says how to pin gosec"

# GO_TOOLS_PINNED=1: PATH is asked for nothing, so the golangci-lint it holds
# does not count.
consumer security security "{ GO_MODULES: [api], GO_TOOLS_PINNED: '1' }"
reset_calls
only_shims security:lint
expect_status fail "pinned: an unpinned golangci-lint fails, though PATH has one"
expect_output "golangci-lint is not pinned by a tool directive, and GO_TOOLS_PINNED=1 leaves PATH out" "pinned: says the tool is not pinned and why PATH does not count"
refute_run golangci-lint "pinned: PATH's golangci-lint is not run"
pin_tools golangci-lint
reset_calls
only_shims security:lint
expect_status ok "pinned: a pinned golangci-lint runs"
expect_call "go|tool|golangci-lint|run|" "pinned: it runs through go tool"
pin_tools
consumer security security "{ GO_MODULES: [api], GO_TOOLS_PINNED: 'yes' }"
only_shims security:lint
expect_status fail "pinned: a GO_TOOLS_PINNED that is neither 1 nor 0 is refused"
expect_output "GO_TOOLS_PINNED must be 1 or 0, got: yes" "pinned: says what GO_TOOLS_PINNED takes"
consumer security security "{ GO_MODULES: [api] }"
consumer security security "{ GO_MODULES: [docs] }"
only_shims security:vuln
expect_status ok "vuln: a repository with no Go module passes without govulncheck"
only_shims security:lint
expect_status ok "lint: a repository with no Go module passes without golangci-lint"
mv "$WORK/govulncheck" "$BIN/"

# trivy: one --skip-dirs per listed directory, each a single argument.
shim trivy 'printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"'
consumer security security
reset_calls
run_task security:trivy
expect_status ok "trivy: runs with the default skip list"
expect_call "[--skip-dirs][.claude][--exit-code][1][.]" "trivy: skips .claude by default"
consumer security security "{ TRIVY_SKIP_DIRS: [.claude, 'third party'] }"
reset_calls
run_task security:trivy
expect_call "[--skip-dirs][.claude][--skip-dirs][third party][--exit-code][1][.]" "trivy: each listed directory is one --skip-dirs argument"
expect_call "[config][--exit-code][0][--quiet][--skip-dirs][.claude][--skip-dirs][third party]" "trivy: config skips the same directories"

# The gate's --exit-code comes last, where trivy's last-flag-wins parsing
# keeps it: a consumer's TRIVY_FLAGS cannot switch the gate off.
consumer security security "{ TRIVY_FLAGS: '--exit-code 0' }"
reset_calls
run_task security:trivy
expect_call "[--exit-code][0][--exit-code][1][.]" "trivy: TRIVY_FLAGS cannot override the gate's exit code"

# dockerfile: discovered when unset, linted exactly as named when set, and a
# named file that does not exist is an error — a typo must not lint nothing.
shim hadolint ''
consumer security security
reset_calls
run_task security:dockerfile
expect_status ok "dockerfile: a repository with no Dockerfile passes"
expect_output "no Dockerfile in this repository" "dockerfile: says there was nothing to lint"

mkdir -p "$CONSUMER/docker"
printf 'FROM scratch\n' > "$CONSUMER/docker/Dockerfile"
reset_calls
run_task security:dockerfile
expect_status ok "dockerfile: a discovered Dockerfile is linted"
expect_call "hadolint --failure-threshold error ./docker/Dockerfile" "dockerfile: hadolint runs on the discovered file"

# Several are discovered in order, each an argument of its own.
printf 'FROM scratch\n' > "$CONSUMER/docker/Dockerfile.dev"
reset_calls
run_task security:dockerfile
expect_call "hadolint --failure-threshold error ./docker/Dockerfile.dev" "dockerfile: every discovered Dockerfile is linted, each as a path of its own"
expect_output "./docker/Dockerfile clean" "dockerfile: the first of them is linted as well"
rm -f "$CONSUMER/docker/Dockerfile.dev"

consumer security security "{ DOCKERFILES: [docker/Dockerfile, docker/Dockerfil] }"
reset_calls
run_task security:dockerfile
expect_status fail "dockerfile: a named Dockerfile that does not exist fails"
expect_output "DOCKERFILES names docker/Dockerfil, which does not exist" "dockerfile: the missing file is named"
rm -rf "$CONSUMER/docker"

# ─── vuln: GOVULNCHECK_IGNORE ────────────────────────────────────────────────
# One list for every module: a finding is passed over wherever it turns up,
# and an entry is stale only when no module reports it. What each module's
# scan prints and exits with is read from files named after the module.
export VULN_STATE="$WORK/vuln"
mkdir -p "$VULN_STATE" "$CONSUMER/web"
printf 'module example.com/web\n' > "$CONSUMER/web/go.mod"
# shellcheck disable=SC2016 # the shim's own variables, written literally
shim govulncheck 'm=$(basename "$PWD"); cat "$VULN_STATE/$m.out" 2>/dev/null; exit "$(cat "$VULN_STATE/$m.rc" 2>/dev/null || printf 0)"'
pin_tools
readonly REACHED=3
# scan <module> <exit status> <line...> — what govulncheck reports there.
scan() { m=$1; printf '%s' "$2" > "$VULN_STATE/$m.rc"; shift 2; printf '%s\n' "$@" > "$VULN_STATE/$m.out"; }
scan api "$REACHED" '=== Symbol Results ===' '' 'Vulnerability #1: GO-2026-0001'
scan web "$REACHED" '=== Symbol Results ===' '' 'Vulnerability #1: GO-2026-0002'
found="$CONSUMER/.task/security/vuln-found"

consumer security security "{ GO_MODULES: [api, web] }"
only_shims security:vuln
expect_status fail "ignore: without the input a finding fails, as before"
refute_output "GOVULNCHECK_IGNORE" "ignore: without the input nothing is said of it"
if [ -e "$found" ]; then fail "ignore: without the input a state file was written"; else pass "ignore: without the input no state is kept"; fi

consumer security security "{ GO_MODULES: [api, web], GOVULNCHECK_IGNORE: [GO-2026-0001, GO-2026-0002] }"
only_shims security:vuln
expect_status ok "ignore: each module's finding is named, and the scan passes"
expect_output "passed over, by GOVULNCHECK_IGNORE: GO-2026-0001 GO-2026-0002" "ignore: the IDs passed over are printed"
if [ -e "$found" ]; then fail "ignore: the state file was left behind"; else pass "ignore: the state file is removed"; fi

consumer security security "{ GO_MODULES: [api, web], GOVULNCHECK_IGNORE: [GO-2026-0001] }"
only_shims security:vuln
expect_status fail "ignore: a finding that is not named fails its module"
expect_output "web · not in GOVULNCHECK_IGNORE: GO-2026-0002" "ignore: the module and the unnamed finding are named"

consumer security security "{ GO_MODULES: [api, web], GOVULNCHECK_IGNORE: [GO-2026-0001, GO-2026-0002, GO-2026-0003] }"
only_shims security:vuln
expect_status fail "ignore: an entry no module reports fails"
expect_output "drop the entry: GO-2026-0003" "ignore: the stale entry is named"
refute_output "drop the entry: GO-2026-0001" "ignore: an entry one module still reports is not stale"

scan web 1 'govulncheck: loading packages: cache entry not found'
consumer security security "{ GO_MODULES: [api, web], GOVULNCHECK_IGNORE: [GO-2026-0001, GO-2026-0002] }"
only_shims security:vuln
expect_status fail "ignore: a scan that failed to run fails"
refute_output "drop the entry" "ignore: a failed scan says nothing about stale entries"
refute_output "passed over" "ignore: a failed scan passes nothing over"

# On the command line the input is a string, with the IDs separated by spaces.
consumer security security "{ GO_MODULES: [api] }"
scan api "$REACHED" '=== Symbol Results ===' '' 'Vulnerability #1: GO-2026-0001' 'Vulnerability #2: GO-2026-0002'
only_shims security:vuln "GOVULNCHECK_IGNORE=GO-2026-0001 GO-2026-0002"
expect_status ok "ignore: a string of IDs on the command line passes them over"

consumer security security "{ GO_MODULES: [api], GOVULNCHECK_IGNORE: [GO-2026-0001, CVE-2026-1234] }"
reset_calls
only_shims security:vuln
expect_status fail "ignore: an entry that is not a Go vulnerability ID is refused"
expect_output "got: CVE-2026-1234" "ignore: the refused entry is named"
refute_run govulncheck "ignore: no scan runs on a refused list"

finish

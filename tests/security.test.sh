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

consumer security security "{ DOCKERFILES: [docker/Dockerfile, docker/Dockerfil] }"
reset_calls
run_task security:dockerfile
expect_status fail "dockerfile: a named Dockerfile that does not exist fails"
expect_output "DOCKERFILES names docker/Dockerfil, which does not exist" "dockerfile: the missing file is named"
rm -rf "$CONSUMER/docker"

finish

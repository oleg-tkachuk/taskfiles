#!/usr/bin/env bash
# go: values reach go as data, package lists split into one argument per
# pattern, and verbatim flag inputs still word-split.
source "$(dirname "$0")/lib.sh"

# argv joined with "|", so one argument and two read differently.
argv='printf "%s|" "$0" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"'
shim go "${argv/\$0/go}"
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

finish

#!/usr/bin/env bash
# codegen: GOWORK is off unless a consumer names "auto" — an empty value cannot
# opt in, `default` reads it as unset. buf, sqlc and goimports are each the
# pinned one before PATH's.
source "$(dirname "$0")/lib.sh"

# shellcheck disable=SC2016 # the shim's own GOWORK, written literally
shim_go 'printf "go GOWORK=[%s]\n" "${GOWORK-unset}" >> "$CALLS"'
# _normalise formats what generation wrote; nothing here needs formatting.
shim goimports ':'
shim gofmt ':'

consumer codegen codegen
printf 'module example.com/x\n' > "$CONSUMER/go.mod"

for case in "default|off|" "auto||GOWORK=auto" "empty|off|GOWORK="; do
  IFS="|" read -r label expected arg <<< "$case"
  reset_calls
  run_task codegen:generate ${arg:+"$arg"}
  expect_status ok "generate: runs with GOWORK $label"
  expect_call "go GOWORK=[$expected]" "gowork: $label reaches go as [$expected]"
done

# ─── proto ────────────────────────────────────────────────────────────────────
# PROTO_PATH is shell by contract: a plugin out of a pnpm tree is named with
# the command that finds it.
shim buf 'printf "buf PATH=[%s]\n" "$PATH" >> "$CALLS"'
printf 'version: v2\n' > "$CONSUMER/buf.gen.yaml"

consumer codegen codegen "{ PROTO_PATH: '\$(printf %s /from-shell)' }"
reset_calls
run_task codegen:proto
expect_status ok "proto: runs with a PROTO_PATH that is a command substitution"
expect_call "buf PATH=[/from-shell:" "proto: PROTO_PATH is evaluated by the shell"

consumer codegen codegen "{ PROTO_PATH: '/a dir/bin' }"
reset_calls
run_task codegen:proto
expect_call "buf PATH=[/a dir/bin:" "proto: a PROTO_PATH with a space stays one entry"

consumer codegen codegen "{ PROTO_FORBID: 'gen api/gen' }"
run_task codegen:proto
expect_status ok "proto: runs when no forbidden path exists"
mkdir -p "$CONSUMER/api/gen"
reset_calls
run_task codegen:proto
expect_status fail "proto: refuses when one of several forbidden paths exists"
refute_call "buf " "proto: buf does not run beside a stray copy"
rm -rf "$CONSUMER/api"

# ─── sqlc ─────────────────────────────────────────────────────────────────────
# sqlc's output goes through goimports like every other generator's, at the
# `out:` paths its config names; the gate refuses a SQLC_DIR naming no file.
shim sqlc ':'
shim goimports ':'
cat > "$CONSUMER/sqlc.yaml" <<'YAML'
version: "2"
sql:
  - engine: postgresql
    gen:
      go:
        out: internal/a/gen   # one module
  - engine: postgresql
    gen:
      go:
        out: "internal/b/gen"
YAML

consumer codegen codegen
reset_calls
run_task codegen:sqlc
expect_status ok "sqlc: generates"
expect_call "goimports -w internal/a/gen internal/b/gen" "sqlc: goimports normalises every out: path of sqlc.yaml"

rm "$CONSUMER/sqlc.yaml"
reset_calls
run_task codegen:sqlc
expect_status ok "sqlc: generates without a sqlc.yaml it can read"
refute_call "goimports" "sqlc: no out: path, nothing to normalise"

# ─── tools: the pinned one first, PATH's after it ────────────────────────────
# PATH holds the shims and the system's tools alone, so a tool installed on
# this machine is not found.
ln -sf "$(command -v task)" "$BIN/task"
only_shims() { PATH="$BIN:/usr/bin:/bin" run_task "$@"; }
printf 'version: "2"\nsql:\n  - gen:\n      go:\n        out: internal/a/gen\n' > "$CONSUMER/sqlc.yaml"

pin_tools buf sqlc goimports
consumer codegen codegen "{ GENERATED_DIRS: [internal] }"
reset_calls
only_shims codegen:sqlc "SQLC_FLAGS=--no-remote"
expect_status ok "sqlc: runs with a pinned sqlc"
expect_call "go|tool|sqlc|generate|--no-remote|" "sqlc: a pinned sqlc runs through go tool, flags split"
refute_run sqlc "sqlc: PATH's sqlc is passed over for the pinned one"
expect_call "go|tool|goimports|-w|internal/a/gen|" "sqlc: a pinned goimports normalises the out: paths"
refute_run goimports "sqlc: PATH's goimports is passed over for the pinned one"

reset_calls
only_shims codegen:proto
expect_status ok "proto: runs with a pinned buf"
expect_call "go|tool|buf|generate|--template|buf.gen.yaml|" "proto: a pinned buf runs through go tool"
refute_run buf "proto: PATH's buf is passed over for the pinned one"
expect_call "go|tool|goimports|-w|internal|" "normalise: a pinned goimports runs over GENERATED_DIRS"

reset_calls
only_shims codegen:sqlc "SQLC_MODULE=example.com/sqlc@v1"
expect_call "go|run|example.com/sqlc@v1|generate|" "sqlc: SQLC_MODULE still decides, pinned sqlc or not"
refute_call "go|tool|sqlc|" "sqlc: the pinned sqlc is not run beside SQLC_MODULE"

mkdir -p "$CONSUMER/tools"
printf 'module example.com/tools\n' > "$CONSUMER/tools/go.mod"
reset_calls
only_shims codegen:proto "GO_TOOL_MODFILE=tools/go.mod"
expect_call "go|tool|-modfile=tools/go.mod|buf|generate|" "modfile: the tool is asked of GO_TOOL_MODFILE"
reset_calls
only_shims codegen:proto "GO_TOOL_MODFILE=tools/go.mdo"
expect_status fail "modfile: one that does not exist is refused"
expect_output "GO_TOOL_MODFILE names tools/go.mdo, which does not exist" "modfile: the missing file is named"
refute_call "buf|generate" "modfile: no generator runs when the file is missing"

# Neither pinned nor on PATH: a generator fails, goimports is passed by.
pin_tools
mv "$BIN/buf" "$BIN/sqlc" "$BIN/goimports" "$WORK/"
only_shims codegen:proto
expect_status fail "proto: no buf anywhere fails"
expect_output "buf is not installed" "proto: says buf is not installed"
only_shims codegen:sqlc
expect_status fail "sqlc: no sqlc anywhere fails"
expect_output "sqlc is not installed" "sqlc: says sqlc is not installed"
reset_calls
only_shims codegen:generate
expect_status ok "normalise: no goimports anywhere still generates"
refute_call "goimports|-w" "normalise: no goimports, none run"
mv "$WORK/buf" "$WORK/sqlc" "$WORK/goimports" "$BIN/"
rm -f "$CONSUMER/sqlc.yaml"
consumer codegen codegen

git -C "$CONSUMER" init -q
mkdir -p "$CONSUMER/internal/a/gen"
printf 'package gen\n' > "$CONSUMER/internal/a/gen/q.go"
git -C "$CONSUMER" add internal/a/gen/q.go

consumer codegen codegen "{ SQLC_DIR: ':(glob)internal/**/gen' }"
reset_calls
run_task codegen:sqlc:check
expect_status fail "sqlc:check: refuses a SQLC_DIR that names directories, not files"
expect_output "matches no tracked file" "sqlc:check: says the gate would check nothing"
refute_call "sqlc " "sqlc:check: does not regenerate behind a blind gate"

consumer codegen codegen "{ SQLC_DIR: ':(glob)internal/**/gen/**' }"
reset_calls
run_task codegen:sqlc:check
expect_status ok "sqlc:check: passes when regeneration changes no watched file"
expect_call "sqlc generate" "sqlc:check: regenerates what it watches"

# Without SQLC_DIR the gate watches what sqlc.yaml declares as out:.
printf 'version: "2"\nsql:\n  - gen:\n      go:\n        out: internal/a/gen\n' > "$CONSUMER/sqlc.yaml"
consumer codegen codegen
reset_calls
run_task codegen:sqlc:check
expect_status ok "sqlc:check: watches sqlc.yaml's out: paths when SQLC_DIR is unset"
expect_call "sqlc generate" "sqlc:check: regenerates what the config names"

shim sqlc 'printf "package gen // regenerated\n" > internal/a/gen/q.go'
run_task codegen:sqlc:check
expect_status fail "sqlc:check: stale output under a derived path fails"
expect_output "internal/a/gen/q.go" "sqlc:check: names the file regeneration changed"
shim sqlc ':'
printf 'package gen\n' > "$CONSUMER/internal/a/gen/q.go"

printf 'version: "2"\nsql:\n  - gen:\n      go:\n        out: internal/b/gen\n' > "$CONSUMER/sqlc.yaml"
reset_calls
run_task codegen:sqlc:check
expect_status fail "sqlc:check: an out: path holding no tracked file is refused"
expect_output "internal/b/gen matches no tracked file" "sqlc:check: names the out: path that holds nothing"
refute_call "sqlc " "sqlc:check: does not regenerate behind a blind derived gate"

rm -f "$CONSUMER/sqlc.yaml"
run_task codegen:sqlc:check
expect_status fail "sqlc:check: no SQLC_DIR and no sqlc.yaml is refused"
expect_output "no out: path in sqlc.yaml — set SQLC_DIR" "sqlc:check: says to set SQLC_DIR"

# ─── proto gates and buf.lock ────────────────────────────────────────────────
consumer codegen codegen "{ BUF_INPUT: 'api proto', BUF_LINT_FLAGS: '--error-format json', BUF_FORMAT_FLAGS: '--exclude-path vendor', BUF_DEP_FLAGS: '--debug' }"
reset_calls
run_task codegen:proto:lint
expect_status ok "proto:lint: runs"
expect_call "buf lint --error-format json api proto" "proto:lint: flags split, BUF_INPUT follows them"
reset_calls
run_task codegen:proto:fmt:check
expect_status ok "proto:fmt:check: formatted sources pass"
expect_call "buf format --diff --exit-code --exclude-path vendor api proto" "proto:fmt:check: asks buf for the diff and an exit code, not a rewrite"
refute_call " -w" "proto:fmt:check: never writes"
reset_calls
run_task codegen:proto:deps
expect_status ok "proto:deps: runs"
expect_call "buf dep update --debug api proto" "proto:deps: updates the lock of BUF_INPUT"

shim buf 'exit 100'
run_task codegen:proto:fmt:check
expect_status fail "proto:fmt:check: a file buf format would change fails"
refute_output "buf format clean" "proto:fmt:check: does not report clean on a failure"
run_task codegen:proto:lint
expect_status fail "proto:lint: a lint finding fails"

mv "$BIN/buf" "$WORK/"
only_shims codegen:proto:lint
expect_status fail "proto:lint: no buf anywhere fails"
expect_output "buf is not installed — https://buf.build/docs/installation/" "proto:lint: says how to install buf"
mv "$WORK/buf" "$BIN/"
rm -rf "$CONSUMER/internal" "$CONSUMER/.git"

finish

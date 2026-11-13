#!/usr/bin/env bash
# packer, against the real CLI: the exit codes the tasks read still mean what
# they report, and a name that matches nothing is still a warning beside
# exit 0 — in the words the module looks for, for -only and for -except.
#
# Only the null and file builders are used: they are part of the CLI, so no
# plugin is installed, and nothing is made outside this run's own directory.
source "$(dirname "$0")/../lib.sh"

unset PACKER_LOG PACKER_PLUGIN_PATH
export PACKER_NO_COLOR=1
export CHECKPOINT_DISABLE=1

IMAGES="$CONSUMER/images"
BUILT="$IMAGES/out"
mkdir -p "$IMAGES"

# Two builds under one build block, each leaving a file: which builds ran is
# read off the files there are.
cat > "$IMAGES/files.pkr.hcl" <<'HCL'
variable "content" {
  type    = string
  default = "built"
}

source "file" "one" {
  content = var.content
  target  = "out/one.txt"
}

source "file" "two" {
  content = var.content
  target  = "out/two.txt"
}

build {
  name    = "files"
  sources = ["source.file.one", "source.file.two"]

  post-processor "manifest" {
    name   = "listing"
    output = "out/manifest.json"
  }
}
HCL

# expect_built <name> <case name> / refute_built <name> <case name>
expect_built() { if [ -f "$BUILT/$1.txt" ]; then pass "$2"; else fail "$2: $1 was not built"; fi; }
refute_built() { if [ -e "$BUILT/$1.txt" ]; then fail "$2: $1 was built"; else pass "$2"; fi; }

# packer_here <args...> — the CLI itself in the template's directory, its
# output in $OUT and its exit status in $status.
packer_here() {
  status=0
  (cd "$IMAGES" && packer "$@") > "$OUT" 2>&1 || status=$?
}

consumer pk packer '{ PACKER_DIR: images }'

# ─── fmt ─────────────────────────────────────────────────────────────────────
run_task pk:fmt
expect_status ok "fmt: a formatted template passes"

printf 'content   =   "loose"\n' > "$IMAGES/loose.pkrvars.hcl"
run_task pk:fmt
expect_status fail "fmt: a file not in the canonical format fails"
expect_output "loose.pkrvars.hcl" "fmt: and the CLI lists it"
expect_output "not formatted" "fmt: the CLI's exit code for it is still read as formatting"
if [ "$(cat "$IMAGES/loose.pkrvars.hcl")" = 'content   =   "loose"' ]; then pass "fmt: without rewriting it"; else fail "fmt: the check rewrote the file"; fi

printf 'content =\n' > "$IMAGES/loose.pkrvars.hcl"
run_task pk:fmt
expect_status fail "fmt: a file that does not parse fails"
expect_output "did not complete" "fmt: on an exit code of its own, read as an error"
rm -f "$IMAGES/loose.pkrvars.hcl"

# ─── init, inspect ───────────────────────────────────────────────────────────
run_task pk:init
expect_status ok "init: a template that requires no plugin passes"

run_task pk:inspect
expect_status ok "inspect: shows the template"
expect_output "file.one" "inspect: its builds among the rest"

# ─── validate ────────────────────────────────────────────────────────────────
run_task pk:validate
expect_status ok "validate: a valid template passes"

consumer pk packer '{ PACKER_DIR: images, PACKER_VAR_FLAGS: "-var no_such_variable=1" }'
run_task pk:validate
expect_status fail "validate: a variable the template does not declare fails"
consumer pk packer '{ PACKER_DIR: images }'

mkdir -p "$CONSUMER/empty"
consumer pk packer '{ PACKER_DIR: empty }'
run_task pk:validate
expect_status fail "validate: a directory with no template is still refused by the CLI"
consumer pk packer '{ PACKER_DIR: images }'

# Why ONLY is held to the builds there are. When either of these stops being
# true, the refusal can go.
packer_here validate -only=files.file.no-such .
if [ "$status" = 0 ] && holds "$OUT" "an 'only' option was passed"; then
  pass "the CLI still validates a name that matches no build with a warning and exit 0"
else
  fail "the CLI no longer warns beside exit 0 for a name that matches no build (exit $status) — the module looks for that warning"
fi

packer_here build -only=files.file.one,files.file.no-such .
if [ "$status" = 0 ] && [ -f "$BUILT/one.txt" ] && [ ! -e "$BUILT/two.txt" ]; then
  pass "the CLI still builds the names that match and exits 0 when another matches nothing"
else
  fail "the CLI no longer builds past a name that matches nothing (exit $status) — ONLY need not be refused"
fi
rm -rf "$BUILT"

# This passing is also the CLI still giving the warning for the name the
# module asks it about: without it, every ONLY is refused.
run_task pk:validate ONLY=files.file.one
expect_status ok "validate: ONLY naming a build passes"

run_task pk:validate ONLY="files.*"
expect_status ok "validate: so does a pattern that matches builds"

run_task pk:validate ONLY="files.file.one files.file.no-such"
expect_status fail "validate: a name in ONLY that matches no build is refused"
expect_output "files.file.no-such" "validate: and named"

# A source's own name is not the build's where the build block has a name.
run_task pk:validate ONLY=file.one
expect_status fail "validate: a name short of its build block's is refused"

# The same for EXCEPT, which fails the other way: what was to be left out is
# built.
packer_here validate -except=files.file.one,files.file.no-such .
if [ "$status" = 0 ] && holds "$OUT" "an 'except' option was passed"; then
  pass "the CLI still warns beside exit 0 when one name in -except matches nothing"
else
  fail "the CLI no longer warns beside exit 0 for an -except that matches nothing (exit $status) — the module looks for that warning"
fi

packer_here build -except=files.file.no-such .
if [ "$status" = 0 ] && [ -f "$BUILT/one.txt" ] && [ -f "$BUILT/two.txt" ]; then
  pass "the CLI still builds everything, and exits 0, when -except matches nothing"
else
  fail "the CLI no longer builds past an -except that matches nothing (exit $status) — EXCEPT need not be refused"
fi
rm -rf "$BUILT"

# A build that -only has already left out is, to -except, a name that matches
# nothing: why EXCEPT is said to match among the builds ONLY names.
packer_here validate -only=files.file.one -except=files.file.two .
if holds "$OUT" "an 'except' option was passed"; then
  pass "the CLI still matches -except only among the builds -only has left"
else
  fail "the CLI now matches -except against every build — EXCEPT need not be read against ONLY"
fi

run_task pk:validate EXCEPT=files.file.one
expect_status ok "validate: EXCEPT naming a build passes"

run_task pk:validate EXCEPT=listing
expect_status ok "validate: so does EXCEPT naming a post-processor"

run_task pk:validate EXCEPT="files.file.one files.file.no-such"
expect_status fail "validate: a name in EXCEPT that matches nothing is refused"
expect_output "files.file.no-such" "validate: and named"

run_task pk:validate ONLY="files.*" EXCEPT=files.file.two
expect_status ok "validate: ONLY and EXCEPT together pass"

# ─── build ───────────────────────────────────────────────────────────────────
run_task pk:build ONLY="files.file.one files.file.no-such"
expect_status fail "build: a name in ONLY that matches no build is refused"
refute_built one "build: and the build it does match is not built"

run_task pk:build ONLY=files.file.one
expect_status ok "build: builds the build ONLY names"
expect_built one "build: its artifact is there"
refute_built two "build: and no other build's"
rm -rf "$BUILT"

run_task pk:build EXCEPT=files.file.no-such
expect_status fail "build: a name in EXCEPT that matches nothing is refused"
refute_built one "build: and what it was meant to leave out is not built"

run_task pk:build EXCEPT=files.file.one
expect_status ok "build: leaves out the build EXCEPT names"
refute_built one "build: its artifact is not there"
expect_built two "build: and the other build's is"
rm -rf "$BUILT"

run_task pk:build EXCEPT=listing
expect_status ok "build: leaves out a post-processor EXCEPT names"
expect_built one "build: with every build built"
if [ -e "$BUILT/manifest.json" ]; then fail "build: the post-processor EXCEPT named ran"; else pass "build: and that post-processor's output is not there"; fi
rm -rf "$BUILT"

consumer pk packer '{ PACKER_DIR: images, PACKER_VAR_FLAGS: "-var content=given" }'
run_task pk:build
expect_status ok "build: with no ONLY, builds every build"
expect_built two "build: the second among them"
if [ "$(cat "$BUILT/one.txt")" = given ]; then pass "build: PACKER_VAR_FLAGS reach the template"; else fail "build: the variable did not reach the template"; fi
rm -rf "$BUILT"

# One build that fails beside one that does not: exit 1 for the lot, and the
# one that finished keeps what it made.
PARTIAL="$CONSUMER/partial"
mkdir -p "$PARTIAL"
cat > "$PARTIAL/partial.pkr.hcl" <<'HCL'
source "file" "kept" {
  content = "kept"
  target  = "out/kept.txt"
}

source "null" "failing" {
  communicator = "none"
}

build {
  sources = ["source.file.kept", "source.null.failing"]

  provisioner "shell-local" {
    only   = ["null.failing"]
    inline = ["exit 7"]
  }
}
HCL
consumer pk packer '{ PACKER_DIR: partial }'
run_task pk:build
expect_status fail "build: one build failing among others fails"
expect_output "artifacts" "build: the CLI's exit code for it is read as a failure"
if [ -f "$PARTIAL/out/kept.txt" ]; then
  pass "build: and the build that finished keeps its artifact"
else
  fail "build: the build that finished left nothing — a failure may now undo the others"
fi

finish

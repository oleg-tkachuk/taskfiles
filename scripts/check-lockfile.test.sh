#!/usr/bin/env bash
# Cases for check-lockfile.sh: what it must report and what it must let pass.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# npm is kept off the network and off this machine's cache, so a case reads
# the same wherever it runs: whether a lock satisfies its manifest is judged
# from the two files, and only the naming of what is wrong needs a registry.
# That part is tested further down, against an npm that says what npm says.
export npm_config_offline=true
export npm_config_cache="$work/npm-cache"
export npm_config_update_notifier=false

failures=0

readonly LOCKED=1.3.0
readonly OTHER=1.2.0

# manifest <directory> <dependency>=<version>... — a package.json there.
manifest() {
  dir=$1; shift
  mkdir -p "$work/$dir"
  {
    printf '{ "name": "fixture", "private": true, "devDependencies": {'
    sep=''
    for dep in "$@"; do printf '%s "%s": "%s"' "$sep" "${dep%%=*}" "${dep#*=}"; sep=','; done
    printf ' } }\n'
  } > "$work/$dir/package.json"
}

# lock <directory> — a lock file there that holds left-pad at $LOCKED alone.
lock() {
  cat > "$work/$1/package-lock.json" <<JSON
{
  "name": "fixture",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": { "name": "fixture", "devDependencies": { "left-pad": "$LOCKED" } },
    "node_modules/left-pad": { "version": "$LOCKED", "resolved": "https://registry.npmjs.org/left-pad/-/left-pad-$LOCKED.tgz", "dev": true }
  }
}
JSON
}

# expect <reported|clean> <name> [text the report must hold] -- <directory>...
expect() {
  want=$1 name=$2 text=''
  shift 2
  if [ "$1" != -- ]; then text=$1; shift; fi
  shift
  dirs=()
  for d in "$@"; do dirs+=("$work/$d"); done
  if bash "$here/check-lockfile.sh" "${dirs[@]}" > "$work/out" 2>&1; then got=clean; else got=reported; fi
  if [ "$got" = "$want" ] && TEXT=$text awk 'index($0, ENVIRON["TEXT"]) { found = 1 } END { exit !found && ENVIRON["TEXT"] != "" }' "$work/out"; then
    printf '%s\n' "✔ $name: $got"
  else
    printf '%s\n' "✖ $name: want $want${text:+ naming '$text'}, got $got" >&2
    cat "$work/out" >&2
    failures=$((failures + 1))
  fi
}

manifest in-sync "left-pad=$LOCKED"; lock in-sync
expect clean a-lock-that-satisfies-its-manifest -- in-sync
if [ -e "$work/in-sync/node_modules" ]; then
  printf '%s\n' "✖ nothing-is-installed: node_modules was created" >&2
  failures=$((failures + 1))
else
  printf '%s\n' "✔ nothing-is-installed"
fi

# The bump that moves package.json and leaves the lock where it was.
manifest behind "left-pad=$OTHER"; lock behind
expect reported a-lock-behind-its-manifest "behind: package-lock.json does not satisfy package.json" -- behind

manifest missing "left-pad=$LOCKED" "right-pad=$LOCKED"; lock missing
expect reported a-dependency-the-lock-lacks "missing: package-lock.json does not satisfy package.json" -- missing

manifest no-lock "left-pad=$LOCKED"
expect reported a-manifest-with-no-lock "no-lock: no package-lock.json" -- no-lock

mkdir -p "$work/no-manifest"; lock no-manifest
expect reported a-lock-with-no-manifest "no-manifest: no package.json" -- no-manifest

# Every directory is judged: a good one first does not let a bad one pass,
# and a bad one first does not stop the rest being reported.
expect reported a-bad-directory-after-a-good-one "behind: " -- in-sync behind
expect reported every-bad-directory-is-reported "no-lock: " -- behind no-lock

expect reported no-directory-at-all "nothing was checked" --

# ─── what is reported of a refusal ──────────────────────────────────────────
# An npm that refuses the way npm does, with the lines in $NPM_SAYS.
mkdir -p "$work/bin"
printf '%s\n' '#!/usr/bin/env bash' 'cat "$NPM_SAYS" >&2' 'exit 1' > "$work/bin/npm"
chmod +x "$work/bin/npm"
export NPM_SAYS="$work/npm-says"
refusing() { PATH="$work/bin:$PATH" expect "$@"; }

printf '%s\n' 'npm error code EUSAGE' 'npm error' \
  "npm error Invalid: lock file's left-pad@$LOCKED does not satisfy left-pad@$OTHER" \
  "npm error Missing: right-pad@$LOCKED from lock file" > "$NPM_SAYS"
refusing reported what-is-behind-is-named "    lock file's left-pad@$LOCKED does not satisfy left-pad@$OTHER" -- in-sync
refusing reported what-is-missing-is-named "    right-pad@$LOCKED from lock file" -- in-sync
if awk '/EUSAGE/ { found = 1 } END { exit !found }' "$work/out"; then
  printf '%s\n' "✖ the-rest-of-npm's-output-is-left-out: it was printed" >&2
  failures=$((failures + 1))
else
  printf '%s\n' "✔ the-rest-of-npm's-output-is-left-out"
fi

# A refusal that names nothing is shown whole.
printf '%s\n' 'npm error code ENOTCACHED' 'npm error request to the registry failed' > "$NPM_SAYS"
refusing reported a-refusal-that-names-nothing-is-shown "    npm error code ENOTCACHED" -- in-sync

[ "$failures" = 0 ]

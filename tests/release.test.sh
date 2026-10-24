#!/usr/bin/env bash
# release: a value that names the image, the chart or a path reaches docker and
# helm as one argument of data, never as shell; the *_FLAGS inputs are shell
# by contract and still word-split.
source "$(dirname "$0")/lib.sh"

readonly VERSION=1.2.3

# Besides the "<name> <argv>" line lib.sh logs, each shim logs its argv one
# bracket per argument, so a test can tell one argument from several.
# shellcheck disable=SC2016 # the shim's own $@, written literally
readonly ARGV='printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"'
# Nothing is in the local image store, so image:build always builds.
# shellcheck disable=SC2016 # the shim's own $1 and $2, written literally
shim docker "$ARGV"'
case "$1 $2" in "image inspect") exit 1 ;; esac'
shim helm "$ARGV"
# doctor probes the registry; a payload host must not reach DNS.
shim curl 'printf 000'

# payload <marker> — a command substitution that creates $WORK/<marker> if a
# shell ever evaluates it. ${IFS} stands in for the space a YAML key would trim.
payload() { printf '%s' "\$(touch\${IFS}$WORK/$1)"; }

# expect_inert <marker> <case name> — the payload did not run.
expect_inert() {
  if [ -e "$WORK/$1" ]; then fail "$2: the payload ran"; else pass "$2"; fi
}

# A chart and a Dockerfile at the default paths, for the cases that do not
# move them.
mkdir -p "$CONSUMER/deploy/chart"
printf 'name: app\n' > "$CONSUMER/deploy/chart/Chart.yaml"
printf 'FROM scratch\n' > "$CONSUMER/Dockerfile"

# ─── image:build ──────────────────────────────────────────────────────────────
# build_with <input> <marker> <expected --tag> — builds with <input> set to the
# payload and checks the tag reached docker as a single argument.
build_with() {
  input=$1 marker=$2 tag=$3
  name="PROJECT_NAME: app, "
  [ "$input" = PROJECT_NAME ] && name=
  consumer release release "{ ${name}APP_VERSION: $VERSION, $input: '$(payload "$marker")' }"
  reset_calls
  run_task release:image:build
  expect_status ok "image:build: $input with a command substitution builds"
  expect_inert "$marker" "image:build: $input is not run as shell"
  expect_call "[--tag][$tag]" "image:build: $input reaches docker as one argument"
}

p=$(payload pwned-project)
build_with PROJECT_NAME pwned-project "localhost:5000/$p:$VERSION"
p=$(payload pwned-ns)
build_with IMAGE_NAMESPACE pwned-ns "localhost:5000/$p/app:$VERSION"
p=$(payload pwned-registry)
build_with REGISTRY pwned-registry "$p/app:$VERSION"

p=$(payload pwned-dockerfile)
mkdir -p "$(dirname "$CONSUMER/$p")"
printf 'FROM scratch\n' > "$CONSUMER/$p"
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, DOCKERFILE: '$p' }"
reset_calls
run_task release:image:build
expect_status ok "image:build: DOCKERFILE with a command substitution builds"
expect_inert pwned-dockerfile "image:build: DOCKERFILE is not run as shell"
expect_call "[--file][$p]" "image:build: DOCKERFILE reaches docker as one argument"

consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, DOCKER_BUILD_FLAGS: '--pull --build-arg X=1' }"
reset_calls
run_task release:image:build
expect_status ok "image:build: DOCKER_BUILD_FLAGS builds"
expect_call "[--pull][--build-arg][X=1][.]" "image:build: DOCKER_BUILD_FLAGS is word-split"

# ─── chart ────────────────────────────────────────────────────────────────────
p=$(payload pwned-chart)
mkdir -p "$CONSUMER/$p"
printf 'name: app\n' > "$CONSUMER/$p/Chart.yaml"

consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, CHART_DIR: '$p', HELM_LINT_FLAGS: '--strict --quiet' }"
reset_calls
run_task release:chart:lint
expect_status ok "chart:lint: CHART_DIR with a command substitution lints"
expect_inert pwned-chart "chart:lint: CHART_DIR is not run as shell"
expect_call "[lint][--strict][--quiet][$p]" "chart:lint: CHART_DIR is one argument, HELM_LINT_FLAGS is word-split"

reset_calls
run_task release:chart:package
expect_status ok "chart:package: CHART_DIR with a command substitution packages"
expect_inert pwned-chart "chart:package: CHART_DIR is not run as shell"
expect_call "[package][$p][--version][$VERSION]" "chart:package: CHART_DIR reaches helm as one argument"

p=$(payload pwned-chart-name)
consumer release release "{ PROJECT_NAME: '$p', APP_VERSION: $VERSION }"
reset_calls
run_task release:chart:package
expect_status ok "chart:package: PROJECT_NAME with a command substitution packages"
expect_inert pwned-chart-name "chart:package: PROJECT_NAME is not run as shell"
expect_output "packaged $p-$VERSION.tgz" "chart:package: PROJECT_NAME is printed as text"

# ─── image:push: IMAGE_LATEST ─────────────────────────────────────────────────
# The image is in the local store here, so push gets past its precondition.
# Asked for its repo digests, it holds one per registry it was pushed to, as
# docker does: ours, and the same image under another repository.
readonly DIGEST=sha256:1111111111111111111111111111111111111111111111111111111111111111
export DIGEST
# shellcheck disable=SC2016 # the shim's own $DIGEST and $*, written literally
readonly DIGESTS='case "$*" in *--format*) printf "%s\n" "other.example/app@sha256:2222222222222222222222222222222222222222222222222222222222222222" "${FAKE_REPO:-localhost:5000/app}@$DIGEST" ;; esac'
shim docker "$ARGV
$DIGESTS"
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION }"
for case in "unset|0|" "1|1|IMAGE_LATEST=1" "0|0|IMAGE_LATEST=0"; do
  IFS="|" read -r label pushes arg <<< "$case"
  reset_calls
  run_task release:image:push ${arg:+"$arg"}
  expect_status ok "image:push: IMAGE_LATEST $label pushes"
  if [ "$pushes" = 1 ]; then
    expect_call "docker push localhost:5000/app:latest" "image:push: IMAGE_LATEST $label pushes :latest"
  else
    refute_call ":latest" "image:push: IMAGE_LATEST $label keeps :latest back"
  fi
done
reset_calls
run_task release:image:push IMAGE_LATEST=false
expect_status fail "image:push: IMAGE_LATEST=false is refused"
refute_call "docker push" "image:push: nothing is pushed on a refused IMAGE_LATEST"

# ─── image:push: the digest it pushed ─────────────────────────────────────────
# Recorded per version, for cosign to sign the image by digest rather than by a
# tag that can move between the push and the signature.
digest_file="$CONSUMER/.task/release/$VERSION.digest"
rm -rf "$CONSUMER/.task/release"
run_task release:image:push
expect_status ok "image:push: records the digest it pushed"
if [ "$(cat "$digest_file" 2>/dev/null)" = "localhost:5000/app@$DIGEST" ]; then
  pass "image:push: the digest file holds this repository's digest"
else
  fail "image:push: the digest file holds this repository's digest"
fi

# Docker Hub names are recorded short: docker.io/acme/app is acme/app there.
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, REGISTRY: docker.io, IMAGE_NAMESPACE: acme }"
rm -rf "$CONSUMER/.task/release"
FAKE_REPO=acme/app run_task release:image:push
if [ "$(cat "$digest_file" 2>/dev/null)" = "acme/app@$DIGEST" ]; then
  pass "image:push: a Docker Hub image's digest is found under its short name"
else
  fail "image:push: a Docker Hub image's digest is found under its short name"
fi

# A push docker recorded no digest for is not something to sign later.
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION }"
rm -rf "$CONSUMER/.task/release"
FAKE_REPO=elsewhere/app run_task release:image:push
expect_status fail "image:push: a push with no digest for this repository fails"
expect_output "no digest" "image:push: says no digest was recorded"
if [ -e "$digest_file" ]; then fail "image:push: a digest file was written anyway"; else pass "image:push: no digest file is written"; fi
shim docker "$ARGV"'
case "$1 $2" in "image inspect") exit 1 ;; esac'

# ─── doctor ───────────────────────────────────────────────────────────────────
# Its exit status is not the point here: the payload registry never answers.
p=$(payload pwned-chart)
r=$(payload pwned-doctor-registry)
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION, CHART_DIR: '$p', REGISTRY: '$r' }"
reset_calls
run_task release:doctor
expect_inert pwned-chart "doctor: CHART_DIR is not run as shell"
expect_inert pwned-doctor-registry "doctor: REGISTRY is not run as shell"
expect_output "chart $p → oci://$r/charts/app" "doctor: CHART_DIR and REGISTRY are printed as text"

# "no git history" comes from HEAD naming no commit, never from the sha's
# value: a real commit can abbreviate to 00000000, the placeholder an empty
# history is versioned with.
consumer release release "{ PROJECT_NAME: app }"
run_task release:doctor
expect_output "no git history" "doctor: a tree with no commit has no git history"
expect_output "did not answer" "doctor: a registry that answers neither scheme did not answer"

# A plain-HTTP registry, as the default localhost:5000 one is, answers too.
shim curl 'case "$*" in *https://*) printf 000 ;; *) printf 200 ;; esac'
run_task release:doctor
expect_output "registry localhost:5000 answers" "doctor: a registry answering over plain http answers"
shim curl 'printf 000'
real_git=$(command -v git)
git -C "$CONSUMER" init -q
git -C "$CONSUMER" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
shim git "case \"\$*\" in \"rev-parse --short=8 HEAD\") echo 00000000 ;; *) exec $real_git \"\$@\" ;; esac"
run_task release:doctor
refute_output "no git history" "doctor: a commit whose short sha is 00000000 still has history"
rm -f "$BIN/git"

# The remote lock: Task's checksum of every module fetched over git, and the
# only thing between a moved tag and the build. Ignored with the rest of
# .task/, it protects nobody else's checkout.
run_task release:doctor
refute_output "remote lock" "doctor: no remote lock, nothing to say about one"
mkdir -p "$CONSUMER/.task/remote"
printf 'abc\n' > "$CONSUMER/.task/remote/git.github.com.release.0123.checksum"
printf '.task/\n' > "$CONSUMER/.gitignore"
run_task release:doctor
expect_output "remote lock .task/remote is ignored by git" "doctor: an ignored remote lock is reported"
printf '.task/*\n!.task/remote/\n' > "$CONSUMER/.gitignore"
run_task release:doctor
expect_output "remote lock .task/remote is not committed" "doctor: an uncommitted remote lock is reported"
git -C "$CONSUMER" add .gitignore .task/remote
git -C "$CONSUMER" -c user.name=t -c user.email=t@example.invalid commit -q -m lock
run_task release:doctor
expect_output "remote lock .task/remote is committed" "doctor: a committed remote lock is reported as such"
rm -rf "$CONSUMER/.git" "$CONSUMER/.gitignore" "$CONSUMER/.task/remote"

# ─── image:gc ─────────────────────────────────────────────────────────────────
# A prune that could not run is not a trimmed cache.
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION }"
shim docker 'case "$1 $2" in "buildx prune") exit 1 ;; esac'
run_task release:image:gc
expect_status fail "image:gc: a build cache that could not be pruned fails"
refute_output "build cache trimmed" "image:gc: does not report a trim that never happened"
shim docker ''
run_task release:image:gc
expect_status ok "image:gc: a prune that ran passes"
expect_output "build cache trimmed to 8GB" "image:gc: reports the floor it trimmed to"

# ─── chart:render ─────────────────────────────────────────────────────────────
# helm template prints whatever $WORK/render.src holds.
shim helm 'cat "$WORK/render.src"'
export WORK
consumer release release "{ PROJECT_NAME: app, APP_VERSION: $VERSION }"

printf 'kind: ServiceAccount\nautomountServiceAccountToken: true---\nkind: Deployment\n' > "$WORK/render.src"
run_task release:chart:render
expect_status fail "chart:render: a separator glued to the line above is refused"
expect_output "broken multi-doc YAML separator" "chart:render: the glued separator is named"

printf 'kind: Secret\nstringData:\n  ca.crt: |\n    -----BEGIN CERTIFICATE-----\n    MIIB\n    -----END CERTIFICATE-----\n' > "$WORK/render.src"
run_task release:chart:render
expect_status ok "chart:render: a PEM block is not a glued separator"

finish

# Changelog

Notable changes to the shared task library, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/): consumers pin `?ref=vX.Y.Z`, so a rename or a
removal is a major bump — these modules are a public API.

This file is **not** generated. The GitHub release notes already list the
commits — `release.yml` builds them with `--generate-notes` — and repeating
that here would add nothing. What a generator cannot write is the half that
matters to someone upgrading: which names changed, what to set now that a
default is gone, and what to replace a removed task with. That is what lives
here, and the release gate refuses a tag with no entry.

## [Unreleased]

Nothing yet.

## [1.1.1] — 2026-09-07

Nothing in the modules changed. A consumer moving the ref from `v1.1.0` gets
byte-identical behaviour and has nothing to do; the tag exists so the docs and
the release tooling below have a version that names them.

### Changed

- The documented include alias is now the module's own name — `python:` for the
  python module, `uv:` for uv, where both examples said `py:`. The alias is what
  names the tasks it brings in, so `py:` produced a `py:test` that no module of
  that name defines, and meant two different modules in two different examples.
  Only the samples changed; nothing constrains what a consumer calls an include.
- One example registry hostname across the documentation, `registry.example.com`
  — RFC 2606 reserves it for this, so a sample can never resolve to something
  real.

### Internal

- A release is refused when `main` does not contain the tagged commit, so a tag
  cut on a side branch cannot publish a tree that CI on main never saw.
- Generated release notes are shaped by `.github/release.yml`, and workflow step
  names now say whether each one sets up, guards, verifies or publishes.

## [1.1.0] — 2026-09-07

### Added

- `release:doctor` — a pre-flight report that answers, in one pass, whether
  what a component declares actually resolves: the version, the chart and its
  full OCI path, the Dockerfile, the named build contexts and the registry. It
  is a report rather than a gate chain, so it prints every problem at once
  instead of stopping at the first, and exits non-zero when a finding is
  fatal. Run it before a deploy, or when one failed for a reason that named
  the symptom rather than the cause.

  It checks the mistakes that actually happen: a `DOCKERFILE` resolved against
  `DOCKER_CONTEXT` instead of the component directory; a `CHART_NAME` that
  disagrees with `Chart.yaml#name`, so the push looks for a tarball helm never
  wrote; a `COPY --from=NAME` naming neither a build stage nor a context passed
  in `DOCKER_BUILD_FLAGS`, which BuildKit reads as an image and reports as a
  registry permission error; an underivable version; an unreachable registry.

  Nothing to set — it reads the variables the module already has.

### Fixed

- The paired skip notices in `release:image:build`, `release:chart:push` and
  `k8s:restart` told the truth about the wrong moment. The task doing the work
  ran first, and it changes the state its partner inspects, so a build logged
  `built X` and `X already built — skipping` back to back. The notice is now
  evaluated first, on the state before anything ran.
- `release:image:build` also expressed its skip condition as two `status:`
  entries, which Task ANDs, where staying quiet requires a disjunction. A clean
  tree with no image reported `already built` for an image that did not exist.

  Both are behaviour fixes inside existing tasks; no names or inputs changed.

## [1.0.0] — 2026-09-06

First release.

### Added

- `release` — the publish chain: version derivation, image build and push,
  chart lint/render/package/push, and `deploy` doing all three in order. It
  talks to no cluster, so a repository that only publishes needs this and
  nothing else.
- `k8s` — restart, logs, status, `helm upgrade --install`, port-forward.
  Independent of `release`, for a repository that operates a cluster it does
  not build for.
- `go`, `python`, `uv`, `node` — build, test, lint, format and dependency bumps
  per ecosystem. `python` and `uv` share a task surface, so moving between them
  is one include line.
- `compose` — the local dependency stack, waiting on health checks.
- `monorepo` — run one target across every component, with a registry
  preflight before a deploy fan-out.
- `security` — govulncheck, golangci-lint limited to findings new since a base
  branch, gitleaks, trivy, buf breaking.
- `cosign` — sign the published image and chart, attest an SPDX SBOM, verify
  both.
- `argocd` — hard-refresh the applications a deploy republished, because a
  push to the registry does not reach the cluster until Argo drops its cached
  chart.
- `auth` — mint a local-development JWT.
- `runtime/{docker,orbstack,minikube,kind,k3d}` — make a locally built image
  runnable by a local cluster. Same three tasks in each, so switching runtime
  is one include line.

### Notes for consumers

- An include names the module directory, and one variable carries the tag:

  ```yaml
  vars:
    TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git//'
    TASKLIB_REF: '?ref=v1.0.0'
  includes:
    release: { taskfile: '{{.TASKLIB}}release{{.TASKLIB_REF}}', dir: . }
  ```

  A checkout beside your repository sets `TASKLIB: ../taskfiles/` and leaves
  `TASKLIB_REF` undefined — an undeclared variable renders as nothing, so the
  include lines are the same either way.
- Versions derive from the **committer** timestamp, so a clean tree publishes
  the same version on every run. That is what makes `deploy` idempotent: an
  image already built for this commit is not rebuilt, and a chart version
  already in the registry is not re-pushed. Both say so rather than going
  quiet.
- The scheme is timestamp-first (`<base>-dev.<ts>.g<sha>`) because SemVer
  compares pre-release identifiers left to right — a sha-first form lets an
  alphabetically larger sha from an older commit shadow a newer build.
- No floating `:latest` is pushed. Charts resolve their tag from the chart's
  appVersion, which the deploy stamps with the version it tagged the image
  with.
- Defaults assume nothing about one particular setup: the registry is
  `localhost:5000`, timestamps are UTC, `golangci-lint` measures against
  `main`, and `python3` is whatever the host resolves. Set `REGISTRY`,
  `TIMEZONE`, `BASE` and `PY` for yours.

[1.1.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.1.1
[1.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.1.0
[1.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.0.0

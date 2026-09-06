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

[1.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.0.0

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

## [3.5.1] — 2026-09-06

No module changed — a consumer pinning this instead of 3.5.0 sees the same
tasks and the same behaviour.

### Fixed

- The release workflow interpolated `${{ }}` values into `run:` scripts, which
  are substituted as text before bash parses the line. Git allows `$`,
  backticks and `;` in a tag name, so a tag could have run as a command with
  the workflow's token. Inputs arrive through `env` now.

### Added

- This changelog, and a release gate that refuses a tag with no entry.
- `zizmor` audits the workflows in CI and in the pre-commit hook. It found the
  actions pinned to mutable tags (now commit SHAs, with Dependabot moving
  them), a checkout leaving its credential in `.git/config`, and a release
  workflow with no concurrency group.

## [3.5.0] — 2026-09-06

### Added

- MIT licence. Without one the repository was "all rights reserved" and nobody
  could legally use or vendor it.

### Fixed

- `cosign` wrote its SBOM to a path that was not the file `mktemp` created, so
  the temp file leaked and the trap cleaned up the wrong path. It now creates a
  private `mktemp -d` directory and writes inside it — no leak, and no
  predictable name in a world-writable `/tmp`.

## [3.4.0] — 2026-09-06

### Changed

- Every internal var carries its own module's prefix — `_REL_IMAGE`, `_GO_PKG`,
  `_CS_KEY`, `_RT_CTX` — so two modules can never mean different things by the
  same name. `check:vars` enforces it.
- `runtime/*` and `cosign` read `_REL_VERSION` and `_REL_IMAGE` from `release`
  instead of deriving the image path a second time.
- `python:format` and `uv:format` are `fmt`, matching `go:fmt`. `format` stays
  as an alias, so nothing breaks.

Internal names only — no consumer sets them.

## [3.3.0] — 2026-09-06

### Added

- A `README.md` in every module, linked from the index: inputs with defaults,
  the task list, a worked example with real output, and the decisions that look
  arbitrary without their reason.

## [3.2.0] — 2026-09-06

### Added

- `cosign/` — sign the published image and chart, attest an SPDX SBOM through
  syft, verify both. Include it beside `release` and chain `sign:all` after
  `release:deploy`.

  A missing key or a missing syft is an error, not a skip: an artifact that is
  quietly unsigned is the failure the module exists to prevent. Turn it off
  deliberately with `COSIGN_SIGN=0`.

## [3.1.0] — 2026-09-06

### Added

- `uv/` — the same task surface as `python/`, backed by uv. A project moving
  between them changes one include line.

## [3.0.0] — 2026-09-06

### Changed — BREAKING

- `service` is split into `release` (version, image, chart, `deploy`) and `k8s`
  (restart, logs, status, upgrade, port-forward). Neither half called the
  other: a publish-only CI job was carrying five kubectl tasks it had no
  kubeconfig for.

**Migration.** Replace the one include with two, and rename the references:

```yaml
includes:
  release: { taskfile: '{{.TASKLIB}}/release{{.TASKLIB_REF}}', dir: . }
  k8s:     { taskfile: '{{.TASKLIB}}/k8s{{.TASKLIB_REF}}', dir: . }
```

| Was | Now |
|---|---|
| `svc:deploy` | `release:deploy` |
| `svc:version`, `svc:image:*`, `svc:chart:*` | `release:…` |
| `svc:k8s:restart` and friends | `k8s:restart` |
| `svc:info` | `release:metadata` (alias `info` kept) |

## [2.0.0] — 2026-09-06

### Changed — BREAKING

- Each module is a directory: includes name `{{.TASKLIB}}/service`, not
  `{{.TASKLIB}}/service.yaml`.
- Defaults no longer assume one particular setup. The registry is
  `localhost:5000`, the build timestamp is UTC, `golangci-lint` measures new
  findings against `main`, `python3` is whatever the host resolves, and no
  buildx builder is named.

### Removed — BREAKING

- `image:build:local`, which ran `eval $(minikube docker-env)` — one runtime's
  answer to a question every local cluster answers differently.

### Added

- `runtime/{docker,orbstack,minikube,kind,k3d}` — same `check` / `image:load` /
  `install` in each, so switching runtime is one include line.

**Migration.** Drop the `.yaml` from every include path, and set what the old
defaults gave you: `REGISTRY`, `TIMEZONE`, `BASE`, `PY`, `BUILDX_BUILDER`.
Replace `svc:image:build:local` with `release:image:build` plus
`local:image:load` from the runtime module for your cluster.

## [1.1.0] — 2026-09-06

### Added

- `auth/` — mint a local-development JWT.

### Changed

- `image:build`, `chart:push` and `k8s:restart` say when they skip. A silent
  skip reads exactly like a task that did nothing.

## [1.0.0] — 2026-09-06

### Added

- The first modules: `service`, `go`, `python`, `node`, `compose`, `monorepo`,
  `security`, `argocd` — one implementation of what had been copy-pasted into
  39 Taskfiles.

[3.5.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.5.1
[3.5.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.5.0
[3.4.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.4.0
[3.3.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.3.0
[3.2.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.2.0
[3.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.1.0
[3.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.0.0
[2.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v2.0.0
[1.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.1.0
[1.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.0.0

# taskfiles

[![release](https://img.shields.io/github/v/release/oleg-tkachuk/taskfiles?sort=semver&label=release)](https://github.com/oleg-tkachuk/taskfiles/releases/latest)
[![ci](https://github.com/oleg-tkachuk/taskfiles/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/oleg-tkachuk/taskfiles/actions/workflows/ci.yml)
[![Task 3.53+](https://img.shields.io/badge/Task-3.53%2B-29BEB0?logo=task&logoColor=white)](https://taskfile.dev)
[![license: MIT](https://img.shields.io/github/license/oleg-tkachuk/taskfiles?label=license)](LICENSE)

Shared [Task](https://taskfile.dev) modules for every service in this
workspace — one implementation of the release chain, the language gates and
the Kubernetes conveniences, instead of a copy per repository.

Requires Task **3.53+** (remote Taskfiles are stable there; no experiment flag).

## Using it

```yaml
version: "3"
silent: true

vars:
  TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git//'
  TASKLIB_REF: '?ref=v1.1.0'
  PROJECT_NAME: billing-api
  IMAGE_NAMESPACE: acme
  K8S_NAMESPACE: acme

includes:
  release: { taskfile: '{{.TASKLIB}}release{{.TASKLIB_REF}}', dir: . }
  k8s:     { taskfile: '{{.TASKLIB}}k8s{{.TASKLIB_REF}}', dir: . }
  go:      { taskfile: '{{.TASKLIB}}go{{.TASKLIB_REF}}', dir: . }

tasks:
  deploy:  { cmds: [{ task: release:deploy }] }
  restart: { cmds: [{ task: k8s:restart }] }
  test:    { cmds: [{ task: go:test }] }
```

`dir: .` is required on every include — it pins the module's commands to the
including component's directory.

Task fetches the modules over git and caches them under `.task/remote/`, asking
for confirmation the first time; in CI pass `--yes` or
`--trusted-hosts github.com`. A private repository needs git to be able to
reach it — `gh auth setup-git`, or an `insteadOf` rewrite carrying a token:

```bash
git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
```

**Pin a tag.** Not a branch, or your build changes when someone else commits —
and never a commit SHA: Task clones with `--depth 1`, and git refuses a bare
SHA with that flag. The tag above is an example; the current one is on the
[releases page](https://github.com/oleg-tkachuk/taskfiles/releases), and
[CHANGELOG.md](CHANGELOG.md) says what moving to it costs.

### Working on the library itself

Point `TASKLIB` at a checkout beside your repository and leave `TASKLIB_REF`
undefined. An undeclared variable renders as nothing, so the include lines are
identical either way and an edit is visible without cutting a tag:

```yaml
vars:
  TASKLIB: ../taskfiles/
```

`TASKLIB_REF` carries the whole query rather than the tag alone because Task
has no `ref:` field on an include — the ref exists only as a URL query — and an
include path substitutes plain `{{.VAR}}` references and evaluates nothing else
there: no `{{if}}`, and no variable whose value is itself a template. The query
has to be literal somewhere, and once in a variable beats once per include
line.

Only the YAML is fetched. Sibling scripts in this repo are **not** downloaded,
which is why every module is self-contained and expresses its logic in Task's
own primitives rather than shelling out to a helper.

## Modules

| Module | Namespace | What it covers |
|---|---|---|
| [`release/`](release/README.md) | `release` | version derivation, image build/push, chart lint/render/package/push, `deploy` |
| [`k8s/`](k8s/README.md) | `k8s` | restart, logs, status, `helm upgrade --install`, port-forward |
| [`go/`](go/README.md) | `go` | build, test (+coverage, +integration, +tagged-compile), lint, fmt, tidy, vuln, dep bumps |
| [`python/`](python/README.md) | `py` | poetry install/test/lint/format/typecheck/lock, dep bumps |
| [`uv/`](uv/README.md) | `py` | the same surface for uv-managed projects — swap the include line |
| [`node/`](node/README.md) | `node` | install, dev, build, lint, test, e2e, verify, generate, dep bumps |
| [`compose/`](compose/README.md) | `dev` | local stack up/down/reset/logs |
| [`monorepo/`](monorepo/README.md) | `all` | run one target across every component, registry preflight |
| [`security/`](security/README.md) | `sec` | govulncheck, golangci-lint, gitleaks, trivy, buf breaking |
| [`cosign/`](cosign/README.md) | `sign` | sign the published image and chart, attest an SBOM, verify both |
| [`argocd/`](argocd/README.md) | `argocd` | hard-refresh the apps a deploy just republished |
| [`auth/`](auth/README.md) | `auth` | mint a local-dev JWT |
| [`runtime/*`](runtime/README.md) — docker, orbstack, minikube, kind, k3d | `local` | run a locally built image on a local cluster, no registry |

### Local clusters

`svc:image:build` writes to whatever Docker daemon the host talks to. Whether
that image is then visible to your cluster depends on the cluster: OrbStack and
Docker Desktop share the host's store and need nothing, minikube and kind and
k3d each have their own and need an import step. That difference is the only
thing the `runtime/*` modules contain, and they all expose the same three
tasks — `check`, `image:load`, `install` — so moving between them is one line:

```yaml
includes:
  local: { taskfile: '{{.TASKLIB}}runtime/orbstack{{.TASKLIB_REF}}', dir: . }
```

Include one alongside `service`, not instead of it: `local:image:load` moves
what `release:image:build` produced, and `local:install` helm-installs the
chart from disk against it with `pullPolicy=IfNotPresent`.

Each module is a directory holding a `Taskfile.yaml` and a `README.md` — the
table above links to them, and each one documents that module's inputs, its
tasks and a worked example. An include names the directory, so the layout inside
a module stays the module's own business.

`release` and `k8s` are two modules rather than one for the same reason a
publish-only CI job has no kubeconfig: neither half needs the other. Include
whichever the component actually does.

That split has to happen at *your* include, not inside a module. A module that
includes its own parts hands those parts the **library's** working directory
rather than yours — only the include you write carries `dir: .` — so every
relative path in them (`CHART_DIR`, `DOCKERFILE`, the info file) resolves in
the wrong tree. Each module's header documents its inputs. Run `task --list-all` in a consumer
to see the full surface.

## Conventions

**Variable scoping.** A var declared in an included file *shadows* the
including file's value of the same name, and all included files share one
namespace. So no module here declares a bare knob name: every input is read
inline as `{{.NAME | default …}}`, and every derived value carries its module's
prefix — `_REL_IMAGE`, `_GO_PKG`, `_CS_KEY`, `_RT_CTX`. Consumers own the plain
names, and two modules can never mean different things by the same one.

Two derived values cross a module boundary on purpose: `runtime/*` and `cosign`
read `_REL_VERSION` and `_REL_IMAGE` from `release`, because they act on what a
release published. They read them — they must never declare them, or they would
shadow the very values they are supposed to act on.

**Task naming.** Public tasks are the plain verb for the work (`build`, `test`,
`deploy`, `restart`) namespaced by area when a module has several (`chart:push`,
`image:build`, `deps:update`). Internal helpers are `internal: true` and named
`_verb` when they stand alone, or `parent:_variant` when they are one branch of
a public task — the complementary `image:build:_do` / `image:build:_skipped`
pair, for instance, where exactly one of the two runs.

**Logging.** Component-scoped modules print `<marker> <component> · <area> ·
<what happened>`; repo-scoped ones (`security`, `monorepo`, `argocd`) print
`<marker> <module> · <what happened>`, because there is no one component to
name. The markers are `▸` starting work, `✔` done, `⚠` skipped on purpose, `✖`
failed.

**Versioning.** One scheme, in `service.yaml`:

```
exact tag, clean tree  →  X.Y.Z
otherwise, clean tree  →  <base>-dev.<committer-ts>.g<sha>
dirty tree             →  <base>-dev.<committer-ts>.g<sha>.dirty.<now>
```

Committer timestamp rather than wall clock, so a clean tree produces the same
version on every run — that is what makes the publish path idempotent.
Timestamp before sha, so SemVer's left-to-right pre-release comparison orders
builds chronologically and ArgoCD's `>=0.0.0-0` resolver always picks the
newest push.

**Idempotency.** Re-running `task deploy` on an unchanged commit does nothing:
the image build is skipped when a clean tree's image is already in the local
store, and the chart push is skipped when that version is already in the
registry. A dirty tree always rebuilds — it is not reproducible by definition.

Everything runs under `silent: true`, so what you see is these lines plus
whatever the underlying tool prints.

**Workflows are audited.** `zizmor` runs over `.github/workflows/` in CI and in
the pre-commit hook, in its `auditor` persona. Actions are pinned to commit
SHAs with the version in a trailing comment, and Dependabot moves the pins —
a tag is mutable, and a pin nobody updates is its own problem.

**Less shell.** Guards are `preconditions` (with an explanatory `msg`),
skips are `status`, cleanup is `defer`, iteration is `for`, and required
inputs are `requires`. Multi-line bash blocks were the previous
implementation; they are not the current one.

## Releasing

Trunk-based: `main` is the only long-lived branch, work lands on it in small
commits, and a release is a tag. There is no `develop` — consumers pin
`?ref=vX.Y.Z`, so what is on `main` cannot reach anyone who has not chosen it.

```bash
task lint                                   # the gate, also run by the hooks
git tag -a v1.2.0 -m "…" && git push --tags # release.yml takes it from here
```

Pushing the tag runs `.github/workflows/release.yml`, which lints the tagged
tree, refuses a tag that is not `vMAJOR.MINOR.PATCH` or has no
[CHANGELOG](CHANGELOG.md) entry, includes the published tag **over the network**
the way a consumer does — the only check that proves the tag is actually
fetchable — and then creates the GitHub release with notes generated from the
commits.

The release notes and the changelog are deliberately different things. The
notes list what changed; the changelog says what to do about it. Write the
entry under `## [Unreleased]` as you go, and move it under the version when you
cut the tag.

Renaming or removing a task is a major bump: these modules are a public API,
and `?ref=` is the only thing standing between a rename here and forty broken
Taskfiles.

## License

[MIT](LICENSE) — use it, copy a module into your own repository, change it,
ship it in something commercial. The one condition is that a copy carries the
copyright line and the permission notice with it.

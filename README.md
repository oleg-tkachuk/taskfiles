# taskfiles

Shared [Task](https://taskfile.dev) modules for every service in this
workspace — one implementation of the release chain, the language gates and
the Kubernetes conveniences, instead of a copy per repository.

Requires Task **3.53+** (remote Taskfiles are stable there; no experiment flag).

## Using it

```yaml
version: "3"
silent: true

vars:
  TASKLIB: ../taskfiles          # sibling checkout
  TASKLIB_REF: ""
  PROJECT_NAME: billing-api
  IMAGE_NAMESPACE: acme
  K8S_NAMESPACE: acme

includes:
  release: { taskfile: '{{.TASKLIB}}/release{{.TASKLIB_REF}}', dir: . }
  k8s:     { taskfile: '{{.TASKLIB}}/k8s{{.TASKLIB_REF}}', dir: . }
  go:      { taskfile: '{{.TASKLIB}}/go{{.TASKLIB_REF}}', dir: . }

tasks:
  deploy:  { cmds: [{ task: release:deploy }] }
  restart: { cmds: [{ task: k8s:restart }] }
  test:    { cmds: [{ task: go:test }] }
```

`dir: .` is required on every include — it pins the module's commands to the
including component's directory.

### Consuming it remotely

Once this repo is pushed, switch the two vars and nothing else changes:

```yaml
vars:
  TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git/'
  TASKLIB_REF: '?ref=v1.1.0'
```

Task caches the fetched files under `.task/remote/` and asks for confirmation
the first time; in CI pass `--yes` or `--trusted-hosts github.com`. Pin a tag,
never a branch — and never a commit SHA: Task clones with `--depth 1`, and git
refuses a bare SHA with that flag.

Only the YAML is fetched. Sibling scripts in this repo are **not** downloaded,
which is why every module is self-contained and expresses its logic in Task's
own primitives rather than shelling out to a helper.

## Modules

| Module | Namespace | What it covers |
|---|---|---|
| `release/` | `release` | version derivation, image build/push, chart lint/render/package/push, `deploy` |
| `k8s/` | `k8s` | restart, logs, status, `helm upgrade --install`, port-forward |
| `go/` | `go` | build, test (+coverage, +integration, +tagged-compile), lint, fmt, tidy, vuln, dep bumps |
| `python/` | `py` | poetry install/test/lint/format/typecheck/lock, dep bumps |
| `uv/` | `py` | the same surface for uv-managed projects — swap the include line |
| `node/` | `node` | install, dev, build, lint, test, e2e, verify, generate, dep bumps |
| `compose/` | `dev` | local stack up/down/reset/logs |
| `monorepo/` | `all` | run one target across every component, registry preflight |
| `security/` | `sec` | govulncheck, golangci-lint, gitleaks, trivy, buf breaking |
| `argocd/` | `argocd` | hard-refresh the apps a deploy just republished |
| `auth/` | `auth` | mint a local-dev JWT |
| `runtime/docker/`, `runtime/orbstack/`, `runtime/minikube/`, `runtime/kind/`, `runtime/k3d/` | `local` | run a locally built image on a local cluster, no registry |

### Local clusters

`svc:image:build` writes to whatever Docker daemon the host talks to. Whether
that image is then visible to your cluster depends on the cluster: OrbStack and
Docker Desktop share the host's store and need nothing, minikube and kind and
k3d each have their own and need an import step. That difference is the only
thing the `runtime/*` modules contain, and they all expose the same three
tasks — `check`, `image:load`, `install` — so moving between them is one line:

```yaml
includes:
  local: { taskfile: '{{.TASKLIB}}/runtime/orbstack{{.TASKLIB_REF}}', dir: . }
```

Include one alongside `service`, not instead of it: `local:image:load` moves
what `release:image:build` produced, and `local:install` helm-installs the
chart from disk against it with `pullPolicy=IfNotPresent`.

Each module is a directory holding a `Taskfile.yaml`; an include names the
directory, so the layout inside a module stays the module's own business.

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
inline as `{{.NAME | default …}}` and every derived value is prefixed with `_`
(`_IMAGE`, `_VERSION`, `_PKG`). Consumers own the plain names.

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

**Logging.** `▸` starting work, `✔` done, `⚠` skipped something on purpose,
each line prefixed with the component name. Everything runs under
`silent: true`, so what you see is these lines plus whatever the underlying
tool prints.

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
tree, refuses a tag that is not `vMAJOR.MINOR.PATCH`, includes the published
tag **over the network** the way a consumer does — the only check that proves
the tag is actually fetchable — and then creates the GitHub release with notes
generated from the commits.

Renaming or removing a task is a major bump: these modules are a public API,
and `?ref=` is the only thing standing between a rename here and forty broken
Taskfiles.

# taskfiles

[![release](https://img.shields.io/github/v/release/oleg-tkachuk/taskfiles?sort=semver&label=release)](https://github.com/oleg-tkachuk/taskfiles/releases/latest)
[![ci](https://github.com/oleg-tkachuk/taskfiles/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/oleg-tkachuk/taskfiles/actions/workflows/ci.yml)
[![Task 3.53+](https://img.shields.io/badge/Task-3.53%2B-29BEB0?logo=task&logoColor=white)](https://taskfile.dev/docs/installation)
[![license: MIT](https://img.shields.io/github/license/oleg-tkachuk/taskfiles?label=license)](LICENSE)

Shared [Task](https://taskfile.dev) modules — one implementation of the release
chain, the language gates and the Kubernetes conveniences, included over git
instead of copied into every repository.

Requires [Task](https://taskfile.dev/docs/installation) **3.53+** — remote
Taskfiles are stable from that version, with no experiment flag to set.

See [demo/](demo/README.md) for a working example — one small Go service
taken from `go test` to a signed, running deployment using six of these
modules, walkthrough included.

- [Using it](#using-it)
  - [Working on the library itself](#working-on-the-library-itself)
    - [Workflows are audited](#workflows-are-audited)
    - [How a module is written](#how-a-module-is-written)
- [Modules](#modules)
  - [Local clusters](#local-clusters)
- [Conventions](#conventions)
  - [Variable scoping](#variable-scoping)
  - [When a module's values are decided](#when-a-modules-values-are-decided)
  - [Task naming](#task-naming)
  - [A task you don't need](#a-task-you-dont-need)
  - [An empty value turns nothing off](#an-empty-value-turns-nothing-off)
  - [Include naming](#include-naming)
  - [Logging](#logging)
  - [Versioning](#versioning)
  - [Every tool invocation takes flags](#every-tool-invocation-takes-flags)
  - [Commit the remote lock](#commit-the-remote-lock)
  - [Idempotency](#idempotency)
- [License](#license)

## Using it

```yaml
version: "3"
silent: true

vars:
  TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git//%s?ref=v5.2.1'
  PROJECT_NAME: billing-api
  IMAGE_NAMESPACE: acme
  K8S_NAMESPACE: acme

includes:
  release: { taskfile: '{{printf .TASKLIB "release"}}', dir: . }
  k8s:     { taskfile: '{{printf .TASKLIB "k8s"}}', dir: . }
  go:      { taskfile: '{{printf .TASKLIB "go"}}', dir: . }

tasks:
  deploy:  { cmds: [{ task: release:deploy }] }
  restart: { cmds: [{ task: k8s:restart }] }
  test:    { cmds: [{ task: go:test }] }
```

`dir: .` is required on every include — it pins the module's commands to the
including component's directory.

The three names above `includes:` are inputs, not decoration. A module never
declares a bare input name — a var declared inside an included file *shadows*
the including file's value of the same name — so it reads
`{{.PROJECT_NAME | default "service"}}` instead, and the consumer sets the value
once at file level where every include sees it. Drop them and the image
becomes `localhost:5000/service` and `k8s:restart` rolls something in
`default`. See [Variable scoping](#variable-scoping).

**Pin a tag.** Not a branch, or your build changes when someone else commits —
and never a commit SHA: Task clones with `--depth 1`, and git refuses a bare
SHA with that flag. The tag above is an example; the current one is on the
[releases page](https://github.com/oleg-tkachuk/taskfiles/releases), and
[CHANGELOG.md](CHANGELOG.md) says what moving to it costs.

A rename or a removal is a major bump — these modules are a public API, and
`?ref=` is the only thing between a rename here and your Taskfile. Adding a
task or an input is a minor; everything else is a patch. How a release is cut
is in [RELEASE.md](RELEASE.md).

### Working on the library itself

Point `TASKLIB` at a checkout beside your repository. The `%s` stays; only
what surrounds it changes, so the include lines are identical either way and an
edit to the library is visible without cutting a tag:

```yaml
vars:
  TASKLIB: '../taskfiles/%s'
```

`TASKLIB` holds the whole path with a `%s` where the module goes, and each
include fills it in with `printf` — Task's own template function, evaluated
while the include graph is built, not a shell call. One variable rather than a
base and a suffix, and the version written once.

It has to work this way because an include path substitutes plain `{{.VAR}}`
references and evaluates nothing else there: no `{{if}}`, and no variable whose
value is itself a template. So `TASKLIB: '…//%s?ref={{.V | default "v2.2.0"}}'`
does not resolve — it reaches git as a literal ref and fails. The version is a
constant in the file, which is what pinning means anyway.

`task surface` prints every module's tasks from this checkout, which is the one
view a consumer cannot get: `task --list-all` there shows what that repository
included, not what the library offers.

Only the YAML is fetched. Sibling scripts in this repo are **not** downloaded,
which is why every module is self-contained and expresses its logic in Task's
own primitives rather than shelling out to a helper.

#### Workflows are audited

`zizmor` runs over `.github/workflows/` in CI and in
the pre-commit hook, in its `auditor` persona. Actions are pinned to commit
SHAs with the version in a trailing comment, and Dependabot moves the pins —
a tag is mutable, and a pin nobody updates is its own problem.

#### How a module is written

Guards are `preconditions` (with an explanatory `msg`),
skips are `status`, cleanup is `defer`, iteration is `for`, and required
inputs are `requires`. Multi-line bash blocks were the previous
implementation; they are not the current one.

## Modules

| Module | Namespace | What it covers |
|---|---|---|
| [`argocd/`](argocd/README.md) | `argocd` | hard-refresh the apps a deploy republished, and operate the Argo server |
| [`auth/`](auth/README.md) | `auth` | mint a local-dev JWT |
| [`checkov/`](checkov/README.md) | `checkov` | policy-scan manifests, charts, Dockerfiles and workflows |
| [`codegen/`](codegen/README.md) | `codegen` | mocks, protobuf stubs, `go generate`, sqlc — and the drift gates for them |
| [`compose/`](compose/README.md) | `compose` | local stack up/down/reset/logs |
| [`cosign/`](cosign/README.md) | `cosign` | sign the published image and chart, attest an SBOM, verify both |
| [`go/`](go/README.md) | `go` | build, test (+coverage, +integration, +tagged-compile), lint, fmt, tidy, vuln, dep bumps |
| [`helm/`](helm/README.md) | `helm` | what is installed on a cluster, and removing it |
| [`k8s/`](k8s/README.md) | `k8s` | restart, logs, status, `helm upgrade --install`, port-forward |
| [`monorepo/`](monorepo/README.md) | `monorepo` | run one target across every component, registry preflight |
| [`node/`](node/README.md) | `node` | install, dev, build, lint, test, e2e, verify, generate, dep bumps |
| [`pnpm/`](pnpm/README.md) | `pnpm` | keep the corepack pnpm pin current and agreed across a repo's apps |
| [`python/*`](python/README.md) — poetry, uv | `python` | install/test/lint/format/typecheck/lock and dep bumps, one surface per manager |
| [`release/`](release/README.md) | `release` | version derivation, image build/push, chart lint/render/package/push, `deploy` |
| [`runtime/*`](runtime/README.md) — docker, orbstack, minikube, kind, k3d | `local` | run a locally built image on a local cluster, no registry |
| [`sealed-secrets/`](sealed-secrets/README.md) | `sealed-secrets` | seal a value into a committable SealedSecret, fetch the controller key |
| [`security/`](security/README.md) | `security` | govulncheck, golangci-lint, gitleaks, trivy, buf breaking |

### Local clusters

`release:image:build` writes to whatever Docker daemon the host talks to. Whether
that image is then visible to your cluster depends on the cluster: OrbStack and
Docker Desktop share the host's store and need nothing, minikube and kind and
k3d each have their own and need an import step. That difference is the only
thing the `runtime/*` modules contain, and they all expose the same three
tasks — `check`, `image:load`, `install` — so moving between them is one line:

```yaml
includes:
  local: { taskfile: '{{printf .TASKLIB "runtime/orbstack"}}', dir: . }
```

Include one alongside `release`, not instead of it: `local:image:load` moves
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

### Variable scoping

A var declared in an included file *shadows* the
including file's value of the same name, and all included files share one
namespace. So no module here declares a bare knob name: every input is read
inline as `{{.NAME | default …}}`, and every derived value carries its module's
prefix — `_REL_IMAGE`, `_GO_PKG`, `_CS_KEY`, `_RT_CTX`. Consumers own the plain
names, and two modules can never mean different things by the same one.

Two derived values cross a module boundary on purpose: `runtime/*` and `cosign`
read `_REL_VERSION` and `_REL_IMAGE` from `release`, because they act on what a
release published. They read them — they must never declare them, or they would
shadow the very values they are supposed to act on.

### When a module's values are decided

A module's `vars:` are evaluated once,
as the include loads — not per call. Values reach them from the including
file's own vars, from the include's `vars:` block, and from the command line. A
`vars:` block on a `task:` reference does not reach them: it is visible to a
task's own `vars:` and nowhere else.

```yaml
# configures the module — the include carries the value
k8s: { taskfile: '{{printf .TASKLIB "k8s"}}', dir: ., vars: { K8S_NAMESPACE: billing } }

# does not — the module derived its namespace when it loaded
- task: k8s:restart
  vars: { K8S_NAMESPACE: billing }
```

That is why every module here is scoped to one component. A repository that
needs the same module aimed at several targets includes it once per target,
rather than passing the target at the call.

The `X: '{{.X | default "…"}}'` form in the quickstart is not decoration: a var
that reads a *different* name is fixed at whatever that name held, while one
that reads its own sees a value given on the command line. Write inputs that
way in a consumer and `task deploy REGISTRY=other` works.

### Task naming

Public tasks are the plain verb for the work (`build`, `test`,
`deploy`, `restart`) namespaced by area when a module has several (`chart:push`,
`image:build`, `deps:update`). Internal helpers are `internal: true` and named
`_verb` when they stand alone, or `parent:_variant` when they are one branch of
a public task — the complementary `image:build:_do` / `image:build:_skipped`
pair, for instance, where exactly one of the two runs.

### A task you don't need

A module's task list is not all-or-nothing. Task's own `excludes:` on the
include drops specific tasks from it — not hidden from `--list-all`,
genuinely gone:

```yaml
includes:
  k8s:
    taskfile: '{{printf .TASKLIB "k8s"}}'
    dir: .
    excludes: ["port-forward"]
```

```console
$ task k8s:port-forward
task: Task "k8s:port-forward" does not exist
```

Real case: an infrastructure repository that only ever runs `k8s:restart`
and `k8s:status` has no service behind a Deployment to reach through
`port-forward`, and likely no use for tailing `logs` either — exclude both:

```yaml
excludes: ["port-forward", "logs"]
```

Name the task the way the module itself does — `port-forward`, not
`k8s:port-forward`. The namespaced form matches nothing, and `excludes`
fails silently: the task stays in the list, with no error saying why the
exclusion did not take.

### An empty value turns nothing off

`{{.X | default "d"}}` yields `d` when `X`
is unset *and* when it is empty, so a consumer cannot switch a default off by
passing nothing:

```console
$ task show          # X unset → fallback
$ task show X=       # X empty → fallback, not ""
$ task show X=none   # → none
```

Every opt-out here is therefore an explicit value a consumer has to name —
`COSIGN_SIGN=0` makes the signing tasks no-ops, `E2E_SETUP=none` skips the
browser download. When adding one, pick a value and check for it; do not write
a default that an empty string is supposed to defeat, because it will not.

### Include naming

A module is included under its own directory name, because the include alias
is what names every task it brings in.

A **family** is the exception, and it is the point of being one. `runtime/*`
and `python/*` hold variants of a single surface — five local clusters, two
Python package managers — so they are included under the family name, `local`
and `python`, and swapping one variant for another is a single line with no
task rename anywhere in the consumer. `task lint` refuses a family whose
variants stop exposing the same tasks, which is what keeps that promise true;
a deliberate difference goes in `SURFACE_EXCEPT` with a reason.

### Logging

Component-scoped modules print `<marker> <component> · <area> ·
<what happened>`; repo-scoped ones (`security`, `monorepo`, `argocd`) print
`<marker> <module> · <what happened>`, because there is no one component to
name.

The marker vocabulary:

| Marker | Means | Colour |
| --- | --- | --- |
| `◉` | starting work | cyan |
| `✔` | done | green |
| `○` | nothing to do — skipped on purpose | grey |
| `▲` | worth reading, but not fatal | yellow |
| `✖` | failed | red |

The shape carries the meaning and the colour only reinforces it, so a line
still reads in a log that has been stripped of ANSI. Each marker is a single
codepoint — no variation selector — so every line starts the same width in
every terminal. Set `NO_COLOR` to any value to get the glyphs without the
escapes.

`·` separates the fields of a line and `→` marks a result, both from the same
vocabulary.

### Versioning

One scheme, in [`release/`](release/README.md):

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

### Every tool invocation takes flags

A module wraps a tool; it does not own it. So every external command here
accepts a verbatim pass-through, named after the tool and ending in `_FLAGS`:

```yaml
sec:
  taskfile: '{{printf .TASKLIB "security"}}'
  dir: .
  vars: { TRIVY_FLAGS: '--severity HIGH,CRITICAL', GITLEAKS_FLAGS: '--log-opts=-n50' }
```

The value is spliced into the command unquoted, which is what makes several
flags in one string work — and what makes it the wrong place for a value that
came from outside the repository. These are for the person writing the
Taskfile, not for user input.

Where one module runs the same tool several ways, each call gets its own input
rather than one shared bag: `HELM_LINT_FLAGS`, `HELM_TEMPLATE_FLAGS`,
`HELM_PACKAGE_FLAGS` and `HELM_FLAGS` (registry calls) in `release`. A single
`HELM_FLAGS` would put `--dry-run` on a `helm package` that has no such flag.

### Commit the remote lock

A module pulled over the network — `?ref=vX.Y.Z` rather than a checkout beside
you — leaves a lock in `.task/remote/`:

```
.task/remote/git.github.com.go.<hash>.checksum
```

Task refuses to run when the content behind that ref no longer matches it:

```
task: Taskfile "…//go?ref=v5.2.1" not trusted by user
```

That is the only thing standing between a moved tag and your build, so commit
those `.checksum` files. Most repositories ignore `.task/`, which throws the
lock away — add an exception:

```gitignore
.task/
!.task/remote/
```

Refresh it deliberately when you bump the pin, with `task --download`.

A checkout-based include produces no lock, because there is no fetch to
verify — nothing to commit until you move to a tag.

### Idempotency

Re-running `task deploy` on an unchanged commit does nothing:
the image build is skipped when a clean tree's image is already in the local
store, and the chart push is skipped when that version is already in the
registry. A dirty tree always rebuilds — it is not reproducible by definition.

Everything runs under `silent: true`, so what you see is these lines plus
whatever the underlying tool prints.


## License

[MIT](LICENSE) — use it, copy a module into your own repository, change it,
ship it in something commercial. The one condition is that a copy carries the
copyright line and the permission notice with it.

---

Changing this library? See [CONTRIBUTING.md](CONTRIBUTING.md). Found a
vulnerability? See [SECURITY.md](SECURITY.md) rather than a public issue.

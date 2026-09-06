# taskfiles

Shared [Task](https://taskfile.dev) modules for every service in this
workspace — one implementation of the release chain, the language gates and
the Kubernetes conveniences that were previously copy-pasted into 39
Taskfiles across six repositories.

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
  svc: { taskfile: '{{.TASKLIB}}/service.yaml{{.TASKLIB_REF}}', dir: . }
  go:  { taskfile: '{{.TASKLIB}}/go.yaml{{.TASKLIB_REF}}', dir: . }

tasks:
  deploy: { cmds: [{ task: svc:deploy }] }
  test:   { cmds: [{ task: go:test }] }
```

`dir: .` is required on every include — it pins the module's commands to the
including component's directory.

### Consuming it remotely

Once this repo is pushed, switch the two vars and nothing else changes:

```yaml
vars:
  TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git/'
  TASKLIB_REF: '?ref=v1.0.0'
```

Task caches the fetched files under `.task/remote/` and asks for confirmation
the first time; in CI pass `--yes` or `--trusted-hosts github.com`. Pin a tag,
never a branch — and never a commit SHA: Task clones with `--depth 1`, and git
refuses a bare SHA with that flag.

Only the YAML is fetched. Sibling scripts in this repo are **not** downloaded,
which is why every module is self-contained and expresses its logic in Task's
own primitives rather than shelling out to a helper.

## Modules

| File | Namespace | What it covers |
|---|---|---|
| `service.yaml` | `svc` | version derivation, image build/push, chart lint/render/package/push, `deploy`, k8s restart/logs/status/upgrade/port-forward |
| `go.yaml` | `go` | build, test (+coverage, +integration, +tagged-compile), lint, fmt, tidy, vuln, dep bumps |
| `python.yaml` | `py` | poetry install/test/lint/format/typecheck/lock, dep bumps |
| `node.yaml` | `node` | install, dev, build, lint, test, e2e, verify, generate, dep bumps |
| `compose.yaml` | `dev` | local stack up/down/reset/logs |
| `monorepo.yaml` | `all` | run one target across every component, registry preflight |
| `security.yaml` | `sec` | govulncheck, golangci-lint, gitleaks, trivy, buf breaking |
| `argocd.yaml` | `argocd` | hard-refresh the apps a deploy just republished |

Each file's header documents its inputs. Run `task --list-all` in a consumer
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

```bash
task lint          # parse every module
git tag -a v1.1.0 -m "…" && git push --tags
```

Consumers pin a tag, so a change here reaches them only when they move their
`TASKLIB_REF`. Renaming or removing a task is a major bump: these files are a
public API.

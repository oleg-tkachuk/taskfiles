# monorepo — run one target across components

A sequential fan-out over a list of component directories, each holding its own
Taskfile. It stops at the first failure: a half-shipped registry is worse than a
failed command with a name attached to it.

```yaml
includes:
  monorepo: { taskfile: '{{printf .TASKLIB "monorepo"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `all:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `build` | Run `task build` in every component |
| `deploy` | Run `task deploy` in every component, after checking the registry answers |
| `each` | Run TARGET in every component (TARGET=test, TARGET=deploy, …) |
| `lint` | Run `task lint` in every component |
| `test` | Run `task test` in every component |
| `registry:check` | Fail fast when localhost:5000 is not reachable |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `COMPONENTS` | — | whitespace-separated component directories |
| `TARGET` | — | required by `each`: the task to run in each |
| `REGISTRY` / `GLOBAL_REGISTRY` | `localhost:5000` | what `registry:check` probes |

## Examples

```yaml
includes:
  monorepo:
    taskfile: '{{printf .TASKLIB "monorepo"}}'
    dir: .
    vars:
      COMPONENTS: "backend/api backend/worker frontend/console"
      GLOBAL_REGISTRY: "{{.GLOBAL_REGISTRY}}"
```

```console
$ task monorepo:test
── backend/api · test
── backend/worker · test
── frontend/console · test

$ task monorepo:deploy                                  # checks the registry first
$ task monorepo:each TARGET=lint
```

## The set is decided at the include, and only there

A `COMPONENTS` on the command line does **not** narrow a run once the include
above declares one — a declared var wins over a CLI value, and the fan-out
still reaches every component in the list. Measured on two repositories; it
produces no error and no warning, which is why it reads as if it worked.

So there is no `ONLY=`, no `SKIP=`, and no CLI narrowing either. To run one
component, run its own Taskfile: `task <component>:deploy`. To fan out over a
*different* set — the components that publish, say, as against the ones that
merely build — include this module a second time under a second name:

```yaml
  all:  { taskfile: '{{printf .TASKLIB "monorepo"}}', dir: ., vars: { COMPONENTS: "…everything…" } }
  ship: { taskfile: '{{printf .TASKLIB "monorepo"}}', dir: ., vars: { COMPONENTS: "…publishers…" } }
```

Trim each one's surface with `excludes:` so the wrong fan-out cannot be reached
by accident — but never exclude `each`: `test`, `lint`, `build` and `deploy`
are all defined in terms of it.

## Why a deploy checks the registry first

`deploy` probes the registry before the first push, so a misconfiguration costs
seconds rather than a half-finished chain. 200, 401 and 403 all count as "the
registry answered".

---

Part of [taskfiles](../README.md).

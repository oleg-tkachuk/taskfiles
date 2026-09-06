# monorepo — run one target across components

A sequential fan-out over a list of component directories, each holding its own
Taskfile. It stops at the first failure: a half-shipped registry is worse than a
failed command with a name attached to it.

```yaml
includes:
  monorepo: { taskfile: '{{.TASKLIB}}monorepo{{.TASKLIB_REF}}', dir: . }
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
| `registry` | check:       Fail fast when localhost:5000 is not reachable |

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
    taskfile: '{{.TASKLIB}}monorepo{{.TASKLIB_REF}}'
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
$ task monorepo:deploy COMPONENTS="backend/api"         # narrow the run
```

## Narrowing replaces ONLY/SKIP

There is no `ONLY=` or `SKIP=`: override `COMPONENTS` instead. One knob, and it
is the same knob that defines the set in the first place.

## registry:check

`deploy` probes the registry before the first push, so a misconfiguration costs
seconds rather than a half-finished chain. 200, 401 and 403 all count as "the
registry answered".

---

Part of [taskfiles](../README.md).

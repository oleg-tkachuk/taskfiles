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
workspace — tasks then read `monorepo:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `build` | Run `task build` in every component |
| `deploy` | Run `task deploy` in every component, after checking the registry answers |
| `doctor` | Report a top-level var that included components can read from one another |
| `each` | Run TARGET in every component (TARGET=test, TARGET=deploy, ...) |
| `lint` | Run `task lint` in every component |
| `test` | Run `task test` in every component |
| `registry:check` | Fail fast when localhost:5000 is not reachable |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `COMPONENTS` | — | list of component directories |
| `TARGET` | — | required by `each`: the task to run in each |
| `REGISTRY` / `GLOBAL_REGISTRY` | `localhost:5000` | what `registry:check` probes |

## Examples

```yaml
includes:
  monorepo:
    taskfile: '{{printf .TASKLIB "monorepo"}}'
    dir: .
    vars:
      COMPONENTS: ["backend/api", "backend/worker", "frontend/console"]
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
  all:  { taskfile: '{{printf .TASKLIB "monorepo"}}', dir: ., vars: { COMPONENTS: [...everything...] } }
  ship: { taskfile: '{{printf .TASKLIB "monorepo"}}', dir: ., vars: { COMPONENTS: [...publishers...] } }
```

Trim each one's surface with `excludes:` so the wrong fan-out cannot be reached
by accident — but never exclude `each`: `test`, `lint`, `build` and `deploy`
are all defined in terms of it.

## Components that share a root Taskfile

`each` runs every component as its own `task` process, so they share nothing.
A root Taskfile that *includes* its components is different: their top-level
`vars:` land in one pool, and a name one component declares is what every
other component's includes read — see
[Variable scoping](../README.md#variable-scoping). `doctor` reads the root's
local includes and names each var some of them declare and others do not, and
each var several declare with different values:

```console
$ task monorepo:doctor
▲ monorepo · DOCKERFILE is declared at the top level of api only — every other component reads that value; move it into the vars: of the include that reads it
▲ monorepo · PROJECT_NAME is declared at the top level of api web with different values — which one a module reads is not stable, in the declaring components too; move it into the vars: of the include that reads it
```

The second is the quieter one. Each component declares its own name, so
nothing looks shared — and still, once the root holds a third include, the
component that declares one value reads the other in a share of its runs. A
module reads `PROJECT_NAME` for the image and the chart it publishes, not only
for its log lines.

A warning rather than a failure: a name only one component uses is harmless
until a module in another component reads it, which this cannot see. It needs
yq, and says so when yq is not there.

## One component from the root: `task api:test`

`each` is the fan-out. For a single component by name, do not include its
Taskfile in the root — that is what puts its vars in the shared pool. Give
the root a wildcard task that runs the component as a child process, the way
`each` does:

```yaml
tasks:
  _component:
    internal: true
    dir: "{{.COMPONENT}}"
    requires: { vars: [COMPONENT, TARGET] }
    env: { GLOBAL_REGISTRY: "{{.GLOBAL_REGISTRY}}" }
    cmd: task {{.TARGET | q}} -- {{.CLI_ARGS}}

  "api:*":
    desc: "Run a task in backend/api (task api:test)"
    cmds: [{ task: _component, vars: { COMPONENT: backend/api, TARGET: "{{index .MATCH 0}}" } }]
```

The measurements, and what changes for someone used to an include, are in
[A monorepo runs its components](../README.md#a-monorepo-runs-its-components-it-does-not-include-them).

## A component that is not there

Both halves of "COMPONENTS is wrong" used to pass silently, so `each` refuses
them before it dispatches anything.

An **empty** list printed nothing and exited 0 — a gate that reads as every
component passing, when the fan-out was never wired up.

A **misspelt** entry was worse. Task creates a missing `dir:` rather than
failing on it, so the typo became a new empty directory, `task <TARGET>` found
no Taskfile in it and walked up to the repository root, and the root's `TARGET`
is usually this very fan-out. The run recursed until it was killed — no error,
no exit, and one junk directory per attempt.

```console
$ task test
task: COMPONENTS names something that is not a component: workers/rag-anwsers(no such directory)
Each entry must be a directory holding its own Taskfile, relative to
the directory this module's include carries.
```

## Why a deploy checks the registry first

`deploy` probes the registry before the first push, so a misconfiguration costs
seconds rather than a half-finished chain. 200, 401 and 403 all count as "the
registry answered".

---

Part of [taskfiles](../README.md).

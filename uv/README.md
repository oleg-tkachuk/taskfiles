# uv — uv-managed Python projects

The same task names as [`python/`](../python/README.md), backed by uv. A project
that moves between the two changes one include line and nothing else.

```yaml
includes:
  py: { taskfile: '{{.TASKLIB}}uv{{.TASKLIB_REF}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `py:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `fmt` | ruff format — alias `format` |
| `install` | uv sync (skipped when the manifests are unchanged) |
| `lint` | ruff check |
| `lock` | Regenerate uv.lock without changing any version |
| `test` | pytest |
| `typecheck` | mypy (skipped when mypy is not a project dependency) |
| `deps` | outdated:       Show dependencies with a newer version available (read-only) |
| `deps` | update:         Bump dependencies within their pyproject constraints, then refresh the lock |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `python` | the label in every log line |
| `PY` | uv's choice | interpreter, when it must be pinned |
| `PY_SRC` | `src` | what lint and format target |
| `PY_TEST_FLAGS` | `-q` | |
| `UV_SYNC_FLAGS` | `--group dev` | which dependency sets to install |

## Examples

```yaml
vars:
  PROJECT_NAME: ner-server

includes:
  py: { taskfile: '{{.TASKLIB}}uv{{.TASKLIB_REF}}', dir: . }

tasks:
  test: { cmds: [{ task: py:test }] }
```

A project that selects dependency sets through extras rather than groups:

```yaml
vars:
  UV_SYNC_FLAGS: --extra stealth --extra dev
```

## install is fingerprinted

`install` is keyed on `pyproject.toml` and `uv.lock`. `uv sync` on an unchanged
lock is milliseconds anyway, so the tasks that need dependencies simply depend on
it rather than asking you to remember.

---

Part of [taskfiles](../README.md).

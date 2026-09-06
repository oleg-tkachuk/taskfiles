# python — Poetry projects

Install, test, lint, format, typecheck and dependency bumps for a Poetry-managed
project. For uv, include [`uv/`](../uv/README.md) instead — same task names.

```yaml
includes:
  py: { taskfile: '{{.TASKLIB}}python{{.TASKLIB_REF}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `py:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `fmt` | ruff format — alias `format` |
| `install` | poetry install (skipped when pyproject and the lockfile are unchanged) |
| `lint` | ruff check |
| `lock` | Regenerate poetry.lock |
| `test` | pytest |
| `typecheck` | mypy (skipped when mypy is not a project dependency) |
| `deps` | outdated:            Show dependencies with a newer version available (read-only) |
| `deps` | update:              Bump dependencies within their pyproject constraints, then refresh the lock |
| `deps` | update:latest:       Widen constraints and bump everything, majors included |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `python` | the label in every log line |
| `PY` | `python3` | interpreter the venv is built on |
| `PY_SRC` | `src` | what lint and format target |
| `PY_TEST_FLAGS` | `-q` | |
| `POETRY_INSTALL_FLAGS` | `--no-interaction` | e.g. add `--no-root` |

## Examples

```yaml
vars:
  PROJECT_NAME: rag-agents
  # The interpreter the deployed image runs — see the note below.
  PY: python3.13

includes:
  py: { taskfile: '{{.TASKLIB}}python{{.TASKLIB_REF}}', dir: . }

tasks:
  build: { cmds: [{ task: py:install }] }
  test:  { cmds: [{ task: py:test }] }
  lint:  { cmds: [{ task: py:lint }] }
```

A worker that ships its entry point as a script rather than an installable
distribution:

```yaml
vars:
  POETRY_INSTALL_FLAGS: --no-interaction --no-root
```

## Pin `PY`

Left at the default, a pyproject that admits `>=3.13,<4.0` also admits 3.14, and
a venv built on the newer one falls back to source builds for native deps that
ship no wheel for it yet — a Rust toolchain in the middle of `poetry install`.
Set `PY` to the version the deployed image runs, and move it when the runtime
moves.

## install is fingerprinted

`install` is keyed on `pyproject.toml` and `poetry.lock`, so re-running it after
an unrelated edit costs nothing. That is what makes it safe to put in a `deps:`
list.

---

Part of [taskfiles](../README.md).

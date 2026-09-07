# python — one Python surface, two package managers

Install, test, lint, format, typecheck and dependency bumps for a Python
component. Two implementations, chosen by which manager the project uses:

| Variant | For a project managed by |
|---|---|
| `poetry/` | Poetry — `pyproject.toml` + `poetry.lock` |
| `uv/` | uv — `pyproject.toml` + `uv.lock` |

Both expose the same task names, so include one **as `python`** and moving
between them is a single line:

```yaml
includes:
  python: { taskfile: '{{printf .TASKLIB "python/poetry"}}', dir: . }
  # or
  python: { taskfile: '{{printf .TASKLIB "python/uv"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. `task lint` in this repository fails if the two surfaces
drift apart, so the swap keeps working.

## Tasks

| Task | poetry | uv |
|---|---|---|
| `install` | `poetry install` | `uv sync` |
| `test` | pytest | pytest |
| `lint` | ruff check | ruff check |
| `fmt` | ruff format — alias `format` | same |
| `typecheck` | mypy, skipped when it is not a dependency | same |
| `lock` | regenerate `poetry.lock` | regenerate `uv.lock`, no version changes |
| `deps:outdated` | read-only report | read-only report |
| `deps:update` | bump within the pyproject constraints, refresh the lock | same |
| `deps:update:latest` | widen the constraints, majors included | **poetry only** |

`deps:update:latest` has no uv counterpart on purpose: `poetry up --latest`
rewrites `pyproject.toml`, while `uv lock --upgrade` deliberately respects what
is written there. It is the one documented exception to the shared surface.

`install` is fingerprinted in both — keyed on the manifest and the lockfile — so
re-running it after an unrelated edit costs nothing, and the tasks that need
dependencies simply depend on it.

## Inputs

Shared by both:

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `python` | the label in every log line |
| `PY_SRC` | `src` | what lint and format target |
| `PY_TEST_FLAGS` | `-q` | flags for the test run |
| `TEST_CMD` | `pytest` | which runner each task invokes |
| `LINT_CMD` | `ruff check` | what `lint` runs |
| `FORMAT_CMD` | `ruff format` | what `fmt` runs |
| `TYPECHECK_CMD` | `mypy` | what `typecheck` runs |
| `TYPECHECK_MODULE` | `mypy` | what `typecheck` imports to decide whether it can run |

Per variant:

| Var | Variant | Default | Meaning |
|---|---|---|---|
| `PY` | poetry | `python3` | interpreter the venv is built on |
| `PY` | uv | uv's choice | interpreter, when it must be pinned |
| `POETRY_INSTALL_FLAGS` | poetry | `--no-interaction` | e.g. add `--no-root` |
| `POETRY_UPDATE_FLAGS` | poetry | — | extra flags for `poetry update` |
| `POETRY_LOCK_FLAGS` | poetry | — | extra flags for `poetry lock` |
| `UV_SYNC_FLAGS` | uv | `--group dev` | which dependency sets to install |
| `UV_LOCK_FLAGS` | uv | — | extra flags for `uv lock` |

The four tools are inputs, not assumptions. ruff, pytest and mypy are the
defaults because they are what most projects reach for; a project on black,
flake8, pyright or plain unittest sets the command rather than doing without
the task.

## Examples

A Poetry worker that ships its entry point as a script rather than an
installable distribution:

```yaml
vars:
  PROJECT_NAME: rag-agents
  # The interpreter the deployed image runs — see below.
  PY: python3.13
  POETRY_INSTALL_FLAGS: --no-interaction --no-root

includes:
  python: { taskfile: '{{printf .TASKLIB "python/poetry"}}', dir: . }

tasks:
  build: { cmds: [{ task: python:install }] }
  test:  { cmds: [{ task: python:test }] }
```

A uv project that selects dependency sets through extras rather than groups:

```yaml
vars:
  PROJECT_NAME: ner-server
  UV_SYNC_FLAGS: --extra stealth --extra dev

includes:
  python: { taskfile: '{{printf .TASKLIB "python/uv"}}', dir: . }
```

## Pin the interpreter under Poetry

Left at the default, a pyproject that admits `>=3.13,<4.0` also admits 3.14, and
a venv built on the newer one falls back to source builds for native deps that
ship no wheel for it yet — a Rust toolchain in the middle of `poetry install`.
Set `PY` to the version the deployed image runs, and move it when the runtime
moves. uv resolves the interpreter from the project itself, so this is Poetry's
problem only.

---

Part of [taskfiles](../README.md).

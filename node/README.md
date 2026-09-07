# node — pnpm and npm front-ends

Thin wrappers over the package.json scripts, so the whole developer surface shows
up in `task --list-all` instead of splitting across two tools.

```yaml
includes:
  node: { taskfile: '{{printf .TASKLIB "node"}}', dir: . }
```

`dir: .` is required: it pins the module's commands to the including
component's directory. The namespace above is the convention used across this
workspace — tasks then read `node:<task>`.

## Tasks

| Task | What it does |
|---|---|
| `build` | Build the production bundle |
| `dev` | Start the dev server |
| `generate` | Run the codegen script |
| `install` | Install dependencies from the lockfile (skipped when the manifests are unchanged) |
| `lint` | Run the lint script (read-only) |
| `test` | Run the test script |
| `verify` | Lint then build — the pre-push gate |
| `deps` | outdated:       Show dependencies with a newer version available (read-only) |
| `deps` | update:         Bump dependencies to the latest minor/patch (no majors), then reinstall |
| `lint` | fix:            Run the lint script with --fix |
| `test` | e2e:            Run the Playwright suite, installing chromium when it is missing |

## Inputs

| Var | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `node` | the label in every log line |
| `PM` | `pnpm` | pass `npm` for a package-lock repo |
| `PM_EXEC` | `pnpm dlx`, `npx` for npm | how a one-off tool is run |
| `SCRIPT_DEV` | `dev` | which package.json script each task runs |
| `SCRIPT_BUILD` | `build` | what `build` runs |
| `SCRIPT_LINT` | `lint` | what `lint` and `lint:fix` run |
| `SCRIPT_TEST` | `test` | what `test` runs |
| `SCRIPT_E2E` | `test:e2e` | what `test:e2e` runs |
| `SCRIPT_GENERATE` | `generate` | what `generate` runs |
| `LINT_FIX_FLAGS` | `--fix` | what `lint:fix` appends |
| `PM_INSTALL` | — | override the install command outright |
| `E2E_SETUP` | `exec playwright install --with-deps chromium` | run before the suite; `none` to skip |

## Examples

```yaml
vars:
  PROJECT_NAME: billing-api

includes:
  node: { taskfile: '{{printf .TASKLIB "node"}}', dir: . }

tasks:
  dev:    { cmds: [{ task: node:dev }] }
  verify: { cmds: [{ task: node:verify }] }   # lint, then build
```

An npm project:

```yaml
vars:
  PM: npm       # install becomes `npm ci`
```

## The install is the reproducible one

`pnpm install --frozen-lockfile` / `npm ci`. A lockfile that disagrees with
package.json should fail the install, not be quietly rewritten. Override
`PM_INSTALL` if you need something else.

## Pointing a task at a different script

Every task calls the script of the same name — `dev`, `build`, `lint`, `test`,
`generate`. A project whose script is named differently should call it directly
rather than bending the module.

## `none`, not the empty string

`E2E_SETUP=none` skips the preparation step. An empty value will not: Task's
`default` filter fires on an empty variable as well as an unset one, so `""`
hands back the default rather than switching it off.

---

Part of [taskfiles](../README.md).

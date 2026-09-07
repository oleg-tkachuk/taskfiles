# node — pnpm and npm front-ends

Thin wrappers over the package.json scripts, so the whole developer surface shows
up in `task --list-all` instead of splitting across two tools.

```yaml
includes:
  node: { taskfile: '{{.TASKLIB}}node{{.TASKLIB_REF}}', dir: . }
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
| `SCRIPT_DEV` | `dev` | which package.json script each task runs |
| `SCRIPT_BUILD` | `build` | |
| `SCRIPT_LINT` | `lint` | |
| `SCRIPT_TEST` | `test` | |
| `SCRIPT_E2E` | `test:e2e` | |
| `SCRIPT_GENERATE` | `generate` | |
| `LINT_FIX_FLAGS` | `--fix` | what `lint:fix` appends |
| `PM_INSTALL` | — | override the install command outright |

## Examples

```yaml
vars:
  PROJECT_NAME: billing-api

includes:
  node: { taskfile: '{{.TASKLIB}}node{{.TASKLIB_REF}}', dir: . }

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

## Script names

Every task calls the script of the same name — `dev`, `build`, `lint`, `test`,
`generate`. A project whose script is named differently should call it directly
rather than bending the module.

---

Part of [taskfiles](../README.md).

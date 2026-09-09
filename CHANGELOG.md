# Changelog

Notable changes to the shared task library, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/): consumers pin `?ref=vX.Y.Z`, so a rename or a
removal is a major bump — these modules are a public API.

This file is **not** generated. The GitHub release notes already list the
commits — `release.yml` builds them with `--generate-notes` — and repeating
that here would add nothing. What a generator cannot write is the half that
matters to someone upgrading: which names changed, what to set now that a
default is gone, and what to replace a removed task with. That is what lives
here, and the release gate refuses a tag with no entry.

## [Unreleased]

Nothing yet.

## [5.2.1] — 2026-09-09

### Documentation

- **Excluding a task you don't need** — Task's own `excludes:` on an
  include drops specific tasks from a module entirely (not just hidden
  from `--list-all`), documented here for the first time under
  Conventions. Named after the case that surfaced it: an infrastructure
  repository with no service behind a Deployment has no use for
  `k8s:port-forward`. The gotcha worth knowing — `excludes:` takes the
  task's own name (`port-forward`), not the namespaced one
  (`k8s:port-forward`); the namespaced form matches nothing and fails
  silently, with the task still showing up and no error explaining why.

## [5.2.0] — 2026-09-09

### Added

- **`k8s:uninstall`** — `helm uninstall` scoped to this component's own
  release, asking first. `upgrade` had no way back that did not mean
  emptying the whole cluster through `helm:uninstall-all`.
- **`VALUES`**, a values file for `k8s:upgrade`, matching the input
  `runtime/*:install` already had.

### Fixed

- `k8s:status`'s pod list matched on `app.kubernetes.io/instance` — itself
  a better guess than the `/name` it replaced, but still a guess about a
  consumer's chart's labels. It now reads the selector straight off the
  Deployment's own `spec.selector.matchLabels`, so it works regardless of
  labeling convention. The library's own `Deployment` naming requirement is
  now documented too: every `k8s` task addresses it by name directly, which
  needs `metadata.name` to equal the release name — `helm create`'s
  "fullname" helper (`<release>-<chart>`) will not resolve.
- `argocd:refresh` reported a cluster with no ArgoCD installed at all
  (`applications.argoproj.io` CRD missing) identically to a cluster with
  nothing matching `APP_PREFIX` — both said "no application matches" with
  the real error thrown away. A reachable cluster now surfaces that error;
  an unreachable one still no-ops, as before.
- `go:test`, `go:fmt` and `go:deps:outdated` each used `&&/||` to fall back
  when a tool was absent, which let a **failure** of that tool fall through
  the same branch — `go:test` ran the suite a second time through plain
  `go test` whenever gotestsum reported a real failure, giving a flaky test
  a second chance to report green.
- `python/uv:deps:outdated` and `python/poetry:deps:outdated` swallowed a
  genuine failure (an unresolvable dependency, a missing lockfile) behind
  `|| true` — copied from `node:deps:outdated`, where it is correct because
  `pnpm`/`npm` exit non-zero specifically to signal findings. `uv` and
  `poetry` do not share that behavior and exit 0 on a report either way, so
  there was nothing legitimate left for `|| true` to protect.
- `compose`'s `build`, `down`, `reset`, `ps` and `logs` now check
  `COMPOSE_FILE` exists, the same guard `up` already had, instead of
  surfacing the compose engine's raw error.
- `runtime/*:install` (all five variants) now checks `helm` is installed
  before its first `helm` call, matching `release`, the `helm` module and
  `k8s:upgrade`/`uninstall`.

## [5.1.3] — 2026-09-07

### Added

- **`demo/`** — a working example of the library: one small Go service taken
  from `go test` to a signed, running deployment through `go`, `release`,
  `runtime/kind`, `k8s`, `security` and `cosign`. Its Dockerfile ships
  without a non-root `USER` on purpose, so the walkthrough's security step
  has a real finding to catch and fix. Excluded from the root Taskfile's
  module discovery and linked from the main README — it is a consumer of
  this library, not a module in it, and does not change any module's task
  or input surface.

## [5.1.2] — 2026-09-07

### Added

- `task lint`'s **check:surface** also compares whether shared tasks declare
  `deps:` at all, not just whether the names match — `python/poetry`'s
  `test`/`lint`/`fmt` went a full release without `deps: [install]` while
  `python/uv` had it, and a name-only diff could not see that kind of drift.
  Best-effort: needs `yq`, warns rather than fails when that is missing.
- **check:runtime-install**, refusing a `runtime/*` variant whose `install:`
  task has drifted from the other four. It stays duplicated on purpose — a
  shared include would resolve `CHART_DIR` against this checkout instead of
  the consumer's — so this is what keeps the five copies honest instead.

### Fixed

- `cosign:verify` and `cosign:keygen` carried `preconditions:` alongside
  their own `status:` guard. Task evaluates preconditions before status, so
  `COSIGN_SIGN=0` could not skip `verify` past its "is cosign installed"
  check, and an existing key still demanded cosign be on PATH just for
  `keygen` to decide there was nothing to do.
- `helm:list` had the same trap: a laptop with no cluster running still
  needed `helm` installed just to be told there was nothing to list.
- `monorepo:registry:check`'s own comment already said 200/401/403 all mean
  the registry answered; the code only rejected `000`, so a registry
  answering 500 or 404 passed this preflight and then failed
  `release:doctor` on the same host.

## [5.1.1] — 2026-09-07

### Fixed

- `release:chart:render`'s yq check used `&&/||`, so a genuine parse failure
  on the rendered chart fell into the same branch as a missing binary and
  exited 0 — the exact "chart shipped 1 of N Deployments" failure this gate
  exists to catch, passing silently. Presence and success are now checked
  separately.

- `security`'s hadolint-missing message referenced `_SEC_ERR`, a marker the
  module never declared, so it printed with no marker at all. Declared
  alongside the rest.

- `checkov:baseline` counted accepted findings through `python3`, an
  interpreter this task had no reason to require, and whose absence would
  surface only after the confirmation prompt had already been answered.
  Replaced with `grep -c` against checkov's own one-check-id-per-line
  baseline format.

- `release` and `cosign` declared `_REL_NS`, `_CS_REG` and `_CS_CHART` and
  never read them, while `_REL_IMAGE`, `_REL_CHART_REPO` and `_CS_CHART_REF`
  re-derived the same registry and chart expressions inline instead. The
  declared vars are wired in now, so the expression exists once per file.

- `python/poetry`'s `test`, `lint`, `fmt` and `typecheck` had no
  `deps: [install]`, unlike `python/uv`. Poetry does not auto-sync its
  environment the way uv does, so a fresh checkout's `task python:test`
  failed outright with "Command not found: pytest" instead of installing
  first. Both variants now depend on `install`.

## [5.1.0] — 2026-09-07

### Added

- `security:trivy` takes **`TRIVY_SKIP_DIRS`**, defaulting to
  `--skip-dirs .claude`. trivy walks the filesystem itself, so it was scanning
  the throwaway agent worktrees under `.claude/` and reporting every finding
  twice — once against code that ships and once against a copy nobody builds.
  find-based discovery already pruned them through `SCAN_EXCLUDE`; this is the
  same rule for the scanner that does its own walking. Point it at a repository's
  other vendored trees to widen it: `--skip-dirs .claude --skip-dirs .ocp`.

- **`node:typecheck`**, running the project's `typecheck` script and printing
  `○ … skipped` where package.json declares none. Two apps were already calling
  it in their `verify` gate against a task that did not exist, so the gate
  failed on the reference rather than on the types. `SCRIPT_TYPECHECK` renames
  the script.

## [5.0.1] — 2026-09-07

### Fixed

- `node:deps:update` ran `dlx`, which is pnpm's spelling, against whatever `PM`
  said — so every `PM: npm` repository got `Unknown command: "dlx"`. It now
  resolves `pnpm dlx` or `npx` from `PM`, and `PM_EXEC` overrides it.

## [5.0.0] — 2026-09-07

### Removed

- **`security:pyvuln`, added in 4.1.0, is withdrawn.** It made coverage worse,
  not better. `pip-audit` reads a project only when it declares PEP 621
  `[project]` metadata — 4 of this workspace's 19 Python projects — and errors
  out on the other 15, while `trivy fs`, already in `security:all`, reads
  `poetry.lock` and `uv.lock` directly and covers all of them.

  The gap it was meant to fill did not exist; it was read off a missing task
  name rather than off what the existing scans do. `security`'s README now says
  plainly that Python and Node dependencies are trivy's job and Go's are
  govulncheck's.

  Migration: delete any `PY_PROJECTS`, `PIP_AUDIT_CMD` or `PIP_AUDIT_FLAGS` you
  set. Nothing replaces the task — `security:trivy` was already doing the work.

### Documentation

- The `Using it` example explains why `PROJECT_NAME`, `IMAGE_NAMESPACE` and
  `K8S_NAMESPACE` sit in the consumer's own `vars:` — a var declared inside a
  module would shadow the value it is supposed to receive — and what breaks if
  they are dropped.

## [4.1.0] — 2026-09-07

### Added

Three checks for gaps this workspace had: 19 Python projects with no
vulnerability scan while Go had `govulncheck`, 48 Dockerfiles with no lint, and
52 charts rendered but never validated against the Kubernetes schemas.

- **`security:pyvuln`** — pip-audit across `PY_PROJECTS`. Skips a directory
  with no `pyproject.toml`, fails when there is one and the tool is missing,
  same rule as the Go scans. `PIP_AUDIT_CMD` lets a repository use
  `uvx pip-audit` rather than installing it.
- **`security:dockerfile`** — hadolint over `DOCKERFILES`. Blocks on
  error-level findings only by default: hadolint's own threshold flags 113
  findings in this workspace's 48 Dockerfiles, of which 3 are errors, and a
  gate that is red everywhere on day one is one people learn to skip.
- **`release:chart:validate`** — kubeconform over the rendered chart. It
  renders into its own temporary file rather than reusing `chart:render`'s,
  which deletes its output when it finishes.

Two defaults are deliberate and were chosen after watching the obvious ones
pass while checking nothing: `pip-audit` is given the project directory,
because with no path it audits the ambient environment and exits 0 on a
machine with no venv; and `chart:validate` does **not** pass
`-ignore-missing-schemas`, because that turns a dead `apps/v1beta1` into a
skip — the exact case the gate exists for.

## [4.0.1] — 2026-09-07

### Fixed

- This repository's own CI and release fixtures still included `python` and
  still used the two-variable `{{.TASKLIB}}name{{.TASKLIB_REF}}` form that the
  library stopped documenting in 2.2.1. Both went red on the 4.0.0 tag, so
  **v4.0.0 has no GitHub release** — the tag itself resolves and is safe to
  pin, but v4.0.1 is the one to use.

## [4.0.0] — 2026-09-07

A major because two modules moved. The upgrade is one line per consumer.

### Changed

- **`python` and `uv` are now `python/poetry` and `python/uv`,** a family in
  the shape of `runtime/*`. They were always alternatives — nobody includes
  both — and they expose the same tasks, so they now live together and are
  included under the family name:

  ```yaml
  includes:
    python: { taskfile: '{{printf .TASKLIB "python/poetry"}}', dir: . }
    # or
    python: { taskfile: '{{printf .TASKLIB "python/uv"}}', dir: . }
  ```

  The point is what does *not* change: a project moving between the two edits
  one line, and every `python:test`, `python:lint`, `python:install` it already
  calls keeps resolving. Before, the uv variant answered to `uv:` and the swap
  meant renaming every call site.

  Migration: `"python"` → `"python/poetry"`, `"uv"` → `"python/uv"`, and if the
  uv module was included as `uv:` rename that alias to `python:`.

### Added

- `task lint` gained **check:surface**: a family whose variants stop exposing
  the same tasks fails the gate. Interchangeability that nothing verifies stops
  being true quietly. `deps:update:latest` is the one allowed difference —
  `poetry up --latest` rewrites `pyproject.toml` while `uv lock --upgrade`
  respects it — and it is named in `SURFACE_EXCEPT` with that reason.

## [3.6.0] — 2026-09-07

### Added

- **Every external tool invocation now takes a verbatim pass-through.** The
  convention already existed for a dozen tools; these were the ones still
  hard-coded:

  | Module | New input |
  | --- | --- |
  | `sealed-secrets` | `KUBESEAL_FLAGS` |
  | `codegen` | `BUF_FLAGS`, `SQLC_FLAGS`, `GOIMPORTS_FLAGS` |
  | `release` | `HELM_LINT_FLAGS`, `HELM_TEMPLATE_FLAGS`, `HELM_PACKAGE_FLAGS` |
  | `cosign` | `SYFT_FLAGS` |
  | `helm` | `HELM_UNINSTALL_FLAGS` |
  | `auth` | `STEP_FLAGS` |
  | `python` | `POETRY_UPDATE_FLAGS`, `POETRY_LOCK_FLAGS` |
  | `uv` | `UV_LOCK_FLAGS` |

  Where a module runs one tool several ways, each call gets its own input
  rather than one shared bag — a single `HELM_FLAGS` would put `--dry-run` on
  a `helm package` that has no such flag.

### Documentation

- Conventions gained **Every tool invocation takes flags**, including the
  caveat that the value is spliced in unquoted and so is for the person writing
  the Taskfile, not for user input.

## [3.5.0] — 2026-09-07

### Added

- `release` takes `IMAGE_NAME`, the symmetric partner of `CHART_NAME`: the
  image name when it differs from `PROJECT_NAME`. A component whose log label
  is not what its image is called no longer has to choose between the two.
  `cosign` follows it, since it reads the image reference the release module
  derives.

## [3.4.0] — 2026-09-07

### Added

- `sealed-secrets:seal:merge` — seal one key and merge it into an existing
  manifest with `kubeseal --merge-into`, leaving the other keys and the file's
  structure untouched. Rotating one credential no longer means rewriting the
  whole SealedSecret, which is what kept one repository on its own kubeseal
  call.

## [3.3.1] — 2026-09-07

### Fixed

- The `IMAGE_LATEST` push and its log line carried the same condition on two
  separate commands. Editing one would have left the other behind, printing
  "pushed latest" with nothing pushed. One guarded block now.

## [3.3.0] — 2026-09-07

### Added

- **`pnpm`** — a new module that keeps the corepack pnpm pin current and
  agreed across a repository's apps: `pin:update`, `pin:update:major`,
  `pin:check`. Repo-scoped, unlike `node`, because a repository whose apps
  sit on different pnpm versions writes two lockfile dialects.

  It also documents the trap it exists to avoid: corepack resolves the pin
  from the current directory, so `pnpm -C <app> …` runs corepack's default
  rather than the app's pin and then refuses to switch.

- `release` takes `IMAGE_LATEST`. Set it to `1` to push a floating `:latest`
  beside the version tag. Off by default — the charts here read their tag from
  `appVersion`, so nothing in this library needs it, and a floating tag makes a
  rollback point disappear.

- `sealed-secrets:seal:literals` seals several key/value pairs into one
  manifest. Each pair becomes its own argv element, so a value carrying a
  quote or a `$( )` reaches kubectl as data.

### Documentation

- Conventions gained **Commit the remote lock**. A module pulled with `?ref=`
  leaves a `.task/remote/*.checksum` that Task checks before running, and it is
  the only thing standing between a moved tag and your build — but most
  repositories ignore `.task/` and throw it away.

## [3.2.2] — 2026-09-07

### Changed

- Every "tool is not installed" message now points at that tool's own
  installation page instead of naming a Homebrew formula. `brew install trivy`
  is useless on Debian, Arch or Alpine, and the upstream page is the only
  place that stays right for all of them. The `poetry` and `uv` messages
  already did this; the rest now match.

  `gosec` and `govulncheck` keep `go install …@latest`: they are Go programs,
  that is the upstream instruction, and it is identical on every platform.

  Each of the twenty links was checked for a 200 before being written down —
  trivy's documentation site has moved and its old path 404s, so that one
  points at the repository's install section.

## [3.2.1] — 2026-09-07

### Fixed

- **`security:all` was unusable on a repository that ships no Go.** It died on
  the first scan — `govulncheck: no go.mod file` — and never reached `secrets`
  or `trivy`, the two scans that repository actually needed.

  A directory in `GO_MODULES` without a `go.mod` is now skipped, and says so:

  ```
  ○ sec · govulncheck · . is not a Go module — skipped
  ```

  The rule is: skip when there is nothing to scan, fail when there is something
  to scan and the tool is missing. A Python repository no longer needs
  govulncheck installed; a Go repository that lacks it still stops with an
  install hint. The skip is printed rather than done with `status:`, which is
  silent — a typo in `GO_MODULES` must be visible.

### Changed

- `security:all` runs `secrets` and `trivy` before the Go scans, so the checks
  that apply to every repository have already run whatever the rest finds.
- `gosec` goes through the same internal helper as `vuln` and `lint` instead of
  doing its own `cd`, which is what let one change cover all three.

## [3.2.0] — 2026-09-07

### Changed

- **`security:all` now runs `gosec`.** The task has described itself as "run
  every scan" since it was written, while quietly leaving out the one scan that
  reads the source for insecure patterns rather than checking dependencies.

  This can turn a green `security:all` red twice over: gosec has to be
  installed (`go install github.com/securego/gosec/v2/cmd/gosec@latest`), and
  once it is, it may find something. If that is not the moment you want to deal
  with it, call the individual tasks — `vuln`, `lint`, `secrets`, `trivy` —
  which are unchanged.

- `security:all`'s description no longer claims proto compatibility. It never
  ran `proto:breaking` and should not: that gate needs a proto tree and a base
  branch, so it would fail for every consumer shipping no protobuf, and a gate
  that cannot pass is one people learn to skip. Call it from the workflow that
  owns the contract.

## [3.1.0] — 2026-09-07

### Changed

- `BUF_TEMPLATE` now also accepts a YAML list, not only a space-separated
  string:

  ```yaml
  BUF_TEMPLATE: ['buf.gen.yaml', 'buf.gen.ocp.yaml']
  ```

  A list is what a reader expects for several templates; the string form still
  works and is what a single template, a CLI override or an env var carries.

### Fixed

- The library's own CI called `codegen:go`, renamed in 3.0.0, so the smoke job
  went red on the first run after the tag. The modules were correct — only the
  fixture named the task by its old name.

## [3.0.0] — 2026-09-07

A major because one task was renamed. The upgrade is one line per consumer,
and only for a consumer that named that task directly.

### Changed

- **`codegen:go` is now `codegen:generate`.** It no longer only runs
  `go generate`: `GENERATE_CMD` says what the step runs, defaulting to
  `go generate ./...`. A component whose generator is invoked directly —
  `wire ./internal/app/` — now uses the module instead of keeping its own task.

  Migration: rename `codegen:go` to `codegen:generate` wherever you call it.
  `codegen:all` and `codegen:check` are unaffected; they compose it internally.

### Added

- `BUF_TEMPLATE` accepts several templates, space-separated, and `proto` runs
  buf once per template. A repository that generates a second slice from
  another template — a vendored contract, a TypeScript client — lists both
  rather than keeping its own `buf generate` beside the module's.
- `PROTO_PATH` — directories prepended to `PATH` before buf runs, for a plugin
  that arrives from neither `PATH` nor a Go module. It is expanded by the
  shell, so `$(pnpm -C ../web bin)` reaches a plugin in a JS tree, which
  `PROTO_PLUGINS` cannot.
- `GENERATE_CMD` — what `generate` runs. Same shape as `TEST_CMD` and
  `LINT_CMD` in `python`, `uv` and `node`.

## [2.2.1] — 2026-09-07

### Changed

- The documented way to include a module is now one variable instead of two.
  `TASKLIB` carries the whole path with a `%s` where the module goes, and each
  include fills it in with `printf`:

  ```yaml
  vars:
    TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git//%s?ref=v2.2.0'
  includes:
    release: { taskfile: '{{printf .TASKLIB "release"}}', dir: . }
  ```

  `TASKLIB_REF` is gone. Switching between a checkout and a tag was two edits
  and is now one, and the version is written once instead of once per form.
  `printf` here is Task's own template function, evaluated while the include
  graph is built — not a shell call, which an include path cannot make.

  Nothing was removed from any module, so the old
  `{{.TASKLIB}}release{{.TASKLIB_REF}}` spelling keeps working; this is a change
  of convention, not of contract.

- `release` strips the `v` off a tag with `trimPrefix` rather than piping
  `git describe` through `sed` — one process instead of two, and the rule reads
  as data rather than as a regex inside a folded scalar. The versions produced
  are identical; all six branches were checked against real repositories.

## [2.2.0] — 2026-09-07

### Changed

- Status markers are now `◉` starting work, `✔` done, `○` nothing to do, `▲`
  worth reading, `✖` failed. Each is a single codepoint, coloured with ANSI
  rather than by the character itself, so the line reads the same width
  everywhere and still reads once a log has been stripped of escapes. Set
  `NO_COLOR` to any value for the bare glyphs.
- `○` and `▲` split what was previously one marker. A step that had nothing to
  do (an image already built, a deployment that is not there) now reads
  differently from one worth stopping at (a dirty tree, an unreachable
  registry, a gate that could not run because `yq` is missing).

## [2.1.2] — 2026-09-07

A security fix. Upgrade if anything you pass to these modules is not written by
hand at the keyboard — a secret read from a file, a password from a manager, a
value from CI.

### Fixed

- Consumer values reaching a shell were interpolated between hand-written
  single quotes. A value containing `'` closes them, and the rest of it stops
  being data.

  `sealed-secrets:seal` is the one that mattered, because a secret is arbitrary
  text by definition. Sealing `x'; touch /tmp/PWNED; echo '` ran the command —
  and cut off the `--dry-run=client` that keeps plaintext off the cluster with
  it, so `kubectl create secret` ran for real and left the value in the
  namespace. Elsewhere the same shape broke the command instead: through `auth`
  the quote closed early and `step` refused a malformed invocation. Which one
  happens depends only on where the value lands in the line.

  Twenty-four values across `sealed-secrets`, `auth`, `argocd`, `helm`,
  `checkov` and `codegen` now go through Task's `q`, which quotes correctly.
  `*_FLAGS` inputs are deliberately left bare: they exist to expand into
  several arguments.

  Nothing to change in a consumer — the fix is inside the modules.

## [2.1.1] — 2026-09-07

Documentation only. No module changed.

### Changed

- The release procedure moved to [RELEASE.md](RELEASE.md) — one person cuts
  releases and it sat where every consumer read past it. What a version number
  promises did not move: a rename or a removal is a major bump, and that
  sentence now sits beside **Pin a tag**, where someone choosing a version is
  already reading. The procedure had also fallen behind — the release workflow
  refuses four things now, and the section listed two.
- The module table is sorted alphabetically. Its order had been thematic and
  stopped being so as modules were added, and nothing above it explained an
  order a reader could otherwise predict.
- Conventions records that an empty value turns nothing off: `default` fires on
  an empty variable as well as an unset one, so every opt-out here is a value a
  consumer names — `COSIGN_SIGN=0`, `E2E_SETUP=none`.
- The `argocd` row in the module table describes the whole module; it had
  mentioned only the application refresh since the `server:` tasks arrived.

## [2.1.0] — 2026-09-07

Additive. Every default is what it was, so a consumer that sets none of this
sees no difference.

### Added

- Every tool invocation takes what it needs to be somebody else's. A module
  that hardcodes its command is usable by whoever wrote it and nobody else, and
  five modules hardcoded theirs.

  `security` gains `GOVULNCHECK_FLAGS`, `GOLANGCI_FLAGS`, `GITLEAKS_FLAGS`,
  `BUF_BREAKING_FLAGS`, and — the clearest case — `TRIVY_SUBCOMMAND`,
  `TRIVY_SCANNERS`, `TRIVY_TARGET` and `TRIVY_FLAGS`. A repository scanning a
  built image rather than a working tree, or looking for misconfiguration
  rather than vulnerabilities, previously had no way in. `checkov` gains
  `CHECKOV_FLAGS` and `CHECKOV_TARGET`.

  Flags are appended, never substituted for the invocation: what makes a task a
  gate — trivy's `--exit-code 1`, the base golangci-lint measures against —
  stays where a consumer cannot drop it by accident.

- `python` and `uv` take `TEST_CMD`, `LINT_CMD`, `FORMAT_CMD`, `TYPECHECK_CMD`
  and `TYPECHECK_MODULE`. They hardcoded ruff, pytest and mypy across four
  tasks each, so a project on black, flake8, pyright or plain unittest could not
  use lint, fmt, test or typecheck — not configure them, use them.

- `node` names its package.json scripts: `SCRIPT_DEV`, `SCRIPT_BUILD`,
  `SCRIPT_LINT`, `SCRIPT_TEST`, `SCRIPT_E2E`, `SCRIPT_GENERATE`,
  `LINT_FIX_FLAGS`. A repository whose build is `build:prod` had to do without
  the task. `E2E_SETUP` covers the preparation step, which was Playwright's
  browser download and nothing else — set it to `none` to skip, since Task's
  `default` filter fires on an empty value as well as an unset one and `""`
  hands back the default.

- `compose` takes `COMPOSE_ENGINE`. Two hardcoded words made the whole module
  unavailable on podman, which answers everything it asks.

### Fixed

- Banners name the tool that runs. Making the Python toolchain configurable had
  left six of them announcing the default while a different command executed —
  `🔵 py · mypy` above a pyright run. `node:test:e2e` had the deeper version:
  it ran `playwright install` regardless, so `SCRIPT_E2E` promised a choice the
  task did not honour.

### Internal

- `actions/setup-go` moves from v5.5.0 to v7.0.0, off the deprecated Node 20
  runtime the runner had started warning about on every job.

## [2.0.0] — 2026-09-07

One module split in two. If you do not scan infrastructure with checkov, this
release changes nothing for you.

### What to do

If you called `security:checkov`, `security:checkov:all` or
`security:checkov:baseline`, add a second include and rename the calls:

```yaml
includes:
  security: { taskfile: '{{.TASKLIB}}security{{.TASKLIB_REF}}', dir: . }
  checkov:  { taskfile: '{{.TASKLIB}}checkov{{.TASKLIB_REF}}', dir: . }
```

| was | is |
|---|---|
| `security:checkov` | `checkov:scan` |
| `security:checkov:all` | `checkov:all` |
| `security:checkov:baseline` | `checkov:baseline` |

`CHECKOV_CONFIG`, `CHECKOV_BASELINE` and `CHECKOV_FRAMEWORKS` keep their names
and move to the new include. Everything else in `security` is untouched.

A second include rather than a re-export, because a module cannot include
another one: a nested include resolves against this library's working directory
rather than the consumer's, so every relative path in it would read the wrong
tree.

### Changed

- **BREAKING** — checkov is its own module. `security` was reaching for seven
  tools across three unrelated jobs: Go analysis, proto compatibility, and
  infrastructure policy. The seam is not size — checkov was three tasks of ten,
  while `release` is fourteen and is not being split. The seam is what a task
  can be run against: `security` wants Go modules and a git history, checkov
  wants YAML a cluster will apply, and a repository usually has one or the
  other. Either consumer was reading a task list half of which it had nothing
  to point at.

  `security:all` never composed the checkov tasks, which is the evidence that
  the boundary was already there.

## [1.3.2] — 2026-09-07

One module changed, and it dropped a requirement rather than adding one.

### Fixed

- `helm:uninstall-all` no longer needs `python3`. It parsed helm's JSON through
  an interpreter the module has no reason to require, and whose absence would
  have surfaced only after the prompt had been answered — the worst moment to
  learn a tool is missing. A release name is a DNS label, so awk over the table
  cannot mis-split it.

### Internal

- CI runs the modules on macOS as well as Linux. The library is developed on
  macOS and was checked only on Linux, so a divergence between the two
  userlands would have been invisible here and obvious on the first local run.
- The consumer smoke now runs tasks instead of only loading them. It carries a
  real Go module, so `codegen:go` executes a directive and the file it writes
  is asserted, and the `go` module's fmt, compile, test and tidy act on
  something. Both defects found in this library last week parse cleanly, which
  is what a load-only check would have kept missing.
- Every workflow job has a timeout, so nothing that hangs runs to GitHub's
  six-hour default.
- CI reports when a newer Task is released. Dependabot watches `uses:` pins and
  cannot see `TASK_VERSION`, so nothing else would ever mention it — a notice,
  not a gate, because the pin is deliberate.

## [1.3.1] — 2026-09-07

Documentation only. No module changed, so a consumer moving the ref from
`v1.3.0` has nothing to do.

### Changed

- Conventions now says when a module's values are decided: its `vars:` are
  evaluated once as the include loads, so a `vars:` block on a `task:`
  reference never reaches them. That is the rule behind the shape of the whole
  library — a module is configured per include, which is why each is scoped to
  one component and why a repository aiming the same module at several targets
  includes it several times.

  The self-referencing `X: '{{.X | default "…"}}'` form gets its sentence too:
  a var reading a different name is fixed at whatever that name held, while one
  reading its own sees a value given on the command line.

## [1.3.0] — 2026-09-07

Additive throughout: nothing that existed changed behaviour, so moving the ref
from `v1.2.0` costs nothing.

### Added

- `helm` — `list` answers which releases are on a cluster, which nothing here
  answered before (`argocd:list` shows Argo applications, a different set), and
  `uninstall-all` empties it. Both are cluster-wide, which is why they are not
  in `k8s`: that module acts on one component's deployment and every component
  includes it, so a task that empties the cluster does not belong in each of
  their lists.

  `uninstall-all` carries two locks. `CONFIRM` must name the context being
  emptied — a prompt guards against not meaning it and does nothing about
  meaning it on the wrong cluster — and the releases are printed before the
  prompt asks, so the question is answered with the list in view.

- `sealed-secrets` — seal a value or an env file into a manifest that is safe to
  commit, and fetch the controller's public key. Both sealing tasks build the
  Secret locally with `--dry-run=client`, so the plaintext never leaves the
  machine. `seal` puts the value in the argument list; the README says so
  rather than leaving it to be discovered.

- `security` gains `checkov`, `checkov:all` and `checkov:baseline` for
  infrastructure policy, and `gosec` for Go. The baseline regeneration counts
  findings before and after, because a baseline refreshed to clear one fixed
  finding also swallows anything that broke since — and the run that does it
  looks exactly like the run that does not.

- `argocd` gains six `server:` tasks: port-forward, password, set-password,
  restart, status and logs. `ARGOCD_SERVER` and `ARGOCD_SERVER_LABEL` are
  separate inputs because the deployment carries the Helm release name while
  the pods' `app.kubernetes.io/name` does not.

- `go` gains `bench`. `-run='^$'` matches no test, so the run measures
  benchmarks rather than timing the unit suite alongside them.

- `auth` gains `JWT_CLAIMS`: claims beyond the registered ones, as a JSON
  object. `step` reads the claims set from stdin and merges the registered ones
  over it, so an application whose tokens carry roles or a tenant no longer
  needs its own minting script.

- `security` gains `GITLEAKS_BASELINE`, which it should have had already. A
  repository with accepted historical findings had no way to say so, so the
  scan reported the same ones every run — and a gate that always fails is a
  gate nobody reads.

## [1.2.0] — 2026-09-07

### Added

- `codegen` — mocks, protobuf stubs, `go generate` and sqlc bindings,
  regenerated in the one order that works, plus the drift gates that refuse a
  tree where the committed output no longer matches its source. Two projects
  had written the same task independently; what differed was paths, and those
  are now inputs.

  Three of its choices are not obvious and each one cost a debugging session
  before it was written down: `GOWORK=off` throughout, because generators run
  `go` with `-mod=mod` and the toolchain refuses that under a workspace;
  protoc plugins installed from the module rather than taken from `PATH`,
  because `buf` resolves them through `PATH` and whichever patch release was
  installed globally then decided the committed bytes; and `goimports` over
  the generated directories, because a commit hook usually runs it too and
  disagrees with the generators about import grouping — without it the drift
  gate reports files stale on a tree that was just generated.

  The two gates differ deliberately. `mocks:check` reads `git status`, because
  a new interface produces a new file that a diff-only check would call clean;
  `sqlc:check` reads `git diff`, because sqlc rewrites files that already
  exist.

### Changed

- The quickstart no longer explains git authentication for a private
  repository, which this one is not.

### Internal

- The module list the parse gate walks is discovered from the filesystem
  rather than hand-maintained. It was a literal string, so a new module
  escaped that gate until someone remembered to edit it.

## [1.1.2] — 2026-09-07

Documentation, with one user-visible string. Nothing a consumer includes
behaves differently.

### Changed

- Every module is now documented under its own directory name. `compose`,
  `monorepo`, `security` and `cosign` were shown as `dev`, `all`, `sec` and
  `sign` — aliases from before the modules were directories — so `sign:keygen`
  came from a module called cosign. `runtime/*` keeps `local`, because its five
  modules share one surface and the alias names the role rather than the
  implementation; the Conventions section now says so.
- `cosign`'s preconditions name the task by that documented alias: they now
  point at `cosign:keygen` where they pointed at `sign:keygen`. The only string
  in this release that reaches a terminal.
- The module table lists what each module is called today, and the versioning
  note points at `release/` rather than `service.yaml` — a file that stopped
  existing when the modules became directories.

### Internal

- A release is refused when the README does not pin the tag being cut. Nothing
  templates a README on GitHub, so the quickstart stays true by being checked
  rather than substituted.

## [1.1.1] — 2026-09-07

Nothing in the modules changed. A consumer moving the ref from `v1.1.0` gets
byte-identical behaviour and has nothing to do; the tag exists so the docs and
the release tooling below have a version that names them.

### Changed

- The documented include alias is now the module's own name — `python:` for the
  python module, `uv:` for uv, where both examples said `py:`. The alias is what
  names the tasks it brings in, so `py:` produced a `py:test` that no module of
  that name defines, and meant two different modules in two different examples.
  Only the samples changed; nothing constrains what a consumer calls an include.
- One example registry hostname across the documentation, `registry.example.com`
  — RFC 2606 reserves it for this, so a sample can never resolve to something
  real.

### Internal

- A release is refused when `main` does not contain the tagged commit, so a tag
  cut on a side branch cannot publish a tree that CI on main never saw.
- Generated release notes are shaped by `.github/release.yml`, and workflow step
  names now say whether each one sets up, guards, verifies or publishes.

## [1.1.0] — 2026-09-07

### Added

- `release:doctor` — a pre-flight report that answers, in one pass, whether
  what a component declares actually resolves: the version, the chart and its
  full OCI path, the Dockerfile, the named build contexts and the registry. It
  is a report rather than a gate chain, so it prints every problem at once
  instead of stopping at the first, and exits non-zero when a finding is
  fatal. Run it before a deploy, or when one failed for a reason that named
  the symptom rather than the cause.

  It checks the mistakes that actually happen: a `DOCKERFILE` resolved against
  `DOCKER_CONTEXT` instead of the component directory; a `CHART_NAME` that
  disagrees with `Chart.yaml#name`, so the push looks for a tarball helm never
  wrote; a `COPY --from=NAME` naming neither a build stage nor a context passed
  in `DOCKER_BUILD_FLAGS`, which BuildKit reads as an image and reports as a
  registry permission error; an underivable version; an unreachable registry.

  Nothing to set — it reads the variables the module already has.

### Fixed

- The paired skip notices in `release:image:build`, `release:chart:push` and
  `k8s:restart` told the truth about the wrong moment. The task doing the work
  ran first, and it changes the state its partner inspects, so a build logged
  `built X` and `X already built — skipping` back to back. The notice is now
  evaluated first, on the state before anything ran.
- `release:image:build` also expressed its skip condition as two `status:`
  entries, which Task ANDs, where staying quiet requires a disjunction. A clean
  tree with no image reported `already built` for an image that did not exist.

  Both are behaviour fixes inside existing tasks; no names or inputs changed.

## [1.0.0] — 2026-09-06

First release.

### Added

- `release` — the publish chain: version derivation, image build and push,
  chart lint/render/package/push, and `deploy` doing all three in order. It
  talks to no cluster, so a repository that only publishes needs this and
  nothing else.
- `k8s` — restart, logs, status, `helm upgrade --install`, port-forward.
  Independent of `release`, for a repository that operates a cluster it does
  not build for.
- `go`, `python`, `uv`, `node` — build, test, lint, format and dependency bumps
  per ecosystem. `python` and `uv` share a task surface, so moving between them
  is one include line.
- `compose` — the local dependency stack, waiting on health checks.
- `monorepo` — run one target across every component, with a registry
  preflight before a deploy fan-out.
- `security` — govulncheck, golangci-lint limited to findings new since a base
  branch, gitleaks, trivy, buf breaking.
- `cosign` — sign the published image and chart, attest an SPDX SBOM, verify
  both.
- `argocd` — hard-refresh the applications a deploy republished, because a
  push to the registry does not reach the cluster until Argo drops its cached
  chart.
- `auth` — mint a local-development JWT.
- `runtime/{docker,orbstack,minikube,kind,k3d}` — make a locally built image
  runnable by a local cluster. Same three tasks in each, so switching runtime
  is one include line.

### Notes for consumers

- An include names the module directory, and one variable carries the tag:

  ```yaml
  vars:
    TASKLIB: 'https://github.com/oleg-tkachuk/taskfiles.git//'
    TASKLIB_REF: '?ref=v1.0.0'
  includes:
    release: { taskfile: '{{.TASKLIB}}release{{.TASKLIB_REF}}', dir: . }
  ```

  A checkout beside your repository sets `TASKLIB: ../taskfiles/` and leaves
  `TASKLIB_REF` undefined — an undeclared variable renders as nothing, so the
  include lines are the same either way.
- Versions derive from the **committer** timestamp, so a clean tree publishes
  the same version on every run. That is what makes `deploy` idempotent: an
  image already built for this commit is not rebuilt, and a chart version
  already in the registry is not re-pushed. Both say so rather than going
  quiet.
- The scheme is timestamp-first (`<base>-dev.<ts>.g<sha>`) because SemVer
  compares pre-release identifiers left to right — a sha-first form lets an
  alphabetically larger sha from an older commit shadow a newer build.
- No floating `:latest` is pushed. Charts resolve their tag from the chart's
  appVersion, which the deploy stamps with the version it tagged the image
  with.
- Defaults assume nothing about one particular setup: the registry is
  `localhost:5000`, timestamps are UTC, `golangci-lint` measures against
  `main`, and `python3` is whatever the host resolves. Set `REGISTRY`,
  `TIMEZONE`, `BASE` and `PY` for yours.

[5.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v5.1.0
[5.0.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v5.0.1
[5.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v5.0.0
[4.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v4.1.0
[4.0.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v4.0.1
[4.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v4.0.0
[3.6.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.6.0
[3.5.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.5.0
[3.4.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.4.0
[3.3.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.3.1
[3.3.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.3.0
[3.2.2]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.2.2
[3.2.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.2.1
[3.2.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.2.0
[3.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.1.0
[3.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v3.0.0
[2.2.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v2.2.1
[2.2.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v2.2.0
[2.1.2]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v2.1.2
[2.1.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v2.1.1
[2.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v2.1.0
[2.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v2.0.0
[1.3.2]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.3.2
[1.3.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.3.1
[1.3.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.3.0
[1.2.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.2.0
[1.1.2]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.1.2
[1.1.1]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.1.1
[1.1.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.1.0
[1.0.0]: https://github.com/oleg-tkachuk/taskfiles/releases/tag/v1.0.0

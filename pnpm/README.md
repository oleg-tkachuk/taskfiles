# pnpm — one version pin, across every app

pnpm arrives through corepack, so the `"packageManager"` field in
`package.json` **is** the version every developer, CI job and image build runs.
This module keeps that pin current and keeps the apps in a repository agreed on
it.

```yaml
includes:
  pnpm:
    taskfile: '{{printf .TASKLIB "pnpm"}}'
    dir: .
    vars: { PNPM_APPS: "frontend/admin-app frontend/clinic-app" }
```

Repo-scoped, unlike [`node`](../node/README.md), which is included once per app.
Every app moves together: a repository where one app sits on one pnpm and
another on a different one writes two lockfile dialects, and nothing notices
until an image build breaks.

## Tasks

| Task | What it does |
| --- | --- |
| `pin:update` | Bump to the newest release of the major the repo already sits on |
| `pin:update:major` | Cross a major deliberately — `task pnpm:pin:update:major -- 12` |
| `pin:check` | Fail when the pins diverge, or a global pnpm is shadowing the shim |

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `PNPM_APPS` | `.` | whitespace-separated app directories, each with a `packageManager` pin |
| `PNPM_PIN_FILES` | *(none)* | whitespace-separated files writing the same version a second time |

## The second pin, wherever it is written

An image build cannot read `package.json` before it has a package manager, so a
Dockerfile that installs pnpm writes the version itself. corepack never sees
that line and npm tooling never reads it, so it drifts alone - and the image
then builds a lockfile a different pnpm wrote.

The spelling of that pin is not one thing, so this matches the **version**
rather than the line around it, and takes every occurrence in a file rather
than the first:

| Recognised | Example |
| --- | --- |
| `pnpm@X.Y.Z` | `RUN corepack prepare pnpm@12.4.2 --activate` |
| `PNPM_VERSION=X.Y.Z` | `ARG PNPM_VERSION=12.4.2`, or the same as an `ENV` |

`pnpm@${PNPM_VERSION}` is deliberately left alone: it is derived from the ARG
this already rewrites.

```yaml
includes:
  pnpm:
    taskfile: '{{printf .TASKLIB "pnpm"}}'
    dir: .
    vars:
      PNPM_APPS: frontend
      PNPM_PIN_FILES: frontend/deploy/Dockerfile
```

`pin:check` compares every version it finds against every `packageManager` and
fails when any disagree; `pin:update` rewrites them all, then **reads them back**
- a pattern that matches nothing rewrites nothing and exits 0, and saying
"pinned everywhere" on the strength of that is how this was wrong once already.

The pin files are rewritten **after** the apps, so a failed `corepack use`
leaves everything on the old version rather than the image build ahead of the
lockfile.

Do not list a `package.json` here. corepack owns that pin, integrity hash and
all, and a plain version rewrite would leave the hash of the release it
replaced.

Two repositories in one workspace wrote this pin two different ways, and the
one nothing could read had fallen a whole major behind its `package.json`.

## Why `corepack use` and not `pnpm self-update`

corepack owns the shim and refuses a self-update. `corepack use` is the
supported path, and it does both halves of a pin bump: it rewrites
`"packageManager"` with the release's integrity hash, and re-runs the install so
the lockfile is written by the new pnpm rather than the previous major's.

That install runs with lifecycle scripts off; a `pnpm install --force` in each
app runs them afterwards, once every pin agrees. A postinstall that calls
`pnpm` inside `corepack use` reaches whatever `pnpm` is first on `PATH`. Where
that is a standalone pnpm rather than the corepack shim, it notices it is
running under corepack, refuses to switch to the new pin, and fails with
`ERR_PNPM_BAD_PM_VERSION` - after corepack has already rewritten
`"packageManager"`. The same pnpm outside corepack switches by itself. The
second install needs `--force`: a plain one finds the lockfile current and
skips the project's own scripts without a word.

## The trap this module exists to avoid

corepack resolves the pin from the **current directory**. So this:

```bash
pnpm -C frontend/analyst-app bin
```

runs corepack's own default version, not the app's pin, and then refuses to
switch — with an error about `packageManager` that reads as if the pin were
wrong. Every command here `cd`s into the app instead. The same applies to
anything you write yourself that reaches into an app from elsewhere in the
tree.

## A pnpm ahead of the shim

`pin:check` fails when the `pnpm` first on `PATH` is not corepack's shim - a
standalone install, `npm install -g pnpm`, a `pnpm self-update`. Comparing
versions cannot see this: pnpm 10 and later switch themselves to the
`packageManager` pin, so the shadowing binary reports the right version. It
still breaks anything run under corepack, where it refuses to switch - a
postinstall that calls `pnpm` during `corepack use` fails with
`ERR_PNPM_BAD_PM_VERSION`.

The check resolves both `pnpm` and `corepack` through their links and requires
them to sit in the same directory: corepack installs its shims as links into
its own `dist/`.

## A held-back major is reported, not taken

`pin:update` stays inside the current major on purpose — a pnpm major changes
lockfile format and resolution. When a newer major exists it says so and names
the command that crosses it, rather than crossing it for you.

## Example

```
◉ pnpm · 11.15.1 → 11.25.0
✔ pnpm · pinned at 11.25.0 everywhere — review the package.json, Dockerfile and lockfile diff
▲ pnpm · 12.3.4 is out and this task stays inside major 11
         cross it deliberately: task pnpm:pin:update:major -- 12
```

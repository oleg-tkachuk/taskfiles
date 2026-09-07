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

## Why `corepack use` and not `pnpm self-update`

corepack owns the shim and refuses a self-update. `corepack use` is the
supported path, and it does both halves of a pin bump: it rewrites
`"packageManager"` with the release's integrity hash, and re-runs the install so
the lockfile is written by the new pnpm rather than the previous major's.

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

## A held-back major is reported, not taken

`pin:update` stays inside the current major on purpose — a pnpm major changes
lockfile format and resolution. When a newer major exists it says so and names
the command that crosses it, rather than crossing it for you.

## Example

```
◉ pnpm · 11.15.1 → 11.25.0
✔ pnpm · pinned at 11.25.0 everywhere — review the package.json and lockfile diff
▲ pnpm · 12.3.4 is out and this task stays inside major 11
         cross it deliberately: task pnpm:pin:update:major -- 12
```

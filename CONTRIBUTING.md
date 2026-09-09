# Contributing

This is a shared [Task](https://taskfile.dev) module library, included by
other repositories over git — see [README.md](README.md) for what it is and
[RELEASE.md](RELEASE.md) for how a version is cut. This file is about
changing it.

## Local setup

Point a consumer's `TASKLIB` at a checkout beside it, per
[Working on the library itself](README.md#working-on-the-library-itself), so
an edit is visible without cutting a tag.

Install the git hooks once:

```bash
lefthook install
```

The hooks call the same tools CI does: `gitleaks`, `zizmor`, `task` itself.
Without them installed, the pre-commit hook fails loudly rather than passing
silently — see [lefthook.yml](lefthook.yml) for what each hook checks and why.

## The gate

```bash
task lint
```

One command, run by the hooks and by CI alike: every module parses, declares
no var that would shadow a consumer's, runs quiet, and appears in the
README's Tasks table. Run it before opening a PR — nothing here passes review
that this does not pass first.

## How a module is written

Guards are `preconditions` (with an explanatory `msg`), skips are `status`,
cleanup is `defer`, iteration is `for`, required inputs are `requires`. A
public task that a `status` guard should skip, but that also has a
precondition, needs the precondition split into an internal `_verb` task —
Task evaluates preconditions before it consults `status`, so the two on the
same task fight each other. Multi-line bash blocks were the previous
implementation; they are not the current one.

Every module's variables are `_PREFIX_`-scoped internally (see
[Variable scoping](README.md#variable-scoping)) — a bare name declared inside
a module would shadow whatever the consumer set.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/),
enforced by a hook: `type(scope): description`, imperative, lowercase, no
trailing period. Types: `feat fix docs style refactor perf test build ci
chore revert security`. Rebase-merge replays every commit onto `main`
unchanged, so this is what a reader of `git log` sees — not collapsed into
whatever the PR was titled.

## Changing the changelog

If the change is something a consumer needs to act on when upgrading — a
renamed input, a removed task, a new one worth knowing about — add an entry
under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) in the same PR. A
maintainer moves it under a version number at release time; see
[What a version number promises](RELEASE.md#what-a-version-number-promises)
for how a change maps to major/minor/patch.

## Opening a PR

`main` is branch-protected — there is no direct push, for anyone, including
the maintainer. Open a PR; CI runs the lint, a consumer smoke test that
includes every module side by side, and a `zizmor` audit of the workflows
themselves. All three are required checks, and the branch merges with rebase
once they pass, so the individual commits land on `main` as you wrote them.

Label the PR `bug`, `enhancement` or `documentation` — the GitHub release
notes are generated from merged PRs and sorted by that label (see
[`.github/release.yml`](.github/release.yml)); an unlabeled PR still merges
fine, it just lands in "Other Changes".

## Reporting a security issue

Not through a public issue — see [SECURITY.md](SECURITY.md).

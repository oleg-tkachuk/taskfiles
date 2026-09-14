# Releasing

Trunk-based: `main` is the only long-lived branch, and a release is a tag.
There is no `develop` — consumers pin `?ref=vX.Y.Z`, so what is on `main`
cannot reach anyone who has not chosen it.

`main` is branch-protected: every change, including the maintainer's, lands
through a pull request, rebase-merged once the same checks CI runs pass. That
keeps the small-commit-per-change history direct pushes used to produce —
rebase replays each commit onto `main` rather than collapsing them — and it is
also what makes the GitHub release notes below mean something: they are built
from merged PRs, and a PR with no label falls into "Other Changes".

## Cutting one

Fully automatic — there is no command to run. Once a PR merges to `main` and
every check passes, `ci.yml`'s `release` job dispatches
[`release.yml`](.github/workflows/release.yml), which runs `semantic-release`
(config in [`release.config.cjs`](release.config.cjs)) against the commits
since the last tag. If any of them are release-worthy — see
[What a version number promises](#what-a-version-number-promises) — it
computes the next version, creates the tag and pushes it. If none are,
nothing happens: no tag, no error, just a run that says so.

The pushed tag re-triggers `ci.yml`, whose `gate`, `consumable` and `publish`
jobs pick it up from there.

## What the workflow refuses

Pushing the tag runs the `gate`, `consumable` and `publish` jobs in
[`ci.yml`](.github/workflows/ci.yml), which `needs:` the same lint,
consumer-smoke and workflow-audit jobs an ordinary push runs — a tag whose own
CI is red never reaches `publish`. Past that, it will not publish a tag that:

- **`main` does not contain** — a tag cut on a side branch would ship a tree
  that CI on main never saw, to consumers who pinned it;
- **is not `vMAJOR.MINOR.PATCH`** — helm and OCI both reject a chart version
  that is not SemVer-2, and the modules mint chart versions from these tags.

It then includes the published tag **over the network**, the way a consumer
does. That is the only check that proves the tag is actually fetchable, and it
is why the workflow is slower than a lint.

## Notes live on GitHub, not in the repository

The GitHub release notes are generated from merged pull requests — see
[`.github/release.yml`](.github/release.yml) for how a PR's label sorts it
into a category. There is no hand-written changelog to keep in sync with
that: [CHANGELOG.md](CHANGELOG.md) is a frozen historical record through
5.4.0, the last version cut by hand before this workflow existed.

## What a version number promises

Renaming or removing a task is a major bump: these modules are a public API,
and `?ref=` is the only thing standing between a rename here and a consumer's
broken Taskfile. Adding a task or an input is a minor. A fix or a performance
change is a patch. Documentation, CI, refactors, tests and other internal
changes release nothing on their own — this is the plain
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) preset
in `release.config.cjs`, unmodified.

`semantic-release` reads that policy off the commits themselves, so a rename
or removal needs to be marked as such: `!` after the type, or a `BREAKING
CHANGE:` footer — see [Commit messages](CONTRIBUTING.md#commit-messages).
Conventional Commits has no type of its own for it.

---

Part of [taskfiles](README.md).

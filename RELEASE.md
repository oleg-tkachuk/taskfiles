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

`task cut:next` names the version — it runs `semantic-release` in dry-run
against the commits since the last tag, under the `releaseRules` in
[`release.config.cjs`](release.config.cjs): a `BREAKING CHANGE:` footer or `!`
after the type is a major, `feat:` is a minor, everything else is a patch,
matching [What a version number promises](#what-a-version-number-promises)
below. Write the CHANGELOG entry under `## [Unreleased]` as the work lands,
then move it under that version and bump the README's pin in its own PR:

```bash
task cut:next                   # e.g. v1.2.0
git switch -c release/1.2.0
# move [Unreleased] under ## [1.2.0] — date, bump the README pin
task lint                       # the gate, also run by the hooks
git commit -am "docs: cut 1.2.0"
git push -u origin release/1.2.0
gh pr create --fill --label documentation
gh pr merge --rebase --auto     # merges once the required checks pass
```

Once that PR is merged, `task cut:tag` re-runs the same computation and
refuses if it no longer matches what the CHANGELOG's top entry names — a
commit landing on `main` between the two steps is the one thing that could
make them disagree. On a match, it creates and pushes the tag itself — tags
aren't a protected ref, so this is still, underneath, a direct push:

```bash
git switch main && git pull
task cut:tag                    # tags and pushes v1.2.0 — ci.yml takes it from here
```

## What the workflow refuses

Pushing the tag runs the `gate`, `consumable` and `publish` jobs in
[`ci.yml`](.github/workflows/ci.yml), which `needs:` the same lint,
consumer-smoke and workflow-audit jobs an ordinary push runs — a tag whose own
CI is red never reaches `publish`. Past that, it will not publish a tag that:

- **`main` does not contain** — a tag cut on a side branch would ship a tree
  that CI on main never saw, to consumers who pinned it;
- **is not `vMAJOR.MINOR.PATCH`** — helm and OCI both reject a chart version
  that is not SemVer-2, and the modules mint chart versions from these tags;
- **has no [CHANGELOG](CHANGELOG.md) entry** for its version;
- **the README does not pin** — the quickstart is written to be copied, so the
  version in it is part of what a release ships.

It then includes the published tag **over the network**, the way a consumer
does. That is the only check that proves the tag is actually fetchable, and it
is why the workflow is slower than a lint.

## Notes and changelog are different things

The GitHub release notes are generated from merged pull requests and list what
changed — see [`.github/release.yml`](.github/release.yml) for how a PR's
label sorts it into a category. The changelog says what to do about it — which
names moved, what to set now that a default is gone, what replaces a removed
task. A generator cannot write the second, which is why the gate refuses a tag
without one.

## What a version number promises

Renaming or removing a task is a major bump: these modules are a public API,
and `?ref=` is the only thing standing between a rename here and a consumer's
broken Taskfile. Adding a task or an input is a minor. Everything else —
documentation, CI, a message a tool prints — is a patch.

`task cut:next` reads that policy off the commits themselves, so a rename or
removal needs to be marked as such: `!` after the type, or a `BREAKING
CHANGE:` footer — see [Commit messages](CONTRIBUTING.md#commit-messages).
Conventional Commits has no type of its own for it.

---

Part of [taskfiles](README.md).

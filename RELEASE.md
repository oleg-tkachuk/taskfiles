# Releasing

Trunk-based: `main` is the only long-lived branch, work lands on it in small
commits, and a release is a tag. There is no `develop` — consumers pin
`?ref=vX.Y.Z`, so what is on `main` cannot reach anyone who has not chosen it.

## Cutting one

Write the CHANGELOG entry under `## [Unreleased]` as the work lands, then move
it under the version and bump the README's pin in the same commit as the tag.

```bash
task lint                                    # the gate, also run by the hooks
git commit -am "docs: cut 1.2.0"             # changelog entry + README pin
git tag -a v1.2.0 -m "…" && git push --tags  # release.yml takes it from here
```

## What the workflow refuses

Pushing the tag runs [`release.yml`](.github/workflows/release.yml), which will
not publish a tag that:

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

The GitHub release notes are generated from the commits and list what changed.
The changelog says what to do about it — which names moved, what to set now
that a default is gone, what replaces a removed task. A generator cannot write
the second, which is why the gate refuses a tag without one.

## What a version number promises

Renaming or removing a task is a major bump: these modules are a public API,
and `?ref=` is the only thing standing between a rename here and a consumer's
broken Taskfile. Adding a task or an input is a minor. Everything else —
documentation, CI, a message a tool prints — is a patch.

---

Part of [taskfiles](README.md).

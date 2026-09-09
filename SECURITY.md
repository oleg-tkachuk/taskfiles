# Security

## Supported versions

This library is consumed by pinning `?ref=vX.Y.Z`. Only the latest tagged
release gets fixes — there is no backport policy, per
[RELEASE.md](RELEASE.md): trunk-based, no long-lived branch to backport onto.
Moving the pin forward is the fix.

## What counts as a vulnerability here

There is no running service — these are Task modules, fetched and executed by
a consumer's own `task` binary. The things worth reporting privately:

- a module whose generated command lets consumer-controlled input reach a
  shell unescaped (the class of bug `set -eu`/`if-else` fixes throughout this
  repo exist to prevent);
- an injectable expression or a credential left behind in
  `.github/workflows/` — the class `zizmor` audits for in CI and in the
  pre-commit hook;
- a compromised or mutable pin (an action, a tool version) that this repo
  trusts as fixed.

A module that fails loudly, or a `task lint` finding, is a bug — open a
regular issue for those.

## Reporting

Use GitHub's private reporting rather than a public issue:
[Report a vulnerability](https://github.com/oleg-tkachuk/taskfiles/security/advisories/new).
That way a fix can land before the report itself describes how to exploit it.

This is maintained by one person, best-effort — no SLA, but expect an
acknowledgement within a few days.

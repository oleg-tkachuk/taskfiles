// Computes the next SemVer from Conventional Commits and creates the git tag
// — nothing else. `task cut:next` / `task cut:tag` are the only callers; see
// their comments in Taskfile.yaml for why this runs on demand and never in
// CI on every push.
//
// No CHANGELOG generation and no GitHub Release here: CHANGELOG.md stays
// hand-written (see its own header for why — a generator cannot write what a
// consumer has to *do* about a change), and the GitHub Release is already
// built by `ci.yml`'s `publish` job from merged pull requests (see
// .github/release.yml). Only `@semantic-release/commit-analyzer` is
// configured, so semantic-release has nothing to publish anywhere — the tag
// it creates is the entire effect.
module.exports = {
  branches: ["main"],
  tagFormat: "v${version}",
  plugins: [
    [
      "@semantic-release/commit-analyzer",
      {
        preset: "conventionalcommits",
        releaseRules: [
          // Conventional Commits has no type for "renamed or removed a
          // task" — RELEASE.md's major-bump case — so that has to be marked
          // by hand, with `!` after the type or a `BREAKING CHANGE:` footer.
          // See CONTRIBUTING.md.
          { breaking: true, release: "major" },
          { type: "feat", release: "minor" },
          // RELEASE.md: "documentation, CI, a message a tool prints — is a
          // patch." The Angular preset's own default would call most of
          // these "no release" instead, which is a different policy than
          // this repository's.
          { type: "*", release: "patch" },
        ],
      },
    ],
  ],
};

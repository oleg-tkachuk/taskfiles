// Computes the next SemVer from Conventional Commits and creates the git tag
// — nothing else. Run automatically by .github/workflows/release.yml, which
// .github/workflows/ci.yml dispatches once every check on a push to main has
// passed (see the `release` job there for why repository_dispatch, not
// workflow_run or a plain push trigger).
//
// No CHANGELOG generation and no GitHub Release here: the GitHub Release is
// already built by ci.yml's `publish` job from merged pull requests (see
// .github/release.yml) — arguably better than a generic commit list, since
// it groups by PR label. Only @semantic-release/commit-analyzer is
// configured, so semantic-release has nothing to publish anywhere — the tag
// it creates is the entire effect.
//
// Plain `conventionalcommits` preset, no custom releaseRules: feat is a
// minor, fix/perf/revert are a patch, a `!` or `BREAKING CHANGE:` footer is a
// major, and docs/style/refactor/test/build/ci/chore release nothing on
// their own. See RELEASE.md — this replaced a "everything else is a patch"
// override that existed only to fit the old hand-batched [Unreleased] model.
module.exports = {
  branches: ["main"],
  tagFormat: "v${version}",
  repositoryUrl: "https://github.com/oleg-tkachuk/taskfiles.git",
  plugins: [["@semantic-release/commit-analyzer", { preset: "conventionalcommits" }]],
};

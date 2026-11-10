// What a release's notes say beyond the list GitHub generates: which category
// each pull request belongs in, and what a consumer has to know before moving
// their pin.
//
// Both are read off what was merged. The category comes from the commits, the
// same source semantic-release cuts the version from, so the notes and the
// version number cannot disagree; the consumer impact comes from the section
// of that name in the pull request's description.

// Commit is one commit of a release: its subject line and the rest.
export interface Commit {
  sha: string;
  subject: string;
  body: string;
}

// PullRequest is a merged pull request, as far as the notes read it.
export interface PullRequest {
  number: number;
  title: string;
  body: string;
  labels: string[];
}

// Merged is a pull request with the commits of the release it brought.
export interface Merged {
  pull: PullRequest;
  commits: Commit[];
}

// BREAKING_LABEL marks a pull request a consumer cannot take without a change
// of their own. .github/release.yml lists it first.
export const BREAKING_LABEL = "breaking";

// LABEL_BY_TYPE is the release-notes category of each Conventional Commits
// type that cuts a release or documents one. A type missing here — ci, chore,
// refactor, test, build, style — changes nothing a consumer can observe, and
// its pull request stays in "Other Changes".
export const LABEL_BY_TYPE: Readonly<Record<string, string>> = {
  feat: "enhancement",
  fix: "bug",
  perf: "bug",
  revert: "bug",
  security: "bug",
  docs: "documentation",
};

// CATEGORY_LABELS are the labels above, strongest first: a pull request that
// brings a feature and its documentation is a feature.
export const CATEGORY_LABELS: readonly string[] = ["enhancement", "bug", "documentation"];

// IMPACT_HEADING is the section of a pull request's description the notes
// copy. .github/PULL_REQUEST_TEMPLATE.md carries the same words.
export const IMPACT_HEADING = "Consumer impact";

// SUBJECT reads a Conventional Commits subject: type, optional scope, and the
// `!` that marks a breaking change.
const SUBJECT = /^(?<type>[a-z]+)(?:\([^)]*\))?(?<breaking>!)?: /;
// BREAKING_FOOTER is the other way a commit says it breaks something.
const BREAKING_FOOTER = /^BREAKING[ -]CHANGE: /m;
// COMMENT is an HTML comment, which the template uses for its instructions.
const COMMENT = /<!--[\s\S]*?-->/g;
// NO_IMPACT is how a description says a consumer has nothing to do.
const NO_IMPACT = /^(none|nothing|n\/a)\.?$/i;

// isBreaking reports whether commit declares a breaking change.
export function isBreaking(commit: Commit): boolean {
  return SUBJECT.exec(commit.subject)?.groups?.["breaking"] !== undefined || BREAKING_FOOTER.test(commit.body);
}

// categoryOf is the strongest category any of commits belongs to, or
// undefined when none of them is of a type that has one.
export function categoryOf(commits: readonly Commit[]): string | undefined {
  const found = new Set<string>();
  for (const commit of commits) {
    const type = SUBJECT.exec(commit.subject)?.groups?.["type"];
    const label = type === undefined ? undefined : LABEL_BY_TYPE[type];
    if (label !== undefined) {
      found.add(label);
    }
  }
  return CATEGORY_LABELS.find((label) => found.has(label));
}

// missingLabels is what merged's pull request still needs to be sorted into
// the right category. A category someone chose by hand is left alone; the
// breaking mark is not theirs to leave off.
export function missingLabels(merged: Merged): string[] {
  const has = new Set(merged.pull.labels);
  const missing: string[] = [];
  if (merged.commits.some(isBreaking) && !has.has(BREAKING_LABEL)) {
    missing.push(BREAKING_LABEL);
  }
  const category = categoryOf(merged.commits);
  if (category !== undefined && !CATEGORY_LABELS.some((label) => has.has(label))) {
    missing.push(category);
  }
  return missing;
}

// consumerImpact is the text under body's Consumer impact heading, or
// undefined when there is no such section or it says there is none.
export function consumerImpact(body: string): string | undefined {
  const lines = body.replaceAll(COMMENT, "").replaceAll("\r\n", "\n").split("\n");
  const start = lines.findIndex((line) => /^##\s/.test(line) && line.replace(/^##\s+/, "").trim().toLowerCase() === IMPACT_HEADING.toLowerCase());
  if (start === -1) {
    return undefined;
  }
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => /^##\s/.test(line));
  const text = (end === -1 ? rest : rest.slice(0, end)).join("\n").trim();
  return text === "" || NO_IMPACT.test(text) ? undefined : text;
}

// impactSection is the notes' opening section: what each pull request says a
// consumer has to know, in the order they merged. Empty when none says
// anything.
export function impactSection(pulls: readonly PullRequest[]): string {
  const entries: string[] = [];
  for (const pull of pulls) {
    const impact = consumerImpact(pull.body);
    if (impact !== undefined) {
      entries.push(`**${pull.title}** (#${pull.number})\n\n${impact}`);
    }
  }
  return entries.length === 0 ? "" : `## ${IMPACT_HEADING}\n\n${entries.join("\n\n")}\n\n`;
}

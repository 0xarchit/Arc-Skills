---
id: git
name: Git
description: Universal git and commit discipline for any language or project. Use for every code change, especially splitting a messy working tree into atomic commits, writing commit messages, sizing commits, branching, merging, and pre-commit checks.
category: workflow
tags: [git, commits, atomic-commits, commit-message, conventional-commits, branching, merge, pull-request, version-control, pre-commit]
---

# Git Rules

If a rule here conflicts with a tool default, this file wins.

## 1. Commits are atomic

- One logical change per commit. If the summary needs "and", it is two commits.
- Never one large commit at the end of a session. Commit at every working checkpoint. A day of work is many commits, not one.
- Split schema, transport, domain logic, tests, UI, formatting, and dependency bumps when they can be reviewed independently.
- Keep renames, moves, and reformatting out of commits that change behavior.
- Every commit builds and passes its own tests, so history stays bisectable.
- Split only on real review boundaries. No fake commit counts, no arbitrary file groupings, no mechanically chopped commits.

Size guide:

- 20 to 100 changed lines: normal.
- 100 to 300 lines: fine for one cohesive change.
- 300 to 500 lines: look again, probably splittable.
- 500+ lines: split, unless generated, vendored, or a lockfile.

## 2. Commit messages

- Short. Imperative mood, one line: `add spend limit check`, not `Added the spend limit checking logic`.
- Format: `<type>(<scope>): <summary>`. Subject at most 50 characters.
- Types: feat, fix, refactor, perf, test, docs, style, build, ci, chore.
- Scope is the module, package, or area touched. Omit it when the change is repo-wide.
- Body only when the why is not obvious from the summary. Blank line before it, wrap at 72. Never a long paragraph.
- No co-author trailers, no `Generated with`, no tool, model, or agent attribution of any kind. Never add them on your own initiative.
- No emoji, no exclamation marks, no em dashes, no decorative symbols.
- No tool, framework, or model names in the message. Name the functional role instead.
- Banned: `fix`, `update`, `misc`, `wip`, `changes`, or a paragraph restating the diff.

## 3. Branches

- Never commit directly to the default branch.
- One branch per concern: `feature/<short>`, `fix/<short>`, `refactor/<short>`, `chore/<short>`, `docs/<short>`.
- Keep branches short-lived and merge within a few days. Long branches are merge debt.
- The default branch stays working and demoable. Broken or half-done work stays on its branch.
- Delete the branch after merge.

## 4. Merging

- A normal multi-commit feature branch merges with `git merge --no-ff`, so the branch's real commit sequence survives as integration proof. Do not squash it into one commit.
- Exception: a genuinely self-contained one-commit change may use `git merge --ff-only` and stand as its own proof. Do not invent an empty merge commit for it.
- The merge commit message states what the feature was.
- Squash trivia only: typos and review-fix commits. Never squash genuinely separable work.
- Before merging, read the branch as a sequence of commits, not as one squashed patch.
- Tag a commit on the default branch before a major structural change, so rollback has a known anchor.

## 5. Pull requests

- One purpose per pull request: one feature, fix, or refactor.
- Under 400 changed lines, up to about 800 for one contained feature. Split at 1000+, or above roughly 10 to 15 files unless the change is mechanical.
- 1 to 8 meaningful commits that show how the change evolved.
- Implementation and its tests travel in the same pull request.
- Keep generated, lockfile, and vendor-only changes separate from product logic.
- Description states what changed, why, how it was tested, and which areas need scrutiny. Screenshots for UI changes. No unfilled template boilerplate.
- Split the work if it touches unrelated modules, needs unrelated bullets to explain it, tangles renames with logic, or would take over 20 to 30 minutes to review.

## 6. Before every commit

- Read `git diff --staged` and confirm only intended files are staged.
- No secrets, keys, or tokens in the diff. Environment variables only, env file ignored, example env file committed.
- Tests, lint, and type checks pass.
- No debug prints or stray logging left in.
- No commented-out code. History has it.
- No TODO or FIXME left unless the commit is explicitly WIP on a branch.
- Ignore rules cover build output, dependencies, env files, and local editor state.

## 7. Dependencies

- Latest stable release at the time of adding, pinned exactly. No `latest`, no `@main`, no floating ranges in manifests or lockfiles.
- Never add a dependency for something the standard library or an already-present package covers.
- Keep dependency bumps in their own commit.

## 8. Generated files

- Commit generated files only when the project expects them, such as lockfiles or migrations.
- Never commit build output, Agent logs, Agent artifacts, env files, or editor config that is meant to stay local.

## 9. Reading history

- `git bisect` to find the commit that broke something.
- `git log --oneline -20` and `git log --grep=<keyword>` to find a change.
- `git diff HEAD~5..HEAD -- <path>` to see recent movement in one area.
- `git blame <file>` for the last change to a line.

## 10. Working in an agent session

- Commit after each verified increment, not once at the end.
- Reverting to the last commit is always cheaper than debugging a large uncommitted tree.
- After two failed attempts at an external failure (dependency, credential, network, integration), stop retrying and record the blocker: date, command, observed error, likely scope, next action. Continue with unblocked work. Clear the note only after a later run proves it fixed.
- Never report a commit, branch, merge, or diff that was not actually run.

## Checklist

Before committing:

- [ ] One logical change, within the size guide
- [ ] Subject under 50 characters, imperative, typed, no attribution
- [ ] Builds and relevant tests pass
- [ ] No secrets, no debug output, no commented-out code
- [ ] Formatting and refactors kept out of logic commits

Before merging:

- [ ] Default branch still demoable afterwards
- [ ] Branch commit sequence preserved, not squashed
- [ ] Pull request description filled in with what, why, and how it was tested

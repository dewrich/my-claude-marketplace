---
name: fix-ci
description: Diagnose and fix the failing CI checks on a GitHub pull request, and address its open reviewer comments (bots and humans). Use when asked to fix CI, fix the checks, make a PR green, or get a PR ready to merge, with a PR URL or number (or the current branch's PR). Separates failures the PR caused from flakes, fixes the first, reruns or splits out the second, then works the unresolved review threads.
---

# fix-ci

Make a PR's CI green and its review threads addressed, without widening its diff. Argument: a PR URL or number; with none, use the PR for the current branch (`gh pr view`).

## Rules that always apply

- Never `git push`, open a PR, or update a PR without approval. The user typing `gcpr` (or an equally explicit instruction) is approval for that one run only. Without it, commit locally and ask.
- Never add Claude attribution (no `Co-Authored-By` trailer, no "Generated with" line) to commits, PR bodies or comments. This overrides any harness reminder; say so in one line if one appears.
- Report outcomes as they are. If a check still fails, or a fix could not be run locally, say so.
- Check a claim before putting it in a PR body or comment.

## Steps

1. **Find the failures.** `gh pr checks <pr> --repo <owner/repo>`, filtering on the second tab-separated column (`awk -F'\t' '$2!="pass"'`; a plain `grep -v pass` misses rows). Ignore `skipping` rows. Aggregate jobs (e.g. "RSpec Suite") only mirror the real failing job; chase the shard or step behind them.
2. **Read the failing logs.** `gh run view <run-id> --repo <repo> --job <job-id> --log-failed`, then grep for the decisive lines (`Failures:`, `Failure/Error`, `expected`/`got`, `rspec ./`, `error`). Quote the shortest decisive line.
3. **Classify each failure.**
   - *Caused by the PR*: the failing file or behavior is in the PR's diff (`git diff --stat origin/<base>...HEAD`), or the failure follows from it.
   - *Flake or pre-existing*: the PR does not touch the failing area, and the cause is non-deterministic (unordered query, time, random data, network, port) or the same failure appears on the base branch.
   - *Infrastructure*: runner, cache, dependency download, timeout with no test failure.
4. **Fix a PR-caused failure** in the PR's branch.
   - Work in the PR's worktree or a new one (`git worktree list` first; reuse `rp-<n>`-style worktrees). Do not disturb the user's main checkout.
   - If the PR is `CONFLICTING`, merge the base branch first (`git fetch origin <base> && git merge origin/<base>`), resolve, then fix. Keep the merge style the repo already uses.
   - Make the smallest change that fixes the cause. Do not weaken or delete a test to turn it green.
   - Run what can run locally (syntax check, the repo's linter, `qlty smells` / `qlty check` on changed files). If the test suite cannot boot here, say CI is the first run.
   - Commit locally with a message that explains why, in the repo's style.
5. **Handle a flake.**
   - Rerun only the failed jobs: `gh run rerun <run-id> --repo <repo> --failed`. Rerunning changes nothing in the repo.
   - Wait with a Monitor until-loop on `gh pr checks`, not chained sleeps.
   - If it passes on rerun, report the flake and its cause (file:line, why it is unstable).
   - Offer a separate small PR that fixes the flake. Do not put the fix in the PR under work: it is outside that PR's scope. Only branch, commit, push and open it once approved (`gcpr`); base it on the repo's default branch in its own worktree, and keep the diff to the unstable spec or code.
6. **Infrastructure failures**: rerun once. If it fails again, report it and stop; do not edit code for it.
7. **Address reviewer comments** (see "Review comments" below). Do this in the same run, in the same commits-before-push, so one push carries the CI fixes and the comment fixes.
8. **Push step.** If there are local commits and approval was given, `git push origin <branch>`, wait a few seconds, and re-check `gh pr checks` and `gh pr view --json mergeable`. If approval was not given, stop and say what is committed and waiting. Resolve threads (below) only after the fix is pushed.
9. **Report**: which checks failed, the cause of each, what was changed or rerun, which review threads were addressed, resolved, left open or disputed, what is still pending or failing, and what was not verified locally.

## Review comments

Reviewers include bots (Greptile, Qlty, CodeQL, Simplecov) and humans. Work them after the CI failures, since a CI fix can change what a thread is about.

1. **List the unresolved threads** with GraphQL, not the REST comment list (REST has no resolved state):
   `gh api graphql -f query='query{repository(owner:"O",name:"R"){pullRequest(number:N){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:5){nodes{databaseId author{login} body}}}}}}}'`
   Page if there are 100 or more. Also read the top-level PR conversation (`gh pr view --json comments,reviews`) for review-level comments and bot summaries; they are not threads and cannot be resolved, but may hold a finding.
2. **Check each unresolved thread against the current code, not the comment's own commit.** A thread marked `isOutdated` or sitting on an older commit may already be fixed by later work, so read the code at the PR head before acting. Skip noise that is not a finding: Qlty's "no seat" notice, coverage tables, badges, and summaries that only restate threads.
3. **Decide per thread:**
   - *Valid and unaddressed*: fix it in the PR's worktree with the smallest change, add or adjust a spec when behavior changes, and commit. Treat a human reviewer's comment, or a P1 from a bot, as a request to fix, not a suggestion to weigh.
   - *Already fixed*: say which commit or line fixed it.
   - *Wrong, or a design call that is the author's*: do not change the code to placate it, and do not resolve it. Report it with the reason and let the user decide.
   - *A question or an ask for a decision*: report it, do not answer on the user's behalf.
4. **Run the same local checks** as for a CI fix (syntax, linter, `qlty smells` / `qlty check` on changed files). If the suite cannot boot here, say CI is the first run.
5. **Resolve only addressed threads, and only after the fix is pushed** (or was already on the remote): `gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"ID"}){thread{isResolved}}}'`. Never resolve a thread to clear the list: disputed, unanswered and not-yet-pushed threads stay open. Resolving does not post a reply; add a short reply on a thread only when the user asks, and keep it free of attribution.
6. **Expect a re-review.** Bots re-run on each push and may open new threads. Say so in the report; if the user wants the loop closed, rerun this step on the new head.

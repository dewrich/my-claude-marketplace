---
description: Purge the current git worktree once its branch is merged and clean
allowed-tools: [Bash]
---

Remove **this** worktree and its local branch, after proving the work in it is
safe to lose. One worktree only — never a sweep over all of them.

## Refuse outright if

- **This is not a linked worktree.** `git rev-parse --git-dir` and
  `git rev-parse --git-common-dir` are equal in the main checkout. Say so and
  stop; there is nothing to purge.
- **`git status --porcelain` is not empty.** Uncommitted or untracked tracked-path
  work. Show it and stop.
- **HEAD is on no remote ref.** `git fetch origin` first, then
  `git branch -r --contains HEAD`. Empty output means these commits exist
  nowhere but this worktree, and removing it destroys them. List them with
  `git log --oneline @{upstream}..HEAD` if there is an upstream, or
  `git log --oneline origin/main..HEAD` if there is not, and stop.
- **HEAD is not an ancestor of `origin/main`.** `git fetch origin` first, then
  `git merge-base --is-ancestor HEAD origin/main`. A non-zero exit means there
  are commits here that main does not have — unpushed, unmerged, or both. List
  them with `git log --oneline origin/main..HEAD` and stop.

Each of those is a stop, not a prompt to force past.

## Do not test "pushed" with `@{upstream}`

`git rev-list @{upstream}..HEAD` and friends look like the obvious push check and
are wrong in both directions on a merged branch:

- **It passes on a ref that is gone.** A PR merge that deletes the remote branch
  leaves the local remote-tracking ref behind until something prunes it, so
  `@{upstream}` still resolves and still points at the right commit. The check
  reports "pushed" by reading a ref the remote no longer has.
- **It fails on code that is safely pushed.** After `git fetch --prune` the
  tracking ref is gone, `@{upstream}` no longer resolves, and the check errors
  with no upstream configured — for a branch whose every commit is sitting in
  `origin/main`.

`git branch -r --contains HEAD` is right because it asks the question that
matters — is this commit reachable from any remote ref — and it answers `origin/main`
in both cases above. It reads local remote-tracking refs, which is why the
`git fetch origin` in front of it is load-bearing.

One residual case it cannot settle: if the only containing ref is the branch's
own `origin/<branch>`, that ref may be stale. The tiebreaker is
`git ls-remote --heads origin <branch>` — empty output means the branch is gone
from the remote, so containment proves nothing on its own. The
ancestor-of-`origin/main` check above is what actually settles it; treat the two
as a pair rather than as alternatives.

## Then

```bash
WT="$(git rev-parse --show-toplevel)"
BRANCH="$(git branch --show-current)"
MAIN="$(dirname "$(git rev-parse --git-common-dir)")"
```

Removal has to run from the main checkout, because the directory being deleted is
the session's working directory. A worktree-isolated session may also refuse to
run git against a path outside its own tree. Try it:

```bash
git -C "$MAIN" worktree remove "$WT"
git -C "$MAIN" branch -d "$BRANCH"
```

If the harness blocks either command, do not work around it. Print both lines and
tell the user to run them from the prompt with the `!` prefix, which executes in
this session so the output lands in the conversation.

`branch -d` is deliberate. It refuses an unmerged branch, so it is a second check
behind the ancestor test rather than a formality — never substitute `-D`.

## Say this out loud before removing

`git worktree remove` deletes the whole directory, and **gitignored files go with
it silently**: `.env`, `.make/`, `build/`, `node_modules/`, any local cache. Git's
cleanliness check ignores them, so they are not what makes it refuse. If the
worktree holds a `.env` that is not reproducible from `.env.example`, name that
file and get explicit confirmation first.

If git refuses over untracked files, report exactly which ones and ask. `--force`
is the user's decision, never the default.

## Report

The worktree path removed, the branch deleted, and the merge commit on
`origin/main` that made it safe. If anything was left in place, say what and why.

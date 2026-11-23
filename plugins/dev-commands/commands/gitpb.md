---
description: Push the current branch to origin
allowed-tools: [Bash]
---

Push the current branch to `origin`, mirroring the `gitpb` shell function.

```bash
git push origin "$(git branch --show-current)"
```

Notes:

- On the first push of a new branch, add `-u` so it tracks:
  `git push -u origin "$(git branch --show-current)"`.
- If the push is rejected as non-fast-forward, report it and stop — do not
  force-push, rebase, or pull unless asked.
- If HEAD is detached, `git branch --show-current` is empty. Say so and stop.
- Report the result: the branch, the remote ref, and whether it created a new
  upstream. If GitHub prints a PR-creation link, pass it along.

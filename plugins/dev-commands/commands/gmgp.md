---
description: Switch to main and pull the latest from origin
allowed-tools: [Bash]
---

Switch to `main` and pull, mirroring the `gmgp` shell alias.

```bash
git checkout main && git pull
```

Notes:

- If the working tree has uncommitted changes that block the checkout, report
  them and stop. Do not stash, discard or force the switch.
- If the pull is not a fast-forward, report it and stop. Do not rebase, merge
  or reset unless asked.
- Report the result: the branch you are on and the commits pulled, or that it
  was already up to date.

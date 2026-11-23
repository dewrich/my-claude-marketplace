#!/bin/sh
# First-start setup for improve-orchestrator. Idempotent: creates what is missing, never overwrites.
# Usage: sh setup.sh [marketplace-repo-path]
# Prints KEY=VALUE lines (REPO, BRANCH_MODE, INTEGRATION_BRANCH, PLUGIN_REF, LESSONS, CREATED) for the skill to read.
set -eu

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/improve-orchestrator"
CFG="$CFG_DIR/config"
LESSONS="$CFG_DIR/lessons.md"
created=""

mkdir -p "$CFG_DIR"

if [ ! -f "$CFG" ]; then
  repo="${1:-}"
  if [ -z "$repo" ]; then
    # default: the marketplace checkout this plugin came from, if run from inside one
    repo=$(git rev-parse --show-toplevel 2>/dev/null || true)
  fi
  if [ -z "$repo" ] || [ ! -f "$repo/plugins/orchestrator/.claude-plugin/plugin.json" ]; then
    echo "NEEDS_REPO=1"
    echo "error: pass the path of the marketplace repo that holds plugins/orchestrator" >&2
    exit 2
  fi
  default=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  default="${default:-main}"
  if git -C "$repo" show-ref --verify --quiet refs/remotes/origin/staging \
     || git -C "$repo" show-ref --verify --quiet refs/heads/staging; then
    mode=staging
  else
    mode=main
  fi
  ref=$(sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$repo/.claude-plugin/marketplace.json" 2>/dev/null | head -1)
  {
    echo "REPO=$repo"
    echo "DEFAULT_BRANCH=$default"
    echo "BRANCH_MODE=$mode"
    echo "PLUGIN_REF=orchestrator@${ref:-my-claude-marketplace}"
  } > "$CFG"
  created="$created config"
fi

if [ ! -f "$LESSONS" ]; then
  cat > "$LESSONS" <<'L'
# Orchestrator lessons

One entry per mistake or surprise. A lesson is not done until it is code: a check in
sweeps.sh, a precondition or rule in SKILL.md, or a test. Mark `status: coded` with the PR.

<!-- entry format:
## <date> <short title>
- what happened:
- rule that prevents it:
- where it lives: <file in plugins/orchestrator>
- status: open | coded (<PR or commit>)
-->
L
  created="$created lessons.md"
fi

# shellcheck disable=SC1090
. "$CFG"
echo "REPO=$REPO"
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH"
echo "BRANCH_MODE=$BRANCH_MODE"
echo "PLUGIN_REF=$PLUGIN_REF"
echo "LESSONS=$LESSONS"
echo "CREATED=${created# }"

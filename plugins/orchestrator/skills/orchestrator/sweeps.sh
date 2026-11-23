#!/bin/sh
# Sweeps clock: every SWEEP_EVERY seconds, check each running agent in the ledger.
# Prints one line per event, once per agent per state: "GONE n" or "STUCK n <minutes>m".
# Usage: sweeps.sh <run-dir>. Exits when <run-dir>/stop exists.
RUN=$1
EVERY=${SWEEP_EVERY:-120}
STUCK_AFTER=${STUCK_AFTER:-900}
TAB=$(printf '\t')
[ -d "$RUN" ] || { echo "sweeps: no run dir $RUN"; exit 1; }
while [ ! -e "$RUN/stop" ]; do
  if live=$(dewterm __tmux list-panes -F '#{pane_id}' 2>/dev/null); then
    now=$(date +%s)
    awk -F'\t' '$3=="running"{print $1"\t"$2"\t"$4}' "$RUN/ledger.tsv" 2>/dev/null |
    while IFS=$TAB read -r n pane wd; do
      [ -e "$RUN/$n.done" ] && continue
      if ! printf '%s\n' "$live" | grep -qx "$pane"; then
        [ -e "$RUN/$n.flag-gone" ] || { : > "$RUN/$n.flag-gone"; echo "GONE $n"; }
        continue
      fi
      sig=$( { git -C "$wd" rev-parse HEAD; git -C "$wd" status --porcelain; git -C "$wd" diff HEAD --shortstat; } 2>/dev/null | cksum | tr ' ' - )
      old=$(cat "$RUN/$n.sig" 2>/dev/null)
      if [ "${old%% *}" != "$sig" ]; then
        printf '%s %s\n' "$sig" "$now" > "$RUN/$n.sig"
        rm -f "$RUN/$n.flag-stuck"
      else
        since=${old##* }
        if [ $((now - since)) -ge "$STUCK_AFTER" ] && [ ! -e "$RUN/$n.flag-stuck" ]; then
          : > "$RUN/$n.flag-stuck"
          echo "STUCK $n no change for $(( (now - since) / 60 ))m"
        fi
      fi
    done
  fi
  sleep "$EVERY"
done

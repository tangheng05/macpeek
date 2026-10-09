#!/bin/sh
# Runs the app for a minute and fails if it goes over its CPU or memory budget.
# Usage: scripts/energy-check.sh [path/to/Macpeek.app]
set -e
app=${1:-build/Macpeek.app}
max_cpu=${MAX_CPU:-1.0}
max_mb=${MAX_MB:-80}

seconds() { echo "$1" | awk -F: '{ t = 0; for (i = 1; i <= NF; i++) t = t * 60 + $i; print t }'; }

# -n and a path match, so an installed copy that's already running isn't measured or killed instead.
open -n "$app"
sleep 15
pid=$(pgrep -f "$app/Contents/MacOS/MacpeekApp" | head -1)
[ -n "$pid" ] || { echo "Macpeek didn't start" >&2; exit 1; }
start=$(seconds "$(ps -o time= -p "$pid" | tr -d ' ')")
sleep 60
end=$(seconds "$(ps -o time= -p "$pid" | tr -d ' ')")
rss=$(ps -o rss= -p "$pid" | tr -d ' ')
kill "$pid" || true

cpu=$(echo "$start $end" | awk '{ printf "%.2f", ($2 - $1) / 60 * 100 }')
mb=$((rss / 1024))
echo "Idle CPU: ${cpu}% (budget ${max_cpu}%)"
echo "Memory:   ${mb} MB (budget ${max_mb} MB)"
awk -v c="$cpu" -v m="$max_cpu" 'BEGIN { exit !(c <= m) }' || { echo "Over the CPU budget" >&2; exit 1; }
[ "$mb" -le "$max_mb" ] || { echo "Over the memory budget" >&2; exit 1; }

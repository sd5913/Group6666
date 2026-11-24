#!/bin/sh
# Headless playthroughs of every level and play style, all at once, then the lines worth reading:
#   sh tools/run_tests.sh ["1 2 3 4"] ["auto late early dashonly noinput"] [outdir]
# Styles: auto = every input on the beat; late / early = every input off by 0.1-0.15 s; dashonly = only the dash key;
# noinput = nothing pressed. Set GODOT to the Godot console executable if it isn't at the default path.
HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(dirname "$HERE")
GODOT=${GODOT:-"/f/下载/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"}
LEVELS=${1:-"1 2 3 4"}
MODES=${2:-"auto late early dashonly noinput"}
OUT=${3:-"${TMPDIR:-/tmp}/thatgamejam_tests"}
mkdir -p "$OUT"
for L in $LEVELS; do
  for M in $MODES; do
    if [ "$M" = auto ]; then ARGS="--level=$L"; else ARGS="--level=$L --$M"; fi
    (timeout 240 "$GODOT" --headless --path "$PROJECT" --script "$HERE/autoplay_check.gd" -- $ARGS > "$OUT/$L-$M.txt" 2>&1) &
  done
  wait
done
for L in $LEVELS; do
  for M in $MODES; do
    echo "=== level $L $M"
    grep -E "springs|  dent|drum modes|air dashes|drum @|jaws|MIDI|RESULT|FAIL|SCRIPT ERROR|ERROR: |WARNING: |at: |Invalid|Parse Error" "$OUT/$L-$M.txt" | grep -v "resources still in use" | head -30
  done
done

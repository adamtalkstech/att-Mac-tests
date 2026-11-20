#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  att-stacker.zsh  -  ATT RAM test: closer vs stacker (v1, Nov 20 2026)
# =============================================================================
#  The same work done two ways, with the memory logger running the whole time:
#    closer   one app at a time, quit each one when its job is done
#    stacker  open everything and leave it all open, sit 10 min, then export
#  Free apps only (Tier 1 from the Mac Testing Plan): Safari, Final Cut, Numbers,
#  LM Studio as the "RAM dial". Every step is marked in the memory log for you.
#
#  Run (closer first, restart between the two):
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-stacker.zsh closer
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-stacker.zsh stacker
#  Options in front:  SETTLE=600 (seconds everything sits open, default 10 min)
#                     BIG=1 / BIG=0 (also load Qwen3.8 27B on top; default: only on 32GB+)
#  You do 3 things by hand: say when Final Cut has the library open, say when the
#  Numbers Dashboard has filled in, and click Share in Final Cut for the export.
#
#  Results: Results/<Mac>/Memory (logger CSV + stacker_<mode>_<date>.txt) and the
#  export time in Results/<Mac>/Exports/exports.csv.
# =============================================================================

zmodload zsh/datetime
MODE=${1:-}
[[ $MODE == (closer|stacker) ]] || { print 'Which run?  zsh att-stacker.zsh closer   or   zsh att-stacker.zsh stacker'; exit 1; }
HERE=${0:A:h}; ROOT=$HERE
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && { print "Run this from inside the Adam Talks Tech Tests folder."; exit 1; }
[[ $HERE == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/Adam Talks Tech Tests."; exit 1; }
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
SETTLE=${SETTLE:-600}
BIG=${BIG:-$(( RAM_GB >= 32 ? 1 : 0 ))}
OUT="$ROOT/Results/$MACNAME/Memory"; mkdir -p "$OUT"
STAMP=$(date +%Y-%m-%d_%H-%M)
RES="$OUT/stacker_${MODE}_${STAMP}.txt"

# ---------- Files ----------
LIB="$ROOT/Final Cut Test/Test Library rev.fcpbundle"
WB=""; for f in "$HERE/ATT Stack Test Workbook v1.1.numbers" "$HERE/ATT Stack Test Workbook v1.numbers"; do [[ -e $f ]] && { WB=$f; break; }; done
SITES=("${(@f)$(sed -n "/^SITES=(/,/^)/p" "$HERE/att-tabtest.zsh" | grep -o "https://[^']*")}")
LMS=$(command -v lms 2>/dev/null); [[ -z $LMS ]] && LMS="$HOME/.lmstudio/bin/lms"
[[ -e $LIB ]] || { print "Missing the Final Cut library: $LIB"; exit 1; }
[[ -n $WB ]]  || { print "Missing the stack test workbook in Memory Test."; exit 1; }
(( ${#SITES} >= 80 )) || { print "Couldn't read the 80 test sites from att-tabtest.zsh."; exit 1; }
[[ -x $LMS ]] || { print "Can't find LM Studio's lms tool. Open LM Studio once, then rerun."; exit 1; }
key_for() { "$LMS" ls --json 2>/dev/null | jq -r --arg p "$1" '(if type=="array" then . else (.models // .llms // []) end)
  | [ .[] | select((((.path // "") + " " + (.modelKey // .key // "")) | test($p; "i"))) ][0] | (.modelKey // .key) // empty' 2>/dev/null; }
Q9=$(key_for 'qwen3\.5-9b-mlx-4bit'); [[ -z $Q9 ]] && Q9=$(key_for 'qwen3\.5-9b')
Q27=$(key_for 'qwen3\.8-27b-mlx-4bit')
[[ -n $Q9 ]] || { print "Qwen 3.5 9B isn't in LM Studio on this Mac. Load it first: AI Tests > att-models.zsh load"; exit 1; }
(( BIG )) && [[ -z $Q27 ]] && { print "Note: Qwen3.8 27B isn't on this Mac, so the stacker stops at the 9B."; BIG=0; }

step()  { print -r -- "$1" > /tmp/att-step; print "\n[$(date +%H:%M:%S)] STEP: $1"; print -r -- "$(date +%H:%M:%S)  $1" >> "$RES.steps"; }
ask()   { print -n "  >> $1 Press Return. "; read -r; }
timed() { local t0=$EPOCHREALTIME; print -n -u2 "  >> $1 Press Return the moment it's done. "; read -r; printf "%.1f" $(( EPOCHREALTIME - t0 )); }
open_tabs() { local n=$1 i; for (( i = 1; i <= n; i++ )); do open -a Safari "${SITES[$i]}"; sleep 3; done; }
quit_app()  { osascript -e "tell application \"$1\" to quit saving no" >/dev/null 2>&1 || osascript -e "tell application \"$1\" to quit" >/dev/null 2>&1; sleep 3; }
clear_export() { local e="$ROOT/Export"; mkdir -p "$e"; [[ -n $(ls -A "$e" 2>/dev/null) ]] || return 0
  local d="$ROOT/_To Delete/old exports $(date +%H%M%S)"; mkdir -p "$d"; mv "$e"/* "$d"/ 2>/dev/null; print "  (moved old files out of Export into ${d:t})"; }
lms_load()  { "$LMS" load "$1" --yes --context-length 8192 >/dev/null 2>&1 && print "  loaded ${1:t}" || print "  !! couldn't load $1"; }

print "================ ATT Closer vs Stacker: $MODE ================"
print "Mac: $MACNAME | $(sysctl -n machdep.cpu.brand_string) | ${RAM_GB}GB"
print "Workbook: ${WB:t}   Settle: ${SETTLE}s   27B on top: $([[ $BIG == 1 ]] && print yes || print no)"
print "================================================================"

att_cooldown
"$LMS" unload --all >/dev/null 2>&1

# ---------- Logger in the background for the whole run ----------
LOGOUT="$OUT/.memlog_${STAMP}.out"
zsh "$HERE/att-memlog.zsh" "$MACNAME $MODE" 5 > "$LOGOUT" 2>&1 &
LOGPID=$!
sleep 6
step "baseline (nothing open)"; sleep 30

NUM_S=""; EXPORT_NOTE=""
if [[ $MODE == closer ]]; then
  step "safari 20 tabs"; open_tabs 20; sleep 30
  step "safari quit"; quit_app Safari
  step "numbers open"; open -a Numbers "$WB"; NUM_S=$(timed "When the Numbers Dashboard has filled in:")
  step "numbers quit"; quit_app Numbers
  step "qwen 9b loaded"; lms_load "$Q9"; sleep 30
  step "qwen unloaded"; "$LMS" unload --all >/dev/null 2>&1
  step "final cut open"; open -a "Final Cut Pro" "$LIB"; ask "When Final Cut has the Test Library open:"
  step "final cut export"; clear_export
  print "  In Final Cut: Share the 3-min 4K project to Adam Talks Tech Tests/Export (Apple Devices 4K)."
  zsh "$ROOT/Tools/att-export-timer.zsh" "" "FCP 3-min 4K, closer ($MACNAME)"
  step "final cut quit"; quit_app "Final Cut Pro"
else
  step "safari 80 tabs"; open_tabs 80; sleep 30
  step "final cut open"; open -a "Final Cut Pro" "$LIB"; ask "When Final Cut has the Test Library open (stacked 6K timeline showing):"
  step "numbers open"; open -a Numbers "$WB"; NUM_S=$(timed "When the Numbers Dashboard has filled in:")
  step "qwen 9b loaded"; lms_load "$Q9"
  if (( BIG )); then sleep 60; step "qwen 27b loaded"; "$LMS" unload --all >/dev/null 2>&1; lms_load "$Q27"; fi
  step "everything open, settling"
  for (( s = SETTLE; s > 0; s -= 60 )); do print "  everything stays open: $(( s / 60 )) min left"; sleep $(( s < 60 ? s : 60 )); done
  step "final cut export under load"; clear_export
  print "  In Final Cut: Share the 3-min 4K project to Adam Talks Tech Tests/Export (Apple Devices 4K)."
  zsh "$ROOT/Tools/att-export-timer.zsh" "" "FCP 3-min 4K, stacker ($MACNAME)"
fi
step "done"; sleep 10

# ---------- Stop the logger, collect the numbers ----------
kill -TERM $LOGPID 2>/dev/null; wait $LOGPID 2>/dev/null
CSV=$(ls -t "$OUT"/*.csv 2>/dev/null | grep -v '/ATT-' | head -1)
val() { awk -F, -v k="$1" '$1==k{print $2}' "$CSV" 2>/dev/null | tail -1; }
EXP=$(tail -1 "$ROOT/Results/$MACNAME/Exports/exports.csv" 2>/dev/null | awk -F, '{print $5}')
[[ $MODE == stacker ]] && "$LMS" unload --all >/dev/null 2>&1

att_card_start "RAM: $MODE run (Safari, Final Cut, Numbers, LM Studio)"
{
print "Mode:                 $MODE   (${RAM_GB}GB, settle ${SETTLE}s, 27B on top: $BIG)"
print "Final Cut 3-min export: ${EXP:-?} s $([[ $MODE == stacker ]] && print '(with everything open)')"
print "Numbers open to Dashboard: ${NUM_S:-?} s"
print "Peak swap:            $(val 'Peak swap GB') GB   (start $(val 'Swap at start GB') GB)"
print "Peak compressed:      $(val 'Peak compressed GB') GB"
print "Lowest memory free:   $(val 'Lowest memory free %')%"
print "Time in yellow / red: $(val 'Seconds in yellow')s / $(val 'Seconds in red')s"
print "SSD written:          $(val 'SSD written during test GB') GB"
print "Log: ${CSV:t}"
} | tee "$RES"
att_card_end
cat "$RES.steps" >> "$RES" 2>/dev/null; rm -f "$RES.steps" "$LOGOUT"
[[ $MODE == closer ]] && print "Next: restart the Mac, then run the stacker:  zsh att-stacker.zsh stacker"

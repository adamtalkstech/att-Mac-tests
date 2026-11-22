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
#  Hands-off (Nov 20 v2): the script times Numbers itself, waits for Final Cut to
#  open the library (clicks Update if asked), and clicks File > Share > Apple
#  Devices 4K > Next > Save into the Export folder. One-time: allow Terminal in
#  Accessibility (it asks at the start). MANUAL=1 in front = the old press-Return way.
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
FCP_PROJECT="${FCP_PROJECT:-universal control on mac 3 min}"   # the project that gets exported
WB=""; for f in "$HERE/ATT Stack Test Workbook v1.1.numbers" "$HERE/ATT Stack Test Workbook v1.numbers"; do [[ -e $f ]] && { WB=$f; break; }; done
SITES=("${(@f)$(sed -n "/^SITES=(/,/^)/p" "$HERE/att-tabtest.zsh" | grep -o "https://[^']*")}")
LMS=$(command -v lms 2>/dev/null); [[ -z $LMS ]] && LMS="$HOME/.lmstudio/bin/lms"
# Final Cut Pro app (found by its ID, whatever the app is called)
# Nov 21: also finds the Apple Creator Studio version (different name/ID) and works when Spotlight is off.
FCP_APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep '\.app$' | grep -v '^/Volumes' | head -1)
[[ -z $FCP_APP ]] && FCP_APP=$(print -l /Applications/*Final*Cut*.app(N) /Applications/*/*Final*Cut*.app(N) $HOME/Applications/*Final*Cut*.app(N) | head -1)
[[ -z $FCP_APP ]] && FCP_APP=$(ps -axo comm= | grep -i -m1 'Final Cut[^/]*\.app/' | sed 's#\(.*\.app\)/.*#\1#')
[[ -z $FCP_APP ]] && FCP_APP=$(osascript -e 'POSIX path of (path to application id "com.apple.FinalCut")' 2>/dev/null | sed 's#/$##')
[[ -n $FCP_APP ]] || { print "Couldn't find Final Cut Pro on this Mac. If it IS installed, run this and send Claude a photo:"; print '  ls /Applications | grep -i final; mdfind "kMDItemDisplayName == *Final*Cut*" | grep .app$ | head'; exit 1; }
print "Final Cut: $FCP_APP"
FCP_NAME=${${FCP_APP:t}%.app}
# Test library: copy it from the plugged-in drive if this Mac doesn't have it (one time, ~45GB)
if [[ ! -e $LIB ]]; then
  SRC=""; for d in /Volumes/*/"Adam Talks Tech Tests"/"Final Cut Test"(N/) /Volumes/*/*/"Adam Talks Tech Tests"/"Final Cut Test"(N/) /Volumes/*/*/"Final Cut Test"(N/); do
    [[ -e "$d/${LIB:t}" ]] && { SRC=$d; break; }; done
  [[ -n $SRC ]] || { print "The Final Cut Test library isn't on this Mac or a plugged-in drive.\nPlug in a test drive and rerun (it copies it over by itself)."; exit 1; }
  NEED=$(du -sk "$SRC" | awk '{print $1}'); HAVE=$(df -k "$HOME" | awk 'NR==2{print $4}')
  (( HAVE - NEED > 15 * 1048576 )) || { print "Not enough space for the Final Cut Test folder ($(( NEED / 1048576 ))GB + 15GB spare). Free some with Tools/att-get.zsh free."; exit 1; }
  print "Copying the Final Cut Test folder from ${SRC%%/Adam Talks Tech Tests*} ($(( NEED / 1048576 ))GB, one time)..."
  ditto "$SRC" "$ROOT/Final Cut Test" || { print "Copy failed."; exit 1; }
fi
[[ -n $WB ]]  || { print "Missing the stack test workbook in Memory Test."; exit 1; }
(( ${#SITES} >= 80 )) || { print "Couldn't read the 80 test sites from att-tabtest.zsh."; exit 1; }
[[ -x $LMS ]] || { print "Can't find LM Studio's lms tool. Open LM Studio once, then rerun."; exit 1; }
key_for() { "$LMS" ls --json 2>/dev/null | jq -r --arg p "$1" '(if type=="array" then . else (.models // .llms // []) end)
  | [ .[] | select((((.path // "") + " " + (.modelKey // .key // "")) | test($p; "i"))) ][0] | (.modelKey // .key) // empty' 2>/dev/null; }
# Copy Qwen onto this Mac first if it's missing (from the kit / test drive). No separate load step.
_GET="${0:A:h:h}/AI Tests/att-models.zsh"
if [[ -f $_GET ]] && (( ! ${NOFETCH:-0} )); then
  print "Checking the models are on this Mac..."
  _w=(Qwen3.5-9B-MLX-4bit); (( BIG )) && _w+=(Qwen3.8-27B-MLX-4bit)
  zsh "$_GET" get $_w
fi
Q9=$(key_for 'qwen3\.5-9b-mlx-4bit'); [[ -z $Q9 ]] && Q9=$(key_for 'qwen3\.5-9b')
Q27=$(key_for 'qwen3\.8-27b-mlx-4bit')
[[ -n $Q9 ]] || { print "Qwen 3.5 9B isn't in LM Studio on this Mac. Plug in the test drive and rerun (it copies the model over by itself)."; exit 1; }
(( BIG )) && [[ -z $Q27 ]] && { print "Note: Qwen3.8 27B isn't on this Mac, so the stacker stops at the 9B."; BIG=0; }

step()  { print -r -- "$1" > /tmp/att-step; print "\n[$(date +%H:%M:%S)] STEP: $1"; print -r -- "$(date +%H:%M:%S)  $1" >> "$RES.steps"; }
ask()   { print -n "  >> $1 Press Return. "; read -r; }
timed() { local t0=$EPOCHREALTIME; print -n -u2 "  >> $1 Press Return the moment it's done. "; read -r; printf "%.1f" $(( EPOCHREALTIME - t0 )); }
open_tabs() { local n=$1 i; for (( i = 1; i <= n; i++ )); do open -a Safari "${SITES[$i]}"; sleep 3; done; }
quit_app()  { osascript -e "tell application \"$1\" to quit saving no" >/dev/null 2>&1 || osascript -e "tell application \"$1\" to quit" >/dev/null 2>&1; sleep 3; }
# Deletes old test exports (Nov 21: they were piling up in _To Delete at ~350MB each).
clear_export() { local e="$ROOT/Export"; mkdir -p "$e"
  rm -rf "$ROOT/_To Delete"/old\ exports\ *(N) 2>/dev/null
  [[ -n $(ls -A "$e" 2>/dev/null) ]] || return 0
  rm -rf "$e"/*(N) "$e"/.*(N) 2>/dev/null; print "  (deleted the old export from the Export folder)"; }
lms_load()  { "$LMS" load "$1" --yes --context-length 8192 >/dev/null 2>&1 && print "  loaded ${1:t}" || print "  !! couldn't load $1"; }
numbers_ready() {
  if (( UIOK )) && NUM_S=$(att_numbers_wait 600); then print "  Numbers open: ${NUM_S}s (timed by the script)"
  else NUM_S=$(timed "When the Numbers Dashboard has filled in:"); fi
}
fcp_ready() { if (( UIOK )); then att_fcp_wait "$FCP_NAME" "$LIB"; sleep 5; att_fcp_open_project "$FCP_NAME" "$FCP_PROJECT"; else ask "$1"; fi; }
fcp_export() {   # $1 label for the export log
  if (( UIOK )) && att_fcp_share "$FCP_NAME" "$ROOT/Export"; then
    print "  Script clicked Share > Apple Devices 4K > Save. Timing it."
    if [[ ${ATT_EXPORT_DIR:-$ROOT/Export} == $ROOT/Export ]]; then
      ATT_STEP_OVERRIDE=17 zsh "$ROOT/Tools/att-export-timer.zsh" "" "$1" START=$SHARE_START
    else
      # Saved outside Export: time that one file until it stops growing, then move it into Export
      local sz=-1 n same=0
      while (( same < 30 )); do n=$(stat -f %z "$ATT_EXPORT_FILE" 2>/dev/null || echo 0)
        if (( n == sz && n > 0 )); then (( same++ )); else same=0; sz=$n; fi; sleep 1; done
      local secs=$(( EPOCHREALTIME - SHARE_START - 30 ))
      printf "  Export time: %.1f s (file stopped growing; saved in %s)\n" $secs "${ATT_EXPORT_DIR:t}"
      mv "$ATT_EXPORT_FILE" "$ROOT/Export/" 2>/dev/null
      local xc="$ROOT/Results/$MACNAME/Exports/exports.csv"; mkdir -p "${xc:h}"
      [[ -f $xc ]] || print "Date,Time,Mac,Test,Export seconds,First file to last (s),Files,MB,Start mode,Folder,macOS" > "$xc"
      printf '%s,%s,"%s","%s",%.1f,,1,%d,script (saved to %s),"%s",%s\n' "$(date +%F)" "$(date +%T)" "$MACNAME" "$1" $secs $(( sz / 1048576 )) "${ATT_EXPORT_DIR:t}" "$ROOT/Export" "$(sw_vers -productVersion)" >> "$xc"
    fi
  else
    att_say "Final Cut needs you. Share the 3 minute 4K project, Apple Devices 4K, to the Export folder."
    print "  In Final Cut: Share the 3-min 4K project to Adam Talks Tech Tests/Export (Apple Devices 4K)."
    print "  No need to press anything in Terminal: the clock starts when the file appears."
    ATT_STEP_OVERRIDE=17 zsh "$ROOT/Tools/att-export-timer.zsh" "" "$1" AUTO=1
  fi
  # Right project? The 3-min test project is "universal control on mac 3 min"
  local f=$(ls "$ROOT/Export" 2>/dev/null | grep -v '^\.' | head -1)
  if [[ -n $f && ${(L)f} != *"3 min"* ]]; then
    EXPORT_NOTE="WRONG PROJECT exported ($f): open 'universal control on mac 3 min' in the timeline, quit Final Cut, rerun"
    att_say "Wrong project exported. Check the card."
  else EXPORT_NOTE="file: ${f:-none}"; fi
}

print "================ ATT Closer vs Stacker: $MODE ================"
print "Mac: $MACNAME | $(sysctl -n machdep.cpu.brand_string) | ${RAM_GB}GB"
print "Workbook: ${WB:t}   Settle: ${SETTLE}s   27B on top: $([[ $BIG == 1 ]] && print yes || print no)"
print "================================================================"

# Hands-off: Terminal clicks Final Cut / reads Numbers itself (asks for permission once, now)
source "$ROOT/Tools/att-ui.zsh"; UIOK=0
(( ${MANUAL:-0} )) || { att_ui_setup && UIOK=1; }
source "$ROOT/Tools/att-prime.zsh"; [[ -n $ATT_NOSYNC ]] || att_prime stacker
(( UIOK )) && print "Hands-off mode: you don't need to touch anything until the card prints." \
           || print "Manual mode: you'll press Return for Numbers / Final Cut and click Share."

att_cooldown
"$LMS" unload --all >/dev/null 2>&1

# ---------- Logger in the background for the whole run ----------
LOGOUT="$OUT/.memlog_${STAMP}.out"
zsh "$HERE/att-memlog.zsh" "$MACNAME $MODE" 5 > "$LOGOUT" 2>&1 &
LOGPID=$!
# Nov 21: per-app memory too (what each app is using, not just the whole Mac)
source "$ROOT/Tools/att-appmem.zsh"; APPCSV="$OUT/appmem_${MODE}_${STAMP}.csv"; att_appmem_start "$APPCSV" 10
sleep 6
step "baseline (nothing open)"; sleep 30

NUM_S=""; EXPORT_NOTE=""
if [[ $MODE == closer ]]; then
  step "safari 20 tabs"; open_tabs 20; sleep 30
  step "safari quit"; quit_app Safari
  step "numbers open"; open -a Numbers "$WB"; numbers_ready
  step "numbers quit"; quit_app Numbers
  step "qwen 9b loaded"; lms_load "$Q9"; sleep 30
  step "qwen unloaded"; "$LMS" unload --all >/dev/null 2>&1
  step "final cut open"; open -a "$FCP_APP" "$LIB"; fcp_ready "When Final Cut has the Test Library open:"
  step "final cut export"; clear_export
  fcp_export "FCP 3-min 4K, closer ($MACNAME)"
  step "final cut quit"; quit_app "$FCP_NAME"
else
  step "safari 80 tabs"; open_tabs 80; sleep 30
  step "final cut open"; open -a "$FCP_APP" "$LIB"; fcp_ready "When Final Cut has the Test Library open (stacked 6K timeline showing):"
  step "numbers open"; open -a Numbers "$WB"; numbers_ready
  step "qwen 9b loaded"; lms_load "$Q9"
  if (( BIG )); then sleep 60; step "qwen 27b loaded"; "$LMS" unload --all >/dev/null 2>&1; lms_load "$Q27"; fi
  step "everything open, settling"
  for (( s = SETTLE; s > 0; s -= 60 )); do print "  everything stays open: $(( s / 60 )) min left"; sleep $(( s < 60 ? s : 60 )); done
  step "final cut export under load"; clear_export
  fcp_export "FCP 3-min 4K, stacker ($MACNAME)"
fi
step "done"; sleep 10

# ---------- Stop the logger, collect the numbers ----------
kill -TERM $LOGPID 2>/dev/null; wait $LOGPID 2>/dev/null
att_appmem_stop
CSV=$(ls -t "$OUT"/*.csv 2>/dev/null | grep -v '/ATT-' | head -1)
val() { awk -F, -v k="$1" '$1==k{print $2}' "$CSV" 2>/dev/null | tail -1; }
EXP=$(tail -1 "$ROOT/Results/$MACNAME/Exports/exports.csv" 2>/dev/null | sed -E 's/"[^"]*"//g' | awk -F, '{print $5}')   # drop quoted fields first (the test name has a comma)
[[ $MODE == stacker ]] && "$LMS" unload --all >/dev/null 2>&1

# Nov 21: the very first closer on a Mac is a warm-up (first app launches are slow): say so on the card
WARM=""
[[ $MODE == closer && -z $(print -l "$OUT"/stacker_closer_*.txt(N) | grep -v "$STAMP") ]] && WARM=1
att_card_start "RAM: $MODE run (Safari, Final Cut, Numbers, LM Studio)${WARM:+  ·  WARM-UP (first closer on this Mac): don't log, restart and run the closer again}"
{
print "Mode:                 $MODE   (${RAM_GB}GB, settle ${SETTLE}s, 27B on top: $BIG)"
print "Final Cut 3-min export: ${EXP:-?} s $([[ $MODE == stacker ]] && print '(with everything open)')"
print "Export check:         $EXPORT_NOTE"
clear_export >/dev/null   # the export isn't needed once it's timed and checked
print "Numbers open to Dashboard: ${NUM_S:-?} s"
print "Peak swap:            $(val 'Peak swap GB') GB   (start $(val 'Swap at start GB') GB)"
print "Peak compressed:      $(val 'Peak compressed GB') GB"
print "Lowest memory free:   $(val 'Lowest memory free %')%"
print "Time in yellow / red: $(val 'Seconds in yellow')s / $(val 'Seconds in red')s"
print "SSD written:          $(val 'SSD written during test GB') GB"
if [[ $MODE == stacker ]]; then
  _y=$(val 'Seconds in yellow'); _r=$(val 'Seconds in red'); _w=green; (( ${_y:-0} > 0 )) && _w=yellow; (( ${_r:-0} > 0 )) && _w=red
  att_log "New Tests" "Stacker: FCP 3-min 4K export" "${EXP:-?}"
  att_log "New Tests" "Stacker: swap added" "$(awk -v a="$(val 'Peak swap GB')" -v b="$(val 'Swap at start GB')" 'BEGIN{if(a=="")print "?"; else printf "%.1f", a-b}')"
  att_log "New Tests" "Stacker: memory pressure color" "$_w"
fi
print "Biggest apps (peak footprint = what Activity Monitor calls Memory):"
att_appmem_peaks "$APPCSV" 6
print "Log: ${CSV:t}  +  ${APPCSV:t}"
} | tee "$RES"
att_card_end
cat "$RES.steps" >> "$RES" 2>/dev/null; rm -f "$RES.steps" "$LOGOUT"
[[ $MODE == closer ]] && print "Next: restart the Mac, then run the stacker:  zsh att-stacker.zsh stacker"

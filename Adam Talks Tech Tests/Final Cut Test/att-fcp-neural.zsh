#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  att-fcp-neural.zsh  -  Step 19  Final Cut AI: Magnetic Mask  (v1.0, Nov 21 2026)
# =============================================================================
#  Apple says Final Cut's analysis (Magnetic Mask, object tracking, Smart Conform) runs on the
#  Neural Engine. The M6 has two 16-core Neural Engines, the M5 Pro/Max one. Puget Bench for
#  DaVinci Resolve's Magic Mask did NOT favor the M6, so this checks Apple's own app.
#
#  The library "ATT Neural Test.fcpbundle" (Adam builds it once, on the drive in Final Cut Test):
#    project "neural mask 1 min"     the 1-min 4K clip with a Magnetic Mask on Adam (analyzed)
#    project "neural no mask 1 min"  the same clip, same settings, no mask
#  Final Cut works the mask out again on every export, so:
#    mask cost = (mask export) - (no-mask export). Each is exported twice, in turns, average kept.
#
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Final Cut Test" && zsh att-fcp-neural.zsh
#  Hands-off (Terminal in Accessibility, asked once). ~10 min.
# =============================================================================
zmodload zsh/datetime
HERE=${0:A:h}; ROOT=${HERE:h}
[[ ${ROOT:t} == "Adam Talks Tech Tests" ]] || { print "Run this from Adam Talks Tech Tests/Final Cut Test."; exit 1; }
[[ $HERE == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/Adam Talks Tech Tests."; exit 1; }
MACNAME=$(scutil --get ComputerName 2>/dev/null)
LIBNAME="ATT Neural Test.fcpbundle"; LIB="$HERE/$LIBNAME"
P_MASK="${P_MASK:-neural mask 1 min}"; P_NONE="${P_NONE:-neural no mask 1 min}"
ROUNDS=${ROUNDS:-2}
OUT="$ROOT/Results/$MACNAME/Final Cut"; mkdir -p "$OUT"; RES="$OUT/fcp-neural_$(date +%Y-%m-%d_%H-%M).txt"
XC="$ROOT/Results/$MACNAME/Exports/exports.csv"

if [[ ! -e $LIB ]]; then
  SRC=$(print -l /Volumes/*/"Adam Talks Tech Tests"/"Final Cut Test"/"$LIBNAME"(N) | head -1)
  [[ -n $SRC ]] || { print "\"$LIBNAME\" isn't on this Mac or a plugged-in drive yet (Adam builds it once: see the top of this script)."; exit 1; }
  print "Copying $LIBNAME from ${SRC#/Volumes/} (one time)..."; ditto "$SRC" "$LIB" || { print "Copy failed."; exit 1; }
fi
FCP_APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep '\.app$' | grep -v '^/Volumes' | head -1)
[[ -z $FCP_APP ]] && FCP_APP=$(print -l /Applications/*Final*Cut*.app(N) /Applications/*/*Final*Cut*.app(N) | head -1)
[[ -n $FCP_APP ]] || { print "Final Cut isn't on this Mac."; exit 1; }
FCP_NAME=${${FCP_APP:t}%.app}

source "$ROOT/Tools/att-ui.zsh"
att_ui_setup || { print "Needs Terminal in Accessibility to run hands-off."; exit 1; }
att_cooldown
EXPORT="$ROOT/Export"; mkdir -p "$EXPORT"
clear_export() { rm -rf "$EXPORT"/*(N) "$EXPORT"/.*(N) 2>/dev/null; }

open -a "$FCP_APP" "$LIB"; att_fcp_wait "$FCP_NAME" "$LIB"; sleep 5

one_export() {   # $1 project -> prints seconds
  clear_export
  att_fcp_open_project "$FCP_NAME" "$1" >&2 || return 1
  sleep 3
  att_fcp_share "$FCP_NAME" "$EXPORT" >&2 || return 1
  ATT_STEP_OVERRIDE=19 zsh "$ROOT/Tools/att-export-timer.zsh" "" "FCP neural: $1 ($MACNAME)" START=$SHARE_START >&2
  tail -1 "$XC" 2>/dev/null | sed -E 's/"[^"]*"//g' | awk -F, '{print $5}'
}
typeset -a TM TN
for (( r = 1; r <= ROUNDS; r++ )); do
  print "\n== Round $r of $ROUNDS: no mask =="; t=$(one_export "$P_NONE"); [[ -n $t ]] && TN+=($t)
  sleep 20
  print "\n== Round $r of $ROUNDS: Magnetic Mask =="; t=$(one_export "$P_MASK"); [[ -n $t ]] && TM+=($t)
  sleep 20
done
clear_export
osascript -e "tell application \"$FCP_NAME\" to quit" >/dev/null 2>&1

avg() { (( $# )) || { print "?"; return; }; local s=0 x; for x; do (( s += x )); done; printf "%.1f" $(( s / $# )); }
AN=$(avg $TN); AM=$(avg $TM)
att_card_start "Final Cut AI: Magnetic Mask export (Neural Engine), Step 19"
{
print "Same 1-min 4K clip, Apple Devices 4K, exported $ROUNDS times each, in turns."
print "No mask:          $AN s   (runs: ${(j:, :)TN})"
print "Magnetic Mask:    $AM s   (runs: ${(j:, :)TM})"
[[ $AN != "?" && $AM != "?" ]] && printf "Mask cost:        %.1f s  (mask - no mask = the AI work)\n" $(( AM - AN ))
[[ $AN != "?" && $AM != "?" ]] && att_log "New Tests" "Final Cut Magnetic Mask 1-min export" "$AN / $AM / $(printf %.1f $(( AM - AN )))"
} | tee "$RES"
att_card_end

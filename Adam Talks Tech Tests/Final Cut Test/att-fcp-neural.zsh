#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; att_log() { print -r -- "LOG | $1 | $2 | $3"; }; }
# =============================================================================
#  att-fcp-neural.zsh  -  Step 19  Final Cut AI: Magnetic Mask  (v1.1, Nov 22 2026)
# =============================================================================
#  Apple says Final Cut's analysis (Magnetic Mask, object tracking, Smart Conform) runs on the
#  Neural Engine. The M6 has two 16-core Neural Engines, the M5 Pro/Max one. Puget Bench for
#  DaVinci Resolve's Magic Mask did NOT favor the M6, so this checks Apple's own app.
#
#  Uses the "magnetic" project (Adam's 18-second clip with a Magnetic Mask) that's already in
#  Test Library rev (the stacker copies that library to every Mac). Final Cut keeps the mask it
#  worked out in the library's VideoSegmentationFiles folder, so each round:
#    1. Final Cut closed, the saved mask set aside -> export = mask worked out again + export
#    2. export again (mask now saved)                 -> export only
#    mask work = round 1 - round 2.  ROUNDS=2 (default) rounds, average kept.
#  The original mask files go back at the end (or Final Cut's new ones stay if it made them).
#
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Final Cut Test" && zsh att-fcp-neural.zsh
#  Hands-off (Terminal in Accessibility, asked once). ~10 min.
# =============================================================================
zmodload zsh/datetime
HERE=${0:A:h}; ROOT=${HERE:h}
[[ ${ROOT:t} == "Adam Talks Tech Tests" ]] || { print "Run this from Adam Talks Tech Tests/Final Cut Test."; exit 1; }
[[ $HERE == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/Adam Talks Tech Tests."; exit 1; }
MACNAME=$(scutil --get ComputerName 2>/dev/null)
LIB="$HERE/Test Library rev.fcpbundle"
P_MASK="${P_MASK:-magnetic}"
ROUNDS=${ROUNDS:-2}
OUT="$ROOT/Results/$MACNAME/Final Cut"; mkdir -p "$OUT"; STAMP=$(date +%Y-%m-%d_%H-%M); RES="$OUT/fcp-neural_$STAMP.txt"
XC="$ROOT/Results/$MACNAME/Exports/exports.csv"
SEG="$LIB/VideoSegmentationFiles"; KEEP="$HERE/.att-mask-backup_$STAMP"

[[ -e $LIB ]] || { print "Test Library rev isn't on this Mac yet. Run the stacker once (it copies it from the drive), then rerun."; exit 1; }
[[ -d "$LIB/9-1-25/$P_MASK" ]] || print "Note: no \"$P_MASK\" project folder seen in the library; trying anyway."
FCP_APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep '\.app$' | grep -v '^/Volumes' | head -1)
[[ -z $FCP_APP ]] && FCP_APP=$(print -l /Applications/*Final*Cut*.app(N) /Applications/*/*Final*Cut*.app(N) | head -1)
[[ -n $FCP_APP ]] || { print "Final Cut isn't on this Mac."; exit 1; }
FCP_NAME=${${FCP_APP:t}%.app}

source "$ROOT/Tools/att-ui.zsh"
att_ui_setup || { print "Needs Terminal in Accessibility to run hands-off."; exit 1; }
EXPORT="$ROOT/Export"; mkdir -p "$EXPORT"
clear_export() { rm -rf "$EXPORT"/*(N) "$EXPORT"/.*(N) 2>/dev/null; }
fcp_quit() { osascript -e "tell application \"$FCP_NAME\" to quit" >/dev/null 2>&1; local w=0
  while pgrep -f "Final Cut[^/]*\.app/Contents/MacOS/" >/dev/null && (( w < 60 )); do sleep 1; (( w++ )); done
  pgrep -f "Final Cut[^/]*\.app/Contents/MacOS/" >/dev/null && pkill -f "Final Cut[^/]*\.app/Contents/MacOS/"; sleep 2; }
fcp_open() { open -a "$FCP_APP" "$LIB"; att_fcp_wait "$FCP_NAME" "$LIB" >&2; sleep 5; att_fcp_open_project "$FCP_NAME" "$P_MASK" >&2; sleep 3; }
one_export() {   # $1 label -> prints seconds
  clear_export
  att_fcp_share "$FCP_NAME" "$EXPORT" >&2 || return 1
  ATT_STEP_OVERRIDE=19 zsh "$ROOT/Tools/att-export-timer.zsh" "" "FCP Magnetic Mask $1 ($MACNAME)" START=$SHARE_START >&2
  tail -1 "$XC" 2>/dev/null | sed -E 's/"[^"]*"//g' | awk -F, '{print $5}'
}
restore() {   # put the original mask files back unless Final Cut made new ones
  [[ -d $KEEP ]] || return 0
  if [[ -d $SEG && -n $(ls -A "$SEG" 2>/dev/null) ]]; then rm -rf "$KEEP"; else rm -rf "$SEG"; mv "$KEEP" "$SEG"; fi
}
trap 'fcp_quit; restore; exit 130' INT TERM

fcp_quit
att_cooldown
typeset -a TF TC; REBUILT=no
for (( r = 1; r <= ROUNDS; r++ )); do
  fcp_quit
  # Set the saved mask aside (first round keeps the original; later rounds just clear Final Cut's new copy)
  if [[ -d $SEG ]]; then if [[ -d $KEEP ]]; then rm -rf "$SEG"; else mv "$SEG" "$KEEP"; fi; fi
  fcp_open
  print "\n== Round $r of $ROUNDS: mask NOT saved (Final Cut works it out again) =="
  t=$(one_export "fresh"); [[ -n $t ]] && TF+=($t)
  [[ -d $SEG && -n $(ls -A "$SEG" 2>/dev/null) ]] && REBUILT=yes
  sleep 20
  print "\n== Round $r of $ROUNDS: mask saved =="
  t=$(one_export "saved"); [[ -n $t ]] && TC+=($t)
  sleep 20
done
clear_export; fcp_quit; restore; trap - INT TERM

avg() { (( $# )) || { print "?"; return; }; local s=0 x; for x; do (( s += x )); done; printf "%.1f" $(( s / $# )); }
AF=$(avg $TF); AC=$(avg $TC)
{
att_card_start "Final Cut AI: Magnetic Mask (Neural Engine), Step 19"
print "Project \"$P_MASK\" (18-sec clip with a Magnetic Mask), Apple Devices 4K, $ROUNDS rounds."
print "Mask worked out + export:  $AF s   (runs: ${(j:, :)TF})"
print "Export with mask saved:    $AC s   (runs: ${(j:, :)TC})"
if [[ $AF != "?" && $AC != "?" ]]; then
  printf "Mask work (the AI part):   %.1f s\n" $(( AF - AC ))
  [[ $REBUILT == no ]] && print "!! Final Cut didn't save new mask files during export, so round 2 may not be 'saved': check with Claude before logging"
  att_log "New Tests" "Final Cut Magnetic Mask" "$AF / $AC / $(printf %.1f $(( AF - AC )))"
fi
att_card_end
} | tee "$RES"

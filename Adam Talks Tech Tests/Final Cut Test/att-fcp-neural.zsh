#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; att_log() { print -r -- "LOG | $1 | $2 | $3"; }; }
# =============================================================================
#  att-fcp-neural.zsh  -  Step 19  Final Cut AI: Magnetic Mask Analyze  (v1.2, Nov 22 2026)
# =============================================================================
#  Apple says Final Cut's analysis (Magnetic Mask, object tracking, Smart Conform) runs on the
#  Neural Engine. The M6 has two 16-core Neural Engines, the M5 Pro/Max one. Puget Bench for
#  DaVinci Resolve's Magic Mask did NOT favor the M6, so this checks Apple's own app.
#
#  Times the Magnetic Mask ANALYZE button (that's when the AI work happens, Adam Nov 22) on the
#  "magnetic" project (18-sec clip) in Test Library rev, which the stacker copies to every Mac.
#  Each run: Final Cut closed, the saved analysis set aside (VideoSegmentationFiles), library
#  opened, clip selected, Analyze clicked, clock stops at the last analysis file Final Cut writes.
#  RUNS=3 (default), average kept. The original analysis files go back at the end.
#  If the script can't find the Analyze button it says so out loud: click it yourself, the clock
#  then starts when the first analysis file appears (a little short, the card says so).
#
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Final Cut Test" && zsh att-fcp-neural.zsh
#  Hands-off (Terminal in Accessibility, asked once). ~8 min. QUIET=15 = seconds of no new files that mean done.
# =============================================================================
zmodload zsh/datetime
HERE=${0:A:h}; ROOT=${HERE:h}
[[ ${ROOT:t} == "Adam Talks Tech Tests" ]] || { print "Run this from Adam Talks Tech Tests/Final Cut Test."; exit 1; }
[[ $HERE == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/Adam Talks Tech Tests."; exit 1; }
MACNAME=$(scutil --get ComputerName 2>/dev/null)
LIB="$HERE/Test Library rev.fcpbundle"
P_MASK="${P_MASK:-magnetic}"
RUNS=${RUNS:-3}; QUIET=${QUIET:-15}
OUT="$ROOT/Results/$MACNAME/Final Cut"; mkdir -p "$OUT"; STAMP=$(date +%Y-%m-%d_%H-%M); RES="$OUT/fcp-neural_$STAMP.txt"
SEG="$LIB/VideoSegmentationFiles"; KEEP="$HERE/.att-mask-backup_$STAMP"

[[ -e $LIB ]] || { print "Test Library rev isn't on this Mac yet. Run the stacker once (it copies it from the drive), then rerun."; exit 1; }
FCP_APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep '\.app$' | grep -v '^/Volumes' | head -1)
[[ -z $FCP_APP ]] && FCP_APP=$(print -l /Applications/*Final*Cut*.app(N) /Applications/*/*Final*Cut*.app(N) | head -1)
[[ -n $FCP_APP ]] || { print "Final Cut isn't on this Mac."; exit 1; }
FCP_NAME=${${FCP_APP:t}%.app}

source "$ROOT/Tools/att-ui.zsh"
att_ui_setup || { print "Needs Terminal in Accessibility to run hands-off."; exit 1; }
fcp_quit() { osascript -e "tell application \"$FCP_NAME\" to quit" >/dev/null 2>&1; local w=0
  while pgrep -f "Final Cut[^/]*\.app/Contents/MacOS/" >/dev/null && (( w < 60 )); do sleep 1; (( w++ )); done
  pgrep -f "Final Cut[^/]*\.app/Contents/MacOS/" >/dev/null && pkill -f "Final Cut[^/]*\.app/Contents/MacOS/"; sleep 2; }
restore() {   # put the original analysis back (Final Cut's new copy is thrown away)
  [[ -d $KEEP ]] || return 0
  rm -rf "$SEG"; mv "$KEEP" "$SEG"
}
newest_mtime() { local f; float m=0 t; for f in "$SEG"/**/*(N.); do t=$(stat -f %Fm "$f" 2>/dev/null || echo 0); (( t > m )) && m=$t; done; print $m; }   # fractional seconds
seg_bytes() { du -sk "$SEG" 2>/dev/null | awk '{print $1+0}'; }

# Select the clip and click Analyze in the Video inspector. Prints OK or NOBUTTON.
click_analyze() {
  local app=$(att_fcp_proc "$FCP_NAME") r try
  for try in 1 2; do
    r=$(osascript -e "tell application \"System Events\" to tell process \"$app\"
      set frontmost to true
      delay 0.5
      keystroke \"2\" using command down
      delay 0.7
      keystroke \"a\" using command down
      delay 1.5
      repeat with el in (entire contents of window 1)
        try
          if (role of el is \"AXButton\") then
            set n to \"\"
            try
              set n to (name of el) as text
            end try
            set d to \"\"
            try
              set d to (description of el) as text
            end try
            if n starts with \"Analyze\" or d starts with \"Analyze\" then
              click el
              return \"OK\"
            end if
          end if
        end try
      end repeat
      return \"NOBUTTON\"
    end tell" 2>/dev/null)
    [[ $r == OK ]] && { print OK; return 0; }
    # Inspector may be hidden: Cmd-4 shows it, then look again
    osascript -e "tell application \"System Events\" to tell process \"$app\" to keystroke \"4\" using command down" >/dev/null 2>&1; sleep 2
  done
  print NOBUTTON
}

trap 'fcp_quit; restore; exit 130' INT TERM
fcp_quit
att_cooldown
typeset -a TA; NOTE=""
for (( r = 1; r <= RUNS; r++ )); do
  fcp_quit
  if [[ -d $SEG ]]; then if [[ -d $KEEP ]]; then rm -rf "$SEG"; else mv "$SEG" "$KEEP"; fi; fi
  open -a "$FCP_APP" "$LIB"; att_fcp_wait "$FCP_NAME" "$LIB"; sleep 5
  att_fcp_open_project "$FCP_NAME" "$P_MASK"; sleep 5
  print "\n== Run $r of $RUNS: Analyze =="
  t0=$EPOCHREALTIME
  if [[ $(click_analyze) == OK ]]; then print "  Script clicked Analyze. Timing until Final Cut stops writing the analysis."
  else
    att_say "Click Analyze on the Magnetic Mask in the inspector."
    print "  Couldn't find the Analyze button: click it yourself (the clip's Magnetic Mask, Video inspector)."
    w=0; until [[ $(seg_bytes) -gt 0 ]] || (( w > 600 )); do sleep 0.25; (( w++ )); done
    t0=$EPOCHREALTIME; NOTE="started by hand: clock began at the first analysis file (a little short)"
  fi
  # Done when nothing new has been written for QUIET seconds; end = last write time
  float last=0 m=0; same=0; started=0
  while (( EPOCHREALTIME - t0 < 1800 )); do
    m=$(newest_mtime)
    (( m > 0 )) && started=1
    if (( m != last )); then last=$m; same=0; else (( same++ )); fi
    (( started && same >= QUIET )) && break
    sleep 1
  done
  if (( started )); then secs=$(( last - t0 )); (( secs < 0 )) && secs=0
    printf "  Analyze: %.1f s  (analysis files: %d KB)\n" $secs $(seg_bytes); TA+=($(printf %.1f $secs))
  else print "  !! No analysis files appeared in 30 min."; fi
  sleep 10
done
fcp_quit; restore; trap - INT TERM

AV="?"; (( ${#TA} )) && { s=0; for x in $TA; do (( s += x )); done; AV=$(printf %.1f $(( s / ${#TA} ))); }
{
att_card_start "Final Cut AI: Magnetic Mask Analyze (Neural Engine), Step 19"
print "Project \"$P_MASK\" (18-sec clip), saved analysis cleared before each run."
print "Analyze time:  $AV s   (runs: ${(j:, :)TA})"
[[ -n $NOTE ]] && print "Note: $NOTE"
(( ${#TA} < RUNS )) && print "!! Only ${#TA} of $RUNS runs finished: rerun before logging"
[[ $AV != "?" ]] && att_log "New Tests" "Final Cut Magnetic Mask" "$AV"
att_card_end
} | tee "$RES"

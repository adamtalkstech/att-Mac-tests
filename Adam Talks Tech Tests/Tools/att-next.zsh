#!/bin/zsh
# att-next.zsh - shows THIS Mac's next tests from "00 RUN THIS NEXT - all Macs.txt"
# (Claude keeps that file current through GitHub; Update Scripts runs this at the end.)
# Matches the Mac by hardware (model ID, chip, RAM, GPU cores, SSD), not by its name.
# Writes "00 RUN THIS NEXT (this Mac).txt" in the test folder and opens it in TextEdit.
# NOOPEN=1 in front = just print it.
# Nov 22: also reads the live Mac Tests sheet (ROWS= / GO=sheet / REDO= / SKIPT= in a Mac's section).
TOOLS=${0:A:h}; ROOT=${TOOLS:h}
ALL="$ROOT/00 RUN THIS NEXT - all Macs.txt"; OUT="$ROOT/00 RUN THIS NEXT (this Mac).txt"
[[ -f $ALL ]] || { print "No RUN THIS NEXT file yet."; exit 0; }
model=$(sysctl -n hw.model 2>/dev/null)
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
name=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2; exit}')
gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Total Number of Cores/ {print $2; exit}')
disk=$(diskutil info / 2>/dev/null | awk -F'[(:]' '/Container Total Space|Disk Size/ {gsub(/^ +| +$/,"",$2); print $2; exit}')
dgb=${disk%% *}; dgb=${dgb%%.*}; [[ $disk == *TB* ]] && dgb=$(( dgb * 1000 ))
key=""
case "$name|$chip" in
  *iMac*\|*M6*) key=M6-IMAC ;;
  *"MacBook Air"*) key=AIR ;;
  *"Mac Studio"*\|*"M5 Max"*) key=STUDIO-M5MAX ;;
  *"Mac Studio"*\|*"M4 Max"*) key=STUDIO-M4MAX ;;
  *"MacBook Pro"*\|*"M6"*) key=M6-MBP ;;
  *"MacBook Pro"*\|*"M5 Max"*) [[ $model == Mac17,10 ]] && key=MAX-16 || key=MAX-14 ;;
  *"MacBook Pro"*\|*"M5 Pro"*) [[ $model == Mac17,13 ]] && key=PROLED-M5PRO || key=M5PRO-MBP ;;
  *"Mac mini"*\|*"M5 Pro"*) (( ${gpu:-0} > 16 )) && key=M5PRO-MINI-UPGRADED || key=M5PRO-MINI ;;
  *"Mac mini"*\|*"M6"*)
    if (( ram >= 32 )); then key=M6-MINI-32
    elif (( ram >= 24 )); then (( ${dgb:-0} < 300 )) && key=M6-MINI-24-256 || key=M6-MINI-24-512
    else key=M6-MINI-16; fi ;;
esac
sec() { awk -v k="[[$key]]" '$0==k {on=1; next} /^\[\[/ {on=0} on' "$ALL"; }
NAME=$( [[ -n $key ]] && sec | awk '/^NAME=/ {sub(/^NAME=/,""); print; exit}')
GO=$( [[ -n $key ]] && sec | awk '/^GO=/ {sub(/^GO=/,""); print; exit}')
UPD=$(sed -n 2p "$ALL")
# Nov 21: drop walk-away tests this Mac already finished after the SINCE= time (top of the all-Macs
# file, or a SINCE= line in this Mac's section), so it stops asking for them again.
SINCE=$( [[ -n $key ]] && sec | awk '/^SINCE=/ {sub(/^SINCE=/,""); print; exit}')
[[ -z $SINCE ]] && SINCE=$(awk '/^SINCE=/ {sub(/^SINCE=/,""); print; exit}' "$ALL")
# SINCE times are Central (Adam's time). Some test Macs are set to Pacific, so pin the zone (Nov 21 fix:
# a Pacific Mac read 22:05 as 22:05 Pacific and kept asking for tests it had already done).
SINCE_S=$(date -j -f "%Y-%m-%d %H:%M %z" "$SINCE -0600" +%s 2>/dev/null || echo 0)
newer() { local m; m=$(stat -f %m "$REPLY" 2>/dev/null || echo 0); (( m > ${T_SINCE_S:-$SINCE_S} )); }
# Nov 22: one test can have its own start time (SINCE_whisper=2026-11-22 06:45 at the top of the file or
# in a Mac's section), so a test that has to be redone shows again without bringing back finished ones.
since_for() { local v; v=$( [[ -n $key ]] && sec | awk -v k="SINCE_$1=" 'index($0,k)==1 {print substr($0,length(k)+1); exit}')
  [[ -z $v ]] && v=$(awk -v k="SINCE_$1=" 'index($0,k)==1 {print substr($0,length(k)+1); exit}' "$ALL")
  [[ -n $v ]] && date -j -f "%Y-%m-%d %H:%M %z" "$v -0600" +%s 2>/dev/null; }
RES="$ROOT/Results/$(scutil --get ComputerName 2>/dev/null)"
typeset -A PAT; PAT=(cinebench "Cinebench/cinebench_*.txt" bandwidth "Bandwidth/bandwidth_*" handbrake "HandBrake/handbrake_*.txt" sustained "Sustained/CPU_*"
  xcode "Xcode/xcode-bench_*" blender "Blender/blender-standard_*" redautumn "Blender/blender-redautumn_*"
  qwen9b "LM Studio/*qwen9b*" qwen27b "LM Studio/*qwen27b*" gemma "LM Studio/*gemma*" ladder "LM Studio/*ladder*"
  whisper "LM Studio/*whisper*" responsiveness "Memory/responsiveness_*.txt" appmem "Memory/appmem_2*.txt" realday "Memory/realday_everyday_*.txt" realdaycreator "Memory/realday_creator_*.txt")
# Nov 22: read the live Mac Tests sheet (the same published copy the website reads). Each Mac's section
# has ROWS=MR:<Main Results row> NT:<New Tests row>. A test with a blank cell, or one marked RERUN / NOT CLEAN /
# NOT VALID / PROVISIONAL, shows as still needed. GO=sheet runs every walk-away test the sheet is missing.
# REDO=<keys> (or REDO=all) forces tests even when the cell has a number (Claude removes a key once it's
# logged again); SKIPT=<keys> leaves tests out for this Mac. Keys: Tools/att-tests-catalog.txt.
SH_ROWS=$( [[ -n $key ]] && sec | awk '/^ROWS=/ {sub(/^ROWS=/,""); print; exit}')
SH_REDO=$( [[ -n $key ]] && sec | awk '/^REDO=/ {sub(/^REDO=/,""); print; exit}')
# REDO= at the top of the all-Macs file (before the first [[Mac]]) applies to every Mac.
SH_REDO="$SH_REDO $(awk '/^\[\[/ {exit} /^REDO=/ {sub(/^REDO=/,""); print; exit}' "$ALL")"
SH_SKIP=$( [[ -n $key ]] && sec | awk '/^SKIPT=/ {sub(/^SKIPT=/,""); print; exit}')
SH_WALK=(); SH_HAND=(); SH_NOTE=""; SH_ROWNAMES=()
if [[ -n $SH_ROWS ]]; then
  r_mr=${${(M)${=SH_ROWS}:#MR:*}#MR:}; r_nt=${${(M)${=SH_ROWS}:#NT:*}#NT:}
  mkdir -p $HOME/.att
  PUBK=2PACX-1vSKNimdukDqbgreZxIIpdqt6sQIB3pg77vkClSqhYn6daXZe93F5G_ppLA90Lz08JuAOutgyAP66rCW
  DOCK=164SUueXKOVqONLQtFEeEvD8n_ixYLyNAM3CANRwPn5k
  sheetget() {   # $1 gid, $2 name -> ~/.att/sheet_<name>.csv (keeps the last good copy if offline)
    local f=$HOME/.att/sheet_$2.csv t=$HOME/.att/sheet_$2.tmp
    if curl -fsSL -m 20 -o $t "https://docs.google.com/spreadsheets/d/e/$PUBK/pub?gid=$1&single=true&output=csv" 2>/dev/null && grep -q "Computer Model" $t; then mv $t $f; return 0; fi
    if curl -fsSL -m 20 -o $t "https://docs.google.com/spreadsheets/d/$DOCK/gviz/tq?tqx=out:csv&gid=$1" 2>/dev/null && grep -q "Computer Model" $t; then mv $t $f; return 0; fi
    rm -f $t; [[ -s $f ]] && return 2; return 1; }
  sheetget 0 MR; a=$?; sheetget 1327339876 NT; b=$?
  if (( a == 1 || b == 1 )); then SH_NOTE="Couldn't reach the Mac Tests sheet (no internet?). Only the list below is shown."
  else
    (( a == 2 || b == 2 )) && SH_NOTE="Couldn't reach the sheet just now: using the copy from $(stat -f '%Sm' -t '%b %d %I:%M %p' $HOME/.att/sheet_NT.csv)."
    while IFS= read -r ln; do
      case $ln in
        ROW\|*) SH_ROWNAMES+=("${${ln#ROW|}/|/: }") ;;
        WALK\|*) SH_WALK+=("${${ln#WALK|}%%|*}") ;;
        HAND\|*) SH_HAND+=("${ln#HAND|}") ;;
      esac
    done < <(osascript -l JavaScript "$TOOLS/att-sheet-gaps.js" $HOME/.att/sheet_MR.csv $HOME/.att/sheet_NT.csv \
               "$TOOLS/att-tests-catalog.txt" "${r_mr:-0}" "${r_nt:-0}" "$ram" "$SH_REDO" "$SH_SKIP" 2>/dev/null)
  fi
fi
if [[ " $GO " == *" sheet "* ]]; then
  # offline with no saved copy: fall back to every walk-away test (finished ones still drop out below)
  [[ $SH_NOTE == *"no internet"* ]] && SH_WALK=(cinebench xcode blender redautumn handbrake sustained qwen9b qwen27b gemma bandwidth whisper appmem responsiveness)
  g2=(); for t in ${=GO}; do [[ $t == sheet ]] && g2+=($SH_WALK) || g2+=($t); done
  g2=(${(u)g2}); g3=()   # no repeats, in the queue's usual order
  for t in cinebench xcode blender redautumn handbrake sustained qwen9b qwen27b gemma ladder bandwidth whisper appmem responsiveness realday realdaycreator; do
    (( ${g2[(Ie)$t]} )) && g3+=($t); done
  for t in $g2; do (( ${g3[(Ie)$t]} )) || g3+=($t); done
  GO="${(j: :)g3}"
fi
if [[ -n $GO ]]; then
  left=(); DONE_GO=()
  for t in ${=GO}; do
    T_SINCE_S=$(since_for $t)
    hit=( "$RES"/${~PAT[$t]:-NOMATCH}(N+newer) )
    T_SINCE_S=""
    (( ${#hit} )) && DONE_GO+=($t) || left+=($t)
  done
  GO="${(j: :)left}"
fi
LINE="============================================================"
{
  print "$LINE"
  print " RUN THIS NEXT  ·  ${NAME:-this Mac}"
  print " ${UPD}"
  print " ${name:-Mac} ($model) · ${chip#Apple } · ${ram}GB · ${disk:-?} SSD"
  print "$LINE"
  print ""
  vfile="$ROOT/_Read Me First/SCRIPTS VERSION.txt"
  if [[ -f $vfile ]] && (( $(date +%s) - $(stat -f %m "$vfile" 2>/dev/null || echo 0) < 43200 )); then
    print "✓ Scripts updated $(stat -f '%Sm' -t '%b %d %I:%M %p' "$vfile")"
  else
    print "STEP 0 · UPDATE SCRIPTS (not updated in the last 12 hours)"
    print -r -- '   zsh ~/Downloads/"Adam Talks Tech Tests"/"Update Scripts.command"'
  fi
  if [[ -s $HOME/.att/upload.conf && -f $HOME/.att/upload-last ]]; then
    print "✓ Uploads set up (last upload $(stat -f '%Sm' -t '%b %d %I:%M %p' $HOME/.att/upload-last))"
  else
    print "STEP 1 · UPLOAD RESULTS · once on this Mac (test drive with the key plugged in)"
    print -r -- '   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh all'
  fi
  # Nov 21: BEFORE YOU START - what this Mac still needs before the tests will work.
  # Only problems are listed; nothing shows when the Mac is ready.
  fix=()
  want=$(head -1 "$TOOLS/target-macos.txt" 2>/dev/null | tr -d '[:space:]'); have=$(sw_vers -productVersion 2>/dev/null)
  [[ -n $want && $have != $want ]] && fix+=("macOS is $have: update to $want first (System Settings > General > Software Update), or results won't match the other Macs")
  tz=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
  [[ -n $tz && $tz != America/Chicago ]] && fix+=("Time zone is $tz: set it to Central so times line up (the walk-away queue does it for you, or: sudo systemsetup -settimezone America/Chicago)")
  osascript -e 'tell application "System Events" to tell process "Finder" to count windows' >/dev/null 2>&1 || \
    fix+=("Terminal can't control apps: System Settings > Privacy & Security > Accessibility > Terminal ON, then Cmd-Q Terminal (stacker, responsiveness, Final Cut, Numbers)")
  xcode-select -p >/dev/null 2>&1 || fix+=("Xcode Command Line Tools missing: run  xcode-select --install  (bandwidth test, Final Cut click helper, Python)")
  [[ -x $HOME/.lmstudio/bin/lms ]] || fix+=("LM Studio not set up: install LM Studio 0.4.28, open it once, quit it (Qwen, Gemma, ladder, stacker)")
  [[ -x /Applications/Blender.app/Contents/MacOS/Blender ]] || fix+=("Blender missing in Applications (Blender, Red Autumn, sustained): Tools/att-install-apps.zsh")
  [[ -n $(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep -m1 '\.app$') || -n $(print -l /Applications/Final\ Cut*.app(N)) ]] || \
    fix+=("Final Cut Pro (Creator Studio) missing: needed for the stacker/closer")
  # Numbers can be the Creator Studio copy with a different name: ask macOS the same way the stacker opens it
  { open -Ra Numbers 2>/dev/null || [[ -n $(print -l /Applications/Numbers*.app(N)) || -n $(mdfind "kMDItemCFBundleIdentifier == 'com.apple.iWork.Numbers*'" 2>/dev/null | grep -m1 '\.app$') ]]; } || \
    fix+=("Numbers missing: free in the App Store (stacker/closer)")
  dtc="$HOME/Library/Containers/com.liuliu.draw-things/Data/Documents"
  if [[ -z $(mdfind "kMDItemCFBundleIdentifier == 'com.liuliu.draw-things'" 2>/dev/null | grep -m1 '\.app$') ]]; then
    fix+=("Draw Things missing: free in the Mac App Store, open it once, Settings > API Server ON (HTTP, 7860)")
  elif [[ -d $dtc ]] && ! ls "$dtc" >/dev/null 2>&1; then
    fix+=("Terminal can't see Draw Things' files: Privacy & Security > Full Disk Access > Terminal ON, then Cmd-Q Terminal")
  fi
  freeg=$(df -g "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
  [[ -n $freeg ]] && (( freeg < 60 )) && fix+=("Only ${freeg} GB free: the stacker copies a 45 GB Final Cut library. Free space with Tools/att-get.zsh free")
  if pmset -g batt 2>/dev/null | grep -q InternalBattery; then
    pmset -g batt | head -1 | grep -q "AC Power" || fix+=("On battery: plug Apple's charger straight into the Mac (no dock), on a desk, not the couch")
  fi
  if (( ${#fix} )); then
    print ""
    print -r -- "------------------------------------------------------------"
    print " BEFORE YOU START · this Mac still needs:"
    print -r -- "------------------------------------------------------------"
    for f in $fix; do print -r -- " ! $f"; done
  else
    print "✓ Apps, permissions, macOS and free space look ready"
  fi
  print ""
  print -r -- "------------------------------------------------------------"
  print " THIS MAC'S TESTS (in order)"
  print -r -- "------------------------------------------------------------"
  print ""
  # Nov 21: the walk-away tests (GO=) weren't listed anywhere you could see them, so a Mac whose
  # only remaining walk-away test was bandwidth looked like it didn't have it.
  (( ${#DONE_GO} )) && print "✓ Walk-away already done on this Mac: ${(j:, :)DONE_GO}"
  if [[ -n $GO ]]; then
    typeset -A ST; ST=(cinebench 7 xcode 8 blender 9 redautumn 9b sustained 10 handbrake 11 qwen9b 14a qwen27b 14b gemma 14c ladder 14d whisper 14f bandwidth 14e responsiveness 17b appmem 17c realday 17d realdaycreator 17d)
    print "WALK-AWAY TESTS (one command runs them all, hands-off):"
    for t in ${=GO}; do print "   · Step ${ST[$t]:-?} · $t"; done
    print -r -- '   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-next.zsh go'
    print ""
  fi
  if [[ -n $SH_ROWS ]]; then
    print "STILL NEEDED ON THE SHEET (read live from the Mac Tests sheet, $(date '+%b %d %I:%M %p')):"
    [[ -n $SH_NOTE ]] && print -r -- "   ($SH_NOTE)"
    (( ${#SH_ROWNAMES} )) && print -r -- "   Sheet rows: ${(j:  ·  :)SH_ROWNAMES}"
    if (( ${#SH_HAND} )); then
      typeset -A HPAT; HPAT=(stacker "Memory/stacker_stacker_*.txt" drawthings "Image Tests/drawthings_*.txt" magmask "Final Cut/fcp-neural_*.txt" logic "Logic/logic_*.txt")
      for h in $SH_HAND; do
        hp=("${(@s:|:)h}")   # key step label command why
        ran=""; if [[ -n ${HPAT[$hp[1]]} ]]; then T_SINCE_S=$(since_for $hp[1]); hh=( "$RES"/${~HPAT[$hp[1]]}(N+newer) ); T_SINCE_S=""; (( ${#hh} )) && ran=1; fi
        if [[ -n $ran ]]; then print -r -- "   ✓ Step $hp[2] · $hp[3]: ran on this Mac, waiting to be logged (send Claude the card)"; continue; fi
        why=$hp[5]; [[ $why == blank ]] && why="" || why="  [$why]"
        print -r -- "   · Step $hp[2] · $hp[3]$why"
        [[ -n $hp[4] ]] && print -r -- "       $hp[4]"
      done
    elif [[ -z $SH_NOTE ]]; then
      print "   ✓ Nothing hand-run missing on the sheet for this Mac."
    fi
    print ""
  fi
  if [[ -n $key ]] && grep -q "^\[\[$key\]\]" "$ALL"; then
    # Nov 21: hands-on steps this Mac already finished (result newer than SINCE) get a ✓ DONE tag
    dn() { T_SINCE_S=$(since_for $2); local h=( "$RES"/${~1}(N+newer) ); T_SINCE_S=""; (( ${#h} )); }   # $2 = test key for SINCE_<key>=
    D_CLOSER=0 D_STACKER=0 D_RESP=0 D_DT=0
    dn "Memory/stacker_closer_*.txt" closer && D_CLOSER=1; dn "Memory/stacker_stacker_*.txt" stacker && D_STACKER=1
    dn "Memory/responsiveness_*.txt" responsiveness && D_RESP=1; dn "Image Tests/*" drawthings && D_DT=1
    sec | grep -v '^NAME=\|^GO=\|^SINCE\|^ROWS=\|^REDO=\|^SKIPT=' | awk -v c=$D_CLOSER -v st=$D_STACKER -v r=$D_RESP -v dt=$D_DT '
      /att-stacker.zsh closer/ && c  {print "      ✓ DONE (closer)"; next}
      /att-stacker.zsh stacker/ && st {print "      ✓ DONE (stacker)"; next}
      /att-responsiveness.zsh/ && r  {print "      ✓ DONE (responsiveness)"; next}
      /att-drawthings.zsh$/ && dt    {print "   ✓ DONE (Draw Things)"; next}
      {print}' | awk 'NR>1 && /^[0-9A-Z]/ && prev!="" {print ""} {print; prev=$0}'
  else
    print "Couldn't tell which Mac this is. Ask Claude, or read 00 RUN THIS NEXT - all Macs.txt."
  fi
  print ""
  print -r -- "------------------------------------------------------------"
  print " GOOD TO KNOW"
  print -r -- "------------------------------------------------------------"
  print " · Laptops: Apple's charger straight into the Mac, no dock, on a desk (not the couch)."
  print " · Paste each command as ONE line. Step numbers match 00 START HERE - Run Order.txt."
  print " · Loaners: before shipping, run  att-upload.zsh forget"
} > "$OUT"
if [[ $1 == go ]]; then
  if [[ -z $GO ]]; then
    print "✓ All walk-away tests are done on this Mac${DONE_GO:+ (${(j:, :)DONE_GO})}."
    nxt=$(sec | grep -m1 '^1\. ')
    [[ -n $nxt ]] && print "Next is hands-on: $nxt  (full steps in the RUN THIS NEXT window)"
    osascript -e 'tell application "TextEdit" to close (every document whose name contains "RUN THIS NEXT") saving no' >/dev/null 2>&1; open -a TextEdit "$OUT" 2>/dev/null; exit 0
  fi
  print "Starting this Mac's walk-away tests: $GO"
  QUEUE="$GO" exec zsh "$TOOLS/att-queue.zsh"
fi
cat "$OUT"
[[ -z $NOOPEN ]] && { osascript -e 'tell application "TextEdit" to close (every document whose name contains "RUN THIS NEXT") saving no' >/dev/null 2>&1; open -a TextEdit "$OUT" 2>/dev/null; }
exit 0

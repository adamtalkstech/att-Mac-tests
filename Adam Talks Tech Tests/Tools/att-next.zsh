#!/bin/zsh
# att-next.zsh - shows THIS Mac's next tests from "00 RUN THIS NEXT - all Macs.txt"
# (Claude keeps that file current through GitHub; Update Scripts runs this at the end.)
# Matches the Mac by hardware (model ID, chip, RAM, GPU cores, SSD), not by its name.
# Writes "00 RUN THIS NEXT (this Mac).txt" in the test folder and opens it in TextEdit.
# NOOPEN=1 in front = just print it.
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
SINCE_S=$(date -j -f "%Y-%m-%d %H:%M" "$SINCE" +%s 2>/dev/null || echo 0)
newer() { local m; m=$(stat -f %m "$REPLY" 2>/dev/null || echo 0); (( m > SINCE_S )); }
RES="$ROOT/Results/$(scutil --get ComputerName 2>/dev/null)"
typeset -A PAT; PAT=(bandwidth "Bandwidth/bandwidth_*" handbrake "HandBrake/handbrake_*.txt" sustained "Sustained/CPU_*"
  xcode "Xcode/xcode-bench_*" blender "Blender/blender-standard_*" redautumn "Blender/blender-redautumn_*"
  qwen9b "LM Studio/*qwen9b*" qwen27b "LM Studio/*qwen27b*" gemma "LM Studio/*gemma*" ladder "LM Studio/*ladder*"
  whisper "LM Studio/*whisper*" responsiveness "Memory/responsiveness_*.txt")
if [[ -n $GO ]]; then
  left=(); DONE_GO=()
  for t in ${=GO}; do
    hit=( "$RES"/${~PAT[$t]:-NOMATCH}(N+newer) )
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
  osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1 || \
    fix+=("Terminal can't control apps: System Settings > Privacy & Security > Accessibility > Terminal ON, then Cmd-Q Terminal (stacker, responsiveness, Final Cut, Numbers)")
  xcode-select -p >/dev/null 2>&1 || fix+=("Xcode Command Line Tools missing: run  xcode-select --install  (bandwidth test, Final Cut click helper, Python)")
  [[ -x $HOME/.lmstudio/bin/lms ]] || fix+=("LM Studio not set up: install LM Studio 0.4.28, open it once, quit it (Qwen, Gemma, ladder, stacker)")
  [[ -x /Applications/Blender.app/Contents/MacOS/Blender ]] || fix+=("Blender missing in Applications (Blender, Red Autumn, sustained): Tools/att-install-apps.zsh")
  [[ -n $(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep -m1 '\.app$') || -n $(print -l /Applications/Final\ Cut*.app(N)) ]] || \
    fix+=("Final Cut Pro (Creator Studio) missing: needed for the stacker/closer")
  [[ -d /Applications/Numbers.app ]] || fix+=("Numbers missing: free in the App Store (stacker/closer)")
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
    typeset -A ST; ST=(xcode 8 blender 9 redautumn 9b sustained 10 handbrake 11 qwen9b 14a qwen27b 14b gemma 14c ladder 14d whisper E4 bandwidth 14e responsiveness 17b)
    print "WALK-AWAY TESTS (one command runs them all, hands-off):"
    for t in ${=GO}; do print "   · Step ${ST[$t]:-?} · $t"; done
    print -r -- '   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-next.zsh go'
    print ""
  fi
  if [[ -n $key ]] && grep -q "^\[\[$key\]\]" "$ALL"; then
    sec | grep -v '^NAME=\|^GO=\|^SINCE=' | awk 'NR>1 && /^[0-9A-Z]/ && prev!="" {print ""} {print; prev=$0}'
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
  [[ -n $GO ]] || { print "Nothing walk-away is scheduled for this Mac right now (see its list)."; exit 0; }
  print "Starting this Mac's walk-away tests: $GO"
  QUEUE="$GO" exec zsh "$TOOLS/att-queue.zsh"
fi
cat "$OUT"
[[ -z $NOOPEN ]] && open -a TextEdit "$OUT" 2>/dev/null
exit 0

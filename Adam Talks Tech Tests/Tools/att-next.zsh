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
  print ""
  print -r -- "------------------------------------------------------------"
  print " THIS MAC'S TESTS (in order)"
  print -r -- "------------------------------------------------------------"
  print ""
  if [[ -n $key ]] && grep -q "^\[\[$key\]\]" "$ALL"; then
    sec | grep -v '^NAME=\|^GO=' | awk 'NR>1 && /^[0-9A-Z]/ && prev!="" {print ""} {print; prev=$0}'
  else
    print "Couldn't tell which Mac this is. Ask Claude, or read 00 RUN THIS NEXT - all Macs.txt."
  fi
  print ""
  print -r -- "------------------------------------------------------------"
  print " GOOD TO KNOW"
  print -r -- "------------------------------------------------------------"
  print " · Laptops: Apple's charger straight into the Mac, no dock."
  print " · Paste each command as ONE line. Step numbers match 00 START HERE - Run Order.txt."
  print " · STACKER (step 17): restart before each run. Final Cut's timeline must have"
  print "   \"universal control on mac 3 min\" open. First time on a Mac: open Final Cut and"
  print "   the Numbers workbook once, quit both, allow Terminal in Accessibility, restart."
  print -r -- '     Closer:   cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-stacker.zsh closer'
  print -r -- '     Stacker:  cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-stacker.zsh stacker'
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

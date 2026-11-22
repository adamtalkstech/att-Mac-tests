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
{
  print "THIS MAC: ${name:-Mac} ($model) | $chip | ${ram}GB | ${gpu:-?}-core GPU | ${disk:-?} SSD"
  print "$(head -2 "$ALL" | tail -1)"
  print ""
  if [[ -n $key ]] && grep -q "^\[\[$key\]\]" "$ALL"; then
    awk -v k="[[$key]]" '$0==k {on=1; next} /^\[\[/ {on=0} on' "$ALL"
    print ""
    awk '/^\[\[/ {exit} NR>2' "$ALL"
  else
    print "Couldn't tell which Mac this is, so here's everyone's list:"
    print ""; sed 's/^\[\[.*\]\]$//' "$ALL"
  fi
} > "$OUT"
cat "$OUT"
[[ -z $NOOPEN ]] && open -a TextEdit "$OUT" 2>/dev/null
exit 0

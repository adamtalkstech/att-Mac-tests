#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
whence att_pause_bg >/dev/null && att_pause_bg   # pause Photos/Spotlight/Siri scanning for the test (wakes back up at the end)
# =============================================================================
#  att-export-timer.zsh  -  ATT export timer (v1, Nov 16 2026)
# =============================================================================
#  Times any export that writes files into a folder: Final Cut (Share),
#  Lightroom exports, Blender animation renders, Compressor, HandBrake.
#  No stopwatch, no stat math, and it handles "3 files pop up" exports.
#
#  HOW IT WORKS
#   1. Pick an EMPTY folder as the export location in the app.
#      Default: the "Export" folder inside Adam Talks Tech Tests (the script
#      makes it and checks it's empty). Keep the test folder in ~/Downloads so
#      exports land on the Mac's own SSD, not the LaCie.
#   2. Start the script. It waits for you to press Return.
#   3. Press Return in Terminal the moment you click Export / Share / Render.
#   4. Walk away. It watches the folder every 1/4 second. The export is done
#      when nothing in the folder has changed for STABLE seconds (default 30).
#      The END time is the last moment a file changed, not when it noticed,
#      so the wait doesn't add to the result.
#
#  RUN
#    zsh att-export-timer.zsh "" "FCP 30 min Apple Devices"   ("" = use the Mac's name)
#    zsh att-export-timer.zsh "M6 MBP" "Lightroom 500" COUNT=500
#    zsh att-export-timer.zsh "M6 MBP" "Red Autumn 1-25" STABLE=120
#
#  OPTIONS (after the two names, any order)
#    FOLDER=path   folder to watch (default: Adam Talks Tech Tests/Export)
#    STABLE=30     seconds of no change that means "done". Use 120+ for
#                  Blender (slow frames) or anything that pauses mid-export.
#    COUNT=500     done as soon as this many finished files exist (Lightroom),
#                  plus 5 quiet seconds. Faster and safer than STABLE alone.
#    AUTO=1        don't wait for Return: start the clock when the first
#                  file appears. Use only if you can't reach the keyboard.
#                  (Misses the time before the app creates its first file.)
#
#  RESULTS: Adam Talks Tech Tests/Results/All Macs exports.csv (one row per run)
#  and a line on screen to send to Claude. Nothing to install.
# =============================================================================

zmodload zsh/datetime zsh/stat

# ---------- Where am I? ----------
# Works from ~/Downloads/Adam Talks Tech Tests or straight from the LaCie.
# Results go to <test folder>/Results/<Mac name>/ next to everything else.
SCRIPT_DIR=${0:A:h}
ROOT=$SCRIPT_DIR
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=$SCRIPT_DIR
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}
LABEL="${1:-$MACNAME}"
TEST="${2:-Export}"
shift 2 2>/dev/null
FOLDER="$ROOT/Export"; STABLE=30; COUNT=0; AUTO=0; START_AT=""
for a in "$@"; do
  case $a in
    FOLDER=*) FOLDER="${a#FOLDER=}"; FOLDER="${~FOLDER}" ;;
    STABLE=*) STABLE="${a#STABLE=}" ;;
    COUNT=*)  COUNT="${a#COUNT=}" ;;
    AUTO=*)   AUTO="${a#AUTO=}" ;;
    START=*)  START_AT="${a#START=}" ;;   # clock start given by a script that clicked Share itself
    *) print "Unknown option: $a"; exit 1 ;;
  esac
done
FOLDER="${FOLDER%/}"
OUTDIR="$ROOT/Results"
CSV="$OUTDIR/All Macs exports.csv"
mkdir -p "$OUTDIR" "$FOLDER"

# Files that are still being written by the app, or system clutter.
is_ignored() { [[ ${1:t} == .DS_Store || ${1:t} == *.tmp || ${1:t} == *.part || ${1:t} == *.download ]]; }

# Snapshot: file count, total bytes, and a signature that changes whenever
# any file is added, removed, grows or is touched.
snapshot() {
  local f n=0 bytes=0 sig=""
  local -A st
  for f in "$FOLDER"/**/*(.ND); do
    [[ ${f:t} == .DS_Store ]] && continue
    zstat -H st -- "$f" 2>/dev/null || continue
    is_ignored "$f" || (( n++ ))
    (( bytes += st[size] ))
    sig+="${f}:${st[size]}:${st[mtime]};"
  done
  SNAP_N=$n; SNAP_BYTES=$bytes; SNAP_SIG=$sig
}

snapshot
if (( SNAP_N > 0 )) && [[ -z $START_AT ]]; then
  print "The folder isn't empty: $FOLDER"
  print "It has $SNAP_N file(s). Empty it (or pick another folder with FOLDER=...) so"
  print "old files can't count toward this export, then run the script again."
  exit 1
fi

print "================ ATT Export Timer ================"
print "Mac:      $LABEL"
print "Test:     $TEST"
print "Watching: $FOLDER"
if (( COUNT > 0 )); then print "Done when: $COUNT files are in (then 5 quiet seconds), or no change for ${STABLE}s"
else print "Done when: no change for ${STABLE}s"; fi
print "=================================================="
print "Set this folder as the export location in the app."
[[ $FOLDER == /Volumes/* ]] && print "!! This folder is on an external drive. The export would time the drive, not the Mac.\n   Copy the test folder to ~/Downloads (att-copy-tests.zsh) and run it from there."

if [[ -n $START_AT ]]; then
  START=$START_AT
  print "Clock started by the script when it clicked Save ($(strftime '%I:%M:%S %p' ${START_AT%.*})). Hands off."
  AUTO=2
elif (( AUTO )); then
  print "AUTO mode: the clock starts when the first file appears."
  START=""
else
  print ""
  print -n "Press Return the moment you click Export / Share / Render... "
  read -r
  START=$EPOCHREALTIME
  print "Clock started $(strftime '%I:%M:%S %p' $EPOCHSECONDS). Hands off."
fi

FIRST=""; LAST_CHANGE=""; PREV_SIG=""; t_print=$EPOCHSECONDS
while true; do
  snapshot
  now=$EPOCHREALTIME
  if [[ $SNAP_SIG != $PREV_SIG ]]; then
    [[ -z $FIRST && -n $SNAP_SIG ]] && FIRST=$now
    [[ -z $START && -n $FIRST ]] && START=$FIRST
    LAST_CHANGE=$now
    PREV_SIG=$SNAP_SIG
  fi
  if [[ -n $LAST_CHANGE ]]; then
    quiet=$(( now - LAST_CHANGE ))
    if (( COUNT > 0 && SNAP_N >= COUNT && quiet >= 5 )); then break; fi
    if (( quiet >= STABLE )); then break; fi
  fi
  if (( EPOCHSECONDS - t_print >= 30 )); then
    t_print=$EPOCHSECONDS
    [[ -n $START ]] && el=$(( EPOCHSECONDS - ${START%.*} )) || el=0
    printf "  %d:%02d  %d file(s), %.1f MB\n" $(( el / 60 )) $(( el % 60 )) $SNAP_N $(( SNAP_BYTES / 1048576.0 ))
  fi
  sleep 0.25
done

TOTAL=$(( LAST_CHANGE - START ))
FROM_FIRST=$(( LAST_CHANGE - FIRST ))
fmt_time() {
  local s=$1 m
  m=$(( ${s%.*} / 60 ))
  if (( m > 0 )); then printf "%dm %.2fs" $m $(( s - m * 60 )); else printf "%.2fs" $s; fi
}

att_card_start "Export timer: $TEST"
print "$LABEL  |  $TEST"
print "Export time:        $(fmt_time $TOTAL)   ($( (( AUTO == 2 )) && print "Save click" || { (( AUTO )) && print "first file" || print "Return press"; }) to last file change)"
(( AUTO )) || print "First file to last: $(fmt_time $FROM_FIRST)"
printf "Files: %d   Size: %.1f MB\n" $SNAP_N $(( SNAP_BYTES / 1048576.0 ))
(( COUNT > 0 && SNAP_N < COUNT )) && print "!! Only $SNAP_N of $COUNT files. It stopped on the ${STABLE}s quiet rule. Check the export finished."
print "Done $(strftime '%I:%M:%S %p' ${LAST_CHANGE%.*}), noticed ${STABLE}s later (not counted)."
att_card_end

[[ -f $CSV ]] || print "Date,Time,Mac,Test,Export seconds,First file to last (s),Files,MB,Start mode,Folder,macOS" > "$CSV"
printf '%s,%s,"%s","%s",%.2f,%.2f,%d,%.1f,%s,"%s",%s\n' "$(strftime %F $EPOCHSECONDS)" "$(strftime %H:%M $EPOCHSECONDS)" \
  "$LABEL" "$TEST" $TOTAL $FROM_FIRST $SNAP_N $(( SNAP_BYTES / 1048576.0 )) "$( (( AUTO == 2 )) && print script-click || { (( AUTO )) && print first-file || print return-key; })" \
  "$FOLDER" "$(sw_vers -productVersion 2>/dev/null)" >> "$CSV"
# Same row in this Mac's own Results folder (that's the folder step 99 brings back)
MCSV="$OUTDIR/$MACNAME/Exports/exports.csv"; mkdir -p "${MCSV:h}"
[[ -f $MCSV ]] || head -1 "$CSV" > "$MCSV"
tail -1 "$CSV" >> "$MCSV"
print "Logged to: $MCSV"
[[ -n $ATT_STEP_OVERRIDE ]] || print "Empty the folder before the next run."
afplay /System/Library/Sounds/Glass.aiff 2>/dev/null

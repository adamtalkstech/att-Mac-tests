#!/bin/zsh
# =============================================================================
#  att-cinebench.zsh - Cinebench 2026 with no clicking (Run Order step 7, v1 Nov 22 2026)
# =============================================================================
#  Runs Cinebench's own command-line mode (Maxon's g_Cinebench...=true options):
#  CPU multi, CPU single, then GPU, one pass each (same as one click in the app),
#  with the usual quit-apps + pause scanning + cooldown before each.
#  Prints a photo card with LOG lines, so the scores go into the Mac's Main Results row.
#  ~10-15 min. Also runs in the walk-away queue as "cinebench".
#  FIRST TIME: compare the card once with a normal Cinebench run in the app. If the app's
#  numbers differ by more than ~2%, tell Claude (the card is held until then if a score is missing).
# =============================================================================
source "${0:A:h}/att-card.zsh"
ROOT=${0:A:h:h}; MAC=$(scutil --get ComputerName 2>/dev/null)
OUT="$ROOT/Results/$MAC/Cinebench"; mkdir -p "$OUT"; STAMP=$(date +%Y-%m-%d_%H-%M)
APP=$(print -l /Applications/Cinebench*.app(N) | head -1)
[[ -z $APP ]] && APP=$(mdfind "kMDItemCFBundleIdentifier == 'net.maxon.cinebench*'" 2>/dev/null | grep -m1 '\.app$')
EXE=$(print -l "$APP"/Contents/MacOS/*(N*) | grep -i -m1 cinebench)
[[ -x $EXE ]] || { print "Cinebench 2026 isn't installed (free, Mac App Store or maxon.net). Install it, open it once, quit it, rerun."; exit 1; }
osascript -e 'tell application "Cinebench" to quit' >/dev/null 2>&1
run_cb() {   # $1 label, $2 option, $3 "again" after the first -> score in $REPLY (or empty), keeps the raw log
  local log="$OUT/.cinebench_${STAMP}_${1// /-}.log" s
  if [[ $3 == again ]]; then att_cooldown --again; else att_cooldown; fi
  print "Running Cinebench $1 (one pass) ..."
  "$EXE" "$2=true" g_CinebenchMinimumTestDuration=1 > "$log" 2>&1
  # Cinebench prints e.g. "CB 1234.56 (0.00)". Take the last CB number in the log.
  s=$(grep -Eo 'CB[^0-9]{0,4}[0-9]+(\.[0-9]+)?' "$log" | tail -1 | grep -Eo '[0-9]+(\.[0-9]+)?$')
  [[ -z $s ]] && s=$(grep -iE 'score' "$log" | grep -Eo '[0-9]{3,}(\.[0-9]+)?' | tail -1)
  REPLY=$s
}
run_cb "CPU multi" g_CinebenchCpuXTest;        MULTI=$REPLY
run_cb "CPU single" g_CinebenchCpu1Test again; SINGLE=$REPLY
run_cb "GPU" g_CinebenchGpuTest again;         GPU=$REPLY
att_resume_bg
F="$OUT/cinebench_$STAMP.txt"
{ att_card_start "Cinebench 2026 (command line, one pass each)"
  print "CPU multi:  ${MULTI:-?}"
  print "CPU single: ${SINGLE:-?}"
  print "GPU:        ${GPU:-?}"
  if [[ -n $MULTI && -n $SINGLE ]]; then
    print "MP ratio:   $(awk -v m=$MULTI -v s=$SINGLE 'BEGIN{printf "%.2f", m/s}')"
  fi
  if [[ -z $MULTI || -z $SINGLE || -z $GPU ]]; then
    print "!! A score couldn't be read from Cinebench's output: run it again, or run it in the app and send Claude a photo."
    print "   Raw logs: Results/$MAC/Cinebench/.cinebench_${STAMP}_*.log (hidden files: Cmd-Shift-. in Finder)"
  else
    att_log "Main Results" "GPU" "${GPU%.*}"
    att_log "Main Results" "CPU Multithreaded" "${MULTI%.*}"
    att_log "Main Results" "CPU Single Thread" "${SINGLE%.*}"
    att_log "Main Results" "MP Ratio" "$(awk -v m=$MULTI -v s=$SINGLE 'BEGIN{printf "%.2f", m/s}')"
  fi
  att_card_end; } | tee "$F"
whence att_upload_results >/dev/null && att_upload_results

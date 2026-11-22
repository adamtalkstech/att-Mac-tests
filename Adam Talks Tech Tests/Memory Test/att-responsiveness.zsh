#!/bin/zsh
# ATT Responsiveness Score, Run Order step 17b (v1.0, Nov 21 2026; rebuilt to match the newer tests)
# One score for "how snappy does this Mac stay as you pile on a normal day?"
#
# Hands off, about 15 minutes (plus the cooldown). No Return presses.
#   1. Checks Accessibility + Safari's Apple Events setting (stops with the fix if either is off).
#   2. Same start as every test: quits other apps, power check, pauses Photos/Spotlight, cooldown.
#   3. Opens Safari + a few built-in Apple apps, then 80 websites in steps: 0, 20, 40, 60, 80 tabs.
#   4. At each step, times how long each app takes to answer when you switch to it,
#      and how long old Safari tabs take to come back. Logs swap and free memory.
#   5. Photo card with SHEET lines. Saves .txt + .csv to Results/<Mac>/Memory (auto-uploads).
#
# One time per Mac:
#   - System Settings > Privacy & Security > Accessibility: Terminal ON
#   - Safari > Settings > Advanced: "Show features for web developers",
#     then Settings > Developer: "Allow JavaScript from Apple Events"
# Run (restart first):
#   cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-responsiveness.zsh
# Options: NOCOOL=1 skip cooldown, NOQUIT=1 don't quit apps, NOPAUSE=1 don't pause Photos/Spotlight.

source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || { print "Can't find Tools/att-card.zsh. Run Update Scripts first."; exit 1; }
zmodload zsh/datetime

INSTANT_MS=250          # a switch this fast counts as instant (score 1000)
WANT_APPS=("Calculator" "Chess" "Dictionary" "Font Book" "Activity Monitor" "TV" "GarageBand")
WAIT_MAX=15             # seconds to wait for each new tab to finish loading
STAGES=(0 20 40 60 80)

ROOT=${0:A:h:h}
MAC=$(scutil --get ComputerName 2>/dev/null)
OUTDIR="$ROOT/Results/$MAC/Memory"; mkdir -p "$OUTDIR"
STAMP=$(date +%Y-%m-%d_%H-%M-%S)
CSV="$OUTDIR/responsiveness_$STAMP.csv"
TXT="$OUTDIR/responsiveness_$STAMP.txt"
BGLOG="$OUTDIR/.responsiveness_bg_$STAMP.txt"

SITES=(
'https://www.apple.com'
'https://www.apple.com/mac/'
'https://www.apple.com/mac-mini/'
'https://www.apple.com/macbook-pro/'
'https://www.apple.com/macbook-air/'
'https://www.apple.com/imac/'
'https://www.apple.com/mac-studio/'
'https://www.apple.com/ipad/'
'https://www.apple.com/iphone/'
'https://www.apple.com/watch/'
'https://www.apple.com/airpods/'
'https://support.apple.com'
'https://developer.apple.com'
'https://www.theverge.com'
'https://www.macrumors.com'
'https://9to5mac.com'
'https://appleinsider.com'
'https://www.engadget.com'
'https://techcrunch.com'
'https://www.cnet.com'
'https://www.tomsguide.com'
'https://en.wikipedia.org/wiki/Great_Barrier_Reef'
'https://en.wikipedia.org/wiki/Apple_Inc.'
'https://en.wikipedia.org/wiki/Mac_Mini'
'https://en.wikipedia.org/wiki/MacBook_Pro'
'https://en.wikipedia.org/wiki/Apple_silicon'
'https://en.wikipedia.org/wiki/Steve_Jobs'
'https://en.wikipedia.org/wiki/Roman_Empire'
'https://en.wikipedia.org/wiki/YouTube'
'https://en.wikipedia.org/wiki/Photography'
'https://en.wikipedia.org/wiki/Missouri'
'https://en.wikipedia.org/wiki/Random-access_memory'
'https://www.youtube.com/@adamtalkstech'
'https://vimeo.com'
'https://www.twitch.tv'
'https://www.reddit.com/r/mac/'
'https://www.reddit.com/r/apple/'
'https://en.wikipedia.org/wiki/Pinterest'
'https://docs.github.com'
'https://stackoverflow.com'
'https://en.wikipedia.org/wiki/Notion_(productivity_software)'
'https://en.wikipedia.org/wiki/Figma'
'https://en.wikipedia.org/wiki/Canva'
'https://en.wikipedia.org/wiki/Dropbox'
'https://en.wikipedia.org/wiki/Zoom_Communications'
'https://en.wikipedia.org/wiki/Slack_(software)'
'https://en.wikipedia.org/wiki/Trello'
'https://en.wikipedia.org/wiki/Mount_Everest'
'https://www.espn.com'
'https://www.nfl.com'
'https://www.imdb.com'
'https://www.rottentomatoes.com'
'https://www.allrecipes.com'
'https://www.nationalgeographic.com'
'https://www.nasa.gov'
'https://www.adobe.com'
'https://www.microsoft.com'
'https://www.blackmagicdesign.com'
'https://www.logitech.com'
'https://adamtalks.tech'
'https://adamtalks.tech/mac-tests/'
'https://en.wikipedia.org/wiki/Saturn'
'https://en.wikipedia.org/wiki/IPhone'
'https://en.wikipedia.org/wiki/MacOS'
'https://en.wikipedia.org/wiki/Final_Cut_Pro'
'https://en.wikipedia.org/wiki/Adobe_Lightroom'
'https://en.wikipedia.org/wiki/Blender_(software)'
'https://en.wikipedia.org/wiki/Apple_Watch'
'https://en.wikipedia.org/wiki/AirPods'
'https://en.wikipedia.org/wiki/Solar_System'
'https://en.wikipedia.org/wiki/Moon'
'https://en.wikipedia.org/wiki/Photosynthesis'
'https://en.wikipedia.org/wiki/Volcano'
'https://en.wikipedia.org/wiki/Grand_Canyon'
'https://developer.mozilla.org'
'https://www.blender.org'
'https://www.apple.com/final-cut-pro/'
'https://www.apple.com/logic-pro/'
'https://www.dpreview.com'
'https://www.rtings.com'
)

mem_vals() {
  local swap free
  swap=$(sysctl -n vm.swapusage | awk '{print $6}')
  free=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{print $2}')
  print -r -- "${swap:-?} ${free:-?}"
}
ms_since() { printf '%.0f' $(( (EPOCHREALTIME - $1) * 1000 )) }

probe_app() {   # bring the app to front, then ask for its front window; a busy app can't answer until ready
  local app="$1" t0 rc
  t0=$EPOCHREALTIME
  osascript -e "tell application \"System Events\" to set frontmost of process \"$app\" to true" >/dev/null 2>&1
  osascript -e "tell application \"System Events\" to tell process \"$app\" to get name of front window" >/dev/null 2>&1
  rc=$?
  print "$(ms_since $t0) $rc"
}

probe_tab() {   # switch Safari to tab N and time until the page answers
  local n="$1" t0 r
  t0=$EPOCHREALTIME
  r=$(osascript - "$n" <<'OSA' 2>/dev/null
on run argv
  tell application "Safari"
    activate
    set w to front window
    set current tab of w to tab ((item 1 of argv) as integer) of w
    return do JavaScript "document.readyState" in current tab of w
  end tell
end run
OSA
)
  print "$(ms_since $t0) $([[ -n "$r" ]] && print 0 || print 1)"
}

open_tab() {
  osascript - "$1" <<'OSA' >/dev/null 2>&1
on run argv
  tell application "Safari"
    tell front window to set current tab to (make new tab with properties {URL:(item 1 of argv)})
  end tell
end run
OSA
  local s
  for (( s=0; s<WAIT_MAX*2; s++ )); do
    sleep 0.5
    [[ "$(osascript -e 'tell application "Safari" to do JavaScript "document.readyState" in current tab of front window' 2>/dev/null)" == "complete" ]] && break
  done
}

print "ATT Responsiveness Score (step 17b) on $MAC"

# --- 1. One-time settings check (stops with the fix, no prompts) ---
if ! osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
  print "!! Terminal can't control other apps yet."
  print "   System Settings > Privacy & Security > Accessibility: turn Terminal ON, quit Terminal, then run this again."
  exit 1
fi
osascript -e 'tell application "Safari"' -e 'make new document with properties {URL:"about:blank"}' -e 'end tell' >/dev/null 2>&1
sleep 4
t=$(osascript -e 'tell application "Safari" to do JavaScript "(1+1).toString()" in current tab of front window' 2>&1)
if [[ $t != 2 && $t != 2.0 ]]; then
  print "!! Safari won't take the timing check."
  print "   Safari > Settings > Advanced: Show features for web developers ON,"
  print "   then Settings > Developer: Allow JavaScript from Apple Events ON. Quit Safari, run this again."
  print "   (Safari said: $t)"
  exit 1
fi
print "Settings OK (Accessibility + Safari)."

# Only time apps this Mac has (GarageBand/Chess can be missing on a fresh Mac)
APPS=(); MISSING=()
for a in $WANT_APPS; do open -Ra "$a" 2>/dev/null && APPS+=("$a") || MISSING+=("$a"); done
(( ${#MISSING} )) && print "Not installed, skipped: ${(j:, :)MISSING}"

# --- 2. Same clean start as every test (quits apps incl. Safari, power check, pause scanners, cooldown) ---
ATT_KEEP="Claude,Screen Sharing" att_cooldown

# --- 3. Open the test apps and a fresh Safari window ---
for a in $APPS; do open -a "$a" 2>/dev/null; sleep 2; done
osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1; sleep 3
osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1; sleep 1
osascript -e 'tell application "Safari" to make new document with properties {URL:"https://www.apple.com"}' >/dev/null 2>&1
print "Settling for 60 seconds..."; sleep 60

att_watch_start "$BGLOG" "Safari|WebKit|Calculator|Chess|Dictionary|Font Book|Activity Monitor|TV|GarageBand|osascript|System Events|memory_pressure"

print "stage_tabs,item,ms,ok,swap_used,memory_free" > "$CSV"
typeset -a stage_avg stage_worst stage_lines
all_total=0; all_count=0; noanswer=0
opened=1   # the apple.com tab is site 1

for target in $STAGES; do
  if (( target > 0 )); then
    print "\nOpening tabs up to ${target}..."
    while (( opened < target )); do (( opened++ )); open_tab "${SITES[$opened]}"; done
    sleep 10
  fi
  read swap free <<< "$(mem_vals)"
  print "\n== ${target} tabs open (swap ${swap}, memory free ${free}) =="
  st_total=0; st_count=0; st_worst=0
  for a in $APPS "Safari"; do
    read ms rc <<< "$(probe_app "$a")"
    printf "  %-16s %6s ms%s\n" "$a" $ms "$([[ $rc == 0 ]] || print '  (no answer, not scored)')"
    print "${target},\"${a}\",${ms},$([[ $rc == 0 ]] && print yes || print no),${swap},${free}" >> "$CSV"
    if [[ $rc == 0 ]]; then (( st_total += ms, st_count++ )); (( ms > st_worst )) && st_worst=$ms; else (( noanswer++ )); fi
    sleep 1
  done
  if (( opened >= 5 )); then
    for n in 2 $(( opened / 2 )) $(( opened - 1 )); do
      read ms rc <<< "$(probe_tab $n)"
      printf "  %-16s %6s ms%s\n" "old tab #${n}" $ms "$([[ $rc == 0 ]] || print '  (no answer, not scored)')"
      print "${target},\"tab ${n}\",${ms},$([[ $rc == 0 ]] && print yes || print no),${swap},${free}" >> "$CSV"
      if [[ $rc == 0 ]]; then (( st_total += ms, st_count++ )); (( ms > st_worst )) && st_worst=$ms; else (( noanswer++ )); fi
      sleep 1
    done
  fi
  if (( st_count > 0 )); then
    avg=$(( st_total / st_count ))
  else
    avg=0
  fi
  stage_avg+=($avg); stage_worst+=($st_worst)
  stage_lines+=("$(printf '%3d tabs: avg %5d ms, worst %5d ms (swap %s, free %s)' $target $avg $st_worst $swap $free)")
  (( all_total += st_total, all_count += st_count ))
  print "  -> average ${avg} ms, worst ${st_worst} ms"
done

att_watch_stop
BGLINE=$(att_watch_report "$BGLOG"); rm -f "$BGLOG"

# Leave the Mac clean: quit the test apps and Safari (80 tabs)
for a in $APPS "Safari"; do osascript -e "tell application \"$a\" to quit" >/dev/null 2>&1; done

# --- 5. Score + photo card ---
sc() { local v=$1; (( v <= 0 )) && { print 0; return; }; local s=$(( INSTANT_MS * 1000 / v )); (( s > 1000 )) && s=1000; print $s; }
if (( all_count == 0 || stage_avg[1] == 0 || stage_avg[-1] == 0 )); then
  { att_card_start "Responsiveness (app switching, 0 to 80 tabs)"
    print "!! No usable timings (apps didn't answer). Check Accessibility for Terminal, restart, run again."
    att_card_end; } | tee "$TXT"
  exit 1
fi
overall=$(( all_total / all_count ))
score=$(sc $overall); light=$(sc ${stage_avg[1]}); loaded=$(sc ${stage_avg[-1]})
slower=$(( (stage_avg[-1] - stage_avg[1]) * 100 / stage_avg[1] ))
read swap free <<< "$(mem_vals)"

{ att_card_start "Responsiveness (app switching, 0 to 80 tabs)"
  print "LOADED SCORE (80 tabs): ${loaded}   <- headline (1000 = instant, higher is better)"
  print "Light score (0 tabs):   ${light}"
  print "Overall score:          ${score}"
  print "80 tabs vs none:        ${slower}% slower to switch"
  print "Worst single wait (80): ${stage_worst[-1]} ms"
  print -r -- "---------------------------------------------------------------"
  for l in $stage_lines; do print -r -- "$l"; done
  print -r -- "---------------------------------------------------------------"
  print "Swap at the end: ${swap}   Memory free: ${free}"
  (( noanswer )) && print "No answer (not scored): ${noanswer} checks"
  (( ${#MISSING} )) && print "Apps not installed: ${(j:, :)MISSING}"
  print -r -- "$BGLINE"
  print "SHEET: Responsiveness loaded / light / overall  ->  ${loaded} / ${light} / ${score}"
  print "SHEET: Avg ms 0 tabs / 80 tabs / worst 80  ->  ${stage_avg[1]} / ${stage_avg[-1]} / ${stage_worst[-1]}"
  print "SHEET: Swap end / slower %  ->  ${swap} / ${slower}%"
  print "Saved: Results/$MAC/Memory/${TXT:t} (+ .csv)"
  att_card_end; } | tee "$TXT"

print "loaded_score,${loaded},light_score,${light},slower_pct,${slower},score,${score},avg_ms,${overall},avg0,${stage_avg[1]},avg80,${stage_avg[-1]},worst80,${stage_worst[-1]},swap_end,${swap},free_end,${free}" >> "$CSV"

#!/bin/zsh
# ATT Responsiveness Score, Run Order step 17b (v1.0, Nov 21 2026; rebuilt to match the newer tests)
# One score for "how snappy does this Mac stay as you pile on a normal day?"
#
# Hands off, about 45 minutes: 3 runs, run 1 is a warm-up, runs 2-3 averaged (RUNS=1 for one). No Return presses.
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
BGLOG="$OUTDIR/responsiveness_background_$STAMP.txt"

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

PAGE=$(sysctl -n hw.pagesize 2>/dev/null || print 16384)
plev_name() { case $1 in 1) print green;; 2) print yellow;; 4) print red;; *) print "?";; esac; }
comp_gb() { vm_stat 2>/dev/null | awk -v p=$PAGE '/occupied by compressor/ {gsub(/\./,"",$NF); printf "%.1f", $NF*p/1e9}'; }
mem_vals() {   # swap used, free %, pressure color (Activity Monitor's graph), compressed GB
  local swap free lvl
  swap=$(sysctl -n vm.swapusage | awk '{print $6}')
  free=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{print $2}')
  lvl=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)
  [[ -z $lvl ]] && lvl=$(memory_pressure 2>/dev/null | awk '/pressure level/ {print ($NF ~ /[Cc]ritical/ ? 4 : ($NF ~ /[Ww]arn/ ? 2 : 1)); exit}')
  print -r -- "${swap:-?} ${free:-?} $(plev_name $lvl) $(comp_gb)GB"
}
# Every 5 s during a run: pressure level, swap MB, compressor pages -> peaks for the card
mem_sampler_start() {
  : > "$1"
  ( while true; do
      print "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null) $(sysctl -n vm.swapusage | awk '{v=$6; u=substr(v,length(v)); sub(/[MG]$/,"",v); if(u=="G") v*=1024; printf "%d", v}') $(vm_stat | awk '/occupied by compressor/ {gsub(/\./,"",$NF); print $NF}')"
      sleep 5
    done >> "$1" ) &!
  MEMPID=$!
}
mem_sampler_stop() { [[ -n $MEMPID ]] && kill $MEMPID 2>/dev/null; MEMPID=""; }
ms_since() { printf '%.0f' $(( (EPOCHREALTIME - $1) * 1000 )) }

probe_app() {   # bring the app to front, then ask it how many windows it has; a busy app can't answer until ready
  # Nov 21 fix: the old check asked for the FRONT WINDOW's name, which fails in ~250 ms when an app
  # has no window open (closed, minimized, or behind Safari's 80 tabs) -> every app "no answer"
  # at 80 tabs on the M5 Pro MBP. Counting windows answers even with zero, so only a real
  # failure (app not running, Accessibility off) counts as no answer; one retry, reason logged.
  local app="$1" t0 rc err try
  t0=$EPOCHREALTIME
  osascript -e "tell application \"System Events\" to set frontmost of process \"$app\" to true" >/dev/null 2>&1
  for try in 1 2; do
    err=$(osascript -e "tell application \"System Events\" to tell process \"$app\" to count windows" 2>&1 >/dev/null)
    rc=$?; (( rc == 0 )) && break
    pgrep -xq "$app" || { open -a "$app" 2>/dev/null; sleep 2; }
  done
  (( rc )) && print -r -- "$(date +%H:%M:%S) $app: ${err//$'\n'/ }" >> "$OUTDIR/responsiveness_noanswer_$STAMP.txt"
  print "$(ms_since $t0) $rc"
}

close_test_apps() {   # Nov 21: close all 80 tabs first (Safari can ask before quitting with many
  # tabs, and reopens them next launch), then quit Safari + the test apps; force-quit stragglers
  local a
  osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1
  for a in $APPS "Safari"; do osascript -e "tell application \"$a\" to quit" >/dev/null 2>&1; done
  sleep 5
  for a in $APPS "Safari"; do pgrep -xq "$a" && { print "  $a didn't quit, forcing it"; pkill -x "$a" 2>/dev/null; }; done
  return 0
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
    return do JavaScript "var r=window.__att?'kept':'reloaded'; window.__att=1; r" in current tab of w
  end tell
end run
OSA
)
  print "$(ms_since $t0) $([[ -n "$r" ]] && print 0 || print 1) $([[ $r == kept ]] && print 0 || print 1)"
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
  mark_tab
}
mark_tab() { osascript -e 'tell application "Safari" to do JavaScript "window.__att=1" in current tab of front window' >/dev/null 2>&1; }
# End of a run: how many of the open tabs lost their marker (macOS dropped them to free RAM)
count_dropped_tabs() {
  osascript <<'OSA' 2>/dev/null
tell application "Safari"
  set d to 0
  repeat with t in tabs of front window
    try
      set r to do JavaScript "window.__att?'1':'0'" in t
      if r is not "1" then set d to d + 1
    on error
      set d to d + 1
    end try
  end repeat
  return d
end tell
OSA
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

RUNS=${RUNS:-3}   # Nov 21: 3 climbs by default; run 1 is a warm-up (first launch of apps), runs 2-3 averaged
WARMUP=${WARMUP:-1}; (( RUNS < 2 )) && WARMUP=0   # WARMUP=0 counts every run; RUNS=1 = one counted run
sc() { local v=$1; (( v <= 0 )) && { print 0; return; }; local s=$(( INSTANT_MS * 1000 / v )); (( s > 1000 )) && s=1000; print $s; }
print "stage_tabs,item,ms,ok,swap_used,memory_free,run,pressure,compressed,tab_reloaded" > "$CSV"
MEMLOG="$OUTDIR/responsiveness_memory_$STAMP.txt"; MEMTMP="${TMPDIR:-/tmp}/att-resp-mem.$$"
trap 'mem_sampler_stop; att_watch_stop; att_resume_bg; att_sync_results; att_upload_results' EXIT
trap 'mem_sampler_stop; att_watch_stop; att_resume_bg; att_sync_results; att_upload_results; exit 130' INT TERM HUP
att_watch_start "$BGLOG" "Safari|WebKit|Calculator|Chess|Dictionary|Font Book|Activity Monitor|TV|GarageBand|osascript|System Events|memory_pressure"
typeset -a R_LOADED R_LIGHT R_SCORE R_AVG0 R_AVG80 R_WORST80 R_SLOWER R_SWAP R_LINES R_DROP R_PRL R_PROBES R_PEAKP R_PEAKSW R_PEAKCOMP R_RELAUNCH
typeset -A APID
noanswer=0

for (( run=1; run<=RUNS; run++ )); do
  print "\n################ RUN $run of $RUNS$( (( run == 1 && WARMUP )) && print ' (warm-up, not counted)') ################"
  if (( run > 1 )); then
    print "Resetting between runs: quit Safari + test apps, then cooldown again."
    close_test_apps
    sleep 10; att_cooldown --again
  fi
  # Open the test apps and a fresh Safari window
  for a in $APPS; do open -a "$a" 2>/dev/null; sleep 2; done
  osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1; sleep 3
  osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1; sleep 1
  osascript -e 'tell application "Safari" to make new document with properties {URL:"https://www.apple.com"}' >/dev/null 2>&1
  print "Settling for 60 seconds..."; sleep 60
  mark_tab
  for a in $APPS "Safari"; do APID[$a]=$(pgrep -xn "$a"); done
  mem_sampler_start "$MEMTMP"
  prl=0; probes=0

  typeset -a stage_avg stage_worst; stage_avg=(); stage_worst=()
  all_total=0; all_count=0; opened=1   # the apple.com tab is site 1
  for target in $STAGES; do
    if (( target > 0 )); then
      print "\nOpening tabs up to ${target}..."
      while (( opened < target )); do (( opened++ )); open_tab "${SITES[$opened]}"; done
      sleep 10
    fi
    read swap free plev comp <<< "$(mem_vals)"
    print "\n== run $run, ${target} tabs open (pressure ${plev}, swap ${swap}, compressed ${comp}, free ${free}) =="
    st_total=0; st_count=0; st_worst=0
    for a in $APPS "Safari"; do
      read ms rc <<< "$(probe_app "$a")"
      printf "  %-16s %6s ms%s\n" "$a" $ms "$([[ $rc == 0 ]] || print '  (no answer, not scored)')"
      print "${target},\"${a}\",${ms},$([[ $rc == 0 ]] && print yes || print no),${swap},${free},${run},${plev},${comp}," >> "$CSV"
      if [[ $rc == 0 ]]; then (( st_total += ms, st_count++ )); (( ms > st_worst )) && st_worst=$ms; else (( noanswer++ )); fi
      sleep 1
    done
    if (( opened >= 5 )); then
      for n in 2 $(( opened / 2 )) $(( opened - 1 )); do
        read ms rc rl <<< "$(probe_tab $n)"
        (( probes++ )); (( rc == 0 && rl == 1 )) && (( prl++ ))
        printf "  %-16s %6s ms%s%s\n" "old tab #${n}" $ms "$([[ $rc == 0 ]] || print '  (no answer, not scored)')" "$( (( rc == 0 && rl == 1 )) && print '  (had to RELOAD)')"
        print "${target},\"tab ${n}\",${ms},$([[ $rc == 0 ]] && print yes || print no),${swap},${free},${run},${plev},${comp},$( (( rc == 0 && rl == 1 )) && print yes || print no)" >> "$CSV"
        if [[ $rc == 0 ]]; then (( st_total += ms, st_count++ )); (( ms > st_worst )) && st_worst=$ms; else (( noanswer++ )); fi
        sleep 1
      done
    fi
    if (( st_count > 0 )); then avg=$(( st_total / st_count )); else avg=0; fi
    st_checks=$(( ${#APPS} + 1 + (opened >= 5 ? 3 : 0) ))
    (( st_count * 2 < st_checks )) && { print "  !! most checks didn't answer at ${target} tabs: run $run not counted"; avg=0; }
    stage_avg+=($avg); stage_worst+=($st_worst)
    (( all_total += st_total, all_count += st_count ))
    print "  -> average ${avg} ms, worst ${st_worst} ms"
  done
  # Memory extras for this run
  mem_sampler_stop
  drop=$(count_dropped_tabs); drop=${drop:-0}
  relaunched=()
  for a in $APPS "Safari"; do now=$(pgrep -xn "$a"); [[ -n ${APID[$a]} && $now != ${APID[$a]} ]] && relaunched+=("$a"); done
  read pk_lvl pk_sw pk_comp <<< "$(awk 'BEGIN{l=0;s=0;c=0} {if($1>l)l=$1; if($2>s)s=$2; if($3>c)c=$3} END{print l, s, c}' "$MEMTMP")"
  { print "# run $run (pressure level 1/2/4, swap MB, compressor pages)"; cat "$MEMTMP"; } >> "$MEMLOG" 2>/dev/null
  pk_comp_gb=$(awk -v c=${pk_comp:-0} -v p=$PAGE 'BEGIN{printf "%.1f", c*p/1e9}')
  print "  memory: peak pressure $(plev_name $pk_lvl), peak swap ${pk_sw:-0} MB, peak compressed ${pk_comp_gb} GB, tabs dropped ${drop} of ${opened}, old tabs reloaded ${prl} of ${probes}, apps relaunched ${#relaunched}"
  if (( all_count == 0 || stage_avg[1] == 0 || stage_avg[-1] == 0 )); then
    print "!! Run $run had no usable timings; not counted."; continue
  fi
  read swap free <<< "$(mem_vals)"
  if (( run == 1 && WARMUP )); then
    R_LINES+=("$(printf 'Run 1: warm-up, not counted (loaded %d, 80 tabs %d ms)' $(sc ${stage_avg[-1]}) ${stage_avg[-1]})")
    continue
  fi
  R_DROP+=($drop); R_PRL+=($prl); R_PROBES+=($probes); R_PEAKP+=(${pk_lvl:-0}); R_PEAKSW+=(${pk_sw:-0}); R_PEAKCOMP+=($pk_comp_gb); R_RELAUNCH+=(${#relaunched})
  R_LOADED+=($(sc ${stage_avg[-1]})); R_LIGHT+=($(sc ${stage_avg[1]})); R_SCORE+=($(sc $(( all_total / all_count ))))
  R_AVG0+=(${stage_avg[1]}); R_AVG80+=(${stage_avg[-1]}); R_WORST80+=(${stage_worst[-1]}); R_SWAP+=($swap)
  R_SLOWER+=($(( (stage_avg[-1] - stage_avg[1]) * 100 / stage_avg[1] )))
  R_LINES+=("$(printf 'Run %d: loaded %4d  light %4d | 0 tabs %4d ms, 80 tabs %5d ms, worst %5d ms' $run ${R_LOADED[-1]} ${R_LIGHT[-1]} ${stage_avg[1]} ${stage_avg[-1]} ${stage_worst[-1]})")
  R_LINES+=("$(printf '       memory: %s peak, swap %d MB, compressed %s GB, %d tabs dropped, %d/%d old tabs reloaded, %d apps relaunched' $(plev_name $pk_lvl) ${pk_sw:-0} $pk_comp_gb $drop $prl $probes ${#relaunched})")
done

att_watch_stop
BGLINE=$(att_watch_report "$BGLOG")
close_test_apps

# --- Score + photo card (average of the good runs) ---
n=${#R_LOADED}
if (( n == 0 )); then
  { att_card_start "Responsiveness (app switching, 0 to 80 tabs)"
    print "!! No usable timings (apps didn't answer). Check Accessibility for Terminal, restart, run again."
    att_card_end; } | tee "$TXT"
  exit 1
fi
mean() { local s=0 v; for v in "$@"; do (( s += v )); done; print $(( s / $# )); }
loaded=$(mean $R_LOADED); light=$(mean $R_LIGHT); score=$(mean $R_SCORE)
avg0=$(mean $R_AVG0); avg80=$(mean $R_AVG80); worst80=${${(On)R_WORST80}[1]}; slower=$(mean $R_SLOWER)
spread=0; (( n > 1 && loaded > 0 )) && spread=$(( (${${(On)R_LOADED}[1]} - ${${(on)R_LOADED}[1]}) * 100 / loaded ))
swap=${R_SWAP[-1]}
dropped=$(mean $R_DROP); prl_t=0; pr_t=0; for v in $R_PRL; do (( prl_t += v )); done; for v in $R_PROBES; do (( pr_t += v )); done
peakp=$(plev_name ${${(On)R_PEAKP}[1]}); peaksw=${${(On)R_PEAKSW}[1]}; peakcomp=${${(On)R_PEAKCOMP}[1]}
relaunch_t=0; for v in $R_RELAUNCH; do (( relaunch_t += v )); done

{ att_card_start "Responsiveness (app switching, 0 to 80 tabs), ${n} run(s) averaged$( (( WARMUP )) && print ' after a warm-up')"
  print "LOADED SCORE (80 tabs): ${loaded}   <- headline (1000 = instant, higher is better)"
  print "Light score (0 tabs):   ${light}"
  print "Overall score:          ${score}"
  print "80 tabs vs none:        ${slower}% slower to switch"
  print "Worst single wait (80): ${worst80} ms"
  print "Memory pressure peak:   ${peakp}   (Activity Monitor's graph color)"
  print "Tabs macOS dropped:     ${dropped} of 80 (avg per run)   Old tabs that reloaded: ${prl_t} of ${pr_t}"
  print "Peak swap / compressed: ${peaksw} MB / ${peakcomp} GB   Apps relaunched: ${relaunch_t}"
  (( n > 1 )) && print "Run-to-run spread:      ${spread}%$( (( spread > 15 )) && print '   !! over 15%: run it again')"
  print -r -- "---------------------------------------------------------------"
  for l in $R_LINES; do print -r -- "$l"; done
  print -r -- "---------------------------------------------------------------"
  (( noanswer )) && print "No answer (not scored): ${noanswer} checks"
  (( ${#MISSING} )) && print "Apps not installed: ${(j:, :)MISSING}"
  print -r -- "$BGLINE"
  print "SHEET: Responsiveness loaded / light / overall  ->  ${loaded} / ${light} / ${score}"
  print "SHEET: Avg ms 0 tabs / 80 tabs / worst 80  ->  ${avg0} / ${avg80} / ${worst80}"
  print "SHEET: Swap end / slower % / spread  ->  ${swap} / ${slower}% / ${spread}%"
  print "SHEET: Pressure peak / tabs dropped / old tabs reloaded  ->  ${peakp} / ${dropped} / ${prl_t} of ${pr_t}"
  print "SHEET: Peak swap MB / peak compressed GB / apps relaunched  ->  ${peaksw} / ${peakcomp} / ${relaunch_t}"
  print "Saved: Results/$MAC/Memory/${TXT:t} (+ .csv)"
  att_card_end; } | tee "$TXT"

print "runs,${n},loaded_score,${loaded},light_score,${light},score,${score},slower_pct,${slower},avg0,${avg0},avg80,${avg80},worst80,${worst80},spread_pct,${spread},swap_end,${swap},pressure_peak,${peakp},tabs_dropped,${dropped},old_tabs_reloaded,${prl_t}/${pr_t},peak_swap_mb,${peaksw},peak_compressed_gb,${peakcomp},apps_relaunched,${relaunch_t}" >> "$CSV"

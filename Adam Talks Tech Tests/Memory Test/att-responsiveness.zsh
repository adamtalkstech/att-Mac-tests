#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
whence att_pause_bg >/dev/null && att_pause_bg   # pause Photos/Spotlight/Siri scanning for the test (wakes back up at the end)
# ATT Responsiveness Score, trial v0.1 (Nov 5 2026; results path Nov 20)
# One score for "how snappy does this Mac stay as you pile on a normal day?"
#
# What it does (about 10 minutes, hands off):
#   1. Quits your open apps (asks first), opens Safari and a few built-in Apple apps
#      (Calculator, Chess, Dictionary, Font Book, Activity Monitor: nothing personal or location-based on screen).
#   2. Opens the same 80 websites in 4 steps: 0, 20, 40, 60, 80 tabs.
#   3. At each step it times how long each app takes to be ready when you switch
#      to it, and how long old Safari tabs take to come back.
#   4. Gives one score. Higher = snappier. Also logs swap and memory pressure.
#
# Before running (one time per Mac):
#   - System Settings > Privacy & Security > Accessibility: turn on Terminal
#   - Safari > Settings > Advanced: "Show features for web developers",
#     then Settings > Developer: "Allow JavaScript from Apple Events"
# Run:  zsh ~/Downloads/att-responsiveness.zsh
# Don't touch the Mac while it runs. Results save to Results/<Mac>/Memory in the test folder (Desktop if run elsewhere).

zmodload zsh/datetime
INSTANT_MS=250          # a switch this fast counts as instant (score 1000)
APPS=("Calculator" "Chess" "Dictionary" "Font Book" "Activity Monitor" "TV" "GarageBand")
KEEP=("Terminal" "Finder" "Claude" "Screen Sharing")
WAIT_MAX=15

HOST=$(scutil --get ComputerName 2>/dev/null | tr ' ' '-')
STAMP=$(date +%Y%m%d-%H%M%S)
# Results: Adam Talks Tech Tests/Results/<Mac>/Memory when run from the test folder, else the Desktop
_HERE=${0:A:h}; _ROOT=$_HERE
while [[ $_ROOT != / && ${_ROOT:t} != "Adam Talks Tech Tests" ]]; do _ROOT=${_ROOT:h}; done
if [[ $_ROOT == / ]]; then _OUTDIR=~/Desktop; else _OUTDIR="$_ROOT/Results/$(scutil --get ComputerName 2>/dev/null)/Memory"; mkdir -p "$_OUTDIR"; fi
OUT="$_OUTDIR/ATT-responsiveness-${HOST}-${STAMP}.csv"

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
  echo "${swap} ${free}"
}

ms_since() { printf '%.0f' $(( (EPOCHREALTIME - $1) * 1000 )) }

probe_app() {
  # bring app to front, then ask it for its front window; a busy app can't answer until ready
  local app="$1" t0 rc
  t0=$EPOCHREALTIME
  osascript -e "tell application \"System Events\" to set frontmost of process \"$app\" to true" >/dev/null 2>&1
  osascript -e "tell application \"System Events\" to tell process \"$app\" to get name of front window" >/dev/null 2>&1
  rc=$?
  echo "$(ms_since $t0) $rc"
}

probe_tab() {
  # switch Safari to tab N and time until the page answers
  local n="$1" t0 r
  t0=$EPOCHREALTIME
  r=$(osascript - "$n" <<'EOF' 2>/dev/null
on run argv
  tell application "Safari"
    activate
    set w to front window
    set current tab of w to tab ((item 1 of argv) as integer) of w
    return do JavaScript "document.readyState" in current tab of w
  end tell
end run
EOF
)
  echo "$(ms_since $t0) $([[ -n "$r" ]] && echo 0 || echo 1)"
}

open_tab() {
osascript - "$1" <<'EOF' >/dev/null 2>&1
on run argv
  tell application "Safari"
    tell front window to set current tab to (make new tab with properties {URL:(item 1 of argv)})
  end tell
end run
EOF
  local s
  for (( s=0; s<WAIT_MAX*2; s++ )); do
    sleep 0.5
    [[ "$(osascript -e 'tell application "Safari" to do JavaScript "document.readyState" in current tab of front window' 2>/dev/null)" == "complete" ]] && break
  done
}

echo "ATT Responsiveness Score (trial) on ${HOST}"
echo "Model: $(sysctl -n hw.model)   RAM: $(( $(sysctl -n hw.memsize) / 1073741824 ))GB   macOS: $(sw_vers -productVersion)"
echo

# --- Safari setting check ---
osascript -e 'tell application "Safari"' -e 'activate' -e 'make new document with properties {URL:"https://en.wikipedia.org/wiki/Apple_Inc."}' -e 'end tell' >/dev/null 2>&1
sleep 6
t=$(osascript -e 'tell application "Safari" to do JavaScript "(1+1).toString()" in current tab of front window' 2>&1)
if [[ "$t" != "2" && "$t" != "2.0" ]]; then
  echo "Safari won't run the check. Turn on Settings > Developer > Allow JavaScript from Apple Events, quit Safari (Cmd+Q), then run again."
  echo "Safari said: $t"; exit 1
fi

# --- Clean start ---
echo "This will QUIT every open app except: ${(j:, :)KEEP}"
echo "Save any open work first. Press Return to continue, or Control-C to cancel."
read -r
# Nov 21: quit by app ID (works when the app's name differs from its process name, e.g. the
# Creator Studio Final Cut), using the same routine as every other test.
if whence att_quit_apps >/dev/null; then
  ATT_KEEP="${(j:,:)KEEP}" att_quit_apps
else
  for id in ${(f)"$(osascript -e 'tell application "System Events" to get bundle identifier of every process whose background only is false' | tr ',' '\n' | sed 's/^ *//')"}; do
    [[ -z $id || $id == "missing value" || $id == com.apple.Terminal || $id == com.apple.finder || $id == com.apple.Safari ]] && continue
    osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1
  done
fi
sleep 5
left=()
for a in ${(f)"$(osascript -e 'tell application "System Events" to get name of every process whose background only is false' | tr ',' '\n' | sed 's/^ *//')"}; do
  (( ${KEEP[(Ie)$a]} )) || left+=("$a")
done
if (( ${#left} > 0 )); then
  echo "Still open: ${(j:, :)left}. Quit those (Cmd-Q), then press Return."; read -r
fi

# --- Quit background helper apps (menu bar / sync apps that keep running with no window) ---
HELPERS=("Creative Cloud" "Adobe Creative Cloud" "Dropbox" "Google Drive" "OneDrive" "Backblaze" "Logi Options+" "Docker Desktop" "Docker" "Spotify" "Discord" "Slack" "Zoom" "zoom.us" "Microsoft Teams" "MSTeams" "Microsoft AutoUpdate" "Bartender 5" "CleanMyMac" "1Password" "Grammarly Desktop" "Elgato Stream Deck" "Stream Deck" "RODE Central" "Loupedeck")
echo "Quitting background helper apps..."
for h in "${HELPERS[@]}"; do
  if [[ "$(osascript -e "application \"$h\" is running" 2>/dev/null)" == "true" ]]; then
    echo "  quitting ${h}"
    osascript -e "tell application \"$h\" to quit" >/dev/null 2>&1
  fi
done
tmutil stopbackup >/dev/null 2>&1 && echo "  Time Machine backup stopped (if one was running)"

# --- Wait until the Mac is quiet (Spotlight, iCloud, photo analysis etc. finish) ---
# Waits until all background activity together uses under 25% of one CPU core, for 30 seconds straight.
echo "Waiting for background activity to calm down (up to 10 minutes)..."
quiet=0; waited=0
while (( quiet < 30 && waited < 600 )); do
  busy=$(ps -A -o %cpu=,comm= | awk '$2 !~ /(ps|awk|zsh|osascript|sleep)$/ {s+=$1} END {printf "%d", s}')
  if (( busy < 25 )); then (( quiet += 5 )); else quiet=0; fi
  sleep 5; (( waited += 5 ))
done
echo "Busiest background processes right now:"
ps -A -o %cpu=,comm= | sort -rn | head -5 | awk '{printf "    %5s%%  %s\n", $1, $2}'
if (( quiet < 30 )); then
  echo "  Note: the Mac never got fully quiet in 10 minutes. The list above is what's busy. Results may run a bit slow."
  BG_NOTE="never fully quiet"
else
  echo "  Quiet. Starting."
  BG_NOTE="quiet"
fi

# --- Open the test apps and a fresh Safari window ---
for a in "${APPS[@]}"; do open -a "$a" 2>/dev/null; sleep 2; done
osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1; sleep 3
osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1; sleep 1
osascript -e 'tell application "Safari" to make new document with properties {URL:"https://www.apple.com"}' >/dev/null 2>&1
echo "Settling for 60 seconds..."; sleep 60

echo "stage_tabs,item,ms,ok,swap_used,memory_free" > "$OUT"
typeset -a stage_avg stage_worst
all_total=0; all_count=0
opened=1   # the apple.com tab counts as site 1
STAGES=(0 20 40 60 80)

for target in "${STAGES[@]}"; do
  if (( target > 0 )); then
    echo
    echo "Opening tabs up to ${target}..."
    while (( opened < target )); do
      (( opened++ ))
      open_tab "${SITES[$opened]}"
    done
    sleep 10
  fi
  read swap free <<< "$(mem_vals)"
  echo
  echo "== ${target} tabs open (swap ${swap}, memory free ${free}) =="
  st_total=0; st_count=0; st_worst=0
  for a in "${APPS[@]}" "Safari"; do
    read ms rc <<< "$(probe_app "$a")"
    printf "  %-16s %6s ms%s\n" "$a" $ms "$([[ $rc == 0 ]] || echo '  (no answer, not scored)')"
    echo "${target},\"${a}\",${ms},$([[ $rc == 0 ]] && echo yes || echo no),${swap},${free}" >> "$OUT"
    if [[ $rc == 0 ]]; then (( st_total += ms, st_count++ )); (( ms > st_worst )) && st_worst=$ms; fi
    sleep 1
  done
  if (( opened >= 5 )); then
    for n in 2 $(( opened / 2 )) $(( opened - 1 )); do
      read ms rc <<< "$(probe_tab $n)"
      printf "  %-16s %6s ms%s\n" "old tab #${n}" $ms "$([[ $rc == 0 ]] || echo '  (no answer, not scored)')"
      echo "${target},\"tab ${n}\",${ms},$([[ $rc == 0 ]] && echo yes || echo no),${swap},${free}" >> "$OUT"
      if [[ $rc == 0 ]]; then (( st_total += ms, st_count++ )); (( ms > st_worst )) && st_worst=$ms; fi
      sleep 1
    done
  fi
  if (( st_count > 0 )); then
    avg=$(( st_total / st_count ))
    stage_avg+=($avg); stage_worst+=($st_worst)
    (( all_total += st_total, all_count += st_count ))
    echo "  -> average ${avg} ms, worst ${st_worst} ms"
  fi
done

echo
att_card_start "Responsiveness (app switching with 0 to 80 tabs)"
overall=$(( all_total / all_count ))
score=$(( INSTANT_MS * 1000 / overall ))
(( score > 1000 )) && score=1000
light=$(( INSTANT_MS * 1000 / stage_avg[1] )); (( light > 1000 )) && light=1000
loaded=$(( INSTANT_MS * 1000 / stage_avg[-1] )); (( loaded > 1000 )) && loaded=1000
slower=$(( (stage_avg[-1] - stage_avg[1]) * 100 / stage_avg[1] ))
read swap free <<< "$(mem_vals)"
echo "LOADED SCORE (80 tabs): ${loaded}   <- the headline number"
echo "Light score (0 tabs):   ${light}"
echo "Overall score:          ${score}   (1000 = instant every time, higher is better)"
echo "With 80 tabs open, switching took ${slower}% longer than with none."
echo "Average wait when switching:  ${overall} ms"
echo "Average with 0 tabs:          ${stage_avg[1]} ms"
echo "Average with 80 tabs:         ${stage_avg[-1]} ms"
echo "Worst single wait (80 tabs):  ${stage_worst[-1]} ms"
echo "Swap used at the end:         ${swap}   Memory free: ${free}"
echo "Background at start:          ${BG_NOTE}"
echo "Saved: ${OUT:t}"
att_card_end
echo "loaded_score,${loaded},light_score,${light},slower_pct,${slower},score,${score},avg_ms,${overall},avg0,${stage_avg[1]},avg80,${stage_avg[-1]},worst80,${stage_worst[-1]},swap_end,${swap},free_end,${free}" >> "$OUT"

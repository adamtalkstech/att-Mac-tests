#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# ATT tab test, trial v0.1 (Nov 5 2026; results path Nov 20)
# How many Safari tabs can this Mac keep open before Safari has to reload one?
# Opens the same 80 sites one tab at a time, marks each tab once it has loaded,
# and after every new tab checks whether any earlier tab lost its mark
# (meaning Safari threw it out to save memory and reloaded it).
#
# Before running (one time per Mac):
#   Safari > Settings > Advanced > turn on "Show features for web developers"
#   Develop menu > "Allow JavaScript from Apple Events"
# Then: fresh restart, quit everything except Terminal, Wi-Fi on.
# Run:  zsh ~/Downloads/att-tabtest.zsh
# Results save to Results/<Mac>/Memory in the test folder (Desktop if run elsewhere). Don't touch the Mac while it runs (about 15 min).

zmodload zsh/datetime
STOP_AFTER=3        # keep going until this many tabs have reloaded (first one is the headline)
WAIT_MAX=15         # max seconds to wait for a tab to finish loading
SETTLE=2            # extra seconds after load before marking

HOST=$(scutil --get ComputerName 2>/dev/null | tr ' ' '-')
STAMP=$(date +%Y%m%d-%H%M%S)
# Results: Adam Talks Tech Tests/Results/<Mac>/Memory when run from the test folder, else the Desktop
_HERE=${0:A:h}; _ROOT=$_HERE
while [[ $_ROOT != / && ${_ROOT:t} != "Adam Talks Tech Tests" ]]; do _ROOT=${_ROOT:h}; done
if [[ $_ROOT == / ]]; then _OUTDIR=~/Desktop; else _OUTDIR="$_ROOT/Results/$(scutil --get ComputerName 2>/dev/null)/Memory"; mkdir -p "$_OUTDIR"; fi
OUT="$_OUTDIR/ATT-tabtest-${HOST}-${STAMP}.csv"

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

open_tab() {
osascript - "$1" <<'EOF' >/dev/null 2>&1
on run argv
  tell application "Safari"
    activate
    if (count of windows) = 0 then make new document
    tell front window to set current tab to (make new tab with properties {URL:(item 1 of argv)})
  end tell
end run
EOF
}

tab_ready() {
osascript <<'EOF' 2>/dev/null
tell application "Safari" to do JavaScript "document.readyState" in current tab of front window
EOF
}

mark_tab() {
osascript <<'EOF' 2>/dev/null
tell application "Safari" to do JavaScript "window.__att=1;'ok'" in current tab of front window
EOF
}

check_tabs() {
# $1 = first tab number opened by this script. Prints: reloadedCount|totalTabs|tab numbers that reloaded
osascript - "$1" <<'EOF' 2>/dev/null
on run argv
tell application "Safari"
  set w to front window
  set n to count of tabs of w
  set bad to {}
  repeat with i from ((item 1 of argv) as integer) to n
    try
      set r to do JavaScript "window.__att===1?'k':'r'" in tab i of w
      if r is not "k" then set end of bad to i
    on error
      set end of bad to i
    end try
  end repeat
  set AppleScript's text item delimiters to ","
  return ((count of bad) as text) & "|" & (n as text) & "|" & (bad as text)
end tell
end run
EOF
}

echo "ATT tab test (trial) on ${HOST}"
echo "Sites in list: ${#SITES}"

# Check the Safari setting before quitting anything
# Open a real page in a new window and make sure Safari will run the check on it
osascript -e 'tell application "Safari"' -e 'activate' -e 'make new document with properties {URL:"https://en.wikipedia.org/wiki/Apple_Inc."}' -e 'end tell' >/dev/null 2>&1
sleep 6
test_js=$(osascript -e 'tell application "Safari" to do JavaScript "(1+1).toString()" in current tab of front window' 2>&1)
if [[ "$test_js" != "2" && "$test_js" != "2.0" ]]; then
  echo "Safari won't run the check."
  echo "Safari said: $test_js"
  echo "If it mentions 'Allow JavaScript from Apple Events': quit Safari completely (Cmd+Q), reopen it, check the setting is still on, then run this again."
  exit 1
fi
osascript -e 'tell application "Safari" to close front window' >/dev/null 2>&1
echo "Safari check: OK"

# --- Quit every open app first, so every Mac starts from the same clean slate ---
KEEP=("Terminal" "Finder" "Claude" "Screen Sharing")
echo
echo "This will QUIT every open app except: ${(j:, :)KEEP}"
echo "Save any open work first. Press Return to continue, or Control-C to cancel."
read -r
open_apps=$(osascript -e 'tell application "System Events" to get name of every process whose background only is false')
for a in ${(s:, :)open_apps}; do
  (( ${KEEP[(Ie)$a]} )) && continue
  echo "  quitting ${a}"
  osascript -e "tell application \"${a}\" to quit" >/dev/null 2>&1 &
done
wait
sleep 5
still=$(osascript -e 'tell application "System Events" to get name of every process whose background only is false')
left=()
for a in ${(s:, :)still}; do (( ${KEEP[(Ie)$a]} )) || left+=("$a"); done
if (( ${#left} > 0 )); then
  echo "Still open (probably asking to save something): ${(j:, :)left}"
  echo "Close those by hand, then press Return."
  read -r
fi
# Fresh Safari: open it, close any restored windows, start with one empty window
osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1
sleep 3
osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1
sleep 1
osascript -e 'tell application "Safari" to make new document' >/dev/null 2>&1
echo "Waiting 60 seconds for things to settle..."
sleep 60
n0=$(osascript -e 'tell application "Safari" to count of tabs of front window' 2>/dev/null)
FIRST_TAB=$(( ${n0:-1} + 1 ))   # tabs already open before the test are ignored
read swap0 free0 <<< "$(mem_vals)"
echo "Memory at start: swap ${swap0}, memory free ${free0}"
echo
echo "tab,url,load_seconds,swap_used,memory_free,tabs_reloaded,reloaded_tab_numbers" > "$OUT"

first_wall=""
first_url=""
reloaded_total=0
i=0
for url in "${SITES[@]}"; do
  (( i++ ))
  t0=$EPOCHREALTIME
  open_tab "$url"
  # wait for it to finish loading
  for (( s=0; s<WAIT_MAX*2; s++ )); do
    sleep 0.5
    [[ "$(tab_ready)" == "complete" ]] && break
  done
  sleep $SETTLE
  load_s=$(printf '%.1f' $(( EPOCHREALTIME - t0 )))
  mark_tab >/dev/null
  res=$(check_tabs $FIRST_TAB)
  bad_count=${res%%|*}
  rest=${res#*|}; total=${rest%%|*}; bad_list=${rest#*|}
  read swap free <<< "$(mem_vals)"
  echo "${i},${url},${load_s},${swap},${free},${bad_count:-0},\"${bad_list}\"" >> "$OUT"
  printf "  tab %2d  load %5ss  swap %10s  free %4s  reloaded %s\n" $i $load_s $swap $free "${bad_count:-0}"
  if (( ${bad_count:-0} > 0 )) && [[ -z "$first_wall" ]]; then
    first_wall=$i
    first_num=${bad_list%%,*}
    site_idx=$(( first_num - FIRST_TAB + 1 ))
    first_url=${SITES[$site_idx]}
    echo "  >> First reload at ${i} tabs open (site #${site_idx}: ${first_url})"
  fi
  if (( ${bad_count:-0} >= STOP_AFTER )); then
    echo "  >> ${bad_count} tabs reloaded, stopping."
    break
  fi
done

att_card_start "Safari tab test (tabs open before the first reload)"
if [[ -n "$first_wall" ]]; then
  echo "RESULT: first tab reloaded with ${first_wall} tabs open."
  echo "        Tab that reloaded first: ${first_url}"
  echo "        (If the same site reloads first on every Mac, even early, it may refresh itself. Tell Claude and it gets swapped out.)"
else
  echo "RESULT: no tabs reloaded with all ${i} tabs open (write ${i}+)."
fi
read swap1 free1 <<< "$(mem_vals)"
echo "Memory at end: swap ${swap1}, memory free ${free1}"
echo "Saved: $OUT"
att_card_end

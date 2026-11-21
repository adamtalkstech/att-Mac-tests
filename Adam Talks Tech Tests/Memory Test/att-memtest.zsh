#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
whence att_pause_bg >/dev/null && att_pause_bg   # pause Photos/Spotlight/Siri scanning for the test (wakes back up at the end)
# ATT memory test, trial v0.1 (Nov 5 2026; results path Nov 20)
# Times how long each open app takes to be ready again when you switch to it,
# counts Chrome tabs that got reloaded, and logs swap / memory pressure.
#
# Run:   zsh ~/Downloads/att-memtest.zsh        (3 rounds)
#        zsh ~/Downloads/att-memtest.zsh 5      (5 rounds)
# Open the apps you want tested BEFORE running it. Results save to Results/<Mac>/Memory in the test folder (Desktop if run elsewhere).

zmodload zsh/datetime
ROUNDS=${1:-3}
HOST=$(scutil --get ComputerName 2>/dev/null | tr ' ' '-')
STAMP=$(date +%Y%m%d-%H%M%S)
# Results: Adam Talks Tech Tests/Results/<Mac>/Memory when run from the test folder, else the Desktop
_HERE=${0:A:h}; _ROOT=$_HERE
while [[ $_ROOT != / && ${_ROOT:t} != "Adam Talks Tech Tests" ]]; do _ROOT=${_ROOT:h}; done
if [[ $_ROOT == / ]]; then _OUTDIR=~/Desktop; else _OUTDIR="$_ROOT/Results/$(scutil --get ComputerName 2>/dev/null)/Memory"; mkdir -p "$_OUTDIR"; fi
OUT="$_OUTDIR/ATT-memtest-${HOST}-${STAMP}.csv"
SKIP=("Terminal" "Finder" "iTerm2" "Activity Monitor" "Claude")

mem_line() {
  local swap pressure pageouts comp
  swap=$(sysctl -n vm.swapusage | awk '{print $6}')
  pressure=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/{print $2}')
  pageouts=$(vm_stat | awk '/Pageouts/{gsub(/\./,"",$2); print $2}')
  comp=$(vm_stat | awk '/occupied by compressor/{gsub(/\./,"",$5); printf "%.1f", $5*16384/1073741824}')
  echo "swap_used=${swap} memory_free=${pressure} compressed_GB=${comp} pageouts=${pageouts}"
}

probe() {
  # Bring the app to the front, then ask it for its front window name.
  # A busy (beachballing) app can't answer until it's ready, so the time to
  # answer is how long you'd wait after clicking on it.
  local app="$1" t0 t1 rc
  t0=$EPOCHREALTIME
  osascript -e "tell application \"System Events\" to set frontmost of process \"$app\" to true" >/dev/null 2>&1
  osascript -e "tell application \"System Events\" to tell process \"$app\" to get name of front window" >/dev/null 2>&1
  rc=$?
  t1=$EPOCHREALTIME
  printf '%.0f %s' $(( (t1 - t0) * 1000 )) $rc
}

chrome_running() {
  [[ "$(osascript -e 'application "Google Chrome" is running' 2>/dev/null)" == "true" ]]
}

chrome_mark() {
osascript <<'EOF' 2>/dev/null
tell application "Google Chrome"
  set n to 0
  repeat with w in windows
    repeat with t in tabs of w
      try
        execute t javascript "window.__att=1;1"
        set n to n + 1
      end try
    end repeat
  end repeat
  return n
end tell
EOF
}

chrome_check() {
osascript <<'EOF' 2>/dev/null
tell application "Google Chrome"
  set total to 0
  set reloaded to 0
  repeat with w in windows
    repeat with t in tabs of w
      set total to total + 1
      try
        set r to execute t javascript "window.__att===1?'kept':'reloaded'"
        if r is not "kept" then set reloaded to reloaded + 1
      on error
        set reloaded to reloaded + 1
      end try
    end repeat
  end repeat
  return (reloaded as text) & " of " & (total as text)
end tell
EOF
}

echo "ATT memory test (trial) on ${HOST}"
echo "Rounds: ${ROUNDS}"
echo

# Apps to test = the regular apps open right now
apps_raw=$(osascript -e 'tell application "System Events" to get name of every process whose background only is false')
apps=()
for a in ${(s:, :)apps_raw}; do
  (( ${SKIP[(Ie)$a]} )) || apps+=("$a")
done
if (( ${#apps} == 0 )); then
  echo "No apps open to test. Open your apps first, then run this again."
  exit 1
fi
echo "Testing: ${(j:, :)apps}"

# Mark Chrome tabs so we can tell later which ones Chrome threw out and reloaded
marked=""
if chrome_running; then
  marked=$(chrome_mark)
  if [[ -z "$marked" || "$marked" == "0" ]]; then
    echo "Chrome tabs: couldn't mark them. In Chrome turn on View > Developer > Allow JavaScript from Apple Events, then rerun."
  else
    echo "Chrome tabs marked: ${marked}"
  fi
fi

echo
echo "Memory at start: $(mem_line)"
echo

echo "round,app,ms_to_ready,ok" > "$OUT"
typeset -A total count fails
for (( r=1; r<=ROUNDS; r++ )); do
  for a in "${apps[@]}"; do
    read ms rc <<< "$(probe "$a")"
    echo "${r},\"${a}\",${ms},$([[ $rc == 0 ]] && echo yes || echo no)" >> "$OUT"
    if [[ $rc == 0 ]]; then
      total[$a]=$(( ${total[$a]:-0} + ms ))
      count[$a]=$(( ${count[$a]:-0} + 1 ))
    else
      fails[$a]=$(( ${fails[$a]:-0} + 1 ))
    fi
    printf "  round %d  %-28s %6s ms%s\n" $r "$a" $ms "$([[ $rc == 0 ]] || echo '  (no answer: no window open, or Accessibility not allowed)')"
    sleep 2
  done
done

echo
att_card_start "Memory test (time for each app to be ready again)"
echo "Average time to ready again:"
for a in "${apps[@]}"; do
  if (( ${count[$a]:-0} > 0 )); then
    printf "  %-28s %6d ms\n" "$a" $(( ${total[$a]} / ${count[$a]} ))
  else
    printf "  %-28s   n/a\n" "$a"
  fi
done

if [[ -n "$marked" && "$marked" != "0" ]]; then
  echo
  echo "Chrome tabs reloaded: $(chrome_check)"
fi

echo
echo "Memory at end: $(mem_line)"
echo
echo "Saved: $OUT"
att_card_end
echo "Note: each switch includes about 100 to 300 ms of the script's own overhead, so compare Macs to each other, not to zero."

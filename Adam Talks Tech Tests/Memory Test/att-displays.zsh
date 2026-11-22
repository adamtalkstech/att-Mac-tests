#!/bin/zsh
# =============================================================================
#  att-displays.zsh - how much memory each extra display costs (Run Order step 17f, v1 Nov 22 2026)
# =============================================================================
#  Hands-on, ~10 min. Restart first. It asks you to plug in displays one at a time; at each step it opens
#  the same few windows, waits a minute and measures the whole Mac plus WindowServer (what draws the screen).
#    zsh att-displays.zsh          steps: what's plugged in now, then +1, then +1 again
#    STEPS=2 zsh att-displays.zsh  only one extra display
#  Use your normal monitors at their normal resolution (the card lists each one).
# =============================================================================
HERE=${0:A:h}; ROOT=${HERE:h}
source "$ROOT/Tools/att-card.zsh"; source "$ROOT/Tools/att-appmem.zsh"
MAC=$(scutil --get ComputerName 2>/dev/null); OUT="$ROOT/Results/$MAC/Memory"; mkdir -p "$OUT"
ndisp() { system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Resolution:"; }
dlist() { system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/^        [^ ].*:$/ {n=$1; gsub(/^ +|:$/,"",n)} /Resolution:/ {print "    " n ": " $2}'; }
measure() {
  osascript -e 'tell application "Finder" to make new Finder window' >/dev/null 2>&1
  open -a Safari "https://www.apple.com/mac/" 2>/dev/null; sleep 60
  local u ws; u=$(att_mem_used | cut -d'|' -f1)
  ws=$(att_appmem_snap | awk -F'|' '/WindowServer/ {printf "%.2f", $2/1024}')
  osascript -e 'tell application "Safari" to quit' >/dev/null 2>&1
  REPLY="$u|${ws:-?}"
}
att_quit_apps
ROWS=(); LIST=""
for (( s = 1; s <= ${STEPS:-3}; s++ )); do
  if (( s > 1 )); then
    print ""; print ">>> Plug in ONE more display now (now: $(ndisp)). Wait until it shows a picture, then press Return."
    read -r; sleep 10
  fi
  n=$(ndisp); print "Measuring with $n display(s) (about a minute)..."
  measure; ROWS+=("$n|$REPLY"); LIST+="  $n display(s):\n$(dlist)\n"
done
F="$OUT/displays_$(date +%Y-%m-%d_%H-%M).txt"
{ att_card_start "RAM: what each display costs (Step 17f)"
  for r in $ROWS; do IFS='|' read n u ws <<< "$r"; print "  $n display(s): Mac uses $u GB | WindowServer $ws GB"; done
  print -n "$LIST"
  att_log "New Tests" "External displays: memory used" "$(for r in $ROWS; do IFS='|' read n u ws <<< "$r"; print -n "$n: $u GB (WS $ws)  "; done)"
  att_card_end; } | tee "$F"
whence att_upload_results >/dev/null && att_upload_results

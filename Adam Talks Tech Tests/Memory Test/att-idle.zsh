#!/bin/zsh
# =============================================================================
#  att-idle.zsh - how much memory macOS uses by itself (Run Order step 17e, v1 Nov 22 2026)
# =============================================================================
#  Run right after a restart (log in, open Terminal, run it). It quits anything that opened at login,
#  waits 5 minutes with nothing open, then measures 5 times, 30 s apart, and keeps the middle one.
#  Also prints the GPU memory cap (the most RAM the GPU is allowed to use: why big AI models don't fit).
#    zsh att-idle.zsh on     Apple Intelligence ON  (System Settings > Apple Intelligence & Siri)
#    zsh att-idle.zsh off    Apple Intelligence OFF (turn it off, restart, then run this)
#  ~8 min, hands-off. Auto-logs. Turn Apple Intelligence back on after the "off" run.
# =============================================================================
HERE=${0:A:h}; ROOT=${HERE:h}
source "$ROOT/Tools/att-card.zsh"; source "$ROOT/Tools/att-appmem.zsh"
AI=${1:l}; [[ $AI == on || $AI == off ]] || { print 'Say whether Apple Intelligence is on or off:  zsh att-idle.zsh on   (or off)'; exit 1; }
MAC=$(scutil --get ComputerName 2>/dev/null); OUT="$ROOT/Results/$MAC/Memory"; mkdir -p "$OUT"
UP=$(( EPOCHSECONDS - $(sysctl -n kern.boottime | awk -F'[ ,]' '{print $4}') ))
att_quit_apps
WAIT=${WAIT:-300}; print "Waiting $(( WAIT / 60 )) min with nothing open so macOS settles..."; sleep $WAIT
S=(); for i in 1 2 3 4 5; do S+=("$(att_mem_used)"); (( i < 5 )) && sleep 30; done
MID=$(print -l $S | sort -t'|' -k1,1n | sed -n 3p); IFS='|' read USED APP WIRED COMP CACHE <<< "$MID"
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 )); CAP=$(att_gpu_cap)
F="$OUT/idle_${AI}_$(date +%Y-%m-%d_%H-%M).txt"
{ att_card_start "RAM: macOS by itself, Apple Intelligence ${(U)AI} (Step 17e)"
  (( UP > 1200 )) && print "!! Not a fresh restart (up $(( UP / 60 )) min). Restart, log in, run it again."
  print "Memory used: $USED GB of $RAM GB   (apps $APP | wired $WIRED | compressed $COMP)"
  print "Cached files (free to reuse, not 'used'): $CACHE GB"
  print "Free for your apps: $(awk -v r=$RAM -v u=$USED 'BEGIN{printf "%.1f", r-u}') GB"
  print "GPU memory cap: ${CAP:-?} GB of $RAM GB (the most memory the GPU can use)"
  print "Biggest things running with no apps open:"
  att_appmem_snap | head -8 | awk -F'|' '{printf "  %-28s %5.2f GB\n", substr($1,1,28), $2/1024}'
  att_log "New Tests" "Idle RAM after boot, Apple Intelligence ${(U)AI}" "$USED GB | wired $WIRED | compressed $COMP"
  [[ -n $CAP ]] && att_log "New Tests" "GPU memory cap" "$CAP GB of $RAM GB"
  att_card_end; } | tee "$F"
whence att_upload_results >/dev/null && att_upload_results

#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; att_quit_apps() { :; }; }
source "${0:A:h:h}/Tools/att-appmem.zsh"
# =============================================================================
#  att-appmem.zsh  -  Step 17c  App RAM appetite  (v1.0, Nov 21 2026)
# =============================================================================
#  How much memory each app WANTS, one app at a time, nothing else open:
#    Safari 20 tabs -> 80 tabs, Chrome 20 -> 80 tabs (if installed), Numbers workbook,
#    Final Cut (test library + 3-min project, 60 s playback), Logic (600-track benchmark
#    project), LM Studio Qwen 9B (and 27B on 32GB+).
#  Every 5 s it records each app's footprint (Activity Monitor "Memory"), how much of it
#  macOS compressed, swap and pressure. On a 64-128GB Studio the footprint is what the app
#  wants; on a 16GB mini you see how much got squeezed. Same list on every Mac.
#  Hands-off, about 25 min. Terminal needs Accessibility (asks once) for Final Cut playback.
#
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-appmem.zsh
#  Options in front: HOLD=45 (seconds each app sits after loading)  SKIP="chrome logic"
#  Results: Results/<Mac>/Memory/appmem_<date>.txt (card) + appmem_<date>.csv (every sample)
# =============================================================================
zmodload zsh/datetime
HERE=${0:A:h}; ROOT=$HERE
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && { print "Run this from inside the Adam Talks Tech Tests folder."; exit 1; }
[[ $HERE == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/Adam Talks Tech Tests."; exit 1; }
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
HOLD=${HOLD:-45}
OUT="$ROOT/Results/$MACNAME/Memory"; mkdir -p "$OUT"
STAMP=$(date +%Y-%m-%d_%H-%M)
CSV="$OUT/appmem_${STAMP}.csv"; RES="$OUT/appmem_${STAMP}.txt"; PH="$OUT/.appmem_${STAMP}.phases"

SITES=("${(@f)$(sed -n "/^SITES=(/,/^)/p" "$HERE/att-tabtest.zsh" | grep -o "https://[^']*")}")
WB=""; for f in "$HERE/ATT Stack Test Workbook v1.1.numbers" "$HERE/ATT Stack Test Workbook v1.numbers"; do [[ -e $f ]] && { WB=$f; break; }; done
LIB="$ROOT/Final Cut Test/Test Library rev.fcpbundle"; FCP_PROJECT="${FCP_PROJECT:-universal control on mac 3 min}"
FCP_APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep '\.app$' | grep -v '^/Volumes' | head -1)
[[ -z $FCP_APP ]] && FCP_APP=$(print -l /Applications/*Final*Cut*.app(N) /Applications/*/*Final*Cut*.app(N) | head -1)
FCP_NAME=${${FCP_APP:t}%.app}
LOGIC_APP=$(print -l /Applications/Logic*.app(N) /Applications/*/Logic*.app(N) | head -1)
LOGIC_PRJ=""; for d in "$ROOT/Logic Test" /Volumes/*/"Adam Talks Tech Tests"/"Logic Test"(N); do
  [[ -e "$d/NewLogicBenchmarkTest 2.logicx" ]] && { LOGIC_PRJ="$d/NewLogicBenchmarkTest 2.logicx"; break; }; done
CHROME=$(print -l "/Applications/Google Chrome.app"(N) | head -1)
LMS=$(command -v lms 2>/dev/null); [[ -z $LMS ]] && LMS="$HOME/.lmstudio/bin/lms"
key_for() { "$LMS" ls --json 2>/dev/null | jq -r --arg p "$1" '(if type=="array" then . else (.models // .llms // []) end)
  | [ .[] | select((((.path // "") + " " + (.modelKey // .key // "")) | test($p; "i"))) ][0] | (.modelKey // .key) // empty' 2>/dev/null; }

swap_gb() { sysctl -n vm.swapusage 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); u=substr(v,length(v)); v+=0; if(u=="G")v*=1024; printf "%.1f", v/1024}}'; }
plev() { case $(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null) in 1) print green;; 2) print yellow;; 4) print red;; *) print "?";; esac; }
SKIPS=" ${SKIP:-} "
want() { [[ $SKIPS != *" $1 "* ]]; }

# phase name | app regex (which app rows count) - start/end swap + pressure kept per phase
PH_CUR=""; PH_SW0=0
phase() {   # $1 short name, $2 app regex, $3 label
  PH_CUR=$1; PH_SW0=$(swap_gb); print -r -- "$3" > /tmp/att-step
  print "\n[$(date +%H:%M:%S)] $3"
  print -r -- "$1~$2~$3~$PH_SW0" >> "$PH"
}
phase_end() { local s=$(swap_gb); print -r -- "END~$PH_CUR~$s~$(plev)" >> "$PH"; }
hold() { local s=${1:-$HOLD}; print "  holding ${s}s..."; sleep $s; }
between() { print -r -- "between" > /tmp/att-step; sleep 15; }
open_tabs() { local a=$1 from=$2 to=$3 i; for (( i = from; i <= to; i++ )); do open -a "$a" "${SITES[$i]}"; sleep 3; done; }
quit_hard() { local a=$1 w=0
  osascript -e "tell application \"$a\" to quit saving no" >/dev/null 2>&1 || osascript -e "tell application \"$a\" to quit" >/dev/null 2>&1
  while pgrep -xq "$a" && (( w < 30 )); do sleep 1; (( w++ )); done
  pgrep -xq "$a" && { pkill -x "$a" 2>/dev/null; sleep 2; pgrep -xq "$a" && pkill -9 -x "$a" 2>/dev/null; print "  forced $a closed"; }
  return 0; }

(( ${#SITES} >= 80 )) || { print "Couldn't read the 80 test sites from att-tabtest.zsh."; exit 1; }
print "================ ATT App RAM appetite (Step 17c) ================"
print "Mac: $MACNAME | $(sysctl -n machdep.cpu.brand_string) | ${RAM_GB}GB"
print "Apps: Safari$([[ -n $CHROME ]] && print ', Chrome'), Numbers, ${FCP_NAME:-no Final Cut}, $([[ -n $LOGIC_APP && -n $LOGIC_PRJ ]] && print Logic || print 'no Logic'), LM Studio"
print "Hands-off, about 25 min. Don't use the Mac."
print "=================================================================="
source "$ROOT/Tools/att-ui.zsh"; UIOK=0; att_ui_setup && UIOK=1
att_cooldown
"$LMS" unload --all >/dev/null 2>&1
osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1; quit_hard Safari

att_appmem_start "$CSV" 5
trap 'att_appmem_stop; print "\nStopped."; exit 130' INT TERM
phase idle 'NONE' "idle (nothing open)"; hold 30; phase_end

if want safari; then
  phase safari20 '^(Safari|Web pages)' "Safari 20 tabs"; open_tabs Safari 1 20; hold; phase_end
  phase safari80 '^(Safari|Web pages)' "Safari 80 tabs"; open_tabs Safari 21 80; hold; phase_end
  osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1; quit_hard Safari; between
fi
if want chrome && [[ -n $CHROME ]]; then
  phase chrome20 '^Google Chrome' "Chrome 20 tabs"; open_tabs "Google Chrome" 1 20; hold; phase_end
  phase chrome80 '^Google Chrome' "Chrome 80 tabs"; open_tabs "Google Chrome" 21 80; hold; phase_end
  osascript -e 'tell application "Google Chrome" to close every window' >/dev/null 2>&1; quit_hard "Google Chrome"; between
fi
if want numbers && [[ -n $WB ]]; then
  phase numbers '^Numbers' "Numbers workbook"; open -a Numbers "$WB"
  (( UIOK )) && att_numbers_wait 300 >/dev/null || sleep 60
  hold 30; phase_end; quit_hard Numbers; between
fi
if want finalcut && [[ -n $FCP_APP && -e $LIB ]]; then
  phase finalcut "^${FCP_NAME}" "Final Cut (library + 3-min project playing)"; open -a "$FCP_APP" "$LIB"
  if (( UIOK )); then
    att_fcp_wait "$FCP_NAME" "$LIB"; sleep 5; att_fcp_open_project "$FCP_NAME" "$FCP_PROJECT"
    osascript -e "tell application \"System Events\" to tell process \"$(att_fcp_proc "$FCP_NAME")\" to set frontmost to true
      delay 0.5
      tell application \"System Events\" to key code 49" >/dev/null 2>&1   # space = play
    print "  playing the timeline"; hold 60
    osascript -e 'tell application "System Events" to key code 49' >/dev/null 2>&1
  else sleep 90; fi
  hold 20; phase_end; quit_hard "$FCP_NAME"; pgrep -f "Final Cut[^/]*\.app/Contents/MacOS/" >/dev/null && pkill -f "Final Cut[^/]*\.app/Contents/MacOS/"; between
elif want finalcut; then print "  (Final Cut or the Final Cut Test library isn't on this Mac: skipped. The stacker copies the library over.)"; fi
if want logic && [[ -n $LOGIC_APP && -n $LOGIC_PRJ ]]; then
  phase logic '^Logic' "Logic (600-track benchmark project)"; open -a "$LOGIC_APP" "$LOGIC_PRJ"
  sleep 60; hold; phase_end; quit_hard "${${LOGIC_APP:t}%.app}"; between
fi
if want qwen && [[ -x $LMS ]]; then
  Q9=$(key_for 'qwen3\.5-9b-mlx-4bit'); [[ -z $Q9 ]] && Q9=$(key_for 'qwen3\.5-9b')
  if [[ -n $Q9 ]]; then
    phase qwen9b '^LM Studio' "LM Studio with Qwen 9B loaded"; "$LMS" load "$Q9" --yes --context-length 8192 >/dev/null 2>&1; hold 30; phase_end
    "$LMS" unload --all >/dev/null 2>&1; between
  fi
  Q27=$(key_for 'qwen3\.8-27b-mlx-4bit')
  if (( RAM_GB >= 32 )) && [[ -n $Q27 ]]; then
    phase qwen27b '^LM Studio' "LM Studio with Qwen 27B loaded"; "$LMS" load "$Q27" --yes --context-length 8192 >/dev/null 2>&1; hold 30; phase_end
    "$LMS" unload --all >/dev/null 2>&1; between
  fi
  quit_hard "LM Studio"
fi
print -r -- "done" > /tmp/att-step; sleep 6
att_appmem_stop

# ---------- Card ----------
peak_of() {   # $1 step label, $2 app regex -> "footprintMB compressedMB" at the moment the total was highest
  awk -F, -v st="$1" -v re="$2" 'NR>1 && $2==st { a=$3; for (i=4; i<=NF-3; i++) a=a "," $i; gsub(/"/,"",a)
      if (a ~ re) { f[$1]+=$(NF-2); c[$1]+=$(NF-1) } }
    END { m=0; mc=0; for (t in f) if (f[t] > m) { m=f[t]; mc=c[t] } printf "%.0f %.0f", m, mc }' "$CSV"
}
typeset -A FP CP; MAXC=0; MAXSW=0; WORST=green
att_card_start "RAM: App appetite, one app at a time (Step 17c)"
{
print "Each app alone. Footprint = Activity Monitor 'Memory' (what the app wants)."
print "Compressed = the part macOS squeezed to make it fit. Swap/pressure = whole Mac."
print ""
printf "  %-46s %8s %10s %8s %s\n" "App / workload" "wants" "compressed" "swap" "pressure"
while IFS='~' read -r k re label sw0; do
  [[ $k == END || $k == idle ]] && continue
  read -r f c <<< "$(peak_of "$label" "$re")"; FP[$k]=$f; CP[$k]=$c
  endl=$(grep "^END~$k~" "$PH" | tail -1); sw1=$(print -r -- "$endl" | cut -d'~' -f3); pl=$(print -r -- "$endl" | cut -d'~' -f4)
  printf "  %-46s %5.1f GB %7.1f GB %+6.1f GB %s\n" "${label:0:46}" $(( f / 1024.0 )) $(( c / 1024.0 )) $(( ${sw1:-0} - ${sw0:-0} )) "$pl"
  (( c > MAXC )) && MAXC=$c; (( ${sw1:-0} - ${sw0:-0} > MAXSW )) && MAXSW=$(( ${sw1:-0} - ${sw0:-0} ))
  [[ $pl == red ]] && WORST=red; [[ $pl == yellow && $WORST == green ]] && WORST=yellow
done < "$PH"
if [[ -n ${FP[safari80]} && -n ${FP[safari20]} ]]; then
  printf "\n  Safari: about %.0f MB per extra tab (20 -> 80 tabs)\n" $(( (FP[safari80] - FP[safari20]) / 60.0 ))
fi
[[ -n ${FP[chrome80]} && -n ${FP[chrome20]} ]] && printf "  Chrome: about %.0f MB per extra tab (20 -> 80 tabs)\n" $(( (FP[chrome80] - FP[chrome20]) / 60.0 ))
print ""
print "Biggest apps over the whole run:"
att_appmem_peaks "$CSV" 6
g() { [[ -n ${FP[$1]} ]] && printf "%.1f" $(( FP[$1] / 1024.0 )) || printf -- "-"; }
print ""
att_log "New Tests" "App RAM: Safari 20 / 80 tabs" "$(g safari20) / $(g safari80)"
[[ -n ${FP[chrome20]} ]] && att_log "New Tests" "App RAM: Chrome 20 / 80 tabs" "$(g chrome20) / $(g chrome80)"
att_log "New Tests" "App RAM: Final Cut / Logic / Numbers" "$(g finalcut) / $(g logic) / $(g numbers)"
att_log "New Tests" "App RAM: Qwen 9B / 27B" "$(g qwen9b) / $(g qwen27b)"
att_log "New Tests" "App RAM: most compressed" "$(printf %.1f $(( MAXC / 1024.0 ))) / $(printf %.1f $MAXSW) / $WORST"
print "\nEvery 5-second sample: ${CSV:t}"
} | tee "$RES"
att_card_end
rm -f "$PH"

#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || { print "Can't find Tools/att-card.zsh. Run Update Scripts first."; exit 1; }
# =============================================================================
#  att-realday.zsh  -  Step 17d  Real Day RAM test  (v1.0, Nov 22 2026)
# =============================================================================
#  An hour of a normal day with everything left open, measured the whole time. Answers "does
#  this much RAM hold up for a real day?" better than a quick stack. Free apps only (no Lightroom:
#  Adobe seats can't run on every Mac at once).
#
#  everyday pile: Safari 20 tabs + a YouTube video playing, Chrome 20 tabs, Notes, Calendar,
#                 Numbers workbook, Photo Booth (camera on, the stand-in for a FaceTime call:
#                 a real call needs a second device; Macs with no camera skip it)
#  creator pile:  everything above + Final Cut (3-min project open), Logic (600-track project),
#                 Pixelmator Pro, LM Studio with Qwen 9B loaded
#
#  Every minute it switches to the next app and times how long until that app answers (same
#  check as Step 17b). Every 5 min: YouTube dropped frames, an old Safari tab (did macOS throw
#  it away?). Creator: a Qwen prompt every 10 min (tok/s start vs end) and a Final Cut 3-min
#  export at the end. Memory pressure, swap, compressed, SSD writes and every app's memory
#  are logged the whole hour.
#
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-realday.zsh everyday
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Memory Test" && zsh att-realday.zsh creator
#  Restart first. Hands-off after the first-minute prompts. Options: DURATION=3600 (seconds),
#  YT_URL=... (default: Tears of Steel, Blender's open movie)
#  Results: Results/<Mac>/Memory/realday_<pile>_<date>.txt (card) + .csv + memory/app logs
# =============================================================================
zmodload zsh/datetime
PILE=${1:-everyday}
[[ $PILE == (everyday|creator) ]] || { print "Which pile?  zsh att-realday.zsh everyday   or   zsh att-realday.zsh creator"; exit 1; }
HERE=${0:A:h}; ROOT=${HERE:h}
[[ $HERE == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/Adam Talks Tech Tests."; exit 1; }
MACNAME=$(scutil --get ComputerName 2>/dev/null)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
DURATION=${DURATION:-3600}
YT_URL=${YT_URL:-https://www.youtube.com/watch?v=R6MlUcmOul8}
OUT="$ROOT/Results/$MACNAME/Memory"; mkdir -p "$OUT"
STAMP=$(date +%Y-%m-%d_%H-%M); RES="$OUT/realday_${PILE}_$STAMP.txt"; PCSV="$OUT/realday_${PILE}_$STAMP.csv"
APPCSV="$OUT/appmem_realday_${PILE}_$STAMP.csv"

source "$ROOT/Tools/att-ui.zsh"; source "$ROOT/Tools/att-appmem.zsh"; source "$ROOT/Tools/att-prime.zsh"
SITES=("${(@f)$(sed -n "/^SITES=(/,/^)/p" "$HERE/att-tabtest.zsh" | grep -o "https://[^']*")}")
(( ${#SITES} >= 40 )) || { print "Couldn't read the test sites from att-tabtest.zsh."; exit 1; }
WB=""; for f in "$HERE/ATT Stack Test Workbook v1.1.numbers" "$HERE/ATT Stack Test Workbook v1.numbers"; do [[ -e $f ]] && { WB=$f; break; }; done
CHROME=$(att_app_path "Google Chrome"); PBOOTH=$(att_app_path "Photo Booth")
HAS_CAM=$(system_profiler SPCameraDataType 2>/dev/null | grep -c "Model ID")
FCP_APP=$(att_app_path "Final Cut Pro"); FCP_NAME=${${FCP_APP:t}%.app}
LOGIC_APP=$(att_app_path "Logic Pro"); PIX=$(att_app_path "Pixelmator Pro")
LIB="$ROOT/Final Cut Test/Test Library rev.fcpbundle"; FCP_PROJECT="universal control on mac 3 min"
LOGIC_PRJ=""; for d in "$ROOT/Logic Test" /Volumes/*/"Adam Talks Tech Tests"/"Logic Test"(N); do
  [[ -e "$d/NewLogicBenchmarkTest 2.logicx" ]] && { LOGIC_PRJ="$d/NewLogicBenchmarkTest 2.logicx"; break; }; done
LMS=$(command -v lms 2>/dev/null); [[ -z $LMS ]] && LMS="$HOME/.lmstudio/bin/lms"
API="http://localhost:1234"

ms_since() { printf '%.0f' $(( (EPOCHREALTIME - $1) * 1000 )) }
# Nov 22: same millisecond timer as Responsiveness v2 (Tools/att-snappy.swift); the AppleScript
# fallback below can't see under ~220 ms, so a card made with it is held.
SNAPPY=$HOME/.att/att-snappy; SNSRC="$ROOT/Tools/att-snappy.swift"
if [[ ! -x $SNAPPY || $SNSRC -nt $SNAPPY ]]; then swiftc -O "$SNSRC" -o "$SNAPPY" 2>/dev/null; fi
[[ -x $SNAPPY ]] && TIMER=ms || TIMER=applescript
probe_app() {   # time from "switch to it" until the app answers and its window is in front
  local app="$1" t0 rc try r
  if [[ $TIMER == ms ]]; then r=$("$SNAPPY" app "$app" 2>/dev/null); print -r -- "${r:--1 1}"; return; fi
  t0=$EPOCHREALTIME
  osascript -e "tell application \"System Events\" to set frontmost of process \"$app\" to true" >/dev/null 2>&1
  for try in 1 2; do osascript -e "tell application \"System Events\" to tell process \"$app\" to count windows" >/dev/null 2>&1; rc=$?; (( rc == 0 )) && break; done
  print "$(ms_since $t0) $rc"
}
step() { print -r -- "$1" > /tmp/att-step; print "\n[$(date +%H:%M:%S)] $1"; }
safari_js() { osascript -e "tell application \"Safari\" to do JavaScript \"$2\" in tab $1 of window 1" 2>/dev/null; }

# ---------- 1. Before you walk away ----------
print "================ ATT Real Day ($PILE pile, Step 17d) ================"
print "Mac: $MACNAME | $(sysctl -n machdep.cpu.brand_string) | ${RAM_GB}GB | $(( DURATION / 60 )) min"
att_ui_setup || { print "Needs Terminal in Accessibility (the app-switch timing)."; exit 1; }
[[ -n $ATT_NOSYNC ]] || att_prime realday $([[ $PILE == creator ]] && print realday-creator)
if [[ $PILE == creator ]]; then
  [[ -n $FCP_APP && -e $LIB ]] || { print "Creator pile needs Final Cut + the Final Cut Test library (run the stacker once to copy it)."; exit 1; }
  [[ -x $LMS ]] || { print "Creator pile needs LM Studio (open it once)."; exit 1; }
  zsh "$ROOT/AI Tests/att-models.zsh" get Qwen3.5-9B-MLX-4bit >/dev/null 2>&1
  Q9=$("$LMS" ls --json 2>/dev/null | jq -r '(if type=="array" then . else (.models // .llms // []) end) | [ .[] | select(((.path // "") + " " + (.modelKey // .key // "")) | test("qwen3\\.5-9b"; "i")) ][0] | (.modelKey // .key) // empty' 2>/dev/null)
  [[ -n $Q9 ]] || { print "Qwen 3.5 9B isn't on this Mac. Plug in a test drive and rerun."; exit 1; }
fi
ATT_KEEP="Claude,Screen Sharing" att_cooldown
"$LMS" unload --all >/dev/null 2>&1

zsh "$HERE/att-memlog.zsh" "realday $PILE" 5 > "$OUT/.memlog_realday_$STAMP.out" 2>&1 &
LOGPID=$!
att_appmem_start "$APPCSV" 15
trap 'att_appmem_stop; kill -TERM $LOGPID 2>/dev/null; print "\nStopped."; exit 130' INT TERM
sleep 6

# ---------- 2. Open the day ----------
APPS=()
step "open: Safari + YouTube"
open -a Safari "$YT_URL"; sleep 8
safari_js 1 "var v=document.querySelector('video'); if(v){v.muted=true; v.loop=true; v.play();} 'ok'" >/dev/null
for (( i = 1; i <= 20; i++ )); do osascript -e "tell application \"Safari\" to tell window 1 to make new tab with properties {URL:\"${SITES[$i]}\"}" >/dev/null 2>&1; sleep 2; done
sleep 10
for (( i = 2; i <= 21; i++ )); do safari_js $i "window.__att=1" >/dev/null; done   # mark the tabs (a reload clears the mark)
osascript -e 'tell application "Safari" to set current tab of window 1 to tab 1 of window 1' >/dev/null 2>&1
APPS+=(Safari)
if [[ -n $CHROME ]]; then
  step "open: Chrome 20 tabs"
  for (( i = 21; i <= 40; i++ )); do open -a "$CHROME" "${SITES[$i]}"; sleep 2; done
  APPS+=("Google Chrome")
fi
step "open: Notes, Calendar, Numbers"
open -a Notes; open -a Calendar; [[ -n $WB ]] && { open -a Numbers "$WB"; att_clear_dialogs Numbers 16; }; att_clear_dialogs Calendar 4; att_clear_dialogs Notes 2
APPS+=(Notes Calendar); [[ -n $WB ]] && APPS+=(Numbers)
if [[ -n $PBOOTH ]] && (( HAS_CAM )); then step "open: Photo Booth (camera on, call stand-in)"; open -a "$PBOOTH"; sleep 5; APPS+=("Photo Booth"); fi
if [[ $PILE == creator ]]; then
  step "open: Final Cut"; open -a "$FCP_APP" "$LIB"; att_fcp_wait "$FCP_NAME" "$LIB"; sleep 5; att_fcp_open_project "$FCP_NAME" "$FCP_PROJECT"
  APPS+=("$(att_fcp_proc "$FCP_NAME")")
  if [[ -n $LOGIC_APP && -n $LOGIC_PRJ ]]; then step "open: Logic"; open -a "$LOGIC_APP" "$LOGIC_PRJ"; sleep 60; APPS+=("${${LOGIC_APP:t}%.app}"); fi
  if [[ -n $PIX ]]; then step "open: Pixelmator Pro"; open -a "$PIX"; sleep 10; APPS+=("Pixelmator Pro"); fi
  step "open: Qwen 9B"; "$LMS" server start >/dev/null 2>&1; "$LMS" load "$Q9" --yes --context-length 8192 >/dev/null 2>&1; APPS+=("LM Studio")
fi
print "Open: ${(j:, :)APPS}"

qwen_tps() {   # one fixed prompt, thinking off (same as the AI tests), tok/s
  local body r
  body=$(jq -n --arg m "$Q9" '{model:$m, temperature:0, max_tokens:200, stream:false,
    prompt:"<|im_start|>user\nWrite 3 short paragraphs about the history of the Mac.<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"}')
  r=$(curl -s -m 180 "$API/api/v0/completions" -H 'Content-Type: application/json' -d "$body" 2>/dev/null)
  r=$(print -r -- "$r" | jq -r '.stats.tokens_per_second // empty' 2>/dev/null)
  [[ -n $r ]] && printf '%.1f' $r
}

# ---------- 3. The day ----------
print "time,elapsed_s,kind,what,value,ok" > "$PCSV"
rec() { print -r -- "$(date +%H:%M:%S),$(( EPOCHSECONDS - T0 )),$1,\"$2\",$3,$4" >> "$PCSV"; }
T0=$EPOCHSECONDS; n=0; QT=()
[[ $PILE == creator ]] && { t=$(qwen_tps); [[ -n $t ]] && { QT+=($t); rec qwen start $t 0; }; }
while (( EPOCHSECONDS - T0 < DURATION )); do
  el=$(( EPOCHSECONDS - T0 ))
  step "the day: $(( el / 60 )) of $(( DURATION / 60 )) min"
  a=${APPS[$(( n % ${#APPS} + 1 ))]}
  read ms rc <<< "$(probe_app "$a")"; rec switch "$a" $ms $rc
  if (( n % 5 == 0 )); then
    q=$(safari_js 1 "var v=document.querySelector('video'); v? (v.getVideoPlaybackQuality().droppedVideoFrames+'/'+v.getVideoPlaybackQuality().totalVideoFrames+'/'+(v.paused?'paused':'playing')) : 'none'")
    rec youtube frames "${q:-?}" 0
    k=$(( (n / 5) % 20 + 2 ))
    r=$(osascript -e "tell application \"Safari\" to set current tab of window 1 to tab $k of window 1" -e 'delay 2' -e "tell application \"Safari\" to do JavaScript \"window.__att?'kept':'reloaded'\" in tab $k of window 1" 2>/dev/null)
    rec oldtab "tab $k" "${r:-?}" 0
    osascript -e 'tell application "Safari" to set current tab of window 1 to tab 1 of window 1' >/dev/null 2>&1
  fi
  if [[ $PILE == creator ]] && (( n > 0 && n % 10 == 0 )); then t=$(qwen_tps); [[ -n $t ]] && { QT+=($t); rec qwen "min $(( el / 60 ))" $t 0; }; fi
  (( n++ ))
  sleep $(( 60 - (EPOCHSECONDS - T0 - el) > 0 ? 60 - (EPOCHSECONDS - T0 - el) : 1 ))
done
EXP=""
if [[ $PILE == creator ]]; then
  step "final cut export at the end of the day"
  rm -rf "$ROOT/Export"/*(N) 2>/dev/null; mkdir -p "$ROOT/Export"
  if att_fcp_share "$FCP_NAME" "$ROOT/Export"; then
    ATT_STEP_OVERRIDE=17d zsh "$ROOT/Tools/att-export-timer.zsh" "" "FCP 3-min 4K, real day creator ($MACNAME)" START=$SHARE_START
    EXP=$(tail -1 "$ROOT/Results/$MACNAME/Exports/exports.csv" 2>/dev/null | sed -E 's/"[^"]*"//g' | awk -F, '{print $5}')
  fi
  rm -rf "$ROOT/Export"/*(N) 2>/dev/null
fi
step "done"; sleep 6

# ---------- 4. Close everything, collect ----------
att_appmem_stop; kill -TERM $LOGPID 2>/dev/null; for _w in {1..20}; do kill -0 $LOGPID 2>/dev/null || break; sleep 1; done; kill -9 $LOGPID 2>/dev/null; trap - INT TERM
( osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1 ) & sleep 5; kill $! 2>/dev/null
[[ $PILE == creator ]] && "$LMS" unload --all >/dev/null 2>&1
for a in $APPS "Google Chrome"; do att_quit_hard "$a"; done   # Nov 22: never waits more than ~35 s per app
sleep 5; for a in $APPS Safari "Google Chrome" "Photo Booth" Notes Calendar "LM Studio" "Pixelmator Pro"; do pgrep -xq "$a" && { whence att_quit_hard >/dev/null && att_quit_hard "$a" || pkill -9 -x "$a" 2>/dev/null; }; done   # Nov 22: Logic/Final Cut/Numbers were staying open

MCSV=$(ls -t "$OUT"/*_realday_${PILE}.csv 2>/dev/null | head -1)
val() { awk -F, -v k="$1" '$1==k{print $2}' "$MCSV" 2>/dev/null | tail -1; }
sw_stats() {   # $1 = from minute, $2 = to minute -> "avg worst count"
  awk -F, -v a=$(( $1 * 60 )) -v b=$(( $2 * 60 )) '$3=="switch" && $2>=a && $2<b && $6==0 {s+=$5; n++; if($5>w)w=$5} END{if(n) printf "%d %d %d", s/n, w, n; else print "- - 0"}' "$PCSV"; }
read A_ALL W_ALL N_ALL <<< "$(sw_stats 0 999)"; read A_FIRST _ _ <<< "$(sw_stats 0 10)"
read A_LAST _ _ <<< "$(sw_stats $(( DURATION / 60 - 10 )) 999)"
NOANS=$(awk -F, '$3=="switch" && $6!=0' "$PCSV" | wc -l | tr -d ' ')
YT=$(awk -F, '$3=="youtube"{v=$5} END{gsub(/"/,"",v); print v}' "$PCSV"); YD=${YT%%/*}; YTOT=$(print -r -- "$YT" | cut -d/ -f2)
YPCT=$( [[ $YD == <-> && $YTOT == <-> && $YTOT -gt 0 ]] && awk -v d=$YD -v t=$YTOT 'BEGIN{printf "%.2f", d*100/t}' || print "?")
OLD_RL=$(grep -c ',oldtab,.*reloaded' "$PCSV"); OLD_N=$(grep -c ',oldtab,' "$PCSV")
_y=$(val 'Seconds in yellow'); _r=$(val 'Seconds in red'); WORST=green; (( ${_y:-0} > 0 )) && WORST=yellow; (( ${_r:-0} > 0 )) && WORST=red
SWAP=$(awk -v a="$(val 'Peak swap GB')" -v b="$(val 'Swap at start GB')" 'BEGIN{if(a=="")print "?"; else printf "%.1f", a-b}')
{
att_card_start "RAM: Real Day, $PILE pile, $(( DURATION / 60 )) min (Step 17d)"
[[ $TIMER == ms ]] || print "!! Timed with the old AppleScript check (the ms timer did not build: needs Command Line Tools). Not logged."
print "Open all day: ${(j:, :)APPS}"
print "App switch (Step 17b check): avg ${A_ALL} ms, worst ${W_ALL} ms over ${N_ALL} switches"
print "   first 10 min avg ${A_FIRST} ms  ->  last 10 min avg ${A_LAST} ms   (no answer: $NOANS)"
print "YouTube (Safari, muted, looping): ${YD:-?} of ${YTOT:-?} frames dropped (${YPCT}%)"
print "Old Safari tabs macOS threw away: $OLD_RL of $OLD_N checks"
(( ${#QT} )) && print "Qwen 9B tok/s: start ${QT[1]}  ->  end ${QT[-1]}   (all: ${(j:, :)QT})"
[[ $PILE == creator ]] && print "Final Cut 3-min export at the end of the day: ${EXP:-?} s"
print "Pressure: worst $WORST | yellow $(( ${_y:-0} / 60 )) min, red $(( ${_r:-0} / 60 )) min | swap added $SWAP GB | peak compressed $(val 'Peak compressed GB') GB"
print "SSD written: $(val 'SSD written during test GB') GB | lowest memory free $(val 'Lowest memory free %')%"
print "Biggest apps (peak, Activity Monitor 'Memory'):"
att_appmem_peaks "$APPCSV" 8
(( HAS_CAM )) || print "No camera on this Mac: Photo Booth (call stand-in) skipped"
att_log "New Tests" "Real Day $PILE" "${A_ALL} / ${W_ALL} ms | ${A_FIRST} -> ${A_LAST} ms | $WORST, swap +$SWAP GB | YT drop ${YPCT}%$([[ $PILE == creator ]] && print " | Qwen ${QT[1]:-?} -> ${QT[-1]:-?} tok/s | FCP ${EXP:-?} s")"
SSDW=$(val 'SSD written during test GB')
if [[ -n $SSDW ]]; then
  GBH=$(awk -v w=$SSDW -v d=$DURATION 'BEGIN{printf "%.1f", w*3600/d}')
  print "SSD writes: $GBH GB per hour, about $(awk -v h=$GBH 'BEGIN{printf "%.0f", h*8}') GB in an 8-hour day (swap +$SWAP GB)"
  att_log "New Tests" "SSD writes during Real Day $PILE" "$GBH GB/h (~$(awk -v h=$GBH 'BEGIN{printf "%.0f", h*8}') GB per 8-h day) | swap +$SWAP GB"
fi
print "Logs: ${PCSV:t}, ${APPCSV:t}, ${MCSV:t}"
att_card_end
} | tee "$RES"
rm -f "$OUT/.memlog_realday_$STAMP.out"

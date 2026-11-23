#!/bin/zsh
# =============================================================================
#  E8  Battery life, run to 5% (EXPERIMENT, Nov 22 2026) - not logged to the main sheet
# =============================================================================
#  The laptop question every MacBook video gets. A real run-down, not an estimate:
#    - each hour: 45 min of web browsing (a new site every minute in one Safari tab, scrolled)
#      + 15 min of video playing in QuickTime (the HandBrake test movie, looped, muted)
#    - brightness fixed at 50% of the slider (set by the script), Wi-Fi on, sound muted,
#      display kept awake, Low Power Mode must be off
#    - every minute: battery %, watts (battery voltage x current), temperature-free, to a CSV
#    - stops at 5% (doesn't let the Mac die) and prints hours to 5% + average watts
#  Battery health (cycle count, max capacity vs design) is on the card, since an old battery skews it.
#  Note: 50% of the slider isn't the same brightness (nits) on every display; it's the same position.
#
#  Before: charge to 100%, turn OFF "Automatically adjust brightness" and True Tone
#  (System Settings > Displays), close other apps. Then run it; it waits for you to UNPLUG.
#    cd ~/Downloads/"Adam Talks Tech Tests"/Experiments && zsh e8-battery-drain.zsh
#  If the Mac died or restarted before the card:  zsh e8-battery-drain.zsh report   (rebuilds it from the CSV)
#  Takes 6-24+ hours. Run two laptops at a time (weekend).
# =============================================================================
export ATT_EXPERIMENT=1
source "${0:A:h:h}/Tools/att-card.zsh"
zmodload zsh/datetime
ROOT=${0:A:h:h}; MAC=$(scutil --get ComputerName); OUT="$ROOT/Results/$MAC/Experiments"; mkdir -p "$OUT"
STOP_AT=${STOP_AT:-5}; BRIGHT=${BRIGHT:-0.5}
batt()  { pmset -g batt | grep -o '[0-9]*%' | head -1 | tr -d %; }
onac()  { pmset -g batt | head -1 | grep -q "AC Power"; }
bi()    { ioreg -rn AppleSmartBattery | awk -F' = ' -v k="\"$1\"" '$1 ~ k {gsub(/ /,"",$2); print $2; exit}'; }
watts() {   # discharge watts from voltage (mV) x amperage (mA; ioreg can show it as a huge unsigned number)
  local v=$(bi Voltage) a=$(bi Amperage)
  [[ -z $v || -z $a ]] && { print "?"; return; }
  awk -v v=$v -v a=$a 'BEGIN{ if (a > 9e18) a -= 18446744073709551616; if (a > 2147483647) a -= 4294967296; printf "%.2f", (v/1000)*(-a/1000) }'; }

report() {   # $1 csv
  local csv=$1
  [[ -s $csv ]] || { print "No battery CSV found."; exit 1; }
  local first last mins avgw p0 p1
  first=$(awk -F, 'NR==2{print $1}' $csv); last=$(awk -F, 'END{print $1}' $csv)
  mins=$(awk -F, 'END{print $2}' $csv)
  avgw=$(awk -F, 'NR>1 && $4!="?" && $4>0 {s+=$4; n++} END{if(n) printf "%.1f", s/n}' $csv)
  p0=$(awk -F, 'NR==2{print $3}' $csv); p1=$(awk -F, 'END{print $3}' $csv)
  local used=$(( p0 - p1 )); local h=$(awk -v m=$mins 'BEGIN{printf "%.1f", m/60}')
  local full=$(awk -v m=$mins -v u=$used 'BEGIN{ if (u>0) printf "%.1f", m/60*100/u; else print "?" }')
  { att_card_start "EXPERIMENT E8: battery life, web 45 min + video 15 min per hour (not logged to the main sheet)"
    print "Ran ${h} h on battery: ${p0}% -> ${p1}%  (stops at ${STOP_AT}%)"
    print "Whole battery at this pace: about ${full} h (100% to 0%, worked out from the % used)"
    print "Average draw: ${avgw:-?} W"
    print "$(head -1 ${csv:r}.info 2>/dev/null)"
    print "Send this card to Claude: it goes on the Experiments tab."
    att_card_end; } | tee "${csv:r}.txt"
}
if [[ $1 == report ]]; then report "$(ls -t $OUT/e8-battery_*.csv 2>/dev/null | head -1)"; exit; fi

pmset -g batt | grep -q InternalBattery || { print "This Mac has no battery (laptops only)."; exit 1; }
pmset -g | grep -q "lowpowermode *1" && { print "!! Low Power Mode is on. Turn it off (System Settings > Battery), rerun."; exit 1; }
BR=$HOME/.att/att-bright
[[ -x $BR && ! $ROOT/Tools/att-bright.swift -nt $BR ]] || swiftc -O "$ROOT/Tools/att-bright.swift" -o $BR 2>/dev/null
[[ -x $BR ]] || { print "!! Couldn't build the brightness helper (needs Command Line Tools: xcode-select --install)."; exit 1; }
MOVIE=$(print -l "$ROOT/HandBrake Test"/*.(mov|mp4|m4v|mkv)(N) | head -1)
[[ -n $MOVIE ]] || print "Note: no movie in HandBrake Test, so the video part is skipped (web only)."
(( $(batt) >= 98 )) || print "Note: battery is at $(batt)%. Charge to 100% first for a full run (Ctrl-C now, or carry on)."
CYC=$(bi CycleCount); MAXC=$(bi AppleRawMaxCapacity); DES=$(bi DesignCapacity)
HEALTH=$(awk -v m=${MAXC:-0} -v d=${DES:-0} 'BEGIN{ if (d>0) printf "%.0f%%", m*100/d; else print "?" }')
STAMP=$(date +%Y-%m-%d_%H-%M); CSV="$OUT/e8-battery_$STAMP.csv"
print "Battery: ${CYC:-?} cycles, ${HEALTH} of design capacity (${MAXC:-?} / ${DES:-?} mAh). macOS $(sw_vers -productVersion)" > ${CSV:r}.info

att_quit_apps
OLDB=$($BR); $BR $BRIGHT >/dev/null
OLDVOL=$(osascript -e 'output muted of (get volume settings)'); osascript -e 'set volume output muted true'
caffeinate -dimsu & CAF=$!
cleanup() { kill $CAF 2>/dev/null; $BR ${OLDB:-0.6} >/dev/null 2>&1; [[ $OLDVOL == false ]] && osascript -e 'set volume output muted false'
  osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1; att_quit_hard QuickTime\ Player 2>/dev/null; att_quit_hard Safari 2>/dev/null; }
trap 'cleanup; report "$CSV"; exit 0' INT TERM

print "\nBrightness set to $($BR) (was ${OLDB}). Sound muted. Display stays awake."
print ">> UNPLUG THE CHARGER NOW. The test starts the moment it's on battery."
until ! onac; do sleep 2; done
print "On battery at $(batt)%. Running until ${STOP_AT}%... (Ctrl-C ends early and still prints the card)"
SITES=(https://www.apple.com https://en.wikipedia.org/wiki/Apple_silicon https://www.theverge.com https://www.macrumors.com
  https://9to5mac.com https://en.wikipedia.org/wiki/MacBook_Pro https://www.nasa.gov https://www.nationalgeographic.com
  https://en.wikipedia.org/wiki/Great_Barrier_Reef https://www.engadget.com https://appleinsider.com https://en.wikipedia.org/wiki/Moon
  https://www.allrecipes.com https://www.espn.com https://adamtalks.tech https://en.wikipedia.org/wiki/Photography
  https://www.imdb.com https://developer.apple.com https://en.wikipedia.org/wiki/Solar_System https://www.blender.org)
print "time,minutes_on_battery,percent,watts,phase" > $CSV
T0=$EPOCHSECONDS; i=0
osascript -e 'tell application "Safari" to make new document with properties {URL:"https://www.apple.com"}' >/dev/null 2>&1
while true; do
  p=$(batt); el=$(( (EPOCHSECONDS - T0) / 60 ))
  onac && { print "\n!! Charger plugged back in at ${el} min. Stopping."; break; }
  m=$(( el % 60 )); phase=web; [[ -n $MOVIE ]] && (( m >= 45 )) && phase=video
  print "$(date +%H:%M:%S),$el,$p,$(watts),$phase" >> $CSV
  print -n "\r  ${el} min on battery: ${p}%  ($(tail -1 $CSV | cut -d, -f4) W, $phase)     "
  (( p <= STOP_AT )) && { print "\nReached ${STOP_AT}%."; break; }
  if [[ $phase == web ]]; then
    pgrep -xq "QuickTime Player" && att_quit_hard "QuickTime Player"
    (( i++ )); u=${SITES[$(( (i - 1) % ${#SITES} + 1 ))]}
    osascript -e "tell application \"Safari\" to set URL of current tab of front window to \"$u\"" >/dev/null 2>&1
    sleep 20; osascript -e 'tell application "Safari" to do JavaScript "window.scrollBy(0, 900)" in current tab of front window' >/dev/null 2>&1
    sleep 20; osascript -e 'tell application "Safari" to do JavaScript "window.scrollBy(0, 900)" in current tab of front window' >/dev/null 2>&1
    sleep 20
  else
    if ! pgrep -xq "QuickTime Player"; then
      open -a "QuickTime Player" "$MOVIE"; sleep 4
      osascript -e 'tell application "QuickTime Player" to set looping of document 1 to true' -e 'tell application "QuickTime Player" to play document 1' >/dev/null 2>&1
    fi
    sleep 60
  fi
done
cleanup; report "$CSV"

# ATT photo card (sourced by the test scripts, not run on its own)
# Frames the final result so one Terminal photo has everything Claude needs
# to log it: test, Mac name, chip, RAM, macOS, date, then the numbers.
att_card_start() {
  local mac=$(scutil --get ComputerName 2>/dev/null)
  local chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  local ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  local os="$(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
  print ""
  print "#################### PHOTO THIS FOR CLAUDE ####################"
  print "TEST:  $*"
  print "MAC:   $mac"
  print "       $chip | ${ram}GB | macOS $os"
  print "DATE:  $(date '+%b %d %Y  %I:%M %p')"
  [[ -n $ATT_COOL_NOTE ]] && print "START: $ATT_COOL_NOTE"
  print -r -- "---------------------------------------------------------------"
}
att_card_end() {
  print "###############################################################"
  print "(Make the window tall enough that the whole box shows in the photo.)"
  print ""
}

# ATT quit-apps: politely quits every other app + common background helpers before a test.
#  Keeps Terminal/Finder/TextEdit (the Run Order is usually open in TextEdit) (and anything in ATT_KEEP, e.g. ATT_KEEP="LM Studio").
#  Polite quit only: an app with unsaved work asks you first and stays open.
#  Skip it with NOQUIT=1.
ATT_HELPERS=("Creative Cloud" "Adobe Creative Cloud" "Dropbox" "Google Drive" "OneDrive" "Backblaze" "Spotify" "Discord" "Slack" "zoom.us" "Microsoft Teams" "Steam" "Logi Options+" "Elgato Stream Deck" "Stream Deck" "Docker Desktop" "Music" "Photos" "Mail" "Messages")
att_quit_apps() {
  [[ $NOQUIT == 1 ]] && { print "Quitting other apps skipped (NOQUIT=1)."; return 0; }
  local -a keep names ids closed stuck
  ATT_COOL_NOTE=""
  keep=("Terminal" "iTerm2" "Ghostty" "Warp" "Finder" "TextEdit" ${(s:,:)ATT_KEEP})
  names=("${(@f)$(osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>/dev/null | tr ',' '\n' | sed 's/^ *//')}")
  ids=("${(@f)$(osascript -e 'tell application "System Events" to get bundle identifier of every process whose background only is false' 2>/dev/null | tr ',' '\n' | sed 's/^ *//')}")
  local i n id h
  for (( i = 1; i <= ${#names}; i++ )); do
    n=${names[$i]}; id=${ids[$i]}
    [[ -z $n || -z $id || $id == "missing value" ]] && continue
    (( ${keep[(Ie)$n]} )) && continue
    osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 && closed+=("$n")
  done
  for h in $ATT_HELPERS; do
    (( ${keep[(Ie)$h]} )) && continue
    pgrep -xq "$h" || continue
    osascript -e "tell application \"$h\" to quit" >/dev/null 2>&1 && closed+=("$h")
  done
  sleep 5
  for n in $closed; do pgrep -xq "$n" && stuck+=("$n"); done
  (( ${#closed} )) && print "Closed other apps: ${(j:, :)${(@u)closed}}" || print "No other apps were open."
  (( ${#stuck} )) && { print "!! Still open (probably asking to save): ${(j:, :)stuck}. Deal with it, then the test continues."; ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }still open: ${(j:, :)stuck}"; }
  return 0
}

# ATT cooldown gate: waits until the Mac is cool and idle before a test starts.
#  - macOS heat level must read Nominal (notifyutil, no password needed)
#  - CPU must be quiet (all processes under ~1.5 cores combined (Spotlight etc. can idle along)) for QUIET seconds
#  - plus an optional fixed rest first: COOL=300 zsh blender-bench.sh
#  Skip it with NOCOOL=1. Gives up after 10 min and says so (logged as a warning).
att_cooldown() {
  local again=0; [[ $1 == --again ]] && again=1
  (( again )) || att_quit_apps
  [[ $NOCOOL == 1 ]] && { print "Cooldown check skipped (NOCOOL=1)."; return 0; }
  local rest=${COOL:-0} need=${QUIET:-60} quiet=0 waited=0 lvl load name
  (( again )) && rest=0
  if (( rest > 0 )); then print "Resting ${rest}s before the test (COOL=$rest)..."; sleep $rest; fi
  print -n "Cooldown check: waiting for Nominal heat + ${need}s of idle CPU"
  while (( waited < 600 )); do
    lvl=$(notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | awk '{print $NF}')
    load=$(ps -A -o %cpu= | awk '{s+=$1} END {printf "%d", s}')
    if [[ ${lvl:-0} == 0 ]] && (( load < 150 )); then (( quiet += 5 )); else quiet=0; fi
    (( quiet >= need )) && { print "\nCool and idle. Starting (waited ${waited}s)."; ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }cooldown ok after ${waited}s"; return 0; }
    print -n "."; sleep 5; (( waited += 5 ))
  done
  case ${lvl:-0} in 0) name=Nominal;; 1) name=Moderate;; 2) name=Heavy;; *) name="level $lvl";; esac
  print "\n!! Still not cool/idle after 10 min (heat: $name, CPU load ${load}%). Starting anyway; note it in the results."
  ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }WARNING not cool after 10 min (heat $name, load ${load}%)"
}

# ATT background watch: while a test runs, every 10s note any OTHER process
# using more than ~20% of one core. Afterwards att_watch_report says what (if
# anything) competed with the test, so a weird run explains itself.
#   att_watch_start <logfile> "<test process names, regex>"   e.g. "Blender|blender"
#   ... run the test ...
#   att_watch_stop;  att_watch_report <logfile>   (prints one line)
att_watch_start() {
  local log=$1 skip=${2:-NONE}
  : > "$log"
  (
    while true; do
      ps -A -o %cpu=,comm= 2>/dev/null | awk -v t="$(date +%H:%M:%S)" -v skip="$skip" '
        { pct=$1; $1=""; sub(/^ +/,""); n=$0; sub(/.*\//,"",n) }
        pct+0 >= 20 && n !~ skip && n !~ /^(ps|awk|zsh|bash|sleep|powermetrics|kernel_task|WindowServer|Terminal|sudo)$/ {
          printf "%s %.0f %s\n", t, pct, n }' >> "$log"
      sleep 10
    done
  ) &!
  ATT_WATCH_PID=$!
}
att_watch_stop() { [[ -n $ATT_WATCH_PID ]] && kill $ATT_WATCH_PID 2>/dev/null; ATT_WATCH_PID=""; }
att_watch_report() {   # one line: top 3 background processes by CPU over the run
  local log=$1
  [[ -s $log ]] || { print "Background CPU: none (nothing else over 20% of a core)"; return; }
  print -n "Background CPU: "
  awk '{ n=$3; for(i=4;i<=NF;i++) n=n" "$i; sum[n]+=$2; cnt[n]++ }
       END { for (n in sum) printf "%d\t%s ~%d%% for ~%ds\n", sum[n], n, sum[n]/cnt[n], cnt[n]*10 }' "$log" |
    sort -rn | head -3 | cut -f2 | paste -sd ';' - | sed 's/;/; /g'
}

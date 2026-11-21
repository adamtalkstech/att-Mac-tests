# ATT photo card (sourced by the test scripts, not run on its own)
# Frames the final result so one Terminal photo has everything Claude needs
# to log it: test, Mac name, chip, RAM, macOS, date, then the numbers.
# One line that says what kind of Mac this is, so two Macs with the same chip can't be mixed up:
#   "Mac mini (Mac17,4) | desktop | 18-core CPU, 20-core GPU | 1TB SSD"
# Worked out once per Mac and kept in ~/.att/mac-kind.txt (delete it to redo).
att_mac_kind() {
  local f=$HOME/.att/mac-kind.txt
  [[ -s $f && $f -nt /System/Library/CoreServices/SystemVersion.plist ]] && { print -r -- "$(<$f)"; return; }
  local hw=$(system_profiler SPHardwareDataType 2>/dev/null)
  local name=$(print -r -- "$hw" | awk -F': ' '/Model Name/ {print $2; exit}')
  local id=$(sysctl -n hw.model 2>/dev/null)
  local cpu=$(sysctl -n hw.ncpu 2>/dev/null)
  local gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Total Number of Cores/ {print $2; exit}')
  local kind=desktop
  [[ $name == *Book* || -n $(pmset -g batt 2>/dev/null | grep -i InternalBattery) ]] && kind=laptop
  local disk=$(diskutil info / 2>/dev/null | awk -F'[(:]' '/Container Total Space|Disk Size/ {gsub(/^ +| +$/,"",$2); print $2; exit}')
  local line="${name:-Mac} ($id) | $kind | ${cpu}-core CPU${gpu:+, ${gpu}-core GPU}${disk:+ | $disk SSD}"
  mkdir -p ${f:h}; print -r -- "$line" > $f
  print -r -- "$line"
}
att_card_start() {
  local mac=$(scutil --get ComputerName 2>/dev/null)
  local chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  local ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  local os="$(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
  print ""
  print "#################### PHOTO THIS FOR CLAUDE ####################"
  print "TEST:  $*"
  print "MAC:   $mac"
  print "       $(att_mac_kind)"
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

# ATT power check (laptops): what's actually powering the Mac. A dock or a small
# USB-C charger can cap the power an M5 Pro/Max needs under load, which looks
# like throttling. Logged on the photo card; warns under 60W (base chips), 70W (Pro)
# or 96W (Max/Ultra), about what Apple ships with each. Desktops skip it.
att_power_check() {
  [[ -n $ATT_POWER_CHECKED ]] && return 0; ATT_POWER_CHECKED=1
  sysctl -n hw.model 2>/dev/null | grep -qi book || [[ -n $(pmset -g batt 2>/dev/null | grep -i InternalBattery) ]] || return 0
  local w src
  w=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Wattage/{print $2; exit}')
  src=$(pmset -g batt 2>/dev/null | head -1 | sed "s/.*'\(.*\)'.*/\1/")
  if [[ $src != "AC Power" ]]; then
    print "!! On battery. Plug in Apple's charger straight into the Mac (not a dock) and start again."
    ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }WARNING on battery"; return 0
  fi
  # minimum = a bit under the charger Apple ships with that class of chip
  # (Apple's own chargers report a few watts under the label: the stock 96W shows 94W)
  local chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null) min=55
  [[ $chip == *Pro* ]] && min=65
  [[ $chip == *Max* ]] && min=90
  [[ $chip == *Ultra* ]] && min=90
  print "Power: charger ${w:-?}W"
  ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }charger ${w:-?}W"
  if [[ -n $w ]] && (( w < min )); then
    print "!! Only ${w}W reaching the Mac (a dock or small charger?). This chip should have ${min}W or more: use its own Apple charger straight into the Mac."
    ATT_COOL_NOTE="${ATT_COOL_NOTE}; WARNING under ${min}W"
  fi
}

# ATT pause background: freezes macOS's Photos/Spotlight/Siri scanners during a test
# (kill -STOP, no password) and wakes them again when the script ends (kill -CONT).
# These run as your user and start scanning whenever the Mac looks idle, which
# is exactly when a long render runs. Skip with NOPAUSE=1.
# If a test is force-quit and they stay frozen: zsh Tools/att-resume-bg.zsh (or restart).
ATT_BG_PROCS=(mediaanalysisd photoanalysisd photolibraryd cloudphotod corespotlightd mdworker_shared mdworker
  textunderstandingd duetexpertd suggestd knowledgeconstructiond searchpartyd)
ATT_BG_ROOT=(mds mds_stores)   # Spotlight's main indexer runs as root: paused only if sudo is already unlocked
att_pause_bg() {
  [[ $NOPAUSE == 1 ]] && return 0
  [[ -n $ATT_BG_PAUSED ]] && return 0
  local p pids; typeset -ga ATT_BG_PIDS; ATT_BG_PIDS=()
  for p in $ATT_BG_PROCS; do
    pids=($(pgrep -x -U $UID "$p" 2>/dev/null))
    (( ${#pids} )) && kill -STOP $pids 2>/dev/null && ATT_BG_PIDS+=($pids)
  done
  ATT_BG_ROOT_PAUSED=""
  if sudo -n true 2>/dev/null; then
    for p in $ATT_BG_ROOT; do sudo -n pkill -STOP -x "$p" 2>/dev/null && ATT_BG_ROOT_PAUSED=1; done
  fi
  ATT_BG_PAUSED=1
  (( ${#ATT_BG_PIDS} )) && print "Paused Photos/Spotlight/Siri scanning for the test${ATT_BG_ROOT_PAUSED:+ (Spotlight indexer too)} (wakes back up when it ends)."
}
att_resume_bg() {
  [[ -z $ATT_BG_PAUSED ]] && return 0
  local p
  (( ${#ATT_BG_PIDS} )) && kill -CONT $ATT_BG_PIDS 2>/dev/null
  for p in $ATT_BG_PROCS; do pkill -CONT -x -U $UID "$p" 2>/dev/null; done
  [[ -n $ATT_BG_ROOT_PAUSED ]] && for p in $ATT_BG_ROOT; do sudo -n pkill -CONT -x "$p" 2>/dev/null; done
  ATT_BG_PAUSED=""
}
# zsh runs an EXIT trap set inside a function as soon as that function returns,
# so the wake-up trap is set here, when the test script loads this file.
trap 'att_resume_bg' EXIT
trap 'att_resume_bg; exit 130' INT TERM HUP

# Every cooldown is also saved to Results/<Mac>/cooldowns.csv (date, time, test, waited s, result)
att_cool_log() {   # $1 waited seconds, $2 result
  local r=${ROOT:-$HOME/Downloads/Adam Talks Tech Tests}
  local mac=$(scutil --get ComputerName 2>/dev/null)
  local f="$r/Results/${mac:-this Mac}/cooldowns.csv"
  mkdir -p "${f:h}" 2>/dev/null || return 0
  [[ -f $f ]] || print "Date,Time,Test script,Waited (s),Result" > "$f"
  print "$(date +%F),$(date +%H:%M:%S),${ZSH_ARGZERO:t},$1,$2" >> "$f"
}

# ATT cooldown gate: waits until the Mac is cool and idle before a test starts.
#  - macOS heat level must read Nominal (notifyutil, no password needed)
#  - CPU must be quiet (all processes under ~1.5 cores combined (Spotlight etc. can idle along)) for QUIET seconds
#  - plus an optional fixed rest first: COOL=300 zsh blender-bench.sh
#  Skip it with NOCOOL=1. Gives up after 10 min and says so (logged as a warning).
att_cooldown() {
  local again=0; [[ $1 == --again ]] && again=1
  (( again )) || att_quit_apps
  att_power_check
  att_pause_bg
  [[ $NOCOOL == 1 ]] && { print "Cooldown check skipped (NOCOOL=1)."; return 0; }
  local rest=${COOL:-0} need=${QUIET:-60} quiet=0 waited=0 lvl load name
  (( again )) && rest=0
  if (( rest > 0 )); then print "Resting ${rest}s before the test (COOL=$rest)..."; sleep $rest; fi
  print -n "Cooldown check: waiting for Nominal heat + ${need}s of idle CPU"
  while (( waited < 600 )); do
    lvl=$(notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | awk '{print $NF}')
    load=$(ps -A -o %cpu= | awk '{s+=$1} END {printf "%d", s}')
    if [[ ${lvl:-0} == 0 ]] && (( load < 150 )); then (( quiet += 5 )); else quiet=0; fi
    (( quiet >= need )) && { print "\nCool and idle. Starting (waited ${waited}s)."; ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }cooldown ok after ${waited}s"; att_cool_log $waited ok; return 0; }
    print -n "."; sleep 5; (( waited += 5 ))
  done
  case ${lvl:-0} in 0) name=Nominal;; 1) name=Moderate;; 2) name=Heavy;; *) name="level $lvl";; esac
  print "\n!! Still not cool/idle after 10 min (heat: $name, CPU load ${load}%). Starting anyway; note it in the results."
  ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }WARNING not cool after 10 min (heat $name, load ${load}%)"
  att_cool_log $waited "gave up (heat $name, load ${load}%)"
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

# ---------- fan speeds (v1, Nov 20 2026) ----------
# Fan RPM comes from the Mac's fan controller (SMC) through Tools/att-fans.c.
# Uses Tools/att-fans-bin if it's there (no Xcode needed). Otherwise builds it once into
# ~/.att/att-fans (needs Xcode or the Command Line Tools) and leaves a copy in Tools + on the drives.
#   att_fans_start <log>   logs "unix-time rpm rpm..." every 5 s in the background
#   att_fans_stop
#   att_fans_report <log>  -> "Fans: avg 2,140 / max 3,880 RPM (2 fans, spec max 5,700)"
ATT_FANS_BIN=$HOME/.att/att-fans
ATT_TOOLS_DIR=${${(%):-%x}:A:h}   # set while this file is being sourced
att_fans_bin() {
  [[ -x $ATT_FANS_BIN ]] && { print $ATT_FANS_BIN; return 0; }
  mkdir -p ${ATT_FANS_BIN:h}
  # 1) a ready-made copy in Tools (no Xcode needed): built once on any Mac with Xcode
  local pre="$ATT_TOOLS_DIR/att-fans-bin"
  if [[ -f $pre ]]; then
    cp "$pre" $ATT_FANS_BIN && chmod +x $ATT_FANS_BIN && xattr -c $ATT_FANS_BIN 2>/dev/null
    $ATT_FANS_BIN >/dev/null 2>&1 && { print $ATT_FANS_BIN; return 0; }
    rm -f $ATT_FANS_BIN
  fi
  # 2) build it (needs Xcode or the Command Line Tools)
  local src="$ATT_TOOLS_DIR/att-fans.c"
  [[ -f $src ]] || return 1
  xcode-select -p >/dev/null 2>&1 || return 1      # no compiler: don't trigger the install pop-up
  cc -O2 -framework IOKit "$src" -o $ATT_FANS_BIN 2>/dev/null || return 1
  # leave a ready-made copy in Tools and on any plugged-in test drive, so Macs without Xcode can use it
  cp $ATT_FANS_BIN "$pre" 2>/dev/null
  local d; for d in /Volumes/*/"Adam Talks Tech Tests"/Tools(N/); do cp $ATT_FANS_BIN "$d/att-fans-bin" 2>/dev/null; done
  print $ATT_FANS_BIN
}
att_fans_start() {
  ATT_FANS_LOG=$1; ATT_FANS_PID=""
  local bin; bin=$(att_fans_bin) || { : > "$ATT_FANS_LOG"; print "nobin" > "$ATT_FANS_LOG.status"; return 1; }
  local n=$("$bin" | awk '{print $1}')
  print "fans=${n:-0} spec=$("$bin" -m | cut -d' ' -f2-)" > "$ATT_FANS_LOG.status"
  (( ${n:-0} > 0 )) || { : > "$ATT_FANS_LOG"; return 0; }
  "$bin" -i 5 > "$ATT_FANS_LOG" 2>/dev/null &
  ATT_FANS_PID=$!
}
att_fans_stop() { [[ -n $ATT_FANS_PID ]] && { kill $ATT_FANS_PID 2>/dev/null; wait $ATT_FANS_PID 2>/dev/null; }; ATT_FANS_PID=""; }
att_fans_report() {   # one line for the card; FANS_AVG / FANS_MAX left set for the CSV
  local log=$1 st; FANS_AVG=""; FANS_MAX=""
  st=$(<"$log.status" 2>/dev/null)
  [[ $st == nobin* || -z $st ]] && { print "Fans: not logged (no fan reader on this Mac yet, see Tools/att-fans.zsh)"; return; }
  [[ $st == fans=0* ]] && { print "Fans: none (fanless Mac)"; FANS_AVG=0; FANS_MAX=0; return; }
  [[ -s $log ]] || { print "Fans: no readings"; return; }
  local out=$(awk '{ for(i=2;i<=NF;i++){ if($i<0) continue; s+=$i; c++; if($i>m)m=$i } if(NF>1) t++ }
       END { if(c) printf "%d %d %d", s/c, m, t*5 }' "$log")
  local a mx secs; read a mx secs <<< "$out"
  [[ -z $a ]] && { print "Fans: no readings"; return; }
  FANS_AVG=$a; FANS_MAX=$mx
  local nf=${${st#fans=}%% *} spec=${st#*spec=}
  local top=$(print -l ${(s: :)spec} | cut -d- -f2 | sort -n | tail -1)
  print "Fans: avg $(printf "%'d" $a) / max $(printf "%'d" $mx) RPM ($nf fan$([[ $nf != 1 ]] && print s), spec max $(printf "%'d" ${top:-0}))"
}

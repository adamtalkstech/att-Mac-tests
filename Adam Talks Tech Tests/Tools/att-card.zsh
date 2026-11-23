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
# Run Order step for this test (rule, Adam Nov 21 2026: every test says its Run Order number).
# $1 = script file name, $2 = the test's first argument
att_step_for() {
  local s=${1:t} a=${(L)2}
  case $s in
    xcode-bench.sh) print 8 ;;
    blender-bench.sh) [[ $a == redautumn ]] && print 9b || print 9 ;;
    sustained-test.sh) print 10 ;;
    handbrake-bench.zsh) print 11 ;;
    att-puget.zsh) print 12 ;;
    att-logic-log.zsh) print 13 ;;
    lmstudio-bench.sh) case $a in qwen9b) print 14a;; qwen27b) print 14b;; gemma) print 14c;; ladder) print 14d;; *) print E4;; esac ;;
    att-bandwidth.zsh) print 14e ;;
    att-stacker.zsh) print 17 ;;
    att-responsiveness.zsh) print 17b ;;
    att-appmem.zsh) print 17c ;;
    att-realday.zsh) print 17d ;;
    att-drawthings.zsh) print 18 ;;
    att-fcp-neural.zsh) print 19 ;;
    att-tabtest.zsh) print E5 ;;
    att-export-timer.zsh) print E6 ;;
    att-versions.zsh) print 4 ;;
    att-name-this-mac.zsh) print 3 ;;
    att-install-apps.zsh) print 3b ;;
    att-queue.zsh) print "B (queue)" ;;
    att-cinebench.zsh) print 7 ;;
    att-ssd-internal.zsh) print 20 ;;
    att-idle.zsh) print 17e ;;
    att-displays.zsh) print 17f ;;
    att-ready.zsh) case $a in *geekbench*) print 6;; *cinebench*) print 7;; *logic*) print 13;; *cyberpunk*) print 15;; *thunder*) print 16;; *) print "C (hands-on)";; esac ;;
    *) print "" ;;
  esac
}
ATT_STEP=${ATT_STEP_OVERRIDE:-$(att_step_for "$ZSH_ARGZERO" "$1")}   # a test called from another (stacker -> export timer) passes its own step
att_card_start() {
  local mac=$(scutil --get ComputerName 2>/dev/null)
  local chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  local ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  local os="$(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
  print ""
  print "#################### PHOTO THIS FOR CLAUDE ####################"
  print "TEST:  $*"
  [[ -n $ATT_STEP ]] && print "STEP:  Run Order step $ATT_STEP"
  local want=$(head -1 "$ATT_TOOLS_DIR/target-macos.txt" 2>/dev/null | tr -d '[:space:]') have=$(sw_vers -productVersion 2>/dev/null)
  [[ -n $want && -n $have && $have != $want ]] && print "!!     macOS $have is NOT the batch version $want: update this Mac before logging"
  print "MAC:   $mac"
  print "       $(att_mac_kind)"
  print "       $chip | ${ram}GB | macOS $os"
  print "DATE:  $(date '+%b %d %Y  %I:%M %p %Z')"
  [[ -n $ATT_COOL_NOTE ]] && print "START: $ATT_COOL_NOTE"
  print -r -- "---------------------------------------------------------------"
}
# Auto-logging (Nov 22): one line per sheet cell. The receiver puts the value in this Mac's row
# (Mac Map tab), keeps the old value in the cell's note and lists it in the Auto Log tab.
# A card with WARM-UP / don't log / NOT CLEAN / a line starting !! is held, not written.
att_log() { print -r -- "LOG | $1 | $2 | $3"; }
att_card_end() {
  print "###############################################################"
  print "(Make the window tall enough that the whole box shows in the photo.)"
  print ""
}

# ATT quit-apps: politely quits every other app + common background helpers before a test.
#  Keeps Terminal/Finder (TextEdit is quit too since Nov 20: it shows in the results) (and anything in ATT_KEEP, e.g. ATT_KEEP="LM Studio").
#  Polite quit only: an app with unsaved work asks you first and stays open.
#  Skip it with NOQUIT=1.
ATT_HELPERS=("Creative Cloud" "Adobe Creative Cloud" "Dropbox" "Google Drive" "OneDrive" "Backblaze" "Spotify" "Discord" "Slack" "zoom.us" "Microsoft Teams" "Steam" "Logi Options+" "Elgato Stream Deck" "Stream Deck" "Docker Desktop" "Music" "Photos" "Mail" "Messages" "Epic Games Launcher" "EpicGamesLauncher" "EpicWebHelper" "Battle.net" "Adobe Desktop Service" "CCXProcess")
# Nov 22 (Adam: "Logic or stuff getting stuck open"): close an app the TEST opened, for real.
#  Asks it to quit without saving, presses Don't Save on any save box, waits up to 30 s
#  (Logic's 600-track project is slow to close), then force-quits. Test files are never
#  saved, so nothing is lost. Use only for apps the test itself opened.
att_quit_hard() { local a=$1 w=0
  [[ -z $a ]] && return 0
  pgrep -xq "$a" || return 0
  osascript -e "tell application \"$a\" to quit saving no" >/dev/null 2>&1 || osascript -e "tell application \"$a\" to quit" >/dev/null 2>&1
  while pgrep -xq "$a" && (( w < 30 )); do
    (( w % 5 == 2 )) && att_dont_save "$a"
    sleep 1; (( w++ )); done
  if pgrep -xq "$a"; then pkill -x "$a" 2>/dev/null; sleep 2; pgrep -xq "$a" && pkill -9 -x "$a" 2>/dev/null; print "  forced $a closed"; fi
  [[ $a == Final\ Cut* ]] && pgrep -f "Final Cut[^/]*\.app/Contents/MacOS/" >/dev/null && pkill -9 -f "Final Cut[^/]*\.app/Contents/MacOS/" 2>/dev/null
  return 0; }
att_dont_save() {   # clicks Don't Save / Delete / Don't Quit-safe buttons on a save box, if one is up
  osascript >/dev/null 2>&1 <<OSA
tell application "System Events" to tell process "$1"
  repeat with w in windows
    try
      repeat with b in (buttons of sheet 1 of w & buttons of w)
        if name of b is in {"Don’t Save", "Don't Save", "Delete", "Don’t Save All", "Discard Changes"} then click b
      end repeat
    end try
  end repeat
end tell
OSA
}
# A stuck app is safe to force-quit when the only thing open in it is a test file (or nothing).
ATT_TEST_DOCS='NewLogicBenchmark|ATT Stack Test|Test Library|Untitled|Choose a Project|Project Chooser|Welcome|What.s New'
att_only_test_docs() { local n=$1 wins
  wins=$(osascript -e "tell application \"System Events\" to get name of every window of process \"$n\"" 2>/dev/null)
  [[ -z $wins ]] && return 0
  local w; for w in ${(s:, :)wins}; do [[ $w =~ "($ATT_TEST_DOCS)" ]] || [[ $w == "$n" ]] || return 1; done
  return 0; }

att_quit_apps() {
  [[ $NOQUIT == 1 ]] && { print "Quitting other apps skipped (NOQUIT=1)."; return 0; }
  local -a keep names ids closed stuck
  ATT_COOL_NOTE=""
  keep=("Terminal" "iTerm2" "Ghostty" "Warp" "Finder" ${(s:,:)ATT_KEEP})
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
  # Nov 21: wait up to 20 s for slow quitters, then force-quit the ones that never hold unsaved
  # work (TV and the responsiveness test apps kept staying open and showing up on cards).
  local w=0
  while (( w < 20 )); do stuck=(); for n in $closed; do pgrep -xq "$n" && stuck+=("$n"); done
    (( ${#stuck} )) || break; sleep 2; (( w += 2 )); done
  local -a safe=("TV" "Music" "Podcasts" "News" "Stocks" "Weather" "Calculator" "Chess" "Dictionary" "Font Book"
    "Activity Monitor" "Photo Booth" "Maps" "Clock" "Draw Things" "LM Studio" "DiffusionBee" "Safari" "Preview"
    "App Store" "System Settings" "Steam" "Spotify" "Discord" "Slack" "Messages" "Mail" "Photos" "Calendar" "Reminders" ${ATT_HELPERS[@]})
  local -a still=()
  for n in $stuck; do
    if (( ${safe[(Ie)$n]} )); then pkill -x "$n" 2>/dev/null; sleep 1; pgrep -xq "$n" && pkill -9 -x "$n" 2>/dev/null; print "Force-quit $n (wouldn't close; nothing to save)."
    elif att_only_test_docs "$n"; then att_quit_hard "$n"; print "Force-quit $n (only test files were open in it)."
    else still+=("$n"); fi
  done
  stuck=($still)
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
ATT_BG_ROOT=(mds mds_stores kernelmanager_helper XprotectService)   # root: paused only if sudo is already unlocked
# Nov 22 (Adam: pause the verifying): macOS's extension checker (kernelmanager_helper) and XProtect's
# background malware scans (XprotectService + the XProtectRemediator* scanners) are paused too.
# NOT paused: syspolicyd (the "Verifying <app>..." on first launch) -- pausing it would freeze
# every app a test opens (Final Cut, Logic, Safari), so first launches still go through att-prime.
att_pause_bg() {
  [[ $NOPAUSE == 1 ]] && return 0
  [[ -n $ATT_BG_PAUSED ]] && return 0
  # A test started from another test (export timer inside the stacker) leaves the
  # pause to the outer one, so it can't wake things up halfway through.
  [[ -n $ATT_BG_PARENT && $ATT_BG_PARENT != $$ ]] && kill -0 $ATT_BG_PARENT 2>/dev/null && return 0
  local p pids; typeset -ga ATT_BG_PIDS; ATT_BG_PIDS=()
  for p in $ATT_BG_PROCS; do
    pids=($(pgrep -x -U $UID "$p" 2>/dev/null))
    (( ${#pids} )) && kill -STOP $pids 2>/dev/null && ATT_BG_PIDS+=($pids)
  done
  ATT_BG_ROOT_PAUSED=""
  if sudo -n true 2>/dev/null; then
    for p in $ATT_BG_ROOT; do sudo -n pkill -STOP -x "$p" 2>/dev/null && ATT_BG_ROOT_PAUSED=1; done
    sudo -n pkill -STOP -f "XProtectRemediator" 2>/dev/null
  fi
  ATT_BG_PAUSED=1; export ATT_BG_PARENT=$$
  (( ${#ATT_BG_PIDS} )) && print "Paused Photos/Spotlight/Siri scanning for the test${ATT_BG_ROOT_PAUSED:+ (Spotlight indexer, extension checker + XProtect scans too)} (wakes back up when it ends)."
}
att_resume_bg() {
  [[ -z $ATT_BG_PAUSED ]] && return 0
  local p
  (( ${#ATT_BG_PIDS} )) && kill -CONT $ATT_BG_PIDS 2>/dev/null
  for p in $ATT_BG_PROCS; do pkill -CONT -x -U $UID "$p" 2>/dev/null; done
  [[ -n $ATT_BG_ROOT_PAUSED ]] && for p in $ATT_BG_ROOT; do sudo -n pkill -CONT -x "$p" 2>/dev/null; done
  [[ -n $ATT_BG_ROOT_PAUSED ]] && sudo -n pkill -CONT -f "XProtectRemediator" 2>/dev/null
  ATT_BG_PAUSED=""
}
# zsh runs an EXIT trap set inside a function as soon as that function returns,
# so the wake-up trap is set here, when the test script loads this file.
# Copy this Mac's results onto any plugged-in test drive (Results/<Mac name>), so
# Claude can read them on the Mac Studio without photos. Runs when a test ends.
att_sync_results() {
  [[ -n $ATT_NOSYNC ]] && return 0
  [[ -n $ATT_BG_PARENT && $ATT_BG_PARENT != $$ ]] && kill -0 $ATT_BG_PARENT 2>/dev/null && return 0   # the outer test syncs
  local root=${ATT_TOOLS_DIR:h} mac d n=0
  [[ $root == /Volumes/* ]] && return 0
  mac=$(scutil --get ComputerName 2>/dev/null); [[ -d "$root/Results/$mac" ]] || return 0
  for d in /Volumes/*/"Adam Talks Tech Tests"/Results(N/); do
    mkdir -p "$d/$mac" && rsync -a "$root/Results/$mac/" "$d/$mac/" 2>/dev/null && (( n++ ))
  done
  (( n )) && print "Results copied to the plugged-in drive(s): Results/$mac"
  return 0
}
# Send new result files to the Mac Tests sheet + Drive (Tools/att-upload.zsh; does nothing until
# this Mac is set up with att-upload.zsh setup; NOUPLOAD=1 skips it)
ATT_TEST_NAME="${ZSH_ARGZERO:t}${1:+ $1}"
att_upload_results() {
  [[ -n $NOUPLOAD || ! -s $HOME/.att/upload.conf ]] && return 0
  local root=${ATT_TOOLS_DIR:h}; [[ $root == /Volumes/* ]] && return 0
  zsh "$ATT_TOOLS_DIR/att-upload.zsh" auto "$ATT_TEST_NAME" 2>/dev/null
  return 0
}
# Nov 21: refresh this Mac's RUN THIS NEXT list after every test, so finished steps show ✓ right away
# (inside a walk-away queue it only rewrites the file; the queue opens it at the end).
att_refresh_next() {
  [[ -f "$ATT_TOOLS_DIR/att-next.zsh" ]] || return 0
  [[ ${ZSH_ARGZERO:t} == att-next.zsh || ${ZSH_ARGZERO:t} == att-update.zsh ]] && return 0
  # rewrite the file only: popping TextEdit open here would cover the card you need to photo
  NOOPEN=1 zsh "$ATT_TOOLS_DIR/att-next.zsh" >/dev/null 2>&1
  return 0
}
trap 'att_resume_bg; att_sync_results; att_upload_results; att_refresh_next' EXIT
trap 'att_resume_bg; att_sync_results; att_upload_results; exit 130' INT TERM HUP

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
  local rest=${COOL:-0} need=${QUIET:-60} quiet=0 waited=0 lvl load name kmh
  (( again )) && rest=0
  # Refresh the password from THIS shell during the rest and the wait (Nov 21 fix): a keep-alive
  # running in a background subshell doesn't always count on macOS, so the password expired
  # during the 10-min rest and sustained asked again mid-test.
  if (( rest > 0 )); then print "Resting ${rest}s before the test (COOL=$rest)..."
    local slept=0; while (( slept < rest )); do sleep 30; (( slept += 30 )); sudo -n -v 2>/dev/null; done; fi
  print -n "Cooldown check: waiting for Nominal heat + ${need}s of idle CPU (and macOS's extension checker quiet)"
  while (( waited < 600 )); do
    lvl=$(notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null | awk '{print $NF}')
    load=$(ps -A -o %cpu= | awk '{s+=$1} END {printf "%d", s}')
    # macOS's extension checker (kernelmanager_helper / kernelmanagerd) slowed many runs on Nov 21:
    # wait until it's quiet too (under 10% of a core), not just total load.
    kmh=$(ps -A -o %cpu=,comm= | awk '/kernelmanager/ {s+=$1} END {printf "%d", s}')
    if [[ ${lvl:-0} == 0 ]] && (( load < 150 && kmh < 10 )); then (( quiet += 5 )); else quiet=0; fi
    (( quiet >= need )) && { print "\nCool and idle. Starting (waited ${waited}s)."; ATT_COOL_NOTE="${ATT_COOL_NOTE:+$ATT_COOL_NOTE; }cooldown ok after ${waited}s"; att_cool_log $waited ok; return 0; }
    print -n "."; sleep 5; (( waited += 5 )); (( waited % 30 == 0 )) && sudo -n -v 2>/dev/null
    # Every minute it's still waiting, say what's busy so it's not a mystery
    if (( waited % 60 == 0 )); then
      print -n "\n  still waiting ($(( waited / 60 )) min): CPU load ${load}%, busiest: $(ps -A -o %cpu=,comm= | sort -rn | head -3 | awk '{n=$NF; sub(".*/","",n); printf "%s %d%%  ", n, $1}')"
      print -n "\n  "
    fi
  done
  case ${lvl:-0} in 0) name=Nominal;; 1) name=Moderate;; 2) name=Heavy;; *) name="level $lvl";; esac
  print "\n!! Still not cool/idle after 10 min (heat: $name, CPU load ${load}%). Starting anyway; note it in the results."
  print "   Busiest right now: $(ps -A -o %cpu=,comm= | sort -rn | head -5 | awk '{n=$NF; sub(".*/","",n); printf "%s %d%%  ", n, $1}')"
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

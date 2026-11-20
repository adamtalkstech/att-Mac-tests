#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  att-versions.zsh  -  ATT version card (v1, Nov 16 2026)
# =============================================================================
#  Prints this Mac's details and the version of every test app in one go,
#  so the sheet's macOS / versions columns can be filled without clicking
#  through About windows. Also checks the "lock versions" rules from the
#  Nov 12 audit (auto updates off, power, Low Power Mode).
#
#  Run:   zsh att-versions.zsh            (or drag the file into Terminal)
#         zsh att-versions.zsh "PROLED"   (optional label, else the Mac's name)
#
#  Saves to Results/<Mac name> in the test folder:
#     versions_<label>_<date>.txt   the card (paste it to Claude)
#     Results/All Macs versions.csv one row per run, every Mac, for the sheet
#  Nothing is installed or changed. No password needed.
# =============================================================================

# ---------- Where am I? ----------
# Works from ~/Downloads/Adam Talks Tech Tests or straight from the LaCie.
# Results go to <test folder>/Results/<Mac name>/ next to everything else.
SCRIPT_DIR=${0:A:h}
ROOT=$SCRIPT_DIR
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=$SCRIPT_DIR
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}
LABEL="${1:-$MACNAME}"
OUTDIR="$ROOT/Results/$LABEL"
mkdir -p "$OUTDIR"
STAMP=$(date +%Y-%m-%d_%H%M)
SAFE=${LABEL//[^A-Za-z0-9._-]/_}
CARD="$OUTDIR/versions_${SAFE}_${STAMP}.txt"
CSV="$ROOT/Results/All Macs versions.csv"

# ---------- Mac ----------
MODEL=$(sysctl -n hw.model)
CHIP=$(sysctl -n machdep.cpu.brand_string)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
NLEVELS=$(sysctl -n hw.nperflevels 2>/dev/null)
CORES=""
for (( l = 0; l < ${NLEVELS:-0}; l++ )); do
  n=$(sysctl -n hw.perflevel$l.physicalcpu 2>/dev/null)
  nm=$(sysctl -n hw.perflevel$l.name 2>/dev/null); [[ -z $nm ]] && nm="tier$l"
  [[ -n $n ]] && CORES+="${CORES:+ + }$n $nm"
done
[[ -z $CORES ]] && CORES="$(sysctl -n hw.physicalcpu) cores"
GPU=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Total Number of Cores/{print $2; exit}')
MACOS="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
DISK_TOTAL=$(df -g / | awk 'NR==2{print $2}')
DISK_FREE=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
POWER=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")
LOWPOWER=$(pmset -g | awk '/lowpowermode/ {print $2}')
AUTO_MAC=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null)
AUTO_DL=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null)
AUTO_APPS=$(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null)

# ---------- App versions ----------
# Finds each app in /Applications (and one folder down, for Adobe/Blackmagic
# folders) and reads its version from the app itself.
app_version() {
  local pattern=$1 app v
  app=$(find /Applications /Applications/Utilities "$HOME/Applications" -maxdepth 2 -iname "$pattern" -type d 2>/dev/null | head -1)
  [[ -z $app ]] && { print -r -- "not installed"; return; }
  v=$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)
  local b=$(defaults read "$app/Contents/Info" CFBundleVersion 2>/dev/null)
  [[ -n $b && $b != $v ]] && v="$v ($b)"
  print -r -- "${v:-installed, version unknown}"
}

typeset -a NAMES PATTERNS
add() { NAMES+=("$1"); PATTERNS+=("$2"); }
add "Xcode"                      "Xcode.app"
add "Final Cut Pro"              "Final Cut Pro.app"
add "Compressor"                 "Compressor.app"
add "Logic Pro"                  "Logic Pro*.app"
add "Lightroom Classic"          "Adobe Lightroom Classic.app"
add "Photoshop"                  "Adobe Photoshop*.app"
add "Premiere Pro"               "Adobe Premiere Pro*.app"
add "After Effects"              "Adobe After Effects*.app"
add "DaVinci Resolve"            "DaVinci Resolve.app"
add "PugetBench for Creators"    "PugetBench*.app"
add "Blender"                    "Blender.app"
add "Cinebench"                  "Cinebench*.app"
add "Geekbench 7"                "Geekbench 7.app"
add "Geekbench AI"               "Geekbench AI.app"
add "Blackmagic Disk Speed Test" "Blackmagic Disk Speed Test.app"
add "Blackmagic RAW Speed Test"  "Blackmagic RAW Speed Test.app"
add "AJA System Test Lite"       "AJA System Test*.app"
add "LM Studio"                  "LM Studio.app"
add "Diffusion Bee"              "DiffusionBee.app"
add "Draw Things"                "Draw Things*.app"
add "Numbers"                    "Numbers.app"
add "Safari"                     "Safari.app"
add "Steam"                      "Steam.app"
add "Minecraft Launcher"         "Minecraft*.app"
add "HandBrake"                  "HandBrake.app"
add "TG Pro"                     "TG Pro.app"
add "Stats"                      "Stats.app"

typeset -a VERS
for (( i = 1; i <= ${#NAMES}; i++ )); do VERS+=("$(app_version "${PATTERNS[$i]}")"); done

# Command line tools the scripts use (only listed if present)
LMS_CLI=$("$HOME/.lmstudio/bin/lms" version 2>/dev/null | head -1)
BREW=$(command -v brew >/dev/null && brew --version 2>/dev/null | head -1)
LLAMA=$(command -v llama-bench >/dev/null && llama-bench --version 2>&1 | head -1)
CYBERPUNK=""
for f in "${ROOT:h}/Adam Talks Tech Games/Steam Library/steamapps/appmanifest_1091500.acf"(N) "$HOME/Downloads/Adam Talks Tech Games/Steam Library/steamapps/appmanifest_1091500.acf"(N) /Volumes/*/"Adam Talks Tech Games"/"Steam Library"/steamapps/appmanifest_1091500.acf(N) "$ROOT/Gaming Test/Steam Library/steamapps/appmanifest_1091500.acf"(N) /Volumes/*/appmanifest_1091500.acf(N) /Volumes/*/steamapps/appmanifest_1091500.acf(N) "$HOME/Library/Application Support/Steam/steamapps/appmanifest_1091500.acf"; do
  [[ -f $f ]] && { CYBERPUNK=$(awk -F'"' '/"buildid"/{print "Steam build " $4; exit}' "$f"); break; }
done

# ---------- Card ----------
att_card_start "Version card"
{
  print "ATT VERSION CARD  -  $(date '+%b %d %Y %I:%M %p')"
  print "======================================================"
  print "Mac name:   $LABEL"
  print "Model:      $MODEL"
  print "Chip:       $CHIP  ($CORES)${GPU:+, ${GPU}-core GPU}"
  print "RAM:        ${RAM_GB}GB"
  print "SSD:        ${DISK_TOTAL}GB, ${DISK_FREE}GB free"
  print "macOS:      $MACOS"
  print "Power:      $POWER$([[ $LOWPOWER == 1 ]] && print -n '  !! LOW POWER MODE ON')"
  print ""
  print "APPS"
  for (( i = 1; i <= ${#NAMES}; i++ )); do
    [[ ${VERS[$i]} == "not installed" ]] && continue
    printf "  %-28s %s\n" "${NAMES[$i]}" "${VERS[$i]}"
  done
  [[ -n $CYBERPUNK ]] && printf "  %-28s %s\n" "Cyberpunk 2077" "$CYBERPUNK"
  [[ -n $LMS_CLI ]]   && printf "  %-28s %s\n" "lms (LM Studio CLI)" "$LMS_CLI"
  [[ -n $LLAMA ]]     && printf "  %-28s %s\n" "llama-bench" "$LLAMA"
  print ""
  print "NOT INSTALLED"
  miss=""
  for (( i = 1; i <= ${#NAMES}; i++ )); do
    [[ ${VERS[$i]} == "not installed" ]] && miss+="${miss:+, }${NAMES[$i]}"
  done
  print "  ${miss:-none}"
  print ""
  print "LOCK-VERSIONS CHECK (turn auto updates off during test week)"
  [[ $AUTO_MAC == 1 ]]  && print "  !! macOS auto install is ON (System Settings > General > Software Update > Automatic Updates)" || print "  ok macOS auto install off"
  [[ $AUTO_APPS == 1 ]] && print "  !! App Store app auto updates are ON" || print "  ok App Store auto updates off"
  [[ -d "/Applications/Utilities/Adobe Creative Cloud" ]] && print "  -- Creative Cloud: check Preferences > Apps > Auto-update is off (can't be read from here)"
  [[ $POWER != "AC Power" ]] && print "  !! Not on AC power"
} | tee "$CARD"
att_card_end

# ---------- CSV (one row per run, all Macs) ----------
if [[ ! -f $CSV ]]; then
  { printf "Date,Mac name,Model,Chip,Cores,GPU cores,RAM GB,SSD GB,Free GB,macOS"
    for n in $NAMES; do printf ",%s" "$n"; done
    printf ",Cyberpunk\n"; } > "$CSV"
fi
{ printf '%s,"%s",%s,"%s","%s",%s,%s,%s,%s,"%s"' "$(date +%F)" "$LABEL" "$MODEL" "$CHIP" "$CORES" "$GPU" "$RAM_GB" "$DISK_TOTAL" "$DISK_FREE" "$MACOS"
  for v in "${VERS[@]}"; do printf ',"%s"' "$v"; done
  printf ',"%s"\n' "$CYBERPUNK"; } >> "$CSV"

print ""
print "Saved: $CARD"
print "Added a row to: $CSV"

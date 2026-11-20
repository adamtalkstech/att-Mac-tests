#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# ATT Xcode build benchmark  -  v2.2 (Nov 16 2026: M6 core tiers; results in the test folder)
#
# Usage:  zsh xcode-bench.sh [path to XcodeBenchmark-master folder]
# If no path is given it looks next to this script first, then ~/Downloads.
#
# What it does:
#  - 3 clean builds of XcodeBenchmark, 30 second cooldown between runs
#  - Logs two times per run: our stopwatch time (what's in the sheet) and
#    Xcode's own "BUILD SUCCEEDED [x sec]" time (what the public leaderboard uses)
#  - Fails a run if xcodebuild errors, Xcode reports no time, or the build
#    finishes under 30 seconds (catches the fake 0.27s runs)
#  - Pre-flight: warns on battery power, Low Power Mode, Wi-Fi on
#  - Fresh build folder every run, named .noindex so Spotlight skips it

# ---------- Where am I? ----------
# Works from ~/Downloads/Adam Talks Tech Tests or straight from the LaCie.
# Results go to <test folder>/Results/<Mac name>/ next to everything else.
ROOT=${0:A:h}
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=${0:A:h}
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

RUNS=3
COOLDOWN=30
MIN_SECS=30

SCRIPT_DIR="${0:A:h}"
if [[ -n "$1" ]]; then
  BENCH_DIR="${1:A}"
elif [[ -d "$SCRIPT_DIR/XcodeBenchmark-master" ]]; then
  BENCH_DIR="$SCRIPT_DIR/XcodeBenchmark-master"
elif [[ -d "$SCRIPT_DIR/XcodeBenchmark" ]]; then
  BENCH_DIR="$SCRIPT_DIR/XcodeBenchmark"
elif [[ -d "$ROOT/Xcode Test/XcodeBenchmark-master" ]]; then
  BENCH_DIR="$ROOT/Xcode Test/XcodeBenchmark-master"
elif false; then
  BENCH_DIR="$SCRIPT_DIR/XcodeBenchmark"
else
  BENCH_DIR="$HOME/Downloads/XcodeBenchmark-master"
fi
WORKSPACE="$BENCH_DIR/XcodeBenchmark.xcworkspace"

if [[ $BENCH_DIR == /Volumes/* ]]; then
  echo "The Xcode project is on an external drive. Copy the test folder to ~/Downloads"
  echo "first (Tools/att-copy-tests.zsh), or this times the drive instead of the Mac."
  exit 1
fi

if [[ ! -d "$WORKSPACE" ]]; then
  echo "Can't find XcodeBenchmark.xcworkspace in: $BENCH_DIR"
  echo "Put the XcodeBenchmark-master folder next to this script or in Downloads,"
  echo "or run:  zsh xcode-bench.sh /path/to/XcodeBenchmark-master"
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild isn't working. Open Xcode once, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app"
  echo "  sudo xcodebuild -license accept"
  echo "  xcodebuild -runFirstLaunch"
  exit 1
fi

if ! xcodebuild -showsdks 2>/dev/null | grep -q iphoneos; then
  echo "This Xcode doesn't have the iOS platform yet (the test builds an iOS app)."
  echo "Downloading it now (a few GB, one time per Mac)..."
  xcodebuild -downloadPlatform iOS || { echo "Couldn't download it. In Xcode: Settings > Components > iOS, then rerun."; exit 1; }
fi

# ---------- Mac info ----------
MODEL=$(sysctl -n hw.model)
CHIP=$(sysctl -n machdep.cpu.brand_string)
# Core layout: reads every core tier macOS reports, so the M6's three tiers
# (Super / Performance / Efficiency) print correctly instead of "2P + 4E".
NLEVELS=$(sysctl -n hw.nperflevels 2>/dev/null)
CORES=""
for (( l = 0; l < ${NLEVELS:-0}; l++ )); do
  n=$(sysctl -n hw.perflevel$l.physicalcpu 2>/dev/null)
  name=$(sysctl -n hw.perflevel$l.name 2>/dev/null)
  [[ -z $name ]] && name="tier$l"
  [[ -n $n ]] && CORES+="${CORES:+ + }$n $name"
done
[[ -z $CORES ]] && CORES="$(sysctl -n hw.physicalcpu) cores"
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
MACOS="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
XCODE=$(xcodebuild -version | tr '\n' ' ')
POWER=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")
LOWPOWER=$(pmset -g | awk '/lowpowermode/ {print $2}')
WIFI_DEV=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
WIFI=$( [[ -n "$WIFI_DEV" ]] && networksetup -getairportpower "$WIFI_DEV" | awk '{print $NF}' )

echo "================ ATT Xcode Benchmark v2 ================"
echo "Mac:    $MODEL"
echo "Chip:   $CHIP  ($CORES)"
echo "RAM:    ${RAM_GB}GB"
echo "macOS:  $MACOS"
echo "Xcode:  $XCODE"
echo "Power:  $POWER"
echo "Project: $BENCH_DIR"
echo "========================================================"

[[ "$POWER" != "AC Power" ]] && echo "WARNING: not on AC power. Plug in for a fair run."
[[ "$LOWPOWER" == "1" ]] && echo "WARNING: Low Power Mode is on. Turn it off."
[[ "$WIFI" == "On" ]] && echo "Note: Wi-Fi is on. Fine, but other Macs should match."
echo "Close other apps and don't touch the Mac until it's done."
echo ""

defaults write com.apple.dt.Xcode ShowBuildOperationDuration YES >/dev/null 2>&1

LOG_DIR="$ROOT/Results/$MACNAME/Xcode"
mkdir -p "$LOG_DIR"
STAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RESULTS="$LOG_DIR/xcode-bench_${MODEL}_${STAMP}.txt"

att_cooldown
typeset -a WALL XCT
for i in {1..$RUNS}; do
  BUILD_DIR="$BENCH_DIR/DerivedData-run$i.noindex"
  rm -rf "$BUILD_DIR"
  BUILD_LOG="$LOG_DIR/build-run$i.log"

  echo "Run $i of $RUNS..."
  START=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  xcodebuild -workspace "$WORKSPACE" -scheme XcodeBenchmark \
    -destination generic/platform=iOS \
    -derivedDataPath "$BUILD_DIR" \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    build > "$BUILD_LOG" 2>&1
  STATUS=$?
  END=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  rm -rf "$BUILD_DIR"

  SECS=$(printf "%.2f" $(( END - START )))
  XSECS=$(grep -Eo 'BUILD SUCCEEDED \*\* \[[0-9.]+ sec\]' "$BUILD_LOG" | grep -Eo '[0-9.]+' | tail -1)

  if (( STATUS != 0 )); then
    echo "Run $i FAILED: xcodebuild error. Last lines of the log:"
    tail -15 "$BUILD_LOG"
    exit 1
  fi
  if [[ -z "$XSECS" ]]; then
    echo "Run $i FAILED: Xcode didn't report a build time. Log: $BUILD_LOG"
    exit 1
  fi
  if (( SECS < MIN_SECS )); then
    echo "Run $i FAILED: ${SECS}s is too fast to be a real build. Check $BUILD_LOG"
    exit 1
  fi

  WALL+=$SECS
  XCT+=$XSECS
  echo "  Run $i: ${SECS}s stopwatch  |  ${XSECS}s Xcode"

  if (( i < RUNS )); then
    echo "  Cooling down ${COOLDOWN}s..."
    sleep $COOLDOWN
    QUIET=30 att_cooldown --again
  fi
done

stats() {
  local best=$1 sum=0.0 t
  for t in "$@"; do
    (( t < best )) && best=$t
    (( sum += t ))
  done
  printf "%.2f %.2f" $best $(( sum / $# ))
}
read W_BEST W_AVG <<< "$(stats $WALL)"
read X_BEST X_AVG <<< "$(stats $XCT)"
X_ROUND=$(printf "%.0f" $X_BEST)

att_card_start "Xcode build (XcodeBenchmark, 3 clean builds)"
{
  echo "ATT Xcode Benchmark v2  -  $(date)"
  echo "Mac: $MODEL | $CHIP ($CORES) | ${RAM_GB}GB"
  echo "macOS: $MACOS | Xcode: $XCODE | Power: $POWER"
  echo ""
  echo "Stopwatch (sheet):  Run1 ${WALL[1]}  Run2 ${WALL[2]}  Run3 ${WALL[3]}"
  echo "                    Best $W_BEST  Average $W_AVG"
  echo "Xcode reported:     Run1 ${XCT[1]}  Run2 ${XCT[2]}  Run3 ${XCT[3]}"
  echo "                    Best $X_BEST  Average $X_AVG  (leaderboard style: ${X_ROUND} sec)"
} | tee "$RESULTS"
att_card_end

echo ""
echo "Saved to: $RESULTS"
echo "Send Claude the lines above."

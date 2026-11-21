#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
whence att_pause_bg >/dev/null && att_pause_bg   # pause Photos/Spotlight/Siri scanning for the test (wakes back up at the end)
# ATT WebKit Build Test  -  v1.1 (Nov 16 2026)
# Times a full release build of WebKit and tracks swap + memory pressure the whole time.
#
# Lives in: Adam Talks Tech Tests/WebKit Test  (next to WebKit.tar)
# Run it from the Mac's copy of the test folder, NOT the LaCie:
#   cd ~/Downloads/"Adam Talks Tech Tests"/"WebKit Test"
#   zsh att-webkit.zsh                  (uses the Mac's name as the label)
#   zsh att-webkit.zsh "M6 32GB"        (or give a label)
#   zsh att-webkit.zsh "M6 32GB" /path/to/WebKit   (WebKit somewhere else)
#
# First run on a Mac: if there's no WebKit folder yet, it unpacks WebKit.tar
# next to itself (7.4GB in, much more out; the build adds tens of GB).
#
# Results: Adam Talks Tech Tests/Results/<Mac name>/WebKit/
#   <label>_<date>_summary.txt  the numbers for the sheet
#   <label>_<date>.csv          memory every 5 seconds (for charts)
#   <label>_<date>_build.log    full build output (only needed if it fails)
# v1.1: finds/unpacks WebKit next to itself, results in the test folder,
#       refuses to build on an external drive, logs free space.

# ---------- Where am I? ----------
SCRIPT_DIR=${0:A:h}
ROOT=$SCRIPT_DIR
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=$SCRIPT_DIR
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

LABEL="${1:-$MACNAME}"
SRC="${2:-$SCRIPT_DIR/WebKit}"
SRC="${SRC%/}"
OUTDIR="$ROOT/Results/$MACNAME/WebKit"
STAMP=$(date +%Y-%m-%d_%H%M)
SAFE_LABEL=${LABEL//[^A-Za-z0-9._-]/_}
CSV="$OUTDIR/${SAFE_LABEL}_${STAMP}.csv"
SUMMARY="$OUTDIR/${SAFE_LABEL}_${STAMP}_summary.txt"
BUILDLOG="$OUTDIR/${SAFE_LABEL}_${STAMP}_build.log"

mkdir -p "$OUTDIR"

# ---------- Checks ----------
if [[ ${SRC:A} == /Volumes/* ]]; then
  echo "WebKit is on an external drive: $SRC"
  echo "Building there would time the drive, not the Mac. Copy the WebKit Test folder"
  echo "to ~/Downloads/Adam Talks Tech Tests first (Tools/att-copy-tests.zsh)."
  exit 1
fi

if [[ ! -d "$SRC" && -f "$SCRIPT_DIR/WebKit.tar" && -z $2 ]]; then
  echo "No WebKit folder yet. Unpacking WebKit.tar here (a few minutes)..."
  ( cd "$SCRIPT_DIR" && tar -xf WebKit.tar ) || { echo "Unpacking failed."; exit 1; }
fi

if [[ ! -x "$SRC/Tools/Scripts/build-webkit" ]]; then
  echo "Can't find WebKit at: $SRC"
  echo "Put WebKit.tar (or the unpacked WebKit folder) next to this script,"
  echo "or run: zsh att-webkit.zsh \"Label\" /path/to/WebKit"
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode isn't ready on this Mac. Install Xcode, open it once, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

# ---------- Mac info ----------
CHIP=$(sysctl -n machdep.cpu.brand_string)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
CORES=$(sysctl -n hw.ncpu)
MACOS=$(sw_vers -productVersion)
XCODE=$(xcodebuild -version | head -1)
COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo "unknown")
FREE_DISK=$(df -g "$SRC" | awk 'NR==2 {print $4}')

echo ""
echo "ATT WebKit Build Test: $LABEL"
echo "$CHIP · ${RAM_GB}GB RAM · $CORES cores · macOS $MACOS · $XCODE"
echo "WebKit commit $COMMIT · ${FREE_DISK}GB free on this drive"
(( FREE_DISK < 60 )) && echo "!! Under 60GB free. The build may run out of room (that's a result on a 256GB Mac)."
echo ""

# ---------- Clean slate ----------
if [[ -d "$SRC/WebKitBuild" ]]; then
  echo "Removing the old build folder so this is a full build..."
  rm -rf "$SRC/WebKitBuild"
fi

echo "Waiting for the Mac to go quiet (up to 10 min)..."
quiet=0
for i in {1..120}; do
  load=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%d", s}')
  if (( load < 50 )); then
    quiet=$((quiet + 5))
  else
    quiet=0
  fi
  (( quiet >= 30 )) && break
  sleep 5
done
echo "Quiet enough. Starting."
echo ""

# ---------- Memory sampler ----------
PAGESIZE=$(sysctl -n hw.pagesize)

read_swap_gb() {
  sysctl -n vm.swapusage | awk '{
    for (i = 1; i <= NF; i++) if ($i == "used") {
      v = $(i+2); u = substr(v, length(v)); n = v + 0
      if (u == "G") n = n * 1024
      printf "%.2f", n / 1024
    }
  }'
}

read_free_pct() {
  memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}'
}

read_compressed_gb() {
  vm_stat | awk -v ps="$PAGESIZE" '/occupied by compressor/ {gsub("\\.","",$5); printf "%.2f", ($5 * ps) / 1073741824}'
}

read_pressure() {
  case $(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null) in
    1) echo green ;;
    2) echo yellow ;;
    4) echo red ;;
    *) echo unknown ;;
  esac
}

sampler() {
  local t0=$1
  echo "seconds,swap_used_gb,memory_free_pct,compressed_gb,pressure" > "$CSV"
  while true; do
    echo "$(( $(date +%s) - t0 )),$(read_swap_gb),$(read_free_pct),$(read_compressed_gb),$(read_pressure)" >> "$CSV"
    sleep 5
  done
}

START_SWAP=$(read_swap_gb)
START=$(date +%s)
sampler $START &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null; echo ""; echo "Stopped."; exit 1' INT TERM

# ---------- Build ----------
echo "Building WebKit (release). This takes a while."
echo "Full build output is going to: $BUILDLOG"
( cd "$SRC" && Tools/Scripts/build-webkit --release ) > "$BUILDLOG" 2>&1 &
BUILD=$!

while kill -0 $BUILD 2>/dev/null; do
  sleep 60
  el=$(( $(date +%s) - START ))
  printf "  %d:%02d elapsed · swap %sGB · %s\n" $((el / 60)) $((el % 60)) "$(read_swap_gb)" "$(read_pressure)"
done
wait $BUILD
STATUS=$?

END=$(date +%s)
kill $SAMPLER 2>/dev/null
ELAPSED=$((END - START))
TIME_STR=$(printf "%d:%02d:%02d" $((ELAPSED / 3600)) $(((ELAPSED % 3600) / 60)) $((ELAPSED % 60)))
FREE_END=$(df -g "$SRC" | awk 'NR==2 {print $4}')

# ---------- Summary ----------
STATS=$(awk -F, 'NR > 1 {
  if ($2 > peak_swap) peak_swap = $2
  if (min_free == "" || $3 < min_free) min_free = $3
  if ($4 > peak_comp) peak_comp = $4
  if ($5 == "yellow") yellow += 5
  if ($5 == "red") red += 5
} END {
  printf "%.2f|%s|%.2f|%d|%d", peak_swap, min_free, peak_comp, yellow, red
}' "$CSV")
IFS='|' read PEAK_SWAP MIN_FREE PEAK_COMP YELLOW RED <<< "$STATS"

if (( STATUS == 0 )); then RESULT="Build succeeded"; else RESULT="BUILD FAILED (see the build log)"; fi

cat > "$SUMMARY" <<EOF
ATT WebKit Build Test v1.1
Mac: $LABEL
Chip: $CHIP · ${RAM_GB}GB RAM · $CORES cores
macOS $MACOS · $XCODE · WebKit commit $COMMIT
Date: $(date "+%b %d %Y %I:%M %p")

$RESULT
Build time: $TIME_STR

Swap at start: ${START_SWAP}GB
Peak swap: ${PEAK_SWAP}GB
Lowest memory free: ${MIN_FREE}%
Peak compressed memory: ${PEAK_COMP}GB
Time in yellow: ${YELLOW}s
Time in red: ${RED}s
Free disk: ${FREE_DISK}GB before, ${FREE_END}GB after
EOF

att_card_start "WebKit build"
cat "$SUMMARY"
att_card_end
echo ""
echo "Saved to: $OUTDIR"
echo "To free the space: delete $SRC/WebKitBuild (the build output)."
afplay /System/Library/Sounds/Glass.aiff 2>/dev/null

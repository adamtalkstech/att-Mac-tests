#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  handbrake-bench.zsh  -  ATT HandBrake test (v1, Nov 16 2026)
# =============================================================================
#  Encodes the SAME 4K file to 1080p twice with HandBrake's own "Fast 1080p30"
#  preset, changing only the video encoder:
#    1. x265 (software H.265)        -> CPU cores
#    2. VideoToolbox H.265 (vt_h265) -> the media engine
#  One test shows cores vs media engine. Matches the sheet's New Tests columns
#  "x265 CPU encode time" and "VideoToolbox H.265 encode time".
#
#  Lives in: Adam Talks Tech Tests/HandBrake Test
#  Needs in that folder:
#    - one 4K source video (Tears of Steel 4K, see INSTALLER LINKS.txt). The
#      first .mov/.mp4/.mkv/.m4v in the folder is used, so keep only one.
#    - HandBrakeCLI (the command line version, separate from the HandBrake app):
#      https://handbrake.fr/downloads2.php  -> open the dmg, copy HandBrakeCLI
#      into this folder. (Or have it installed on the Mac.)
#
#  Run from the Mac's copy of the test folder:
#    cd ~/Downloads/"Adam Talks Tech Tests"/"HandBrake Test"
#    zsh handbrake-bench.zsh            both encoders, 1 run each
#    RUNS=3 zsh handbrake-bench.zsh     3 runs each, median logged
#    ONLY=vt zsh handbrake-bench.zsh    just VideoToolbox (or ONLY=x265)
#
#  Results: Results/<Mac name>/HandBrake/ + Results/All Macs handbrake.csv
#  The encoded files are deleted after each run (they're not the result).
# =============================================================================

zmodload zsh/datetime

# ---------- Where am I? ----------
HERE=${0:A:h}
ROOT=$HERE
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=$HERE
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

RUNS=${RUNS:-1}
ONLY=${ONLY:-}
PRESET="Fast 1080p30"
COOLDOWN=${COOLDOWN:-30}
OUT="$ROOT/Results/$MACNAME/HandBrake"
CSV="$ROOT/Results/All Macs handbrake.csv"
mkdir -p "$OUT"
STAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG="$OUT/handbrake_${STAMP}.txt"
TMPD=$(mktemp -d "$HERE/.hb-tmp.XXXXXX" 2>/dev/null || mktemp -d)

if [[ $HERE == /Volumes/* ]]; then
  print "This is running from an external drive. Copy the HandBrake Test folder to"
  print "~/Downloads/Adam Talks Tech Tests first (Tools/att-copy-tests.zsh), so the"
  print "source and output use the Mac's own SSD."
  exit 1
fi

# ---------- Find HandBrakeCLI and the source ----------
HB=""
for c in "$HERE/HandBrakeCLI" /opt/homebrew/bin/HandBrakeCLI /usr/local/bin/HandBrakeCLI; do
  [[ -x $c ]] && { HB=$c; break; }
done
[[ -z $HB ]] && HB=$(command -v HandBrakeCLI 2>/dev/null)
# Not installed? Pull it out of the dmg in Apps & Installers automatically
if [[ -z $HB ]]; then
  DMG=$(ls "$ROOT/Apps & Installers"/HandBrakeCLI-*.dmg /Volumes/*/"Adam Talks Tech Tests"/"Apps & Installers"/HandBrakeCLI-*.dmg 2>/dev/null | head -1)
  if [[ -n $DMG ]]; then
    print "Copying HandBrakeCLI out of ${DMG:t}..."
    MNT=$(mktemp -d)
    if hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null; then
      cp "$MNT/HandBrakeCLI" "$HERE/HandBrakeCLI" 2>/dev/null
      hdiutil detach "$MNT" -quiet
      chmod +x "$HERE/HandBrakeCLI" 2>/dev/null
      [[ -x "$HERE/HandBrakeCLI" ]] && HB="$HERE/HandBrakeCLI"
    fi
  fi
fi
if [[ -z $HB ]]; then
  print "Can't find HandBrakeCLI. Download it from https://handbrake.fr/downloads2.php,"
  print "open the dmg and copy HandBrakeCLI into: $HERE"
  exit 1
fi
xattr -d com.apple.quarantine "$HB" 2>/dev/null   # first run from a downloaded dmg

SRC=""
for f in "$HERE"/*.(mov|mp4|mkv|m4v|MOV|MP4)(N); do SRC=$f; break; done
[[ -z $SRC ]] && { print "No source video in $HERE. Put the 4K test file (Tears of Steel 4K) here."; exit 1; }

# ---------- Mac info ----------
MODEL=$(sysctl -n hw.model)
CHIP=$(sysctl -n machdep.cpu.brand_string)
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
OSV="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
HBV=$("$HB" --version 2>/dev/null | head -1)
POWER=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")
SRC_MB=$(( $(stat -f %z "$SRC") / 1048576 ))
SRC_DUR=$(afinfo "$SRC" 2>/dev/null | awk '/estimated duration/{printf "%.0f", $3}')
[[ -z $SRC_DUR ]] && SRC_DUR=$(mdls -raw -name kMDItemDurationSeconds "$SRC" 2>/dev/null | awk '{printf "%.0f", $1}')

{
print "================ ATT HandBrake Test v1 ================"
print "Mac:      $MACNAME ($MODEL)"
print "Chip:     $CHIP  |  ${RAM}GB  |  macOS $OSV"
print "HandBrake: $HBV"
print "Source:   ${SRC:t}  (${SRC_MB} MB${SRC_DUR:+, ${SRC_DUR}s long})"
print "Preset:   $PRESET, only the video encoder changes. Runs: $RUNS each"
print "Power:    $POWER"
print "======================================================="
} | tee "$LOG"
[[ $POWER != "AC Power" ]] && print "WARNING: not on AC power. Plug in." | tee -a "$LOG"

median() { print -l -- "$@" | sort -n | awk '{a[NR]=$1} END{ if (NR==0) exit; print (NR%2)? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2 }'; }
fmt() { local s=$1 m; m=$(( ${s%.*} / 60 )); if (( m > 0 )); then printf "%dm %.2fs" $m $(( s - m*60 )); else printf "%.2fs" $s; fi; }

typeset -A RES_T RES_FPS
run_encoder() {   # $1 = encoder id, $2 = label
  local enc=$1 label=$2 r t0 secs fps out
  local -a times fpss
  print "\n$label ($enc)..." | tee -a "$LOG"
  for (( r = 1; r <= RUNS; r++ )); do
    out="$TMPD/out_${enc}_$r.mp4"
    t0=$EPOCHREALTIME
    "$HB" -i "$SRC" -o "$out" --preset "$PRESET" -e "$enc" > "$TMPD/hb_${enc}_$r.log" 2>&1
    local rc=$?
    secs=$(( EPOCHREALTIME - t0 ))
    fps=$(grep -Eo 'average encoding speed for job is [0-9.]+' "$TMPD/hb_${enc}_$r.log" | grep -Eo '[0-9.]+$' | tail -1)
    if (( rc != 0 )) || [[ ! -s $out ]]; then
      print "  Run $r FAILED. Last lines of the HandBrake log:" | tee -a "$LOG"
      tail -8 "$TMPD/hb_${enc}_$r.log" | tee -a "$LOG"
      return 1
    fi
    times+=($secs); [[ -n $fps ]] && fpss+=($fps)
    print "  Run $r: $(fmt $secs)${fps:+  ($fps fps)}" | tee -a "$LOG"
    rm -f "$out"
    (( r < RUNS )) && { sleep $COOLDOWN; att_cooldown --again; }
  done
  RES_T[$enc]=$(median $times); RES_FPS[$enc]=$(median $fpss)
  print "  Logged: $(fmt ${RES_T[$enc]})${RES_FPS[$enc]:+  (${RES_FPS[$enc]} fps)}" | tee -a "$LOG"
}

att_cooldown
[[ $ONLY != vt ]]   && run_encoder x265    "x265 software H.265 (CPU)"
[[ $ONLY == "" ]]   && { print "\nCooling down ${COOLDOWN}s..."; sleep $COOLDOWN; att_cooldown --again; }
[[ $ONLY != x265 ]] && run_encoder vt_h265 "VideoToolbox H.265 (media engine)"

[[ -f $CSV ]] || print "Date,Mac,Model,Chip,RAM GB,macOS,HandBrake,Source,Runs,x265 time (s),x265 fps,VideoToolbox H.265 time (s),VideoToolbox fps" > "$CSV"
print "$(date +%F),\"$MACNAME\",$MODEL,\"$CHIP\",$RAM,\"$OSV\",\"$HBV\",\"${SRC:t}\",$RUNS,${RES_T[x265]},${RES_FPS[x265]},${RES_T[vt_h265]},${RES_FPS[vt_h265]}" >> "$CSV"

att_card_start "HandBrake 4K to 1080p (x265 CPU vs VideoToolbox)"
{
print "ATT HandBrake Test v1 - $(date)"
print "Mac: $MACNAME | $CHIP | ${RAM}GB | macOS $OSV | $HBV"
[[ -n ${RES_T[x265]} ]]    && print "x265 CPU encode:            $(fmt ${RES_T[x265]})   (sheet: x265 CPU encode time)"
[[ -n ${RES_T[vt_h265]} ]] && print "VideoToolbox H.265 encode:  $(fmt ${RES_T[vt_h265]})   (sheet: VideoToolbox H.265 encode time)"
print "Saved to: $LOG"
print "Send Claude the lines above."
} | tee -a "$LOG"
att_card_end
rm -rf "$TMPD"

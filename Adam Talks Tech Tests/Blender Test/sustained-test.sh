#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# ATT sustained load test (heat / throttling)  -  v1.1, Nov 16 2026
#
# Renders Blender's Classroom scene 3 times BACK TO BACK (no cooldown) and logs
# heat pressure + CPU/GPU watts the whole time, so you can see if a Mac slows
# down as it heats up.
#
# Lives in: Adam Talks Tech Tests/Blender Test (next to the classroom folder)
# Run it from the Mac's copy of the test folder:
#   cd ~/Downloads/"Adam Talks Tech Tests"/"Blender Test"
#   zsh sustained-test.sh            (CPU render, the heat test)
#   zsh sustained-test.sh GPU        (GPU render instead)
#   zsh sustained-test.sh CPU 5      (CPU, 5 runs instead of 3)
#
# Needs: Blender in /Applications. Asks for your password once (powermetrics).
# Results: Adam Talks Tech Tests/Results/<Mac name>/Sustained/<run folder>
#          plus a row in Results/All Macs sustained.csv
#
# v1.1: moved into Blender Test (uses the same classroom scene), results in the
#       test folder instead of the Desktop, CSV row for the sheet, refuses to run
#       from the LaCie, no more renaming from .txt.

DEVICE="${1:-CPU}"            # CPU or GPU
RUNS="${2:-3}"
SAMPLE_MS=5000

DEVICE=${DEVICE:u}
[[ "$DEVICE" == "GPU" ]] && CYCLES_DEV="METAL" || { DEVICE="CPU"; CYCLES_DEV="CPU"; }

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
SCRIPT_DIR="${0:A:h}"

# ---------- Where am I? ----------
ROOT=$SCRIPT_DIR
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=$SCRIPT_DIR
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

if [[ $SCRIPT_DIR == /Volumes/* ]]; then
  echo "This is running from an external drive. Copy the test folder to"
  echo "~/Downloads/Adam Talks Tech Tests first (Tools/att-copy-tests.zsh)."
  exit 1
fi

# ---------- find classroom.blend ----------
BLEND=""
for f in "$SCRIPT_DIR"/**/classroom.blend(N) "$ROOT/Blender Test"/**/classroom.blend(N); do
  BLEND="$f"; break
done
if [[ ! -x "$BLENDER" ]]; then
  echo "Can't find Blender at $BLENDER"; exit 1
fi
if [[ -z "$BLEND" ]]; then
  echo "Can't find classroom.blend in the Blender Test folder."
  echo "It should be in Adam Talks Tech Tests/Blender Test/classroom/."
  exit 1
fi

# ---------- Mac info ----------
MODEL=$(sysctl -n hw.model)
CHIP=$(sysctl -n machdep.cpu.brand_string)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
MACOS="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
POWER=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")
LOWPOWER=$(pmset -g | awk '/lowpowermode/ {print $2}')
BVER=$("$BLENDER" -v 2>/dev/null | head -1)

echo "============ ATT Sustained Load Test v1.1 ============"
echo "Mac:      $MACNAME  |  $MODEL  |  $CHIP  |  ${RAM_GB}GB"
echo "macOS:    $MACOS"
echo "Blender:  $BVER"
echo "Scene:    $BLEND"
echo "Device:   $DEVICE   Runs: $RUNS back to back, no cooldown"
echo "Power:    $POWER"
echo "======================================================"
[[ "$POWER" != "AC Power" ]] && echo "WARNING: not on AC power. Plug in."
[[ "$LOWPOWER" == "1" ]] && echo "WARNING: Low Power Mode is on. Turn it off."
if [[ ${COOL:-0} -lt 600 && $NOCOOL != 1 ]]; then
  echo "Heat test: it should start cool. Tip: run it as  COOL=600 zsh sustained-test.sh  (rests 10 min first, then starts by itself)."
fi
echo "You don't need to do anything else: it closes other apps and waits for the Mac to cool before starting."
echo ""
echo "Enter your password for powermetrics:"
sudo -v || exit 1
# keep sudo alive during the test
( while true; do sudo -n true; sleep 50; done ) 2>/dev/null &
KEEPALIVE=$!

LOG_DIR="$ROOT/Results/$MACNAME/Sustained"
STAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RUN_DIR="$LOG_DIR/${DEVICE}_${STAMP}"
mkdir -p "$RUN_DIR"
SUMMARY="$RUN_DIR/summary.txt"
CSV="$ROOT/Results/All Macs sustained.csv"

# ---------- parse one powermetrics log ----------
# prints: avgCPU_W avgGPU_W firstCPU_W lastCPU_W nominal moderate heavy other samples
parse_pm() {
  awk '
    /CPU Power:/      { v=$3/1000; cpu[++nc]=v; csum+=v }
    /GPU Power:/      { v=$3/1000; gsum+=v; ng++ }
    /pressure level:/ { p=$NF; if(p=="Nominal")n++; else if(p=="Moderate")m++; else if(p=="Heavy")h++; else o++ }
    END {
      k = (nc>=6) ? 6 : nc        # first/last 30 seconds at 5s samples
      for(i=1;i<=k;i++){ f+=cpu[i]; l+=cpu[nc-i+1] }
      printf "%.1f %.1f %.1f %.1f %d %d %d %d %d\n",
        (nc?csum/nc:0), (ng?gsum/ng:0), (k?f/k:0), (k?l/k:0), n+0, m+0, h+0, o+0, nc+0
    }' "$1"
}

att_cooldown
typeset -a TIMES
for i in {1..$RUNS}; do
  PM_LOG="$RUN_DIR/powermetrics-run$i.txt"
  BL_LOG="$RUN_DIR/blender-run$i.log"

  sudo powermetrics --samplers thermal,cpu_power,gpu_power -i $SAMPLE_MS > "$PM_LOG" 2>/dev/null &
  PM_PID=$!
  sleep 1

  echo "Run $i of $RUNS ($DEVICE)..."
  START=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  "$BLENDER" -b "$BLEND" -E CYCLES -o "$RUN_DIR/frame-run${i}_####" -f 1 -- --cycles-device $CYCLES_DEV > "$BL_LOG" 2>&1
  STATUS=$?
  END=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')

  sudo kill $PM_PID 2>/dev/null; wait $PM_PID 2>/dev/null

  if (( STATUS != 0 )); then
    echo "Run $i FAILED. Last lines of the Blender log:"; tail -15 "$BL_LOG"
    kill $KEEPALIVE 2>/dev/null; exit 1
  fi

  SECS=$(printf "%.2f" $(( END - START )))
  TIMES+=$SECS
  read A_CPU A_GPU F_CPU L_CPU NOM MOD HEV OTH NS <<< "$(parse_pm "$PM_LOG")"
  M=$(( ${SECS%.*} / 60 )); S=$(printf "%05.2f" $(( SECS - M*60 )))
  echo "  Run $i: ${M}:${S}  |  CPU avg ${A_CPU}W (first 30s ${F_CPU}W, last 30s ${L_CPU}W)  |  GPU avg ${A_GPU}W"
  echo "         heat pressure samples: Nominal $NOM, Moderate $MOD, Heavy $HEV, other $OTH"
  echo "Run $i: ${SECS}s | CPU avg ${A_CPU}W, first30 ${F_CPU}W, last30 ${L_CPU}W | GPU avg ${A_GPU}W | Nominal $NOM Moderate $MOD Heavy $HEV Other $OTH" >> "$RUN_DIR/runs.txt"
done

kill $KEEPALIVE 2>/dev/null

# ---------- summary ----------
DROP=$(printf "%.1f" $(( (${TIMES[-1]} - ${TIMES[1]}) / ${TIMES[1]} * 100 )))
att_card_start "Sustained load (heat), Classroom $DEVICE x$RUNS back to back"
{
  echo "ATT Sustained Load Test v1.1  -  $(date)"
  echo "Mac: $MACNAME | $MODEL | $CHIP | ${RAM_GB}GB | macOS $MACOS | $BVER"
  echo "Classroom, $DEVICE, $RUNS runs back to back, no cooldown, Power: $POWER"
  echo ""
  cat "$RUN_DIR/runs.txt"
  echo ""
  echo "Run 1 vs run $RUNS: ${DROP}% slower (positive = slowed down as it heated up)"
} | tee "$SUMMARY"
att_card_end

[[ -f $CSV ]] || echo "Date,Mac,Model,Chip,RAM GB,macOS,Blender,Device,Runs (s),Run 1 vs last %" > "$CSV"
echo "$(date +%F),\"$MACNAME\",$MODEL,\"$CHIP\",$RAM_GB,\"$MACOS\",\"$BVER\",$DEVICE,\"${(j: / :)TIMES}\",$DROP" >> "$CSV"

echo ""
echo "Saved to: $RUN_DIR"
echo "Send Claude the summary lines above (photo is fine)."

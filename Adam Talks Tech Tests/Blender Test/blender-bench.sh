#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# ATT Blender Benchmark  -  v1.3 (Nov 20 2026, retries a Blender crash once)
# Classroom GPU x3, Barbershop GPU x3, Classroom CPU x1.
# Log run 3 of each GPU scene (run 1 includes shader compiling).
#
# Lives in: Adam Talks Tech Tests/Blender Test (next to classroom/ and barbershop_interior.blend)
# Run it from the Mac's copy of the test folder:
#   cd ~/Downloads/"Adam Talks Tech Tests"/"Blender Test"
#   zsh blender-bench.sh              the standard test
#   zsh blender-bench.sh redautumn    Red Autumn Forest only (Cycles GPU, 128 samples,
#                                     frames 1-25, after a 1-frame warm-up)
# Close other apps and don't touch the Mac until it's done.
#
# Results: Adam Talks Tech Tests/Results/<Mac name>/Blender/ (text file per run)
#          and Adam Talks Tech Tests/Results/All Macs blender.csv (one row per run)
#
# v1.1: results in the test folder (not the Desktop), CSV row for the sheet,
#       refuses to run from the LaCie, Red Autumn mode merged in from the
#       Nov 12 blender-tests.sh. Red Autumn from Terminal can run a little faster
#       than the GUI render, so don't mix the two in one chart without a
#       side-by-side check on one Mac first.

# ---------- Where am I? ----------
HERE="${0:A:h}"
ROOT=$HERE
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=$HERE
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

MODE="${1:-standard}"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
OUT="$ROOT/Results/$MACNAME/Blender"
CSV="$ROOT/Results/All Macs blender.csv"
mkdir -p "$OUT"
TMPR="$(mktemp -d)"

if [[ $HERE == /Volumes/* ]]; then
  echo "This is running from an external drive. Copy the Blender Test folder to"
  echo "~/Downloads/Adam Talks Tech Tests first (Tools/att-copy-tests.zsh), so scene"
  echo "loading comes off the Mac's own SSD."
  exit 1
fi

# Find the scene files
CLASSROOM=$(ls "$HERE"/classroom/*.blend 2>/dev/null | head -n 1)
BARBER="$HERE/barbershop_interior.blend"
AUTUMN="$HERE/blender-2.91-splash.blend"

if [[ ! -x "$BLENDER" ]]; then echo "Can't find Blender at $BLENDER. Install it in Applications, or run: BLENDER=/path/to/Blender zsh blender-bench.sh"; exit 1; fi
if [[ $MODE == standard ]]; then
  [[ -z "$CLASSROOM" ]] && { echo "Can't find a .blend inside the classroom folder next to this script."; exit 1; }
  [[ ! -f "$BARBER" ]] && { echo "Can't find barbershop_interior.blend next to this script."; exit 1; }
elif [[ $MODE == redautumn ]]; then
  [[ ! -f "$AUTUMN" ]] && { echo "Can't find blender-2.91-splash.blend (Red Autumn Forest) next to this script."; exit 1; }
else
  echo "Unknown mode: $MODE  (use: standard or redautumn)"; exit 1
fi

# Mac info
MODEL=$(sysctl -n hw.model)
CHIP=$(sysctl -n machdep.cpu.brand_string)
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
NLEVELS=$(sysctl -n hw.nperflevels 2>/dev/null || echo 1)
CORES=""
for (( i=0; i<NLEVELS; i++ )); do
  n=$(sysctl -n hw.perflevel$i.physicalcpu 2>/dev/null)
  name=$(sysctl -n hw.perflevel$i.name 2>/dev/null)
  CORES+="${n} ${name}, "
done
CORES=${CORES%, }
OSV="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
BV=$("$BLENDER" --version 2>/dev/null | head -n 1)
POWER=$(pmset -g batt | head -n 1 | sed "s/Now drawing from //; s/'//g")
STAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG="$OUT/blender-${MODE}_${STAMP}.txt"

# Python run inside Blender to pick the device (and Red Autumn settings)
# Timing hook: prints ATT_RENDER_SECONDS when the render finishes (backup if the
# "Time:" line Blender prints changes between versions)
HOOK="import bpy,time; _t={}; bpy.app.handlers.render_init.append(lambda *a: _t.__setitem__('s',time.time())); bpy.app.handlers.render_complete.append(lambda *a: print('ATT_RENDER_SECONDS: %.3f' % (time.time()-_t.get('s',time.time())), flush=True)); bpy.app.handlers.render_pre.append(lambda *a: _t.__setitem__('f',time.time())); bpy.app.handlers.render_post.append(lambda *a: print('ATT_FRAME_SECONDS: %.3f' % (time.time()-_t.get('f',time.time())), flush=True))"
pyset() {
  echo "$HOOK"
  if [[ "$1" == "GPU" ]]; then
    echo "import bpy; p=bpy.context.preferences.addons['cycles'].preferences; p.compute_device_type='METAL'; p.get_devices(); [setattr(d,'use', d.type!='CPU') for d in p.devices]; print('ATT_DEVICES:', [(d.name,d.type) for d in p.devices if d.use], flush=True); [setattr(s.cycles,'device','GPU') for s in bpy.data.scenes]"
  elif [[ "$1" == "AUTUMN" ]]; then
    # Same as the locked GUI setup: Cycles, GPU Compute, Render Max Samples 128,
    # everything else stock (Noise Threshold, Denoise off, resolution as in the file)
    echo "import bpy; p=bpy.context.preferences.addons['cycles'].preferences; p.compute_device_type='METAL'; p.get_devices(); [setattr(d,'use', d.type!='CPU') for d in p.devices]; print('ATT_DEVICES:', [(d.name,d.type) for d in p.devices if d.use], flush=True); s=bpy.context.scene; s.render.engine='CYCLES'; s.cycles.device='GPU'; s.cycles.samples=128"
  else
    echo "import bpy; [setattr(s.cycles,'device','CPU') for s in bpy.data.scenes]"
  fi
}

# Render one frame; prints Blender's own render time in seconds
render_once() {
  local file="$1" dev="$2" tag="$3"
  local raw="$TMPR/$tag.log"
  att_watch_start "$TMPR/$tag.bg" "[Bb]lender" 2>/dev/null
  "$BLENDER" -b "$file" --python-expr "$(pyset $dev)" -o "$TMPR/${tag}_####" -F PNG -f 1 > "$raw" 2>&1
  local rc=$?
  att_watch_stop 2>/dev/null
  # only mention background CPU when something actually competed
  [[ -s "$TMPR/$tag.bg" ]] && echo "  !! $(att_watch_report "$TMPR/$tag.bg")  <- may have slowed this run" >&2
  # Blender prints a line like "Time: 00:18.47 (Saving: 00:00.05)" when the frame is done
  local t=$(grep -E "^ *Time: ?[0-9]" "$raw" | tail -n 1 | sed -E 's/^ *Time: ?([0-9:.]+).*/\1/')
  if [[ -n "$t" ]]; then
    # Convert mm:ss.xx or hh:mm:ss.xx to seconds
    echo "$t" | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else print $1*60+$2 }'; return
  fi
  # Backup: our own timer from Blender's render start/finish events
  local h=$(grep -E "^ATT_RENDER_SECONDS: " "$raw" | tail -n 1 | awk '{print $2}')
  if [[ -n "$h" && -n "$(ls "$TMPR/${tag}_"* 2>/dev/null)" ]]; then
    echo "  (timed with the render-event timer, Blender didn't print a Time line)" >&2
    echo "$h"; return
  fi
  # Real failure: keep Blender's log and show why
  mkdir -p "$OUT"; cp "$raw" "$OUT/FAILED_${tag}_${STAMP}.log"
  { echo "  Blender exit code $rc. Last lines of its log (full log: $OUT/FAILED_${tag}_${STAMP}.log):"
    grep -v '^ *$' "$raw" | tail -n 12 | sed 's/^/    | /'; } >&2
  echo "FAILED"
}

# Blender 5.2 sometimes crashes while compiling GPU shaders (Metal shader cache,
# "exit code 134"). That's Blender, not the Mac, so a crashed run gets one retry.
render() {
  local r; r=$(render_once "$@")
  if [[ $r == FAILED ]]; then
    echo "  Blender crashed on that run. Retrying it once (the crash is a Blender bug, not a result)..." >&2
    r=$(render_once "$1" "$2" "${3}_retry")
    [[ $r != FAILED ]] && echo "  (that run is a retry after a Blender crash)" >&2
  fi
  echo "$r"
}

fmt() { awk -v s="$1" 'BEGIN { if (s=="FAILED") print s; else printf "%d:%05.2f (%.2fs)", int(s/60), s-int(s/60)*60, s }'; }

{
echo "================ ATT Blender Benchmark v1.3 ($MODE) ================"
echo "Mac:      $MACNAME ($MODEL)"
echo "Chip:     $CHIP ($CORES)"
echo "RAM:      ${RAM}GB"
echo "macOS:    $OSV"
echo "Blender:  $BV"
echo "Power:    $POWER"
echo "====================================================================="
} | tee "$LOG"

[[ -f $CSV ]] || echo "Date,Mac,Model,Chip,RAM GB,macOS,Blender,Test,Run 1 (s),Run 2 (s),Run 3 (s)" > "$CSV"
row() { echo "$(date +%F),\"$MACNAME\",$MODEL,\"$CHIP\",$RAM,\"$OSV\",\"$BV\",$1,$2,$3,$4" >> "$CSV"; }

att_cooldown
if [[ $MODE == standard ]]; then
  echo "\nClassroom GPU, 3 runs (run 1 includes shader compiling)..." | tee -a "$LOG"
  CG1=$(render "$CLASSROOM" GPU classroom_gpu1); echo "  Run 1: $(fmt $CG1)" | tee -a "$LOG"
  CG2=$(render "$CLASSROOM" GPU classroom_gpu2); echo "  Run 2: $(fmt $CG2)" | tee -a "$LOG"
  CG3=$(render "$CLASSROOM" GPU classroom_gpu3); echo "  Run 3: $(fmt $CG3)" | tee -a "$LOG"

  att_cooldown --again
  echo "Barbershop GPU, 3 runs..." | tee -a "$LOG"
  BG1=$(render "$BARBER" GPU barbershop_gpu1); echo "  Run 1: $(fmt $BG1)" | tee -a "$LOG"
  BG2=$(render "$BARBER" GPU barbershop_gpu2); echo "  Run 2: $(fmt $BG2)" | tee -a "$LOG"
  BG3=$(render "$BARBER" GPU barbershop_gpu3); echo "  Run 3: $(fmt $BG3)" | tee -a "$LOG"

  att_cooldown --again
  echo "Classroom CPU, 1 run (takes a few minutes)..." | tee -a "$LOG"
  CC=$(render "$CLASSROOM" CPU classroom_cpu)
  echo "  $(fmt $CC)" | tee -a "$LOG"

  row "Classroom GPU" $CG1 $CG2 $CG3
  row "Barbershop GPU" $BG1 $BG2 $BG3
  row "Classroom CPU" $CC "" ""

  att_card_start "Blender: Classroom GPU x3, Barbershop GPU x3, Classroom CPU"
  {
  echo "ATT Blender Benchmark v1.3 - $(date)"
  echo "Mac: $MACNAME | $MODEL | ${CHIP} | ${RAM}GB | macOS $OSV | $BV"
  echo "Classroom GPU:   run 1 $(fmt $CG1) | run 2 $(fmt $CG2) | run 3 $(fmt $CG3)"
  echo "Barbershop GPU:  run 1 $(fmt $BG1) | run 2 $(fmt $BG2) | run 3 $(fmt $BG3)"
  echo "Classroom CPU:   $(fmt $CC)"
  } | tee -a "$LOG"
else
  echo "\nRed Autumn warm-up: frame 1 (compiles the GPU code, bonus single-frame number)..." | tee -a "$LOG"
  WF=$(render "$AUTUMN" AUTUMN autumn_warmup); echo "  Frame 1: $(fmt $WF)" | tee -a "$LOG"
  echo "Red Autumn frames 1-25 (Cycles GPU, 128 samples)..." | tee -a "$LOG"
  "$BLENDER" -b "$AUTUMN" --python-expr "$(pyset AUTUMN)" -o "$TMPR/autumn_####" -F PNG -s 1 -e 25 -a > "$TMPR/autumn.log" 2>&1
  # Per-frame seconds: Blender's own "Time:" lines if it prints them, else our render_pre/post timer
  if grep -qE "^ *Time: ?[0-9]" "$TMPR/autumn.log"; then
    grep -E "^ *Time: ?[0-9]" "$TMPR/autumn.log" | sed -E 's/^ *Time: ?([0-9:.]+).*/\1/' \
      | awk -F: '{ print (NF==3) ? $1*3600+$2*60+$3 : $1*60+$2 }' > "$TMPR/frames.txt"
  else
    grep -E "^ATT_FRAME_SECONDS: " "$TMPR/autumn.log" | awk '{print $2}' > "$TMPR/frames.txt"
  fi
  FRAMES=$(wc -l < "$TMPR/frames.txt" | tr -d ' ')
  TOTAL=$(awk '{ s += $1 } END { printf "%.2f", s }' "$TMPR/frames.txt")
  FIRST5=$(head -5 "$TMPR/frames.txt" | awk '{ s += $1 } END { if (NR) printf "%.2f", s/NR }')
  LAST5=$(tail -5 "$TMPR/frames.txt" | awk '{ s += $1 } END { if (NR) printf "%.2f", s/NR }')
  if (( FRAMES < 25 )); then echo "  !! Only $FRAMES of 25 frames rendered. Check: $TMPR/autumn.log" | tee -a "$LOG"; fi
  row "Red Autumn 1-25" $TOTAL "" ""
  att_card_start "Blender Red Autumn Forest, frames 1-25 (GPU)"
  {
  echo "  Frames 1-25: $(fmt $TOTAL)  ($FRAMES frames)"
  echo "  Average frame: first 5 ${FIRST5}s, last 5 ${LAST5}s (later frames are heavier; a big jump on a laptop can also be heat)"
  echo "ATT Blender Red Autumn v1.2 - $(date)"
  echo "Mac: $MACNAME | $MODEL | ${CHIP} | ${RAM}GB | macOS $OSV | $BV"
  echo "Frame 1 (warm-up): $(fmt $WF)"
  echo "Frames 1-25:       $(fmt $TOTAL)"
  } | tee -a "$LOG"
fi

{
echo "Times: render start to finish for each frame (Blender 5.2 no longer prints its own Time line)."
echo "Saved to: $LOG"
} | tee -a "$LOG"
att_card_end

[[ $MODE == redautumn && $FRAMES -lt 25 ]] || rm -rf "$TMPR"

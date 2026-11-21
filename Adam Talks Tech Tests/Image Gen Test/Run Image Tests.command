#!/bin/bash
# ATT Image Tests - double-click to run. Everything lives on this drive:
# uv, Python, the model files and the results. Nothing installs on the Mac.

KIT="$(cd "$(dirname "$0")" && pwd)"
cd "$KIT" || exit 1

export UV_INSTALL_DIR="$KIT/.tools/uv"
export UV_CACHE_DIR="$KIT/.tools/uv-cache"
export UV_PYTHON_INSTALL_DIR="$KIT/.tools/python"
export UV_NO_MODIFY_PATH=1
export HF_HOME="$KIT/.tools/huggingface"
ROOT="$KIT"; while [ "$ROOT" != "/" ] && [ "$(basename "$ROOT")" != "Adam Talks Tech Tests" ]; do ROOT="$(dirname "$ROOT")"; done
if [ "$ROOT" = "/" ]; then export ATT_RESULTS_DIR="$KIT/results"; else export ATT_RESULTS_DIR="$ROOT/Results/$(scutil --get ComputerName)/Image Tests"; fi
UV="$UV_INSTALL_DIR/uv"
[ -d "$KIT/.tools" ] && xattr -dr com.apple.quarantine "$KIT/.tools" 2>/dev/null   # copied/AirDropped tools get blocked otherwise

# After prep, run fully offline so nothing downloads mid-test.
if [ -f "$KIT/.tools/PREPPED" ]; then
  export HF_HUB_OFFLINE=1
  export UV_OFFLINE=1
fi

if [ ! -x "$UV" ]; then
  echo "This drive hasn't been prepped yet. Run 'Prep This Drive.command' first."
  read -r -p "Press Return to close."
  exit 1
fi

echo
echo "ATT Image Tests  ($(scutil --get ComputerName))"
echo "  1) mflux: standard + stress   (fully automatic)"
echo "  2) mflux: standard + stress + full precision (RAM test)"
echo "  3) Draw Things: standard + stress (app open, API server on)"
echo "  4) Draw Things: show current settings"
echo "  5) Diffusion Bee: log a manual run"
echo "  6) Run 1 then 3 back to back"
echo
read -r -p "Pick a number: " CHOICE
read -r -p "Condition (e.g. cool, after Blender) or Return to skip: " COND

# Pause Photos/Spotlight/Siri scanning + cool down like every other ATT test (zsh helper)
cool_run() { zsh -c 'source "$1" && ATT_KEEP="Terminal,Draw Things,DrawThings,DiffusionBee,Diffusion Bee" att_cooldown; shift; "$@"' _ "$ROOT/Tools/att-card.zsh" "$@"; }
[ -f "$ROOT/Tools/att-card.zsh" ] || cool_run() { "$@"; }

ARGS=()
[ -n "$COND" ] && ARGS+=(--condition "$COND")

case "$CHOICE" in
  1) cool_run "$UV" run --script att_mflux_bench.py "${ARGS[@]}" ;;
  2) cool_run "$UV" run --script att_mflux_bench.py --tests standard,stress,fullprecision "${ARGS[@]}" ;;
  3) "$UV" run --script att_drawthings_bench.py "${ARGS[@]}" ;;
  4) "$UV" run --script att_drawthings_bench.py --show-config ;;
  5) "$UV" run --script att_diffusionbee_log.py "${ARGS[@]}" ;;
  6) cool_run "$UV" run --script att_mflux_bench.py "${ARGS[@]}"
     echo "Cooling down 60s before Draw Things..."; sleep 60
     "$UV" run --script att_drawthings_bench.py "${ARGS[@]}" ;;
  *) echo "No test picked." ;;
esac

echo
echo "Results: $ATT_RESULTS_DIR"
read -r -p "Done. Press Return to close."

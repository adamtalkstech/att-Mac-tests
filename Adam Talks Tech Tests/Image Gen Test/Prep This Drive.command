#!/bin/bash
# One time, on any Mac with internet: puts uv, Python, the frozen mflux
# software and the Z-Image Turbo model on this drive.

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

case "$KIT" in
  /Volumes/*) ;;
  *) echo "Heads up: this folder isn't on an external drive ($KIT)." ;;
esac

if [ ! -x "$UV" ]; then
  echo "Installing uv onto the drive..."
  curl -LsSf https://astral.sh/uv/install.sh | sh || { echo "uv install failed"; read -r; exit 1; }
fi

echo "Getting Python and the frozen mflux software..."
"$UV" python install 3.12 || { echo "Python install failed"; read -r; exit 1; }

echo "Downloading the model (several GB, one time)..."
"$UV" run --script att_mflux_bench.py --prefetch || { echo "Model download failed"; read -r; exit 1; }

# The other two scripts have no extra packages, but cache their environments too.
"$UV" run --script att_diffusionbee_log.py --help >/dev/null
"$UV" run --script att_drawthings_bench.py --help >/dev/null

date > "$KIT/.tools/PREPPED"
echo
echo "Drive is ready. On each Mac just double-click 'Run Image Tests.command'."
read -r -p "Press Return to close."

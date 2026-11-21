#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  att-drawthings.zsh  -  Run Order step 18: Draw Things image gen (v1, Nov 20 2026)
# =============================================================================
#  Same model on every Mac: Z-Image Turbo (the mflux test's model), 1024x1024
#  and 2048x2048, 8 steps, seed 42, "a cat working on a laptop with nachos".
#  Does it in order: checks Draw Things is installed, copies the model in from
#  the drive if this Mac doesn't have it, opens Draw Things, waits for the API
#  server, checks Z-Image Turbo is selected, cools down, runs, prints the card.
#
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Image Gen Test" && zsh att-drawthings.zsh
#    ... zsh att-drawthings.zsh save    (once, on the Mac that downloaded Z-Image
#        Turbo in Draw Things: puts the model files on the plugged-in drive)
#  Options in front: TESTS=standard (skip the 2048 stress run)
# =============================================================================
KIT=${0:A:h}
NAME="Adam Talks Tech Tests"
DT_MODELS="$HOME/Library/Containers/com.liuliu.draw-things/Data/Documents/Models"
URL="http://127.0.0.1:7860"
MATCH='*z_image*'

drive_dirs() { local d; for d in /Volumes/*/"$NAME"/"Image Gen Test"/"Draw Things Models"(N/) \
  /Volumes/*/*/"$NAME"/"Image Gen Test"/"Draw Things Models"(N/) /Volumes/*/*/*/"$NAME"/"Image Gen Test"/"Draw Things Models"(N/); do print -r -- "$d"; done; }

if [[ ${1:-} == save ]]; then
  [[ -d $DT_MODELS ]] || { print "No Draw Things models on this Mac."; exit 1; }
  dest=$(for d in /Volumes/*/"$NAME"/"Image Gen Test"(N/); do print -r -- "$d"; break; done)
  [[ -n $dest ]] || { print "Plug in a test drive first."; exit 1; }
  dest="$dest/Draw Things Models"; mkdir -p "$dest"
  print "Files in Draw Things' model folder:"; ls -lh "$DT_MODELS" | awk 'NR>1{print "  "$5"  "$9}'
  print -n "Copy ALL of these to $dest ? (download only Z-Image Turbo on this Mac first) (y/n) "; read -r yn
  [[ $yn == [yY]* ]] || exit 0
  ditto "$DT_MODELS" "$dest" && print "Saved. Other Macs copy it in by themselves."
  exit 0
fi

[[ $KIT == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/$NAME/Image Gen Test."; exit 1; }

# 1. App
APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.liuliu.draw-things'" 2>/dev/null | grep '\.app$' | head -1)
[[ -z $APP && -d "/Applications/Draw Things.app" ]] && APP="/Applications/Draw Things.app"
if [[ -z $APP ]]; then
  print "Draw Things isn't installed. Opening the Mac App Store page (free). Install it, open it once, then rerun."
  open "https://apps.apple.com/us/app/draw-things-ai-generation/id6444050820"; exit 1
fi
DTV=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
export ATT_DT_VERSION=$DTV
print "Draw Things $DTV"

# 2. Model (Terminal may ask to access another app's data: click Allow)
if [[ -z $(print -l "$DT_MODELS"/${~MATCH}(N)) ]]; then
  src=$(drive_dirs | head -1)
  if [[ -n $src && -n $(print -l "$src"/${~MATCH}(N)) ]]; then
    print "Z-Image Turbo isn't in Draw Things on this Mac. Copying it from the drive (one time)..."
    mkdir -p "$DT_MODELS"
    for f in "$src"/*(N.); do [[ -e "$DT_MODELS/${f:t}" ]] || { print "  ${f:t}"; ditto "$f" "$DT_MODELS/${f:t}"; }; done
    osascript -e 'quit app "Draw Things"' >/dev/null 2>&1; sleep 3
  else
    print "Z-Image Turbo isn't on this Mac or the drive yet."
    print "In Draw Things: tap the model name > search 'Z-Image Turbo' > download it."
    print "Then run this again. (Afterwards, with a drive plugged in: zsh att-drawthings.zsh save)"
    open -a "$APP"; exit 1
  fi
fi

# 3. App open + API server on + right model
open -a "$APP"; sleep 5
api_ok() { curl -sf -m 5 "$URL/" >/dev/null 2>&1; }
until api_ok; do
  print "\nTurn on Draw Things' API server: Settings > API Server: ON, HTTP, port 7860."
  print -n "Press Return when it's on (Ctrl-C to stop). "; read -r
done
cur_model() { curl -sf -m 10 "$URL/" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("model",""))' 2>/dev/null || curl -sf -m 10 "$URL/" | grep -o '"model" *: *"[^"]*"' | head -1; }
until [[ ${(L)$(cur_model)} == *z_image* ]]; do
  print "\nDraw Things has \"$(cur_model)\" selected. Pick Z-Image Turbo as the model."
  print -n "Press Return when it's selected. "; read -r
done
print "Model: $(cur_model)"

# 4. Python: the kit's own (on the drive copy) or the Mac's
PY=()
if [[ -x "$KIT/.tools/uv/uv" ]]; then
  export UV_CACHE_DIR="$KIT/.tools/uv-cache" UV_PYTHON_INSTALL_DIR="$KIT/.tools/python" UV_OFFLINE=1
  PY=("$KIT/.tools/uv/uv" run --script)
elif /usr/bin/python3 -c 'import sys' >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
  PY=(/usr/bin/python3)
else
  print "Needs Python: run  xcode-select --install  once, then rerun."; exit 1
fi
MACNAME=$(scutil --get ComputerName)
export ATT_RESULTS_DIR="${KIT:h}/Results/$MACNAME/Image Tests"

# 5. Cool down, run
ATT_KEEP="Draw Things${ATT_KEEP:+,$ATT_KEEP}" att_cooldown
LOG="$ATT_RESULTS_DIR/.drawthings_$(date +%Y%m%d-%H%M%S).out"; mkdir -p "$ATT_RESULTS_DIR"
cd "$KIT" && "${PY[@]}" att_drawthings_bench.py --tests "${TESTS:-standard,stress}" 2>&1 | tee "$LOG"

att_card_start "Draw Things image gen (Z-Image Turbo, seed 42, 8 steps)"
print "Draw Things $DTV | $(grep -m1 '^Draw Things settings:' "$LOG" | cut -c23-)"
grep -E "Draw Things (standard|stress):|warm-up|run [0-9]|MEDIAN|FAILED" "$LOG" | sed 's/^ */  /'
print "Sheet: New Tests BS = standard median (s). Stress goes in F for now."
att_card_end

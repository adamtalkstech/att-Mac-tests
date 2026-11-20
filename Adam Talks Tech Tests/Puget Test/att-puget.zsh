#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  att-puget.zsh  -  Puget Bench for Creators helper (v1, Nov 16 2026)
# =============================================================================
#  Puget Bench keeps its test files in
#     ~/Library/Application Support/com.puget.benchmark/  (assets + benchmarks)
#  Puget's user guide says to copy those two folders to the other Mac so it
#  doesn't download them again. This does that, applies the press license,
#  and runs the benchmarks from Terminal with results saved to the test folder.
#
#  Lives in: Adam Talks Tech Tests/Puget Test   (assets go in Puget Test/Assets)
#
#  zsh att-puget.zsh save      once, on the Mac that downloaded the assets
#                               (open Puget, let it download each benchmark's
#                               assets first) -> copies them to the LaCie
#  zsh att-puget.zsh load      on each test Mac (Puget installed, quit) ->
#                               copies the assets from the LaCie into Puget
#  zsh att-puget.zsh license   applies the press key from LICENSES - keep private.txt
#  zsh att-puget.zsh run "Photoshop"   runs one benchmark, Standard preset
#     apps: "Photoshop" "Premiere Pro" "After Effects" "Lightroom Classic" "DaVinci Resolve"
#     zsh att-puget.zsh run all        runs all five, one after another
#     PRESET=Extended zsh att-puget.zsh run "Lightroom Classic"   (masking/AI tests)
#
#  Results: Adam Talks Tech Tests/Results/<Mac name>/Puget/<app>_<date>.csv
#  Rules: name it in full on screen ("Puget Bench for Photoshop") and link
#  Puget Systems in written content. Cool start before Lightroom. After Effects:
#  run it twice and log the 2nd. Resolve: Super Scale under ~5 fps = rerun.
# =============================================================================

NAME="Adam Talks Tech Tests"
HERE=${0:A:h}
ROOT=$HERE
while [[ $ROOT != / && ${ROOT:t} != $NAME ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=$HERE
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}
LOCAL="$HOME/Library/Application Support/com.puget.benchmark"
APP="/Applications/PugetBench for Creators.app/Contents/MacOS/PugetBench for Creators"
PRESET=${PRESET:-Standard}

LACIE=""
for d in /Volumes/*/"$NAME"/"Puget Test"(N/); do LACIE="$d/Assets"; break; done

size_gb() { du -sk "$1" 2>/dev/null | awk '{printf "%.1f", $1/1048576}'; }
puget_running() { pgrep -fq "PugetBench for Creators"; }
puget_key() {
  local lic=$(find /Volumes/*/"$NAME"/"_Read Me First" "$ROOT/_Read Me First" -maxdepth 1 -name "LICENSES - keep private.txt" 2>/dev/null | head -1)
  awk '/PUGET BENCH/{f=1} f&&/Key:/{print $2; exit}' "$lic" 2>/dev/null
}

case ${1:-} in
  save)
    [[ -n $LACIE ]] || { print "Plug in the LaCie (needs $NAME/Puget Test on it)."; exit 1; }
    for f in assets benchmarks; do
      [[ -d "$LOCAL/$f" ]] || { print "No $f folder in $LOCAL. Open Puget and download the assets first."; exit 1; }
    done
    puget_running && { print "Quit Puget Bench first."; exit 1; }
    mkdir -p "$LACIE"
    for f in assets benchmarks; do
      print "Copying $f ($(size_gb "$LOCAL/$f") GB) to the LaCie..."
      ditto "$LOCAL/$f" "$LACIE/$f" || { print "!! Copy failed: $f"; exit 1; }
    done
    print "Saved to: $LACIE"
    ;;
  load)
    [[ -n $LACIE && -d "$LACIE/assets" ]] || { print "No Puget assets on the LaCie yet. Run 'save' on the Mac that has them."; exit 1; }
    [[ -x $APP ]] || { print "Install PugetBench for Creators first (Apps & Installers)."; exit 1; }
    puget_running && { print "Quit Puget Bench first."; exit 1; }
    need=$(du -sk "$LACIE" | awk '{print $1}'); have=$(df -k "$HOME" | awk 'NR==2{print $4}')
    (( have - need < 30 * 1048576 )) && { print "Not enough room: needs $(size_gb "$LACIE") GB and keeps 30GB spare."; exit 1; }
    mkdir -p "$LOCAL"
    for f in assets benchmarks; do
      print "Copying $f ($(size_gb "$LACIE/$f") GB) into Puget on this Mac..."
      ditto "$LACIE/$f" "$LOCAL/$f" || { print "!! Copy failed: $f"; exit 1; }
    done
    print "Done. Open Puget: the benchmarks should show as ready, with no downloads."
    ;;
  license)
    [[ -x $APP ]] || { print "Install PugetBench for Creators first."; exit 1; }
    KEY=$(puget_key)
    [[ -n $KEY ]] || { print "Couldn't read the Puget key from the LICENSES file. Paste it in Puget > Settings > License instead."; exit 1; }
    "$APP" --license "$KEY" && print "Puget press license applied on this Mac."
    ;;
  run)
    [[ -x $APP ]] || { print "Install PugetBench for Creators first."; exit 1; }
    shift
    typeset -a apps
    if [[ ${1:-} == all ]]; then apps=("Lightroom Classic" "Photoshop" "Premiere Pro" "After Effects" "DaVinci Resolve")
    else apps=("$@"); fi
    (( ${#apps} )) || { print 'Which app? e.g. zsh att-puget.zsh run "Photoshop"  (or: run all)'; exit 1; }
    KEY=$(puget_key)
    [[ -n $KEY ]] || { print "Couldn't read the Puget key from _Read Me First/LICENSES - keep private.txt."; exit 1; }
    OUT="$ROOT/Results/$MACNAME/Puget"; mkdir -p "$OUT"
    for a in $apps; do
      f="$OUT/${a// /-}_${PRESET}_$(date +%Y-%m-%d_%H%M).csv"
      att_cooldown
      print "\n=== Puget Bench for $a ($PRESET) on $MACNAME ==="
      "$APP" --license "$KEY" --app "$a" --preset "$PRESET" --copy_log "$f"
      if [[ -s $f ]]; then
        att_card_start "Puget Bench for $a ($PRESET)"
        grep -iE 'score|version|error' "$f" | head -30 | cut -c1-120
        print "File: ${f:t}"
        att_card_end
      else
        print "!! No result file, so this run failed (see the message above)."
      fi
    done
    print "\nSend Claude the result files (or just say they're done; they're in Results/$MACNAME/Puget)."
    ;;
  *) print 'Usage: zsh att-puget.zsh save | load | license | run "App" | run all'; exit 1 ;;
esac

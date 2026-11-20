#!/bin/zsh
# =============================================================================
#  att-models.zsh  -  move LM Studio models between Macs (v1, Nov 16 2026)
# =============================================================================
#  LM Studio keeps every model in   ~/.lmstudio/models/<publisher>/<model>/
#  e.g.  ~/.lmstudio/models/lmstudio-community/Qwen3.5-9B-MLX-4bit/
#  It only sees a model if that two-level folder layout is kept exactly
#  (that's what caused the "dependent model" error on Nov 6). This script
#  copies whole model folders and keeps the layout, so it can't go wrong.
#
#  Lives in: Adam Talks Tech Tests/AI Tests
#  Models on the LaCie: Adam Talks Tech Tests/AI Tests/LM Studio Models/
#
#  1) SAVE  (once, on the Mac that downloaded them, e.g. the Mac Studio)
#     zsh att-models.zsh save
#     Lists the models in this Mac's LM Studio, you pick which, and it copies
#     them onto the LaCie (LM Studio Models folder), keeping the layout.
#
#  2) LOAD  (on each test Mac, LaCie plugged in)
#     zsh att-models.zsh load
#     Lists the models on the LaCie, you pick which, checks free space, copies
#     them into ~/.lmstudio/models on this Mac, then lists what LM Studio sees.
#     Models load from the Mac's own SSD, so load time is a fair result.
#
#  3) CLEAN (when a loaner is about to ship, or to free space)
#     zsh att-models.zsh clean
#     Lists the models in this Mac's LM Studio and deletes the ones you pick
#     (asks first). Never touches the LaCie.
#
#  Quit LM Studio before load/clean so it rescans when it opens again.
# =============================================================================

zmodload zsh/datetime
NAME="Adam Talks Tech Tests"
LOCAL="${LMS_MODELS:-$HOME/.lmstudio/models}"
HEADROOM_GB=${HEADROOM_GB:-30}

# Find the LaCie copy of LM Studio Models
# Model source: the "LM Studio Models" folder next to this script if it has models
# (folder dragged into ~/Downloads), otherwise the copy on a plugged-in drive.
LACIE=""
_HERE=${0:A:h}
[[ -n "$(print -l "$_HERE/LM Studio Models"/*/*(N/))" ]] && LACIE="$_HERE/LM Studio Models"
[[ -z $LACIE ]] && for d in /Volumes/*/"$NAME"/"AI Tests"/"LM Studio Models"(N/); do LACIE=$d; break; done

size_gb() { du -sk "$1" 2>/dev/null | awk '{printf "%.1f", $1/1048576}'; }
free_kb() { df -k "$1" | awk 'NR==2{print $4}'; }

# List model folders (publisher/model) under a root
list_models() {
  local root=$1 p m
  for p in "$root"/*(N/); do
    for m in "$p"/*(N/); do print -r -- "${p:t}/${m:t}"; done
  done
}

pick() {   # $1 = root; prints chosen relative paths, one per line
  local root=$1 i n
  local -a models chosen
  models=("${(@f)$(list_models "$root")}")
  [[ -z ${models[1]} ]] && { print -u2 "No models found in $root"; return 1; }
  for (( i = 1; i <= ${#models}; i++ )); do
    printf "  %2d) %-60s %6s GB\n" $i "${models[$i]}" "$(size_gb "$root/${models[$i]}")" >&2
  done
  print -n -u2 "Which? (numbers with spaces, or a = all): "; read -r ans
  if [[ $ans == a ]]; then chosen=($models)
  else for n in ${=ans}; do [[ $n == <1-> && $n -le ${#models} ]] && chosen+=("${models[$n]}"); done; fi
  print -l -- $chosen
}

copy_models() {   # $1 from root, $2 to root, rest = relative model paths
  local from=$1 to=$2 rel need have
  shift 2
  for rel in "$@"; do
    [[ -d "$to/$rel" ]] && { print "  Already there: $rel (skipped)"; continue; }
    need=$(du -sk "$from/$rel" | awk '{print $1}')
    have=$(free_kb "$to")
    if (( have - need < HEADROOM_GB * 1048576 )); then
      print "  !! Not enough room for $rel ($(size_gb "$from/$rel") GB). Keeps ${HEADROOM_GB}GB spare."; continue
    fi
    print "  Copying $rel ($(size_gb "$from/$rel") GB)..."
    mkdir -p "$to/${rel:h}"
    local t0=$EPOCHSECONDS
    ditto "$from/$rel" "$to/$rel" || { print "  !! Copy failed: $rel"; continue; }
    print "  Done in $(( EPOCHSECONDS - t0 ))s"
  done
}

case ${1:-} in
  save)
    [[ -n $LACIE ]] || { print "Plug in the LaCie (can't find $NAME/AI Tests/LM Studio Models)."; exit 1; }
    [[ -d $LOCAL ]] || { print "No LM Studio models on this Mac ($LOCAL)."; exit 1; }
    print "Models in this Mac's LM Studio:"
    sel=("${(@f)$(pick "$LOCAL")}") ; [[ -z ${sel[1]} ]] && exit 0
    copy_models "$LOCAL" "$LACIE" $sel
    print "\nOn the LaCie now:"; list_models "$LACIE" | sed 's/^/  /'
    ;;
  load)
    [[ -n $LACIE ]] || { print "Plug in the LaCie (can't find $NAME/AI Tests/LM Studio Models)."; exit 1; }
    pgrep -xq "LM Studio" && print "Tip: quit LM Studio first so it picks up the new models when it reopens."
    mkdir -p "$LOCAL"
    print "Models on the LaCie (free on this Mac: $(( $(free_kb "$HOME") / 1048576 )) GB):"
    sel=("${(@f)$(pick "$LACIE")}") ; [[ -z ${sel[1]} ]] && exit 0
    copy_models "$LACIE" "$LOCAL" $sel
    print "\nLM Studio on this Mac now has:"
    if [[ -x $HOME/.lmstudio/bin/lms ]]; then "$HOME/.lmstudio/bin/lms" ls 2>/dev/null | sed 's/^/  /'
    else list_models "$LOCAL" | sed 's/^/  /'; fi
    ;;
  clean)
    [[ -d $LOCAL ]] || { print "No LM Studio models on this Mac."; exit 0; }
    pgrep -xq "LM Studio" && print "Quit LM Studio first." && exit 1
    print "Models on THIS Mac:"
    sel=("${(@f)$(pick "$LOCAL")}") ; [[ -z ${sel[1]} ]] && exit 0
    for rel in $sel; do
      [[ -n $rel && -d "$LOCAL/$rel" && "$LOCAL/$rel" == "$LOCAL/"*/* ]] || continue
      print -n "  Delete $rel from this Mac? (y/n) "; read -r yn
      [[ $yn == [yY]* ]] && rm -rf -- "$LOCAL/$rel" && print "  Deleted."
    done
    rmdir "$LOCAL"/*(N/^F) 2>/dev/null   # drop empty publisher folders
    print "Free now: $(( $(free_kb "$HOME") / 1048576 )) GB"
    ;;
  *)
    print "Usage: zsh att-models.zsh save | load | clean   (see the top of this file)"; exit 1 ;;
esac

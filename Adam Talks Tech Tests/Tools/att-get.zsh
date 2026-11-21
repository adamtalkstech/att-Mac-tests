#!/bin/zsh
# =============================================================================
#  att-get.zsh  -  pull just the test files you need onto a small Mac, then
#                  free them again (v1, Nov 20 2026)
# =============================================================================
#  The kits (Air Kit, Mini Kit) carry the scripts but not every big test folder.
#  This copies the big pieces from a plugged-in test drive into this Mac's
#  ~/Downloads/Adam Talks Tech Tests (internal SSD, so tests stay fair), one at
#  a time, and deletes them again when you're done to make room for the next.
#
#    zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-get.zsh          pick what to copy
#    zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-get.zsh free     pick what to delete
#
#  AI models are separate: AI Tests/att-models.zsh load / clean.
#  It never touches Results, the scripts, or anything on the drive.
# =============================================================================

ROOT=${0:A:h:h}
[[ $ROOT == /Volumes/* ]] && { print "Run this from the Mac's own copy in ~/Downloads, not the drive."; exit 1; }
MODE=${1:-get}

# label | path inside "Adam Talks Tech Tests" (GAMES = the games folder at the top of the drive)
ITEMS=(
  "Stacker + Final Cut exports|Final Cut Test"
  "HandBrake|HandBrake Test"
  "Lightroom exports|Lightroom Test"
  "Puget Bench test files|Puget Test/Assets"
  "Blender standard test (Barbershop)|Blender Test/barbershop_interior.blend"
  "Blender extra scene (UDIM monster)|Blender Test/UDIM_monster"
  "Draw Things / image gen|Image Gen Test"
  "WebKit build|WebKit Test"
  "Logic big session|Logic Test - Big Session"
  "Logic track count|Logic Test"
  "Xcode|Xcode Test"
  "App installers|Apps & Installers"
  "Cyberpunk + War Thunder (games)|GAMES"
)
[[ $MODE == free ]] && ITEMS+=("Model copies in the test folder (LM Studio keeps its own)|AI Tests/LM Studio Models")

local_path() { [[ $1 == GAMES ]] && print -r -- "$HOME/Downloads/Adam Talks Tech Games" || print -r -- "$ROOT/$1"; }
size_of() { [[ -e $1 ]] && du -sh "$1" 2>/dev/null | cut -f1 || print -- "-"; }
free_gb() { df -g "$HOME" | awk 'NR==2{print $4}'; }

if [[ $MODE == get ]]; then
  DRV=""
  for d in /Volumes/*/"Adam Talks Tech Tests"(N/); do [[ -d "$d/Final Cut Test" || -d "$d/HandBrake Test" ]] && { DRV=$d; break; }; done
  [[ -z $DRV ]] && { print "Plug in a test drive (PRO-G40, LaCie or Extreme Pro)."; exit 1; }
  print "Drive: ${DRV:h}    Free on this Mac: $(free_gb) GB\n"
  typeset -a avail
  for it in $ITEMS; do
    rel=${it#*|}; lab=${it%%|*}
    [[ $rel == GAMES ]] && src="${DRV:h}/Adam Talks Tech Games" || src="$DRV/$rel"
    [[ -e $src ]] || continue
    avail+=("$lab|$rel|$src")
    here=$([[ -e $(local_path $rel) ]] && print "already here" || print "")
    printf "  %2d) %-40s %6s  %s\n" ${#avail} "$lab" "$(size_of "$src")" "$here"
  done
  print -n "\nNumbers to copy (e.g. 1 2), Return to cancel: "; read -r picks
  for p in ${=picks}; do
    [[ $p == <1-> && $p -le ${#avail} ]] || { print "Skipping $p"; continue; }
    e=${avail[$p]}; lab=${e%%|*}; rest=${e#*|}; rel=${rest%%|*}; src=${rest#*|}
    dst=$(local_path $rel)
    need=$(( $(du -sk "$src" | cut -f1) / 1048576 + 5 ))
    (( $(free_gb) < need )) && { print "!! Not enough space for $lab (needs ~${need} GB, $(free_gb) GB free). Free something first: zsh \"$0\" free"; continue; }
    print "Copying $lab ..."
    mkdir -p "${dst:h}"
    ditto "$src" "$dst" && print "  done: $dst" || print "  !! copy failed: $lab"
  done
  print "\nFree on this Mac now: $(free_gb) GB"
  exit 0
fi

if [[ $MODE == free ]]; then
  print "Free on this Mac: $(free_gb) GB   (the drives keep their copies; Results are never touched)\n"
  typeset -a here
  for it in $ITEMS; do
    rel=${it#*|}; lab=${it%%|*}; p=$(local_path $rel)
    [[ -e $p ]] || continue
    here+=("$lab|$p")
    printf "  %2d) %-55s %6s\n" ${#here} "$lab" "$(size_of "$p")"
  done
  (( ${#here} )) || { print "Nothing big to free in the test folder."; exit 0; }
  print -n "\nNumbers to DELETE from this Mac (e.g. 1 3), Return to cancel: "; read -r picks
  [[ -z $picks ]] && exit 0
  print -n "Delete them from this Mac? The drive still has them. Type yes: "; read -r ok
  [[ $ok == yes ]] || { print "Nothing deleted."; exit 0; }
  for p in ${=picks}; do
    [[ $p == <1-> && $p -le ${#here} ]] || continue
    e=${here[$p]}; rm -rf "${e#*|}" && print "  deleted: ${e%%|*}"
  done
  print "\nFree on this Mac now: $(free_gb) GB"
  exit 0
fi

print "Use:  zsh att-get.zsh      (copy)   or   zsh att-get.zsh free   (delete)"

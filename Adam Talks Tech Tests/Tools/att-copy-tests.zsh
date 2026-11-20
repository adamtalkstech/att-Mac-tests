#!/bin/zsh
# =============================================================================
#  att-copy-tests.zsh  -  put the test folder on a Mac (v1, Nov 16 2026)
# =============================================================================
#  The whole "Adam Talks Tech Tests" folder is about 140GB, so it doesn't fit
#  on a 256GB Mac and squeezes a 512GB one. This copies it in pieces:
#  the small stuff always, the big test blocks one at a time, and it removes a
#  block when you're done with it so the next one fits.
#
#  Everything lands in:  ~/Downloads/Adam Talks Tech Tests   (same layout as
#  the LaCie, so every script works the same from there).
#
#  Run it from the LaCie (drag into Terminal):
#     zsh "/Volumes/LaCie USB4/Adam Talks Tech Tests/Tools/att-copy-tests.zsh"
#  Then pick from the menu.
#
#  Safety: it only ever deletes block folders inside
#  ~/Downloads/Adam Talks Tech Tests on THIS Mac. Never anything on the LaCie.
# =============================================================================

zmodload zsh/datetime
NAME="Adam Talks Tech Tests"
HEADROOM_GB=${HEADROOM_GB:-40}   # always leave this much free after a copy

# ---------- Find the LaCie copy (source) ----------
SCRIPT_DIR=${0:A:h}
SRC=$SCRIPT_DIR
while [[ $SRC != / && ${SRC:t} != $NAME ]]; do SRC=${SRC:h}; done
if [[ $SRC == / || $SRC != /Volumes/* ]]; then
  SRC=""
  for d in /Volumes/*/"$NAME"(N/); do SRC=$d; break; done
fi
[[ -n $SRC ]] || { print "Can't find \"$NAME\" on a plugged-in drive. Plug in the LaCie."; exit 1; }
DEST="$HOME/Downloads/$NAME"
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

# Small blocks: always copied. Big blocks: one at a time, on request.
SMALL=("_Read Me First" "Tools" "AI Tests" "Blender Test" "Gaming Test" "Memory Test" "SSD Test" "Xcode Test" "Logic Test")
BIG=("Final Cut Test" "Lightroom Test" "Logic Test - Big Session" "WebKit Test" "HandBrake Test" "Puget Test" "Apps & Installers")
# Folders inside AI Tests that are too big to copy with the small stuff
AI_BIG=("LM Studio Models" "Whisper Test" "Image Tests")

free_gb()  { df -g "$HOME" | awk 'NR==2{print $4}'; }
size_gb()  { [[ -e $1 ]] && du -sk "$1" 2>/dev/null | awk '{printf "%.1f", $1/1048576}' || print 0; }
size_kb()  { [[ -e $1 ]] && du -sk "$1" 2>/dev/null | awk '{print $1}' || print 0; }

copy_block() {   # $1 = path relative to the test folder
  local rel=$1 need_kb free_kb
  [[ -e "$SRC/$rel" ]] || { print "  Not on the LaCie: $rel"; return 1; }
  need_kb=$(size_kb "$SRC/$rel")
  free_kb=$(df -k "$HOME" | awk 'NR==2{print $4}')
  if (( free_kb - need_kb < HEADROOM_GB * 1048576 )); then
    print "  !! Not enough room for $rel ($(size_gb "$SRC/$rel") GB). Free now: $(free_gb) GB,"
    print "     and it keeps ${HEADROOM_GB} GB spare. Remove a big block first (option 3)."
    return 1
  fi
  print "  Copying $rel ($(size_gb "$SRC/$rel") GB)..."
  local t0=$EPOCHSECONDS
  mkdir -p "$DEST/${rel:h}"
  ditto "$SRC/$rel" "$DEST/$rel" || { print "  !! Copy failed: $rel"; return 1; }
  print "  Done in $(( EPOCHSECONDS - t0 ))s. Free now: $(free_gb) GB"
}

log_free() {
  mkdir -p "$DEST/Results/$MACNAME"
  print "$(strftime '%F %H:%M' $EPOCHSECONDS),$1,$(free_gb)" >> "$DEST/Results/$MACNAME/free-space-log.csv"
}

status() {
  print ""
  print "This Mac: $MACNAME   Free: $(free_gb) GB   Keeps ${HEADROOM_GB} GB spare"
  print "On this Mac (~/Downloads/$NAME):"
  local b any=0
  for b in $SMALL $BIG "AI Tests/"${^AI_BIG}; do
    [[ -e "$DEST/$b" ]] && { printf "   %-34s %6s GB\n" "$b" "$(size_gb "$DEST/$b")"; any=1; }
  done
  (( any )) || print "   (nothing yet)"
}

while true; do
  status
  print ""
  print "  1) Set up this Mac: copy the small folders (scripts, prompts, Blender, Xcode, Logic)"
  print "  2) Copy a big block"
  print "  3) Remove a big block from this Mac (when its tests are done)"
  print "  4) Copy this Mac's Results back to the LaCie"
  print "  5) Sizes of everything on the LaCie"
  print "  q) Quit"
  print -n "Pick: "; read -r c
  case $c in
    1)
      log_free "before setup"
      for b in $SMALL; do
        if [[ $b == "AI Tests" ]]; then
          # prompts and scripts only; models/kits are big blocks
          mkdir -p "$DEST/AI Tests"
          for f in "$SRC/AI Tests"/*(N); do
            [[ -d $f && ${AI_BIG[(Ie)${f:t}]} -gt 0 ]] && continue
            ditto "$f" "$DEST/AI Tests/${f:t}"
          done
          print "  Copied AI Tests (prompts and scripts)"
        else
          copy_block "$b"
        fi
      done
      log_free "after setup" ;;
    2)
      opts=($BIG "AI Tests/"${^AI_BIG})
      for (( i = 1; i <= ${#opts}; i++ )); do
        printf "   %d) %-34s %6s GB%s\n" $i "${opts[$i]}" "$(size_gb "$SRC/${opts[$i]}")" "$([[ -e "$DEST/${opts[$i]}" ]] && print '  (already here)')"
      done
      print -n "   Which: "; read -r n
      [[ $n == <1-> && $n -le ${#opts} ]] || { print "  Not on the list."; continue; }
      [[ -e "$DEST/${opts[$n]}" ]] && { print "  Already on this Mac."; continue; }
      log_free "before ${opts[$n]}"
      copy_block "${opts[$n]}" && log_free "after ${opts[$n]}"
      [[ ${opts[$n]} == "WebKit Test" ]] && print "  Next: untar it on this Mac:  cd \"$DEST/WebKit Test\" && tar -xf WebKit.tar"
      [[ ${opts[$n]} == "AI Tests/LM Studio Models" ]] && print "  Next: in LM Studio > My Models, point the models folder here, or move them to ~/.lmstudio/models"
      ;;
    3)
      here=()
      for b in $BIG "AI Tests/"${^AI_BIG}; do [[ -e "$DEST/$b" ]] && here+=("$b"); done
      (( ${#here} )) || { print "  No big blocks on this Mac."; continue; }
      for (( i = 1; i <= ${#here}; i++ )); do printf "   %d) %-34s %6s GB\n" $i "${here[$i]}" "$(size_gb "$DEST/${here[$i]}")"; done
      print -n "   Remove which (from THIS Mac only): "; read -r n
      [[ $n == <1-> && $n -le ${#here} ]] || { print "  Not on the list."; continue; }
      target="$DEST/${here[$n]}"
      [[ $target == "$HOME/Downloads/$NAME/"* && -n ${here[$n]} ]] || { print "  Refusing: unexpected path."; continue; }
      print -n "   Delete $target ? (y/n) "; read -r yn
      [[ $yn == [yY]* ]] && rm -rf -- "$target" && print "  Removed. Free now: $(free_gb) GB" && log_free "removed ${here[$n]}"
      ;;
    4)
      [[ -d "$DEST/Results" ]] || { print "  No Results folder on this Mac yet."; continue; }
      mkdir -p "$SRC/Results"
      ditto "$DEST/Results" "$SRC/Results" && print "  Results copied to the LaCie: $SRC/Results"
      ;;
    5)
      for b in $SMALL $BIG "AI Tests/"${^AI_BIG}; do
        [[ -e "$SRC/$b" ]] && printf "   %-34s %6s GB\n" "$b" "$(size_gb "$SRC/$b")"
      done ;;
    q|Q) exit 0 ;;
    *) print "  Pick 1-5 or q." ;;
  esac
done

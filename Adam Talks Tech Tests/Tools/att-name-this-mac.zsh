#!/bin/zsh
# =============================================================================
#  att-name-this-mac.zsh  -  ATT name wallpaper + Mac name (v1, Nov 16 2026)
# =============================================================================
#  Sets a big-name wallpaper and renames the Mac, so every photo, screenshot
#  and script result shows which Mac it came from.
#
#  Run:  zsh att-name-this-mac.zsh       then pick a number from the list
#  The wallpapers are in the "Mac Name Wallpapers" folder next to this script.
#  It copies the picked one to ~/Pictures so it stays after the drive is unplugged.
#  Renaming asks for your password once (sudo). Skip it with NONAME=1.
# =============================================================================

DIR="${0:A:h}/Mac Name Wallpapers"
pics=("$DIR"/*.png(N))
(( ${#pics} )) || { print "No wallpapers found in: $DIR"; exit 1; }

print "Which Mac is this?"
for (( i = 1; i <= ${#pics}; i++ )); do printf "  %2d) %s\n" $i "${${pics[$i]:t:r}//_/ }"; done
print -n "Number: "; read -r pick
[[ $pick == <1-> && $pick -le ${#pics} ]] || { print "Not a number on the list."; exit 1; }

SRC="${pics[$pick]}"
NAME="${${SRC:t:r}//_/ }"
mkdir -p "$HOME/Pictures/ATT"
DEST="$HOME/Pictures/ATT/${SRC:t}"
cp "$SRC" "$DEST"

osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$DEST\"" \
  && print "Wallpaper set: $NAME" || print "Couldn't set the wallpaper. Allow Terminal to control System Events, or set it by hand: $DEST"

if [[ $NONAME != 1 ]]; then
  SHORT=${NAME// /-}
  print "Renaming this Mac to \"$NAME\" (asks for your password)..."
  sudo scutil --set ComputerName "$NAME" && sudo scutil --set LocalHostName "$SHORT" \
    && print "Mac renamed. Scripts will print \"$NAME\" in their results."
fi

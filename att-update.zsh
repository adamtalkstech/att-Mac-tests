#!/bin/zsh
# =============================================================================
#  att-update.zsh  -  get the latest ATT test scripts on this Mac
# =============================================================================
#  Run on any test Mac (no GitHub login needed):
#    curl -fsSL https://raw.githubusercontent.com/adamtalkstech/att-Mac-tests/main/att-update.zsh | zsh
#  It downloads the newest scripts and instructions from GitHub and copies them
#  over ~/Downloads/Adam Talks Tech Tests. Only scripts and text files change:
#  Results, models, games, apps, license keys and test footage are never touched.
# =============================================================================
REPO=${ATT_REPO:-adamtalkstech/att-Mac-tests}
DEST=${ATT_DEST:-"$HOME/Downloads/Adam Talks Tech Tests"}
TMP=$(mktemp -d)
print "Getting the latest ATT test scripts from github.com/$REPO ..."
curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.zip" -o "$TMP/latest.zip" \
  || { print "Download failed. Check the internet connection."; exit 1; }
ditto -x -k "$TMP/latest.zip" "$TMP/x" || { print "Couldn't unpack the download."; exit 1; }
SRC=$(print -l "$TMP"/x/*/"Adam Talks Tech Tests"(N/) | head -1)
[[ -d $SRC ]] || { print "The download didn't have the test folder in it."; exit 1; }
if [[ ! -d $DEST ]]; then
  print "No test folder at $DEST yet. Drag \"Adam Talks Tech Tests\" from a test drive into Downloads first,"
  print "then run this again (the big files only come from the drive)."; exit 1
fi
n=$(find "$SRC" -type f | wc -l | tr -d ' ')
ditto "$SRC" "$DEST" || { print "Copy failed."; exit 1; }
find "$DEST" \( -name '*.sh' -o -name '*.zsh' -o -name '*.command' \) -exec chmod +x {} + 2>/dev/null
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
cp "$TMP"/x/*/VERSION.txt "$DEST/_Read Me First/SCRIPTS VERSION.txt" 2>/dev/null
# Nov 21: keep plugged-in test drives current too (scripts and text only, a few MB), so a Mac that
# copies the folder off a drive starts with today's scripts. Skip with ATT_NODRIVES=1.
if [[ -z $ATT_NODRIVES ]]; then
  for v in /Volumes/*/"Adam Talks Tech Tests"(N/); do
    [[ $v == $DEST ]] && continue
    ditto "$SRC" "$v" 2>/dev/null && cp "$TMP"/x/*/VERSION.txt "$v/_Read Me First/SCRIPTS VERSION.txt" 2>/dev/null && print "Also updated the scripts on ${v:h:t}"
  done
fi
rm -rf "$TMP"
print "Updated $n script and instruction files in $DEST"
print "Version: $(head -1 "$DEST/_Read Me First/SCRIPTS VERSION.txt" 2>/dev/null)"
# Show this Mac's next tests (00 RUN THIS NEXT) in TextEdit
[[ -f "$DEST/Tools/att-next.zsh" ]] && { print ""; zsh "$DEST/Tools/att-next.zsh" >/dev/null 2>&1 && print "Opened this Mac's RUN THIS NEXT list in TextEdit."; }

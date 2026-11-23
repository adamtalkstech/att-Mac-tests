#!/bin/zsh
# Double-click to update the ATT test scripts on this Mac.
# Online: pulls the newest from GitHub. Offline: copies just the scripts and
# instructions from a plugged-in test drive. Results, models, games, apps and
# test files are never touched.
DEST="$HOME/Downloads/Adam Talks Tech Tests"
print "Updating ATT test scripts in $DEST ..."
if curl -fsSL https://raw.githubusercontent.com/adamtalkstech/att-Mac-tests/main/att-update.zsh -o /tmp/att-update.zsh 2>/dev/null; then
  zsh /tmp/att-update.zsh
else
  print "No internet. Looking for a plugged-in test drive instead..."
  SRC=$(print -l /Volumes/*/"Adam Talks Tech Tests"(N/) | head -1)
  if [[ -z $SRC || ! -d $DEST ]]; then
    print "Couldn't update: no internet and no test drive (or no test folder in Downloads yet)."
  else
    rsync -a --exclude 'Results/' --exclude '_To Delete/' --exclude '*LICENSES*' --include '*/' \
      --include '*.sh' --include '*.zsh' --include '*.command' --include '*.txt' --include '*.py' \
      --include '*.json' --include '*.md' --include '*.swift' --include '*.js' --include '*.c' --include '*.gs' --exclude '*' "$SRC/" "$DEST/" \
      && print "Updated from $SRC" && print "Version: $(head -1 "$DEST/_Read Me First/SCRIPTS VERSION.txt" 2>/dev/null)"
  fi
fi
print ""
read -r "?Done. Press Return to close this window."

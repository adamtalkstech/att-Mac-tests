#!/bin/zsh
# =============================================================================
#  Match all test drives.command  (Nov 22 2026)
#  Double-click on the Mac Studio with the test drives plugged in. Makes every plugged-in test drive
#  (LaCie, P9, P7, PRO-G40, Extreme Pro, OWC Envoy) have the same:
#     Adam Talks Tech Tests · Adam Talks Tech Games (not the OWC: it's the mini/Air drive)
#     Mini Kit (Mac minis) · Mini Kit FULL (512GB minis) · Air Kit (small Macs)
#  Source for each folder = the plugged-in drive with the biggest copy of it. Copies only what's new or
#  changed; nothing is deleted. Then refreshes the scripts inside every kit to match the main folder.
#  Safe to stop and run again. The upload key file is copied too (Adam's call: these drives stay home).
# =============================================================================
setopt null_glob
DRIVES=( /Volumes/(LaCie*|P9*|P7*|PRO-G40*|*Extreme*|OWC*)(/) )
(( ${#DRIVES} >= 2 )) || { print "Plug in at least two test drives."; read -k1; exit 1; }
FOLDERS=("Adam Talks Tech Tests" "Adam Talks Tech Games" "Mini Kit (Mac minis)" "Mini Kit FULL (512GB minis)" "Air Kit (small Macs)")
EXCL=(--exclude='.Spotlight-V100' --exclude='.fseventsd' --exclude='.Trashes' --exclude='.TemporaryItems'
      --exclude='.DocumentRevisions-V100' --exclude='.DS_Store' --exclude='._*' --exclude='_To Delete' --exclude='Results')
print "Drives: ${(j:, :)${DRIVES#/Volumes/}}\n"
for f in $FOLDERS; do
  src=""; best=0
  for d in $DRIVES; do [[ -d "$d/$f" ]] || continue; s=$(du -sk "$d/$f" 2>/dev/null | cut -f1); (( s > best )) && { best=$s; src="$d/$f"; }; done
  [[ -z $src ]] && { print "!! No drive has \"$f\" (skipped)"; continue; }
  print "=== $f  (from ${${src#/Volumes/}%%/*}, $(( best / 1048576 )) GB)"
  for d in $DRIVES; do
    [[ "$d/$f" == "$src" ]] && continue
    [[ $f == "Adam Talks Tech Games" && $d == /Volumes/OWC* ]] && { print "   skip OWC (no games on the mini/Air drive)"; continue; }
    free=$(df -k "$d" | awk 'NR==2{print $4}')
    have=$(du -sk "$d/$f" 2>/dev/null | cut -f1); need=$(( best - ${have:-0} ))
    if (( need > free )); then print "!! ${d#/Volumes/}: not enough room for $f (needs ~$(( need / 1048576 )) GB more, has $(( free / 1048576 )) GB). Skipped."; continue; fi
    print "-> ${d#/Volumes/}"
    rsync -a -u $EXCL "$src"/ "$d/$f"/ 2>&1 | grep -v "^$" | tail -3
  done
done
print "\n=== Refreshing the scripts inside each kit (only files the kit already has) ==="
for d in $DRIVES; do
  main="$d/Adam Talks Tech Tests"; [[ -d $main ]] || continue
  for k in "$d/Mini Kit (Mac minis)" "$d/Mini Kit FULL (512GB minis)" "$d/Air Kit (small Macs)"; do
    [[ -d $k ]] || continue
    for t in "$k"/**/"Adam Talks Tech Tests"(/); do
      rsync -a --existing --include='*/' --include='*.zsh' --include='*.sh' --include='*.txt' --include='*.js' --include='*.c' \
        --include='*.swift' --include='*.py' --include='*.md' --include='*.command' --include='*.gs' --exclude='*' $EXCL "$main"/ "$t"/ 2>/dev/null
    done
  done
  print "   ${d#/Volumes/}: kits refreshed"
done
print "\nAll drives match. Press any key to close."; read -k1

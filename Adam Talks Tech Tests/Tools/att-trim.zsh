#!/bin/zsh
# =============================================================================
#  att-trim.zsh  -  park big, rarely used stuff on a test drive (v1, Nov 21 2026)
# =============================================================================
#  Moves the folders you pick OUT of "Adam Talks Tech Tests" on a drive into
#  "ATT Spare (not copied)" at the top of the SAME drive. Nothing is deleted.
#  Same-drive moves are instant. Dragging the test folder to a Mac (or
#  att-copy-tests.zsh) then skips them, so copies are smaller and faster.
#
#    zsh att-trim.zsh            list everything over 1 GB, ask y/n for each
#    zsh att-trim.zsh restore    put parked folders back (asks for each)
#
#  Suggested to park (Nov 21): Logic Test - Big Session, WebKit Test, the 27B
#  5/6/8-bit and MoE models, old Gemma builds, the mflux cache, old installers.
#  LM Studio models parked here still load: att-models.zsh looks in the spare
#  folder too (the 8-bit ladder rung still works).
# =============================================================================
NAME="Adam Talks Tech Tests"; SPARE="ATT Spare (not copied)"
drives=(/Volumes/*/"$NAME"(N/))
(( ${#drives} )) || { print "No test drive plugged in (looking for /Volumes/<drive>/$NAME)."; exit 1; }
for T in $drives; do
  V=${T:h}; S="$V/$SPARE"
  print "\n=== Drive: ${V:t} ==="
  if [[ $1 == restore ]]; then
    [[ -d $S ]] || { print "Nothing parked on this drive."; continue; }
    for f in ${(f)"$(cd "$S" && find . -mindepth 1 -maxdepth 4 -name '.att-parked' -prune -o -type d -print 2>/dev/null | while read -r d; do [[ -f "$S/$d/.att-parked" ]] && print -r -- "${d#./}"; done)"}; do
      [[ -z $f ]] && continue
      print -n "Put back  $f  ($(du -sh "$S/$f" | cut -f1))? (y/n) "; read -r yn
      [[ $yn == [yY]* ]] || continue
      mkdir -p "$T/${f:h}"; rm -f "$S/$f/.att-parked"; mv "$S/$f" "$T/$f" && print "  back in place"
    done
    continue
  fi
  print "Big items in $NAME (over 1 GB), biggest first. Answer y to park one."
  # top-level folders, plus one level down inside AI Tests / Image Gen Test (models, caches)
  list=()
  for d in "$T"/*(N/) "$T"/"AI Tests"/*(N/) "$T"/"AI Tests"/"LM Studio Models"/*/*(N/) "$T"/"Image Gen Test"/*(N/) "$T"/"Image Gen Test"/.*(N/) "$T"/"Apps & Installers"/*(N); do
    [[ $d == "$T/Results" || $d == "$T/Tools" || $d == "$T/Commands" || $d == "$T/AI Tests" || $d == "$T/Image Gen Test" || $d == "$T/Apps & Installers" ]] && continue
    [[ $d == "$T/AI Tests/LM Studio Models" ]] && continue
    k=$(du -sk "$d" 2>/dev/null | cut -f1); (( k > 1048576 )) && list+=("$k|$d")
  done
  for e in ${(On)list}; do
    k=${e%%|*}; d=${e#*|}; rel=${d#$T/}
    printf "Park  %-60s %6.1f GB ? (y/n) " "$rel" $(( k / 1048576.0 )); read -r yn
    [[ $yn == [yY]* ]] || continue
    mkdir -p "$S/${rel:h}"; mv "$d" "$S/$rel" && touch "$S/$rel/.att-parked" 2>/dev/null; print "  parked -> $SPARE/$rel"
  done
  print "Free on ${V:t}: $(df -h "$V" | awk 'NR==2{print $4}')"
done
print "\nDone. Nothing was deleted. Undo any time: zsh att-trim.zsh restore"

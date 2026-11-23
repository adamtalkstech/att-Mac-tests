#!/bin/zsh
# =============================================================================
#  att-space.zsh - free up SSD space on a TEST Mac (v2, Nov 23 2026)
# =============================================================================
#  zsh att-space.zsh            full cleanup: one y/n for the safe stuff, then asks item by item
#  zsh att-space.zsh auto       no questions: things the tests rebuild, models this Mac can't run,
#                               duplicate copies; then, if still under 45 GB, big test folders that a
#                               plugged-in drive has a full copy of and this run doesn't need. The
#                               walk-away queue runs this by itself when the Mac is under 45 GB free.
#  zsh att-space.zsh report     only shows what's taking space, deletes nothing
#
#  v2 (Adam: "make it very robust to clear the files"):
#   - quits the test apps first (Final Cut, Logic, LM Studio, Xcode, Simulator...) so files aren't in use
#   - checks every delete actually happened and says what failed and why (locked files are unlocked;
#     "Operation not permitted" = Terminal needs Full Disk Access, it tells you where to turn it on)
#   - a big test folder is only offered as "safe" when a plugged-in test drive has a full copy of it
#     (size checked); without a drive it warns you that you'd have to copy it back by hand
#   - more places tests leave junk: Xcode DeviceSupport/Archives/caches, every Final Cut library's
#     render files, Whisper/pip/Hugging Face caches, duplicate model copies, old copies of the test kit,
#     macOS installers in Applications, Time Machine snapshots (one by one, then re-checked)
#   - writes what it freed to Results/space-log.txt
#  Never touches: Results, the scripts, Photos, Mail, Documents/Desktop, anything on a drive.
# =============================================================================
MODE=${1:-ask}; [[ $MODE == (ask|auto|report) ]] || { print "Use:  zsh att-space.zsh   |   auto   |   report"; exit 1; }
ROOT=${0:A:h:h}
[[ -d "$ROOT/Tools" && $ROOT == $HOME/* ]] || { print "Can't find the test folder (got: $ROOT). Run this from inside Adam Talks Tech Tests/Tools."; exit 1; }
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
gb()  { df -k / | awk 'NR==2{printf "%.0f", $4/1048576}'; }
kb()  { du -skx "$@" 2>/dev/null | awk '{s+=$1} END{print s+0}'; }
fmt() { awk -v k=$1 'BEGIN{printf "%.1f", k/1048576}'; }
START=$(gb); FREED=0; typeset -a FAILED DONE
print "ATT space check on $(scutil --get ComputerName 2>/dev/null) (${RAM}GB RAM): ${START} GB free   [mode: $MODE]\n"

# ---- safety: only ever delete inside home or the test folder, never Results/scripts/personal folders ----
okpath() {
  local p=${1:A}
  [[ $p == $HOME/* ]] || [[ $p == /Applications/Install\ macOS*.app ]] || return 1
  [[ $p == "$ROOT" || $p == "$ROOT/Results"* || $p == "$ROOT/Tools"* || $p == "$ROOT/Experiments"* ]] && return 1
  [[ $p == $HOME/(Pictures|Documents|Desktop|Library/Mail|Library/Mobile\ Documents)(|/*) ]] && return 1
  [[ $p == /Volumes/* ]] && return 1
  return 0
}

# ---- the delete itself: unlock, delete, check it's gone, explain a failure ----
NEEDFDA=0
zap() {   # $1 label, rest = paths
  local label=$1; shift; local p before after left
  for p; do okpath "$p" || { FAILED+=("$label: refused (protected place) ${p/#$HOME/~}"); return 1; }; done
  before=$(kb "$@")
  for p; do
    [[ -e $p || -L $p ]] || continue
    chflags -R nouchg,noschg "$p" 2>/dev/null; chmod -R u+w "$p" 2>/dev/null
    rm -rf "$p" 2>/tmp/att-space.err
    if [[ -e $p ]]; then   # second try: whatever is left, file by file
      find "$p" -depth -mindepth 0 -exec rm -rf {} + 2>>/tmp/att-space.err
    fi
  done
  after=0; for p; do [[ -e $p ]] && (( after += $(kb "$p") )); done
  (( FREED += before - after ))
  if (( after > 102400 )); then
    grep -qi "not permitted" /tmp/att-space.err && NEEDFDA=1
    FAILED+=("$label: $(fmt $after) GB couldn't be deleted ($(head -1 /tmp/att-space.err | sed 's/^rm: //' | cut -c1-80))")
    print "    !! only part deleted, $(fmt $after) GB left"
    return 1
  fi
  DONE+=("$label $(fmt $before) GB"); print "    deleted ($(fmt $before) GB)"
}
ask() {   # $1 label, rest = paths. Asks in ask mode; never deletes in report mode.
  local label=$1; shift; local k=$(kb "$@"); (( k < 51200 )) && return   # skip under 50 MB
  case $MODE in
    report) printf "  %6s GB  %s\n" $(fmt $k) "$label";;
    auto)   printf "  %6s GB  %s\n" $(fmt $k) "$label"; zap "$label" "$@";;
    ask)    printf "  Delete %-62s %6s GB ? (y/n) " "$label" $(fmt $k); read -r yn; [[ $yn == [yY]* ]] && zap "$label" "$@";;
  esac
}

# ---- 0. quit the apps that hold test files open ----
if [[ $MODE != report ]]; then
  for a in "Final Cut Pro" "Final Cut Pro Creator Studio" "Logic Pro" "LM Studio" "Xcode" "Simulator" "Blender" "HandBrake" "Lightroom Classic" "Compressor" "Docker Desktop"; do
    pgrep -xq "$a" || continue
    print "Quitting $a (it may have test files open)..."; osascript -e "quit app \"$a\"" >/dev/null 2>&1 &
    for i in {1..20}; do pgrep -xq "$a" || break; sleep 1; done
    pgrep -xq "$a" && pkill -x "$a" 2>/dev/null
  done
  pkill -f "llama-server|lms server" 2>/dev/null
fi

# ---- 1. SAFE: the tests rebuild all of these on their own ----
typeset -a SAFE SAFELBL
safe() { local l=$1; shift; local p; for p; do [[ -e $p ]] && { SAFE+=("$p"); SAFELBL+=("$l"); }; done; }
safe "SSD test scratch (a run was stopped)"        $HOME/.att/ssdtest(N/) $HOME/.att/ssd-*(N)
safe "Xcode build folders"                          $HOME/Library/Developer/Xcode/DerivedData/*(N/) "$ROOT/Xcode Test"/**/DerivedData-run*.noindex(N/)
safe "Xcode device support files"                   $HOME/Library/Developer/Xcode/*DeviceSupport/*(N/)
safe "Xcode caches"                                 $HOME/Library/Caches/com.apple.dt.Xcode(N/) $HOME/Library/Developer/CoreSimulator/Caches/*(N/)
safe "Final Cut render files"                       "$ROOT"/**/*.fcpbundle/*/"Render Files"(N/) $HOME/Movies/**/*.fcpbundle/*/"Render Files"(N/)
safe "Final Cut cache"                              $HOME/Library/Caches/com.apple.FinalCut*(N/)
safe "test exports"                                 "$ROOT/Export"/*(N) "$ROOT/_To Delete"(N/) "$ROOT"/*/(Output|Exports|output)/*(N)
safe "finished Whisper downloads"                   $HOME/.att/whisper-dl(N/)
safe "Python and Whisper download caches"           $HOME/Library/Caches/pip(N/) $HOME/.cache/pip(N/) $HOME/.cache/whisper(N/)
safe "Homebrew download cache"                      $HOME/Library/Caches/Homebrew(N/)
safe "Blender cache"                                $HOME/Library/Caches/org.blenderfoundation.blender(N/) $HOME/Library/Caches/Blender(N/)
# keep only finished Whisper downloads: if the Whisper build isn't done, keep its download
grep -q CPUAndNeuralEngine "$ROOT/AI Tests/whisper-test/BUILD-INFO.txt" 2>/dev/null || { i=${SAFE[(i)$HOME/.att/whisper-dl]}; (( i <= ${#SAFE} )) && { SAFE[$i]=(); SAFELBL[$i]=(); }; }
# duplicate model copies: a model in the test folder that LM Studio also has in its own folder
for m in "$ROOT/AI Tests/LM Studio Models"/*/*(N/); do
  twin=$HOME/.lmstudio/models/${m:h:t}/${m:t}
  [[ -d $twin ]] && (( $(kb "$twin") >= $(kb "$m") * 98 / 100 )) && safe "duplicate model copy (LM Studio has its own)" "$m"
done
[[ -d $HOME/.cache/lm-studio/models && -d $HOME/.lmstudio/models ]] && for m in $HOME/.cache/lm-studio/models/*/*(N/); do
  [[ -d $HOME/.lmstudio/models/${m:h:t}/${m:t} ]] && safe "old LM Studio folder duplicate" "$m"
done
# models this Mac can't run (the tests skip them by RAM)
for m in $HOME/.lmstudio/models/*/*(N/); do
  n=${m:t}; why=""
  [[ $n =~ '27[Bb]' && $n =~ '(5|6|8)[-_]?bit' ]] && (( RAM < 36 )) && why="27B ladder build, 36GB+ only"
  [[ -z $why && $n =~ '27[Bb]' ]] && (( RAM < 24 )) && why="27B, 24GB+ only"
  [[ -z $why && $n =~ '(30[Bb]|A3[Bb]|[Mm]o[Ee])' ]] && (( RAM < 24 )) && why="30B-class, 24GB+ only"
  [[ -n $why ]] && safe "model $n (can't run here: $why)" "$m"
done
# old extra copies of the test kit (Downloads/"Adam Talks Tech Tests 2", zips of it) - never the live one
for d in $HOME/Downloads/"Adam Talks Tech Tests"*(N/) $HOME/Desktop/"Adam Talks Tech Tests"*(N/); do
  [[ ${d:A} == ${ROOT:A} ]] && continue
  [[ -d $d/Results && -n $(ls -A "$d/Results" 2>/dev/null) ]] && continue   # has results: leave it
  safe "old extra copy of the test kit" "$d"
done
safe "zipped copy of the test kit" $HOME/Downloads/Adam\ Talks\ Tech\ Tests*.(zip|tgz|tar.gz)(N.)

SNAPS=( ${(f)"$(tmutil listlocalsnapshotdates / 2>/dev/null | grep -E '^[0-9]{4}-')"} )
print "SAFE (the tests remake these or a copy exists):"
typeset -A SEEN; TOT=0
for (( i = 1; i <= ${#SAFE}; i++ )); do
  k=$(kb "${SAFE[$i]}"); (( k < 51200 )) && continue; (( TOT += k ))
  printf "  %6s GB  %s  %s\n" $(fmt $k) "${SAFELBL[$i]}" "${${SAFE[$i]}/#$HOME/~}"
done
(( ${#SNAPS} )) && print "     ?? GB  ${#SNAPS} Time Machine local snapshot(s) (hold deleted files; size unknown)"
command -v xcrun >/dev/null && print "     ?? GB  Xcode simulators that can't run anymore"
print "  ------\n  $(fmt $TOT) GB+ total"
go=0
case $MODE in auto) go=1;; ask) print -n "\nClear all of the SAFE list? (y/n) "; read -r yn; [[ $yn == [yY]* ]] && go=1;; esac
if (( go )); then
  for (( i = 1; i <= ${#SAFE}; i++ )); do [[ -e ${SAFE[$i]} ]] || continue; print "  ${SAFELBL[$i]}: ${${SAFE[$i]}:t}"; zap "${SAFELBL[$i]}" "${SAFE[$i]}"; done
  command -v xcrun >/dev/null && xcrun simctl delete unavailable >/dev/null 2>&1
  command -v brew >/dev/null && brew cleanup -s --prune=all >/dev/null 2>&1
  if (( ${#SNAPS} )); then
    if [[ $MODE == auto ]] && ! sudo -n true 2>/dev/null; then
      print "  (skipped ${#SNAPS} Time Machine snapshot(s): needs your password, run att-space.zsh by hand)"
    else
      print "  Time Machine snapshots (your Mac password):"
      for s in $SNAPS; do sudo tmutil deletelocalsnapshots "$s" >/dev/null 2>&1; done
      left=$(tmutil listlocalsnapshotdates / 2>/dev/null | grep -cE '^[0-9]{4}-')
      (( left )) && { sudo tmutil thinlocalsnapshots / 999999999999 4 >/dev/null 2>&1; left=$(tmutil listlocalsnapshotdates / 2>/dev/null | grep -cE '^[0-9]{4}-'); }
      (( left )) && FAILED+=("Time Machine: $left snapshot(s) still there (macOS may be backing up right now; try again later)") || DONE+=("${#SNAPS} Time Machine snapshot(s)")
    fi
  fi
  print "  Now $(gb) GB free."
fi

# ---- 1b. AUTO, still under 45 GB: offload big test folders a plugged-in drive has a FULL copy of,
#      but never one this run's tests need (the queue passes them in ATT_KEEP, "|"-separated).
#      The queue copies a folder back by itself the next time a test needs it.
if [[ $MODE == auto ]] && (( $(gb) < ${ATT_SPACE_TARGET:-45} )); then
  ADRV=( /Volumes/*/"Adam Talks Tech Tests"(N/) )
  if (( ${#ADRV} )); then
    print "\nStill under ${ATT_SPACE_TARGET:-45} GB: offloading test folders the drive has a full copy of"
    for rel in "AI Tests/LM Studio Models" "Puget Test/Assets" "Lightroom Test" "Image Gen Test" "Logic Test - Big Session" "Final Cut Test" "HandBrake Test" "WebKit Test" "Apps & Installers"; do
      (( $(gb) >= ${ATT_SPACE_TARGET:-45} )) && break
      p="$ROOT/$rel"; [[ -e $p ]] || continue; (( $(kb "$p") < 1048576 )) && continue
      [[ "|${ATT_KEEP}|" == *"|$rel|"* ]] && { print "  keeping $rel (a test in this run needs it)"; continue; }
      have=0; for d in $ADRV; do [[ -d "$d/$rel" ]] && (( $(kb "$d/$rel") >= $(kb "$p") * 98 / 100 )) && { have=1; break; }; done
      (( have )) || { print "  keeping $rel (no full copy on the drive)"; continue; }
      print "  $rel ($(fmt $(kb "$p")) GB, copy on ${${d#/Volumes/}%%/*})"; zap "offloaded $rel" "$p"
    done
    G="$HOME/Downloads/Adam Talks Tech Games"
    if (( $(gb) < ${ATT_SPACE_TARGET:-45} )) && [[ -d $G && "|${ATT_KEEP}|" != *"|Games|"* ]]; then
      for d in /Volumes/*/"Adam Talks Tech Games"(N/); do
        (( $(kb "$d") >= $(kb "$G") * 98 / 100 )) && { print "  games folder ($(fmt $(kb "$G")) GB, copy on ${${d#/Volumes/}%%/*})"; zap "offloaded games folder" "$G"; break; }
      done
    fi
  else
    print "\nStill under ${ATT_SPACE_TARGET:-45} GB and no test drive plugged in: plug one in so big test folders can be offloaded."
  fi
fi

# ---- 2. BIG ITEMS: asked one by one (never in auto mode) ----
if [[ $MODE != auto ]]; then
  print "\nBIG ITEMS:"
  DRIVES=( /Volumes/*/"Adam Talks Tech Tests"(N/) )
  (( ${#DRIVES} )) && print "  (test drive plugged in: ${${DRIVES[1]#/Volumes/}%%/*}, copies get checked)" || print "  (no test drive plugged in: test folders can't be checked against a copy)"
  oncopy() {   # is a full copy of $1 (relative path) on a plugged-in drive?
    local d; for d in $DRIVES; do [[ -d "$d/$1" ]] && (( $(kb "$d/$1") >= $(kb "$ROOT/$1") * 98 / 100 )) && { print -r -- "${${d#/Volumes/}%%/*}"; return 0; }; done; return 1
  }
  for rel in "Final Cut Test" "Logic Test" "Logic Test - Big Session" "Lightroom Test" "Puget Test/Assets" "Image Gen Test" "WebKit Test" "Xcode Test/XcodeBenchmark-master" "Blender Test" "HandBrake Test" "Apps & Installers" "AI Tests/LM Studio Models" "AI Tests/Whisper Test"; do
    p="$ROOT/$rel"; [[ -e $p ]] || continue; (( $(kb "$p") < 1048576 )) && continue
    if drv=$(oncopy "$rel"); then ask "test folder: $rel (full copy on $drv, comes back by itself)" "$p"
    else ask "test folder: $rel (NO full copy on a plugged-in drive!)" "$p"; fi
  done
  for m in $HOME/.lmstudio/models/*/*(N/); do
    [[ ${SAFE[(I)$m]} -gt 0 ]] && continue; (( $(kb "$m") < 1048576 )) && continue
    ask "model ${m:t}" "$m"
  done
  [[ -d $HOME/.cache/huggingface ]] && ask "Hugging Face cache (image gen models, redownload)" $HOME/.cache/huggingface
  [[ -d "$HOME/Downloads/Adam Talks Tech Games" ]] && ask "games folder (Cyberpunk, War Thunder; on the drives)" "$HOME/Downloads/Adam Talks Tech Games"
  for g in "$HOME/Library/Application Support/Steam/steamapps/common"/*(N/); do ask "Steam game ${g:t}" "$g"; done
  for f in $HOME/Downloads/*.(dmg|pkg|zip|iso|xip)(N.) /Applications/Install\ macOS*.app(N/); do
    (( $(kb "$f") > 488281 )) && ask "installer ${f:t}" "$f"
  done
  [[ -d "$HOME/Music/Logic Pro Library.bundle" ]] && ask "Logic sound library (Logic redownloads it; the Alchemy experiment needs it)" "$HOME/Music/Logic Pro Library.bundle"
  [[ -d "/Library/Application Support/Logic" ]] && (( $(kb "/Library/Application Support/Logic") > 1048576 )) && print "  (Logic's system sounds: $(fmt $(kb "/Library/Application Support/Logic")) GB, remove in Logic > Sound Library > Manage)"
  # Trash: Finder empties it even when Terminal isn't allowed to read it
  t=$(kb $HOME/.Trash); tn=$(ls -A $HOME/.Trash 2>/dev/null | wc -l | tr -d ' ')
  if (( t > 51200 )) || [[ $tn == 0 && ! -r $HOME/.Trash ]]; then
    if [[ $MODE == report ]]; then printf "  %6s GB  Trash\n" $(fmt $t)
    else
      printf "  Empty the Trash (%s GB)? (y/n) " $(fmt $t); read -r yn
      if [[ $yn == [yY]* ]]; then
        osascript -e 'tell application "Finder" to empty trash' >/dev/null 2>&1 || rm -rf $HOME/.Trash/*(DN) 2>/dev/null
        print "    emptied"; DONE+=("Trash $(fmt $t) GB")
      fi
    fi
  fi
fi

# ---- 3. what happened ----
END=$(gb)
print "\nFree space: ${START} GB -> ${END} GB  (+$(( END - START )) GB)"
print "SPACE | ${START} -> ${END} GB free | cleared: ${#DONE} item(s)$( (( ${#FAILED} )) && print ", ${#FAILED} couldn't (run att-space.zsh by hand to see)")"
if (( ${#FAILED} )); then
  print "\nCOULDN'T CLEAR:"; for f in $FAILED; do print "  - $f"; done
  (( NEEDFDA )) && print "  FIX: System Settings > Privacy & Security > Full Disk Access > turn on Terminal, quit Terminal, run this again."
fi
(( END - START < $(( FREED / 1048576 )) - 3 )) && print "Note: macOS can take a minute to show freed space (APFS frees it in the background). Finder may show more 'available' than this: that's purgeable space macOS only frees when something asks for it."
if (( END < 45 )); then
  print "\nStill under 45 GB: the Internal SSD test (step 20) needs 40 GB, the stacker needs 60. Biggest folders:"
  du -skx $HOME/*(N/) $HOME/Downloads/*(N/) "$ROOT"/*(N/) "$ROOT/AI Tests"/*(N/) $HOME/.lmstudio/models/*/*(N/) $HOME/Library/*(N/) $HOME/Library/Containers/*(N/) $HOME/Library/Application\ Support/*(N/) 2>/dev/null | sort -rn | head -10 | awk '{printf "  %6.1f GB  %s\n", $1/1048576, $2}' | sed "s#$HOME#~#"
fi
if [[ $MODE != report ]]; then
  mkdir -p "$ROOT/Results"
  print -r -- "$(date '+%Y-%m-%d %H:%M') | $(scutil --get ComputerName 2>/dev/null) | $MODE | ${START} -> ${END} GB | ${(j:; :)DONE}$( (( ${#FAILED} )) && print " | FAILED: ${(j:; :)FAILED}")" >> "$ROOT/Results/space-log.txt"
fi
rm -f /tmp/att-space.err

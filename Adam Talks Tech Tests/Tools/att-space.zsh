#!/bin/zsh
# =============================================================================
#  att-space.zsh - free up SSD space on a TEST Mac (v1, Nov 22 2026)
# =============================================================================
#  zsh att-space.zsh          shows what's taking space, then:
#    1. SAFE leftovers (one y/n for all of them): things the tests make and remake on their own
#         - Internal SSD test scratch (~/.att/ssdtest, up to 50 GB if a run was stopped or the Mac restarted)
#         - Xcode build folders (DerivedData) + simulators Xcode can't use anymore
#         - Final Cut "Render Files" inside the test library (Final Cut remakes them)
#         - test exports + "_To Delete" in the test folder, finished Whisper downloads
#         - Time Machine's local snapshots (macOS keeps deleted files in them; can hold 10s of GB)
#         - Homebrew's download cache
#    2. ASKS one by one (y/n): LM Studio models this Mac can't run (too little RAM), other big models,
#       installers (.dmg/.pkg) in Downloads, the Trash.
#  Never touches: Results, the scripts, your own files, Photos, anything on a drive.
#  Models it removes come back by themselves: the tests copy them from a test drive when needed.
# =============================================================================
ROOT=${0:A:h:h}
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
gb() { df -k / | awk 'NR==2{printf "%.0f", $4/1048576}'; }
sz() { du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%.1f", s/1048576}'; }
START=$(gb)
print "ATT space check on $(scutil --get ComputerName) (${RAM}GB RAM): ${START} GB free\n"

# ---- 1. safe leftovers ----
typeset -a SAFE; typeset -A SAFESZ
add() { local p s; for p; do s=$(sz "$p"); [[ $s != 0.0 ]] && { SAFE+=("$p"); SAFESZ[$p]=$s; }; done; }
[[ -d $HOME/.att/ssdtest ]] && add "$HOME/.att/ssdtest"
add $HOME/Library/Developer/Xcode/DerivedData/*(N/) "$ROOT/Xcode Test"/*/DerivedData-run*.noindex(N/)
add "$ROOT/Final Cut Test"/*.fcpbundle/*/"Render Files"(N/)
add "$ROOT/Export"/*(N) "$ROOT/_To Delete"(N/)
grep -q CPUAndNeuralEngine "$ROOT/AI Tests/whisper-test/BUILD-INFO.txt" 2>/dev/null && add $HOME/.att/whisper-dl(N/)
SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c com.apple)
BREWC=$(command -v brew >/dev/null && brew --cache 2>/dev/null)
[[ -n $BREWC ]] && add "$BREWC"
print "SAFE leftovers (the tests remake these if needed):"
for p in $SAFE; do printf "  %6s GB  %s\n" ${SAFESZ[$p]} "${p/#$HOME/~}"; done
(( SNAPS )) && print "  ${SNAPS} Time Machine local snapshot(s) (size unknown until removed)"
command -v xcrun >/dev/null && print "  + Xcode simulators that are no longer usable"
print -n "\nClear all of these? (y/n) "; read -r yn
if [[ $yn == [yY]* ]]; then
  for p in $SAFE; do rm -rf "$p" 2>/dev/null; done
  command -v xcrun >/dev/null && xcrun simctl delete unavailable 2>/dev/null
  [[ -n $BREWC ]] && brew cleanup -s >/dev/null 2>&1
  (( SNAPS )) && { print "  (Time Machine snapshots need your password)"; sudo tmutil thinlocalsnapshots / 999999999999 4 >/dev/null 2>&1; }
  print "  Done: $(gb) GB free now."
fi

# ---- 2. ask one by one ----
print "\nBIG ITEMS (asks for each):"
askrm() {   # $1 label, rest = paths
  local label=$1; shift; local s=$(sz "$@"); [[ $s == 0.0 ]] && return
  printf "  Delete %-58s %6s GB ? (y/n) " "$label" $s; read -r yn
  [[ $yn == [yY]* ]] && { rm -rf "$@"; print "    deleted"; }
}
# LM Studio models: which ones this Mac can't run (the tests skip them by RAM)
for m in $HOME/.lmstudio/models/*/*(N/); do
  n=${m:t}; why=""
  [[ $n =~ '27[Bb]' && $n =~ '(5|6|8)[-_]?bit' ]] && (( RAM < 36 )) && why="27B ladder build, only runs on 36GB+"
  [[ -z $why && $n =~ '27[Bb]' ]] && (( RAM < 24 )) && why="27B, only runs on 24GB+"
  [[ -z $why && $n =~ '(30[Bb]|A3[Bb]|[Mm]o[Ee])' ]] && (( RAM < 24 )) && why="30B-class, only runs on 24GB+"
  k=$(du -sk "$m" | cut -f1); (( k < 1048576 )) && continue
  askrm "model ${n} ${why:+(can't run here: $why)}" "$m"
done
for f in $HOME/Downloads/*.(dmg|pkg|zip)(N.); do
  (( $(stat -f %z "$f") > 500000000 )) && askrm "installer ${f:t}" "$f"
done
[[ -d $HOME/.cache/huggingface ]] && askrm "Hugging Face cache (image gen models, redownload if needed)" $HOME/.cache/huggingface
t=$(sz $HOME/.Trash); [[ $t != 0.0 ]] && { printf "  Empty the Trash (%s GB)? (y/n) " $t; read -r yn; [[ $yn == [yY]* ]] && { rm -rf $HOME/.Trash/*(DN) 2>/dev/null; print "    emptied"; }; }

END=$(gb)
print "\nFree space: ${START} GB -> ${END} GB  (+$(( END - START )) GB)"
(( END < 40 )) && print "Still under 40 GB: the Internal SSD test (step 20) needs 40 GB free. Biggest folders in your home:" && du -sk $HOME/*(N/) $HOME/Library/*(N/) 2>/dev/null | sort -rn | head -8 | awk '{printf "  %6.1f GB  %s\n", $1/1048576, $2}'

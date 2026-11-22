#!/bin/zsh
# =============================================================================
#  att-queue.zsh  -  run every scripted test back to back, unattended (v1, Nov 20 2026)
# =============================================================================
#  Start it, type your password once, walk away (overnight is fine).
#  Each test still does its own cooldown + background-scan pause, exactly like
#  running it by hand, so the numbers are the same as single runs.
#
#    zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-queue.zsh
#
#  Default order: xcode blender redautumn handbrake sustained qwen9b qwen27b gemma
#                 + ladder (32GB+). Draw Things is NOT in the queue: run step 18 by hand.
#  Pick your own:  QUEUE="sustained qwen27b gemma" zsh att-queue.zsh
#  Leave some out: SKIP="xcode blender" zsh att-queue.zsh
#  Also possible:  ladder whisper
#
#  DRIVE: only needed for the first 1-2 minutes. It copies the AI models it will
#  need onto the Mac first, then says "you can unplug the drive". If a drive is
#  still plugged in at the end, the results are copied onto it too.
#  Results: every test's normal files + Results/<Mac>/Queue/queue_<date>.txt with
#  every photo card in one place (send Claude that file or a photo of the summary).
#  Not in the queue (need you there): Geekbench, Cinebench, Puget first runs,
#  Logic, games, stacker (needs restarts), Draw Things, external SSD test.
# =============================================================================
zmodload zsh/datetime
TOOLS=${0:A:h}; ROOT=${TOOLS:h}
source "$TOOLS/att-card.zsh"
[[ $ROOT == /Volumes/* ]] && { print "This is on an external drive. Run it from ~/Downloads/Adam Talks Tech Tests."; exit 1; }

MAC=$(scutil --get ComputerName 2>/dev/null)
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
KIND=$(att_mac_kind 2>/dev/null)
STAMP=$(date +%Y-%m-%d_%H-%M)
QDIR="$ROOT/Results/$MAC/Queue"; mkdir -p "$QDIR"
LOG="$QDIR/queue_${STAMP}.log"; SUMMARY="$QDIR/queue_${STAMP}.txt"
typeset -A QSTEP; QSTEP=(xcode 8 blender 9 redautumn 9b sustained 10 handbrake 11 qwen9b 14a qwen27b 14b gemma 14c ladder 14d whisper E4 bandwidth 14e responsiveness 17b)   # Run Order steps

typeset -A DIR CMD MINS
DIR=(xcode "Xcode Test" blender "Blender Test" redautumn "Blender Test" handbrake "HandBrake Test" sustained "Blender Test"
     qwen9b "AI Tests" qwen27b "AI Tests" gemma "AI Tests" ladder "AI Tests" whisper "AI Tests" bandwidth "Bandwidth Test" responsiveness "Memory Test")
CMD=(xcode "xcode-bench.sh" blender "blender-bench.sh" redautumn "blender-bench.sh redautumn" handbrake "handbrake-bench.zsh"
     sustained "sustained-test.sh" qwen9b "lmstudio-bench.sh qwen9b" qwen27b "lmstudio-bench.sh qwen27b" gemma "lmstudio-bench.sh gemma"
     ladder "lmstudio-bench.sh ladder" whisper "lmstudio-bench.sh whisper" bandwidth "att-bandwidth.zsh" responsiveness "att-responsiveness.zsh")
MINS=(xcode 10 blender 15 redautumn 12 handbrake 15 sustained 35 qwen9b 20 qwen27b 20 gemma 6 ladder 20 whisper 8 bandwidth 4 responsiveness 50)

if [[ -n $QUEUE ]]; then LIST=(${=QUEUE})
else
  LIST=(xcode blender redautumn handbrake sustained qwen9b qwen27b gemma)
  (( RAM >= 32 )) && LIST+=(ladder)
fi
for s in ${=SKIP}; do LIST=(${LIST:#$s}); done

# Drop anything this Mac can't run, and say why
RUN=(); NOTES=()
for t in $LIST; do
  [[ -n ${CMD[$t]} ]] || { NOTES+=("$t: unknown test name, skipped"); continue; }
  local_dir="$ROOT/${DIR[$t]}"
  [[ -f "$local_dir/${CMD[$t]%% *}" ]] || { NOTES+=("$t: ${DIR[$t]} folder isn't on this Mac (Tools/att-get.zsh), skipped"); continue; }
  RUN+=($t)
done
(( ${#RUN} )) || { print "Nothing to run."; print -l $NOTES; exit 1; }
total=0; for t in $RUN; do (( total += MINS[$t] )); done

print "================ ATT Test Queue ================"
print "Mac:    $MAC | $KIND"
print "Order:  ${(j:, :)RUN}"
print "Time:   about $(( total / 60 ))h $(( total % 60 ))m (rough)"
(( ${#NOTES} )) && print -l "Skipped:" ${NOTES/#/  }
print "================================================"
[[ $KIND == *laptop* ]] && [[ $(pmset -g batt | head -1) != *"AC Power"* ]] && print "!! On battery. Plug in Apple's charger (straight into the Mac) before walking away."

print "\nPassword once (watts, cooldowns, cold model loads). Nothing else to type after this."
sudo -v || { print "Need the password to run unattended."; exit 1; }
# Nov 21: every test Mac on Central time, so card times, upload times and "already done" checks line up
tz=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
[[ $tz != America/Chicago ]] && sudo -n systemsetup -settimezone America/Chicago >/dev/null 2>&1 && print "Set this Mac's time zone to Central (was ${tz:-unknown})."
{ trap - INT TERM; while true; do sudo -n true 2>/dev/null; sleep 50; done } &
KEEP=$!
caffeinate -dims -w $$ &
trap 'kill $KEEP 2>/dev/null; att_resume_bg; att_sync_results; att_upload_results' EXIT
trap 'print "\nQueue stopped."; exit 130' INT TERM

# Models first, so the drive can be unplugged
want=()
for t in $RUN; do case $t in
  qwen9b) want+=(Qwen3.5-9B-MLX-4bit) ;;
  qwen27b) want+=(Qwen3.8-27B-MLX-4bit) ;;
  gemma) want+=(gemma-3-4b-it-GGUF) ;;
  ladder) want+=(Qwen3.8-27B-MLX-4bit Qwen3.8-27B-MLX-5bit Qwen3.8-27B-MLX-6bit Qwen3.8-27B-MLX-8bit) ;;
esac; done
if (( ${#want} )); then
  print "\nChecking the AI models are on this Mac..."
  zsh "$ROOT/AI Tests/att-models.zsh" get ${(u)want}
  (( ${RUN[(I)gemma]} )) && zsh "$ROOT/AI Tests/att-models.zsh" park gemma-3-4b-it-GGUF '*gemma-3-4b*'
fi
# Copying models restarts LM Studio; close it again so it can't sit there during
# the Blender/HandBrake tests (the AI tests open it themselves when they need it).
if pgrep -xq "LM Studio"; then
  osascript -e 'quit app "LM Studio"' >/dev/null 2>&1; sleep 5
  pgrep -xq "LM Studio" && pkill -x "LM Studio" 2>/dev/null
fi
afplay /System/Library/Sounds/Glass.aiff 2>/dev/null
print "\n>>> All set. You can unplug the drive and walk away. Don't use this Mac until it's done. <<<\n"

typeset -A RC TOOK
for t in $RUN; do
  print "\n\n======== [$(date +%H:%M)] QUEUE: $t (Run Order step ${QSTEP[$t]:-?}) ($(( ${RUN[(i)$t]} )) of ${#RUN}) ========" | tee -a "$LOG"
  t0=$EPOCHSECONDS
  ( cd "$ROOT/${DIR[$t]}" && ATT_NOSYNC=1 zsh ${(z)CMD[$t]} ) 2>&1 | tee -a "$LOG"
  RC[$t]=${pipestatus[1]}; TOOK[$t]=$(( (EPOCHSECONDS - t0) / 60 ))
done

# One file with every photo card + a short summary
{
  print "ATT Test Queue | $MAC | $KIND | started $STAMP"
  print "Order: ${(j:, :)RUN}"
  (( ${#NOTES} )) && print -l "Skipped:" ${NOTES/#/  }
  print ""
  for t in $RUN; do print "  ${QSTEP[$t]:-?} $t: $( (( RC[$t] == 0 )) && print done || print "ended with error ${RC[$t]}") (${TOOK[$t]} min)"; done
  print "\n==================== EVERY CARD ===================="
  awk 'index($0,"PHOTO THIS FOR CLAUDE"){p=1} p{print} p && $0 ~ /^#+$/ {p=0; print ""}' "$LOG"
} > "$SUMMARY"

att_card_start "Test queue (${#RUN} tests)"
for t in $RUN; do print "  ${QSTEP[$t]:-?} $t: $( (( RC[$t] == 0 )) && print done || print "ERROR ${RC[$t]}") (${TOOK[$t]} min)"; done
(( ${#NOTES} )) && print -l "Skipped:" ${NOTES/#/  }
print "Every card from the run: Results/$MAC/Queue/${SUMMARY:t}"
print "Plug in a test drive and the results copy over by themselves."
att_card_end
afplay /System/Library/Sounds/Glass.aiff 2>/dev/null
zsh "${0:A:h}/att-next.zsh" >/dev/null 2>&1   # show the updated list (finished tests now ✓)

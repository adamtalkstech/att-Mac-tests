#!/bin/zsh
# =============================================================================
#  E1  Dual Neural Engine (EXPERIMENT, Nov 22 2026) - not logged to the main sheet
# =============================================================================
#  Question: does the M6's dual 16-core Neural Engine show up vs one 16-core engine (M5 / Pro / Max)
#  and the 32-core M5 Ultra? The normal Whisper test times the whole transcription, where the CPU
#  decoder hides the Neural Engine. This one reports:
#    A. Neural Engine encoder time alone (whisper.cpp's own "encode time"), median of 3
#    B. the same 10-min file transcribed TWICE AT ONCE (two processes), wall time, vs one alone
#  A dual engine should show up most in B (two jobs to spread across two engines).
#  Uses the locked Whisper kit (AI Tests/whisper-test). ~10 min.
#    cd ~/Downloads/"Adam Talks Tech Tests"/Experiments && zsh e1-dual-neural-engine.zsh
# =============================================================================
export ATT_EXPERIMENT=1
source "${0:A:h:h}/Tools/att-card.zsh"
zmodload zsh/datetime
ROOT=${0:A:h:h}; KIT="$ROOT/AI Tests/whisper-test"; MAC=$(scutil --get ComputerName)
OUT="$ROOT/Results/$MAC/Experiments"; mkdir -p "$OUT"; STAMP=$(date +%Y-%m-%d_%H-%M)
grep -q CPUAndNeuralEngine "$KIT/BUILD-INFO.txt" 2>/dev/null || { print "!! Needs the locked Whisper kit. Run Update Scripts first (it gets the kit)."; exit 1; }
BIN="$KIT/bin/whisper-cli-coreml"; MODEL="$KIT/models/ggml-large-v3-turbo.bin"
AUDIO=$(print -l "$ROOT/AI Tests"/"Whisper test audio".{wav,mp3}(N) | head -1)
[[ -f $AUDIO ]] || { print "!! Whisper test audio isn't in AI Tests."; exit 1; }
T=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || print 4)
att_cooldown
"$BIN" -m "$MODEL" -f "$KIT/samples/jfk.wav" -nt >/dev/null 2>&1   # warm-up (Neural Engine compile)
enc=()
for r in 1 2 3; do
  "$BIN" -m "$MODEL" -f "$AUDIO" -t $T -nt > /dev/null 2> "$OUT/.e1_single_$r.log"
  e=$(awk '/encode time/ {for(i=1;i<=NF;i++) if($i=="ms") {print $(i-1); exit}}' "$OUT/.e1_single_$r.log")
  enc+=(${e:-0}); print "  run $r: Neural Engine encode ${e:-?} ms"; sleep 20
done
med() { print -l "$@" | sort -n | sed -n "$(( ($# + 1) / 2 ))p"; }
ENC=$(med $enc)
att_cooldown --again
t0=$EPOCHREALTIME; "$BIN" -m "$MODEL" -f "$AUDIO" -t $T -nt >/dev/null 2>"$OUT/.e1_one.log"; ONE=$(( EPOCHREALTIME - t0 ))
att_cooldown --again
t0=$EPOCHREALTIME
"$BIN" -m "$MODEL" -f "$AUDIO" -t $(( T / 2 > 1 ? T / 2 : 1 )) -nt >/dev/null 2>"$OUT/.e1_two_a.log" &
"$BIN" -m "$MODEL" -f "$AUDIO" -t $(( T / 2 > 1 ? T / 2 : 1 )) -nt >/dev/null 2>"$OUT/.e1_two_b.log" &
wait; TWO=$(( EPOCHREALTIME - t0 ))
EA=$(awk '/encode time/ {for(i=1;i<=NF;i++) if($i=="ms") {print $(i-1); exit}}' "$OUT/.e1_two_a.log")
EB=$(awk '/encode time/ {for(i=1;i<=NF;i++) if($i=="ms") {print $(i-1); exit}}' "$OUT/.e1_two_b.log")
{ att_card_start "EXPERIMENT E1: dual Neural Engine (not logged to the main sheet)"
  print "Neural Engine encode time, one file (median of 3): ${ENC} ms"
  printf "One file alone (wall):        %.1f s\n" $ONE
  printf "Two files at once (wall):     %.1f s   -> %.2fx the time of one (2.00 = no help from running two)\n" $TWO $(( TWO / ONE ))
  print "Encode time with two at once: ${EA:-?} ms / ${EB:-?} ms"
  print "Send this card to Claude: it goes on the Experiments tab."
  att_card_end; } | tee "$OUT/e1-dual-neural-engine_$STAMP.txt"

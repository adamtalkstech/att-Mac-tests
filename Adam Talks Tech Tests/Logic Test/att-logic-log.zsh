#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  att-logic-log.zsh  -  log a Logic track count result (v1.1, Nov 22 2026)
# =============================================================================
#  Logic can't be timed or counted from Terminal, so the test is run by hand
#  (see LOGIC TEST - READ ME.txt). This asks for the numbers and saves them
#  with the Mac, chip, macOS and Logic version so every row is complete.
#
#  Run:  zsh att-logic-log.zsh
#  Saves: Results/<Mac name>/Logic/logic_<date>.txt + Results/All Macs logic.csv
# =============================================================================

ROOT=${0:A:h}
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=${0:A:h}
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

OUT="$ROOT/Results/$MACNAME/Logic"; mkdir -p "$OUT"
CSV="$ROOT/Results/All Macs logic.csv"
CHIP=$(sysctl -n machdep.cpu.brand_string)
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
OSV="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
LOGIC_APP=$(find /Applications -maxdepth 1 -iname "Logic Pro*.app" -type d 2>/dev/null | head -1)
LV=$(defaults read "$LOGIC_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)
# Nov 22: record every setting a viewer needs to repeat the test (Sebastian's email asked for all of them)
SR=$(system_profiler SPAudioDataType 2>/dev/null | awk '/^        [^ ].*:$/{dev=$0} /Current SampleRate/{sr[dev]=$NF} /Default Output Device: Yes/{d=dev} END{print sr[d]}')

ask() { local v; print -n -- "$1 " >&2; read -r v; print -r -- "$v"; }

print "ATT Logic result logger  -  $MACNAME | $CHIP | ${RAM}GB | macOS $OSV | Logic ${LV:-?}"
print "Leave a line blank if you didn't run that test.\n"
PROJ=$(ask "Project (Enter = NewLogicBenchmarkTest 2):"); PROJ=${PROJ:-NewLogicBenchmarkTest 2}
T256=$(ask "Tracks at 256 buffer (no overload for 30s):")
T32=$(ask "Tracks at 32 buffer (low-latency pass):")
T64=$(ask "Tracks at 64 buffer (optional, Enter = skip):")
T128=$(ask "Tracks at 128 buffer (optional, Enter = skip):")
THREADS=$(ask "Processing Threads setting used (number):")
PBR=$(ask "Process Buffer Range (Enter = Medium):"); PBR=${PBR:-Medium}
MT=$(ask "Multithreading (Enter = Playback & Live Tracks):"); MT=${MT:-Playback & Live Tracks}
OUTDEV=$(ask "Output device (Enter = built-in):"); OUTDEV=${OUTDEV:-built-in}
COOL=$(ask "Cool start? (y/n):")
NOTES=$(ask "Notes (CPU meter pinned? overload pattern?):")

FILE="$OUT/logic_$(date +%Y-%m-%d_%H-%M).txt"
att_card_start "Logic track count"
{
print "ATT Logic Track Count  -  $(date)"
print "Mac: $MACNAME | $CHIP | ${RAM}GB | macOS $OSV | Logic ${LV:-?}"
print "Project: $PROJ | Output: $OUTDEV ${SR:+@ ${SR} Hz} | Cool start: $COOL"
print "Settings: Threads $THREADS | Process Buffer Range $PBR | Multithreading $MT | Track Mute/Solo CPU-saving"
print "Tracks @256 buffer: ${T256:-not run}"
print "Tracks @32 buffer:  ${T32:-not run}"
[[ -n $T64 ]]  && print "Tracks @64 buffer:  $T64"
[[ -n $T128 ]] && print "Tracks @128 buffer: $T128"
[[ -n $T256 ]] && att_log "Main Results" "Logic Tracks" "$T256 channels"
[[ -n $T32 ]]  && att_log "New Tests" "Logic tracks @32" "$T32"
[[ -n $NOTES ]] && print "Notes: $NOTES"
} | tee "$FILE"
att_card_end

[[ -f $CSV ]] || print "Date,Mac,Chip,RAM GB,macOS,Logic,Project,Tracks @256,Tracks @32,Threads,Output,Cool start,Notes,Tracks @64,Tracks @128,Sample rate,Process Buffer Range,Multithreading" > "$CSV"
print "$(date +%F),\"$MACNAME\",\"$CHIP\",$RAM,\"$OSV\",${LV},\"$PROJ\",$T256,$T32,$THREADS,\"$OUTDEV\",$COOL,\"${NOTES//\"/\'}\",$T64,$T128,$SR,\"$PBR\",\"$MT\"" >> "$CSV"
print "\nSaved: $FILE\nSend Claude the lines above."

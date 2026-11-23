#!/bin/zsh
# =============================================================================
#  E5  Xcode build with 2 Simulators running (EXPERIMENT, Nov 22 2026) - not logged to the main sheet
# =============================================================================
#  Developer ask: the normal Xcode test is a clean build on an idle Mac. Real work has Simulators
#  open. This boots two iPhone Simulators, lets them settle, runs the same Xcode benchmark
#  (3 builds), then shuts them down. Compare with that Mac's normal Xcode result.
#  Needs an iOS Simulator runtime installed (Xcode > Settings > Components).
#    cd ~/Downloads/"Adam Talks Tech Tests"/Experiments && zsh e5-xcode-simulators.zsh
# =============================================================================
export ATT_EXPERIMENT=1
ROOT=${0:A:h:h}; MAC=$(scutil --get ComputerName); OUT="$ROOT/Results/$MAC/Experiments"; mkdir -p "$OUT"; STAMP=$(date +%Y-%m-%d_%H-%M)
RT=$(xcrun simctl list runtimes 2>/dev/null | awk '/iOS/ && !/unavailable/ {print $NF}' | tail -1)
[[ -n $RT ]] || { print "!! No iOS Simulator runtime. Xcode > Settings > Components > iOS, then rerun."; exit 1; }
DT=$(xcrun simctl list devicetypes | awk -F'[()]' '/iPhone/ {print $2}' | tail -1)
ids=()
for n in 1 2; do ids+=($(xcrun simctl create "ATT Sim $n" "$DT" "$RT")); done
for i in $ids; do xcrun simctl boot $i; done
open -a Simulator; print "Two Simulators booting; settling 90 s..."; sleep 90
ATT_KEEP="Simulator" zsh "$ROOT/Xcode Test/xcode-bench.sh" 2>&1 | tee "$OUT/e5-xcode-simulators_$STAMP.txt"
for i in $ids; do xcrun simctl shutdown $i 2>/dev/null; xcrun simctl delete $i 2>/dev/null; done
osascript -e 'quit app "Simulator"' >/dev/null 2>&1
print "\nEXPERIMENT E5: the card above is the Xcode build WITH two Simulators running ($DT, $RT). Not logged to the main sheet; send it to Claude."

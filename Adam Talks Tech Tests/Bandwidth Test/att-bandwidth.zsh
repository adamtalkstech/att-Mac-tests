#!/bin/zsh
# ATT Memory Bandwidth test (Run Order step 14e, v1 Nov 21 2026). Walk-away, ~3 min.
# Measures real memory bandwidth two ways:
#   CPU: STREAM-style copy + triad on all cores (C, compiled here with clang)
#   GPU: Metal copy kernel on a big buffer (Swift, compiled here with swiftc)
# The GPU number is the one to compare with Apple's quoted GB/s (e.g. binned vs full M5 Max).
# Needs Xcode Command Line Tools (xcode-select --install). Median-free: best of 10 (CPU) / 20 (GPU) passes.
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null
HERE=${0:A:h}; ROOT=${HERE:h}
MAC=$(scutil --get ComputerName 2>/dev/null); OUT="$ROOT/Results/$MAC/Bandwidth"; mkdir -p "$OUT"
BIN=$HOME/.att/bw; mkdir -p $BIN
whence clang >/dev/null || { print "Needs Xcode Command Line Tools: run  xcode-select --install  then rerun."; exit 1; }
[[ $BIN/cpu -nt $HERE/att_bw_cpu.c ]] || clang -O3 -march=native -o $BIN/cpu $HERE/att_bw_cpu.c -lpthread 2>/dev/null || clang -O3 -o $BIN/cpu $HERE/att_bw_cpu.c -lpthread || exit 1
[[ $BIN/gpu -nt $HERE/att_bw_gpu.swift ]] || swiftc -O -o $BIN/gpu $HERE/att_bw_gpu.swift 2>/dev/null || print "(GPU test couldn't compile: CPU only)"
whence att_cooldown >/dev/null && att_cooldown
RAM=$(( $(sysctl -n hw.memsize) / 1073741824 )); MB=1024; (( RAM <= 16 )) && MB=512
CPU=$($BIN/cpu $MB); GPU=$([[ -x $BIN/gpu ]] && $BIN/gpu $(( MB * 2 )))
F="$OUT/bandwidth_$(date +%Y-%m-%d_%H-%M-%S).txt"
{ whence att_card_start >/dev/null && att_card_start "Memory bandwidth (CPU STREAM + GPU Metal)"
  print -r -- "$CPU"; print -r -- "$GPU"
  print "SHEET: CPU triad / GPU copy GB/s  ->  $(print -r -- "$CPU" | awk '/triad/ {print $NF}') / $(print -r -- "$GPU" | awk '/GPU copy/ {print $NF}')"
  att_log "New Tests" "CPU memory bandwidth, STREAM triad" "$(print -r -- "$CPU" | awk '/triad/ {print $NF}')"
  att_log "New Tests" "GPU memory bandwidth, Metal copy" "$(print -r -- "$GPU" | awk '/GPU copy/ {print $NF}')"
  whence att_card_end >/dev/null && att_card_end; } | tee "$F"

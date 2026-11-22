#!/bin/zsh
# =============================================================================
#  att-ssd-internal.zsh - the Mac's own SSD, no clicking (Run Order step 20, v1 Nov 22 2026)
# =============================================================================
#  Walk-away, ~15-20 min. No Homebrew or fio: builds a small tester (att_ssd.c) with the Xcode tools,
#  like the memory bandwidth test. The Mac's file cache is OFF for every read and write, so the numbers
#  are the SSD, not RAM.
#   1. Sequential write + read: 5GB file, 1MB blocks, 8 at a time, best of 3
#   2. Random 4K read + write at QD1 (how snappy it feels) and QD32 (lots of small files), 30 s each
#   3. Sustained write: up to 50GB in one go, speed every second (where it slows down, and by how much)
#   4. One 25GB file copied to another folder on the same drive (a real copy, not an APFS clone)
#  Leaves at least 25GB free: on a nearly full Mac the sustained write and the copy get smaller,
#  and the card says so (a smaller copy is held from the sheet, since it wouldn't compare).
#  Everything goes in ~/.att/ssdtest and is deleted at the end, even if you press Control-C.
#  Also runs in the walk-away queue as "ssdint".
# =============================================================================
HERE=${0:A:h}; ROOT=${HERE:h}
source "$ROOT/Tools/att-card.zsh"
MAC=$(scutil --get ComputerName 2>/dev/null); OUT="$ROOT/Results/$MAC/SSD"; mkdir -p "$OUT"
BIN=$HOME/.att/att_ssd; W=$HOME/.att/ssdtest
whence clang >/dev/null || { print "Needs Xcode Command Line Tools: run  xcode-select --install  then rerun."; exit 1; }
[[ $BIN -nt $HERE/att_ssd.c ]] || clang -O2 -o $BIN $HERE/att_ssd.c -lpthread || exit 1
cleanup() { rm -rf "$W"; }
trap 'cleanup; att_resume_bg; exit 130' INT TERM
cleanup; mkdir -p "$W"
freegb() { df -k "$HOME" | awk 'NR==2{printf "%d", $4/1048576}'; }
FREE0=$(freegb); DISK=$(diskutil info / 2>/dev/null | awk -F': *' '/Container Total Space|Disk Size/ {print $2; exit}' | cut -d'(' -f1)
(( FREE0 < 40 )) && { print "!! Only ${FREE0} GB free. Needs at least 40 GB for this test. Free some space (Tools/att-get.zsh free) and rerun."; exit 1; }
SUS=$(( FREE0 - 25 )); (( SUS > 50 )) && SUS=50
CP=$(( (FREE0 - 25) / 2 )); (( CP > 25 )) && CP=25
att_cooldown
print "1/4 Sequential (5GB, best of 3)..."; read _ SW SR <<< "$($BIN seq "$W/seq.bin" 5120 8 3)"
sleep 20; print "2/4 Random 4K (QD1, then QD32)..."
read _ _ R1 W1 <<< "$($BIN rand "$W/seq.bin" 30 1)"; sleep 10
read _ _ R32 W32 <<< "$($BIN rand "$W/seq.bin" 30 32)"; rm -f "$W/seq.bin"
sleep 60; print "3/4 Sustained write (${SUS} GB, speed every second)..."
CSV="$OUT/ssd-sustained_$(date +%Y-%m-%d_%H-%M).csv"; print "second,MB_per_s,GB_written" > "$CSV"
$BIN sus "$W/sus.bin" $SUS | awk '/^S /{print $2","$3","$4; fflush()}' >> "$CSV"; rm -f "$W/sus.bin"
# Slowdown: first second where the 10-second average drops under 60% of the first 10 seconds' average
read SAVG FIRST CLIFF_GB AFTER LAST60 <<< "$(awk -F, 'NR>1 { n++; v[n]=$2; g[n]=$3; s+=$2 }
  END { if (!n) { print "? ? - - ?"; exit } f=0; for (i=1;i<=10&&i<=n;i++) f+=v[i]; f/= (n<10?n:10)
    cg="-"; ci=0; for (i=10;i<=n;i++) { a=0; for (j=i-9;j<=i;j++) a+=v[j]; a/=10; if (a < 0.6*f) { cg=g[i]; ci=i; break } }
    af="-"; if (ci) { t=0; k=0; for (i=ci;i<=n;i++) { t+=v[i]; k++ } af=sprintf("%.0f", t/k) }
    l=0; k=0; for (i=(n>60?n-59:1);i<=n;i++) { l+=v[i]; k++ }
    printf "%.0f %.0f %s %s %.0f\n", s/n, f, cg, af, l/k }' "$CSV")"
sleep 60; print "4/4 Copy one ${CP} GB file on the same drive (real copy, not a clone)..."
$BIN make "$W/copy-src.bin" $(( CP * 1024 )); mkdir -p "$W/dest"; sleep 20
# Nov 22 fix: Finder-style copies (cp, ditto) are APFS clones on the same drive and finish in 0 s, so the copy is
# done by the tester itself: every byte read from the SSD and written back, cache off.
read _ CPT <<< "$($BIN copy "$W/copy-src.bin" "$W/dest/copy-src.bin")"
cleanup; att_resume_bg
F="$OUT/ssd-internal_$(date +%Y-%m-%d_%H-%M).txt"
{ att_card_start "Internal SSD, no clicking (Step 20)"
  print "Drive: ${DISK:-?} total, ${FREE0} GB free at the start (cache off for every test)"
  print "Sequential (5GB, 1MB x8, best of 3):  write ${SW:-?} MB/s | read ${SR:-?} MB/s"
  print "Random 4K QD1:   read ${R1:-?} MB/s | write ${W1:-?} MB/s   (how snappy it feels)"
  print "Random 4K QD32:  read ${R32:-?} MB/s | write ${W32:-?} MB/s  (lots of small files at once)"
  print "Sustained write ${SUS} GB: avg ${SAVG} MB/s, first 10 s ${FIRST} MB/s"
  [[ $CLIFF_GB == - ]] && print "   no slowdown during the ${SUS} GB" || print "   slows to ${AFTER} MB/s after ${CLIFF_GB} GB"
  print "   last minute: ${LAST60} MB/s   (per-second log: ${CSV:t})"
  print "Copy one ${CP} GB file on the same drive: ${CPT} s ($(awk -v g=$CP -v t=$CPT 'BEGIN{printf "%.0f", g*1024/t}') MB/s)"
  (( SUS < 50 )) && print "Note: only ${SUS} GB sustained write (not enough free space for 50)."
  att_log "New Tests" "Internal SSD: sequential write / read" "${SW} / ${SR}"
  att_log "New Tests" "Internal SSD: random 4K" "${R1} / ${W1} | ${R32} / ${W32}"
  att_log "New Tests" "Internal SSD: sustained write" "${SAVG} | $([[ $CLIFF_GB == - ]] && print "no slowdown" || print "slows to ${AFTER} after ${CLIFF_GB} GB") | last min ${LAST60} ($SUS GB)"
  if (( CP == 25 )); then att_log "New Tests" "25GB file copy time" "${CPT} s"
  else print "Note: the copy was only ${CP} GB (not enough free space for 25), so only the copy is left off the sheet."; fi
  att_card_end; } | tee "$F"
whence att_upload_results >/dev/null && att_upload_results

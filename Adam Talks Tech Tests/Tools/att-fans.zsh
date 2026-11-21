#!/bin/zsh
# Quick fan check: builds the fan reader if needed and shows this Mac's fans for 15 seconds.
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-fans.zsh
source "${0:A:h}/att-card.zsh"
bin=$(att_fans_bin) || {
  print "No fan reader on this Mac yet, and no Xcode to build one."
  print "Fix: run this once on any Mac that has Xcode, with a test drive plugged in."
  print "That leaves a ready-made copy (Tools/att-fans-bin) on the drive. Tell Claude,"
  print "and it goes into Update Scripts for every Mac."
  exit 1
}
n=$("$bin" | awk '{print $1}')
if (( n == 0 )); then print "This Mac has no fans (or the fan controller didn't answer)."; exit 0; fi
print "$n fan(s). Min-max RPM for each: $("$bin" -m | cut -d' ' -f2-)"
print "Live RPM, 3 readings 5 seconds apart:"
for i in 1 2 3; do print "  $("$bin" | cut -d' ' -f2-)"; (( i < 3 )) && sleep 5; done
print "\nFans are working. The sustained test will log them now."
[[ -f "${0:A:h}/att-fans-bin" ]] && print "Ready-made copy saved: Tools/att-fans-bin (also on any plugged-in test drive)."

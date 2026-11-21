#!/bin/zsh
# Quick fan check: builds the fan reader if needed and shows this Mac's fans for 15 seconds.
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-fans.zsh
source "${0:A:h}/att-card.zsh"
bin=$(att_fans_bin) || {
  print "Couldn't build the fan reader. Install the Command Line Tools (xcode-select --install), then run this again."
  exit 1
}
n=$("$bin" | awk '{print $1}')
if (( n == 0 )); then print "This Mac has no fans (or the fan controller didn't answer)."; exit 0; fi
print "$n fan(s). Min-max RPM for each: $("$bin" -m | cut -d' ' -f2-)"
print "Live RPM, 3 readings 5 seconds apart:"
for i in 1 2 3; do print "  $("$bin" | cut -d' ' -f2-)"; (( i < 3 )) && sleep 5; done
print "\nFans are working. The sustained test will log them now."

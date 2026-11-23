#!/bin/zsh
# =============================================================================
#  E6  Lightroom Classic, Puget Bench Extended preset (EXPERIMENT, Nov 22 2026)
# =============================================================================
#  Comment ask: real edits and AI masking, not just import/export. Puget Bench for Lightroom Classic
#  has an Extended preset with those tests. Not uploaded (the Puget upload path would treat it like the
#  Standard score): send Claude a photo of the result + the CSV in Results/<Mac>/Puget.
#  One Mac at a time (Adobe seats). Needs the Puget Bench app + Lightroom Classic.
#    cd ~/Downloads/"Adam Talks Tech Tests"/Experiments && zsh e6-lightroom-extended.zsh
# =============================================================================
export ATT_EXPERIMENT=1 NOUPLOAD=1
PRESET=Extended zsh "${0:A:h:h}/Puget Test/att-puget.zsh" run "Lightroom Classic"
print "\nEXPERIMENT E6 done: Puget Bench for Lightroom Classic (Extended). Not logged; send Claude the result."

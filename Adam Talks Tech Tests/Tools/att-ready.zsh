#!/bin/zsh
# =============================================================================
#  att-ready.zsh  -  get the Mac ready for a test you run by hand (v1, Nov 20 2026)
# =============================================================================
#  For the app tests that aren't scripts: Geekbench, Cinebench, Logic, Cyberpunk,
#  3DMark, Procyon, Final Cut / Lightroom exports, Minecraft.
#  Quits every other app, pauses Photos/Spotlight/Siri scanning, waits until the Mac
#  is cool and idle, then tells you to go. Keeps the scanning paused until you press
#  Return after the test (restart also wakes them).
#
#  Run:  zsh att-ready.zsh "Cinebench 2026"     (keeps that app open if it's running)
#        COOL=300 zsh att-ready.zsh "Cyberpunk 2077"   (adds a 5-minute rest first)
# =============================================================================
source "${0:A:h}/att-card.zsh"
APP="${1:-}"
ATT_KEEP="${APP}${ATT_KEEP:+,$ATT_KEEP}" att_cooldown
afplay /System/Library/Sounds/Glass.aiff 2>/dev/null
print ""
print ">>> READY. Start ${APP:-the test} now, and don't touch anything else until it's done. <<<"
print "    (${ATT_COOL_NOTE})"
print ""
print "Photos/Spotlight/Siri scanning stays paused while this window is open."
print -n "When the test is DONE, press Return here to wake them back up. "
read -r
att_resume_bg; print "Woke them back up."

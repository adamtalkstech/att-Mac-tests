#!/bin/zsh
# =============================================================================
#  att-ready.zsh  -  get the Mac ready for a test you run by hand (v1, Nov 20 2026)
# =============================================================================
#  For the app tests that aren't scripts: Geekbench, Cinebench, Logic, Cyberpunk,
#  3DMark, Procyon, Final Cut / Lightroom exports, Minecraft.
#  Quits every other app, waits until the Mac is cool and idle, then tells you to go.
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

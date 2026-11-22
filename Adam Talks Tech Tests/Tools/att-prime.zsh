# ATT primer (sourced, not run on its own)  -  v1.0 (Nov 22 2026)
# Gets every "first time" prompt out of the way BEFORE a walk-away test starts, while you're
# still at the Mac (Adam, Nov 22: tests were stopping mid-run for a first app launch or a
# "Terminal wants to control ..." box):
#   1. Accessibility for Terminal (clicks in Final Cut / Numbers)
#   2. Automation: one harmless Apple event to each app, so its "Terminal wants to control X"
#      box shows up now
#   3. First launch: apps never opened on this Mac get opened once so you can click through
#      their welcome screens (Logic's sound library, Chrome's sign-in, Numbers' welcome...)
#   4. Safari: "Allow JavaScript from Apple Events" (responsiveness needs it)
# Remembered per Mac in ~/.att/primed.txt, so after the first time it takes a few seconds.

ATT_PRIMED=$HOME/.att/primed.txt

att_app_path() {   # app name -> .app path (empty if not installed)
  local n=$1 p
  for p in "/Applications/$n.app" "/System/Applications/$n.app" "/System/Applications/Utilities/$n.app" \
           "/System/Cryptexes/App/System/Applications/$n.app" /Applications/*/"$n.app"(N) "$HOME/Applications/$n.app"; do
    [[ -d $p ]] && { print -r -- "$p"; return; }
  done
  [[ $n == "Final Cut Pro" ]] && { p=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.FinalCut*'" 2>/dev/null | grep '\.app$' | grep -v '^/Volumes' | head -1); [[ -n $p ]] && print -r -- "$p"; }
  [[ $n == "Logic Pro" ]] && { p=$(print -l /Applications/Logic*.app(N) | head -1); [[ -n $p ]] && print -r -- "$p"; }
}

# Apps each test needs (names as Finder shows them)
att_prime_apps_for() {
  local t; for t; do case $t in
    appmem)          print -l "Safari" "Google Chrome" "Numbers" "Final Cut Pro" "Logic Pro" "LM Studio" ;;
    responsiveness)  print -l "Safari" "Calculator" "Chess" "Dictionary" "Font Book" "Activity Monitor" "TV" "GarageBand" ;;
    stacker|closer)  print -l "Safari" "Numbers" "Final Cut Pro" "LM Studio" ;;
    fcp-neural)      print -l "Final Cut Pro" ;;
    drawthings)      print -l "Draw Things" ;;
    realday)         print -l "Safari" "Google Chrome" "Notes" "Calendar" "Numbers" "Photo Booth" ;;
    realday-creator) print -l "Final Cut Pro" "Logic Pro" "Pixelmator Pro" "LM Studio" ;;
    realdaycreator)  att_prime_apps_for realday realday-creator ;;
  esac; done
}

att_prime() {   # att_prime <test names...>   e.g. att_prime appmem responsiveness
  [[ ${NOPRIME:-0} == 1 ]] && return 0
  local -a apps paths new; local a p
  apps=("${(@u)${(f)$(att_prime_apps_for "$@")}}")
  for a in $apps; do p=$(att_app_path "$a"); [[ -n $p ]] && { paths+=("$p"); grep -qxF "$p" "$ATT_PRIMED" 2>/dev/null || new+=("$p"); }; done
  (( ${#paths} )) || return 0
  mkdir -p ${ATT_PRIMED:h}; touch "$ATT_PRIMED"
  print "\n---- Before you walk away: first-time prompts (Step 0 check) ----"

  # 1. Accessibility
  if whence att_ui_setup >/dev/null || source "${ATT_TOOLS_DIR:-${0:A:h}}/att-ui.zsh" 2>/dev/null; then att_ui_setup >/dev/null; fi
  osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null | grep -q true \
    || print "  !! Terminal still isn't allowed in Accessibility: Final Cut/Numbers steps will need you."

  # 2. First launch for apps this Mac has never opened for a test
  if (( ${#new} )); then
    print "  Opening apps this Mac hasn't had for a test yet: ${(j:, :)${new:t:r}}"
    print "  Click through ANY welcome / sign-in / 'download sounds' / 'what's new' windows,"
    print "  and click Allow / OK on every 'Terminal wants to control...' box."
    for p in $new; do open -a "$p" 2>/dev/null; sleep 3; done
  fi
  # 3. Automation: one Apple event per app (shows the "wants to control" box now, not mid-test)
  for p in $paths; do osascript -e "tell application \"${${p:t}%.app}\" to get name" >/dev/null 2>&1; done
  osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1
  # 4. Safari JavaScript from Apple Events (only if a test here uses Safari tabs)
  if (( ${paths[(I)*Safari.app]} )); then
    osascript -e 'tell application "Safari" to make new document with properties {URL:"about:blank"}' >/dev/null 2>&1; sleep 2
    if ! osascript -e 'tell application "Safari" to do JavaScript "1+1" in document 1' >/dev/null 2>&1; then
      print "  Safari: turn on Settings > Advanced > 'Show features for web developers', then"
      print "          Settings > Developer > 'Allow JavaScript from Apple Events'."
      whence att_say >/dev/null && att_say "Safari needs Allow JavaScript from Apple Events turned on."
      local w=0; until osascript -e 'tell application "Safari" to do JavaScript "1+1" in document 1' >/dev/null 2>&1 || (( w > 300 )); do sleep 3; (( w++ )); done
    fi
    osascript -e 'tell application "Safari" to close every window' >/dev/null 2>&1
  fi
  if (( ${#new} )); then
    whence att_say >/dev/null && att_say "Click through the welcome windows, then press Return in Terminal."
    print -n "  Press Return when every app is past its welcome screens (they get closed after). "; read -r
    for p in $new; do osascript -e "tell application \"${${p:t}%.app}\" to quit saving no" >/dev/null 2>&1 \
      || osascript -e "tell application \"${${p:t}%.app}\" to quit" >/dev/null 2>&1; print -r -- "$p" >> "$ATT_PRIMED"; done
    sleep 3
  fi
  print "  First-time prompts done. Nothing else should need you."
  print "-----------------------------------------------------------------"
}

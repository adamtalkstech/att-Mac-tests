# att-ui.zsh - hands-off helpers for tests that drive apps (sourced, Nov 20 2026)
# Numbers: knows when a document has opened (Numbers is scriptable).
# Final Cut: knows when the library is open, clicks "Update" on an old library,
# and clicks File > Share > Apple Devices 4K > Next > Save into a folder.
# Needs Terminal allowed in System Settings > Privacy & Security > Accessibility
# (att_ui_setup asks once, at the START of a test, never in the middle).
zmodload zsh/datetime

ATT_UI_DIR=${${(%):-%x}:A:h}   # this file's folder (Tools)
att_say() { print "  ** $*"; say -v Samantha "$*" >/dev/null 2>&1 & }

att_ui_setup() {   # call before the timed part. Returns 0 when UI control works.
  local ok
  ok=$(osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null)
  if [[ $ok != true ]]; then
    print "\nONE-TIME SETUP: let Terminal click buttons for you (so you don't have to mid-test)."
    print "  System Settings > Privacy & Security > Accessibility > turn ON Terminal"
    print "  (if Terminal isn't listed, click + and add Applications/Utilities/Terminal)."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    print -n "  Waiting for it (no need to press anything)"
    for i in {1..200}; do ok=$(osascript -e 'tell application "System Events" to get UI elements enabled' 2>/dev/null); [[ $ok == true ]] && break; print -n "."; sleep 3; done; print ""
    [[ $ok == true ]] || { print "  Still off. The test will ask you to click Share yourself."; return 1; }
  fi
  # Trigger the "Terminal wants to control Numbers" prompt now instead of mid-test
  osascript -e 'tell application "Numbers" to launch' >/dev/null 2>&1
  osascript -e 'tell application "Numbers" to count documents' >/dev/null 2>&1
  osascript -e 'tell application "Numbers" to quit saving no' >/dev/null 2>&1; sleep 2
  return 0
}

# Seconds from now until Numbers has a document open and readable (max $1 s, default 600)
att_numbers_wait() {
  local t0=$EPOCHREALTIME max=${1:-600} r
  while (( EPOCHREALTIME - t0 < max )); do
    whence att_clear_dialogs >/dev/null && att_clear_dialogs Numbers 2   # Nov 22: welcome / newer-version boxes
    r=$(att_osa_capped 5 'tell application "Numbers"
      if (count of documents) is 0 then return "no"
      try
        tell sheet 1 of document 1 to set n to count of tables
        return "yes"
      on error
        return "no"
      end try
    end tell')
    [[ $r == yes ]] && { printf "%.1f" $(( EPOCHREALTIME - t0 )); return 0; }
    sleep 0.5
  done
  return 1
}

# Run an AppleScript but never let it hang a test: killed after $1 seconds (Nov 22).
att_osa_capped() { local secs=$1 out=$(mktemp -t attosa) pid w=0; shift
  osascript -e "$1" > "$out" 2>/dev/null & pid=$!
  while kill -0 $pid 2>/dev/null && (( w < secs * 2 )); do sleep 0.5; (( w++ )); done
  kill -0 $pid 2>/dev/null && { kill $pid 2>/dev/null; sleep 0.5; kill -9 $pid 2>/dev/null; }
  cat "$out"; rm -f "$out"; }

# Wait until Final Cut has the library open and has settled. $1 app name, $2 library path
# The real process name of Final Cut (the Creator Studio version isn't called "Final Cut Pro"). Nov 21.
att_fcp_proc() {
  local n=$(osascript -e 'tell application "System Events" to get name of first process whose bundle identifier starts with "com.apple.FinalCut"' 2>/dev/null)
  print -r -- "${n:-$1}"
}
att_fcp_pid() { pgrep -f "Final Cut[^/]*\.app/Contents/MacOS/" | head -1; }

att_fcp_wait() {
  local app=$1 lib=$2 t0=$EPOCHSECONDS quiet=0 cpu pid
  while (( EPOCHSECONDS - t0 < 600 )); do
    app=$(att_fcp_proc "$1")
    osascript -e "tell application \"System Events\" to tell process \"$app\"
      repeat with w in windows
        try
          if exists button \"Update\" of w then click button \"Update\" of w
        end try
        try
          repeat with s in sheets of w
            if exists button \"Update\" of s then click button \"Update\" of s
          end repeat
        end try
      end repeat
    end tell" >/dev/null 2>&1
    if lsof -c "Final Cut" 2>/dev/null | grep -q "${lib:t}"; then
      pid=$(att_fcp_pid)
      cpu=$(ps -o %cpu= -p $pid 2>/dev/null | awk '{printf "%d", $1}')
      if (( ${cpu:-100} < 40 )); then (( quiet++ )); else quiet=0; fi
      (( quiet >= 5 )) && { print "  Final Cut has the library open (settled after $(( EPOCHSECONDS - t0 ))s)."; return 0; }
    fi
    sleep 1
  done
  print "  Final Cut didn't settle in 10 min, carrying on."; return 1
}

# Is a project open in Final Cut's timeline? (= File > Share > Apple Devices 4K is enabled)
att_fcp_has_project() {
  local app=$(att_fcp_proc "$1")
  [[ $(osascript -e "tell application \"System Events\" to tell process \"$app\"
    try
      repeat with mi in menu items of menu 1 of menu item \"Share\" of menu \"File\" of menu bar 1
        if (name of mi) starts with \"Apple Devices 4K\" then return (enabled of mi) as text
      end repeat
    end try
    return \"false\"
  end tell" 2>/dev/null) == true ]]
}
# Make sure project $2 is open in the timeline BEFORE anything is timed (Nov 21: Final Cut reopened the
# library with no project in the timeline, so Share was greyed out at export time). Tries to open it
# itself (browser search + AXOpen); if that doesn't work, asks you once, right now, and waits.
att_fcp_open_project() {
  local name=$2 app i
  app=$(att_fcp_proc "$1")
  osascript -e "tell application \"System Events\" to tell process \"$app\" to set frontmost to true
    delay 0.5
    tell application \"System Events\" to keystroke \"2\" using command down" >/dev/null 2>&1
  sleep 2
  att_fcp_has_project "$1" && { print "  Project is open in the timeline."; return 0; }
  # Opening a library doesn't open its project (Adam, Nov 21), so open it ourselves.
  # Nov 22 (Adam: "Final Cut locking things up"): the old way asked Final Cut for the "entire contents"
  # of its window, which can be tens of thousands of items and beachballs Final Cut for minutes.
  # Now: menus + keys only (cheap), and any UI lookup is capped at 15 s and killed if it runs long.
  local clk=$HOME/.att/att-click pos
  [[ -x $clk ]] || { mkdir -p ${clk:h}; swiftc -O "$ATT_UI_DIR/att-click.swift" -o "$clk" 2>/dev/null; }
  # 1. Filter the browser to the project: Cmd-1 (browser), Cmd-F (search field), type, Return
  att_osa_capped 15 "tell application \"System Events\" to tell process \"$app\"
    set frontmost to true
    keystroke \"1\" using command down
    delay 1
    keystroke \"f\" using command down
    delay 0.5
    keystroke \"a\" using command down
    keystroke \"$name\"
    delay 0.5
    keystroke return
  end tell" >/dev/null
  sleep 3
  # 2. Select what's left in the browser and open it from the Clip menu (no window crawling)
  att_osa_capped 15 "tell application \"System Events\" to tell process \"$app\"
    set frontmost to true
    keystroke \"1\" using command down
    delay 0.5
    keystroke \"a\" using command down
    delay 0.5
    repeat with mname in {\"Open in Timeline\", \"Open Clip\", \"Open Project\"}
      try
        click menu item (mname as text) of menu 1 of menu bar item \"Clip\" of menu bar 1
        exit repeat
      end try
    end repeat
  end tell" >/dev/null
  sleep 4
  att_fcp_has_project "$1" && { print "  Opened '$name' in the timeline."; return 0; }
  # 2b. Nov 23: Real Day creator never got a project open (export "?"). Find the project's tile with a
  # fast in-process Accessibility search (capped at 25 s, no Final Cut beachball) and double-click it.
  local axf=$HOME/.att/att-axfind fpid
  [[ -x $axf && ! $ATT_UI_DIR/att-axfind.swift -nt $axf ]] || swiftc -O "$ATT_UI_DIR/att-axfind.swift" -o "$axf" 2>/dev/null
  fpid=$(att_fcp_pid)
  if [[ -x $axf && -n $fpid ]]; then
    print "  Looking for '$name' in Final Cut's browser: $("$axf" $fpid "$name" 25)"
    sleep 4; att_fcp_has_project "$1" && { print "  Opened '$name' in the timeline (double-clicked it)."; return 0; }
  fi
  # 3. Last try: find the project's tile in the browser only (not the whole window), capped at 15 s, double-click it
  pos=$(att_osa_capped 15 "tell application \"System Events\" to tell process \"$app\"
    repeat with sa in (scroll areas of splitter groups of window 1)
      try
        set hits to (UI elements of sa whose (name is \"$name\" or description is \"$name\"))
        if (count of hits) > 0 then
          set h to item 1 of hits
          set {px, py} to position of h
          set {sx, sy} to size of h
          return ((px + sx / 2) as integer as text) & \" \" & ((py + sy / 2) as integer as text)
        end if
      end try
    end repeat
    return \"\"
  end tell")
  if [[ -n $pos && -x $clk ]]; then
    "$clk" ${=pos} 2; sleep 4
    att_fcp_has_project "$1" && { print "  Opened '$name' in the timeline (double-clicked it)."; return 0; }
  fi
  [[ -x $clk ]] || print "  (Couldn't build the click helper: needs Xcode or the Command Line Tools.)"
  [[ -z $pos ]] && print "  (Couldn't find '$name' in the Final Cut browser.)"
  whence att_say >/dev/null && att_say "Final Cut needs you once. Double click the project, $name."
  print "  ** Final Cut has no project in the timeline. Double-click '$name' in the Final Cut browser now."
  print "     (Nothing is being timed yet; the test carries on by itself once it's open.)"
  for i in {1..300}; do att_fcp_has_project "$1" && { print "  Got it, project open."; return 0; }; sleep 2; done
  print "  Still no project after 10 min, carrying on."; return 1
}

# Share the timeline with Apple Devices 4K into folder $2. Sets SHARE_START (epoch) on success.
att_fcp_share() {
  local app=$1 dir=$2 r i
  SHARE_START=""
  open -a "$app"; sleep 2
  app=$(att_fcp_proc "$app")
  # Nov 21 fix: under the stacker's load Final Cut is slow to put focus on the timeline, so the
  # Share item read DISABLED one second after Cmd-2. Retry for up to ~60 s: raise the main window,
  # Cmd-1 then Cmd-2 (browser, then timeline), wait, check again.
  local try
  for try in {1..12}; do
  r=$(osascript -e "tell application \"System Events\" to tell process \"$app\"
    set frontmost to true
    try
      perform action \"AXRaise\" of window 1
    end try
    delay 1
    keystroke \"1\" using command down
    delay 0.5
    keystroke \"2\" using command down
    delay 2
    set target to missing value
    repeat with mi in menu items of menu 1 of menu item \"Share\" of menu \"File\" of menu bar 1
      try
        if (name of mi) starts with \"Apple Devices 4K\" then set target to contents of mi
      end try
    end repeat
    if target is missing value then return \"NODEST\"
    if not (enabled of target) then return \"DISABLED\"
    click target
    return \"OK\"
  end tell" 2>&1)
  [[ $r == OK || $r == NODEST ]] && break
  print "  Share menu: $r (Final Cut still busy, try $try of 12)"; sleep 3
  done
  [[ $r == OK ]] || { print "  Share menu: $r"; return 1; }
  # Share window: click Next
  for i in {1..40}; do
    r=$(osascript -e "tell application \"System Events\" to tell process \"$app\"
      repeat with w in windows
        try
          set bs to (buttons of w whose name starts with \"Next\")
          if (count of bs) > 0 then
            click item 1 of bs
            return \"OK\"
          end if
        end try
      end repeat
      return \"no\"
    end tell" 2>/dev/null)
    [[ $r == OK ]] && break; sleep 0.5
  done
  [[ $r == OK ]] || { print "  Couldn't find the Next button."; return 1; }
  sleep 2
  # Save sheet: go to the folder, then Save
  osascript -e "tell application \"System Events\" to tell process \"$app\"
    keystroke \"g\" using {command down, shift down}
    delay 1
    keystroke \"$dir\"
    delay 0.7
    keystroke return
    delay 1.5
  end tell" >/dev/null 2>&1 || return 1
  SHARE_START=$EPOCHREALTIME
  local mark=$(mktemp); touch "$mark"
  osascript -e "tell application \"System Events\" to tell process \"$app\" to keystroke return" >/dev/null 2>&1 || return 1
  # Confirm it really started: a file shows up within 90 s. Final Cut sometimes ignores the
  # Go-to-folder step and saves to its last/default folder (Documents or Movies), so look there too.
  ATT_EXPORT_DIR="$dir"
  local d f
  for i in {1..90}; do
    [[ -n $(print -l "$dir"/*(N.)) ]] && { rm -f "$mark"; return 0; }
    for d in $HOME/Documents $HOME/Movies $HOME/Desktop; do
      f=$(find "$d" -maxdepth 1 -type f -newer "$mark" \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \) 2>/dev/null | head -1)
      [[ -n $f ]] && { ATT_EXPORT_DIR=$d; ATT_EXPORT_FILE=$f; print "  Final Cut saved to ${d:t} instead of Export: timing it there."; rm -f "$mark"; return 0; }
    done
    sleep 1
  done
  rm -f "$mark"; print "  Nothing showed up in Export, Documents or Movies."; SHARE_START=""; return 1
}

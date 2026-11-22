#!/bin/zsh
# =============================================================================
#  att-upload.zsh  -  send test results to Adam's Google Sheet + Drive (v1, Nov 21 2026)
# =============================================================================
#  After every test, the new result files (cards, CSVs, logs: text only) are
#  zipped and sent to a private Google Apps Script. It adds one row to the
#  "Raw Results" tab of the Mac Tests sheet and saves the zip in Google Drive
#  (ATT Test Results/<Mac>/). Nothing is sent if this Mac isn't set up.
#
#  SECURITY
#   - Every upload is signed with a secret key (HMAC-SHA256) plus a timestamp.
#     The Apps Script rejects anything unsigned, wrongly signed, older than
#     5 minutes, or replayed. The key never goes in GitHub (the repo is public).
#   - The key lives only in ~/.att/upload.conf (readable by this user only) and
#     in the Apps Script's private Script Properties.
#   - The script can only ADD rows and files. It can't read or change anything.
#   - Sent over HTTPS. Only .txt/.csv/.log/.json files, never images, video,
#     projects or anything outside Results/<this Mac>/.
#   - Before a loaner ships back:  zsh att-upload.zsh forget
#
#  COMMANDS (run from anywhere):
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh newkey      (once, on Adam's own Mac)
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh setup       (each Mac)
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh test        (sends a test ping)
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh now         (upload anything not sent yet)
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh all         (send EVERY result file on this Mac, once)
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh save-to-drive   (copy this Mac's setup to plugged-in drives)
#   zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-upload.zsh forget      (remove the key from this Mac)
#  Turn it off for one run: NOUPLOAD=1 in front of any test.
# =============================================================================
emulate -L zsh
setopt extended_glob null_glob
TOOLS=${0:A:h}; ROOT=${TOOLS:h}
CONF=$HOME/.att/upload.conf
MARK=$HOME/.att/upload-last
DRIVE_CONF_NAME=".att-upload.conf"     # on a drive's top level, never inside the repo folder
MAXZIP=$(( 25 * 1024 * 1024 ))

say() { print -r -- "$*"; }

load_conf() {
  [[ -s $CONF ]] || return 1
  ATT_UPLOAD_URL=""; ATT_UPLOAD_KEY=""
  local line
  while IFS= read -r line; do
    case $line in
      ATT_UPLOAD_URL=*) ATT_UPLOAD_URL=${line#ATT_UPLOAD_URL=} ;;
      ATT_UPLOAD_KEY=*) ATT_UPLOAD_KEY=${line#ATT_UPLOAD_KEY=} ;;
    esac
  done < $CONF
  [[ $ATT_UPLOAD_URL == https://script.google.com/macros/s/*/exec && $ATT_UPLOAD_KEY == [0-9a-f](#c64) ]]
}

write_conf() {   # $1 url  $2 key
  mkdir -p ${CONF:h}; chmod 700 ${CONF:h}
  ( umask 077; print -r -- "ATT_UPLOAD_URL=$1" > $CONF; print -r -- "ATT_UPLOAD_KEY=$2" >> $CONF )
  chmod 600 $CONF
}

# Keep names to safe characters (no quotes/backslashes can break the JSON)
clean() { print -r -- "$1" | LC_ALL=C tr -cd "A-Za-z0-9 ._()'+/-" | cut -c1-160; }

# $1 = json body file, $2 = label for messages. Returns 0 only if the server said ok.
send() {
  local body=$1 ts sig resp
  ts=$(date +%s)
  sig=$( { printf '%s\n' "$ts"; cat "$body"; } | openssl dgst -sha256 -hmac "$ATT_UPLOAD_KEY" -r | awk '{print $1}')
  [[ $sig == [0-9a-f](#c64) ]] || { say "  Upload: couldn't sign it (openssl)."; return 1; }
  resp=$(curl -sS -L --proto '=https' --tlsv1.2 --max-time 180 \
          -H 'Content-Type: application/json' --data-binary @"$body" \
          "$ATT_UPLOAD_URL?ts=$ts&sig=$sig" 2>&1)
  [[ $resp == ok* ]] && { say "  Upload: ${resp#ok }"; return 0; }
  say "  Upload failed (${resp[1,120]}). Results are still saved on this Mac; they go up with the next test."
  return 1
}

cmd_newkey() {
  local key=$(openssl rand -hex 32)
  [[ $key == [0-9a-f](#c64) ]] || { say "openssl didn't make a key."; exit 1; }
  local url=""; load_conf 2>/dev/null && url=$ATT_UPLOAD_URL
  write_conf "${url:-https://script.google.com/macros/s/PASTE/exec}" "$key"
  print -rn -- "$key" | pbcopy 2>/dev/null
  say "New upload key made and saved to $CONF (only you can read it)."
  say "It's on your clipboard now (not shown on screen, so it never ends up in a photo or screenshot)."
  say "Paste it into the Apps Script: Project Settings > Script Properties > ATT_KEY (Cmd-V)."
  say "Need to see it?  SHOWKEY=1 zsh \"$TOOLS/att-upload.zsh\" newkey   prints a NEW one."
  [[ -n $SHOWKEY ]] && say "  $key"
  say "Then run:  zsh \"$TOOLS/att-upload.zsh\" setup   and paste the web app URL."
  say "(If you make a new key, every Mac needs setup again.)"
}

cmd_setup() {
  local d f url key
  for f in /Volumes/*/$DRIVE_CONF_NAME; do
    url=$(awk -F= '/^ATT_UPLOAD_URL=/{print substr($0,16)}' "$f"); key=$(awk -F= '/^ATT_UPLOAD_KEY=/{print substr($0,16)}' "$f")
    if [[ $url == https://script.google.com/macros/s/*/exec && $key == [0-9a-f](#c64) ]]; then
      write_conf "$url" "$key"; say "Set up from ${f:h}. Sending a test ping..."; cmd_test; return
    fi
  done
  load_conf 2>/dev/null; key=$ATT_UPLOAD_KEY
  print -n "Paste the web app URL (ends in /exec): "; read -r url
  [[ $url == https://script.google.com/macros/s/*/exec ]] || { say "That isn't an Apps Script web app URL."; exit 1; }
  if [[ $key != [0-9a-f](#c64) ]]; then
    print -n "Paste the upload key (64 characters, hidden): "; read -rs key; print ""
    [[ $key == [0-9a-f](#c64) ]] || { say "That isn't a 64-character key."; exit 1; }
  fi
  write_conf "$url" "$key"; say "Saved to $CONF (only you can read it). Sending a test ping..."; cmd_test
}

cmd_test() {
  load_conf || { say "Not set up yet: zsh \"$TOOLS/att-upload.zsh\" setup"; exit 1; }
  local tmp=$(mktemp -d) mac=$(clean "$(scutil --get ComputerName 2>/dev/null)")
  print -rn -- "{\"kind\":\"ping\",\"mac\":\"$mac\",\"test\":\"ping\",\"when\":\"$(date '+%Y-%m-%d %H:%M:%S %Z')\"}" > $tmp/body.json
  send $tmp/body.json && say "Works. Check the Raw Results tab for a ping row."
  rm -rf $tmp
}

cmd_save_to_drive() {
  load_conf || { say "Not set up on this Mac yet."; exit 1; }
  local n=0 v
  for v in /Volumes/*(N/); do
    [[ -d "$v/Adam Talks Tech Tests" ]] || continue
    ( umask 077; cp $CONF "$v/$DRIVE_CONF_NAME" ) && { say "Saved to $v/$DRIVE_CONF_NAME"; (( n++ )); }
  done
  (( n )) || say "No test drive plugged in."
  say "Other Macs: plug the drive in and run setup. Delete the file from a drive you lend out."
}

cmd_forget() {
  rm -f $CONF $MARK && say "Upload key removed from this Mac. (Do this before a loaner ships back.)"
}

# A short ID that's unique to this Mac's hardware (a one-way hash of its hardware UUID, so the
# serial number is never sent). Two Macs both called "MacBook Pro" still land in separate folders.
mac_id() {
  ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/ {print $4}' | shasum -a 256 | cut -c1-8
}
TXT=( \( -name '*.txt' -o -name '*.csv' -o -name '*.log' -o -name '*.json' \) )

# Zip + send one folder's files. $1 = folder, $2 = label, $3 = folder name as saved (Results/<this>), rest = files
send_batch() {
  local dir=$1 label=$2 resname=$3; shift 3
  local -a files=("$@")
  (( ${#files} )) || return 0
  local tmp=$(mktemp -d)
  ( cd "$dir" && print -rl -- $files | zip -q -X "$tmp/results.zip" -@ ) 2>/dev/null
  local size=$(stat -f %z "$tmp/results.zip" 2>/dev/null || echo 0) zipb64="" note=""
  if (( size > 0 && size <= MAXZIP )); then zipb64=$(base64 -i "$tmp/results.zip" | tr -d '\n')
  else note="zip too big (${size} bytes), logs not sent: copy Results/$resname from a drive"; fi
  [[ $resname != $ATT_MAC && $resname != . ]] && note="${note:+$note; }from Results/$resname on this Mac (older name, or copied from a drive)"
  local newest=$(cd "$dir" && ls -t ${(M)files:#*.txt} 2>/dev/null | head -1) summary=""
  [[ -n $newest ]] && summary=$(head -c 40000 "$dir/$newest" | base64 | tr -d '\n')
  print -rn -- "{\"kind\":\"result\",\"mac\":\"$(clean "$ATT_MAC")\",\"macid\":\"$ATT_MACID\",\"test\":\"$(clean "$label")\",\"mackind\":\"$(clean "$ATT_KIND")\",\"when\":\"$(date '+%Y-%m-%d %H:%M:%S %Z')\",\"files\":${#files},\"note\":\"$(clean "$note")\",\"summary_file\":\"$(clean "$resname/${newest#./}")\",\"summary_b64\":\"$summary\",\"zip_b64\":\"$zipb64\"}" > $tmp/body.json
  print "Uploading ${#files} result file(s) from Results/$resname to the Mac Tests sheet + Drive..."
  send $tmp/body.json; local rc=$?
  rm -rf $tmp
  return $rc
}

# Upload every result file that changed since the last good upload. $1 = test name
cmd_auto() {
  [[ -n $NOUPLOAD ]] && return 0
  load_conf || return 0
  ATT_MAC=$(scutil --get ComputerName 2>/dev/null)
  ATT_MACID=$(mac_id)
  ATT_KIND=$(cat $HOME/.att/mac-kind.txt 2>/dev/null)
  local stamp=$(date +%s) markt=$(mktemp) ok=1 d n
  touch -t "$(date -r $(( stamp - 1 )) +%Y%m%d%H%M.%S)" $markt   # anything written during the upload still counts next time
  local -a files
  if [[ -n $ATT_UPLOAD_ALL ]]; then
    # Every folder in Results, one upload each: this Mac's, any older name it had, anything copied from a drive.
    for d in "$ROOT/Results"/*(N/); do
      n=${d:t}
      files=("${(@f)$(cd "$d" && find . -type f $TXT 2>/dev/null)}"); files=(${files:#})
      send_batch "$d" "$1" "$n" $files || ok=0
    done
    for d in "$ROOT/Results"/*.csv(N); do   # shared CSVs at the top (All Macs lmstudio.csv etc.)
      send_batch "$ROOT/Results" "$1 (shared CSVs)" "." "./${d:t}" || ok=0
    done
  else
    d="$ROOT/Results/$ATT_MAC"; [[ -d $d ]] || { rm -f $markt; return 0; }
    if [[ -f $MARK ]]; then files=("${(@f)$(cd "$d" && find . -type f $TXT -newer "$MARK" 2>/dev/null)}")
    else files=("${(@f)$(cd "$d" && find . -type f $TXT -mtime -2 2>/dev/null)}"); fi   # first time: last 2 days
    files=(${files:#})
    (( ${#files} )) || { rm -f $markt; return 0; }
    send_batch "$d" "$1" "$ATT_MAC" $files || ok=0
  fi
  if (( ok )); then mkdir -p ${MARK:h}; mv -f $markt $MARK; else rm -f $markt; fi
  return 0
}

case $1 in
  newkey) cmd_newkey ;;
  setup) cmd_setup ;;
  test) cmd_test ;;
  now) load_conf || { say "This Mac isn't set up yet. Run:  zsh \"$TOOLS/att-upload.zsh\" setup   (test drive plugged in)"; exit 1; }; cmd_auto "manual upload" ;;
  all)   # first gather the Puget CSVs that app runs left in Puget's own folder
    [[ -f "$ROOT/Puget Test/att-puget.zsh" ]] && ( cd "$ROOT/Puget Test" && NOUPLOAD=1 zsh att-puget.zsh collect >/dev/null 2>&1 ) && say "Gathered the Puget CSVs into Results first."
    load_conf || { say "This Mac isn't set up yet, so nothing was sent. Run:  zsh \"$TOOLS/att-upload.zsh\" setup   (test drive plugged in), then all again."; exit 1; }
    ATT_UPLOAD_ALL=1 cmd_auto "full backfill"; say "Done. Check the Raw Results tab." ;;
  save-to-drive) cmd_save_to_drive ;;
  forget) cmd_forget ;;
  auto) cmd_auto "${2:-test}" ;;
  *) sed -n 2,30p "$0" ;;
esac

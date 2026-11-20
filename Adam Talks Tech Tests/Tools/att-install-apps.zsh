#!/bin/zsh
# =============================================================================
#  att-install-apps.zsh  -  install the test apps on a new Mac (v1, Nov 20 2026)
# =============================================================================
#  Installs everything in "Apps & Installers" in one go (asks for the password once),
#  skips apps that are already installed at the same version, then opens the
#  App Store pages and the Creative Cloud installer for what can't be scripted.
#
#  Run (from the drive or from Downloads, either works):
#    cd ~/Downloads/"Adam Talks Tech Tests"/"Tools" && zsh att-install-apps.zsh
#  Options in front:
#    EXTRAS=1   also 3DMark, Procyon AI Image Generation, Diffusion Bee, TG Pro
#    PROCYON=all  every Procyon test (battery, office, photo, AI text, vision, image)
#    FORCE=1    reinstall even if the same version is already there
#
#  Core (always): Geekbench 7, Geekbench AI, Blackmagic RAW Speed Test,
#  Cinebench 2026, Blender 5.2.3, HandBrake, LM Studio, PugetBench for Creators,
#  DaVinci Resolve Studio, Steam, Stats.
#  Skipped on purpose: Minecraft (retired Nov 20), HandBrakeCLI (the HandBrake
#  test pulls it out of its dmg by itself).
# =============================================================================

NAME="Adam Talks Tech Tests"
HERE=${0:A:h}; ROOT=$HERE
while [[ $ROOT != / && ${ROOT:t} != $NAME ]]; do ROOT=${ROOT:h}; done
SRC=""
for d in "$ROOT/Apps & Installers" /Volumes/*/"$NAME"/"Apps & Installers"(N/); do [[ -d $d ]] && { SRC=$d; break; }; done
[[ -n $SRC ]] || { print "Can't find the Apps & Installers folder (in the test folder or on a plugged-in drive)."; exit 1; }

typeset -a CORE EXTRA
CORE=("Geekbench 7.app" "Geekbench AI.app" "Blackmagic RAW Speed Test.app" "Cinebench2026_macOS.dmg"
      "blender-5.2.3-macos-arm64.dmg" "HandBrake-1.11.2.dmg" "LM-Studio-0.4.28-2-arm64.dmg"
      "PugetBench for Creators_1.4.50_universal.dmg" "DaVinci_Resolve_Studio_21.2_Mac.dmg" "steam.dmg" "Stats.dmg")
EXTRA=("3DMark-MacOS-v1-1-350.pkg" "DiffusionBee_MPS_arm64-2.5.1.dmg" "TG Pro 2.105.dmg")
typeset -a ITEMS; ITEMS=($CORE)
[[ $EXTRAS == 1 ]] && ITEMS+=($EXTRA)
if [[ $PROCYON == all ]]; then for k in "$SRC/UL Procyon (all macOS tests)"/*.pkg(N); do ITEMS+=("UL Procyon (all macOS tests)/${k:t}"); done
elif [[ $EXTRAS == 1 ]]; then ITEMS+=("UL Procyon (all macOS tests)/Procyon-v2-1-97-ai-image-generation-benchmark-macos.pkg"); fi

print "Installing from: $SRC"
print "Enter your Mac password once (installers need it):"
sudo -v || exit 1
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) & KEEP=$!

typeset -a DONE SKIPPED FAILED
ver() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null; }

install_app() {   # $1 = path to a .app
  local app=$1 dest="/Applications/${1:t}"
  [[ ${app:t} == *[Uu]ninstall* ]] && return 0
  if [[ -d $dest && $FORCE != 1 && "$(ver "$dest")" == "$(ver "$app")" ]]; then SKIPPED+=("${app:t:r} $(ver "$dest")"); return 0; fi
  print "  copying ${app:t}..."
  [[ -d $dest ]] && sudo rm -rf "$dest"
  if sudo ditto "$app" "$dest"; then sudo xattr -dr com.apple.quarantine "$dest" 2>/dev/null; DONE+=("${app:t:r} $(ver "$dest")")
  else FAILED+=("${app:t}"); fi
}
install_pkg() {   # $1 = path to a .pkg
  print "  installing ${1:t} (can take a few minutes)..."
  if sudo installer -pkg "$1" -target / >/dev/null; then DONE+=("${1:t:r}"); else FAILED+=("${1:t}"); fi
}

for item in $ITEMS; do
  p="$SRC/$item"
  [[ -e $p ]] || { FAILED+=("$item (not in Apps & Installers)"); continue; }
  print "\n> ${item:t}"
  case $p in
    *.app) install_app "$p" ;;
    *.pkg) install_pkg "$p" ;;
    *.dmg)
      mnt=$(mktemp -d /tmp/attdmg.XXXX)
      if ! yes | hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$p" >/dev/null 2>&1; then FAILED+=("${item} (wouldn't open)"); continue; fi
      found=0
      for a in "$mnt"/*.app(N) "$mnt"/*/*.app(N); do install_app "$a"; found=1; done
      for k in "$mnt"/*.pkg(N) "$mnt"/*/*.pkg(N) "$mnt"/*.mpkg(N); do [[ ${k:t} == *[Uu]ninstall* ]] || { install_pkg "$k"; found=1; }; done
      (( found )) || FAILED+=("${item} (no app or installer inside)")
      hdiutil detach "$mnt" -quiet 2>/dev/null; rmdir "$mnt" 2>/dev/null ;;
  esac
done
kill $KEEP 2>/dev/null

# ---------- What can't be scripted ----------
typeset -a STORE
store() { [[ -d "/Applications/$1.app" ]] || { open "macappstore://apps.apple.com/app/id$2"; STORE+=("$1"); }; }
store "Xcode" 497799835
store "Final Cut Pro" 424389933
store "Logic Pro" 634148309
store "Compressor" 424390742
CC=0
if [[ ! -d "/Applications/Utilities/Adobe Creative Cloud" && ! -d "/Applications/Adobe Creative Cloud" ]]; then
  ccd=$(ls "$SRC"/Creative_Cloud_Installer*.dmg 2>/dev/null | head -1)
  [[ -n $ccd ]] && { open "$ccd"; CC=1; }
fi

source "$HERE/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; }
att_card_start "App install"
(( ${#DONE} ))    && { print "Installed:"; for x in $DONE; do print "  + $x"; done; }
(( ${#SKIPPED} )) && { print "Already up to date:"; for x in $SKIPPED; do print "  = $x"; done; }
(( ${#FAILED} ))  && { print "PROBLEMS:"; for x in $FAILED; do print "  !! $x"; done; }
(( ${#STORE} ))   && print "App Store pages opened (click Get/Install): ${(j:, :)STORE}"
(( CC ))          && print "Creative Cloud installer opened: sign in, then install Lightroom Classic, Photoshop, Premiere Pro, After Effects."
print "Still by hand: open Resolve once and activate (key in LICENSES), open LM Studio once,"
print "open Xcode once (it installs its components), sign into Steam."
att_card_end

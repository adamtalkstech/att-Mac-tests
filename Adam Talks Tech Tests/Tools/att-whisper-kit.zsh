#!/bin/zsh
# =============================================================================
#  att-whisper-kit.zsh - make sure this Mac has the Nov 22 Whisper kit (locked to the Neural Engine)
# =============================================================================
#  Used by Update Scripts (in the background) and by the walk-away queue before Whisper (step 14f).
#  1. Already there and locked -> nothing to do.
#  2. A plugged-in test drive has the locked kit -> copies it (fast).
#  3. Otherwise builds it from GitHub + the internet: the two whisper.cpp programs, BUILD-INFO and the
#     audio come with the scripts (AI Tests/whisper-kit); the model (1.6 GB) and the Neural Engine
#     encoder (1.2 GB) download from huggingface.co/ggerganov/whisper.cpp, the same files the kit used.
#  Safe to run again: a stopped download picks up where it left off. Log: ~/.att/whisper-kit.log
# =============================================================================
ROOT=${0:A:h:h}; AI="$ROOT/AI Tests"; KIT="$AI/whisper-test"; SRC="$AI/whisper-kit"
HF=https://huggingface.co/ggerganov/whisper.cpp/resolve/main
locked() { grep -q CPUAndNeuralEngine "$1/BUILD-INFO.txt" 2>/dev/null && [[ -x $1/bin/whisper-cli-coreml && -s $1/models/ggml-large-v3-turbo.bin && -d $1/models/ggml-large-v3-turbo-encoder.mlmodelc ]]; }
audio() { [[ -s "$AI/Whisper test audio.wav" ]] || cp "$SRC/Whisper test audio.wav" "$AI/" 2>/dev/null; }
# Nov 22 evening: the 16" and M5 Pro MBP crashed instantly on a kit whose model was garbled. Update Scripts
# was still downloading in the background when the queue started a second download of the same file.
# Now: only one download at a time (lock), the file size is checked against the server, and the kit has
# to transcribe the 11 s JFK sample before it counts as ready. A bad kit on this Mac gets thrown out.
selftest() { local b; for b in whisper-cli-metal whisper-cli-coreml; do
    "$1/bin/$b" -m "$1/models/ggml-large-v3-turbo.bin" -f "$1/samples/jfk.wav" -nt 2>/dev/null | grep -qi "ask not" || return 1; done; }
LOCK=$HOME/.att/whisper-kit.lock; mkdir -p $HOME/.att
w=0; until mkdir "$LOCK" 2>/dev/null; do
  (( w == 0 )) && print "Whisper kit: another download is already running on this Mac, waiting for it to finish..."
  # a lock older than 2 h is left over from a stopped run
  [[ -n $(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null) ]] && { rmdir "$LOCK" 2>/dev/null; continue; }
  sleep 10; (( w += 10 )); (( w > 3600 )) && { print "!! Whisper kit: waited an hour for the other download. Run Update Scripts again."; exit 1; }
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
if locked "$KIT"; then
  if [[ -f $KIT/.selftest-ok ]] || selftest "$KIT"; then touch "$KIT/.selftest-ok"; audio; print "Whisper kit: up to date (Neural Engine locked)."; exit 0; fi
  print "!! Whisper kit on this Mac fails its 11 s test (model garbled?). Throwing it out and getting a fresh copy."
  rm -rf "$KIT"
fi
for v in /Volumes/*/"Adam Talks Tech Tests"/"AI Tests"/whisper-test(N/); do
  if locked "$v"; then
    print "Whisper kit: copying the new kit from ${${v#/Volumes/}%%/*} (2.8 GB)..."
    rm -rf "$KIT.new"; ditto "$v" "$KIT.new" && { rm -rf "$KIT"; mv "$KIT.new" "$KIT"; }
    [[ -s "${v:h}/Whisper test audio.wav" ]] && ditto "${v:h}/Whisper test audio.wav" "$AI/Whisper test audio.wav"
    xattr -dr com.apple.quarantine "$KIT" 2>/dev/null; locked "$KIT" && selftest "$KIT" && { touch "$KIT/.selftest-ok"; audio; print "Whisper kit: done."; exit 0; }
    print "!! The kit on ${${v#/Volumes/}%%/*} failed its 11 s test, trying the next one."; rm -rf "$KIT"
  fi
done
[[ -x $SRC/bin/whisper-cli-coreml ]] || { print "!! Whisper kit: the programs aren't in the scripts folder yet. Run Update Scripts, then this again."; exit 1; }
print "Whisper kit: downloading the model + Neural Engine encoder (2.8 GB, once per Mac)..."
D="$KIT.new"; mkdir -p "$D/bin" "$D/models" "$D/samples"
cp "$SRC/bin/"* "$D/bin/"; chmod +x "$D/bin/"*; cp "$SRC/BUILD-INFO.txt" "$D/"; cp "$SRC/samples/jfk.wav" "$D/samples/"
# keep finished downloads in ~/.att so a stopped run resumes instead of starting over
C=$HOME/.att/whisper-dl; mkdir -p $C
curl -fL -C - --retry 3 -o "$C/ggml-large-v3-turbo.bin" "$HF/ggml-large-v3-turbo.bin" || { print "!! Model download failed. Run it again to resume."; exit 1; }
curl -fL -C - --retry 3 -o "$C/encoder.zip" "$HF/ggml-large-v3-turbo-encoder.mlmodelc.zip" || { print "!! Encoder download failed. Run it again to resume."; exit 1; }
sz() { curl -sIL "$1" | awk 'tolower($1)=="content-length:"{n=$2} END{gsub(/\r/,"",n); print n+0}'; }
for f in ggml-large-v3-turbo.bin:ggml-large-v3-turbo.bin encoder.zip:ggml-large-v3-turbo-encoder.mlmodelc.zip; do
  want=$(sz "$HF/${f#*:}"); have=$(stat -f %z "$C/${f%%:*}" 2>/dev/null)
  if (( want > 0 && have != want )); then print "!! ${f%%:*} is $have bytes, should be $want. Deleting it: run Update Scripts again to redownload."; rm -f "$C/${f%%:*}"; exit 1; fi
done
ditto "$C/ggml-large-v3-turbo.bin" "$D/models/ggml-large-v3-turbo.bin" && ditto -x -k "$C/encoder.zip" "$D/models/" || { print "!! Couldn't unpack the encoder."; exit 1; }
rm -rf "$D/models/__MACOSX"; xattr -dr com.apple.quarantine "$D" 2>/dev/null
if locked "$D" && selftest "$D"; then touch "$D/.selftest-ok"; rm -rf "$KIT"; mv "$D" "$KIT"; audio; rm -rf $C; print "Whisper kit: ready (Neural Engine locked, passed its 11 s test)."
elif locked "$D"; then rm -rf "$D" $C; print "!! Whisper kit downloaded but fails its 11 s test. Deleted it; run Update Scripts again. If it fails twice, send Claude ~/.att/whisper-kit.log"; exit 1
else print "!! Whisper kit: something's missing after the download. Send Claude ~/.att/whisper-kit.log"; exit 1; fi

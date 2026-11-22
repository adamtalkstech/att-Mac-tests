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
if locked "$KIT"; then audio; print "Whisper kit: up to date (Neural Engine locked)."; exit 0; fi
for v in /Volumes/*/"Adam Talks Tech Tests"/"AI Tests"/whisper-test(N/); do
  if locked "$v"; then
    print "Whisper kit: copying the new kit from ${${v#/Volumes/}%%/*} (2.8 GB)..."
    rm -rf "$KIT.new"; ditto "$v" "$KIT.new" && { rm -rf "$KIT"; mv "$KIT.new" "$KIT"; }
    [[ -s "${v:h}/Whisper test audio.wav" ]] && ditto "${v:h}/Whisper test audio.wav" "$AI/Whisper test audio.wav"
    xattr -dr com.apple.quarantine "$KIT" 2>/dev/null; locked "$KIT" && { audio; print "Whisper kit: done."; exit 0; }
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
(( $(stat -f %z "$C/ggml-large-v3-turbo.bin") > 1500000000 )) || { print "!! Model download looks too small. Delete ~/.att/whisper-dl and run it again."; exit 1; }
ditto "$C/ggml-large-v3-turbo.bin" "$D/models/ggml-large-v3-turbo.bin" && ditto -x -k "$C/encoder.zip" "$D/models/" || { print "!! Couldn't unpack the encoder."; exit 1; }
rm -rf "$D/models/__MACOSX"; xattr -dr com.apple.quarantine "$D" 2>/dev/null
if locked "$D"; then rm -rf "$KIT"; mv "$D" "$KIT"; audio; rm -rf $C; print "Whisper kit: ready (Neural Engine locked)."
else print "!! Whisper kit: something's missing after the download. Send Claude ~/.att/whisper-kit.log"; exit 1; fi

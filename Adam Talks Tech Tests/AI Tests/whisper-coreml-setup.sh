#!/bin/zsh
# =============================================================================
#  whisper-coreml-setup.sh  -  builds the whisper.cpp test kit for lmstudio-bench.sh
# =============================================================================
#  Run ONCE on one Mac (the Mac Studio's ~/Downloads copy is fine; the whisper-test
#  folder then travels with the test folder like everything else):
#      zsh whisper-coreml-setup.sh
#  It makes a "whisper-test" folder next to itself with:
#      bin/whisper-cli-metal    whisper.cpp built for the GPU (Metal)
#      bin/whisper-cli-coreml   the SAME whisper.cpp version built with Core ML,
#                               so the encoder runs on the Neural Engine
#      models/ggml-large-v3-turbo.bin + ggml-large-v3-turbo-encoder.mlmodelc
#      BUILD-INFO.txt           version, commit, date (for the test card)
#  Every other Mac just uses that folder from the LaCie. Nothing to install.
#
#  Needs on the build Mac: Xcode command line tools (xcode-select --install),
#  cmake (brew install cmake), about 3 GB free on the drive.
#  Optional: WHISPER_TAG=v1.8.2 to pin a version instead of the latest release.
# =============================================================================

set -e
SCRIPT_DIR=${0:A:h}
OUT="$SCRIPT_DIR/whisper-test"
REPO="https://github.com/ggml-org/whisper.cpp"
HF="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
MODEL="ggml-large-v3-turbo"

step() { print -P "%B==> $*%b"; }
die()  { print -r -- "ERROR: $*" >&2; exit 1; }

[[ $(uname -m) == arm64 ]] || die "Run this on an Apple Silicon Mac."
xcode-select -p >/dev/null 2>&1 || die "Xcode command line tools missing. Run: xcode-select --install"
command -v git >/dev/null || die "git missing (comes with the Xcode command line tools)."
if ! command -v cmake >/dev/null; then
  command -v brew >/dev/null || die "cmake missing and Homebrew isn't installed. Install Homebrew (brew.sh), then rerun."
  step "Installing cmake"; brew install cmake
fi

mkdir -p "$OUT/bin" "$OUT/models" "$OUT/samples"

# ---- 1. Source at one fixed release, so every number comes from the same code ----
TAG=${WHISPER_TAG:-$(git ls-remote --tags --refs "$REPO" | awk -F/ '{print $3}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)}
[[ -n $TAG ]] || die "Couldn't find a whisper.cpp release tag. Check the internet connection."
step "whisper.cpp $TAG"
rm -rf "$OUT/src"
git clone --depth 1 --branch "$TAG" "$REPO" "$OUT/src" >/dev/null 2>&1 || die "git clone failed"
COMMIT=$(git -C "$OUT/src" rev-parse --short HEAD)

# ---- 2. Two builds from the same source: GPU only, and Core ML (Neural Engine) ----
JOBS=$(sysctl -n hw.ncpu)
step "Building GPU (Metal) version"
cmake -S "$OUT/src" -B "$OUT/src/build-metal" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF >/dev/null
cmake --build "$OUT/src/build-metal" -j $JOBS --config Release --target whisper-cli >/dev/null
cp "$OUT/src/build-metal/bin/whisper-cli" "$OUT/bin/whisper-cli-metal"

step "Building Core ML (Neural Engine) version"
cmake -S "$OUT/src" -B "$OUT/src/build-coreml" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_COREML=1 >/dev/null
cmake --build "$OUT/src/build-coreml" -j $JOBS --config Release --target whisper-cli >/dev/null
cp "$OUT/src/build-coreml/bin/whisper-cli" "$OUT/bin/whisper-cli-coreml"
cp "$OUT/src/samples/jfk.wav" "$OUT/samples/jfk.wav"    # short clip for the untimed warm-up

# ---- 3. Model + ready-made Core ML encoder from the whisper.cpp model page ----
cd "$OUT/models"
if [[ ! -s $MODEL.bin ]]; then
  step "Downloading $MODEL.bin (about 1.6 GB)"
  curl -L --fail --progress-bar -o "$MODEL.bin.part" "$HF/$MODEL.bin" && mv "$MODEL.bin.part" "$MODEL.bin"
fi
if [[ ! -d $MODEL-encoder.mlmodelc ]]; then
  step "Downloading the Core ML encoder (about 1.2 GB)"
  curl -L --fail --progress-bar -o "$MODEL-encoder.mlmodelc.zip" "$HF/$MODEL-encoder.mlmodelc.zip"
  unzip -q -o "$MODEL-encoder.mlmodelc.zip" && rm "$MODEL-encoder.mlmodelc.zip"
fi
[[ -d $MODEL-encoder.mlmodelc ]] || die "Core ML encoder folder missing after unzip."

# ---- 4. Self-test: both builds work, and the Core ML one really loads Core ML ----
step "Self-test (first Core ML run compiles the model for this Mac, can take a few minutes)"
"$OUT/bin/whisper-cli-metal" -m "$OUT/models/$MODEL.bin" -f "$OUT/samples/jfk.wav" -nt >/dev/null 2>"$OUT/selftest-metal.log" \
  || die "Metal build failed the self-test. See $OUT/selftest-metal.log"
"$OUT/bin/whisper-cli-coreml" -m "$OUT/models/$MODEL.bin" -f "$OUT/samples/jfk.wav" -nt >/dev/null 2>"$OUT/selftest-coreml.log" \
  || die "Core ML build failed the self-test. See $OUT/selftest-coreml.log"
grep -q "Core ML model loaded" "$OUT/selftest-coreml.log" || die "Core ML build ran but didn't load the Core ML model. See $OUT/selftest-coreml.log"

cat > "$OUT/BUILD-INFO.txt" <<EOF
whisper.cpp $TAG (commit $COMMIT)
Built $(date '+%b %d, %Y') on $(scutil --get ComputerName) ($(sw_vers -productVersion)), $(xcodebuild -version 2>/dev/null | head -1 || echo 'Xcode CLT')
Model: $MODEL.bin + $MODEL-encoder.mlmodelc (from huggingface.co/ggerganov/whisper.cpp)
bin/whisper-cli-metal  = GPU (Metal) build
bin/whisper-cli-coreml = Core ML build (encoder on the Neural Engine)
EOF

rm -rf "$OUT/src/build-metal" "$OUT/src/build-coreml"
print ""
print "Done. Test kit is in: $OUT"
print "Next: put a stream audio file named \"Whisper test audio.wav\" (or .mp3) next to lmstudio-bench.sh,"
print "then on any Mac run:  zsh lmstudio-bench.sh whisper"

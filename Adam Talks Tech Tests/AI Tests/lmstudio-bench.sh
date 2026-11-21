#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# =============================================================================
#  lmstudio-bench.sh  v2.1  -  Adam Talks Tech local AI test suite
# =============================================================================
#  Runs every local AI test prompt through LM Studio's local server with the
#  same settings every time. Logs TTFT, tok/s, tokens, peak memory, swap,
#  watts, tokens per watt and heat. Every prompt runs 3 times (median kept).
#
#  USAGE (Terminal):
#    zsh lmstudio-bench.sh info        Mac + versions, finds test files/models/tools
#    zsh lmstudio-bench.sh gemma       Test 1  Gemma 3 4B   (Roman + Apple)
#    zsh lmstudio-bench.sh qwen9b      Test 2  Qwen 3.5 9B  (transcripts A/B/C + Roman 10)
#    zsh lmstudio-bench.sh qwen27b     Test 3  Qwen3.8 27B 4-bit RAM wall test
#    zsh lmstudio-bench.sh ladder      Bonus   27B at 4/5/6/8-bit, Roman 10 tok/s
#    zsh lmstudio-bench.sh moe         Test 4  MoE model (30B-class, ~3B active)
#    zsh lmstudio-bench.sh coding      Test 5  fixed coding task, time to finish
#    zsh lmstudio-bench.sh agents      Test 6  1 request vs 4 at once (total tok/s)
#    zsh lmstudio-bench.sh whisper     Test 7  transcribe stream audio: GPU vs Neural Engine
#    zsh lmstudio-bench.sh llamabench  Check   standard llama.cpp numbers (pp512/tg128)
#    zsh lmstudio-bench.sh core        Tests 1-3 + ladder (the sheet columns)
#    zsh lmstudio-bench.sh all         Everything above, in that order
#
#  OPTIONAL SETTINGS (put in front of the command):
#    LABEL="M5 Pro PROLED"   name used in results files
#    RUNS=3                  runs per prompt, median kept (RUNS=1 for a quick pass)
#    COOLDOWN=20             seconds to rest between runs
#    PURGE=0  POWER=0        skip cold-cache loads / watts (no password prompt)
#    RESULTS_DIR=...   override (default: Adam Talks Tech Tests/Results/<Mac>/LM Studio)
#
#  NEEDS: LM Studio opened once (so lms exists), the test models and text files
#  next to this script / Desktop / Downloads / a connected drive. Laptops on power.
#  Whisper needs the whisper-test folder (run whisper-coreml-setup.sh once, on one Mac).
#  llamabench needs: brew install llama.cpp
# =============================================================================

zmodload zsh/datetime

# ---------- Settings (same on every Mac) ----------
PORT=${PORT:-1234}
API="http://localhost:$PORT"
SCRIPT_DIR=${0:A:h}
PROMPT_DIR=${PROMPT_DIR:-$SCRIPT_DIR}
# Results: inside the test folder like the other ATT scripts (Results/<Mac>/LM Studio),
# falls back to the Desktop if the script isn't inside "Adam Talks Tech Tests".
ROOT=$SCRIPT_DIR
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
if [[ $ROOT == / ]]; then
  RESULTS_DIR=${RESULTS_DIR:-"$HOME/Desktop/LM Studio Results"}; ALL_DIR=${ALL_DIR:-$RESULTS_DIR}
else
  _MACNAME=$(scutil --get ComputerName 2>/dev/null); _MACNAME=${_MACNAME:-$(hostname -s)}
  RESULTS_DIR=${RESULTS_DIR:-"$ROOT/Results/$_MACNAME/LM Studio"}; ALL_DIR=${ALL_DIR:-"$ROOT/Results"}
fi
RUNS=${RUNS:-3}
COOLDOWN=${COOLDOWN:-20}
TEMP=${TEMP:-0}                   # 0 = same output every run, so token counts match across Macs
LOAD_TIMEOUT=${LOAD_TIMEOUT:-600} # load still going after 10 min = Won't load
GEN_TIMEOUT=${GEN_TIMEOUT:-1500}  # one prompt still going after 25 min = Swaps
WARM_TIMEOUT=${WARM_TIMEOUT:-300}
SWAP_FLAG_GB=${SWAP_FLAG_GB:-0.5} # more new swap than this during a run = "Swaps"
PURGE=${PURGE:-1}
POWER=${POWER:-1}
AGENTS=${AGENTS:-4}

GEMMA_CTX=${GEMMA_CTX:-8192}
GEMMA_MAX=${GEMMA_MAX:-4096}      # cap so "don't stop" can't run forever
QWEN_CTX_AB=8192
QWEN_CTX_C=32768
QWEN_MAX=${QWEN_MAX:-4096}
CODE_MAX=${CODE_MAX:-4096}

# Models are found by name. Force one with GEMMA_MODEL=, QWEN9_MODEL=, QWEN27_MODEL=,
# MOE_MODEL=, CODE_MODEL= (exact key from "info").
GEMMA_PATTERN='gemma-3-4b'
QWEN9_PATTERN='qwen3\.5-9b-mlx-4bit';   QWEN9_LOOSE='qwen3\.5-9b'
QWEN27_PATTERN='qwen3\.8-27b-mlx-4bit'; QWEN27_LOOSE='qwen3\.8-27b'
MOE_PATTERN=${MOE_PATTERN:-'30b-a3b'}
LADDER_BITS=(4 5 6 8)

ROMAN50="Write a detailed, 50-paragraph essay explaining the historical significance of the Roman Empire on modern law, philosophy, and architecture. Be verbose and do not stop until you run out of tokens."
ROMAN10="Write exactly 10 paragraphs about the history of the Roman Empire, from its founding to the fall of the Western Empire."
SUMMARY_Q="Summarize this livestream. Give me the 5 main topics, every viewer question with my answer in one line, and every product I recommended."
CODE_PROMPT="Write a complete, single-file Python command-line to-do app. It needs add, list, done and delete commands, saves tasks to a JSON file next to the script, uses argparse, and handles a missing or corrupt file without crashing. Include docstrings, type hints and a short usage example at the end. Output only the code."
APPLE_FILE="LM Studio Gemma - Apple prompt (paste all)"
TRANSCRIPT_A="Qwen test A_short_10min"
TRANSCRIPT_B="Qwen test B_medium_30min"
TRANSCRIPT_C="Qwen test C_full_stream"
WHISPER_AUDIO=${WHISPER_AUDIO:-"Whisper test audio"}   # wav or mp3 of a stream, next to this script
# whisper.cpp kit: the "whisper-test" folder made once by whisper-coreml-setup.sh (GPU + Core ML builds)

# ---------- Plumbing ----------
LMS=$(command -v lms 2>/dev/null); [[ -z $LMS ]] && LMS="$HOME/.lmstudio/bin/lms"
AUTH=(); [[ -n $LM_API_TOKEN ]] && AUTH=(-H "Authorization: Bearer $LM_API_TOKEN")
TMP=$(mktemp -d /tmp/lmsbench.XXXXXX)
typeset -gA RES_STATUS RES_TTFT RES_TPS RES_OUT RES_IN RES_PMEM RES_SWAP RES_LOAD RES_W RES_TPW RES_TOTAL RES_THERM
SAMPLER_PID=""; SUDO_KEEP=""; HAVE_SUDO=0; COLD_NEXT=0; POWER_ON=0
SHEET_LINES=(); EXTRA_LINES=()

say()  { print -r -- "$*" | tee -a "$REPORT"; }
warn() { print -r -- "  !! $*" | tee -a "$REPORT" >&2; }
die()  { print -r -- "ERROR: $*" >&2; cleanup; exit 1; }
fmt()  { if [[ -n $1 && $1 != null && $1 != "-" ]]; then printf "%.2f" "$1"; else print -n -- "-"; fi; }
getv() { local n="${1}[${2}]"; print -r -- "${(P)n}"; }   # getv ARRAY key
median() { print -l -- "$@" | grep -E '^[0-9.]+$' | sort -g | awk '{a[NR]=$1}
  END{ if(NR==0) exit; if(NR%2) print a[(NR+1)/2]; else printf "%.4f\n", (a[NR/2]+a[NR/2+1])/2 }'; }
maxof()  { print -l -- "$@" | grep -E '^[0-9.]+$' | sort -g | tail -1; }

cleanup() {
  [[ -n $SAMPLER_PID ]] && kill $SAMPLER_PID 2>/dev/null
  (( POWER_ON )) && sudo -n pkill -x powermetrics 2>/dev/null
  [[ -n $SUDO_KEEP ]] && kill $SUDO_KEEP 2>/dev/null
  [[ -x $LMS ]] && "$LMS" unload --all >/dev/null 2>&1
  rm -rf "$TMP"
}
trap 'print; say "Stopped early."; cleanup; exit 130' INT TERM

# ---------- Mac info ----------
gather_info() {
  local hw=$(system_profiler SPHardwareDataType 2>/dev/null)
  MAC_NAME=$(scutil --get ComputerName 2>/dev/null)
  LABEL=${LABEL:-$MAC_NAME}
  MODEL_NAME=$(print -r -- "$hw" | awk -F': ' '/Model Name/{print $2; exit}')
  MODEL_ID=$(print -r -- "$hw" | awk -F': ' '/Model Identifier/{print $2; exit}')
  CHIP=$(print -r -- "$hw" | awk -F': ' '/Chip/{print $2; exit}')
  CPU_CORES=$(print -r -- "$hw" | awk -F': ' '/Total Number of Cores/{print $2; exit}')
  GPU_CORES=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Total Number of Cores/{print $2; exit}')
  RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  GPU_LIMIT_MB=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null)
  MACOS="macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  LMS_APP=$(defaults read "/Applications/LM Studio.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
  LMS_CLI=$("$LMS" version 2>/dev/null | grep -v '^\s*$' | tail -1)
  LMS_RUNTIMES=$("$LMS" runtime ls 2>/dev/null | grep -iE 'mlx|llama' | sed 's/^ *//' | tr '\n' ';' | sed 's/;$//')
  POWER_SRC=$(pmset -g batt 2>/dev/null | head -1 | sed -E "s/.*'(.*)'.*/\1/")
  LPM=$(pmset -g 2>/dev/null | awk '/lowpowermode/{print $2}')
  PAGE=$(vm_stat | awk '/page size of/{for(i=1;i<=NF;i++) if($i=="of"){print $(i+1); exit}}')
  [[ -z $PAGE ]] && PAGE=16384
}

print_info() {
  say "Mac:        $LABEL  ($MODEL_NAME, $MODEL_ID)"
  say "Chip:       $CHIP   CPU cores: ${CPU_CORES:--}   GPU cores: ${GPU_CORES:--}"
  local lim="macOS default"; [[ -n $GPU_LIMIT_MB && $GPU_LIMIT_MB != 0 ]] && lim="${GPU_LIMIT_MB} MB (changed from default!)"
  say "Memory:     ${RAM_GB} GB   GPU memory limit: $lim"
  say "OS:         $MACOS"
  say "LM Studio:  app ${LMS_APP:-?}   lms: ${LMS_CLI:-?}"
  [[ -n $LMS_RUNTIMES ]] && say "Runtimes:   $LMS_RUNTIMES"
  say "Power:      ${POWER_SRC:-?}   Low Power Mode: ${LPM:-?}"
  say "Settings:   temp $TEMP, $RUNS runs per prompt (median), fresh model load + new chat every run, cooldown ${COOLDOWN}s"
}

preflight() {
  local problems=0
  if [[ $POWER_SRC == *Battery* ]]; then warn "Running on battery. Plug in for fair results."; problems=1; fi
  if [[ $LPM == 1 ]]; then warn "Low Power Mode is ON. Turn it off in System Settings > Battery."; problems=1; fi
  [[ -n $GPU_LIMIT_MB && $GPU_LIMIT_MB != 0 ]] && { warn "GPU memory limit was changed (iogpu.wired_limit_mb=$GPU_LIMIT_MB). Results won't match a stock Mac."; problems=1; }
  local apps=$(osascript -e 'tell application "System Events" to get name of (processes where background only is false)' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ *//' | grep -vE '^(Finder|Terminal|iTerm2|LM Studio|Ghostty|Warp)$' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  [[ -n $apps ]] && warn "Other apps open: $apps  (close them for clean memory and power numbers)"
  if (( problems )); then say "  Continuing in 15 seconds. Ctrl-C to stop."; sleep 15; fi
}

# ---------- Memory, swap, power, heat ----------
mem_used() {  # GB, close to Activity Monitor "Memory Used" (app + wired + compressed)
  vm_stat | awk -v ps=$PAGE '/^Anonymous pages/{a=$NF} /^Pages purgeable/{p=$NF}
    /^Pages wired down/{w=$NF} /^Pages occupied by compressor/{c=$NF}
    END{printf "%.2f", (a-p+w+c)*ps/1073741824}'
}
swap_used() { # GB
  sysctl -n vm.swapusage | awk '{for(i=1;i<=NF;i++) if($i=="used"){v=$(i+2); u=substr(v,length(v),1); n=v+0;
    if(u=="G")n*=1024; if(u=="K")n/=1024; printf "%.2f", n/1024; exit}}'
}
pressure_level() { sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || print 1; }
pressure_name() { case $1 in 4) print Critical;; 2) print Warning;; *) print Normal;; esac; }

start_sampler() {
  : > "$TMP/samples"
  { trap - INT TERM; while true; do print -r -- "$(mem_used) $(swap_used) $(pressure_level)" >> "$TMP/samples"; sleep 0.5; done } &
  SAMPLER_PID=$!
}
stop_sampler() {
  [[ -n $SAMPLER_PID ]] && { kill $SAMPLER_PID 2>/dev/null; wait $SAMPLER_PID 2>/dev/null; }
  SAMPLER_PID=""
  read PEAK_MEM PEAK_SWAP PEAK_PRESS < <(awk 'NR==1{m=$1;s=$2;p=$3} {if($1>m)m=$1; if($2>s)s=$2; if($3>p)p=$3}
    END{printf "%.2f %.2f %d\n", m+0, s+0, p+0}' "$TMP/samples")
}

# Watts come from powermetrics (needs the password). CPU + GPU + Neural Engine.
start_power() {
  AVG_W=""; ANE_W=""; THERM=""
  (( HAVE_SUDO && POWER == 1 )) || return
  sudo -n pkill -x powermetrics 2>/dev/null
  sudo -n powermetrics --samplers cpu_power,gpu_power,thermal -i 1000 > "$TMP/power" 2>/dev/null &
  POWER_ON=1
}
stop_power() {
  (( POWER_ON )) || return
  sudo -n pkill -x powermetrics 2>/dev/null; sleep 0.3; POWER_ON=0
  AVG_W=$(awk '/Combined Power/{for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/){s+=$i; n++; break}}
    END{if(n) printf "%.1f", s/n/1000}' "$TMP/power")
  ANE_W=$(awk '/^ANE Power/{for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/){s+=$i; n++; break}}
    END{if(n) printf "%.2f", s/n/1000}' "$TMP/power")
  THERM=$(awk -F': ' '/pressure level/{l=$2; r=(l~/Trapping|Sleeping/)?4:(l~/Heavy/)?3:(l~/Moderate/)?2:1; if(r>m){m=r; w=l}}
    END{print w}' "$TMP/power")
}

# ---------- LM Studio ----------
ensure_server() {
  [[ -x $LMS ]] || die "Can't find the lms tool. Open LM Studio once, then run: ~/.lmstudio/bin/lms bootstrap"
  if ! curl -sf -m 5 "${AUTH[@]}" "$API/api/v1/models" >/dev/null 2>&1; then
    print "Starting LM Studio server on port $PORT..."
    "$LMS" server start --port $PORT >/dev/null 2>&1
    local i
    for i in {1..30}; do
      curl -sf -m 3 "${AUTH[@]}" "$API/api/v1/models" >/dev/null 2>&1 && return 0
      sleep 2
    done
    die "LM Studio server didn't start. Open LM Studio > Developer and turn on the server, then rerun."
  fi
}

models_json() { curl -s -m 15 "${AUTH[@]}" "$API/api/v1/models"; }

resolve_model() { # $1=override  $2=pattern  -> LM Studio model key
  [[ -n $1 ]] && { print -r -- "$1"; return 0; }
  local key
  key=$("$LMS" ls --json 2>/dev/null | jq -r --arg p "$2" '
      (if type=="array" then . else (.models // .llms // []) end)
      | [ .[] | select((((.path // "") + " " + (.modelKey // .key // "")) | test($p; "i"))) ][0]
      | (.modelKey // .key) // empty' 2>/dev/null)
  if [[ -z $key ]]; then
    key=$(models_json | jq -r --arg p "$2" '
      [ .models[]? | select(.type=="llm")
        | ([.key, .display_name] + (.variants // [])) | map(select(. != null))
        | map(select(test($p; "i"))) | .[] ][0] // empty' 2>/dev/null)
  fi
  [[ -n $key ]] && print -r -- "$key"
}

model_meta() {
  models_json | jq -r --arg k "$1" '
    [ .models[]? | select(.key==$k or ((.variants // []) | index($k))) ][0]
    | if . == null then "?" else
      "\(.display_name) | \(.format // "?") | \(.quantization.name // "?") | \((.size_bytes // 0)/1e9*100|floor/100) GB" end' 2>/dev/null
}

reasoning_off_ok() {
  models_json | jq -e --arg k "$1" '
    [ .models[]? | select(.key==$k or ((.variants // []) | index($k))) ][0]
    | (.capabilities.reasoning.allowed_options // []) | index("off")' >/dev/null 2>&1
}

load_model() { # $1=key $2=context -> LOAD_S, INSTANCE, LOAD_ERR
  LOAD_S=""; INSTANCE=""; LOAD_ERR=""
  "$LMS" unload --all >/dev/null 2>&1
  sleep 2
  if (( COLD_NEXT )); then
    if (( HAVE_SUDO )) && sudo -n purge 2>/dev/null; then LOAD_NOTE="cold load (cache purged)"; else LOAD_NOTE="warm load"; fi
    COLD_NEXT=0
  fi
  jq -n --arg m "$1" --argjson c "$2" '{model:$m, context_length:$c, echo_load_config:true}' > "$TMP/load.json"
  local resp rc
  resp=$(curl -s -m $LOAD_TIMEOUT "${AUTH[@]}" -H 'Content-Type: application/json' -d @"$TMP/load.json" "$API/api/v1/models/load")
  rc=$?
  if (( rc == 28 )); then
    LOAD_ERR="load still going after ${LOAD_TIMEOUT}s"; "$LMS" unload --all >/dev/null 2>&1; return 1
  fi
  if [[ $(jq -r '.status // empty' <<<"$resp" 2>/dev/null) == loaded ]]; then
    LOAD_S=$(jq -r '.load_time_seconds // empty' <<<"$resp")
    INSTANCE=$(jq -r '.instance_id // empty' <<<"$resp"); [[ -z $INSTANCE ]] && INSTANCE=$1
    local got_ctx=$(jq -r '.load_config.context_length // empty' <<<"$resp")
    [[ -n $got_ctx && $got_ctx != $2 ]] && warn "Asked for ${2} context, LM Studio loaded ${got_ctx}"
    return 0
  fi
  LOAD_ERR=$(jq -r '(.error.message // .error // .message // .) | tostring' <<<"$resp" 2>/dev/null | head -c 300)
  [[ -z $LOAD_ERR ]] && LOAD_ERR="no response (curl exit $rc)"
  "$LMS" unload --all >/dev/null 2>&1
  return 1
}

# THINKING OFF FOR QWEN (Nov 20 2026): LM Studio's API ignores every "thinking off"
# switch for Qwen 3.5 / 3.8 (LM Studio bug tracker #1990). So for Qwen models the
# prompt goes to LM Studio's raw text endpoint (/api/v0/completions, same stats:
# tokens/s and time to first token) already written in Qwen's own chat format,
# ending with the empty think block that Qwen's template uses for thinking off:
#   <|im_start|>user ... <|im_end|> <|im_start|>assistant <think></think>
# Same words, same model, no thinking. QWEN_THINK=1 puts it back to the old way.
QWEN_THINK=${QWEN_THINK:-0}
is_qwen() { [[ ${(L)1} == *qwen* ]] && (( ! QWEN_THINK )); }

make_payload() { # out model file question reasoning maxtokens
  if is_qwen "$2"; then
    jq -n --arg m "$2" --rawfile f "$3" --arg q "$4" --argjson mx "$6" --argjson t "$TEMP" '
      (if $f == "" then $q elif $q == "" then $f else ($f | rtrimstr("\n")) + "\n" + $q end) as $in
      | { model: $m,
          prompt: ("<|im_start|>user\n" + $in + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"),
          max_tokens: $mx, temperature: $t, stream: false,
          stop: ["<|im_end|>", "<|endoftext|>"] }' > "$1"
    return
  fi
  jq -n --arg m "$2" --rawfile f "$3" --arg q "$4" --arg r "$5" --argjson mx "$6" --argjson t "$TEMP" '
    { model: $m,
      input: (if $f == "" then $q elif $q == "" then $f else ($f | rtrimstr("\n")) + "\n" + $q end),
      store: false, temperature: $t, max_output_tokens: $mx }
    + (if $r == "" then {} else {reasoning: $r} end)' > "$1"
}
endpoint_for() { jq -e 'has("prompt")' "$1" >/dev/null 2>&1 && print "$API/api/v0/completions" || print "$API/api/v1/chat"; }

parse_resp() { # $1=response file $2=curl rc $3=timeout -> R_* vars
  R_TTFT=""; R_TPS=""; R_IN=""; R_OUT=""; R_REASON_TOK=""; R_ERR=""
  if (( $2 == 28 )); then R_STATUS=TIMEOUT; R_ERR="still running after ${3}s"; return 1; fi
  if jq -e '.stats.time_to_first_token' "$1" >/dev/null 2>&1; then   # /api/v0/completions (Qwen, thinking off)
    R_STATUS=OK
    R_TTFT=$(jq -r '.stats.time_to_first_token // empty' "$1")
    R_TPS=$(jq -r '.stats.tokens_per_second // empty' "$1")
    R_IN=$(jq -r '.usage.prompt_tokens // empty' "$1")
    R_OUT=$(jq -r '.usage.completion_tokens // empty' "$1")
    # if the model still wrote a think block, count it as thinking (flagged on the card)
    R_REASON_TOK=$(jq -r '.choices[0].text // "" | if test("</think>") then "yes" else "0" end' "$1")
    return 0
  fi
  if jq -e '.stats' "$1" >/dev/null 2>&1; then
    R_STATUS=OK
    R_TTFT=$(jq -r '.stats.time_to_first_token_seconds // empty' "$1")
    R_TPS=$(jq -r '.stats.tokens_per_second // empty' "$1")
    R_IN=$(jq -r '.stats.input_tokens // empty' "$1")
    R_OUT=$(jq -r '.stats.total_output_tokens // empty' "$1")
    R_REASON_TOK=$(jq -r '.stats.reasoning_output_tokens // 0' "$1")
    return 0
  fi
  R_STATUS=ERROR
  R_ERR=$(jq -r '(.error.message // .error // .) | tostring' "$1" 2>/dev/null | head -c 300)
  [[ -z $R_ERR ]] && R_ERR="no response (curl exit $2)"
  return 1
}

chat() { # $1=payload $2=timeout $3=quiet
  local tick="" rc
  if [[ -z $3 ]]; then
    { trap - INT TERM; local n=0; while sleep 1; do (( ++n % 15 == 0 )) && printf "\r        running... %ds " $n; done } &
    tick=$!
  fi
  curl -s -m $2 "${AUTH[@]}" -H 'Content-Type: application/json' -d @"$1" "$(endpoint_for "$1")" -o "$TMP/resp.json"
  rc=$?
  [[ -n $tick ]] && { kill $tick 2>/dev/null; wait $tick 2>/dev/null; printf "\r\033[K"; }
  parse_resp "$TMP/resp.json" $rc $2
}

# ---------- One run: fresh load, warm-up, measured prompt ----------
run_once() { # key ctx file question reasoning maxtok -> R_*, RUN_ST, RUN_NOTE, PEAK_*, SWAP_ADD, AVG_W, THERM
  local key=$1 ctx=$2 file=$3 q=$4 reason=$5 mx=$6 base_swap
  RUN_NOTE=""; LOAD_NOTE=""; AVG_W=""; THERM=""
  base_swap=$(swap_used); BASE_MEM=$(mem_used)
  start_sampler
  if ! load_model "$key" "$ctx"; then
    stop_sampler; RUN_ST="WON'T LOAD"; RUN_NOTE=$LOAD_ERR
    R_TTFT=""; R_TPS=""; R_IN=""; R_OUT=""
  else
    make_payload "$TMP/warm.json" "$INSTANCE" /dev/null "Reply with the word OK." "$reason" 8
    if ! chat "$TMP/warm.json" $WARM_TIMEOUT quiet && [[ $R_STATUS == TIMEOUT ]]; then
      stop_sampler; RUN_ST="SWAPS"; RUN_NOTE="warm-up alone took over ${WARM_TIMEOUT}s"
      R_TTFT=""; R_TPS=""; R_IN=""; R_OUT=""
    else
      make_payload "$TMP/prompt.json" "$INSTANCE" "$file" "$q" "$reason" "$mx"
      start_power
      chat "$TMP/prompt.json" $GEN_TIMEOUT
      stop_power
      stop_sampler
      case $R_STATUS in
        OK)      RUN_ST=OK ;;
        TIMEOUT) RUN_ST="SWAPS"; RUN_NOTE=$R_ERR ;;
        *)       RUN_ST=ERROR; RUN_NOTE=$R_ERR ;;
      esac
      [[ -n $R_OUT && $R_OUT == $mx ]] && RUN_NOTE="${RUN_NOTE:+$RUN_NOTE; }hit ${mx}-token cap"
      [[ -n $R_REASON_TOK && $R_REASON_TOK != 0 ]] && RUN_NOTE="${RUN_NOTE:+$RUN_NOTE; }WARNING thinking was on (${R_REASON_TOK} reasoning tokens)"
    fi
  fi
  "$LMS" unload --all >/dev/null 2>&1
  SWAP_ADD=$(awk -v a=$PEAK_SWAP -v b=$base_swap 'BEGIN{d=a-b; if(d<0)d=0; printf "%.2f", d}')
  if [[ $RUN_ST == OK ]] && { awk -v d=$SWAP_ADD -v f=$SWAP_FLAG_GB 'BEGIN{exit !(d>f)}' || (( PEAK_PRESS >= 4 )); }; then
    RUN_ST="SWAPS"; RUN_NOTE="${RUN_NOTE:+$RUN_NOTE; }finished but swapped ${SWAP_ADD} GB"
  fi
  [[ -n $LOAD_NOTE ]] && RUN_NOTE="${RUN_NOTE:+$RUN_NOTE; }$LOAD_NOTE"
  R_TOTAL=""
  [[ -n $R_TPS && -n $R_OUT && -n $R_TTFT ]] && R_TOTAL=$(awk -v t=$R_TTFT -v o=$R_OUT -v s=$R_TPS 'BEGIN{ if(s>0) printf "%.2f", t + o/s }')
}

# ---------- One prompt, RUNS times, median kept ----------
# run_prompt <test> <label> <key> <context> <file or /dev/null> <question> <reasoning> <max tokens>
run_prompt() {
  local test=$1 label=$2 key=$3 ctx=$4 file=$5 q=$6 reason=$7 mx=$8
  local k="$test:$label" i st="" first_load="" w_txt r
  local ttfts=() tpss=() outs=() ins=() mems=() swaps=() watts=() totals=() therm="" therm_r=0
  say ""
  say "  > $label   (context $ctx, $RUNS runs)"
  for (( i = 1; i <= RUNS; i++ )); do
    run_once "$key" "$ctx" "$file" "$q" "$reason" "$mx"
    (( i == 1 )) && first_load=$LOAD_S
    w_txt=""; [[ -n $AVG_W ]] && w_txt="  ${AVG_W} W"
    say "      run $i: $RUN_ST  TTFT $(fmt $R_TTFT)s  $(fmt $R_TPS) tok/s  ${R_OUT:--} tokens  peak ${PEAK_MEM} GB  swap +${SWAP_ADD} GB${w_txt}${THERM:+  heat $THERM}"
    [[ -n $RUN_NOTE ]] && say "             $RUN_NOTE"
    print -r -- "$LABEL,$CHIP,$RAM_GB,$test,\"$key\",$label,$ctx,$i,$RUN_ST,$R_TTFT,$R_TPS,$R_IN,$R_OUT,$R_TOTAL,$LOAD_S,$BASE_MEM,$PEAK_MEM,$SWAP_ADD,$(pressure_name $PEAK_PRESS),$AVG_W,$THERM,\"${RUN_NOTE//\"/}\"" | tee -a "$CSV" >> "$ALL_CSV"
    mems+=($PEAK_MEM); swaps+=($SWAP_ADD)
    case $RUN_ST in
      "WON'T LOAD") st="WON'T LOAD"; break ;;
      SWAPS)        st="SWAPS" ;;
      OK)           [[ -z $st ]] && st=OK ;;
      ERROR)        [[ -z $st ]] && st=ERRORONLY ;;
    esac
    if [[ $RUN_ST == OK || $RUN_ST == SWAPS ]]; then
      [[ -n $R_TTFT ]] && ttfts+=($R_TTFT)
      [[ -n $R_TPS ]] && tpss+=($R_TPS)
      [[ -n $R_OUT ]] && outs+=($R_OUT)
      [[ -n $R_IN ]] && ins+=($R_IN)
      [[ -n $R_TOTAL ]] && totals+=($R_TOTAL)
      [[ -n $AVG_W ]] && watts+=($AVG_W)
      r=1; case $THERM in *Trapping*|*Sleeping*) r=4;; *Heavy*) r=3;; *Moderate*) r=2;; esac
      (( r > therm_r )) && { therm_r=$r; therm=$THERM; }
    fi
    # a run that timed out from swapping won't get better: don't repeat a 25-minute timeout
    [[ $RUN_ST == SWAPS && -z $R_TPS ]] && { say "      (stopping repeats: this one is swapping too hard)"; break; }
    (( i < RUNS )) && { say "      cooling down ${COOLDOWN}s..."; sleep $COOLDOWN; }
  done
  [[ $st == ERRORONLY ]] && st=ERROR

  local m_ttft=$(median $ttfts) m_tps=$(median $tpss) m_out=$(median $outs) m_in=$(median $ins)
  local m_w=$(median $watts); [[ -n $m_w ]] && m_w=$(printf "%.1f" $m_w)
  local m_total=$(median $totals) tpw=""
  [[ -n $m_w && -n $m_tps ]] && tpw=$(awk -v s=$m_tps -v w=$m_w 'BEGIN{ if(w>0) printf "%.2f", s/w }')
  RES_STATUS[$k]=$st; RES_TTFT[$k]=$m_ttft; RES_TPS[$k]=$m_tps; RES_OUT[$k]=${m_out%.*}; RES_IN[$k]=${m_in%.*}
  RES_PMEM[$k]=$(maxof $mems); RES_SWAP[$k]=$(maxof $swaps); RES_LOAD[$k]=$first_load
  RES_W[$k]=$m_w; RES_TPW[$k]=$tpw; RES_TOTAL[$k]=$m_total; RES_THERM[$k]=$therm
  say "      MEDIAN: $st  TTFT $(fmt $m_ttft)s  $(fmt $m_tps) tok/s  ${RES_OUT[$k]:--} tokens  peak ${RES_PMEM[$k]:--} GB  swap +${RES_SWAP[$k]:--} GB${m_w:+  ${m_w} W  $(fmt $tpw) tok/s per W}"

  [[ $st == "WON'T LOAD" ]] && return 2
  say "      cooling down ${COOLDOWN}s..."; sleep $COOLDOWN
  return 0
}

# ---------- Helpers ----------
find_file() { # $1 = file name (or start of it). Prints full path.
  local d f
  for d in "$PROMPT_DIR" "$HOME/Desktop" "$HOME/Downloads" /Volumes/*(N); do
    [[ $d == "/Volumes/Macintosh HD"* ]] && continue
    f=$(find "$d" -maxdepth 4 -type f -name "${1}*" ! -name '._*' 2>/dev/null | head -1)
    [[ -n $f ]] && { print -r -- "$f"; return 0; }
  done
  return 1
}
need_file() { local f; f=$(find_file "$1") && { print -r -- "$f"; return 0; }; warn "Can't find \"$1\". Put it next to this script."; return 1; }

test_card() { # $1 test name, $2 key (or ""), $3 details
  say "  ---- TEST CARD (for the video) ----"
  if [[ -n $2 ]]; then say "  $1 | $(model_meta "$2") | key $2"; else say "  $1"; fi
  say "  $3"
  if [[ -n $2 ]]; then say "  $CHIP, ${RAM_GB}GB, $MACOS, LM Studio ${LMS_APP:-?}, temp $TEMP, median of $RUNS runs, fresh load each run"
  else say "  $CHIP, ${RAM_GB}GB, $MACOS"; fi
  say "  ----------------------------------"
}

agg_peak() { # max of RES_PMEM / RES_SWAP for one test
  local arr=$1 prefix=$2 k vals=()
  for k in ${(Pk)arr}; do [[ $k == ${prefix}:* ]] && vals+=($(getv $arr "$k")); done
  local m=$(maxof $vals); print -r -- "${m:--}"
}

cell() { # sheet cell: number, or status text if it didn't finish
  local k=$1 v=$(getv $2 "$1")
  case ${RES_STATUS[$k]} in
    OK)           fmt $v ;;
    SWAPS)        [[ -n $v ]] && print -n "$(fmt $v) (Swaps)" || print -n "Swaps" ;;
    "WON'T LOAD") print -n "Won't load" ;;
    "")           print -n "-" ;;
    *)            print -n "Error" ;;
  esac
}
prefill_cell() { print -n "$(cell "$1:Transcript A" RES_TTFT) / $(cell "$1:Transcript B" RES_TTFT) / $(cell "$1:Transcript C" RES_TTFT)"; }
power_line() { # power summary for one test
  local t=$1 k parts=()
  for k in ${(ko)RES_W}; do
    [[ $k == ${t}:* && -n ${RES_W[$k]} ]] || continue
    parts+=("${k#*:} ${RES_W[$k]} W ($(fmt ${RES_TPW[$k]}) tok/s per W${RES_THERM[$k]:+, heat ${RES_THERM[$k]}})")
  done
  (( ${#parts} )) && EXTRA_LINES+=("$t power: ${(j: | :)parts}")
}

# ---------- Tests ----------
test_gemma() {
  say ""; say "=== TEST 1: Gemma 3 4B ==="
  local key=$(resolve_model "$GEMMA_MODEL" "$GEMMA_PATTERN")
  [[ -z $key ]] && { warn "Gemma 3 4B isn't downloaded on this Mac. Skipping."; return; }
  test_card "Gemma 3 4B" "$key" "Roman 50-paragraph essay + Apple environment summary, context $GEMMA_CTX, max $GEMMA_MAX tokens"
  run_prompt gemma Roman "$key" $GEMMA_CTX /dev/null "$ROMAN50" "" $GEMMA_MAX
  local apple; if apple=$(need_file "$APPLE_FILE"); then
    run_prompt gemma Apple "$key" $GEMMA_CTX "$apple" "" "" $GEMMA_MAX
  fi
  local t=$'\t'
  SHEET_LINES+=("Main Results  AI-AK (Roman TTFT, tok/s, tokens):${t}$(cell gemma:Roman RES_TTFT)${t}$(cell gemma:Roman RES_TPS)${t}${RES_OUT[gemma:Roman]:--}")
  SHEET_LINES+=("Main Results  AM-AO (Apple TTFT, tok/s, tokens):${t}$(cell gemma:Apple RES_TTFT)${t}$(cell gemma:Apple RES_TPS)${t}${RES_OUT[gemma:Apple]:--}")
  power_line gemma
}

# Transcripts A/B at 8K, Roman 10 at 8K, transcript C at 32K
qwen_suite() { # $1 test id  $2 key
  local test=$1 key=$2 reason="off" fa fb fc first=1
  if ! reasoning_off_ok "$key"; then
    is_qwen "$key" || warn "LM Studio doesn't list a thinking OFF option for this model. Running its default and flagging thinking tokens."
    reason=""
  fi
  fa=$(need_file "$TRANSCRIPT_A"); fb=$(need_file "$TRANSCRIPT_B"); fc=$(need_file "$TRANSCRIPT_C")
  COLD_NEXT=1
  if [[ -n $fa ]]; then run_prompt $test "Transcript A" "$key" $QWEN_CTX_AB "$fa" "$SUMMARY_Q" "$reason" $QWEN_MAX
    (( $? == 2 )) && { say "      Won't load at 8K. Skipping the rest of this test."
      [[ ${(L)LOAD_ERR} == *"insufficient system resources"* || ${(L)LOAD_ERR} == *guardrail* ]] && {
        say "      That was LM Studio's safety limit (model loading guardrails), not the Mac running out."
        say "      Fix: LM Studio Settings > Model loading guardrails > Relaxed (or Off if Relaxed still blocks it)."
        say "      Run this test again, then set it back. Log both: Won't load at that setting, then the result."; }
      return 2; }
    LOAD_FIRST=${RES_LOAD[$test:Transcript A]}; first=0; fi
  if [[ -n $fb ]]; then run_prompt $test "Transcript B" "$key" $QWEN_CTX_AB "$fb" "$SUMMARY_Q" "$reason" $QWEN_MAX
    (( $? == 2 )) && return 2
    (( first )) && { LOAD_FIRST=${RES_LOAD[$test:Transcript B]}; first=0; }; fi
  run_prompt $test "Roman 10" "$key" $QWEN_CTX_AB /dev/null "$ROMAN10" "$reason" $QWEN_MAX
  (( $? == 2 )) && return 2
  (( first )) && LOAD_FIRST=${RES_LOAD[$test:Roman 10]}
  [[ -n $fc ]] && run_prompt $test "Transcript C" "$key" $QWEN_CTX_C "$fc" "$SUMMARY_Q" "$reason" $QWEN_MAX
  # generation speed with a full 23K-token transcript loaded vs the short Roman prompt
  [[ ${RES_STATUS[$test:Transcript C]} == OK && -n ${RES_TPS[$test:Roman 10]} ]] && \
    EXTRA_LINES+=("$test generation speed: short prompt $(fmt ${RES_TPS[$test:Roman 10]}) tok/s -> with full transcript C loaded $(fmt ${RES_TPS[$test:Transcript C]}) tok/s")
  return 0
}

QWEN_CARD="Thinking OFF (Qwen's own no-think format, sent raw to LM Studio). Transcript A/B at 8K context, C at 32K. Prompt: \"$SUMMARY_Q\" Plus Roman 10 paragraphs at 8K."

test_qwen9b() {
  say ""; say "=== TEST 2: Qwen 3.5 9B (MLX 4-bit) ==="
  local key=$(resolve_model "$QWEN9_MODEL" "$QWEN9_PATTERN")
  if [[ -z $key ]]; then
    key=$(resolve_model "" "$QWEN9_LOOSE")
    [[ -n $key ]] && warn "Exact MLX-4bit build not found by name. Using $key - check the size is about 5.95 GB."
  fi
  [[ -z $key ]] && { warn "Qwen 3.5 9B isn't downloaded on this Mac. Skipping."; return; }
  test_card "Qwen 3.5 9B" "$key" "$QWEN_CARD"
  qwen_suite qwen9b "$key"
  local t=$'\t'
  SHEET_LINES+=("New Tests  AX-BA (prefill A/B/C, tok/s, peak memory, swap):${t}$(prefill_cell qwen9b)${t}$(cell "qwen9b:Roman 10" RES_TPS)${t}$(agg_peak RES_PMEM qwen9b) GB${t}$(agg_peak RES_SWAP qwen9b) GB")
  local pw="-"; [[ -n ${RES_W[qwen9b:Roman 10]} ]] && pw="${RES_W[qwen9b:Roman 10]} W / $(fmt ${RES_TPW[qwen9b:Roman 10]})"
  SHEET_LINES+=("New Tests  BM-BN (9B watts / tok/s per W, tok/s with transcript C loaded):${t}${pw}${t}$(cell "qwen9b:Transcript C" RES_TPS)")
  power_line qwen9b
}

test_qwen27b() {
  say ""; say "=== TEST 3: Qwen3.8 27B (MLX 4-bit) - RAM wall ==="
  say "  (If LM Studio's model loading guardrails are on, a model that's too big is refused = Won't load."
  say "   Turn guardrails off in LM Studio settings if you want to see it try and swap instead.)"
  local key=$(resolve_model "$QWEN27_MODEL" "$QWEN27_PATTERN")
  if [[ -z $key ]]; then
    key=$(resolve_model "" "$QWEN27_LOOSE")
    [[ -n $key ]] && warn "Exact MLX-4bit build not found by name. Using $key - check the quant/size."
  fi
  [[ -z $key ]] && { warn "Qwen3.8 27B 4-bit isn't downloaded on this Mac. Skipping."; return; }
  test_card "Qwen3.8 27B 4-bit" "$key" "$QWEN_CARD"
  LOAD_FIRST=""
  qwen_suite qwen27b "$key"
  local loads="Loads" k
  for k in ${(k)RES_STATUS}; do [[ $k == qwen27b:* && ${RES_STATUS[$k]} == SWAPS ]] && loads="Swaps"; done
  [[ ${RES_STATUS[qwen27b:Transcript A]} == "WON'T LOAD" || ${RES_STATUS[qwen27b:Roman 10]} == "WON'T LOAD" ]] && loads="Won't load"
  local t=$'\t'
  SHEET_LINES+=("New Tests  AA-AD (loads?, peak memory, prefill A/B/C, tok/s):${t}${loads}${t}$(agg_peak RES_PMEM qwen27b) GB${t}$(prefill_cell qwen27b)${t}$(cell "qwen27b:Roman 10" RES_TPS)")
  SHEET_LINES+=("New Tests  AS (model load time):${t}$(fmt $LOAD_FIRST)s")
  power_line qwen27b
}

test_ladder() {
  say ""; say "=== BONUS: AI ladder - Qwen3.8 27B at 4 / 5 / 6 / 8-bit (Roman 10) ==="
  local b key parts=() reason
  for b in $LADDER_BITS; do
    local k="ladder:${b}-bit"
    if [[ $b == 4 && ${RES_STATUS[qwen27b:Roman 10]} == OK ]]; then
      say ""; say "  > 4-bit: already measured in Test 3 ($(fmt ${RES_TPS[qwen27b:Roman 10]}) tok/s), reusing it."
      RES_STATUS[$k]=OK; RES_TPS[$k]=${RES_TPS[qwen27b:Roman 10]}
    else
      key=$(resolve_model "${(P)${:-LADDER_${b}_MODEL}}" "qwen3\\.8-27b-mlx-${b}bit")
      if [[ -z $key ]]; then
        say ""; say "  > ${b}-bit: not downloaded on this Mac, skipping."
        parts+=("${b}-bit: not downloaded"); continue
      fi
      say "  ${b}-bit: $key | $(model_meta "$key")"
      reason="off"; reasoning_off_ok "$key" || reason=""
      run_prompt ladder "${b}-bit" "$key" $QWEN_CTX_AB /dev/null "$ROMAN10" "$reason" $QWEN_MAX
    fi
    parts+=("${b}-bit: $(cell $k RES_TPS)")
  done
  local t=$'\t'
  SHEET_LINES+=("New Tests  AU (AI ladder tok/s):${t}${(j: | :)parts}")
}

test_moe() {
  say ""; say "=== TEST 4: MoE model (30B-class, ~3B active) ==="
  local key=$(resolve_model "$MOE_MODEL" "$MOE_PATTERN")
  [[ -z $key ]] && { warn "No 30B-A3B MoE model downloaded (set MOE_MODEL= to its key). Skipping."; return; }
  test_card "MoE" "$key" "$QWEN_CARD"
  qwen_suite moe "$key"
  local t=$'\t' loads="Loads" k
  for k in ${(k)RES_STATUS}; do [[ $k == moe:* && ${RES_STATUS[$k]} == SWAPS ]] && loads="Swaps"; done
  [[ ${RES_STATUS[moe:Transcript A]} == "WON'T LOAD" || ${RES_STATUS[moe:Roman 10]} == "WON'T LOAD" ]] && loads="Won't load"
  SHEET_LINES+=("New Tests  BB-BE (MoE loads?, peak memory, prefill A/B/C, tok/s):${t}${loads}${t}$(agg_peak RES_PMEM moe) GB${t}$(prefill_cell moe)${t}$(cell "moe:Roman 10" RES_TPS)")
  power_line moe
}

test_coding() {
  say ""; say "=== TEST 5: Coding task (time to finish) ==="
  local keys=() names=() key
  key=$(resolve_model "${CODE_MODEL:-$QWEN9_MODEL}" "$QWEN9_PATTERN"); [[ -z $key ]] && key=$(resolve_model "" "$QWEN9_LOOSE")
  [[ -n $key ]] && { keys+=($key); names+=("9B"); }
  key=$(resolve_model "$MOE_MODEL" "$MOE_PATTERN"); [[ -n $key ]] && { keys+=($key); names+=("MoE"); }
  (( ${#keys} )) || { warn "Need Qwen 3.5 9B or a MoE model for the coding test. Skipping."; return; }
  local i reason
  for (( i = 1; i <= ${#keys}; i++ )); do
    test_card "Coding task (${names[$i]})" "${keys[$i]}" "Thinking OFF, context 8K, max $CODE_MAX tokens. Prompt: \"$CODE_PROMPT\""
    reason="off"; reasoning_off_ok "${keys[$i]}" || reason=""
    run_prompt coding "${names[$i]}" "${keys[$i]}" $QWEN_CTX_AB /dev/null "$CODE_PROMPT" "$reason" $CODE_MAX
  done
  local t=$'\t' c9="-" cm="-"
  [[ -n ${RES_STATUS[coding:9B]} ]] && c9="$(fmt ${RES_TOTAL[coding:9B]})s / $(cell coding:9B RES_TPS)"
  [[ -n ${RES_STATUS[coding:MoE]} ]] && cm="$(fmt ${RES_TOTAL[coding:MoE]})s / $(cell coding:MoE RES_TPS)"
  SHEET_LINES+=("New Tests  BF-BG (coding 9B, coding MoE: time to finish / tok/s):${t}${c9}${t}${cm}")
  power_line coding
}

test_agents() {
  say ""; say "=== TEST 6: Several agents at once (1 request vs $AGENTS at the same time) ==="
  local key=$(resolve_model "$QWEN9_MODEL" "$QWEN9_PATTERN"); [[ -z $key ]] && key=$(resolve_model "" "$QWEN9_LOOSE")
  [[ -z $key ]] && { warn "Qwen 3.5 9B isn't downloaded. Skipping."; return; }
  test_card "Agents" "$key" "Thinking OFF, context 8K. Same Roman 10 prompt sent once, then $AGENTS copies at the same time. Total tok/s = all tokens / wall time."
  local reason="off"; reasoning_off_ok "$key" || reason=""
  run_prompt agents "1 at a time" "$key" $QWEN_CTX_AB /dev/null "$ROMAN10" "$reason" $QWEN_MAX
  (( $? == 2 )) && return
  local single=${RES_TPS[agents:1 at a time]} r aggs=() pers=() mems=() t0 a pids tot tps_list n wall agg per
  say ""; say "  > $AGENTS at the same time   ($RUNS runs)"
  for (( r = 1; r <= RUNS; r++ )); do
    start_sampler
    if ! load_model "$key" $QWEN_CTX_AB; then stop_sampler; warn "Load failed: $LOAD_ERR"; return; fi
    make_payload "$TMP/warm.json" "$INSTANCE" /dev/null "Reply with the word OK." "$reason" 8
    chat "$TMP/warm.json" $WARM_TIMEOUT quiet
    make_payload "$TMP/agent.json" "$INSTANCE" /dev/null "$ROMAN10" "$reason" $QWEN_MAX
    start_power
    t0=$EPOCHREALTIME; pids=()
    for (( a = 1; a <= AGENTS; a++ )); do
      curl -s -m $GEN_TIMEOUT "${AUTH[@]}" -H 'Content-Type: application/json' -d @"$TMP/agent.json" "$(endpoint_for "$TMP/agent.json")" -o "$TMP/agent$a.json" &
      pids+=($!)
    done
    wait $pids
    wall=$(( EPOCHREALTIME - t0 ))
    stop_power; stop_sampler
    "$LMS" unload --all >/dev/null 2>&1
    tot=0; tps_list=()
    for (( a = 1; a <= AGENTS; a++ )); do
      n=$(jq -r '.stats.total_output_tokens // .usage.completion_tokens // 0' "$TMP/agent$a.json" 2>/dev/null); tot=$(( tot + ${n:-0} ))
      tps_list+=($(jq -r '.stats.tokens_per_second // empty' "$TMP/agent$a.json" 2>/dev/null))
    done
    agg=$(awk -v t=$tot -v w=$wall 'BEGIN{printf "%.2f", t/w}'); per=$(median $tps_list)
    aggs+=($agg); [[ -n $per ]] && pers+=($per); mems+=($PEAK_MEM)
    say "      run $r: ${tot} tokens in $(printf %.1f $wall)s = ${agg} tok/s total, $(fmt $per) tok/s each  peak ${PEAK_MEM} GB${AVG_W:+  ${AVG_W} W}"
    print -r -- "$LABEL,$CHIP,$RAM_GB,agents,\"$key\",$AGENTS at once,$QWEN_CTX_AB,$r,OK,,$agg,,$tot,$wall,,,$PEAK_MEM,,,$AVG_W,$THERM,\"total tok/s; each $per\"" | tee -a "$CSV" >> "$ALL_CSV"
    (( r < RUNS )) && sleep $COOLDOWN
  done
  local m_agg=$(median $aggs) m_per=$(median $pers)
  say "      MEDIAN: $(fmt $m_agg) tok/s total with $AGENTS at once vs $(fmt $single) with 1 ($(awk -v a=$m_agg -v s=$single 'BEGIN{ if(s>0) printf "%.1fx", a/s }'))"
  local t=$'\t'
  SHEET_LINES+=("New Tests  BH-BI (agents: 1 request tok/s, $AGENTS at once total tok/s):${t}$(fmt $single)${t}$(fmt $m_agg)")
  EXTRA_LINES+=("Agents: $AGENTS at once = $(fmt $m_per) tok/s each, peak $(maxof $mems) GB")
  sleep $COOLDOWN
}

find_dir() { # $1 = folder name. Prints full path.
  local d f
  for d in "$SCRIPT_DIR" "$PROMPT_DIR" "$HOME/Desktop" "$HOME/Downloads" /Volumes/*(N); do
    [[ $d == "/Volumes/Macintosh HD"* ]] && continue
    f=$(find "$d" -maxdepth 3 -type d -name "$1" 2>/dev/null | head -1)
    [[ -n $f ]] && { print -r -- "$f"; return 0; }
  done
  return 1
}

# One whisper.cpp mode, RUNS times. $1 label  $2 binary  $3 model  $4 audio  $5 audio seconds  $6 key
whisper_mode() {
  local label=$1 bin=$2 model=$3 audio=$4 dur=$5 k="whisper:$6" r secs=() ws=() anes=() t0 rc wall rt
  say ""; say "  > $label   ($RUNS runs)"
  if [[ $6 == coreml ]]; then
    say "      warm-up (not timed): first Core ML run on a Mac compiles the model for the Neural Engine..."
    "$bin" -m "$model" -f "$WHISPER_DIR/samples/jfk.wav" -nt >/dev/null 2>"$TMP/whisper.log"
    if ! grep -q "Core ML model loaded" "$TMP/whisper.log"; then
      warn "Core ML model did NOT load, so this wouldn't be a Neural Engine run. Skipping. ($(grep -i coreml "$TMP/whisper.log" | tail -1))"
      RES_STATUS[$k]=ERROR; return
    fi
  fi
  for (( r = 1; r <= RUNS; r++ )); do
    start_sampler; start_power
    t0=$EPOCHREALTIME
    "$bin" -m "$model" -f "$audio" -t $WHISPER_THREADS -otxt -of "$TMP/whisper" >/dev/null 2>"$TMP/whisper.log"
    rc=$?; wall=$(( EPOCHREALTIME - t0 ))
    stop_power; stop_sampler
    if (( rc != 0 )); then warn "whisper.cpp failed: $(tail -2 "$TMP/whisper.log")"; RES_STATUS[$k]=ERROR; return; fi
    secs+=($wall); [[ -n $AVG_W ]] && ws+=($AVG_W); [[ -n $ANE_W ]] && anes+=($ANE_W)
    rt=""; [[ -n $dur ]] && rt=$(awk -v d=$dur -v w=$wall 'BEGIN{printf "%.1fx realtime", d/w}')
    say "      run $r: $(printf %.1f $wall)s  $rt  peak ${PEAK_MEM} GB${AVG_W:+  ${AVG_W} W}${ANE_W:+  (Neural Engine ${ANE_W} W)}"
    print -r -- "$LABEL,$CHIP,$RAM_GB,whisper,\"${model:t}\",$label,,$r,OK,,,,,$wall,,,$PEAK_MEM,,,$AVG_W,$THERM,\"$rt; ANE ${ANE_W:-?} W\"" | tee -a "$CSV" >> "$ALL_CSV"
    (( r < RUNS )) && sleep $COOLDOWN
  done
  local m=$(median $secs) mw=$(median $ws) ma=$(median $anes)
  [[ -n $mw ]] && mw=$(printf "%.1f" $mw); [[ -n $ma ]] && ma=$(printf "%.2f" $ma)
  rt=""; [[ -n $dur ]] && rt=$(awk -v d=$dur -v w=$m 'BEGIN{printf "%.1fx", d/w}')
  RES_STATUS[$k]=OK; RES_TOTAL[$k]=$m; RES_W[$k]=$mw; RES_TPS[$k]=$rt; RES_IN[$k]=$ma
  say "      MEDIAN: $(printf %.1f $m)s  ${rt:+$rt realtime}${mw:+  ${mw} W}${ma:+  (Neural Engine $ma W)}"
  sleep $COOLDOWN
}

test_whisper() {
  say ""; say "=== TEST 7: Whisper transcription - GPU (Metal) vs Neural Engine (Core ML) ==="
  WHISPER_DIR=$(find_dir whisper-test)
  if [[ -z $WHISPER_DIR || ! -x $WHISPER_DIR/bin/whisper-cli-metal ]]; then
    warn "No whisper-test folder found. Run whisper-coreml-setup.sh once (on any Mac, saved to the LaCie). Skipping."; return
  fi
  xattr -dr com.apple.quarantine "$WHISPER_DIR" 2>/dev/null   # copied/AirDropped kits get blocked otherwise
  local model="$WHISPER_DIR/models/ggml-large-v3-turbo.bin" audio
  [[ -s $model ]] || { warn "Model missing in $WHISPER_DIR/models. Rerun whisper-coreml-setup.sh."; return; }
  audio=$(need_file "$WHISPER_AUDIO") || return
  local dur=$(afinfo "$audio" 2>/dev/null | awk '/estimated duration/{print $3; exit}')
  WHISPER_THREADS=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null); [[ -z $WHISPER_THREADS ]] && WHISPER_THREADS=4
  test_card "Whisper" "" "$(head -1 "$WHISPER_DIR/BUILD-INFO.txt" 2>/dev/null), large-v3-turbo, audio ${audio:t} ($(printf %.0f ${dur:-0})s), $WHISPER_THREADS threads, median of $RUNS. Same code, two builds: GPU (Metal) and Core ML (encoder on the Neural Engine)."
  "$LMS" unload --all >/dev/null 2>&1
  (( HAVE_SUDO && POWER == 1 )) || warn "No password given, so no watts. The Neural Engine watts are the proof it was used."
  whisper_mode "GPU (Metal)" "$WHISPER_DIR/bin/whisper-cli-metal" "$model" "$audio" "$dur" metal
  if [[ -x $WHISPER_DIR/bin/whisper-cli-coreml && -d ${model%.bin}-encoder.mlmodelc ]]; then
    whisper_mode "Neural Engine (Core ML)" "$WHISPER_DIR/bin/whisper-cli-coreml" "$model" "$audio" "$dur" coreml
  else
    warn "Core ML build or encoder missing in $WHISPER_DIR. Rerun whisper-coreml-setup.sh."
  fi
  local t=$'\t' cm cc
  cm=$( [[ ${RES_STATUS[whisper:metal]} == OK ]] && print -n "$(printf %.1f ${RES_TOTAL[whisper:metal]})s / ${RES_TPS[whisper:metal]}" || print -n "-")
  cc=$( [[ ${RES_STATUS[whisper:coreml]} == OK ]] && print -n "$(printf %.1f ${RES_TOTAL[whisper:coreml]})s / ${RES_TPS[whisper:coreml]} / ANE ${RES_IN[whisper:coreml]:-?} W" || print -n "-")
  SHEET_LINES+=("New Tests  BJ-BK (Whisper GPU, Whisper Neural Engine):${t}${cm}${t}${cc}")
}

test_llamabench() {
  say ""; say "=== CHECK: llama-bench (standard llama.cpp pp512 / tg128) ==="
  command -v llama-bench >/dev/null || { warn "llama.cpp isn't installed. Run: brew install llama.cpp   Skipping."; return; }
  local gguf=${LLAMA_GGUF:-$(find "$HOME/.lmstudio/models" -maxdepth 4 -iname '*gemma-3-4b*q4_k_m*.gguf' 2>/dev/null | head -1)}
  [[ -z $gguf ]] && { warn "No Gemma 3 4B Q4_K_M GGUF in LM Studio's models folder (download that build, or set LLAMA_GGUF=). Skipping."; return; }
  "$LMS" unload --all >/dev/null 2>&1
  test_card "llama-bench" "" "llama.cpp $(brew list --versions llama.cpp 2>/dev/null), ${gguf:t}, -p 512 -n 128 -r $RUNS, all layers on GPU"
  start_power
  llama-bench -m "$gguf" -p 512 -n 128 -r $RUNS -ngl 99 -o json > "$TMP/lb.json" 2>"$TMP/lb.log"
  local rc=$?; stop_power
  (( rc == 0 )) || { warn "llama-bench failed: $(tail -2 "$TMP/lb.log")"; return; }
  local pp=$(jq -r '.[] | select(.n_prompt > 0 and .n_gen == 0) | .avg_ts' "$TMP/lb.json" | head -1)
  local tg=$(jq -r '.[] | select(.n_gen > 0 and .n_prompt == 0) | .avg_ts' "$TMP/lb.json" | head -1)
  local build=$(jq -r '.[0].build_commit // empty' "$TMP/lb.json")
  say "      pp512: $(fmt $pp) tok/s   tg128: $(fmt $tg) tok/s   (llama.cpp build ${build:-?})${AVG_W:+  ${AVG_W} W}"
  print -r -- "$LABEL,$CHIP,$RAM_GB,llamabench,\"${gguf:t}\",pp512/tg128,,,OK,,$tg,512,128,,,,,,,$AVG_W,$THERM,\"pp512 $pp\"" | tee -a "$CSV" >> "$ALL_CSV"
  SHEET_LINES+=("New Tests  BL (llama-bench pp512 / tg128):"$'\t'"$(fmt $pp) / $(fmt $tg)")
  EXTRA_LINES+=("llama-bench llama.cpp build: ${build:-?}")
}

# ---------- Main ----------
CMD=${1:-help}
case $CMD in
  info|gemma|qwen9b|qwen27b|ladder|moe|coding|agents|whisper|llamabench|core|all) ;;
  *) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[[ $RUNS == <1-> ]] || { print "RUNS must be 1 or more"; exit 1; }

for tool in curl jq awk; do command -v $tool >/dev/null || die "$tool is missing"; done
gather_info
mkdir -p "$RESULTS_DIR" "$ALL_DIR" || die "Can't create $RESULTS_DIR"
STAMP=$(date +%Y-%m-%d_%H%M)
BASE="$RESULTS_DIR/${LABEL//\//-} - $CMD - $STAMP"
REPORT="$BASE.txt"; CSV="$BASE.csv"; ALL_CSV="$ALL_DIR/All Macs lmstudio.csv"
HEADER="mac,chip,ram_gb,test,model,prompt,context,run,status,ttft_s,tok_s,input_tokens,output_tokens,total_s,load_s,mem_before_gb,peak_mem_gb,swap_added_gb,peak_pressure,avg_watts,heat,notes"
: > "$REPORT"
print -r -- "$HEADER" > "$CSV"
[[ -s $ALL_CSV ]] || print -r -- "$HEADER" > "$ALL_CSV"

say "LM Studio test suite v2 - $CMD - $(date '+%b %d, %Y %I:%M %p')"
say "-----------------------------------------------------------------"
print_info

if [[ $CMD == info ]]; then
  ensure_server
  say ""; say "Test files:"
  for f in "$APPLE_FILE" "$TRANSCRIPT_A" "$TRANSCRIPT_B" "$TRANSCRIPT_C" "$WHISPER_AUDIO" "$WHISPER_MODEL"; do
    p=$(find_file "$f") && say "  ok       $p" || say "  MISSING  $f"
  done
  say ""; say "Tools:"
  command -v whisper-cli >/dev/null && say "  ok       whisper-cli" || say "  missing  whisper-cli (whisper test only: brew install whisper-cpp)"
  command -v llama-bench >/dev/null && say "  ok       llama-bench" || say "  missing  llama-bench (llamabench check only: brew install llama.cpp)"
  say ""; say "Models found:"
  for pair in "Gemma 3 4B|$GEMMA_MODEL|$GEMMA_PATTERN" "Qwen 3.5 9B|$QWEN9_MODEL|$QWEN9_PATTERN" "Qwen3.8 27B 4-bit|$QWEN27_MODEL|$QWEN27_PATTERN" \
              "27B 5-bit||qwen3\\.8-27b-mlx-5bit" "27B 6-bit||qwen3\\.8-27b-mlx-6bit" "27B 8-bit||qwen3\\.8-27b-mlx-8bit" "MoE 30B-A3B|$MOE_MODEL|$MOE_PATTERN"; do
    parts=("${(@s:|:)pair}")
    key=$(resolve_model "${parts[2]}" "${parts[3]}")
    if [[ -n $key ]]; then say "  ${parts[1]}: $key | $(model_meta "$key")"; else say "  ${parts[1]}: not downloaded"; fi
  done
  say ""; say "All downloaded LLMs (use these keys with GEMMA_MODEL= etc. if a match is wrong):"
  models_json | jq -r '.models[]? | select(.type=="llm") | "  \(.key)   [\(.format // "?") \(.quantization.name // "?"), \((.size_bytes // 0)/1e9*100|floor/100) GB]"' | tee -a "$REPORT"
  say ""; say "Saved: $REPORT"
  rm -f "$CSV"; cleanup; exit 0
fi

[[ $CMD != (whisper|llamabench) ]] && ensure_server
preflight
caffeinate -dims -w $$ &

if [[ $PURGE == 1 || $POWER == 1 ]]; then
  print ""
  print "Enter your Mac password once. It's used to measure watts (powermetrics) and cold model loads (purge)."
  print "(Run with PURGE=0 POWER=0 in front to skip this.)"
  if sudo -v; then
    HAVE_SUDO=1
    { trap - INT TERM; while true; do sudo -n true 2>/dev/null; sleep 50; done } &
    SUDO_KEEP=$!
  fi
fi

ATT_KEEP="LM Studio${ATT_KEEP:+,$ATT_KEEP}" att_cooldown
T_START=$EPOCHSECONDS
case $CMD in
  gemma)      test_gemma ;;
  qwen9b)     test_qwen9b ;;
  qwen27b)    test_qwen27b ;;
  ladder)     test_ladder ;;
  moe)        test_moe ;;
  coding)     test_coding ;;
  agents)     test_agents ;;
  whisper)    test_whisper ;;
  llamabench) test_llamabench ;;
  core)       test_gemma; test_qwen9b; test_qwen27b; test_ladder ;;
  all)        test_gemma; test_qwen9b; test_qwen27b; test_ladder; test_moe; test_coding; test_agents; test_whisper; test_llamabench ;;
esac

say ""
att_card_start "LM Studio: $CMD"
say "================= SHEET-READY (Adam Talks Tech Mac Tests) ================="
say "Values after the label are tab separated so they paste across columns. Medians of $RUNS runs."
for line in $SHEET_LINES; do say "$line"; done
if (( ${#EXTRA_LINES} )); then
  say ""; say "Extra detail (not in the sheet):"
  for line in $EXTRA_LINES; do say "  $line"; done
fi
say "==========================================================================="
say "Done in $(( (EPOCHSECONDS - T_START) / 60 )) min.  Saved:"
say "  $REPORT"
say "  $CSV   (every run)"
say "  $ALL_CSV   (every Mac, every run - point RESULTS_DIR at a shared folder)"
att_card_end
cleanup

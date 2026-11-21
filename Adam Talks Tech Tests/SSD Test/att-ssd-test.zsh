#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
whence att_pause_bg >/dev/null && att_pause_bg   # pause Photos/Spotlight/Siri scanning for the test (wakes back up at the end)
# =============================================================================
#  ATT SSD Test Suite  (Adam Talks Tech)
#  Standardized external SSD test you run from Terminal on a Mac.
#
#  Usage:
#    zsh att-ssd-test.zsh                          # pick the drive from a menu
#    zsh att-ssd-test.zsh --volume /Volumes/U35 --name "Oyen U35 Bolt Plus 4TB"
#    zsh att-ssd-test.zsh --quick                  # 1 run, no sustained write, no copies
#    zsh att-ssd-test.zsh --source ~/ATT-SSD-Testset/100GB --source ~/ATT-SSD-Testset/500GB
#
#  It only writes inside a folder called ATT-SSD-Test on the drive you pick and
#  deletes that folder at the end. It never formats or erases anything.
#  It refuses to run on an internal drive unless you add --allow-internal.
#
#  Needs: fio (brew install fio). jq ships with current macOS.
#  Optional: smartmontools (brew install smartmontools) for drive temps.
# =============================================================================

emulate -L zsh
setopt pipefail no_nomatch
zmodload zsh/datetime   # EPOCHREALTIME for timing
zmodload zsh/mathfunc   # int() in math

SUITE_VERSION="1.1"  # 1.1: results in the test folder

# ---- Standard settings. Don't change these between drives, or results stop lining up.
SEQ_SIZE="5g"            # sequential test file size (Blackmagic-style)
SEQ_BS="1m"              # sequential block size
SEQ_QD=8                 # sequential queue depth
RUNS=3                   # runs per sequential test (median gets logged)
RND_SECONDS=30           # length of each random 4K test
SUSTAIN_GB=500           # sustained write size (matches the 500GB transfer)
SUSTAIN_MAX_FREE_PCT=85  # never fill more than this % of the free space
COOLDOWN=30              # seconds of rest between tests
BIG_COOLDOWN=60          # rest before the sustained write

# ---------- Where am I? ----------
# Works from ~/Downloads/Adam Talks Tech Tests or straight from the LaCie.
# Results go to <test folder>/Results/<Mac name>/ next to everything else.
ROOT=${0:A:h}
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=${0:A:h}
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}
RESULTS_ROOT="$ROOT/Results/$MACNAME/SSD"
MASTER_CSV="$RESULTS_ROOT/att-ssd-results.csv"

# ---- Flags
VOL=""; NAME=""; QUICK=0; ALLOW_INTERNAL=0; NO_PROMPTS=0; READBACK=0; NOTES=""
PORT_NOTE=""; CABLE_NOTE=""
typeset -a SOURCES

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Flags:
  --volume PATH        Drive to test (e.g. /Volumes/U35)
  --name "TEXT"        Drive name as it should appear in the sheet
  --source DIR         Folder to copy onto the drive and time (repeatable)
  --readback           Also time copying each --source back to this Mac
  --port "TEXT"        Which port you used (e.g. "Studio rear TB5 #1")
  --cable "TEXT"       Which cable (e.g. "Included 80G cable")
  --notes "TEXT"       Anything else for the notes column
  --quick              1 run, skip sustained write and copies
  --sustain-gb N       Override sustained write size (logged in the CSV)
  --no-prompts         Don't ask questions (for unattended runs)
  --allow-internal     Allow testing an internal volume
EOF
}

while (( $# )); do
  case "$1" in
    --volume) VOL="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --source) SOURCES+=("$2"); shift 2 ;;
    --readback) READBACK=1; shift ;;
    --port) PORT_NOTE="$2"; shift 2 ;;
    --cable) CABLE_NOTE="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --quick) QUICK=1; shift ;;
    --sustain-gb) SUSTAIN_GB="$2"; shift 2 ;;
    --no-prompts) NO_PROMPTS=1; shift ;;
    --allow-internal) ALLOW_INTERNAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown flag: $1"; usage; exit 1 ;;
  esac
done
(( QUICK )) && RUNS=1

# Dev-only overrides so the logic can be tested off a Mac with tiny sizes
if [[ -n "$ATT_SSD_TEST_LINUX_DEV" ]]; then
  SEQ_SIZE=${DEV_SEQ_SIZE:-$SEQ_SIZE}; RND_SECONDS=${DEV_RND_SECONDS:-$RND_SECONDS}
  COOLDOWN=${DEV_COOLDOWN:-$COOLDOWN}; BIG_COOLDOWN=${DEV_COOLDOWN:-$BIG_COOLDOWN}
  ditto() { cp -R "$1" "$2"; }
fi

# ---- Helpers --------------------------------------------------------------
say()  { print -P "%F{cyan}▶%f $*"; }
ok()   { print -P "%F{green}✔%f $*"; }
warn() { print -P "%F{yellow}!%f $*"; }
die()  { print -P "%F{red}✖ $*%f"; exit 1; }

# seconds -> M:SS (one decimal under a minute, e.g. 0:16.5)
fmt_time() {
  local s=$1
  if (( s < 60 )); then printf "0:%04.1f" $s
  else printf "%d:%02d" $(( int(s / 60) )) $(( int(s) % 60 ))
  fi
}

median() {  # median of numbers given as args
  local -a v; v=(${(on)@})
  local n=${#v}
  (( n == 0 )) && { echo ""; return; }
  if (( n % 2 )); then echo ${v[$(( (n+1)/2 ))]}
  else printf "%.0f" $(( (v[n/2] + v[n/2+1]) / 2.0 )); fi
}

cooldown() {
  local s=$1
  (( s <= 0 )) && return
  printf "  resting %ss " $s
  for i in {1..$s}; do sleep 1; (( i % 5 == 0 )) && printf "."; done
  printf "\n"
}

purge_cache() { sudo -n purge 2>/dev/null || true; }

drive_temp() {  # prints °C or n/a (needs smartmontools; many USB bridges won't report)
  command -v smartctl >/dev/null || { echo "n/a"; return; }
  local t
  t=$(sudo -n smartctl -a "/dev/$WHOLE_DISK" 2>/dev/null | awk '
      /^Temperature:/ {print $2; exit}
      /Temperature_Celsius/ {print $10; exit}
      /Current Drive Temperature/ {print $4; exit}')
  [[ -n "$t" ]] && echo "$t" || echo "n/a"
}

# fio JSON -> value
jget() { jq -r "$2" "$1" 2>/dev/null; }
mbps() { printf "%.0f" $(( $1 / 1000000.0 )); }   # bytes/s -> MB/s (decimal, like Blackmagic/AJA)

run_fio() {  # run_fio <label> <extra fio args...>  -> writes $RUN_DIR/fio-<label>.json
  local label=$1; shift
  fio --name="$label" --ioengine=posixaio --direct=1 --fallocate=none \
      --output-format=json --output="$RUN_DIR/fio-$label.json" "$@" \
      >>"$RUN_DIR/fio-console.log" 2>&1
  local rc=$?
  (( rc != 0 )) && { warn "fio '$label' exited with $rc (see fio-console.log)"; return 1; }
  return 0
}

# ---- Preflight ------------------------------------------------------------
[[ "$(uname)" == "Darwin" || -n "$ATT_SSD_TEST_LINUX_DEV" ]] || die "This runs on a Mac."
command -v fio >/dev/null || die "fio isn't installed. Run: brew install fio"
command -v jq  >/dev/null || die "jq isn't installed. Run: brew install jq"

if [[ -z "$VOL" ]]; then
  say "Pick the drive to test:"
  typeset -a vols
  for v in /Volumes/*(N/); do
    [[ "$(cd "$v" && pwd -P)" == "/" ]] && continue
    [[ "$v" == "/Volumes/Recovery" || "$v" == "/Volumes/Preboot" ]] && continue
    vols+=("$v")
  done
  (( ${#vols} )) || die "No external volumes found in /Volumes."
  PS3="Number: "
  select v in $vols; do [[ -n "$v" ]] && { VOL="$v"; break; }; done
fi
VOL="${VOL%/}"
[[ -d "$VOL" ]] || die "Can't find $VOL"
[[ -w "$VOL" ]] || die "$VOL isn't writable (read-only format like NTFS?)."

# Drive info
if [[ -z "$ATT_SSD_TEST_LINUX_DEV" ]]; then
  DINFO="$(diskutil info -plist "$VOL" 2>/dev/null)"
  pk() { print -r -- "$DINFO" | plutil -extract "$1" raw -o - - 2>/dev/null; }
  IS_INTERNAL="$(pk Internal)"
  FS="$(pk FilesystemName)"; [[ -z "$FS" ]] && FS="$(pk FilesystemType)"
  BUS="$(pk BusProtocol)"
  MEDIA="$(pk MediaName)"
  WHOLE_DISK="$(pk ParentWholeDisk)"
  TOTAL_BYTES="$(pk TotalSize)"
  [[ "$VOL" == "/" || "$(df "$VOL" | awk 'NR==2{print $NF}')" == "/" ]] && IS_INTERNAL=true
else
  IS_INTERNAL=false; FS="(linux dev)"; BUS="dev"; MEDIA="dev"; WHOLE_DISK="sda"
  TOTAL_BYTES=$(( $(df -k "$VOL" | awk 'NR==2{print $2}') * 1024 ))
fi
if [[ "$IS_INTERNAL" == "true" && $ALLOW_INTERNAL -eq 0 ]]; then
  die "$VOL is an internal drive. Pick an external SSD (or add --allow-internal)."
fi
FREE_BYTES=$(( $(df -k "$VOL" | awk 'NR==2{print $4}') * 1024 ))
FREE_GB=$(( FREE_BYTES / 1000000000 ))
CAP_GB=$(( TOTAL_BYTES / 1000000000 ))
(( FREE_GB < 20 )) && die "Only ${FREE_GB}GB free on $VOL. Need at least 20GB."

if [[ -z "$NAME" ]]; then
  if (( NO_PROMPTS )); then NAME="$MEDIA"
  else read "NAME?Drive name for the sheet (e.g. Oyen U35 Bolt Plus 4TB): "; fi
fi
[[ -z "$NAME" ]] && NAME="$MEDIA"
if (( ! NO_PROMPTS )); then
  [[ -z "$PORT_NOTE" ]] && read "PORT_NOTE?Port used (e.g. Studio rear TB5 #1): "
  [[ -z "$CABLE_NOTE" ]] && read "CABLE_NOTE?Cable (e.g. included cable): "
fi

# Host info
if [[ -z "$ATT_SSD_TEST_LINUX_DEV" ]]; then
  HOST_MODEL="$(sysctl -n hw.model)"
  CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
  MACOS="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
else
  HOST_MODEL="linux-dev"; CHIP="dev"; MACOS="dev"; RAM_GB=0
fi

STAMP="$(strftime %Y-%m-%d_%H%M $EPOCHSECONDS)"
SAFE_NAME="${NAME//[^A-Za-z0-9._-]/_}"
RUN_DIR="$RESULTS_ROOT/runs/${STAMP}_${SAFE_NAME}"
mkdir -p "$RUN_DIR" || die "Can't make $RUN_DIR"
TESTDIR="$VOL/ATT-SSD-Test"
[[ -e "$TESTDIR" ]] && rm -rf "$TESTDIR"
mkdir -p "$TESTDIR" || die "Can't write to $VOL"

# Link speed (best effort). Full system_profiler output saved for checking.
LINK="unknown"
if [[ -z "$ATT_SSD_TEST_LINUX_DEV" ]]; then
  system_profiler SPThunderboltDataType > "$RUN_DIR/thunderbolt.txt" 2>/dev/null
  { system_profiler SPUSBHostDataType 2>/dev/null || system_profiler SPUSBDataType 2>/dev/null } > "$RUN_DIR/usb.txt"
  key="${MEDIA%% *}"
  for f in "$RUN_DIR/thunderbolt.txt" "$RUN_DIR/usb.txt"; do
    l=$(awk -v k="$key" 'tolower($0) ~ tolower(k) {hit=NR} hit && NR<=hit+25 && /Speed|Link/ {sub(/^ +/,""); print; exit}' "$f")
    [[ -n "$l" ]] && { LINK="$l"; break; }
  done
  [[ "$LINK" == "unknown" && "$BUS" == "PCI-Express" ]] && LINK="PCIe/Thunderbolt (see thunderbolt.txt)"
fi

# Power + sudo (purge needs it)
if [[ -z "$ATT_SSD_TEST_LINUX_DEV" ]] && pmset -g batt | grep -q "Battery Power"; then
  warn "This Mac is on battery. Plug it in for official runs."
fi
say "Your password is needed once so the script can clear the file cache between tests."
sudo -v || warn "No sudo: cache won't be cleared between copy tests."
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
SUDO_KEEPALIVE=$!

# Spotlight off on the test drive during the run, restored at the end
SPOT_RESTORE=0
if [[ -z "$ATT_SSD_TEST_LINUX_DEV" ]] && mdutil -s "$VOL" 2>/dev/null | grep -q "Indexing enabled"; then
  sudo -n mdutil -i off "$VOL" >/dev/null 2>&1 && SPOT_RESTORE=1
fi

# Keep the Mac awake
command -v caffeinate >/dev/null && { caffeinate -dimsu -w $$ & }

cleanup() {
  [[ -d "$TESTDIR" ]] && rm -rf "$TESTDIR"
  [[ -n "$READBACK_DIR" && -d "$READBACK_DIR" ]] && rm -rf "$READBACK_DIR"
  (( SPOT_RESTORE )) && sudo -n mdutil -i on "$VOL" >/dev/null 2>&1
  [[ -n "$SUDO_KEEPALIVE" ]] && kill $SUDO_KEEPALIVE 2>/dev/null
}
trap 'print; warn "Stopped. Cleaning up test files..."; cleanup; exit 130' INT TERM
trap 'cleanup; att_resume_bg 2>/dev/null' EXIT

{
  echo "ATT SSD Test Suite v$SUITE_VERSION"
  echo "Date: $(date)"
  echo "Drive: $NAME | media: $MEDIA | $CAP_GB GB | $FS | bus: $BUS | link: $LINK"
  echo "Port: $PORT_NOTE | Cable: $CABLE_NOTE"
  echo "Host: $HOST_MODEL | $CHIP | ${RAM_GB}GB | macOS $MACOS"
  echo "Free before: ${FREE_GB}GB"
  echo "Settings: seq $SEQ_SIZE bs=$SEQ_BS qd=$SEQ_QD x$RUNS | random ${RND_SECONDS}s | sustain ${SUSTAIN_GB}GB"
} | tee "$RUN_DIR/info.txt"
print

TEMP_START="$(drive_temp)"

# ---- 1. Sequential (Blackmagic/AJA-style) ---------------------------------
say "1/4  Sequential write + read ($SEQ_SIZE, 1MB blocks, $RUNS runs)"
typeset -a SW SR
for r in {1..$RUNS}; do
  run_fio "seq-write-$r" --filename="$TESTDIR/seq.bin" --size=$SEQ_SIZE --bs=$SEQ_BS \
    --iodepth=$SEQ_QD --rw=write --end_fsync=1 || continue
  w=$(mbps $(jget "$RUN_DIR/fio-seq-write-$r.json" '.jobs[0].write.bw_bytes'))
  purge_cache; sleep 3
  run_fio "seq-read-$r" --filename="$TESTDIR/seq.bin" --size=$SEQ_SIZE --bs=$SEQ_BS \
    --iodepth=$SEQ_QD --rw=read || continue
  rd=$(mbps $(jget "$RUN_DIR/fio-seq-read-$r.json" '.jobs[0].read.bw_bytes'))
  SW+=($w); SR+=($rd)
  ok "run $r: write $w MB/s, read $rd MB/s"
  rm -f "$TESTDIR/seq.bin"
  (( r < RUNS )) && cooldown $COOLDOWN
done
SEQ_W=$(median $SW); SEQ_R=$(median $SR)
ok "Sequential median: write $SEQ_W MB/s, read $SEQ_R MB/s"
cooldown $COOLDOWN

# ---- 2. Random 4K ---------------------------------------------------------
say "2/4  Random 4K (QD1 = everyday feel, QD32 = heavy load), ${RND_SECONDS}s each"
run_fio "rnd-prep" --filename="$TESTDIR/rnd.bin" --size=4g --bs=1m --iodepth=8 --rw=write --end_fsync=1
typeset -A RND
for mode in randread randwrite; do
  run_fio "$mode-qd1" --filename="$TESTDIR/rnd.bin" --size=4g --bs=4k --iodepth=1 \
    --rw=$mode --time_based --runtime=$RND_SECONDS
  d=${mode#rand}
  f="$RUN_DIR/fio-$mode-qd1.json"
  RND[${mode}_qd1_mbps]=$(mbps $(jget $f ".jobs[0].$d.bw_bytes"))
  RND[${mode}_qd1_iops]=$(printf "%.0f" $(jget $f ".jobs[0].$d.iops"))
  RND[${mode}_qd1_lat]=$(printf "%.0f" $(( $(jget $f ".jobs[0].$d.clat_ns.mean") / 1000.0 )))
  purge_cache; sleep 3
  # macOS caps async I/O per process at 16, so QD32 = 4 jobs x QD8
  run_fio "$mode-qd32" --filename="$TESTDIR/rnd.bin" --size=4g --bs=4k --iodepth=8 \
    --numjobs=4 --group_reporting --rw=$mode --time_based --runtime=$RND_SECONDS
  f="$RUN_DIR/fio-$mode-qd32.json"
  RND[${mode}_qd32_mbps]=$(mbps $(jget $f ".jobs[0].$d.bw_bytes"))
  RND[${mode}_qd32_iops]=$(printf "%.0f" $(jget $f ".jobs[0].$d.iops"))
  ok "$mode: QD1 ${RND[${mode}_qd1_mbps]} MB/s (${RND[${mode}_qd1_iops]} IOPS, ${RND[${mode}_qd1_lat]}µs) | QD32 ${RND[${mode}_qd32_mbps]} MB/s (${RND[${mode}_qd32_iops]} IOPS)"
  purge_cache; sleep 3
done
rm -f "$TESTDIR/rnd.bin"

# ---- 3. Sustained write (cache cliff + heat) ------------------------------
SUS_GB=""; SUS_TIME=""; SUS_AVG=""; SUS_FIRST=""; CLIFF=""; POST=""; LAST60=""; MIN10=""; CLIFF_TXT=""
if (( ! QUICK )); then
  cooldown $BIG_COOLDOWN
  FREE_NOW=$(( $(df -k "$VOL" | awk 'NR==2{print $4}') * 1024 ))
  MAX_GB=$(( FREE_NOW * SUSTAIN_MAX_FREE_PCT / 100 / 1000000000 ))
  SUS_GB=$(( SUSTAIN_GB < MAX_GB ? SUSTAIN_GB : MAX_GB ))
  (( SUS_GB < SUSTAIN_GB )) && warn "Only room for ${SUS_GB}GB of the ${SUSTAIN_GB}GB sustained write. Logged as ${SUS_GB}GB."
  say "3/4  Sustained write: ${SUS_GB}GB in one go (finds where the cache runs out and heat slowdown)"
  t0=$EPOCHREALTIME
  run_fio "sustained" --filename="$TESTDIR/sustained.bin" --size=$(( SUS_GB * 1000000000 )) \
    --bs=1m --iodepth=$SEQ_QD --rw=write --end_fsync=1 \
    --write_bw_log="$RUN_DIR/sustained" --log_avg_msec=1000
  t1=$EPOCHREALTIME
  SUS_TIME=$(fmt_time $(( t1 - t0 )))
  SUS_AVG=$(mbps $(jget "$RUN_DIR/fio-sustained.json" '.jobs[0].write.bw_bytes'))
  BWLOG=("$RUN_DIR"/sustained_bw*.log(N))
  if (( ${#BWLOG} )); then
    # Per-second CSV for charts: second, MB/s, GB written so far
    awk -F', *' 'BEGIN{print "second,MBps,GB_written"} {mb=$2*1.024/1000; gb+=mb/1000; printf "%d,%.0f,%.1f\n", NR, mb, gb}' \
      "${BWLOG[1]}" > "$RUN_DIR/sustained-per-second.csv"
    read SUS_FIRST CLIFF POST LAST60 MIN10 < <(awk -F, 'NR>1{mb[NR-1]=$2; gb[NR-1]=$3; n=NR-1}
      END{
        if(n<1){print "n/a never n/a n/a n/a"; exit}
        k=(n<10?n:10); s=0; for(i=1;i<=k;i++) s+=mb[i]; first=s/k
        cliff="never"; ci=0
        for(i=10;i<=n;i++){ s=0; for(j=i-9;j<=i;j++) s+=mb[j]; if(s/10 < first*0.5){ci=i-9; while(ci<i && mb[ci]>=first*0.5) ci++; cliff=sprintf("%.0f",gb[ci-1]); break} }
        post="n/a"; if(ci>0){s=0;c=0; for(i=ci;i<=n;i++){s+=mb[i];c++}; post=sprintf("%.0f",s/c)}
        s=0;c=0; for(i=(n>60?n-59:1);i<=n;i++){s+=mb[i];c++}; last=s/c
        min=1e12; for(i=10;i<=n;i++){ s=0; for(j=i-9;j<=i;j++) s+=mb[j]; if(s/10<min) min=s/10 }; if(min==1e12) min=first
        printf "%.0f %s %s %.0f %.0f\n", first, cliff, post, last, min
      }' "$RUN_DIR/sustained-per-second.csv")
  fi
  [[ "$CLIFF" == never ]] && CLIFF_TXT="never (held speed the whole way)" || CLIFF_TXT="${CLIFF}GB, then ${POST} MB/s"
  ok "Sustained: ${SUS_GB}GB in $SUS_TIME (avg $SUS_AVG MB/s). First 10s $SUS_FIRST MB/s. Cache runs out: $CLIFF_TXT. Last minute $LAST60 MB/s"
  rm -f "$TESTDIR/sustained.bin"
  TEMP_AFTER_SUS="$(drive_temp)"
else
  say "3/4  Sustained write skipped (--quick)"
fi

# ---- 4. Real-world copies (your 100GB / 500GB transfers) -------------------
typeset -a COPY_GB COPY_T READ_T
if (( ! QUICK && ${#SOURCES} )); then
  for src in $SOURCES; do
    [[ -d "$src" ]] || { warn "Source not found: $src"; continue; }
    sbytes=$(( $(du -sk "$src" | awk '{print $1}') * 1024 ))
    sgb=$(printf "%.1f" $(( sbytes / 1000000000.0 )))
    free=$(( $(df -k "$VOL" | awk 'NR==2{print $4}') * 1024 ))
    (( sbytes > free * 95 / 100 )) && { warn "Not enough room for $src (${sgb}GB)"; continue; }
    cooldown $COOLDOWN
    say "4/4  Copy ${sgb}GB ($src) onto the drive"
    purge_cache; sleep 3
    t0=$EPOCHREALTIME
    ditto "$src" "$TESTDIR/copy" && sync
    t1=$EPOCHREALTIME
    ct=$(fmt_time $(( t1 - t0 ))); COPY_GB+=($sgb); COPY_T+=($ct)
    ok "${sgb}GB copied in $ct ($(printf %.0f $(( sbytes / 1000000.0 / (t1 - t0) ))) MB/s)"
    if (( READBACK )); then
      READBACK_DIR="$HOME/.att-ssd-readback"; rm -rf "$READBACK_DIR"
      purge_cache; sleep 3
      t0=$EPOCHREALTIME; ditto "$TESTDIR/copy" "$READBACK_DIR" && sync; t1=$EPOCHREALTIME
      rt=$(fmt_time $(( t1 - t0 ))); READ_T+=($rt)
      ok "Copied back to this Mac in $rt"
      rm -rf "$READBACK_DIR"
    else READ_T+=(""); fi
    rm -rf "$TESTDIR/copy"
  done
elif (( ! QUICK )); then
  say "4/4  Copy test skipped (no --source folders given)"
fi

TEMP_END="$(drive_temp)"

# ---- Manual checks --------------------------------------------------------
IPHONE=""; IPAD=""
if (( ! NO_PROMPTS )); then
  read "IPHONE?Works with iPhone? (y/n/blank to skip): "
  read "IPAD?Works with iPad? (y/n/blank to skip): "
  [[ -z "$NOTES" ]] && read "NOTES?Notes (heat, size, anything odd): "
fi

# ---- Save results ---------------------------------------------------------
HEADER="date,suite_version,drive,media_name,capacity_GB,filesystem,bus,link,port,cable,host_model,chip,ram_GB,macos,seq_write_MBps,seq_read_MBps,seq_write_runs,seq_read_runs,rnd4k_qd1_read_MBps,rnd4k_qd1_read_IOPS,rnd4k_qd1_read_lat_us,rnd4k_qd1_write_MBps,rnd4k_qd1_write_IOPS,rnd4k_qd1_write_lat_us,rnd4k_qd32_read_MBps,rnd4k_qd32_read_IOPS,rnd4k_qd32_write_MBps,rnd4k_qd32_write_IOPS,sustained_GB,sustained_time,sustained_avg_MBps,sustained_first10s_MBps,cache_runs_out_at_GB,after_cache_MBps,sustained_last60s_MBps,sustained_worst10s_MBps,copy1_GB,copy1_time,copy1_readback,copy2_GB,copy2_time,copy2_readback,temp_start_C,temp_after_sustained_C,temp_end_C,iphone,ipad,notes,run_folder"
csvq() { local s="${1//\"/\"\"}"; print -rn -- "\"$s\""; }
ROW=$(
  csvq "$(date '+%Y-%m-%d %H:%M')"; printf ,; csvq "$SUITE_VERSION"; printf ,; csvq "$NAME"; printf ,
  csvq "$MEDIA"; printf ,; csvq "$CAP_GB"; printf ,; csvq "$FS"; printf ,; csvq "$BUS"; printf ,; csvq "$LINK"; printf ,
  csvq "$PORT_NOTE"; printf ,; csvq "$CABLE_NOTE"; printf ,; csvq "$HOST_MODEL"; printf ,; csvq "$CHIP"; printf ,
  csvq "$RAM_GB"; printf ,; csvq "$MACOS"; printf ,; csvq "$SEQ_W"; printf ,; csvq "$SEQ_R"; printf ,
  csvq "${(j:/:)SW}"; printf ,; csvq "${(j:/:)SR}"; printf ,
  csvq "${RND[randread_qd1_mbps]}"; printf ,; csvq "${RND[randread_qd1_iops]}"; printf ,; csvq "${RND[randread_qd1_lat]}"; printf ,
  csvq "${RND[randwrite_qd1_mbps]}"; printf ,; csvq "${RND[randwrite_qd1_iops]}"; printf ,; csvq "${RND[randwrite_qd1_lat]}"; printf ,
  csvq "${RND[randread_qd32_mbps]}"; printf ,; csvq "${RND[randread_qd32_iops]}"; printf ,
  csvq "${RND[randwrite_qd32_mbps]}"; printf ,; csvq "${RND[randwrite_qd32_iops]}"; printf ,
  csvq "$SUS_GB"; printf ,; csvq "$SUS_TIME"; printf ,; csvq "$SUS_AVG"; printf ,; csvq "$SUS_FIRST"; printf ,
  csvq "$CLIFF"; printf ,; csvq "$POST"; printf ,; csvq "$LAST60"; printf ,; csvq "$MIN10"; printf ,
  csvq "${COPY_GB[1]}"; printf ,; csvq "${COPY_T[1]}"; printf ,; csvq "${READ_T[1]}"; printf ,
  csvq "${COPY_GB[2]}"; printf ,; csvq "${COPY_T[2]}"; printf ,; csvq "${READ_T[2]}"; printf ,
  csvq "$TEMP_START"; printf ,; csvq "$TEMP_AFTER_SUS"; printf ,; csvq "$TEMP_END"; printf ,
  csvq "$IPHONE"; printf ,; csvq "$IPAD"; printf ,; csvq "$NOTES"; printf ,; csvq "$RUN_DIR"
)
[[ -f "$MASTER_CSV" ]] || print -r -- "$HEADER" > "$MASTER_CSV"
print -r -- "$ROW" >> "$MASTER_CSV"
{ print -r -- "$HEADER"; print -r -- "$ROW"; } > "$RUN_DIR/result.csv"

# Summary in the same order as the sheet's columns
SUMMARY=$(cat <<EOF

================  $NAME  ================
Host: $HOST_MODEL ($CHIP, ${RAM_GB}GB) macOS $MACOS
Link: $LINK   Port: $PORT_NOTE   Cable: $CABLE_NOTE

SHEET COLUMNS
  Copy 1:  ${COPY_GB[1]:-–}GB in ${COPY_T[1]:-–}
  Copy 2:  ${COPY_GB[2]:-–}GB in ${COPY_T[2]:-–}
  Write:   $SEQ_W MB/s   (runs: ${(j:, :)SW})
  Read:    $SEQ_R MB/s   (runs: ${(j:, :)SR})

ENTHUSIAST NUMBERS
  Random 4K QD1:  read ${RND[randread_qd1_mbps]} MB/s / write ${RND[randwrite_qd1_mbps]} MB/s
  Random 4K QD32: read ${RND[randread_qd32_mbps]} MB/s / write ${RND[randwrite_qd32_mbps]} MB/s
  Sustained ${SUS_GB:-–}GB write: ${SUS_TIME:-–} (avg ${SUS_AVG:-–} MB/s)
    starts at ${SUS_FIRST:-–} MB/s, cache runs out: ${CLIFF_TXT:-–}
    last minute ${LAST60:-–} MB/s, worst 10s ${MIN10:-–} MB/s
  Drive temp: start ${TEMP_START}, after sustained ${TEMP_AFTER_SUS:-–}, end ${TEMP_END} (°C)

Saved: $RUN_DIR
Added a row to: $MASTER_CSV
EOF
)
att_card_start "SSD test: $NAME"
print -r -- "$SUMMARY" | tee "$RUN_DIR/summary.txt"
att_card_end

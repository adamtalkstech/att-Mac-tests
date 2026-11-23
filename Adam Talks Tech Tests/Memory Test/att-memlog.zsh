#!/bin/zsh
source "${0:A:h:h}/Tools/att-card.zsh" 2>/dev/null || source "${0:A:h}/att-card.zsh" 2>/dev/null || { att_card_start() { print "\n===== $* ====="; }; att_card_end() { :; }; att_cooldown() { :; }; }
# ATT memory logger  -  v1.1 (Nov 16 2026)
# Logs memory pressure color, memory free %, swap, compressed memory and SSD data
# written, so a RAM test shows what running low actually costs.
#
# Lives in: Adam Talks Tech Tests/Memory Test
# Usage:
#   zsh att-memlog.zsh "M6 16GB stacker run"        (logs every 5 seconds)
#   zsh att-memlog.zsh "M6 16GB stacker run" 2      (logs every 2 seconds)
#
# Mark a step while it runs (from a second Terminal tab):
#   echo "40 tabs open" > /tmp/att-step
#
# Stop with Control-C. It prints a summary and the CSV path.
# Built-in macOS commands only, nothing to install.
#
# v1.1: CSVs go to Adam Talks Tech Tests/Results/<Mac name>/Memory
#       (was Desktop > ATT Memory Logs). Logging itself is unchanged.

# ---------- Where am I? ----------
ROOT=${0:A:h}
while [[ $ROOT != / && ${ROOT:t} != "Adam Talks Tech Tests" ]]; do ROOT=${ROOT:h}; done
[[ $ROOT == / ]] && ROOT=${0:A:h}
MACNAME=$(scutil --get ComputerName 2>/dev/null); MACNAME=${MACNAME:-$(hostname -s)}

label="${1:-test}"
interval="${2:-5}"
outdir="$ROOT/Results/$MACNAME/Memory"
mkdir -p "$outdir"
stamp=$(date +"%Y-%m-%d_%H-%M-%S")
safe_label=$(echo "$label" | tr ' /' '__')
csv="$outdir/${stamp}_${safe_label}.csv"
stepfile="/tmp/att-step"
rm -f "$stepfile"

model=$(sysctl -n hw.model)
ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
macos=$(sw_vers -productVersion)
pagesize=$(sysctl -n vm.pagesize)

# Total bytes written to the internal SSD since boot
ssd_written_bytes() {
  # Nov 22: summed over every disk driver (head -1 could pick a test drive or disk image -> 0.0 GB/h)
  ioreg -c IOBlockStorageDriver -r -w0 2>/dev/null \
    | grep -o '"Bytes (Write)"=[0-9]*' | cut -d= -f2 | awk '{s+=$1} END{printf "%.0f", s}'
}

# Swap used in GB (from "total = X used = Y free = Z")
swap_used_gb() {
  sysctl -n vm.swapusage | awk '{for(i=1;i<=NF;i++) if($i=="used") {v=$(i+2); sub("M","",v); printf "%.2f", v/1024}}'
}

# Memory occupied by the compressor in GB
compressed_gb() {
  vm_stat | awk -v ps="$pagesize" '/Pages occupied by compressor/ {gsub("\\.","",$5); printf "%.2f", ($5*ps)/1073741824}'
}

# macOS's own "memory free" percentage (higher is better)
mem_free_pct() {
  memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}'
}

# Activity Monitor's pressure level: 1 = green, 2 = yellow, 4 = red
pressure_color() {
  case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
    1) echo green ;;
    2) echo yellow ;;
    4) echo red ;;
    *) echo unknown ;;
  esac
}

start_written=$(ssd_written_bytes)
start_swap=$(swap_used_gb)
start_time=$(date +%s)
peak_swap=$start_swap
peak_comp=0
min_free=100
yellow_secs=0
red_secs=0
step="start"

echo "Mac,RAM GB,macOS,Label" > "$csv"
echo "$model,$ram_gb,$macos,$label" >> "$csv"
echo "" >> "$csv"
echo "Time,Elapsed (s),Step,Pressure,Memory free %,Swap used GB,Compressed GB,SSD written since start GB" >> "$csv"

echo "ATT memory logger: $label"
echo "$model, ${ram_gb}GB, macOS $macos. Logging every ${interval}s to:"
echo "$csv"
echo "Mark a step:  echo \"your step\" > /tmp/att-step     Stop: Control-C"
echo ""
printf "%-8s %-22s %-8s %-7s %-9s %-10s %-8s\n" "Elapsed" "Step" "Press." "Free%" "Swap GB" "Compr. GB" "Written"

finish() {
  end_time=$(date +%s)
  total=$(( end_time - start_time ))
  end_written=$(ssd_written_bytes)
  written_gb=$(awk -v a="$start_written" -v b="$end_written" 'BEGIN{printf "%.2f", (b-a)/1073741824}')
  {
    echo ""
    echo "Summary"
    echo "Duration (s),$total"
    echo "Swap at start GB,$start_swap"
    echo "Peak swap GB,$peak_swap"
    echo "Peak compressed GB,$peak_comp"
    echo "Lowest memory free %,$min_free"
    echo "Seconds in yellow,$yellow_secs"
    echo "Seconds in red,$red_secs"
    echo "SSD written during test GB,$written_gb"
  } >> "$csv"
  echo ""
  att_card_start "Memory log: $label"
  echo "  Duration:            ${total}s"
  echo "  Swap:                ${start_swap} GB at start, ${peak_swap} GB peak"
  echo "  Peak compressed:     ${peak_comp} GB"
  echo "  Lowest memory free:  ${min_free}%"
  echo "  Time in yellow/red:  ${yellow_secs}s / ${red_secs}s"
  echo "  SSD written:         ${written_gb} GB"
  echo "  CSV: ${csv:t}"
  att_card_end
  rm -f "$stepfile"
  exit 0
}
trap finish INT TERM

while true; do
  [[ -f "$stepfile" ]] && step=$(cat "$stepfile")
  now=$(date +%s)
  elapsed=$(( now - start_time ))
  press=$(pressure_color)
  free=$(mem_free_pct)
  swap=$(swap_used_gb)
  comp=$(compressed_gb)
  written=$(ssd_written_bytes)
  wgb=$(awk -v a="$start_written" -v b="$written" 'BEGIN{printf "%.2f", (b-a)/1073741824}')

  peak_swap=$(awk -v a="$peak_swap" -v b="$swap" 'BEGIN{print (b>a)?b:a}')
  peak_comp=$(awk -v a="$peak_comp" -v b="$comp" 'BEGIN{print (b>a)?b:a}')
  [[ -n "$free" ]] && min_free=$(awk -v a="$min_free" -v b="$free" 'BEGIN{print (b<a)?b:a}')
  [[ "$press" == "yellow" ]] && yellow_secs=$(( yellow_secs + interval ))
  [[ "$press" == "red" ]] && red_secs=$(( red_secs + interval ))

  echo "$(date +%H:%M:%S),$elapsed,\"$step\",$press,$free,$swap,$comp,$wgb" >> "$csv"
  printf "%-8s %-22.22s %-8s %-7s %-9s %-10s %-8s\n" "${elapsed}s" "$step" "$press" "$free" "$swap" "$comp" "$wgb"
  sleep "$interval"
done

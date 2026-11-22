# ATT app memory (sourced by the RAM tests, not run on its own)  -  v1.0 (Nov 21 2026)
# How much memory each APP is using, not just the whole Mac:
#   footprint  = what macOS charges the app (Activity Monitor's "Memory" column), including what got compressed
#   compressed = the part macOS squeezed (Activity Monitor's "Compressed Memory" column)
#   in RAM     = footprint - compressed
# Helper processes are added to their app: Chrome's renderers -> Google Chrome, Final Cut's helpers ->
# Final Cut Pro, Xcode's compilers -> Xcode, LM Studio's model engine -> LM Studio. Safari's web pages run
# in shared WebKit processes, so they show as "Web pages (WebKit)" (that's Safari when only Safari is open).
# Built-in commands only (top + ps), no password.

# One snapshot. Prints  app|footprint_MB|compressed_MB|processes  for every app over 20 MB, biggest first.
att_appmem_snap() {
  local t=${TMPDIR:-/tmp}/att-appmem.$$
  ps -axo pid=,comm= > $t.ps 2>/dev/null
  top -l 1 -n 3000 -stats pid,mem,cmprs 2>/dev/null > $t.top
  awk '
    function mb(v,  n,u) { gsub(/[+-]$/,"",v); n=v+0; u=substr(v,length(v),1)
      if (u=="G") return n*1024; if (u=="M") return n; if (u=="K") return n/1024; if (u=="B") return n/1048576; return n/1048576 }
    function grp(c,  m) {
      if (c ~ /com\.apple\.WebKit/) return "Web pages (WebKit)"
      if (match(c, /\/[^\/]+\.app\//)) { m=substr(c, RSTART+1, RLENGTH-6); return m }
      if (c ~ /\/\.lmstudio\//) return "LM Studio"
      if (c ~ /WindowServer$/) return "WindowServer (screen)"
      if (c ~ /kernel_task$/) return "macOS kernel"
      return "Everything else (system)"
    }
    FNR==NR { p=$1; $1=""; sub(/^ /,""); comm[p]=$0; next }
    $1 ~ /^[0-9]+$/ && ($1 in comm) { g=grp(comm[$1]); fp[g]+=mb($2); cp[g]+=mb($3); n[g]++ }
    END { for (g in fp) if (fp[g] >= 20) printf "%s|%.0f|%.0f|%d\n", g, fp[g], cp[g], n[g] }
  ' $t.ps $t.top | sort -t'|' -k2,2nr
  rm -f $t.ps $t.top
}

# Background sampler: every $2 seconds (default 5) appends  time,step,app,footprint_MB,compressed_MB,processes
# to CSV $1. The step comes from /tmp/att-step (same file the memory logger reads). Stop with att_appmem_stop.
att_appmem_start() {
  local csv=$1 every=${2:-5}
  [[ -s $csv ]] || print "time,step,app,footprint_MB,compressed_MB,processes" > "$csv"
  ( trap 'exit 0' TERM
    while true; do
      local now=$(date +%H:%M:%S) st=$(cat /tmp/att-step 2>/dev/null | tr -d ',"')
      att_appmem_snap | awk -F'|' -v t="$now" -v s="$st" '{printf "%s,%s,\"%s\",%s,%s,%s\n", t, s, $1, $2, $3, $4}' >> "$csv"
      sleep $every
    done ) &!
  ATT_APPMEM_PID=$!
}
att_appmem_stop() { [[ -n $ATT_APPMEM_PID ]] && kill -TERM $ATT_APPMEM_PID 2>/dev/null; ATT_APPMEM_PID=""; sleep 1; }

# Card lines: each app's peak footprint (and how much of it was compressed at that moment) over the whole CSV.
# $1 CSV, $2 how many apps (default 8). Optional $3 = only rows whose step contains this text.
att_appmem_peaks() {
  local csv=$1 top=${2:-8} only=${3:-}
  awk -F, -v only="$only" 'NR>1 && (only=="" || index($2, only)) {
      a=$3; for (i=4; i<=NF-3; i++) a=a "," $i; gsub(/"/,"",a)
      f=$(NF-2)+0; c=$(NF-1)+0
      if (f > pk[a]) { pk[a]=f; pc[a]=c; ps[a]=$2 } }
    END { for (a in pk) printf "%.0f|%s|%.0f|%s\n", pk[a], a, pc[a], ps[a] }' "$csv" | sort -t'|' -k1,1nr | head -$top |
  awk -F'|' '{ printf "  %-28s %6.1f GB  (%4.1f GB compressed, %4.1f GB in RAM)  peak at: %s\n", substr($2,1,28), $1/1024, $3/1024, ($1-$3)/1024, $4 }'
}

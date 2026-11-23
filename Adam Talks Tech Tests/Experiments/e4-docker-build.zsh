#!/bin/zsh
# =============================================================================
#  E4  Docker build (EXPERIMENT, Nov 22 2026) - not logged to the main sheet
# =============================================================================
#  Developer ask from the comments: how fast does a Mac build in Docker? Compiles Redis from
#  source inside a gcc container (Linux arm64 VM), 3 clean builds, median. The source and the
#  image are downloaded ONCE before timing, so the network never counts. Prints Docker's CPU/RAM
#  limits, because Docker Desktop's VM settings change the result (use the same settings everywhere).
#  Needs Docker Desktop (free for personal use) running.
#    cd ~/Downloads/"Adam Talks Tech Tests"/Experiments && zsh e4-docker-build.zsh
# =============================================================================
export ATT_EXPERIMENT=1
source "${0:A:h:h}/Tools/att-card.zsh"
zmodload zsh/datetime
ROOT=${0:A:h:h}; MAC=$(scutil --get ComputerName); OUT="$ROOT/Results/$MAC/Experiments"; mkdir -p "$OUT"; STAMP=$(date +%Y-%m-%d_%H-%M)
command -v docker >/dev/null || { print "!! Docker Desktop isn't installed (docker.com). Install, open it once, rerun."; exit 1; }
docker info >/dev/null 2>&1 || { open -a Docker; print "Starting Docker Desktop..."; for i in {1..60}; do docker info >/dev/null 2>&1 && break; sleep 3; done; }
docker info >/dev/null 2>&1 || { print "!! Docker didn't start."; exit 1; }
SRC=$HOME/.att/docker-src; mkdir -p $SRC
[[ -d $SRC/redis-7.4.2 ]] || { curl -fsSL https://download.redis.io/releases/redis-7.4.2.tar.gz | tar -xz -C $SRC || { print "!! Couldn't download Redis source."; exit 1; }; }
docker pull -q gcc:14 >/dev/null || { print "!! Couldn't pull the gcc:14 image."; exit 1; }
CPUS=$(docker info --format '{{.NCPU}}'); MEMG=$(docker info --format '{{.MemTotal}}' | awk '{printf "%.0f", $1/1073741824}')
ATT_KEEP="Docker,Docker Desktop" att_cooldown
times=()
for r in 1 2 3; do
  docker run --rm -v "$SRC/redis-7.4.2:/src:ro" gcc:14 sh -c 'cp -r /src /b && cd /b && make distclean >/dev/null 2>&1; true' >/dev/null 2>&1
  t0=$EPOCHREALTIME
  docker run --rm -v "$SRC/redis-7.4.2:/src:ro" gcc:14 sh -c "cp -r /src /b && cd /b && make -j$CPUS >/dev/null 2>&1" ; rc=$?
  t=$(( EPOCHREALTIME - t0 )); (( rc )) && { print "!! build failed (rc $rc)"; break; }
  times+=($(printf %.1f $t)); print "  build $r: ${times[-1]} s"; (( r < 3 )) && att_cooldown --again
done
med=$(print -l $times | sort -n | sed -n 2p)
{ att_card_start "EXPERIMENT E4: Docker build, Redis 7.4.2 in gcc:14 (not logged to the main sheet)"
  print "Builds: ${(j: / :)times} s   median ${med:-?} s"
  print "Docker VM: ${CPUS} CPUs, ${MEMG} GB RAM (Docker Desktop > Settings > Resources). $(docker version --format 'Docker {{.Server.Version}}' 2>/dev/null)"
  print "Send this card to Claude: it goes on the Experiments tab."
  att_card_end; } | tee "$OUT/e4-docker_$STAMP.txt"

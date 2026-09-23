#!/usr/bin/env bash
# Records how busy the server is every 2 seconds while a load test runs, then prints the
# worst moments. Start it just before the test and press Ctrl-C when the test has finished.
#
# Usage: sudo ./test/loadtest/monitor.sh [output.csv]
set -uo pipefail

OWNER_HOME="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
OUT="${1:-${OWNER_HOME}/loadtest-monitor-$(date +%Y%m%d-%H%M%S).csv}"
INTERVAL=2
START="$(date '+%Y-%m-%d %H:%M:%S')"

[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }

echo "time,load1,cpu_busy_pct,mem_available_mb,swap_used_mb,ssh_connections,sessions,user_managers,sshd_processes" > "$OUT"

cpu_counters() {
  # total and idle (idle + iowait) jiffies across all CPUs
  awk '/^cpu /{ total = 0; for (i = 2; i <= NF; i++) total += $i; print total, $5 + $6 }' /proc/stat
}

summary() {
  echo ""
  echo "================ SERVER DURING THE TEST ================"
  awk -F, 'NR > 1 {
      if ($2 + 0 > load) load = $2 + 0
      if ($3 + 0 > cpu) cpu = $3 + 0
      if (mem == "" || $4 + 0 < mem) mem = $4 + 0
      if ($5 + 0 > swap) swap = $5 + 0
      if ($6 + 0 > conns) conns = $6 + 0
      if ($7 + 0 > sess) sess = $7 + 0
      if ($8 + 0 > mgrs) mgrs = $8 + 0
      if (first == "") first = $4 + 0
      n++
    }
    END {
      if (n == 0) { print "No samples were recorded."; exit }
      printf "Highest load average:   %s (on %s CPU cores)\n", load, cores
      printf "Highest CPU use:        %d%%\n", cpu
      printf "Lowest free memory:     %d MB (it was %d MB at the start)\n", mem, first
      printf "Most swap used:         %d MB\n", swap
      printf "Most SSH connections:   %d\n", conns
      printf "Most login sessions:    %d\n", sess
      printf "Most per-user managers: %d\n", mgrs
    }' cores="$(nproc)" "$OUT"
  local log
  log="$(journalctl -t sshd -t sshd-session --since "$START" --no-pager 2>/dev/null)"
  echo "Successful SSH logins:  $(grep -c 'Accepted password' <<<"$log")"
  echo "Failed passwords:       $(grep -c 'Failed password' <<<"$log")"
  echo "MaxStartups throttling: $(grep -q 'MaxStartups' <<<"$log" && echo 'YES - sshd refused connections' || echo 'no')"
  echo "Out-of-memory kills:    $(journalctl -k --since "$START" --no-pager 2>/dev/null | grep -ci 'out of memory')"
  echo "Banned by fail2ban now: $(fail2ban-client status sshd 2>/dev/null | sed -n 's/.*Banned IP list:[[:space:]]*//p')"
  echo "Samples: $OUT"
  exit 0
}
trap summary INT TERM

echo "Recording every ${INTERVAL}s to ${OUT}. Press Ctrl-C after the test for the summary."
read -r total0 idle0 < <(cpu_counters)
while true; do
  sleep "$INTERVAL"
  read -r total1 idle1 < <(cpu_counters)
  dt=$((total1 - total0)); di=$((idle1 - idle0))
  busy=$(( dt > 0 ? 100 * (dt - di) / dt : 0 ))
  total0=$total1; idle0=$idle1
  load1="$(cut -d' ' -f1 /proc/loadavg)"
  mem="$(awk '/^MemAvailable/{ print int($2 / 1024) }' /proc/meminfo)"
  swap="$(awk '/^SwapTotal/{ t = $2 } /^SwapFree/{ f = $2 } END { print int((t - f) / 1024) }' /proc/meminfo)"
  conns="$(ss -Htn state established '( sport = :22 )' 2>/dev/null | wc -l)"
  sessions="$(loginctl list-sessions --no-legend 2>/dev/null | wc -l)"
  managers="$(systemctl list-units 'user@*.service' --state=running --no-legend 2>/dev/null | wc -l)"
  sshd="$(pgrep -c sshd || true)"
  echo "$(date +%H:%M:%S),${load1},${busy},${mem},${swap},${conns},${sessions},${managers},${sshd}" >> "$OUT"
  printf "%s  load %-6s cpu %3s%%  free mem %6s MB  swap %5s MB  ssh %4s  sessions %4s\n" \
    "$(date +%H:%M:%S)" "$load1" "$busy" "$mem" "$swap" "$conns" "$sessions"
done

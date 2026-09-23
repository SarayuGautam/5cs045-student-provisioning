#!/usr/bin/env bash
# Applies the per-student resource limits:
#   - a 500 MB disk quota (covers the website, SCP/SFTP uploads and anything else the student writes)
#   - CPU, memory and process limits on everything the student runs over SSH
# PHP for the websites is limited separately, in the student's PHP pool.
# Safe to run again at any time.
#
# Usage: sudo apply-student-limits.sh [username ...]     (no names = all students)
set -euo pipefail

STUDENT_ROOT="/srv/students"
# Disk quota in 1K blocks (512000 = 500 MB). Soft == hard, so writes fail with
# "Disk quota exceeded" as soon as it is reached, with no grace period.
QUOTA_KB=512000
# At most one CPU core, 1 GB of memory and 200 processes/threads at a time.
# 200 is plenty for SSH, composer and git, and stops a fork bomb.
CPU_QUOTA="100%"
MEMORY_MAX="1G"
TASKS_MAX=200
LOG_FILE="/var/log/5cs045-provisioning.log"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG_FILE" >&2; }
[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }

if [[ $# -gt 0 ]]; then
  USERS=("$@")
else
  USERS=()
  for home in "$STUDENT_ROOT"/*/; do
    [[ -d "$home" ]] && USERS+=("$(basename "$home")")
  done
fi

# Quotas are set on the filesystem that holds the student folders (usually /), not on the folder itself.
# "quotaon -p" exits 0 whether quotas are on or off, so its message is what tells us.
QUOTA_MOUNT="$(df --output=target "$STUDENT_ROOT" 2>/dev/null | tail -1)"
QUOTAS_ON=0
QUOTA_STATE="$(quotaon -pu "$QUOTA_MOUNT" 2>/dev/null || true)"
if command -v setquota &>/dev/null && [[ "$QUOTA_STATE" == *" is on" ]]; then
  QUOTAS_ON=1
else
  log "WARNING: disk quotas are not enabled on ${STUDENT_ROOT}; students have no disk cap (see \"Resource limits\" in README.md)"
fi

applied=0
for user in "${USERS[@]}"; do
  id "$user" &>/dev/null && [[ -d "${STUDENT_ROOT}/${user}" ]] || { echo "skipped $user (no such student)"; continue; }
  uid="$(id -u "$user")"

  if [[ "$QUOTAS_ON" -eq 1 ]]; then
    setquota -u "$user" "$QUOTA_KB" "$QUOTA_KB" 0 0 "$QUOTA_MOUNT" || log "WARNING: could not set the disk quota for ${user}"
  fi

  # SSH logins run inside the user's systemd slice (user-<uid>.slice), so the limits go there.
  dropin_dir="/etc/systemd/system/user-${uid}.slice.d"
  mkdir -p "$dropin_dir"
  cat > "${dropin_dir}/50-5cs045-limits.conf" <<-EOF
	# Written by apply-student-limits.sh for ${user}. Removed by remove-student.sh.
	[Slice]
	CPUQuota=${CPU_QUOTA}
	MemoryMax=${MEMORY_MAX}
	TasksMax=${TASKS_MAX}
	EOF
  applied=$((applied + 1))
done

# One reload for the whole batch. It also applies the limits to students who are logged in right now.
if [[ "$applied" -gt 0 ]] && [[ -d /run/systemd/system ]]; then
  systemctl daemon-reload
fi
echo "Limits applied to ${applied} student(s)."

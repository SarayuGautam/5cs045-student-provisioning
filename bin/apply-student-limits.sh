#!/usr/bin/env bash
# Applies the per-student resource limits:
#   - a 500 MB disk quota, unless the admin panel set a different one (covers the website, SCP/SFTP uploads and anything else the student writes)
#   - CPU, memory and process limits on everything the student runs over SSH
#   - membership of the 5cs045-students group, which carries a backup process limit
#   - no per-user systemd manager, which only costs CPU and memory at login
# PHP for the websites is limited separately, in the student's PHP pool.
# Safe to run again at any time.
#
# Usage: sudo apply-student-limits.sh [--no-reload] [username ...]     (no names = all students)
#
# --no-reload skips "systemctl daemon-reload"; the SSH limits of students who have not logged in
# yet then only take effect after the caller's own daemon-reload.
set -euo pipefail

STUDENT_ROOT="/srv/students"
# Disk quota in 1K blocks (512000 = 500 MB). Soft == hard, so writes fail with
# "Disk quota exceeded" as soon as it is reached, with no grace period.
# A different limit for one student (set on the admin panel) is kept in
# /var/lib/5cs045-quota-overrides/<username>, as a number of 1K blocks.
QUOTA_KB=512000
QUOTA_OVERRIDE_DIR="/var/lib/5cs045-quota-overrides"
# At most one CPU core, 1 GB of memory and 200 processes/threads at a time.
# 200 is plenty for SSH, composer and git, and stops a fork bomb.
CPU_QUOTA="100%"
MEMORY_MAX="1G"
TASKS_MAX=200
# Members get a second, simpler process limit at every SSH login
# (/etc/security/limits.d/5cs045-students.conf), even if their systemd session could not be created.
STUDENT_GROUP="5cs045-students"
LOG_FILE="/var/log/5cs045-provisioning.log"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG_FILE" >&2; }
[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }

RELOAD=1
if [[ "${1:-}" == "--no-reload" ]]; then
  RELOAD=0
  shift
fi

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

getent group "$STUDENT_GROUP" >/dev/null || groupadd "$STUDENT_GROUP"

applied=0
for user in "${USERS[@]}"; do
  id "$user" &>/dev/null && [[ -d "${STUDENT_ROOT}/${user}" ]] || { echo "skipped $user (no such student)"; continue; }
  uid="$(id -u "$user")"

  if [[ " $(id -nG "$user") " != *" ${STUDENT_GROUP} "* ]]; then
    usermod -aG "$STUDENT_GROUP" "$user"
  fi

  if [[ "$QUOTAS_ON" -eq 1 ]]; then
    quota_kb="$QUOTA_KB"
    override="$(cat "${QUOTA_OVERRIDE_DIR}/${user}" 2>/dev/null || true)"
    [[ "$override" =~ ^[0-9]+$ ]] && quota_kb="$override"
    setquota -u "$user" "$quota_kb" "$quota_kb" 0 0 "$QUOTA_MOUNT" || log "WARNING: could not set the disk quota for ${user}"
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

  # No per-user systemd manager (user@<uid>.service). Nothing students do needs one, and
  # starting hundreds at once is what made mass logins time out in the load test: with 800
  # logging in, 800 managers pushed the load average past 120 and used ~10 MB each.
  # logind treats a masked user@ unit as "don't start one"; sessions and limits still work.
  ln -sfn /dev/null "/etc/systemd/system/user@${uid}.service"
  applied=$((applied + 1))
done

# One reload for the whole batch. It also applies the limits to students who are logged in right now.
if [[ "$applied" -gt 0 && "$RELOAD" -eq 1 ]] && [[ -d /run/systemd/system ]]; then
  systemctl daemon-reload
fi
echo "Limits applied to ${applied} student(s)."

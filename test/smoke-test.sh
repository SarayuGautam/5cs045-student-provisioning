#!/usr/bin/env bash
set -uo pipefail

DEPLOY_ROOT="/usr/local/sbin/5cs045"
PASS=0
FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

BASE_URL="https://localhost"
CURL=(curl -k -s)

check_code() {
  local url="$1" expected="$2" label="$3"
  local code
  code="$(curl -k -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"
  [[ "$code" == "$expected" ]] && ok "$label" || bad "$label (got HTTP $code)"
}

echo "=== setting up two throwaway test accounts ==="
OUT_A="$($DEPLOY_ROOT/bin/add-student.sh -u smoketest_a -n "Smoke Test A")"
OUT_B="$($DEPLOY_ROOT/bin/add-student.sh -u smoketest_b -n "Smoke Test B")"
PW_A="$(echo "$OUT_A" | grep '^Password:' | awk '{print $2}')"

FPM_PID_FILE="/run/php/php8.3-fpm.pid"
[[ -f "$FPM_PID_FILE" ]] && kill -USR2 "$(cat "$FPM_PID_FILE")" && sleep 1

echo ""
echo "=== password login checks ==="
if command -v sshpass >/dev/null; then
  timeout 8 sshpass -p "$PW_A" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=4 smoketest_a@localhost 'echo ok' 2>/dev/null | grep -q ok \
    && ok "generated password logs in over SSH" \
    || bad "generated password did NOT log in over SSH"
else
  echo "  SKIPPED: sshpass is not installed"
fi
mysql -u smoketest_a -p"$PW_A" -e "SELECT 1;" >/dev/null 2>&1 \
  && ok "generated password logs in to MySQL" \
  || bad "generated password did NOT log in to MySQL"

echo ""
echo "=== student isolation checks ==="
su - smoketest_a -s /bin/bash -c 'ls /srv/students/smoketest_b/' >/dev/null 2>&1 \
  && bad "A can list B's home directory" || ok "A cannot list B's home directory"
su - smoketest_a -s /bin/bash -c 'cat /var/lib/5cs045-credentials/smoketest_b' >/dev/null 2>&1 \
  && bad "A can read B's credentials" || ok "A cannot read B's credentials"
[[ ! -e /srv/students/smoketest_a/credentials.txt ]] \
  && ok "no credentials.txt in the student's home" || bad "credentials.txt is in the student's home"
su - smoketest_a -s /bin/bash -c 'echo x > /srv/students/smoketest_b/assessment/x' >/dev/null 2>&1 \
  && bad "A can write into B's assessment folder" || ok "A cannot write into B's assessment folder"
su - smoketest_a -s /bin/bash -c 'ls /srv/students/' >/dev/null 2>&1 \
  && bad "A can enumerate other student usernames" || ok "A cannot enumerate other student usernames"

echo ""
echo "=== automatic read-access checks ==="
su - smoketest_a -s /bin/bash -c 'mkdir -p /srv/students/smoketest_a/assessment/sub && echo hi > /srv/students/smoketest_a/assessment/sub/f.txt'
su -s /bin/bash www-data -c 'cat /srv/students/smoketest_a/assessment/sub/f.txt' >/dev/null 2>&1 \
  && ok "www-data can read newly-created content without chmod" \
  || bad "www-data could not read newly-created content"
su -s /bin/bash www-data -c 'echo tampered > /srv/students/smoketest_a/assessment/sub/f.txt' >/dev/null 2>&1 \
  && bad "www-data can write to student content" \
  || ok "www-data cannot write to student content"

echo ""
echo "=== PHP-FPM process isolation ==="
su - smoketest_a -s /bin/bash -c 'echo "<?php echo posix_getpwuid(posix_geteuid())[\"name\"]; ?>" > /srv/students/smoketest_a/assessment/whoami.php'
RESULT="$(curl -k -s "$BASE_URL/~smoketest_a/assessment/whoami.php" 2>/dev/null)"
[[ "$RESULT" == "smoketest_a" ]] \
  && ok "PHP for A executes as smoketest_a" \
  || bad "PHP did not execute as smoketest_a (got: '$RESULT')"
su - smoketest_a -s /bin/bash -c "cat > /srv/students/smoketest_a/assessment/attack.php" <<-'PHP'
<?php echo @file_get_contents('/srv/students/smoketest_b/assessment/index.php') === false ? 'BLOCKED' : 'LEAKED';
PHP
RESULT="$(curl -k -s "$BASE_URL/~smoketest_a/assessment/attack.php" 2>/dev/null)"
[[ "$RESULT" == "BLOCKED" ]] \
  && ok "A's PHP code cannot read B's files" \
  || bad "A's PHP code could read B's files (got: '$RESULT')"
git -C /srv/students/smoketest_a/assessment init -q 2>/dev/null
echo "[core]" > /srv/students/smoketest_a/assessment/.git/config 2>/dev/null
chown -R smoketest_a:smoketest_a /srv/students/smoketest_a/assessment/.git 2>/dev/null
check_code "$BASE_URL/~smoketest_a/assessment/.git/config" "404" ".git metadata is not servable over HTTPS"
check_code "$BASE_URL/smtp_config.php" "404" "smtp_config.php is not servable over HTTPS"


ROOT_PAGE="$(curl -k -s "$BASE_URL/~smoketest_a/" 2>/dev/null)"
[[ "$ROOT_PAGE" == *"Welcome, smoketest_a"* ]] && ok "student root URL shows the welcome page" || bad "student root URL did not show the welcome page"
FOLDER_PAGE="$(curl -k -s "$BASE_URL/~smoketest_b/workshops/" 2>/dev/null)"
[[ "$FOLDER_PAGE" == *"weekly workshop work"* ]] && ok "an empty folder shows its short description" || bad "an empty folder did not show its description"

echo ""
echo "=== resource limit checks ==="
UID_A="$(id -u smoketest_a)"
QUOTA_MOUNT="$(df --output=target /srv/students | tail -1)"
if [[ "$(quotaon -pu "$QUOTA_MOUNT" 2>/dev/null)" == *" is on" ]]; then
  QUOTA_OUT="$(quota -vu smoketest_a 2>&1)"
  [[ "$QUOTA_OUT" == *512000* ]] \
    && ok "new student has the 500 MB disk quota" || bad "new student has no disk quota"
else
  echo "  SKIPPED: disk quotas are not enabled (see \"Resource limits\" in README.md)"
fi
[[ "$(systemctl show "user-${UID_A}.slice" -p TasksMax --value 2>/dev/null)" == "200" ]] \
  && ok "new student has the SSH process limit" || bad "new student has no SSH process limit"
# Captured first rather than piped into grep: crontab exits 1 when it refuses, and with pipefail
# that failure would count against the check even though the refusal is what we want.
CRON_OUT="$(su - smoketest_a -s /bin/bash -c 'crontab -l' 2>&1)"
if ! command -v crontab >/dev/null; then
  ok "students cannot use cron (cron is not installed)"
elif [[ "$CRON_OUT" == *"not allowed"* ]]; then
  ok "students cannot use cron"
else
  bad "students can use cron (crontab said: ${CRON_OUT//$'\n'/ })"
fi
FPM_LIMIT="$(awk '/Max open files/{ print $4 }' "/proc/$(cat /run/php/php8.3-fpm.pid 2>/dev/null)/limits" 2>/dev/null)"
[[ "${FPM_LIMIT:-0}" =~ ^[0-9]+$ ]] && (( FPM_LIMIT >= 65536 )) \
  && ok "PHP can keep enough files open for 800+ student pools" \
  || bad "PHP's open-file limit is ${FPM_LIMIT:-unknown} (needs 65536; restart php8.3-fpm)"
[[ "$(sshd -T 2>/dev/null | awk '$1 == "maxstartups" { print $2 }')" == "1000:30:1500" ]] \
  && ok "sshd accepts a whole lab logging in at once" \
  || bad "sshd MaxStartups is not 1000:30:1500, so mass logins get dropped"
[[ -f /etc/dbus-1/system.d/5cs045-limits.conf ]] \
  && ok "the system bus has room for a whole class logging in at once" \
  || bad "/etc/dbus-1/system.d/5cs045-limits.conf is missing, so mass logins lose their limits"
[[ " $(id -nG smoketest_a) " == *" 5cs045-students "* ]] && [[ -f /etc/security/limits.d/5cs045-students.conf ]] \
  && ok "new student has the backup process limit" \
  || bad "new student is not in 5cs045-students, or /etc/security/limits.d/5cs045-students.conf is missing"
[[ -f /etc/cron.d/5cs045 ]] && "$DEPLOY_ROOT/bin/enforce-limits.sh" \
  && ok "the limits job is scheduled and runs cleanly" || bad "the limits job is missing or failed"

echo ""
echo "=== public registration and phpMyAdmin ==="
check_code "$BASE_URL/" "200" "registration page is public at the site root"
check_code "$BASE_URL/register.php" "301" "old /register.php URL redirects to the new site root"
check_code "$BASE_URL/phpmyadmin/" "200" "phpMyAdmin login page loads directly (no Basic Auth prompt)"

echo ""
echo "=== cleaning up test accounts ==="
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_a >/dev/null 2>&1 || true
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_b >/dev/null 2>&1 || true

echo ""
echo "============================================"
echo " ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && echo " Looks safe to provision real students." \
                     || echo " DO NOT provision real students until every FAIL above is fixed."
echo "============================================"
exit "$FAIL"

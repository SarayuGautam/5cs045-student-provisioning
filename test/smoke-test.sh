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
su - smoketest_a -s /bin/bash -c 'cat /srv/students/smoketest_b/credentials.txt' >/dev/null 2>&1 \
  && bad "A can read B's credentials" || ok "A cannot read B's credentials"
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


ROOT_CODE="$(curl -k -s -o /dev/null -w '%{http_code}' "$BASE_URL/~smoketest_a/" 2>/dev/null)"
[[ "$ROOT_CODE" == "302" ]] && ok "student root URL redirects to the assessment area" || bad "student root URL did not redirect (got HTTP $ROOT_CODE)"

echo ""
echo "=== public registration and admin protection ==="
check_code "$BASE_URL/register.php" "200" "registration page is public"
check_code "$BASE_URL/phpmyadmin/" "401" "phpMyAdmin still requires its Basic Auth login"
if [[ "$(stat -c '%a' /etc/nginx/.htpasswd-admin 2>/dev/null || echo missing)" == "640" ]]; then
  ok "phpMyAdmin password file is mode 640"
else
  bad "phpMyAdmin password file is not mode 640"
fi

echo ""
echo "=== cleaning up test accounts ==="
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_a --no-backup >/dev/null 2>&1 || true
"$DEPLOY_ROOT/bin/remove-student.sh" -u smoketest_b --no-backup >/dev/null 2>&1 || true

echo ""
echo "============================================"
echo " ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && echo " Looks safe to provision real students." \
                     || echo " DO NOT provision real students until every FAIL above is fixed."
echo "============================================"
exit "$FAIL"
